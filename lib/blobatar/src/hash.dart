/// Seed hashing.
///
/// Dart port of `packages/blobatar/src/hash.ts` at blobatar 2.4.0. Two
/// guarantees this file exists to provide:
///
/// 1. Avalanche — "alain" and "alaim" must produce visually unrelated
///    blobatars. Plain FNV-1a does not give you this; the murmur3 finalizer
///    does.
/// 2. Streaming — the seed is hashed once, then each trait key continues from
///    that state. Trait values are therefore independent of one another, so
///    adding a trait in a later version cannot disturb existing blobatars.
///
/// The JavaScript uint32 semantics (multiplication overflow, signed shifts,
/// the `[0, 1)` stream range) are reproduced exactly; see [imul] and
/// [toInt32].
library;

import 'dart:convert';

const int _sep = 0xff;

String _nfc(String input) {
  if (!input.runes.any((r) => r >= 0x0300 && r <= 0x036F)) return input;
  const Map<int, Map<int, int>> composed = {
    0x0300: {0x41: 0xC0, 0x45: 0xC8, 0x49: 0xCC, 0x4F: 0xD2, 0x55: 0xD9, 0x61: 0xE0, 0x65: 0xE8, 0x69: 0xEC, 0x6F: 0xF2, 0x75: 0xF9},
    0x0301: {0x41: 0xC1, 0x45: 0xC9, 0x49: 0xCD, 0x4F: 0xD3, 0x55: 0xDA, 0x59: 0xDD, 0x61: 0xE1, 0x65: 0xE9, 0x69: 0xED, 0x6F: 0xF3, 0x75: 0xFA, 0x79: 0xFD, 0x43: 0x0106, 0x63: 0x0107},
    0x0302: {0x41: 0xC2, 0x45: 0xCA, 0x49: 0xCE, 0x4F: 0xD4, 0x55: 0xDB, 0x61: 0xE2, 0x65: 0xEA, 0x69: 0xEE, 0x6F: 0xF4, 0x75: 0xFB},
    0x0303: {0x41: 0xC3, 0x4E: 0xD1, 0x4F: 0xD5, 0x61: 0xE3, 0x6E: 0xF1, 0x6F: 0xF5},
    0x0308: {0x41: 0xC4, 0x45: 0xCB, 0x49: 0xCF, 0x4F: 0xD6, 0x55: 0xDC, 0x61: 0xE4, 0x65: 0xEB, 0x69: 0xEF, 0x6F: 0xF6, 0x75: 0xFC, 0x79: 0xFF},
    0x0327: {0x43: 0xC7, 0x63: 0xE7},
  };
  final runes = input.runes.toList();
  final out = <int>[];
  for (final r in runes) {
    final map = composed[r];
    if (map != null && out.isNotEmpty && map.containsKey(out.last)) {
      out[out.length - 1] = map[out.last]!;
    } else {
      out.add(r);
    }
  }
  return String.fromCharCodes(out);
}

/// JavaScript `Math.imul` — 32-bit integer multiplication, returned as a
/// signed int32.
///
/// Written with 16-bit decomposition rather than relying on `(a * b) &
/// 0xFFFFFFFF`: the direct form wraps correctly on the Dart VM (64-bit
/// two's-complement ints) but silently loses precision when compiled to
/// JavaScript, where ints are doubles.
int imul(int a, int b) {
  final int x = a & 0xFFFFFFFF;
  final int y = b & 0xFFFFFFFF;
  final int xl = x & 0xFFFF;
  final int xh = x >> 16;
  final int yl = y & 0xFFFF;
  final int yh = y >> 16;
  // x*y mod 2^32 = xl*yl + ((xl*yh + xh*yl) & 0xFFFF) << 16, with xh*yh
  // contributing only at bit 32 and above.
  final int low =
      (xl * yl + (((xl * yh + xh * yl) & 0xFFFF) << 16)) & 0xFFFFFFFF;
  return low >= 0x80000000 ? low - 0x100000000 : low;
}

/// JavaScript's `| 0` view of an int: the low 32 bits, signed.
int toInt32(int v) {
  final int low = v & 0xFFFFFFFF;
  return low >= 0x80000000 ? low - 0x100000000 : low;
}

/// JS `h >>> n` — a logical shift of the 32-bit pattern, zero-filling.
int _shr32(int h, int n) => (h & 0xFFFFFFFF) >>> n;

/// Mixes bytes into a 32-bit state.
int _feed(int h, List<int> bytes) {
  for (final int byte in bytes) {
    h = imul(h ^ byte, 3432918353);
    h = toInt32((h << 13) | _shr32(h, 19));
  }
  return h;
}

/// murmur3 fmix32 — a bijection on uint32 with full avalanche.
int _finalize(int h) {
  h = imul(h ^ _shr32(h, 16), 2246822507);
  h = imul(h ^ _shr32(h, 13), 3266489909);
  return (h ^ _shr32(h, 16)) & 0xFFFFFFFF;
}

/// Normalizes a seed so that inputs a human considers equal hash equally.
///
/// NFC first, so precomposed "é" and decomposed "é" agree; then trim, then
/// lowercase. Without this, `Alain@x.com` and `alain@x.com` produce different
/// blobatars for the same person — which gets reported as a bug, every time.
String normalizeSeed(String seed) => _jsToLower(_nfc(seed).trim());

/// JS `String.prototype.toLowerCase` on top of Dart's.
///
/// Dart lowercases with the Unicode *simple* mapping. JavaScript uses the
/// *full* mapping, which differs in two unconditional places, and the
/// paste-a-name case can hit the first:
///
/// - U+0130 LATIN CAPITAL LETTER I WITH DOT ABOVE lowercases to `i` plus a
///   combining dot, not to bare `i`.
/// - A capital sigma takes its word-final form `ς` when it is preceded by a
///   cased letter and no cased letter follows (the Final_Sigma context,
///   skipping case-ignorable combining marks). Word-initial and isolated
///   sigmas keep the plain `σ`.
///
/// The Final_Sigma "cased letter" and "case-ignorable" tests use explicit
/// ranges for the scripts that appear in real names (Latin, Greek, Cyrillic,
/// Latin-extended) and the common combining-mark block, not the full Unicode
/// properties. The reference vectors pin the cases that matter.
///
/// **Documented deviation:** the final `.toLowerCase()` delegates to Dart's
/// simple mapping, which is generated from an older Unicode data version than
/// current JavaScript engines. Uppercase letters whose lowercase pairs were
/// added in later Unicode releases (for example Georgian Mtavruli U+1C90,
/// Adlam, Deseret, Warang Citi, Medefaidrin) keep their uppercase form here
/// and hash differently from the JS core. `test/traits_test.dart` records the
/// boundary. Re-check when Dart's Unicode data advances.
String _jsToLower(String s) {
  var needsWork = false;
  for (final int u in s.codeUnits) {
    if (u == 0x0130 || u == 0x03A3) {
      needsWork = true;
      break;
    }
  }
  if (!needsWork) return s.toLowerCase();

  final units = s.codeUnits;
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final int u = units[i];
    if (u == 0x0130) {
      out.write('i\u0307');
    } else if (u == 0x03A3 &&
        _precededByCased(units, i) &&
        !_followedByCased(units, i)) {
      out.write('\u03C2');
    } else {
      out.writeCharCode(u);
    }
  }
  return out.toString().toLowerCase();
}

bool _precededByCased(List<int> units, int i) {
  for (var j = i - 1; j >= 0; j--) {
    final int u = units[j];
    if (_isCased(u)) return true;
    if (!_isCaseIgnorable(u)) return false;
  }
  return false;
}

bool _followedByCased(List<int> units, int i) {
  for (var j = i + 1; j < units.length; j++) {
    final int u = units[j];
    if (_isCased(u)) return true;
    // Approximate case-ignorable: combining marks are skipped; anything else
    // terminates the context.
    if (!_isCaseIgnorable(u)) return false;
  }
  return false;
}

/// Approximates Unicode's Case_Ignorable: combining marks plus a couple of
/// common format characters that glue names together.
bool _isCaseIgnorable(int u) =>
    (u >= 0x0300 && u <= 0x036F) || u == 0x00AD || u == 0x200B;

bool _isCased(int u) =>
    (u >= 0x41 && u <= 0x5A) ||
    (u >= 0x61 && u <= 0x7A) ||
    (u >= 0xC0 && u <= 0x24F && u != 0xD7 && u != 0xF7) ||
    (u >= 0x370 && u <= 0x3FF) ||
    (u >= 0x400 && u <= 0x4FF) ||
    (u >= 0x1E00 && u <= 0x1FFF);

/// Hashes the seed once into a reusable state. Non-ASCII seeds are encoded to
/// UTF-8 bytes first, so hashing is over codepoints rather than UTF-16 units
/// (surrogate pairs would otherwise hash inconsistently across engines).
int seedState(String seed, {bool normalize = true}) {
  final String s = normalize ? normalizeSeed(seed) : seed;
  return _feed(1779033703 ^ s.length, utf8.encode(s));
}

/// Derives one uniform float in [0, 1) for `key`, independent of every other
/// key.
double stream(int state, String key) =>
    _finalize(_feed(_feed(state, [_sep]), utf8.encode(key))) / 4294967296;
