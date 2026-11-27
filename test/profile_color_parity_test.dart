import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuro_reader/models/manga_models.dart';
import 'package:kuro_reader/services/profile_palette_service.dart';

void main() {
  test('a cor manual preserva grafite, vermelho e azul sem remapeamento', () {
    for (final argb in [0xff9893aa, 0xffff0000, 0xff0954c8]) {
      final profile = UserProfile(customAccentColor: argb);
      expect(ProfilePaletteService.synchronousFallbackFor(profile).primary, Color(argb));
    }
  });

  test('a semente tem o mesmo resultado do leitor web', () {
    expect(const UserProfile(blobatarSeed: 'Kuro').seedHue, 327);
    expect(const UserProfile(name: 'Kuro').seedHue, 327);
  });
}
