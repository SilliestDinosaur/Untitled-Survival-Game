# Untitled Survival (working title)

Stylized, fully procedural, first-person survival in Godot 4.5 (GDScript).
Day: explore and gather. Night: defend your base from shadow creatures that break walls.

## Run it
1. Install Godot 4.5+ (standard build): https://godotengine.org/download
2. Open Godot -> Import -> select this folder's `project.godot`.
3. Press F5.

**Controls:** WASD move · Shift sprint · Space jump / swim up · Left click swing / eat ·
1-6 or mouse wheel hotbar · Tab inventory · Esc pause · F3 debug info

## Everything is generated from the seed
Each seed produces its own:
- **Island**: terrain shape, mountain height, coastline (2 km x 2 km)
- **Biomes**: Meadow, Forest, Autumn Grove, Drylands + Beach, Highlands, Snowfields
- **Palette**: grass, foliage, rock, sky, water, flower colors (~1 in 5 worlds is "exotic")
- **Species**: tree/bush/rock/ore shapes and their names
- **World name**
- **Wildlife**: grazers, territorial beasts, critters and birds with generated bodies
  (legs, neck, ears, horns/antlers/tusks, tail, coat pattern), behaviors, calls and names

## Gameplay so far
- **Gathering (Rust-style):** hit trees, rocks, ore and bushes; each hit gives resources and
  the node breaks when its HP runs out (trees topple over). You start with a rock;
  bare hands are slow on wood and can't break stone.
- **Hunting:** grazers flee, territorial beasts fight back when hit. Dead animals become
  carcasses you harvest for raw meat, hide and bone.
- **Food:** select berries or meat on the hotbar and click to eat (raw meat hurts a little).
- **Death:** you drop everything and wake up back at the spawn point with a rock.

## Art style
Painterly / gouache: soft two-band lighting with warm light and cool shadows, world-space
brush-stroke color variation, "puffy" canopies lit as one volume, painted two-tone clouds,
and a screen filter (Kuwahara + paper grain) whose strength follows the quality setting.

Type a number or any word into the seed box on the title screen.
Sounds (footsteps, wind, ocean, UI) are synthesized at startup, so there are no audio files.

## Layout
| Path | What it does |
|---|---|
| `scripts/core/game.gd` | Autoload `Game`: seed, world name, palette, generators, input map |
| `scripts/core/settings.gd` | Autoload `Settings`: saved to `user://settings.cfg` |
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
| `tests/gameplay_test.gd` | Chops, mines, eats, hunts and harvests headlessly |

## Performance notes
- Chunks are generated on worker threads, so streaming doesn't stutter.
- 3 terrain detail tiers: full detail + collision + grass near you, simpler farther out.
- All plants/rocks are drawn with MultiMesh (one draw call per type per chunk).
- Quality presets (Low/Medium/High) control shadows, SSAO, MSAA and grass density.
