# Music 0.1.2

This update prepares Music for signed Sparkle updates and improves the app
settings experience.

## What's New

- Added Sparkle update support with automatic checks and a manual update path in
  Settings.
- Added a Settings update status indicator so users can see when a newer build is
  available.
- Improved the Settings window with clearer sections, readable paths, and a
  dedicated Updates pane.
- Fixed the pre-rollout update state so builds without update credentials show a
  clear setup-required message instead of a disabled update button.
- Hardened release validation so packaged builds must include Sparkle, the
  expected appcast URL, automatic update checks, and a valid public update key.
- Improved update packaging so signed appcasts and update archives can be
  published to GitHub Pages.

## Notes

- YouTube import still depends on helper tools being available on the Mac.
- Music keeps playback and library data local to the user's Mac.
