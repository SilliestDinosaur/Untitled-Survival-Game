# Untitled Survival (working title)

Stylized, fully procedural, first-person survival in Godot 4.5 (GDScript).
Day: explore and gather. Night: defend your base from shadow creatures that break walls.

## Run it
1. Install Godot 4.5+ (standard build): https://godotengine.org/download
2. Open Godot -> Import -> select this folder's `project.godot`.
3. Press F5.

**Controls** (all remappable in Settings → Controls): WASD move · Shift sprint ·
Space jump / swim up · Left click swing / eat · 1-6 or mouse wheel hotbar · Tab satchel ·
Esc pause · F3 debug info

## Saves
Worlds are saved in `user://saves/` (on Windows: `%APPDATA%/Godot/app_userdata/Untitled Survival/saves`).
The title screen has **Continue**, **New World** (name + seed, with a live preview) and
**Load World** (play, rename or delete). The game autosaves every 2 minutes, when you pause,
and when you quit or close the window. A save stores the seed plus everything that changed:
your position, stats and inventory, and every tree/rock you gathered (they regrow after 15 minutes).

## Everything is generated from the seed
Each seed produces its own:
- **Island**: terrain shape, mountain height, coastline (2 km x 2 km)
- **Biomes**: Meadow, Forest, Autumn Grove, Savanna, Taiga, Marsh, Desert + Beach, Highlands, Snowfields
- **Mountains**: warped ridged ranges with foothills, alpine meadows and snow caps
- **Clutter**: fallen logs, stumps, mushrooms, pebbles, boulders, ferns, reeds, dry brush
- **Palette**: grass, foliage, rock, sky, water, flower colors (~1 in 5 worlds is "exotic")
- **Species**: tree/bush/rock/ore shapes and their names
- **World name**
- **Wildlife**: 10 body plans (slender, stocky, bulky, shellback, two-legged strider, wader,
  boar, horned brute, hopper, ferret) plus birds, each with generated proportions, coat pattern,
  horns/antlers/tusks, behavior, call and name

## Gameplay so far
- **Gathering (Rust-style):** hit trees, rocks, ore and bushes; each hit gives resources and
  the node breaks when its HP runs out (trees topple over). You start with a rock;
  bare hands are slow on wood and can't break stone.
- **Hunting:** grazers flee, territorial beasts fight back when hit. Dead animals become
  carcasses you harvest for raw meat, hide and bone.
- **Food:** select berries or meat on the hotbar and click to eat (raw meat hurts a little).
- **Death:** you drop everything and wake up back at the spawn point with a rock.

## Art style
Painterly / gouache, done per material (no screen filter): a generated brush-stroke texture
varies the pigment, the light/shadow edge follows the strokes, values band softly into a few
painted tones, and paint pools darker at silhouettes. Canopies are lit as one soft volume and
clouds are painted in two tones. The UI matches: parchment cards with ragged painted edges,
brush-stroke buttons and bars, and the Alegreya typefaces (SIL Open Font License, `fonts/OFL.txt`).

## Graphics settings
- **View distance**: 4-10 chunks; far chunks use simpler terrain and low-poly tree twins.
- **Quality**: shadows, ambient occlusion, anti-aliasing, grass density.
- **Model detail** (Low / Medium / High / Ultra): polygon count of every generated plant, rock
  and animal. Changes apply instantly.

Type a number or any word into the seed box on the title screen.
Sounds (footsteps, wind, ocean, UI) are synthesized at startup, so there are no audio files.

## Layout
| Path | What it does |
|---|---|
| `scripts/core/game.gd` | Autoload `Game`: seed, world name, palette, generators, input map |
| `scripts/core/settings.gd` | Autoload `Settings`: options + key bindings, saved to `user://settings.cfg` |
| `scripts/core/save_manager.gd` | World save files: list, read, write, rename, delete |
| `scripts/core/main.gd` | Game flow: title -> loading -> playing <-> paused |
| `scripts/core/name_gen.gd` | Procedural world and species names |
| `scripts/world/palette.gd` | Per-seed colors |
| `scripts/world/world_gen.gd` | Pure terrain/biome math (thread-safe) |
| `scripts/world/flora_library.gd` | Generates tree/bush/rock/grass meshes per seed |
| `scripts/world/mesh_kit.gd` | Low-poly mesh building helper |
| `scripts/world/chunk_generator.gd` | Builds chunk data on worker threads |
| `scripts/world/terrain_chunk.gd` | Turns chunk data into meshes/colliders |
| `scripts/world/world.gd` | Streams chunks with 3 detail tiers, ocean |
| `scripts/world/atmosphere.gd` | Sun, sky, fog, graphics quality |
| `scripts/player/` | First-person controller, stats, viewmodel (held item + swing) |
| `scripts/items/` | Item definitions and the inventory/hotbar |
| `scripts/gameplay/` | Gathering rules and hit effects |
| `scripts/wildlife/` | Species generation, animal/critter/bird behavior, spawning |
| `scripts/world/art_style.gd` | Shared painterly textures and materials |
| `scripts/audio/` | Procedural sound generation + playback |
| `scripts/ui/` | Theme, HUD, compass, stat bars, menus |
| `shaders/` | Painterly include + terrain, painted, foliage, grass, sky, water, post filter |
| `tests/smoke_test.gd` | `godot --headless --path . -s tests/smoke_test.gd` |
| `tests/gameplay_test.gd` | Chops, mines, eats, hunts, harvests, then saves and reloads |

## Performance notes
- Chunks are generated on worker threads, so streaming doesn't stutter.
- 3 terrain detail tiers: full detail + collision + grass near you, simpler farther out.
- All plants/rocks are drawn with MultiMesh (one draw call per type per chunk).
- Quality presets (Low/Medium/High) control shadows, SSAO, MSAA and grass density.
