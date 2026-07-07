# Scene background licenses

The scene backgrounds in this directory (`battle.png`, `campfire.png`,
`menu.png`) are composited from **CC0 (Creative Commons Zero v1.0 Universal)**
pixel-art environment packs by **Luis Zuno (@ansimuz)** — public domain, free
for commercial and non-commercial use, no attribution required (credited here
with gratitude).

| Background | Source pack | Source |
|---|---|---|
| `battle.png` | GothicVania Cemetery Pack | https://opengameart.org/content/gothicvania-cemetery-pack |
| `campfire.png` | GothicVania Cemetery Pack | https://opengameart.org/content/gothicvania-cemetery-pack |
| `menu.png` | Gothicvania Town | https://opengameart.org/content/gothicvania-town |

Only the **artwork** is used (CC0). The packs also bundle music by Pascal
Belisle under a credit-required license — that music is NOT used in this project.

Conversion (layer compositing, integer NEAREST upscale to cover 640x360,
center crop, darken) is performed by `tools/sprites/import_env.py` driven by
`tools/sprites/env.json`. Original ZIPs are not committed
(`tools/sprites/packs/` is gitignored); re-download from the links above.
