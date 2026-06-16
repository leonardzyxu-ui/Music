# Music UI Protected Areas

These areas are already-good UI surfaces and should not be changed while fixing the window corner/chrome bug unless a direct dependency is proven:

- `Sources/JarvisMusic/Views/NowPlayingBar.swift`: protect the liquid-glass floating now-playing bar, capsule/semicircle ends, control layout, hover behavior, progress placement, thickness, right margin, and no-large-volume-slider behavior.
- `Sources/JarvisMusic/Views/SongListView.swift`: protect the Apple Music-like list, row artwork, row spacing, separators, title/artist layout, and row play buttons.
- `Sources/JarvisMusic/Views/YouTubeImportView.swift`: protect the polished native import/search/results UI and candidate thumbnail behavior. Do not restore a normal YouTube website/browser as the default import flow.
- `Sources/JarvisMusic/Support/MusicPalette.swift`: protect the current space-black and Apple Music dark palette unless the window fix requires a narrow color correction.
- `Sources/JarvisMusic/Support/MusicTypography.swift`: protect SF/system typography choices and weights.
- `Sources/JarvisMusic/Views/SidebarView.swift`: protect white normal sidebar text, red selected text/icon/count state, and full-row click targets. Only adjust sidebar layout if required for the window-corner geometry.
- `Sources/JarvisMusic/Views/ContentView.swift`: protect the overall Apple Music layout, top-right search placement, and bottom floating player overlay. Only change root/sidebar/window hit-test layout when required for the corner fix or tab redraw fix.
- Library, playback, bridge, import, and metadata service code: protect all service behavior and music-library file handling unless a test exposes a direct dependency for this window bug.
