extends RefCounted
## A player's progress: the first-steps guide (the basics, in order) and the journal's milestones. Worked out from the
## player's state a couple of times a second (what they've carried, what stands in the world, where they've been),
## so it works the same for a guest as for the host and needs no hooks in the rest of the game. Kept in the player's
## own save data (see Player.progress), so each player in a world has their own.
##
## progress = {seen: {item id: 1}, biomes: {name: 1}, landmarks: {index: 1}, done: {milestone id: day}, guide: {step: 1},
##             flags: {cave, peak}}

## The first steps, in order: [id, text (with {action} key names filled in), check].
const GUIDE := [
	["gather", "Gather fiber from bushes and pick up sticks ({interact})"],
	["stone", "Pick up a few stones from the ground ({interact})"],
	["hatchet", "Craft a stone hatchet: open your satchel ({inventory})"],
	["wood", "Chop a tree for wood (hatchet in hand, {attack})"],
	["campfire", "Craft a campfire and place it"],
	["cook", "Cook some meat or fruit at the fire ({interact} on it)"],
	["shelter", "Before night: build walls (a building plan, hold {build_menu}; then a hammer)"],
]

## The journal: [id, group, title, description].
const MILESTONES := [
	["first_steps", "Survival", "Finding your feet", "Finish the first steps."],
	["night1", "Survival", "Through the night", "See the sun come up on your second day."],
	["day5", "Survival", "Settling in", "Live to see day five."],
	["day10", "Survival", "Islander", "Live to see day ten."],
	["cooked", "Survival", "A hot meal", "Cook something over a fire."],
	["forage", "Survival", "Brave taster", "Try a wild mushroom or herb to learn what it does."],
	["bandage", "Survival", "Patched up", "Make a bandage."],
	["slept", "Survival", "Sound asleep", "Sleep the night away in a bed of your own."],
	["stone_tools", "Crafting", "Stone age", "Make a stone hatchet and a stone pickaxe."],
	["workbench", "Crafting", "Woodworker", "Build a workbench."],
	["home", "Crafting", "A roof overhead", "Build a home: walls round you and a roof above."],
	["forge", "Crafting", "Fire and stone", "Build a forge."],
	["ingot", "Crafting", "First metal", "Smelt ore into an ingot at the forge."],
	["metal_tool", "Crafting", "Sharper edges", "Make a metal tool."],
	["hunt", "Hunting", "Hunter", "Bring down an animal for its meat."],
	["hide", "Hunting", "Tanner's stock", "Take a hide from an animal."],
	["biomes3", "Exploring", "Wanderer", "Walk through three different lands."],
	["biomes6", "Exploring", "Traveller", "Walk through six different lands."],
	["biomes9", "Exploring", "Cartographer", "Walk through nine different lands."],
	["cave", "Exploring", "Into the dark", "Go down into a cave."],
	["peak", "Exploring", "On top of the world", "Climb to a mountain peak."],
	["explored", "Exploring", "Mapmaker", "Explore a quarter of the island."],
	["lm_giant_tree", "Landmarks", "The old giant", "Find a giant tree standing in its clearing."],
	["lm_meadow", "Landmarks", "Hidden meadow", "Find a glade of flowers deep in a forest."],
	["lm_stones", "Landmarks", "Standing stones", "Find a ring of old stones on a hilltop."],
	["lm_arch", "Landmarks", "Stone arch", "Find a natural rock arch."],
	["lm_stack", "Landmarks", "Sea stacks", "Find the rock pillars standing in the sea."],
	["lm_all", "Landmarks", "Seen it all", "Find every landmark on the island."],
]
const GROUPS := ["Survival", "Crafting", "Hunting", "Exploring", "Landmarks"]

const WALLS := ["wall", "wood_wall", "stone_wall", "window_wall", "wood_window", "stone_window", "doorway", "wood_doorway",
	"stone_doorway", "brick_half", "wood_half", "stone_half"]
const ROOFS := ["roof", "wood_roof", "stone_roof"]
const LM_NAMES := {"giant_tree": "a giant tree", "meadow": "a hidden meadow", "stones": "standing stones", "arch": "a stone arch", "stack": "sea stacks"}


static func blank() -> Dictionary:
	return {"seen": {}, "biomes": {}, "landmarks": {}, "done": {}, "guide": {}, "flags": {}}


## The text of a guide step, with the player's own key for each {action}.
static func guide_text(step: Array) -> String:
	var t: String = step[1]
	for action: String in ["interact", "inventory", "attack", "build_menu"]:
		t = t.replace("{%s}" % action, key_name(action))
	return t


static func key_name(action: String) -> String:
	var code: String = Settings.binding_of(action)
	var parts := code.split(":")
	if parts.size() != 2:
		return "?"
	if parts[0] == "mouse":
		return {"1": "left click", "2": "right click", "3": "middle click"}.get(parts[1], "mouse %s" % parts[1])
	return OS.get_keycode_string(int(parts[1]))


## The first guide step not yet done (index), or -1 when the basics are all done.
static func guide_step(p: Dictionary) -> int:
	for i in GUIDE.size():
		if not (p.guide as Dictionary).has(GUIDE[i][0]):
			return i
	return -1


## Look at the player and the world; mark what's newly done. Returns the milestone ids earned just now, and fills
## `guide_new` with guide steps finished just now. (A step only counts once those before it are done.)
static func update(p: Dictionary, player: Node3D, guide_new: Array) -> Array:
	for k: String in ["seen", "biomes", "landmarks", "done", "guide", "flags"]:
		if not p.has(k):
			p[k] = {}
	var seen: Dictionary = p.seen
	var inv = player.inventory
	for s: Dictionary in inv.slots:
		var id := String(s.get("id", ""))
		if id != "":
			seen[id] = 1
	var pos: Vector3 = player.global_position
	var gen: WorldGen = Game.world_gen
	if gen:
		if not Game.in_cave:
			p.biomes[gen.BIOME_NAMES[gen.get_biome(pos.x, pos.z)]] = 1
		for i in gen.landmarks.size():
			var lm: Dictionary = gen.landmarks[i]
			var lp: Vector3 = lm.pos
			if Vector2(lp.x - pos.x, lp.z - pos.z).length() < float(lm.r) + (45.0 if lm.kind == "stack" else 25.0):
				p.landmarks[str(i)] = String(lm.kind)
		if Game.in_cave:
			p.flags.cave = 1
		if pos.y > 68.0 and not Game.in_cave:
			p.flags.peak = 1
	var built := {}
	for sid: String in Game.structures:
		var st: Dictionary = Game.structures[sid]
		if float(st.get("built", 1.0)) < 1.0:
			continue   # a blueprint not yet hammered up
		var kind := String(st.get("kind", ""))
		built[kind] = int(built.get(kind, 0)) + 1
	var has := func(id: String) -> bool: return seen.has(id)
	var built_any := func(kinds: Array) -> int:
		var n := 0
		for k: String in kinds:
			n += int(built.get(k, 0))
		return n

	# The guide, in order.
	var checks := {
		"gather": has.call("fiber") and has.call("sticks"),
		"stone": has.call("stone"),
		"hatchet": has.call("hatchet_t1") or _any_tool(seen, "hatchet"),
		"wood": has.call("wood"),
		"campfire": int(built.get("campfire", 0)) > 0,
		"cook": has.call("cooked_meat") or has.call("roast_fruit") or has.call("stew"),
		"shelter": int(built_any.call(WALLS)) >= 2,
	}
	for step: Array in GUIDE:
		if p.guide.has(step[0]):
			continue
		if not checks[step[0]]:
			break
		p.guide[step[0]] = 1
		guide_new.append(step[0])

	# The journal.
	var lm_kinds := {}
	for k: String in p.landmarks:
		lm_kinds[p.landmarks[k]] = true
	var ok := {
		"first_steps": guide_step(p) == -1,
		"night1": Game.day >= 2,
		"day5": Game.day >= 5,
		"day10": Game.day >= 10,
		"cooked": checks.cook,
		"forage": not Game.known_items.is_empty(),
		"bandage": has.call("bandage"),
		"stone_tools": (has.call("hatchet_t1") or _any_tool(seen, "hatchet")) and (has.call("pickaxe_t1") or _any_tool(seen, "pickaxe")),
		"workbench": int(built.get("workbench", 0)) > 0,
		"home": p.flags.has("home"),   # (stood in a room with a roof and walls all round: see Player._update_exposure)
		"slept": p.flags.has("slept"),
		"forge": int(built.get("forge", 0)) > 0,
		"ingot": _any_prefix(seen, "ingot_t") or has.call("dusk_ingot"),
		"metal_tool": _metal_tool(seen),
		"hunt": has.call("raw_meat"),
		"hide": has.call("hide"),
		"biomes3": p.biomes.size() >= 3,
		"biomes6": p.biomes.size() >= 6,
		"biomes9": p.biomes.size() >= 9,
		"cave": p.flags.has("cave"),
		"peak": p.flags.has("peak"),
		"explored": _explored_share() >= 0.25,
		"lm_giant_tree": lm_kinds.has("giant_tree"),
		"lm_meadow": lm_kinds.has("meadow"),
		"lm_stones": lm_kinds.has("stones"),
		"lm_arch": lm_kinds.has("arch"),
		"lm_stack": lm_kinds.has("stack"),
		"lm_all": gen != null and not gen.landmarks.is_empty() and p.landmarks.size() >= gen.landmarks.size(),
	}
	var earned: Array = []
	for m: Array in MILESTONES:
		if not p.done.has(m[0]) and ok.get(m[0], false):
			p.done[m[0]] = Game.day
			earned.append(m[0])
	return earned


static func milestone(id: String) -> Array:
	for m: Array in MILESTONES:
		if m[0] == id:
			return m
	return []


static func _any_tool(seen: Dictionary, type: String) -> bool:
	for t in range(1, 6):
		if seen.has("%s_t%d" % [type, t]):
			return true
	return false


static func _metal_tool(seen: Dictionary) -> bool:
	for type: String in ["hatchet", "pickaxe", "spear", "knife"]:
		for t in range(2, 6):
			if seen.has("%s_t%d" % [type, t]):
				return true
	return false


static func _any_prefix(seen: Dictionary, prefix: String) -> bool:
	for k: String in seen:
		if k.begins_with(prefix):
			return true
	return false


## How much of the island has been seen (land and sea cells alike), checked now and then (it's a big grid).
static var _share_cache := 0.0
static var _share_at := -100.0
static func _explored_share() -> float:
	if Game.play_time - _share_at < 10.0:
		return _share_cache
	_share_at = Game.play_time
	var e: PackedByteArray = Game.explored
	if e.is_empty():
		return 0.0
	var n := e.size() - e.count(0)
	# The island is about half the map; count against that, so a quarter of the island is reachable.
	_share_cache = float(n) / (e.size() * 0.5)
	return _share_cache
