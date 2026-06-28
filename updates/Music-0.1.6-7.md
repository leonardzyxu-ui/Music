# Music 0.1.6

This update collects the newest fixes since the last Sparkle rollout and keeps the app visually consistent in Light Mode environments. It is still not Developer ID signed or notarized.

## What's New

- Music now forces its main window, settings window, sidebar, and system-backed controls into Dark Aqua so macOS Light Mode cannot turn the sidebar gray.
- YouTube Import now ships with bundled yt-dlp and ffmpeg helpers inside Music.app, so clean Macs no longer need Python, pip, Homebrew, or Xcode command-line helper paths.
- Settings and YouTube Import use the same helper resolver, so the helper path shown in Settings matches the path used during imports.
- Old app-managed Python yt-dlp wrappers are detected as repair-needed instead of being treated as working helpers.
- The public DMG now carries the same helper-bundled app that Sparkle can deliver through the update feed.
- The Music website hero animation now waits for the hero image to decode before starting, so the full three-second animation is visible.

## Notes

- Music keeps playback and library data local to the user's Mac.
- Users should import only audio they have rights or permission to save.
- This is a local development distribution build for Leo's rollout testing.
