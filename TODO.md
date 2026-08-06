# TODO — Fix blurred image clarity after sending

## Steps
- [x] 1. `image_codec_util.dart`: use high-quality `Interpolation.average` when downscaling in `copyResize` calls (both mesh + internet paths).
- [x] 2. `message_bubble.dart`: add `FilterQuality.high` to `Image.memory` rendering.
- [x] 3. `image_viewer_screen.dart`: add `FilterQuality.high` to full-screen viewer.
- [x] 4. Run `flutter analyze` + `flutter test` in `apps/mobile` to verify no regressions.

## Validation
- ✅ `flutter analyze` → **No issues found!**
- ✅ `flutter test` → **All tests passed!**
