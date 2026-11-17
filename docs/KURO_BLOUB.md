# Kuro / native Flutter integration

YomiBloubCompanion paints vectors directly with CustomPainter. There is no embedded website or video. Its shared 2.3 MB atlas is generated from the Bloub engine at 24 samples/sec; adjacent vector poses and state transitions are interpolated on the display clock. Idle shapes/expressions are cached as independent poses with native blinking. Procedural ring geometry preserves front/back occlusion. Some non-circular decorative dots are simplified as circles.

The atlas is loaded once, decoded off the UI isolate and shared by instances. Animation pauses with OS reduced motion, battery saving, app background, TickerMode and offscreen scrolling. Small avatars stay static. Profile appearance preferences and backup fields are mapped at the rendering boundary without modifying saved data.

Home welcomes the reader, library is curious, profile has an orbit entrance, reader controls remain discreet, and the existing end-of-chapter footer celebrates before returning to rest. The contextual controller uses active animation time and spacing between gestures, avoiding continuously repeated celebrations.

## Rebuild vectors

With Node 24+, run `node tool/bloub/bake.cjs`. All required upstream sources and the MIT license are included. Keep source easing/profile changes synchronized with the web integration, then regenerate this atlas. This is sampled vector playback rather than a full Dart port of every interactive engine input; live pointer-driven gaze is currently web-only. Before release, validate on a physical entry-level Android device.

## Upstream and license

Source is based on jeremy-prt/bloub commit b4bb3c1b5f93c7b87a2e8d620f667c4093d97749, under MIT (LICENSE.bloub is preserved beside the motor). Engine easing and the renderer are Yomi adaptations. The original README states that MIT covers its code, not the x.ai design it imitates. This integration does not establish exclusive rights to that design.

## Seasonal extension, later

Use independent layers: atmosphere behind the mascot; body palette; head/hand accessories; foreground effects. Keep the inventory and calendar outside the animation motor. Equip an item only after the account owns it, and keep ownership when an event ends.

Start with aura colors, a scarf and a small floating star. A hat should attach to a stable head anchor during idle/wink; when a state turns the entire body into a comet or symbol, fade the hat out and restore it after the morph. Avoid stretching garments across those silhouettes. Calendar activation changes decoration automatically, while equipment remains the user's choice. Seasonal particles remain outside the chapter artwork.



## Shape persistence audit — revision 03

All 15 states now preserve the selected 64-sample radial profile. State profiles from the original video are motion references only; they do not replace the character with a circle, triangle, glyph or dot. Pose rotation/translation and bounded (0.92–1.08) squash/stretch remain available. Each transition blends corresponding vertices. The eye fitting table uses this same personalized geometry.

Changing shape midway through a morph snapshots the displayed radii and eye correction instead of restarting from the previous target. CyclePlayer uses monotonic absolute time and blended restart at block boundaries, including repeated blocks and wraps; reset is reserved for explicit seeking. No cycle or contextual return clears the selected shape.

The Flutter atlas v2 stores state motion separately from catalog profiles. Native playback reconstructs each contour from the selected profile and interpolated pose, and fits eyes to that profile. A shape change keeps the current action clock and blends from the currently drawn frame. This avoids a separate large animation atlas per shape. The generated asset is approximately 2.5 MB.

Regression coverage: eight shapes across fifteen states and multiple internal timestamps; every pair of state transitions and both sides of the blend cutoff; interrupted shape changes; cycle wraps/repeated blocks; native selected-shape differentiation and widget transitions.
