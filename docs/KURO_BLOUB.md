# Kuro / native Flutter integration

YomiBloubCompanion paints vectors directly with CustomPainter. There is no embedded website or video. Its shared 2.5 MB atlas is generated from the Bloub engine at 24 samples/sec; adjacent vector poses and state transitions are interpolated on the display clock. Idle shapes/expressions are cached as independent poses with native blinking. Procedural ring geometry preserves front/back occlusion. Some non-circular decorative dots are simplified as circles.

The atlas is loaded once, decoded off the UI isolate and shared by instances. Animation pauses with OS reduced motion, battery saving, app background, TickerMode and offscreen scrolling. Small avatars stay static. Profile appearance preferences and backup fields are mapped at the rendering boundary without modifying saved data.

Home welcomes the reader, library is curious, profile has an orbit entrance, reader controls remain discreet, and the existing end-of-chapter footer celebrates before returning to rest. The contextual controller uses active animation time and spacing between gestures, avoiding continuously repeated celebrations.

## Rebuild vectors

With Node 24+, run `node tool/bloub/bake.cjs`. All required upstream sources and the MIT license are included. Keep source easing/profile changes synchronized with the web integration, then regenerate this atlas. This is sampled vector playback rather than a full Dart port of every interactive engine input; live pointer-driven gaze is currently web-only. Before release, validate on a physical entry-level Android device.

## Upstream and license

Source is based on jeremy-prt/bloub commit b4bb3c1b5f93c7b87a2e8d620f667c4093d97749, under MIT (LICENSE.bloub is preserved beside the motor). Engine easing and the renderer are Yomi adaptations. The original README states that MIT covers its code, not the x.ai design it imitates. This integration does not establish exclusive rights to that design.

## Seasonal events and wardrobe

The default shape is `cercle`; explicit saved shape choices are preserved. Equipment has four independent slots: aura, scarf, hat and floating object. The eight initial items are Aurora, Little Star, Winter Scarf, Santa Hat, Witch Hat, Pumpkin Orb, Golden Aura and Tiny Book. Empty strings unequip slots. Hat/scarf anchors follow the actual transformed contour; aura and floating objects share its center and scale. State policy interpolates accessory opacity through the same interrupted-transition machinery as the body. Stable poses restore accessories; orbit, swirl, burst, comet, play, alert and exclaim hide them smoothly. Reduced-motion contextual playback settles on visible idle.

Calendar uses a fixed UTC-03 product clock, inclusive start and exclusive end: Christmas December 1–January 1; Halloween October 15–November 1; New Year December 28–January 8; Book Week April 18–25. New Year wins the overlapping visual theme, while both reward windows remain claimable. Aurora and Little Star are always claimable. Calendar changes seasonal accents automatically; equipping items remains a user choice and does not expire with the event.

The web `/guarda-roupa` and native profile wardrobe support claims, combination and unequipping. Preview mode offers all items and a seasonal override without persisting anything. The override changes presentation only: production claims always use the server clock.

Both clients share Firebase Auth UID and these Firestore documents:

- `kuroUsers/{uid}/items/{itemId}`: immutable `{itemId, claimedAt}` grants, created with a server timestamp in a read-before-create transaction. Repeated claims are no-ops.
- `kuroUsers/{uid}/state/equipment`: four slot strings and `updatedAt`, validated against owned grants and category membership.

Ownership is separate from editable profile backups. One shared account subscription feeds the mascots; pending local writes are ignored until acknowledged. Account changes immediately clear visible equipment and invalidate old callbacks. Native offline cache is UID-scoped in its own Hive box; it cannot authorize server grants. Other commenters do not inherit the signed-in user's clothes.

Catalog source: web `src/lib/kuro/catalog.json`, mirrored into the renderer's `cosmetic-catalog.ts` and native `assets/mascot/cosmetics.json`. Adding items requires keeping these mirrors, renderer designs and Firestore allowlists/windows aligned. For engine changes, synchronize web and native TypeScript sources and regenerate the native atlas with `node tool/bloub/bake.cjs`.

### Release requirement

The authoritative rules are in the web repository's `firestore.rules`. Deploy those rules to the shared Firebase project before releasing claim/equip UI; the old rules do not enable the new collection. The production rules were deployed and read back for verification on 2026-11-17. Existing backup/comment permissions were preserved; no real user inventory was modified during testing. This uses existing Firebase services without paid animation tools or Cloud Functions; normal Firebase project quotas still apply.

### Verification

Web: 75 unit/regression tests, production compilation and browser checks of all four slots, combinations, interrupted fade, mobile layout, reduced motion and preview isolation. Native: 185 tests, including catalog boundaries, ownership/category validation, customized anchors and rendering with four slots. Firestore emulator checks account isolation, immutable claims, seasonal boundaries, duplicate transactions, forged backup ownership and permanent out-of-season equipment. Run isolated rule tests using the web `tests/firestore/README.md`; never deploy its test-only calendar endpoint. Real-account cross-device synchronization and a physical entry-level Android benchmark remain release checks.


## Shape persistence audit — revision 03

All 15 states now preserve the selected 64-sample radial profile. State profiles from the original video are motion references only; they do not replace the character with a circle, triangle, glyph or dot. Pose rotation/translation and bounded (0.92–1.08) squash/stretch remain available. Each transition blends corresponding vertices. The eye fitting table uses this same personalized geometry.

Changing shape midway through a morph snapshots the displayed radii and eye correction instead of restarting from the previous target. CyclePlayer uses monotonic absolute time and blended restart at block boundaries, including repeated blocks and wraps; reset is reserved for explicit seeking. No cycle or contextual return clears the selected shape.

The Flutter atlas v2 stores state motion separately from catalog profiles. Native playback reconstructs each contour from the selected profile and interpolated pose, and fits eyes to that profile. A shape change keeps the current action clock and blends from the currently drawn frame. This avoids a separate large animation atlas per shape. The generated asset is approximately 2.5 MB.

Regression coverage: eight shapes across fifteen states and multiple internal timestamps; every pair of state transitions and both sides of the blend cutoff; interrupted shape changes; cycle wraps/repeated blocks; native selected-shape differentiation and widget transitions.
