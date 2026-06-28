# Music 0.1.5

This is a local development build for the Sparkle rollout test. It is still not Developer ID signed or notarized, but it fixes the clean-Mac YouTube helper path that showed up after the first successful update.

## What's New

- Clean first-run library setup remains intact for new installs.
- Rights-aware YouTube import now uses one shared helper resolver for Settings
  and Import.
- Music can install app-managed yt-dlp and ffmpeg helpers into Application
  Support without requiring Python, pip, Homebrew, or Xcode command-line paths.
- Old app-managed Python yt-dlp wrappers are detected as repair-needed instead
  of being treated as a working import helper.
- Jarvis bridge behavior is unchanged.

## Notes

- Music keeps playback and library data local to the user's Mac.
- Users should import only audio they have rights or permission to save.
