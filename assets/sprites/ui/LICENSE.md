# UI skin textures

The 9-slice frame textures in this directory (`panel.png`, `button_*.png`) are
baked from the **Kenney Fantasy UI Borders** pack, released under **CC0
(Creative Commons Zero v1.0 Universal)** — free for commercial and
non-commercial use, no attribution required (credited here with gratitude).

Source: https://kenney.nl/assets/fantasy-ui-borders

The white silhouette panels are composited into two-tone framed textures
(dark-purple fill + parchment/gold border ring, colours mirroring
`theme/dark_fantasy.tres`) by `tools/sprites/bake_ui.py`, driven by the staged
pack at `tools/sprites/packs/kenney_fantasy_ui/` (gitignored; re-download from
the link above). Used as `StyleBoxTexture` 9-slice frames (texture_margin 6).
