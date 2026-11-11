/// The ten-shape vocabulary introduced by Blobatar 2.
///
/// Dart port of `packages/blobatar/src/styles/blob.ts` at blobatar 2.4.0.
///
/// Weighted rather than uniform: round and organic are the everyday shapes,
/// while the louder silhouettes stay finds. These bands, the layout ranges in
/// `compose.dart`, and the tone set together form gen2's frozen seed-to-look
/// mapping.
library;

import 'compose.dart';
import 'shapes.dart';

/// The band table. The thresholds are part of the frozen contract.
const List<Band> bands = [
  (round, 0.22),
  (organic, 0.48),
  (boxy, 0.6),
  (capsule, 0.7),
  (nub, 0.79),
  (cloud, 0.86),
  (droplet, 0.915),
  (hexagon, 0.95),
  (sun, 0.98),
  (triangle, 1.0),
];

/// Blobatar 2's composed style.
const BlobatarStyle style = BlobatarStyle(bands, faceFit);
