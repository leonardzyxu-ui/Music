# Music 0.1.7

This update adds Music package sharing, automatic legacy-library migration, clearer update badges, and playback resume fixes. It is still not Developer ID signed or notarized.

## What's New

- Music now stores shared/synced songs as dense binary `.musicpkg` files instead of loose MP3/M4A/AAC/WAV files.
- Legacy loose-audio libraries are packaged automatically by the updated app and moved to a local backup after package verification.
- YouTube Import now stages downloaded audio outside the active library, wraps it into `.musicpkg`, and keeps the active package folder clean.
- Users can import `.musicpkg` files and export a song as a package from the song context menu.
- Settings shows a red update badge when a newer version is available, including the latest version and a short release summary.
- Automatic update checks remain on by default; Music checks its badge feed every 30 minutes while open and Sparkle checks every 6 hours.
- Music remembers each song's playback position across relaunches, saves only on song switch or app close, and resets the position when the song finishes.
- Song selection is limited to one song so album or queue playback does not accumulate selected rows.
- Dock and Stage Manager now use the full rounded-square waveform app icon instead of a floating transparent waveform glyph.
- YouTube Import no longer asks yt-dlp for remote JavaScript components unless an app-managed Deno runtime is available, and JavaScript-runtime/helper-timeout failures now show Music-safe recovery text instead of raw helper output.

## Notes

- Music keeps playback and library data local to the user's Mac.
- Users should import only audio they have rights or permission to save.
- `.musicpkg` wraps the existing compressed audio bytes by default; it does not reduce audio quality through normal migration.
- This is a local development distribution build for Leo's rollout testing.
