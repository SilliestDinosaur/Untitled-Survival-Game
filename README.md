# Untitled Survival (working title)

Stylized, fully procedural, first-person survival in Godot 4.5 (GDScript).
Day: explore and gather. Night: defend your base from shadow creatures that break walls.

## Run it
1. Install Godot 4.5+ (standard build): https://godotengine.org/download
2. Open Godot -> Import -> select this folder's `project.godot`.
3. Press F5.

**Controls** (all remappable in Settings → Controls): WASD move · Shift sprint ·
Space jump / swim up · **Left click** swing: chop, mine, break, hunt, eat ·
**E** harvest by hand: berries, sticks, fiber, fruit, pick up, butcher, open caches ·
**Q** drop (Ctrl+Q whole stack) · 1-8 / mouse wheel hotbar · Tab satchel · Esc pause ·
F3 debug info · F9 debug item menu

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
- **Plants & clutter**: palms, saplings, flowering shrubs, agave, barrel cacti, tumbleweeds,
  ferns, tall grass, clover, reeds, dry brush, fallen logs (with shelf fungi), stumps with roots,
  fallen branches, mushrooms, pebbles, scree, boulders
- **Palette**: grass, foliage, rock, sky, water, flower colors (~1 in 5 worlds is "exotic")
- **Species**: tree/bush/rock/ore shapes and their names
- **World name**
- **Wildlife**: 10 body plans (slender, stocky, bulky, shellback, two-legged strider, wader,
  boar, horned brute, hopper, ferret) plus birds. Counting only the discrete choices (pattern,
  ears, horns/antlers/tusks, tail, hump, temperament) there are 968 distinct animal designs;
  each also has ~15 continuous traits (size, proportions, neck, head, horn length, three coat
  colors), so no two worlds share the same animals. Bodies, necks and heads are lofted surfaces.

## Items & tiers
Held items float in view (no hands). Every model is built from lofts, bevelled outlines and
faceted surfaces in `scripts/items/item_models.gd`, and the same models lie in the world when dropped.

Tools come in tiers: **Rock → Stone → three materials generated per world → Duskforged**.
Every island invents its own metals and gem (name, color, trait like *Swift*, *Keen*, *Sturdy*,
*Vicious* or *Luminous*) found at different altitudes: the first metal in the hills, the second in
the mountains, crystals near the peaks. Better ore needs a pickaxe of the tier below it. The last
tier is forged from shadow essence dropped by the night's creatures (coming with the night cycle).
Hatchets, pickaxes, spears and knives exist for every tier and wear down with use. Crafting comes
next; for now tools are found in supply caches around the island (or via the F9 debug menu).
Food is per-world too: berries, a fruiting tree species, and mushrooms and herbs whose effects
(mending, vigor, sated... or poison) are unknown until you try them.

## Gameplay so far
- **Destroy (left click):** each hit gives resources and the node breaks when its HP runs out
  (trees topple over). **Harvest (E):** take what a plant offers without killing it; it regrows.
- **Satchel:** 24 slots + 8-slot hotbar, drag & drop, split, shift-click, drop into the world.
- **Animals:** temperaments (calm, wary, skittish, curious), herds that share alarm, alert
  states, territorial beasts that warn before charging. Butcher carcasses with E (a knife helps).
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
| `scripts/core/game_actions.gd` | Every world-changing action (host-authoritative later) |
| `scripts/world/pickups.gd` | Items lying in the world |
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
| `scripts/items/` | Item registry (base + per-world tiers/foods) and slot inventory |
| `scripts/gameplay/` | Gathering rules and hit effects |
| `scripts/wildlife/` | Species generation, animal/critter/bird behavior, spawning |
| `scripts/world/art_style.gd` | Shared painterly textures and materials |
| `scripts/audio/` | Procedural sound generation + playback |
| `scripts/ui/` | Theme, HUD, compass, stat bars, menus |
| `shaders/` | Painterly include + terrain, painted, foliage, grass, sky, water, post filter |
| `tests/smoke_test.gd` | `godot --headless --path . -s tests/smoke_test.gd` |
| `tests/gameplay_test.gd` | Chops, mines, eats, hunts, harvests, then saves and reloads |

## Built for multiplayer later
World changes go through `scripts/core/game_actions.gd` with a player id, inventories live in
`Game.inventories` keyed by player, dropped items have stable entity ids, and saves store a map of
players. A peer-to-peer host can run the same actions for every client; clients regenerate the
world from the seed and only need the list of changes.

## Performance notes
- Chunks are generated on worker threads, so streaming doesn't stutter.
- 3 terrain detail tiers: full detail + collision + grass near you, simpler farther out.
- All plants/rocks are drawn with MultiMesh (one draw call per type per chunk).
- Quality presets (Low/Medium/High) control shadows, SSAO, MSAA and grass density.
