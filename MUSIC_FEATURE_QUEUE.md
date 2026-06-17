# Music Feature Queue

This file is the parking lot for Leo's sudden ideas and requested changes.
When Leo says something like "btw could you add this feature", record it here
instead of interrupting the current task or trusting memory.

## Active

- Add Apple Music-style song focus mode: hovering current song artwork shows a darkened artwork overlay with an expand arrow, clicking opens a full-window song-only view with album-color blur, close and compact-player glass controls, no lyrics panel, and playback controls.
- Add Apple Music-style compact player mode from song focus: shrink the whole Music window into a small rounded player with artwork/title/progress/transport controls, and reveal secondary controls on hover.

## Parked Ideas

- None.

## Completed

- Add an explicit persistent queue file for Leo's sudden ideas and non-interrupting feature requests.
- Redesign YouTube Import as a guided step flow: search/select, download progress, review/rename, confirm, return to All Songs, select the imported song, and cue it paused at the start.
- Add manual `Your Pick` refresh.
- Automatically refresh `Your Pick` after 30 minutes of inactivity, meaning no song is playing.
- Replace typewriter/monospaced-looking duration numbers with SF Pro-style numerals.
- Add a Recycle Bin for deleted songs and expose it from the menu/sidebar.
- Lower now-playing artwork/logo/text in the play bar so it does not kiss the top edge.
- Move the YouTube/original-video icon into a fixed column between song info and `All Songs` so duration/play columns line up.
- Audit now-playing bar right-side controls: remove non-working controls and turn the remaining ones into real controls.
- Give now-playing bar buttons a full circular hit area instead of requiring the cursor to land exactly on the symbol.
- Give sidebar menu rows larger click patches so the whole row area responds immediately, not only the label/icon.
- Make the now-playing `...` button open the same core actions as a song row secondary-click menu.
- When nothing is playing, replace the `Not Playing / Choose a song` center text with a half-transparent Music logo, dim unavailable left transport controls, and make player buttons slightly larger like Apple Music.
- Enforce a real minimum Music window size at the Figure One boundary so resizing cannot collapse the UI into broken squish states.
- In YouTube Import, make `Back` use the same pill/capsule shape as `Next`, but keep it dark/neutral instead of red.
- In YouTube Import, make Back navigation slide opposite to Next navigation.
- Change the sidebar YouTube symbol to a video icon instead of an import/download icon.
- Make selected sidebar rows look like Apple Music: rounded background behind the full row, wider click area, and red selected text.
- Add a way to remove a song from `Your Pick` by demoting it below the current Your Pick cutoff so the next-ranked song rises.
- Restyle the New Playlist dialog as one large Liquid Glass block, removing the old gray-to-black gradient look.
- Restyle New Playlist text input as a Liquid Glass capsule with two semicircle ends.
- Restyle the YouTube Import panels to avoid the old gray-to-black gradient panel; use cleaner Liquid Glass.
- Fix New Playlist modal presentation/dismissal jitter by avoiding the background blur transform that caused the app content to jolt.
- Define shared button terminology: Window Traffic Lights, Icon-Only Controls, Sidebar Navigation Rows, Capsule Action Buttons, and Context Menu Items.
- Make selected/current song contents turn red without turning the whole row into a full-width red banner.
- Make `Move to Group` from `Your Pick` actually remove/demote the song from Your Pick after moving it.
- Fix the repeat/loop button overlapping the hover scrubber area by giving the transport controls more room and shortening the center scrubber budget.
- Make both shuffle/repeat loop buttons larger and easier to see.
- Make all left-side now-playing transport buttons pure white when a song is selected, and gray all of them out when no song is selected.
- Restyle regular non-Play-Bar action buttons as capsule/semicircle-ended buttons instead of rounded rectangles.
- Add subtle Liquid Glass lighting to regular app buttons, inspired by the App Store `Get` button, while keeping neutral buttons black-ish and primary buttons red.
- Make YouTube URL input fields true semicircle/capsule rounded, not rounded rectangles.
- Use native `.borderedProminent` Capsule Action Buttons with capsule border shape and tint instead of hand-painted gradients.
- Restore primary-only red Capsule Action Button lighting because native `.borderedProminent` tint rendered too flat, while keeping neutral capsule buttons flat/native.
- Keep selected/current song row separators visible and tint the selected row's top and bottom separators red.
- Reduce sidebar navigation perceived lag by selecting rows on mouse-down instead of waiting for mouse-up.
- Make right-side now-playing Icon-Only Controls match the larger visual size and hit area of the left-side loop/shuffle/repeat controls.
- Incorporate neutral real tint/material-lighting into the Play Bar without using song artwork colors.
- When shuffle/repeat/loop modes are active from any loop button, tint the active loop control red so the state is obvious.
- Move the left and right loop controls closer to the three-button transport cluster, roughly halving the gap on each side, while preserving the relative spacing among previous/play/next.
- Remove the small chevron marks next to the now-playing ellipsis and list buttons.
- Fix the now-playing ellipsis menu's `Move to Group` submenu flickering by flattening move targets into the main menu section.
