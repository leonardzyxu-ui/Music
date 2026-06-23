# Music Website

Local preview:

```sh
python3 -m http.server 5173 --directory website
```

Open:

```text
http://127.0.0.1:5173/
```

QA screenshots live in `website/qa/`. The `?capture=player`, `?capture=import`,
`?capture=focus`, and `?capture=jarvis` query modes are only for deterministic
section screenshots.

Local DMG download artifacts live in `website/downloads/` after the release
checks sync them from `dist/`. Both `website/qa/` and `website/downloads/` are
local generated outputs and should stay out of source control until a separate
public hosting decision is made.
