# Music Feature Queue

This file is the parking lot for Leo's sudden ideas and requested changes.
When Leo says something like "btw could you add this feature", record it here
instead of interrupting the current task or trusting memory.

## Active

- Redesign YouTube Import as a guided step flow:
  1. Search for a song/video.
  2. Show thumbnail candidate rows and select one.
  3. Click Next to slide to a download/progress screen with one long bar and current helper stage.
  4. Click Next after download finishes to review artwork and edit the song name.
  5. Confirm, return to All Songs, select/reveal the imported song, and cue it in the play bar paused at the start.

## Parked Ideas

- Add manual `Your Pick` refresh.
- Automatically refresh `Your Pick` after 30 minutes of inactivity, meaning no song is playing.
- Replace typewriter/monospaced-looking duration numbers with SF Pro-style numerals.
- Add a Recycle Bin for deleted songs and expose it from the menu/sidebar later.
- Lower the current-song artwork in the now-playing bar slightly so it does not touch the top edge.
- Move the YouTube/original-video icon to the left side of song rows so duration/play columns line up for songs with and without source metadata.
- Now-playing bar right-side controls need an audit: delete controls that cannot work, and turn the remaining ones into real buttons.
- Give now-playing bar buttons a full circular hit area instead of requiring the cursor to land exactly on the symbol.
- Give sidebar menu rows larger click patches so the whole row area responds immediately, not only the label/icon.
- Make the now-playing `...` button open the same actions as a song row secondary-click menu.
- When nothing is playing, replace the sad `Not Playing / Choose a song` center text with a half-transparent Music logo, dim unavailable left transport controls, and make player buttons slightly larger like Apple Music.
- Enforce a real minimum Music window size at the Figure One boundary: do not allow horizontal or vertical resizing that hides song metadata, shrinks/removes player controls, crops the play bar, leaves only the sidebar, or collapses down to traffic lights. The app should preserve the accepted full UI with no broken squish states.

## Completed

- Add an explicit persistent queue file for Leo's sudden ideas and non-interrupting feature requests.
