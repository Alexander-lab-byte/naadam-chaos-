# Naadam Chaos — web build

This folder is the **3D Godot game exported for the browser**. Vercel serves it at
https://naadam-chaos.vercel.app (see `vercel.json` in the repo root: `outputDirectory = web`).

Do not edit these files by hand. They are made by Godot.

## Update the website

1. In Godot: **Project → Export… → Web → Export Project**, save as `web/index.html`
   (the preset is already in `export_presets.cfg`).
   First time only: Godot asks to download **export templates** (Editor → Manage Export Templates).
2. Commit and push. Vercel updates the site by itself in about a minute.

## Notes

- Web uses Godot's **Compatibility** renderer (WebGL 2). Forward+ effects like SSAO are off in the browser.
- Single-threaded export (`thread_support = false`), so no special server headers are needed.
- `.gdignore` stops Godot from importing these files back into the project.
- Works best in Chrome or Safari on a laptop. Phones can be slow, and there are no touch buttons yet.
