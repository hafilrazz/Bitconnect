# TODO — Fix blurred image clarity after sending

## Steps
- [x] 1. `image_codec_util.dart`: use high-quality `Interpolation.average` when downscaling in `copyResize` calls (both mesh + internet paths).
- [x] 2. `message_bubble.dart`: add `FilterQuality.high` to `Image.memory` rendering.
- [x] 3. `image_viewer_screen.dart`: add `FilterQuality.high` to full-screen viewer.
- [x] 4. Run `flutter analyze` in `apps/mobile` — passed. Only 1 pre-existing info-level lint (mesh_controller.dart:407, unrelated to image changes). Edited files have no errors/warnings.
- [x] 5. Run `flutter test` in `apps/mobile` — All tests passed.
- [x] 6. Verified final state of all edited files (image_codec_util.dart, message_bubble.dart, image_viewer_screen.dart) — changes correct. Runtime device test recommended for visual confirmation.
