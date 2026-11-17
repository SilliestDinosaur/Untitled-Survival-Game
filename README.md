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
- **Biomes**: Meadow, Forest, Autumn Grove, Savanna, Taiga, Marsh, Desert, Jungle, Tundra,
  Badlands (striped mesas), Fungal Grove (rare: giant mushrooms and glowcaps) + Beach, Highlands, Snowfields
- **Mountains**: warped ridged ranges with foothills, alpine meadows and snow caps
- **Water**: the sea, plus meandering rivers and lowland lakes carved into the terrain (how
  lake-rich a world is varies). Painted water shader: clear shallows that show the ground,
  banded depth colours, sky reflections, shore foam lines and glints.
- **Music**: each world has its own key, scales, motifs and chord progressions (see below)
- **Plants & clutter**: palms, saplings, flowering shrubs, agave, barrel cacti, tumbleweeds,
  ferns, tall grass, clover, reeds, dry brush, fallen logs (with shelf fungi), stumps with roots,
  fallen branches, mushrooms, pebbles, scree, boulders
- **Palette**: grass, foliage, rock, sky, water, flower colors (~1 in 5 worlds is "exotic")
- **Species**: tree/bush/rock/ore shapes and their names
- **World name**
- **Wildlife**: every biome has its own adapted grazer, and some get their own beast and critter.
  The biome shapes them: thick shaggy fur, bigger bodies and small ears in the cold; lean,
  sand-coloured, big-eared and night-active in the desert; bold stripes in the jungle; rust coats
  in the badlands; glowing spots in the fungal grove. Marsh animals keep to the water's edge, and
  highland and badlands animals climb slopes. Built from 10 body plans (slender, stocky, bulky, shellback, two-legged strider, wader,
  boar, horned brute, hopper, ferret) plus birds. Counting only the discrete choices (pattern,
  ears, horns/antlers/tusks, tail, hump, temperament) there are 968 distinct animal designs;
  each also has ~15 continuous traits (size, proportions, neck, head, horn length, three coat
  colors), so no two worlds share the same animals. Bodies, necks and heads are lofted surfaces.

## Items & tiers
Held items float in view (no hands). Tool heads are sculpted (`MeshKit.sculpt`): thickness varies
across each head, so axes swell into a socket that wraps the handle and taper to a real edge with a
grind line and a bright honed band, spear heads have a central ridge, knives a spine and fuller.
Handles are oval with grain, a knob at the butt and a wound leather grip; stone tools are knapped
flint lashed on with crossed cord. All in `scripts/items/item_models.gd`; the same models lie in
the world when dropped and float beside other players.

Tools come in tiers: **Rock → Stone → three materials generated per world → Duskforged**.
Every island invents its own metals and gem (name, color, trait like *Swift*, *Keen*, *Sturdy*,
*Vicious* or *Luminous*) found at different altitudes: the first metal in the hills, the second in
the mountains, crystals near the peaks. Better ore needs a pickaxe of the tier below it. The last
tier is forged from shadow essence dropped by the night's creatures (the creatures come next).
Hatchets, pickaxes, spears and knives exist for every tier and wear down with use. Supply caches
around the island hold a few used tools to get you started.
Food is per-world too: berries, a fruiting tree species, and mushrooms and herbs whose effects
(mending, vigor, sated... or poison) are unknown until you try them.

## Shaping the land
- **Shovel** (R changes mode, `[` and `]` change width): **Dig** removes dirt and gives it to you,
  **Pile** builds up with dirt from your satchel, **Flatten** levels to the height you aim at,
  **Smooth** softens bumps. Changes are saved with the world and shared with friends.
- **Pickaxe**: breaks stone on rocky or steep ground (not on soft soil) and gives stone.
  Stone chiseled at a workbench becomes **stone bricks**.
- **Base building**: a **Foundation** (4 bricks) levels the ground under it, blending into the
  slope. **Brick walls** (3 bricks) and **plank walls** (3 planks) snap to the edges of a
  foundation, so they can't float or clip into the ground. Pieces snap to a 2 m grid.

## Crafting
Open the satchel (Tab) to see the crafting list beside it, by group: Basics, Stations, Tools,
Materials, Food. Ingredients show what you have / need; Shift-click Craft to make five.
- **By hand:** rope, torches (a held light that matters at night), bandages, stone tools, campfire, workbench.
- **Campfire:** cooked meat, roasted fruit, hearty stew. Lights up the night.
- **Workbench:** planks, leather, the first metal's tools, cut gems and gem tools. Also builds the forge.
- **Forge:** smelts this world's ores into ingots, the second metal's tools, Duskforged ingots and tools.

Stations are placed like Rust: hold one, aim (a green/red ghost shows if it fits), click to place.
Press E on a station to open crafting; hit it a few times to pack it back up.

## Survival
- Hunger runs out in about 15 minutes; sprinting burns food and stamina quickly.
- Tools wear down and gathering takes effort, so upgrading tools matters.
- **Warmth**: nights are cold, and the tundra, taiga, highlands, mountain tops and water are
  colder still. When warmth runs low you stop healing and tire faster; at zero you freeze.
  Stand by a campfire (or forge) to warm up, or carry a torch to slow the chill.

## Day & night
A day lasts 16 minutes. The sun and moon cross the sky, dusk warms the light and the sky glows
on the sun's side, night brings stars, a moon, cool shadows and darkness (torches and campfires
matter). The HUD shows the day and time, and warns as the sun sets.

## Music
Procedural, like No Man's Sky: synthesized instruments (pad, kalimba pluck, bell, flute, bass,
tremolo strings, soft drums) and a generative sequencer. Moods change with what's happening:
**title**, calm **day**, **exploring** (after a stretch of travel), **dusk**, **night**,
**hunting** (chasing and striking prey) and **combat** (only when something fights back),
crossfading between them. Every world
picks its own key and scales per mood, so each island sounds different, and the music
periodically thins out to leave room for the ambience.

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
- **Model detail** (Low / Medium / High / Ultra): polygon count of every generated plant, rock,
  animal and item.
- **Shadows** (Off / Low / Medium / High / Ultra), **Anti-aliasing** (Off, FXAA, MSAA 2x/4x/8x, TAA),
  **Grass & flowers** density, **Render scale** with FSR upscaling, **FPS limit**, **V-Sync**,
  **Ambient occlusion**, **Glow**.
- Audio: master, music and effects volume.

Type a number or any word into the seed box on the title screen.
Sounds and music are synthesized at startup, so there are no audio files.

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
| `scripts/world/atmosphere.gd` | Day/night: sun, moon, sky, fog; graphics settings |
| `scripts/world/structures.gd` | Placed stations (campfire light, forge coals) |
| `scripts/world/structure_models.gd` | Campfire, workbench and forge models |
| `scripts/items/recipes.gd` | Crafting recipes |
| `scripts/audio/music.gd` | Autoload `Music`: generative mood-based music |
| `scripts/net/net.gd` | Autoload `Net`: hosting, joining, invite codes, action routing, sync |
| `scripts/net/remote_player.gd` | Other players' avatars |
| `scripts/audio/instruments.gd` | Synthesized instrument samples |
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

## Multiplayer (co-op, up to 4)
- **Host:** switch on *Open to friends* when creating or loading a world, or press *Open to
  Friends* in the pause menu. The game asks your router to open UDP port 24680 (UPnP) and shows
  an **invite code** to give your friend. A **same-network code** is shown too.
- **Join:** title screen -> *Play with Friends*, pick your name and colour, enter the code.
- If your router doesn't allow UPnP, the menu says so: friends on your Wi-Fi can still use the
  same-network code; for internet play forward UDP port 24680, or both join a virtual LAN
  (Tailscale, ZeroTier, Radmin VPN) and type the host's address (e.g. `100.64.1.2`) as the code.
- It's the host's world: guests' characters (inventory, position, health) are saved in the host's
  save and restored when they rejoin.
- Other players appear as simple floating figures (torso, head, held item, name tag).

How it works: the host is the authority. Every world-changing action goes through
`Net.request()` (`scripts/net/net.gd`): offline and on the host it runs `GameActions` directly;
a guest sends it to the host, which runs it for that guest's inventory and broadcasts the result
(trees falling, items dropped, structures, inventories). The host simulates animals for everyone
and streams their positions; guests show puppets. Players stream their pose to each other.
Test it with two processes: `tests/net_host_test.gd` and `tests/net_client_test.gd`.

## Performance notes
- Chunks are generated on worker threads, so streaming doesn't stutter.
- 3 terrain detail tiers: full detail + collision + grass near you, simpler farther out.
- All plants/rocks are drawn with MultiMesh (one draw call per type per chunk).
- Shadows, SSAO, AA, render scale and grass density are separate settings.
- Music instruments are rendered once on a worker thread; playback uses polyphonic streams.
