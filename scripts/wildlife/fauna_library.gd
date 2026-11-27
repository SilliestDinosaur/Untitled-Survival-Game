class_name FaunaLibrary
extends RefCounted
## Generates this world's creature species from the seed: body plan, colors, pattern,
## behavior numbers, name and call. Each species' body parts are built once here and
## shared by every animal of that species.

const Biome := WorldGen.Biome

## One generated species.
class Species:
	var id := ""
	var name := ""
	var role := ""            ## grazer | defensive | critter | bird
	var label := ""           ## shown under the name ("Grazer", "Territorial beast"...)
	var size := 1.0
	var hp := 40.0
	var walk_speed := 1.4
	var run_speed := 7.0
	var flee_radius := 14.0
	var damage := 0.0
	var herd := Vector2i(1, 1)
	var yield_scale := 1.0
	var biome_pref := {}      ## Biome -> weight
	var home := -1            ## the biome this species is adapted to (-1 = none, e.g. birds)
	var active := "any"       ## any | day | night: when it's out and about
	var habitat := ""         ## "" | water (stays near water) | steep (climbs slopes)
	# Body layout (meters, already scaled by size)
	var leg_len := 0.7
	var body_len := 1.0
	var body_h := 0.55
	var body_w := 0.45
	var head_pivot := Vector3.ZERO
	var leg_offsets: Array[Vector3] = []
	# Meshes
	var body_mesh: ArrayMesh
	var head_mesh: ArrayMesh
	var leg_mesh: ArrayMesh        ## front legs
	var hind_leg_mesh: ArrayMesh   ## back legs (bent hock)
	var temperament := "wary"      ## calm | wary | skittish | curious
	var wing_mesh: ArrayMesh
	var call_sound: AudioStreamWAV
	# Added with the bigger menagerie.
	var body := "quad"        ## quad | sprawl (lizards: legs out to the sides) | serpent | upright | seal | frog
	var diet := "herb"        ## herb | carn | omni: what it eats (predators hunt animals smaller than themselves)
	var climbs := false       ## goes up trees (monkeys)
	var swims := false        ## goes into the water and swims (otters, seals, penguins)
	var venom := false        ## its bite poisons
	var segs := 0             ## serpents: how many body segments follow the head
	var seg_mesh: ArrayMesh   ## serpents: one segment of the body (the head mesh leads them)
	var tail_mesh: ArrayMesh  ## the tail on its own (it swishes), built about its root
	var tail_pivot := Vector3.ZERO   ## where the tail joins the body
	var bird_kind := "flock"  ## birds: flock (circling) | perch (lands in trees and on logs) | soar (high slow circles)

	## Whether it runs off as soon as someone comes near. About half the island's kinds do (the skittish ones, and
	## some of the wary); the rest stand their ground, watch, and edge away if crowded, and only bolt when startled:
	## someone sprinting at them, a hit, or the herd taking fright. Worked out from the species itself, so it's the
	## same on every machine and for every world already made.
	func bolts() -> bool:
		match temperament:
			"skittish":
				return true
			"wary":
				return fposmod(flee_radius * 7.31 + leg_len * 3.7, 1.0) < 0.55
		return false

const ROLE_LABELS := {"grazer": "Grazer", "defensive": "Territorial beast", "critter": "Critter", "bird": "Bird", "small": "Small animal"}

var species: Array[Species] = []
var material: ShaderMaterial
var _pal: WorldPalette
var _exotic_shift := 0.0   ## exotic worlds: every coat's hue is rotated by this


## Body plans. Each species picks one, then randomizes within its ranges.
## size, leg (x size), body_h (x size), neck (x size), neck_angle (degrees), legs, and favorite biomes.
const ARCHETYPES := {
	"slender": {"role": "grazer", "size": [0.55, 0.8], "leg": [0.8, 0.95], "body_h": [0.38, 0.46], "neck": [0.28, 0.42], "angle": [45, 65], "legs": 4,
		"biomes": {Biome.MEADOW: 1.0, Biome.FOREST: 0.7, Biome.AUTUMN: 0.8, Biome.DRYLANDS: 0.6}},
	"stocky": {"role": "grazer", "size": [0.9, 1.2], "leg": [0.55, 0.72], "body_h": [0.42, 0.5], "neck": [0.2, 0.34], "angle": [35, 55], "legs": 4,
		"biomes": {Biome.MEADOW: 0.8, Biome.FOREST: 1.0, Biome.AUTUMN: 1.0, Biome.TAIGA: 0.5}},
	"bulky": {"role": "grazer", "size": [1.4, 1.8], "leg": [0.42, 0.55], "body_h": [0.55, 0.65], "neck": [0.08, 0.18], "angle": [10, 25], "legs": 4,
		"biomes": {Biome.TAIGA: 1.0, Biome.MEADOW: 0.5, Biome.FOREST: 0.6}},
	"shellback": {"role": "grazer", "size": [0.7, 1.0], "leg": [0.18, 0.25], "body_h": [0.42, 0.5], "neck": [0.15, 0.25], "angle": [10, 25], "legs": 4,
		"biomes": {Biome.DRYLANDS: 1.0, Biome.DESERT: 1.0, Biome.MARSH: 0.8}},
	"strider": {"role": "grazer", "size": [0.9, 1.2], "leg": [1.0, 1.25], "body_h": [0.5, 0.6], "neck": [0.6, 0.8], "angle": [70, 80], "legs": 2,
		"biomes": {Biome.DRYLANDS: 1.0, Biome.DESERT: 0.8, Biome.MEADOW: 0.5}},
	"wader": {"role": "grazer", "size": [0.7, 0.95], "leg": [1.0, 1.2], "body_h": [0.36, 0.42], "neck": [0.5, 0.7], "angle": [55, 70], "legs": 4,
		"biomes": {Biome.MARSH: 1.0, Biome.FOREST: 0.3}},
	"boar": {"role": "defensive", "size": [0.85, 1.15], "leg": [0.32, 0.45], "body_h": [0.5, 0.62], "neck": [0.1, 0.2], "angle": [15, 35], "legs": 4,
		"biomes": {Biome.FOREST: 1.0, Biome.AUTUMN: 0.8, Biome.TAIGA: 0.6, Biome.MEADOW: 0.4}},
	"horned": {"role": "defensive", "size": [1.1, 1.4], "leg": [0.45, 0.6], "body_h": [0.55, 0.65], "neck": [0.1, 0.2], "angle": [15, 30], "legs": 4,
		"biomes": {Biome.DRYLANDS: 1.0, Biome.MEADOW: 0.6, Biome.DESERT: 0.4}},
	"hopper": {"role": "critter", "size": [0.26, 0.36], "leg": [0.18, 0.3], "body_h": [0.38, 0.5], "neck": [0.22, 0.4], "angle": [35, 60], "legs": 4,
		"biomes": {Biome.MEADOW: 1.0, Biome.FOREST: 0.7, Biome.AUTUMN: 0.8, Biome.DRYLANDS: 0.6, Biome.TAIGA: 0.5}},
	"ferret": {"role": "critter", "size": [0.3, 0.4], "leg": [0.14, 0.2], "body_h": [0.28, 0.34], "neck": [0.15, 0.25], "angle": [15, 30], "legs": 4,
		"biomes": {Biome.FOREST: 1.0, Biome.TAIGA: 0.9, Biome.MARSH: 0.8, Biome.AUTUMN: 0.6}},
	# Added with the bigger menagerie (each made for its own biome, see _more_fauna).
	"feline": {"role": "defensive", "size": [0.95, 1.2], "leg": [0.48, 0.58], "body_h": [0.38, 0.44], "neck": [0.12, 0.2], "angle": [18, 28], "legs": 4, "biomes": {}},
	"canine": {"role": "grazer", "size": [0.5, 0.72], "leg": [0.58, 0.68], "body_h": [0.36, 0.42], "neck": [0.08, 0.14], "angle": [18, 28], "legs": 4, "biomes": {}},
	"otter": {"role": "grazer", "size": [0.42, 0.55], "leg": [0.14, 0.2], "body_h": [0.3, 0.36], "neck": [0.12, 0.2], "angle": [12, 22], "legs": 4, "biomes": {}},
	"lizard": {"role": "small", "size": [0.28, 0.4], "leg": [0.16, 0.22], "body_h": [0.2, 0.26], "neck": [0.04, 0.08], "angle": [4, 10], "legs": 4, "biomes": {}},
	"monkey": {"role": "grazer", "size": [0.5, 0.68], "leg": [0.6, 0.72], "body_h": [0.4, 0.48], "neck": [0.06, 0.12], "angle": [30, 42], "legs": 4, "biomes": {}},
	"heron": {"role": "grazer", "size": [0.55, 0.7], "leg": [1.15, 1.35], "body_h": [0.4, 0.46], "neck": [0.7, 0.9], "angle": [70, 82], "legs": 2, "biomes": {}},
}


## Which body plans live in each biome.
const BIOME_FAUNA := {
	Biome.MEADOW: {"grazer": ["slender", "stocky"], "beast": ["horned"]},
	Biome.FOREST: {"grazer": ["stocky", "slender"], "beast": ["boar"]},
	Biome.AUTUMN: {"grazer": ["slender", "stocky"], "beast": ["boar"]},
	Biome.DRYLANDS: {"grazer": ["strider", "slender"], "beast": ["horned"]},
	Biome.DESERT: {"grazer": ["strider", "shellback"], "beast": []},
	Biome.TAIGA: {"grazer": ["bulky", "stocky"], "beast": ["boar"]},
	Biome.MARSH: {"grazer": ["wader", "shellback"], "beast": []},
	Biome.JUNGLE: {"grazer": ["slender", "strider"], "beast": ["boar"]},
	Biome.TUNDRA: {"grazer": ["bulky", "stocky"], "beast": ["horned"]},
	Biome.BADLANDS: {"grazer": ["shellback", "stocky"], "beast": ["horned"]},
	Biome.FUNGAL: {"grazer": ["shellback", "wader", "slender"], "beast": []},
	Biome.HIGHLANDS: {"grazer": ["stocky"], "beast": ["horned"]},
}

## How a biome shapes the animals that live there.
##  coat: color scheme, size/leg/width: body multipliers, fur: shaggy coat, ears: big | small,
##  patterns: allowed coat patterns, active: day | night | any (chance), hp/speed multipliers,
##  habitat: water | steep, words: name prefixes.
const BIOME_TRAITS := {
	Biome.MEADOW: {"coat": "earth", "patterns": ["none", "saddle", "spots"], "words": ["Meadow", "Clover", "Sun"]},
	Biome.FOREST: {"coat": "dark", "patterns": ["spots", "none"], "words": ["Moss", "Bramble", "Shade"]},
	Biome.AUTUMN: {"coat": "russet", "patterns": ["none", "saddle", "spots"], "words": ["Ember", "Amber", "Rust"]},
	Biome.DRYLANDS: {"coat": "tan", "patterns": ["stripes", "spots"], "leg": 1.1, "speed": 1.1, "words": ["Grass", "Plains", "Sun"]},
	Biome.DESERT: {"coat": "sand", "patterns": ["none", "saddle"], "width": 0.85, "ears": "big", "night": 0.8, "hp": 0.9, "words": ["Dune", "Sand", "Mirage"]},
	Biome.TAIGA: {"coat": "dark", "fur": true, "size": 1.1, "patterns": ["none", "saddle"], "hp": 1.15, "words": ["Pine", "Frost", "Bark"]},
	Biome.MARSH: {"coat": "olive", "patterns": ["none", "stripes"], "leg": 1.1, "habitat": "water", "words": ["Bog", "Reed", "Mire"]},
	Biome.JUNGLE: {"coat": "vivid", "patterns": ["stripes", "spots"], "speed": 1.15, "skittish": true, "words": ["Canopy", "Jade", "Vine"]},
	Biome.TUNDRA: {"coat": "snow", "fur": true, "size": 1.2, "leg": 0.85, "ears": "small", "hp": 1.35, "speed": 0.9, "patterns": ["none"], "words": ["Frost", "Rime", "Snow"]},
	Biome.BADLANDS: {"coat": "rust", "patterns": ["saddle", "stripes"], "hp": 1.2, "night": 0.4, "habitat": "steep", "words": ["Mesa", "Red", "Cliff"]},
	Biome.FUNGAL: {"coat": "fungal", "patterns": ["spots"], "night": 0.9, "curious": true, "ears": "big", "words": ["Spore", "Glow", "Gloam"]},
	Biome.HIGHLANDS: {"coat": "stone", "fur": true, "patterns": ["saddle", "none"], "leg": 0.9, "habitat": "steep", "hp": 1.15, "words": ["Crag", "Ridge", "Stone"]},
}


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	material = ArtStyle.painted({"brush_strength": 0.22, "rim_amount": 0.25})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	_exotic_shift = rng.randf_range(0.25, 0.75)
	# One grazer adapted to each biome, territorial beasts and critters in some of them,
	# and 2-3 birds. A body plan that suits the biome is picked, then its coat, fur, build
	# and habits are shaped by where it lives.
	for home: int in BIOME_FAUNA:
		var plans: Dictionary = BIOME_FAUNA[home]
		var g: Array = plans.grazer
		species.append(_make_quadruped(rng, g[rng.randi() % g.size()], home))
	var beast_homes: Array = BIOME_FAUNA.keys().filter(func(b: int) -> bool: return not BIOME_FAUNA[b].beast.is_empty())
	var critter_homes: Array = BIOME_FAUNA.keys()
	for list: Array in [beast_homes, critter_homes]:
		for i in range(list.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var tmp: int = list[i]
			list[i] = list[j]
			list[j] = tmp
	for home: int in beast_homes.slice(0, 4):
		var b: Array = BIOME_FAUNA[home].beast
		species.append(_make_quadruped(rng, b[rng.randi() % b.size()], home))
	for home: int in critter_homes.slice(0, 5):
		species.append(_make_quadruped(rng, ["hopper", "ferret"][rng.randi() % 2] if home != Biome.MARSH else "ferret", home))
	for i in rng.randi_range(2, 3):
		species.append(_make_bird(rng))
	species.append(_make_cave_beast())   # after the others, so every older species keeps its number
	_more_fauna()                        # and the bigger menagerie after that (its own random numbers)


func by_role(role: String) -> Array[Species]:
	var out: Array[Species] = []
	for s in species:
		if s.role == role:
			out.append(s)
	return out


## Coat colors: earthy on normal worlds, anything goes on exotic ones.
func _coat(rng: RandomNumberGenerator) -> Color:
	if _pal.exotic:
		return Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.7), rng.randf_range(0.45, 0.85))
	# Natural worlds: browns, tans, greys and the odd muted color.
	if rng.randf() < 0.15:
		return Color.from_hsv(0.08, rng.randf_range(0.0, 0.08), rng.randf_range(0.4, 0.85))   # greys/whites
	var hue := rng.randf_range(0.03, 0.12) if rng.randf() < 0.9 else rng.randf_range(0.0, 1.0)
	var sat := rng.randf_range(0.25, 0.6) if hue < 0.13 else rng.randf_range(0.15, 0.3)
	return Color.from_hsv(hue, sat, rng.randf_range(0.35, 0.8))


## A coat that fits the biome (natural worlds); exotic worlds keep their strange colors.
## The beast of the deep chambers: pale-eyed and dark, with faintly glowing markings, hardier and harder-hitting
## than anything on the surface. It lives only in caves (CAVE_HOME), guarding the chambers it lairs in.
const CAVE_HOME := -2
const CAVE_TRAITS := {"coat": "cave", "fur": true, "size": 1.15, "patterns": ["stripes", "spots"], "hp": 1.6, "night": 1.0,
	"habitat": "cave", "ears": "small", "words": ["Gloom", "Hollow", "Deep"]}


func _make_cave_beast() -> Species:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "cave beast"])
	var s := _make_quadruped(rng, "boar" if rng.randf() < 0.5 else "horned", CAVE_HOME)
	s.biome_pref = {}
	s.label = "Cave beast"
	s.damage *= 1.25
	s.herd = Vector2i(1, 1)
	s.yield_scale *= 1.4
	return s


func _biome_coat(rng: RandomNumberGenerator, scheme: String) -> Color:
	var c := _natural_coat(rng, scheme)
	# Exotic worlds keep the biome's light/dark and saturation, but in the world's strange hue.
	if _pal.exotic and scheme not in ["snow", "fungal", "cave"]:
		c = Color.from_hsv(fposmod(c.h + _exotic_shift, 1.0), minf(c.s * 1.25 + 0.1, 1.0), c.v)
	return c


func _natural_coat(rng: RandomNumberGenerator, scheme: String) -> Color:
	match scheme:
		"dark": return Color.from_hsv(rng.randf_range(0.05, 0.1), rng.randf_range(0.3, 0.5), rng.randf_range(0.28, 0.45))
		"russet": return Color.from_hsv(rng.randf_range(0.02, 0.06), rng.randf_range(0.5, 0.7), rng.randf_range(0.5, 0.7))
		"tan": return Color.from_hsv(rng.randf_range(0.08, 0.12), rng.randf_range(0.35, 0.55), rng.randf_range(0.65, 0.8))
		"sand": return Color.from_hsv(rng.randf_range(0.09, 0.12), rng.randf_range(0.2, 0.35), rng.randf_range(0.78, 0.9))
		"olive": return Color.from_hsv(rng.randf_range(0.12, 0.2), rng.randf_range(0.25, 0.4), rng.randf_range(0.35, 0.5))
		"vivid": return Color.from_hsv(rng.randf_range(0.0, 0.12) if rng.randf() < 0.6 else rng.randf(), rng.randf_range(0.55, 0.8), rng.randf_range(0.6, 0.85))
		"snow": return Color.from_hsv(rng.randf_range(0.08, 0.6), rng.randf_range(0.0, 0.07), rng.randf_range(0.82, 0.95))
		"rust": return Color.from_hsv(rng.randf_range(0.02, 0.06), rng.randf_range(0.5, 0.7), rng.randf_range(0.45, 0.62))
		"fungal": return _pal.fungal_caps[rng.randi() % _pal.fungal_caps.size()].lerp(Color(0.85, 0.85, 0.9), 0.35)
		"stone": return Color.from_hsv(rng.randf_range(0.06, 0.12), rng.randf_range(0.05, 0.18), rng.randf_range(0.5, 0.7))
		"cave": return Color.from_hsv(rng.randf_range(0.55, 0.68), rng.randf_range(0.08, 0.18), rng.randf_range(0.26, 0.36))
	return _coat(rng)


func _make_quadruped(rng: RandomNumberGenerator, arch: String, home := -1, look := {}) -> Species:
	var a: Dictionary = ARCHETYPES[arch]
	var role: String = a.role
	var tr: Dictionary = CAVE_TRAITS if home == CAVE_HOME else BIOME_TRAITS.get(home, {})
	if not look.is_empty():   # the new animals: their own coat, not just their biome's
		tr = tr.duplicate()
		tr.merge(look, true)
	var s := Species.new()
	s.role = role
	s.home = home
	s.label = ROLE_LABELS[role]
	if home >= 0:
		s.label = "%s %s" % [WorldGen.BIOME_NAMES[home], {"grazer": "grazer", "defensive": "beast", "critter": "critter", "small": "creature"}[role]]
	s.id = "%s_%d" % [arch, species.size()]
	var size := rng.randf_range(a.size[0], a.size[1]) * float(tr.get("size", 1.0))
	s.size = size
	s.name = NameGen.species_name(rng, role)
	if tr.has("words") and rng.randf() < 0.6:
		var words: Array = tr.words
		s.name = "%s %s" % [words[rng.randi() % words.size()], s.name.get_slice(" ", 1)]
	if home >= 0:
		# Lives in its home biome; strays a little into the others.
		s.biome_pref[home] = 1.0
		if home == Biome.HIGHLANDS:
			s.biome_pref[Biome.SNOW] = 0.6
		if home == Biome.TUNDRA:
			s.biome_pref[Biome.SNOW] = 0.8
	else:
		for b: int in a.biomes:
			s.biome_pref[b] = a.biomes[b] * rng.randf_range(0.7, 1.0)
	s.habitat = tr.get("habitat", "")
	if rng.randf() < float(tr.get("night", 0.0)):
		s.active = "night"
	elif role == "grazer" and rng.randf() < 0.2:
		s.active = "day"

	# --- Proportions ---
	var stocky := role == "defensive" or arch == "bulky"
	s.body_h = size * rng.randf_range(a.body_h[0], a.body_h[1])
	s.body_len = s.body_h * rng.randf_range(1.9, 2.5)
	if arch == "strider":
		s.body_len = s.body_h * 1.4
	elif arch == "ferret":
		s.body_len = s.body_h * 2.9
	elif arch == "shellback":
		s.body_len = s.body_h * 2.1
	elif arch == "lizard":
		s.body_len = s.body_h * 3.0
	elif arch == "otter":
		s.body_len = s.body_h * 3.1
	elif arch == "monkey":
		s.body_len = s.body_h * 1.55
	elif arch == "heron":
		s.body_len = s.body_h * 1.6
	elif arch in ["feline", "canine"]:
		s.body_len = s.body_h * rng.randf_range(2.3, 2.6)
	s.body_w = s.body_h * rng.randf_range(0.75, 0.95) * float(tr.get("width", 1.0))
	s.leg_len = size * rng.randf_range(a.leg[0], a.leg[1]) * float(tr.get("leg", 1.0))
	var leg_r := size * (0.085 if stocky else 0.07) * rng.randf_range(0.9, 1.15)
	if arch in ["wader", "strider"]:
		leg_r *= 0.7
	elif arch == "heron":
		leg_r *= 0.45   # stilts
	var neck_len := size * rng.randf_range(a.neck[0], a.neck[1])
	var neck_angle := deg_to_rad(rng.randf_range(a.angle[0], a.angle[1]))
	var head_len := size * rng.randf_range(0.34, 0.46) * (0.7 if arch in ["strider", "wader", "shellback", "heron"] else 1.0)
	if arch == "lizard":
		head_len *= 1.3

	# --- Behavior ---
	match role:
		"grazer":
			s.hp = 25.0 * pow(size, 1.6) + 10.0
			s.walk_speed = 1.2 + size * 0.4
			s.run_speed = 6.0 + size * 2.0
			s.flee_radius = rng.randf_range(11.0, 18.0)
			s.herd = Vector2i(1, 3) if size > 1.3 else Vector2i(2, 5)
			s.yield_scale = size
			if arch == "shellback":   # slow and tough
				s.hp *= 2.0
				s.walk_speed = 0.6
				s.run_speed = 1.8
				s.flee_radius = 6.0
			elif arch == "strider":
				s.run_speed += 2.5
		"defensive":
			s.hp = 70.0 * size
			s.walk_speed = 1.1
			s.run_speed = 6.5
			s.flee_radius = 0.0
			s.damage = rng.randf_range(10.0, 15.0) * (1.25 if arch == "horned" else 1.0)
			s.herd = Vector2i(1, 2)
			s.yield_scale = 1.2 * size
		"critter":
			s.hp = 5.0
			s.walk_speed = 1.0
			s.run_speed = 5.0
			s.flee_radius = 7.0
			s.herd = Vector2i(1, 1)
			s.yield_scale = 0.2
		"small":
			s.hp = 8.0
			s.walk_speed = 0.8
			s.run_speed = 5.0
			s.flee_radius = 6.0
			s.herd = Vector2i(1, 2)
			s.yield_scale = 0.3
	match arch:
		"canine":
			s.run_speed += 2.0
			s.herd = Vector2i(1, 2)
		"monkey":
			s.herd = Vector2i(3, 6)
			s.hp *= 0.7
		"otter":
			s.herd = Vector2i(1, 3)
			s.run_speed = 4.0
		"heron":
			s.herd = Vector2i(1, 1)
		"lizard":
			s.run_speed = 6.5   # a dart for cover
		"feline":
			s.run_speed = 8.5
			s.damage *= 1.1
			s.herd = Vector2i(1, 1)

	# Biome adaptations: hardier in the cold and badlands, faster on the plains and in the jungle.
	s.hp *= float(tr.get("hp", 1.0))
	s.run_speed *= float(tr.get("speed", 1.0))
	s.walk_speed *= float(tr.get("speed", 1.0))

	# Temperament decides how close you can get before it reacts.
	s.temperament = {"slender": "skittish", "stocky": "wary", "bulky": "calm", "shellback": "calm", "strider": "wary",
		"wader": "wary", "boar": "wary", "horned": "calm", "hopper": "skittish", "ferret": "curious",
		"feline": "calm", "canine": "wary", "otter": "curious", "lizard": "skittish", "monkey": "skittish", "heron": "wary"}[arch]
	if role == "grazer" and rng.randf() < 0.25 and arch in ["slender", "stocky", "bulky", "shellback", "strider", "wader"]:
		s.temperament = "curious"
	if role == "grazer" and tr.get("skittish", false):
		s.temperament = "skittish"
	if role != "defensive" and tr.get("curious", false):
		s.temperament = "curious"
	if role != "defensive":
		s.flee_radius = {"skittish": rng.randf_range(16.0, 22.0), "wary": rng.randf_range(10.0, 14.0),
			"calm": rng.randf_range(5.0, 7.0), "curious": rng.randf_range(6.0, 8.0)}[s.temperament]

	# --- Colors & pattern ---
	var coat := _biome_coat(rng, tr.get("coat", ""))
	var belly := coat.lightened(rng.randf_range(0.25, 0.45))
	var accent := coat.darkened(rng.randf_range(0.3, 0.5)) if rng.randf() < 0.7 else coat.lightened(0.5)
	var pattern: String = ["none", "stripes", "spots", "saddle", "none", "rosettes", "dorsal"][rng.randi() % 7]
	if tr.has("patterns"):
		var pats: Array = tr.patterns
		pattern = pats[rng.randi() % pats.size()]
		# Now and then a pattern outside the biome's usual (rosettes for the spotted, a back stripe for the plain).
		if pattern == "spots" and rng.randf() < 0.4:
			pattern = "rosettes"
		elif pattern == "none" and rng.randf() < 0.35:
			pattern = "dorsal"
	match String(tr.get("coat", "")):
		"vivid": accent = Color.from_hsv(fposmod(coat.h + 0.5, 1.0), 0.3, 0.15) if rng.randf() < 0.5 else coat.darkened(0.6)   # bold markings
		"fungal", "cave": accent = _pal.glow   # glowing spots
		"snow": accent = coat.darkened(0.2)
		"rust": accent = _pal.badlands_cream
	var fur: bool = tr.get("fur", false)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 3.5 / size
	var warp := FastNoiseLite.new()   # bends stripes and blurs edges, so markings look grown, not ruled
	warp.seed = rng.randi()
	warp.frequency = 2.0 / size
	var stripe_f := rng.randf_range(9.0, 16.0) / size
	var body_h := s.body_h
	# Countershading: darker along the back, shading to the pale belly (a soft blend, not a line).
	var back_col := coat.darkened(rng.randf_range(0.08, 0.18))
	var coat_fn := func(p: Vector3) -> Color:
		var wob := warp.get_noise_3dv(p)
		var c := coat.lerp(back_col, smoothstep(0.0, body_h * 0.4, p.y) * 0.8)
		var mark := 0.0
		match pattern:
			"stripes":   # wavering bands round the body, fading out low on the flanks
				var band := sin(p.z * stripe_f + p.y * 3.0 + wob * 3.0)
				mark = smoothstep(0.3, 0.6, band) * smoothstep(-body_h * 0.25, body_h * 0.05, p.y)
			"spots":
				mark = smoothstep(0.24, 0.36, noise.get_noise_3dv(p) + wob * 0.1)
			"rosettes":   # rings: dark rims round coat-coloured middles
				var n := noise.get_noise_3dv(p)
				mark = smoothstep(0.18, 0.26, n) * (1.0 - smoothstep(0.34, 0.42, n)) * smoothstep(-body_h * 0.3, 0.0, p.y)
			"saddle":
				mark = smoothstep(body_h * 0.08, body_h * 0.28, p.y + wob * body_h * 0.15)
			"dorsal":   # a dark stripe along the spine
				mark = 1.0 - smoothstep(body_h * 0.06, body_h * 0.14, absf(p.x) + wob * body_h * 0.03)
				mark *= smoothstep(body_h * 0.1, body_h * 0.3, p.y)
		c = c.lerp(accent, clampf(mark, 0.0, 1.0))
		c = c.lerp(belly, smoothstep(-body_h * 0.08, -body_h * 0.3, p.y + wob * body_h * 0.06) * 0.85)
		return c

	# --- Body: one continuous lofted torso (rump, waist, ribcage, shoulders) ---
	var kit := MeshKit.new(rng.randi())
	var L := s.body_len
	var H := s.body_h
	var W := s.body_w
	var chest := Vector3(0, H * 0.06, -L * 0.2)
	var hips := Vector3(0, H * 0.02, L * 0.24)
	var hump_h := (0.22 if arch == "bulky" else (0.1 if stocky else 0.0)) * H
	var torso: Array = []
	var torso_r: Array = []
	# Radius profile from rump (t=0) to the base of the neck (t=1).
	# A round rump, a waist tucked in behind the ribs, a deep chest and the shoulders: an animal, not a loaf.
	var profile := [0.5, 0.86, 0.93, 0.8, 0.84, 0.98, 1.03, 0.9, 0.62]
	for i in profile.size():
		var t := float(i) / (profile.size() - 1)
		var z := lerpf(L * 0.5, -L * 0.5, t)
		# The back dips a little behind the shoulders, and the chest hangs lower than the belly.
		var y := sin(t * PI) * H * 0.04 + hump_h * exp(-pow((t - 0.72) / 0.16, 2.0)) - H * 0.05 * exp(-pow((t - 0.42) / 0.14, 2.0)) \
			- H * 0.05 * exp(-pow((t - 0.72) / 0.12, 2.0))
		torso.append(Vector3(0, y, z))
		torso_r.append(H * 0.5 * float(profile[i]) * (1.0 + hump_h / H * exp(-pow((t - 0.72) / 0.16, 2.0))))
	var w_ratio := W / H
	var torso_coat := func(t: float, a: float) -> Color:
		# Rebuild an approximate body-space point so the coat pattern lines up.
		return coat_fn.call(Vector3(-sin(a) * W * 0.5, -cos(a) * H * 0.5, lerpf(L * 0.5, -L * 0.5, t)))
	var torso_bumps := 0.012 if arch == "bulky" else 0.0
	if fur:
		torso_bumps = maxf(torso_bumps, H * 0.05)   # thick shaggy winter coat
	kit.loft(torso, torso_r, 18, coat, torso_coat, func(t: float, a: float) -> Vector2: return Vector2(1.0, w_ratio), true, true, torso_bumps)
	if arch == "bulky" or (fur and role != "critter" and arch != "shellback"):   # shaggy chest ruff
		kit.loft([chest + Vector3(0, -H * 0.1, -L * 0.1), chest + Vector3(0, -H * 0.35, -L * 0.2), chest + Vector3(0, -H * 0.55, -L * 0.18)], [H * 0.35, H * 0.3, H * 0.12], 10, accent.lerp(coat, 0.5), Callable(), Callable(), true, true, 0.03)
	if arch == "shellback":
		var shell := accent.lerp(coat, 0.35)
		var plates := func(p: Vector3) -> Color:
			return shell.darkened(0.25) if sin(p.x * 18.0 / size) * sin(p.z * 18.0 / size) > 0.55 else shell
		kit.add_primitive(MeshKit.sphere(0.5, 16, 9), Transform3D(Basis.from_scale(Vector3(W * 1.4, H * 1.15, L * 1.12)), Vector3(0, H * 0.3, 0)), shell, 0.0, 0.03, null, plates)
		# The shell's rim: a rounded lip following its edge all the way round, at its widest (it was a flat plate
		# below the shell, poking out under the body like a sheet).
		var rim: Array = []
		var rim_r: Array = []
		for i in 24:
			var ang := TAU * i / 24.0
			rim.append(Vector3(cos(ang) * W * 0.69, H * 0.3, sin(ang) * L * 0.55))
			rim_r.append(H * 0.07)
		kit.loft(rim, rim_r, 8, shell.darkened(0.15), Callable(), func(_t: float, _a: float) -> Vector2: return Vector2(0.6, 1.0), false, false, 0.0, true)
	# Tail: a lofted curve from the rump, built on its own (so it can swish) and joined back on at its root.
	var tail_len := size * rng.randf_range(0.18, 0.45)
	var tail_root: Vector3 = torso[0] + Vector3(0, H * 0.2, -L * 0.02)
	var body_kit := kit
	kit = MeshKit.new(hash([s.id, "tail"]))
	if arch == "ferret":
		tail_len = L * 0.85
	if arch == "feline":
		tail_len = L * 0.95
	elif arch == "canine":
		tail_len = L * 0.6
	elif arch == "otter":
		tail_len = L * 0.6
	elif arch == "lizard":
		tail_len = L * 1.25
	elif arch == "monkey":
		tail_len = L * 1.7
	if arch in ["lizard", "otter"]:
		# A thick-rooted tail tapering to a point, held low (dragged, or a rudder).
		var tp2 := [tail_root - Vector3(0, H * 0.25, 0), tail_root + Vector3(0, -H * 0.32, tail_len * 0.35), tail_root + Vector3(0, -H * 0.38, tail_len * 0.7), tail_root + Vector3(0, -H * 0.4, tail_len)]
		kit.loft(tp2, [H * 0.32, H * 0.22, H * 0.12, H * 0.02], 8, coat, func(t: float, a2: float) -> Color: return coat_fn.call(Vector3(-sin(a2) * H * 0.2, -cos(a2) * H * 0.2, L * 0.5 + t * tail_len)))
	elif arch == "monkey":
		# A long tail curling up into a loop at the end.
		var tp3: Array = []
		var tr3: Array = []
		for i in 9:
			var t := i / 8.0
			var curl := maxf(t - 0.55, 0.0) / 0.45
			tp3.append(tail_root + Vector3(0, -tail_len * 0.25 * sin(t * PI * 0.6) + sin(curl * PI * 1.4) * tail_len * 0.18, tail_len * (t * 0.8 - (1.0 - cos(curl * PI * 1.4)) * 0.1)))
			tr3.append(size * lerpf(0.035, 0.015, t))
		kit.loft(tp3, tr3, 6, coat)
	elif arch == "canine":
		# A bushy brush, light at the tip.
		var tp4 := [tail_root, tail_root + Vector3(0, -tail_len * 0.3, tail_len * 0.35), tail_root + Vector3(0, -tail_len * 0.55, tail_len * 0.7), tail_root + Vector3(0, -tail_len * 0.62, tail_len * 0.95)]
		kit.loft(tp4, [size * 0.05, size * 0.09, size * 0.08, size * 0.02], 9, coat, func(t: float, _a: float) -> Color: return belly if t > 0.75 else coat, Callable(), true, true, size * 0.01)
	elif arch == "strider":
		for i in 5:   # fan of tail plumes
			var tb := Basis(Vector3.UP, (i - 2) * 0.3) * Basis(Vector3.RIGHT, deg_to_rad(-125))
			var tip := tail_root + tb.y * size * 0.35
			kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(size * 0.06, size * 0.15), Vector2(0, size * 0.36), Vector2(-size * 0.06, size * 0.15)]),
				Transform3D(tb, tail_root), size * 0.02, size * 0.01, accent, accent.lightened(0.2), 0.4)
	elif role == "critter" and arch != "ferret":
		kit.add_primitive(MeshKit.sphere(size * 0.13, 9, 6), Transform3D(Basis(), tail_root), belly, 0.04, 0.05)   # puff tail
	elif arch != "shellback" and arch != "heron":
		var droop := 0.9 if arch != "ferret" else 0.35
		if arch == "feline":
			droop = 0.55
		var tp := [tail_root, tail_root + Vector3(0, -tail_len * 0.25 * droop, tail_len * 0.4), tail_root + Vector3(0, -tail_len * 0.75 * droop, tail_len * 0.65), tail_root + Vector3(0, -tail_len * droop, tail_len * 0.72)]
		kit.loft(tp, [size * 0.05, size * 0.04, size * 0.028, size * 0.012], 7, coat, func(t: float, a: float) -> Color: return accent if t > 0.7 else coat)
		if tail_len > size * 0.3 and arch != "ferret":
			kit.add_primitive(MeshKit.sphere(size * 0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1.7, 1)), tp[3]), accent, 0.05, 0.04)
	if kit.verts.size() > 0:
		s.tail_mesh = _shifted(kit.commit(material), -tail_root)
		s.tail_pivot = tail_root
	kit = body_kit
	s.body_mesh = kit.commit(material)

	# --- Head & neck: a tapering lofted neck rising from the chest, a lofted skull-to-nose head ---
	s.head_pivot = chest + Vector3(0, H * 0.2, -L * 0.18)
	kit = MeshKit.new(rng.randi())
	var neck_dir := Vector3(0, sin(neck_angle), -cos(neck_angle))
	var neck_r := H * (0.4 if stocky else 0.3)
	var neck_end := neck_dir * neck_len
	var neck_path := [-neck_dir * neck_r * 0.6, neck_dir * neck_len * 0.35, neck_dir * neck_len * 0.75, neck_end]
	kit.loft(neck_path, [neck_r * 1.1, neck_r * 0.92, neck_r * 0.78, neck_r * 0.72], 12, coat,
		func(t: float, a: float) -> Color: return coat_fn.call(Vector3(-sin(a) * neck_r, -cos(a) * neck_r + H * 0.3, 0.0)),
		func(t: float, a: float) -> Vector2: return Vector2(1.0, 0.85))
	# Negative = nose tipped down (heads carried forward, not gazing at the sky).
	var head_tilt := Basis(Vector3.RIGHT, deg_to_rad(-rng.randf_range(8.0, 22.0)))
	var fwd := head_tilt * Vector3(0, 0, -1)
	var up := head_tilt * Vector3(0, 1, 0)
	var snout_len := head_len * rng.randf_range(0.5, 0.75)
	if arch == "wader":
		snout_len = head_len * 1.2   # long bill
	elif arch == "strider":
		snout_len = head_len * 0.5
	elif arch in ["boar", "shellback"]:
		snout_len = head_len * 0.45
	elif arch == "feline":
		snout_len = head_len * 0.3
	elif arch == "canine":
		snout_len = head_len * 0.9
	elif arch == "monkey":
		snout_len = head_len * 0.22
	elif arch == "lizard":
		snout_len = head_len * 0.55
	elif arch == "heron":
		snout_len = head_len * 1.6   # dagger bill
	var bill := arch in ["wader", "strider", "heron"]
	var back := neck_end + up * head_len * 0.05 - fwd * head_len * 0.15
	var skull := back + fwd * head_len * 0.35
	var nose := skull + fwd * (head_len * 0.3 + snout_len) - up * head_len * 0.12
	var head_path := [back, skull, skull + fwd * head_len * 0.25 - up * head_len * 0.04, nose]
	var head_r := [head_len * 0.3, head_len * 0.36, head_len * 0.27, head_len * (0.08 if bill else (0.1 if arch == "canine" else 0.18))]
	if arch == "lizard":
		head_r = [head_len * 0.26, head_len * 0.3, head_len * 0.24, head_len * 0.14]
	var muzzle := belly.lerp(coat, 0.5)
	kit.loft(head_path, head_r, 12, coat, func(t: float, a: float) -> Color:
		return muzzle if t > 0.6 else coat,
		func(t: float, a: float) -> Vector2: return Vector2(0.85, 1.0), true, true)
	if bill:
		kit.loft([skull + fwd * head_len * 0.3, nose + fwd * snout_len * 0.2], [head_len * 0.09, head_len * 0.02], 7, Color(0.86, 0.66, 0.32))
	else:
		kit.add_primitive(MeshKit.sphere(head_len * 0.1, 8, 6), Transform3D(Basis.from_scale(Vector3(1.25, 0.8, 0.7)), nose + fwd * head_len * 0.06), Color(0.14, 0.11, 0.1), 0.0, 0.0)   # nose pad
	for side in [-1.0, 1.0]:
		var eye := skull + Vector3(side * head_len * 0.27, 0, 0) + up * head_len * 0.08 + fwd * head_len * 0.05
		kit.add_primitive(MeshKit.sphere(head_len * 0.075, 9, 6), Transform3D(Basis(), eye), Color(0.07, 0.05, 0.04), 0.0, 0.0)
		kit.add_primitive(MeshKit.sphere(head_len * 0.025, 6, 4), Transform3D(Basis(), eye + Vector3(side * head_len * 0.03, head_len * 0.035, 0) + fwd * head_len * 0.03), Color(1, 1, 1), 0.0, 0.0)   # glint
	if arch == "monkey":
		# A pale bare face and round ears out to the sides.
		kit.add_primitive(MeshKit.sphere(head_len * 0.3, 10, 7), Transform3D(Basis.from_scale(Vector3(1.0, 1.1, 0.45)), skull + fwd * head_len * 0.22), Color(0.85, 0.7, 0.6).lerp(coat, 0.25), 0.0, 0.03)
		for side in [-1.0, 1.0]:
			kit.add_primitive(MeshKit.sphere(head_len * 0.14, 8, 5), Transform3D(Basis.from_scale(Vector3(0.45, 1, 1)), skull + Vector3(side * head_len * 0.36, head_len * 0.05, 0)), coat.darkened(0.1), 0.0, 0.03)
	elif arch == "canine":
		for side in [-1.0, 1.0]:   # tall pointed ears
			var eb := Basis(Vector3.FORWARD, side * deg_to_rad(-18))
			kit.add_primitive(MeshKit.cylinder(0.0, head_len * 0.16, head_len * 0.5, 4), Transform3D(eb, skull - fwd * head_len * 0.05 + Vector3(side * head_len * 0.2, head_len * 0.35, 0) + eb.y * head_len * 0.2), coat, 0.0, 0.03)
	elif arch == "feline":
		for side in [-1.0, 1.0]:   # short rounded-triangle ears
			var eb := Basis(Vector3.FORWARD, side * deg_to_rad(-25))
			kit.add_primitive(MeshKit.cylinder(head_len * 0.02, head_len * 0.15, head_len * 0.26, 5), Transform3D(eb, skull - fwd * head_len * 0.08 + Vector3(side * head_len * 0.24, head_len * 0.3, 0) + eb.y * head_len * 0.1), coat, 0.0, 0.03)
	elif arch == "heron":
		kit.loft([skull - fwd * head_len * 0.2, skull - fwd * head_len * 0.6 - up * head_len * 0.1], [head_len * 0.06, head_len * 0.01], 4, accent)   # a crest plume
	elif not arch in ["shellback", "strider", "wader", "lizard", "otter"]:
		_ears(kit, rng, role, skull - fwd * head_len * 0.1, head_len, coat, belly, tr.get("ears", ""))
	elif arch == "otter":
		for side in [-1.0, 1.0]:
			kit.add_primitive(MeshKit.sphere(head_len * 0.08, 6, 4), Transform3D(Basis(), skull + Vector3(side * head_len * 0.28, head_len * 0.18, head_len * 0.02)), coat, 0.0, 0.03)
	_horns(kit, rng, arch, skull - fwd * head_len * 0.1, head_len, size, nose)
	s.head_mesh = kit.commit(material)

	# --- Legs: jointed. Front legs nearly straight; hind legs bend back at the hock. ---
	var thigh_col := coat
	var shin_col := coat.lerp(accent, 0.35)
	var hoof := Color(0.16, 0.13, 0.11)
	if arch in ["feline", "canine", "otter", "lizard", "monkey"]:
		hoof = shin_col.darkened(0.25)   # paws, not hooves
	elif arch == "heron":
		hoof = Color(0.3, 0.26, 0.2)
	var ll := s.leg_len
	kit = MeshKit.new(rng.randi())
	# The shoulder: a big muscle that runs up into the body's side (so the leg grows out of it, not pinned on).
	var bulk := 0.85 if arch in ["heron", "wader", "strider"] else 1.0
	kit.add_primitive(MeshKit.sphere(leg_r * 1.45 * bulk, 10, 7), Transform3D(Basis.from_scale(Vector3(0.7, 1.7, 1.05)), Vector3(0, leg_r * 0.6, 0)), thigh_col, 0.0, 0.04, null, coat_fn)
	var knee := Vector3(0, -ll * 0.5, -ll * 0.04)
	_segment(kit, Vector3(0, -leg_r, 0), knee, leg_r * 1.35, leg_r, thigh_col, Callable())
	_segment(kit, knee, Vector3(0, -ll + leg_r * 0.5, 0), leg_r, leg_r * 0.72, shin_col, Callable())
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.85, leg_r * 0.95, leg_r * 1.3, 8), Transform3D(Basis(), Vector3(0, -ll + leg_r * 0.55, -leg_r * 0.1)), hoof, 0.0, 0.0)
	s.leg_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	# The haunch: the hind leg's big rounded thigh, running up into the rump.
	kit.add_primitive(MeshKit.sphere(leg_r * 1.7 * bulk, 10, 7), Transform3D(Basis.from_scale(Vector3(0.7, 1.65, 1.2)), Vector3(0, leg_r * 0.6, leg_r * 0.15)), thigh_col, 0.0, 0.04, null, coat_fn)
	var stifle := Vector3(0, -ll * 0.4, -ll * 0.1)
	var hock := Vector3(0, -ll * 0.68, ll * 0.1)
	_segment(kit, Vector3(0, -leg_r, 0), stifle, leg_r * 1.6, leg_r * 1.1, thigh_col, Callable())
	_segment(kit, stifle, hock, leg_r * 1.05, leg_r * 0.8, shin_col, Callable())
	_segment(kit, hock, Vector3(0, -ll + leg_r * 0.5, ll * 0.02), leg_r * 0.8, leg_r * 0.7, shin_col, Callable())
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.8, leg_r * 0.9, leg_r * 1.3, 8), Transform3D(Basis(), Vector3(0, -ll + leg_r * 0.55, 0)), hoof, 0.0, 0.0)
	s.hind_leg_mesh = kit.commit(material)
	var lx := W * (0.62 if arch == "lizard" else 0.32)
	var ly := -H * 0.25
	s.leg_offsets = [Vector3(-lx, ly, chest.z - L * 0.05), Vector3(lx, ly, chest.z - L * 0.05), Vector3(-lx, ly, hips.z + L * 0.05), Vector3(lx, ly, hips.z + L * 0.05)]
	if a.legs == 2:
		s.leg_offsets = [Vector3(-lx, ly, 0), Vector3(lx, ly, 0)]
		s.leg_mesh = s.hind_leg_mesh

	s.call_sound = SoundGen.creature_call(role, size, rng)
	match arch:
		"feline":
			s.diet = "carn"
		"canine":
			s.diet = "carn"
			s.call_sound = SoundGen.creature_call("bark", size, rng)
		"otter":
			s.diet = "carn"
			s.swims = true
			s.habitat = "water"
			s.call_sound = SoundGen.creature_call("critter", size, rng)
		"lizard":
			s.body = "sprawl"
			s.diet = "carn"
			s.call_sound = SoundGen.creature_call("hiss", size, rng)
		"monkey":
			s.diet = "omni"
			s.climbs = true
			s.call_sound = SoundGen.creature_call("chatter", size, rng)
		"heron":
			s.diet = "carn"
			s.habitat = "water"
			s.call_sound = SoundGen.creature_call("squawk", size, rng)
	return s


## A tapered limb/neck segment between two points (joint spheres keep it smooth).
## The same mesh moved by `offset` (a part built in the body's space, re-centred on its own pivot).
static func _shifted(mesh: ArrayMesh, offset: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for si in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(si)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] += offset
		arrays[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(si, mesh.surface_get_material(si))
	return out


func _segment(kit: MeshKit, a: Vector3, b: Vector3, ra: float, rb: float, col: Color, color_fn: Callable) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var basis := Basis(Quaternion(Vector3.UP, d / length))
	kit.add_primitive(MeshKit.cylinder(rb, ra, length, 9), Transform3D(basis, (a + b) * 0.5), col, 0.0, 0.04, null, color_fn)
	kit.add_primitive(MeshKit.sphere(rb, 8, 5), Transform3D(Basis(), b), col, 0.0, 0.04, null, color_fn)


func _ears(kit: MeshKit, rng: RandomNumberGenerator, role: String, head_c: Vector3, head_len: float, coat: Color, inner: Color, size_hint := "") -> void:
	var style: String = "long" if role == "critter" and rng.randf() < 0.6 else ["pointy", "round", "long", "pointy"][rng.randi() % 4]
	if size_hint == "small":
		style = "round"   # cold climates: small round ears lose less heat
	var length := head_len * (0.9 if style == "long" else 0.4)
	if size_hint == "big":
		length *= 1.6     # desert: big ears shed heat (and hear predators)
	for side in [-1.0, 1.0]:
		var base := head_c + Vector3(side * head_len * 0.22, head_len * 0.25, head_len * 0.15)
		var tilt := Basis(Vector3.FORWARD, side * deg_to_rad(rng.randf_range(20, 45))) * Basis(Vector3.RIGHT, deg_to_rad(15))
		if style == "round":
			kit.add_primitive(MeshKit.sphere(head_len * 0.16, 8, 5), Transform3D(tilt * Basis.from_scale(Vector3(1, 1, 0.4)), base + tilt.y * head_len * 0.12), coat, 0.0, 0.04)
		else:
			kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(tilt * Basis.from_scale(Vector3(head_len * 0.16, length, head_len * 0.07)), base + tilt.y * length * 0.45), coat, 0.0, 0.04,
				null, func(p: Vector3) -> Color: return inner if p.z < base.z - head_len * 0.01 else coat)


func _horns(kit: MeshKit, rng: RandomNumberGenerator, arch: String, head_c: Vector3, head_len: float, size: float, snout_c: Vector3) -> void:
	var horn_col := Color.from_hsv(rng.randf_range(0.08, 0.12), 0.2, rng.randf_range(0.7, 0.9))
	if arch in ["shellback", "strider", "wader", "hopper", "ferret", "feline", "canine", "otter", "lizard", "monkey", "heron"]:
		return
	if arch == "horned":
		# Big forward-sweeping horns.
		for side in [-1.0, 1.0]:
			var pos := head_c + Vector3(side * head_len * 0.25, head_len * 0.25, head_len * 0.05)
			var dir := Vector3(side, 0.35, -0.1).normalized()
			var r := head_len * 0.14
			for seg in 6:
				var seg_len := head_len * 0.26
				kit.add_primitive(MeshKit.cylinder(r * 0.8, r, seg_len, 8), Transform3D(Basis(Quaternion(Vector3.UP, dir)), pos + dir * seg_len * 0.5), horn_col, 0.0, 0.03)
				pos += dir * seg_len * 0.9
				dir = (dir + Vector3(-side * 0.25, 0.15, -0.35)).normalized()
				r *= 0.8
		return
	if arch == "boar":
		# Tusks curving up from the snout.
		for side in [-1.0, 1.0]:
			var b := Basis(Vector3.FORWARD, side * deg_to_rad(-25)) * Basis(Vector3.RIGHT, deg_to_rad(-35))
			var length := head_len * rng.randf_range(0.45, 0.7)
			kit.add_primitive(MeshKit.cylinder(0.0, head_len * 0.06, length, 7), Transform3D(b, snout_c + Vector3(side * head_len * 0.15, 0, 0) + b.y * length * 0.45), horn_col, 0.0, 0.03)
		return
	if rng.randf() < 0.3 and arch != "bulky":
		return
	var style: String = ["straight", "curved", "antlers"][rng.randi() % 3]
	if arch == "bulky":
		style = "antlers" if rng.randf() < 0.6 else "curved"
	elif arch == "slender":
		style = "straight" if rng.randf() < 0.5 else "curved"
	for side in [-1.0, 1.0]:
		var root := head_c + Vector3(side * head_len * 0.15, head_len * 0.3, head_len * 0.05)
		match style:
			"straight":
				var b := Basis(Vector3.FORWARD, side * deg_to_rad(-15)) * Basis(Vector3.RIGHT, deg_to_rad(35))
				var length := head_len * rng.randf_range(0.6, 1.0)
				kit.add_primitive(MeshKit.cylinder(head_len * 0.015, head_len * 0.1, length, 8), Transform3D(b, root + b.y * length * 0.5), horn_col, 0.0, 0.03)
			"curved":
				var pos := root
				var dir := Vector3(side * 0.4, 1.0, 0.3).normalized()
				var r := head_len * 0.1
				for seg in 5:
					var seg_len := head_len * 0.22
					var b := Basis(Quaternion(Vector3.UP, dir))
					kit.add_primitive(MeshKit.cylinder(r * 0.8, r, seg_len, 7), Transform3D(b, pos + dir * seg_len * 0.5), horn_col, 0.0, 0.03)
					pos += dir * seg_len * 0.9
					dir = (dir + Vector3(side * 0.2, -0.35, 0.45)).normalized()
					r *= 0.82
			"antlers":
				var b := Basis(Vector3.FORWARD, side * deg_to_rad(-30))
				var length := head_len * 1.2 * size
				var tip := root + b.y * length
				kit.add_primitive(MeshKit.cylinder(head_len * 0.03, head_len * 0.05, length, 6), Transform3D(b, root + b.y * length * 0.5), horn_col, 0.0, 0.03)
				for t in rng.randi_range(2, 3):
					var start := root.lerp(tip, rng.randf_range(0.35, 0.9))
					var bd := Vector3(side * rng.randf_range(0.2, 0.7), rng.randf_range(0.4, 0.9), rng.randf_range(-0.6, 0.3)).normalized()
					var bl := length * rng.randf_range(0.3, 0.5)
					kit.add_primitive(MeshKit.cylinder(head_len * 0.015, head_len * 0.03, bl, 5), Transform3D(Basis(Quaternion(Vector3.UP, bd)), start + bd * bl * 0.5), horn_col, 0.0, 0.03)


func _make_bird(rng: RandomNumberGenerator) -> Species:
	var s := Species.new()
	s.role = "bird"
	s.label = ROLE_LABELS.bird
	s.id = "bird_%d" % species.size()
	s.name = NameGen.species_name(rng, "bird")
	s.size = rng.randf_range(0.18, 0.32)
	var main := _coat(rng) if rng.randf() < 0.5 else Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.5, 0.9))
	var wing_col := main.darkened(rng.randf_range(0.1, 0.35))
	var size := s.size
	var kit := MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(0.5, 10, 6), Transform3D(Basis().scaled(Vector3(size * 0.5, size * 0.45, size)), Vector3.ZERO), main, 0.0, 0.05)
	kit.add_primitive(MeshKit.sphere(size * 0.22, 9, 6), Transform3D(Basis(), Vector3(0, size * 0.18, -size * 0.5)), main.lightened(0.1), 0.0, 0.05)
	kit.add_primitive(MeshKit.cylinder(0.0, size * 0.06, size * 0.25, 6), Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, size * 0.16, -size * 0.75)), Color(0.9, 0.7, 0.3), 0.0, 0.0)
	kit.add_primitive(MeshKit.sphere(0.5, 8, 4), Transform3D(Basis().scaled(Vector3(size * 0.45, size * 0.06, size * 0.5)), Vector3(0, 0, size * 0.65)), wing_col, 0.0, 0.04)
	s.body_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	var span := size * rng.randf_range(1.0, 1.5)
	kit.add_primitive(MeshKit.sphere(0.5, 9, 4), Transform3D(Basis().scaled(Vector3(span, size * 0.05, size * 0.5)), Vector3(span * 0.5, 0, 0)), wing_col, 0.0, 0.05)
	s.wing_mesh = kit.commit(material)
	s.call_sound = SoundGen.creature_call("bird", size, rng)
	return s



# --- The bigger menagerie -----------------------------------------------------------------------------------------

## Jungle, tundra, river and desert animals, each made for its own biome, and birds that perch or soar. Each fills a
## niche (a climber, a stalker, a waddling swimmer, ...) but is made up fresh for every world like the others: its
## body, colours, markings and name. Drawn from their own random numbers, after every other species, so the animals
## older worlds already have stay as they were.
func _more_fauna() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "more fauna"])
	var add := func(sp: Species, prefs: Dictionary) -> void:
		for b: int in prefs:
			sp.biome_pref[b] = prefs[b]
		species.append(sp)
	var pick := func(list: Array) -> Variant: return list[rng.randi() % list.size()]
	# Jungle: tree climbers, a big stalker, a harmless serpent and a venomous one.
	add.call(_labelled(rng, _make_quadruped(rng, "monkey", Biome.JUNGLE, {"coat": pick.call(["dark", "russet", "stone", "tan", "olive"]), "patterns": pick.call([["none"], ["saddle"], ["stripes"], ["none", "saddle"]])}), ["climber", "canopy-leaper", "tree-runner"]), {})
	add.call(_labelled(rng, _make_quadruped(rng, "feline", Biome.JUNGLE, {"coat": pick.call(["tan", "dark", "russet", "vivid", "stone"]), "patterns": pick.call([["spots"], ["stripes"], ["none"], ["spots", "stripes"]])}), ["stalker", "prowler", "ambusher"]), {})
	add.call(_make_serpent(rng, false), {Biome.JUNGLE: 1.0, Biome.MARSH: 0.7, Biome.FOREST: 0.4, Biome.MEADOW: 0.3})
	add.call(_make_serpent(rng, true), {Biome.JUNGLE: 0.7, Biome.DESERT: 0.8, Biome.BADLANDS: 0.8, Biome.DRYLANDS: 0.5})
	# Tundra: an upright waddling swimmer, a prowler, a big shore lounger.
	add.call(_make_upright_swimmer(rng), {Biome.TUNDRA: 1.0, Biome.SNOW: 0.6})
	add.call(_labelled(rng, _make_quadruped(rng, "canine", Biome.TUNDRA, {"fur": true, "coat": pick.call(["snow", "snow", "stone", "dark"]), "patterns": pick.call([["none"], ["saddle"]])}), ["prowler", "snow-hunter", "drift-runner"]), {Biome.SNOW: 0.6, Biome.TAIGA: 0.4})
	add.call(_make_lounger(rng), {Biome.TUNDRA: 1.0, Biome.SNOW: 0.5, Biome.TAIGA: 0.3})
	# Rivers and wetlands: croakers, a stilt-legged fisher, a sleek swimmer.
	add.call(_make_frog(rng), {Biome.MARSH: 1.0, Biome.JUNGLE: 0.6, Biome.FOREST: 0.4, Biome.MEADOW: 0.3})
	add.call(_labelled(rng, _make_quadruped(rng, "heron", Biome.MARSH, {"coat": pick.call(["stone", "snow", "dark", "tan", "olive"]), "patterns": pick.call([["saddle"], ["none"], ["stripes"]])}), ["stilt-walker", "fisher", "reed-stalker"]), {Biome.MEADOW: 0.3, Biome.FOREST: 0.3})
	add.call(_labelled(rng, _make_quadruped(rng, "otter", Biome.MARSH, {"coat": pick.call(["dark", "russet", "tan", "stone"]), "patterns": pick.call([["none"], ["saddle"], ["spots"]])}), ["swimmer", "river-runner", "slider"]), {Biome.FOREST: 0.5, Biome.TAIGA: 0.5, Biome.MEADOW: 0.3})
	# Desert and badlands: baskers and a scavenger.
	add.call(_labelled(rng, _make_quadruped(rng, "lizard", Biome.DESERT, {"coat": pick.call(["olive", "tan", "sand", "rust", "vivid"]), "patterns": pick.call([["stripes"], ["spots"], ["saddle"], ["none"]])}), ["basker", "skitterer", "sand-runner"]), {Biome.BADLANDS: 0.9, Biome.DRYLANDS: 0.7})
	add.call(_labelled(rng, _make_quadruped(rng, "canine", Biome.BADLANDS, {"coat": pick.call(["tan", "sand", "rust", "stone"]), "patterns": pick.call([["none"], ["saddle"], ["spots"]])}), ["scavenger", "yipper", "skulker"]), {Biome.DESERT: 0.6, Biome.DRYLANDS: 0.8})
	species[-1].diet = "omni"   # the scavenger eats what it finds
	# Birds: two kinds that land in the jungle trees, one in the woods, and one that soars over the dry lands.
	species.append(_make_perch_bird(rng, "parrot"))
	species.append(_make_perch_bird(rng, "toucan"))
	species.append(_make_perch_bird(rng, "songbird"))
	species.append(_make_perch_bird(rng, "vulture"))


## "<Home biome> <one of the niche's words>": the label shown under a species' name.
func _labelled(rng: RandomNumberGenerator, sp: Species, words: Array) -> Species:
	sp.label = _niche_label(rng, sp.home, words)
	return sp


func _niche_label(rng: RandomNumberGenerator, home: int, words: Array) -> String:
	var word: String = words[rng.randi() % words.size()]
	return ("%s %s" % [WorldGen.BIOME_NAMES[home], word]) if home >= 0 else word.capitalize()


## A colour from a natural scheme (exotic worlds shift it like the others).
func _scheme(rng: RandomNumberGenerator, schemes: Array) -> Color:
	return _biome_coat(rng, String(schemes[rng.randi() % schemes.size()]))


## A serpent: the head mesh leads, `segs` body segments follow along its trail (see Animal). Each world's has its own
## colours, markings (bands, diamonds, stripes, blotches or none), head and length; a venomous one is boldly coloured
## with a broad head, and warns before it bites.
func _make_serpent(rng: RandomNumberGenerator, venomous: bool) -> Species:
	var s := Species.new()
	s.body = "serpent"
	s.role = "defensive" if venomous else "small"
	s.venom = venomous
	s.diet = "carn"
	s.home = Biome.JUNGLE if not venomous else Biome.DESERT
	s.label = _niche_label(rng, s.home, ["fang", "venom-coil", "rattler"] if venomous else ["serpent", "slitherer", "grass-coil"])
	s.id = "serpent_%d" % species.size()
	s.name = NameGen.species_name(rng, "critter")
	s.size = rng.randf_range(0.35, 0.55) if venomous else rng.randf_range(0.28, 0.5)
	var size := s.size
	s.hp = 14.0 if venomous else 8.0
	s.walk_speed = rng.randf_range(0.55, 0.85)
	s.run_speed = rng.randf_range(2.2, 3.2)
	s.flee_radius = 0.0 if venomous else rng.randf_range(4.0, 6.5)
	s.temperament = "wary"
	s.damage = rng.randf_range(6.0, 9.0) if venomous else 0.0
	s.herd = Vector2i(1, 1)
	s.yield_scale = 0.25
	s.leg_len = 0.0
	var girth := rng.randf_range(0.09, 0.13)
	s.body_h = size * girth * 1.8
	s.body_w = s.body_h
	s.body_len = size * 0.4
	s.segs = rng.randi_range(10, 14)
	var base: Color = _scheme(rng, ["olive", "dark", "tan", "stone", "sand"])
	var mark: Color = base.darkened(rng.randf_range(0.35, 0.6))
	if venomous:   # warning colours
		base = Color.from_hsv(rng.randf_range(0.0, 0.16) if rng.randf() < 0.7 else rng.randf_range(0.25, 0.4), rng.randf_range(0.5, 0.75), rng.randf_range(0.55, 0.8))
		mark = [Color(0.1, 0.08, 0.07), Color(0.95, 0.9, 0.75), base.darkened(0.6)][rng.randi() % 3]
		if _pal.exotic:
			base = Color.from_hsv(fposmod(base.h + _exotic_shift, 1.0), base.s, base.v)
	var belly := base.lightened(rng.randf_range(0.25, 0.45))
	var pattern: String = ["bands", "diamonds", "stripe", "blotch", "plain"][rng.randi() % 5]
	if venomous and pattern == "plain":
		pattern = "bands"
	var band_w := rng.randf_range(0.15, 0.3)
	var r := size * girth
	# One segment: a short fat capsule along -z, its marking on top.
	var kit := MeshKit.new(rng.randi())
	kit.loft([Vector3(0, 0, r * 1.6), Vector3(0, 0, 0), Vector3(0, 0, -r * 1.6)], [r * 0.95, r, r * 0.95], 10, base,
		func(t: float, a: float) -> Color:
			if cos(a) > -0.3:
				return belly
			match pattern:
				"bands": return mark if t < band_w else base
				"diamonds": return mark if absf(t - 0.5) + absf(sin(a)) * 0.35 < 0.3 else base
				"stripe": return mark if absf(sin(a)) < 0.25 else base
				"blotch": return mark if absf(t - 0.5) < 0.25 and absf(sin(a)) < 0.7 else base
			return base,
		func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.75), true, true)
	s.seg_mesh = kit.commit(material)
	# The head: wedge-shaped, flat, eyes on the sides, a flicking tongue.
	kit = MeshKit.new(rng.randi())
	var hw := r * (rng.randf_range(1.5, 1.8) if venomous else rng.randf_range(1.05, 1.35))
	var snout := rng.randf_range(2.2, 3.0)
	kit.loft([Vector3(0, 0, r * 0.8), Vector3(0, r * 0.15, -r * 0.6), Vector3(0, r * 0.1, -r * snout * 0.72), Vector3(0, 0, -r * snout)], [r * 0.9, hw * 0.8, hw * 0.6, r * 0.25], 10, base,
		func(t: float, a: float) -> Color: return belly if cos(a) > 0.3 else base,
		func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.6), true, true)
	var eye := Color.from_hsv(rng.randf_range(0.08, 0.18), 0.8, 0.85) if venomous or rng.randf() < 0.3 else Color(0.08, 0.06, 0.05)
	for side in [-1.0, 1.0]:
		kit.add_primitive(MeshKit.sphere(r * 0.22, 7, 5), Transform3D(Basis(), Vector3(side * hw * 0.5, r * 0.25, -r * snout * 0.54)), eye, 0.0, 0.0)
	kit.loft([Vector3(0, -r * 0.1, -r * (snout - 0.1)), Vector3(0, -r * 0.12, -r * (snout + 0.8))], [r * 0.05, r * 0.03], 4, Color(0.75, 0.15, 0.2))   # tongue
	s.body_mesh = kit.commit(material)   # the body node carries the head; its segments follow behind
	s.head_mesh = null
	s.call_sound = SoundGen.creature_call("hiss", size, rng)
	return s


## An upright swimmer of the cold shores: stands on short legs, flippers for wings, waddles on land, slides on its
## belly in a hurry, and swims. Each world's has its own build, coat, front, bill and head trimmings.
func _make_upright_swimmer(rng: RandomNumberGenerator) -> Species:
	var s := Species.new()
	s.body = "upright"
	s.role = "grazer"
	s.home = Biome.TUNDRA
	s.label = _niche_label(rng, s.home, ["waddler", "diver", "shore-strutter", "ice-slider"])
	s.id = "penguin_%d" % species.size()
	s.name = NameGen.species_name(rng, "grazer")
	s.size = rng.randf_range(0.45, 1.0)
	var size := s.size
	s.hp = 14.0 + size * 10.0
	s.walk_speed = rng.randf_range(0.55, 0.85)
	s.run_speed = rng.randf_range(2.6, 3.6)
	s.flee_radius = rng.randf_range(6.0, 10.0)
	s.temperament = ["curious", "wary", "calm"][rng.randi() % 3]
	s.herd = Vector2i(3, rng.randi_range(5, 9))
	s.yield_scale = 0.6 * size
	s.diet = "carn"
	s.swims = true
	s.habitat = "water"
	s.leg_len = size * rng.randf_range(0.09, 0.15)
	s.body_h = size * rng.randf_range(0.65, 0.95)
	s.body_w = size * rng.randf_range(0.35, 0.55)
	s.body_len = s.body_w
	var back := _scheme(rng, ["dark", "dark", "stone", "cave", "russet", "olive"])
	var front := back.lightened(rng.randf_range(0.6, 0.9)) if rng.randf() < 0.4 else Color.from_hsv(rng.randf_range(0.08, 0.15), rng.randf_range(0.0, 0.25), rng.randf_range(0.85, 0.97))
	var front_style: String = ["full", "full", "bib", "plain"][rng.randi() % 4]
	var bill_col: Color = [Color(0.13, 0.12, 0.12), Color(0.95, 0.6, 0.15), Color(0.9, 0.8, 0.2), Color(0.8, 0.3, 0.2)][rng.randi() % 4]
	var accent := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.85), rng.randf_range(0.7, 0.95))
	if _pal.exotic:
		accent = Color.from_hsv(fposmod(accent.h + _exotic_shift, 1.0), accent.s, accent.v)
	var kit := MeshKit.new(rng.randi())
	var H := s.body_h
	var W := s.body_w
	var plump := rng.randf_range(0.55, 0.72)
	var path := [Vector3(0, -H * 0.1, 0), Vector3(0, H * 0.25, 0), Vector3(0, H * 0.55, 0), Vector3(0, H * 0.78, -size * 0.02)]
	kit.loft(path, [W * 0.45, W * plump, W * (plump - 0.07), W * 0.35], 14, back,
		func(t: float, a: float) -> Color:
			var facing := cos(a + PI)
			match front_style:
				"full": return front if facing > 0.25 and t < 0.92 else back
				"bib": return front if facing > 0.35 and t > 0.45 and t < 0.92 else back
			return back.lightened(0.12) if facing > 0.5 else back, Callable(), true, true)
	var flip := H * rng.randf_range(0.32, 0.5)
	for side in [-1.0, 1.0]:   # flippers
		var fb := Basis(Vector3.FORWARD, side * rng.randf_range(0.15, 0.35))
		kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(fb * Basis.from_scale(Vector3(size * 0.05, flip * 2.0, size * 0.16)), Vector3(side * W * 0.6, H * 0.42, 0)), back, 0.0, 0.03)
	s.body_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	var hr := size * rng.randf_range(0.13, 0.2)
	var bill_len := hr * rng.randf_range(0.7, 1.7)
	kit.add_primitive(MeshKit.sphere(hr, 12, 8), Transform3D(Basis(), Vector3.ZERO), back, 0.0, 0.03)
	kit.add_primitive(MeshKit.cylinder(0.0, hr * rng.randf_range(0.22, 0.34), bill_len, 6), Transform3D(Basis(Vector3.RIGHT, -PI * 0.5 + rng.randf_range(-0.15, 0.2)), Vector3(0, -hr * 0.1, -hr * 0.65 - bill_len * 0.5)), bill_col, 0.0, 0.0)
	if rng.randf() < 0.6:   # cheek patches
		for side in [-1.0, 1.0]:
			kit.add_primitive(MeshKit.sphere(hr * 0.45, 8, 5), Transform3D(Basis.from_scale(Vector3(0.3, 1.0, 1.0)), Vector3(side * hr * 0.72, hr * 0.05, -hr * 0.05)), front if rng.randf() < 0.6 else accent, 0.0, 0.0)
	if rng.randf() < 0.35:   # a crest of plumes
		for k in rng.randi_range(3, 5):
			var a := (k - 2) * 0.3
			kit.loft([Vector3(sin(a) * hr * 0.4, hr * 0.7, -hr * 0.2), Vector3(sin(a) * hr * 1.1, hr * 1.2, hr * 0.5)], [hr * 0.08, hr * 0.02], 4, accent)
	var eye := Color(0.05, 0.05, 0.05) if rng.randf() < 0.7 else Color(0.85, 0.2, 0.15)
	for side in [-1.0, 1.0]:
		kit.add_primitive(MeshKit.sphere(hr * 0.12, 6, 4), Transform3D(Basis(), Vector3(side * hr * 0.62, hr * 0.25, -hr * 0.55)), eye, 0.0, 0.0)
	s.head_mesh = kit.commit(material)
	s.head_pivot = Vector3(0, H * 0.88, -size * 0.02)
	kit = MeshKit.new(rng.randi())
	var foot: Color = bill_col.darkened(0.2) if rng.randf() < 0.5 else Color(0.85, 0.55, 0.45)
	kit.loft([Vector3(0, 0, 0), Vector3(0, -s.leg_len, 0)], [size * 0.04, size * 0.035], 6, foot)
	kit.add_primitive(MeshKit.sphere(0.5, 7, 4), Transform3D(Basis.from_scale(Vector3(size * 0.12, size * 0.03, size * 0.18)), Vector3(0, -s.leg_len, -size * 0.05)), foot, 0.0, 0.0)
	s.leg_mesh = kit.commit(material)
	s.leg_offsets = [Vector3(-W * 0.22, 0.0, 0), Vector3(W * 0.22, 0.0, 0)]
	s.call_sound = SoundGen.creature_call("honk", size, rng)
	return s


## A big lounger of the cold shores: a long sleek body that humps along on land and glides in the water, fore-flippers
## and a forked tail. Each world's has its own size, coat, markings, snout, and sometimes tusks.
func _make_lounger(rng: RandomNumberGenerator) -> Species:
	var s := Species.new()
	s.body = "seal"
	s.role = "grazer"
	s.home = Biome.TUNDRA
	s.label = _niche_label(rng, s.home, ["lounger", "flopper", "shore-basker", "blubberback"])
	s.id = "seal_%d" % species.size()
	s.name = NameGen.species_name(rng, "grazer")
	s.size = rng.randf_range(0.8, 1.5)
	var size := s.size
	s.hp = 55.0 * size
	s.walk_speed = rng.randf_range(0.4, 0.6)
	s.run_speed = rng.randf_range(1.3, 1.9)
	s.flee_radius = rng.randf_range(5.0, 9.0)
	s.temperament = ["calm", "calm", "wary"][rng.randi() % 3]
	s.herd = Vector2i(1, rng.randi_range(3, 6))
	s.yield_scale = 1.3 * size
	s.diet = "carn"
	s.swims = true
	s.habitat = "water"
	s.leg_len = 0.0
	s.body_h = size * rng.randf_range(0.36, 0.48)
	s.body_w = size * rng.randf_range(0.4, 0.52)
	s.body_len = size * rng.randf_range(1.3, 1.7)
	var coat := _scheme(rng, ["stone", "stone", "dark", "snow", "tan", "cave"])
	var mark := coat.darkened(rng.randf_range(0.2, 0.4)) if rng.randf() < 0.7 else coat.lightened(0.35)
	var pattern: String = ["spots", "spots", "saddle", "none"][rng.randi() % 4]
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = rng.randf_range(2.5, 6.0)
	var kit := MeshKit.new(rng.randi())
	var L := s.body_len
	var H := s.body_h
	var path := [Vector3(0, H * 0.05, L * 0.55), Vector3(0, H * 0.12, L * 0.3), Vector3(0, H * 0.2, 0), Vector3(0, H * 0.25, -L * 0.25), Vector3(0, H * 0.3, -L * 0.42)]
	kit.loft(path, [H * 0.12, H * 0.42, H * 0.55, H * 0.5, H * 0.38], 14, coat,
		func(t: float, a: float) -> Color:
			var c := coat.lightened(0.25) if cos(a) > 0.4 else coat
			match pattern:
				"spots": return mark if noise.get_noise_2d(t * 20.0, a * 3.0) > 0.35 else c
				"saddle": return mark if cos(a) < -0.5 and t > 0.25 and t < 0.75 else c
			return c,
		func(_t: float, _a: float) -> Vector2: return Vector2(1.15, 0.85), true, true)
	for side in [-1.0, 1.0]:
		var fb := Basis(Vector3.UP, side * 0.5) * Basis(Vector3.FORWARD, side * 0.6)
		kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(fb * Basis.from_scale(Vector3(size * 0.3, size * 0.04, size * 0.14)), Vector3(side * H * 0.5, -H * 0.15, -L * 0.18)), coat.darkened(0.15), 0.0, 0.03)
		var tb := Basis(Vector3.UP, side * 0.45)
		kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(tb * Basis.from_scale(Vector3(size * 0.14, size * 0.04, size * 0.26)), Vector3(side * H * 0.12, H * 0.0, L * 0.66)), coat.darkened(0.15), 0.0, 0.03)
	s.body_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	var hr := H * rng.randf_range(0.35, 0.45)
	var snout := rng.randf_range(0.6, 1.2)
	kit.add_primitive(MeshKit.sphere(hr, 12, 8), Transform3D(Basis.from_scale(Vector3(1.0, 0.95, 1.2)), Vector3.ZERO), coat, 0.0, 0.03)
	kit.add_primitive(MeshKit.sphere(hr * 0.55, 10, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.8, snout)), Vector3(0, -hr * 0.2, -hr * (0.6 + snout * 0.3))), coat.lightened(0.15), 0.0, 0.03)
	kit.add_primitive(MeshKit.sphere(hr * 0.14, 6, 4), Transform3D(Basis(), Vector3(0, -hr * 0.05, -hr * (0.9 + snout * 0.45))), Color(0.08, 0.07, 0.07), 0.0, 0.0)
	if rng.randf() < 0.2:   # tusks
		for side in [-1.0, 1.0]:
			kit.add_primitive(MeshKit.cylinder(0.0, hr * 0.08, hr * 1.2, 6), Transform3D(Basis(Vector3.RIGHT, 0.25), Vector3(side * hr * 0.2, -hr * 0.85, -hr * (0.6 + snout * 0.3))), Color(0.92, 0.88, 0.75), 0.0, 0.03)
	for side in [-1.0, 1.0]:
		kit.add_primitive(MeshKit.sphere(hr * 0.2, 8, 5), Transform3D(Basis(), Vector3(side * hr * 0.42, hr * 0.25, -hr * 0.75)), Color(0.04, 0.04, 0.05), 0.0, 0.0)
	s.head_mesh = kit.commit(material)
	s.head_pivot = Vector3(0, H * 0.45, -L * 0.5)
	s.leg_offsets = []
	s.call_sound = SoundGen.creature_call("honk", size * 1.6, rng)
	return s


## A croaker: squat, wide-mouthed, big-eyed, folded jumping legs. Hops about by the water and plops away. Each world's
## has its own skin, markings, eyes and build (now and then a bright warning-coloured one).
func _make_frog(rng: RandomNumberGenerator) -> Species:
	var s := Species.new()
	s.body = "frog"
	s.role = "small"
	s.home = Biome.MARSH
	s.label = _niche_label(rng, s.home, ["croaker", "leaper", "pond-hopper"])
	s.id = "frog_%d" % species.size()
	s.name = NameGen.species_name(rng, "critter")
	s.size = rng.randf_range(0.14, 0.28)
	var size := s.size
	s.hp = 4.0
	s.walk_speed = 0.6
	s.run_speed = rng.randf_range(2.5, 3.5)
	s.flee_radius = rng.randf_range(3.0, 5.0)
	s.temperament = "skittish"
	s.herd = Vector2i(1, 3)
	s.yield_scale = 0.1
	s.diet = "carn"
	s.swims = true
	s.habitat = "water"
	s.leg_len = size * 0.12
	s.body_h = size * rng.randf_range(0.38, 0.52)
	s.body_w = size * rng.randf_range(0.5, 0.7)
	s.body_len = size * rng.randf_range(0.6, 0.8)
	var skin := _scheme(rng, ["olive", "olive", "tan", "dark", "stone"])
	if rng.randf() < 0.25:
		skin = Color.from_hsv(rng.randf(), rng.randf_range(0.7, 0.9), rng.randf_range(0.65, 0.85))   # bright warning colours
		if _pal.exotic:
			skin = Color.from_hsv(fposmod(skin.h + _exotic_shift, 1.0), skin.s, skin.v)
	var spot := skin.darkened(rng.randf_range(0.35, 0.55)) if rng.randf() < 0.7 else Color.from_hsv(rng.randf(), 0.7, 0.2)
	var pattern: String = ["spots", "stripes", "plain", "marbled"][rng.randi() % 4]
	var freq := rng.randf_range(45.0, 70.0) / size
	var kit := MeshKit.new(rng.randi())
	var H := s.body_h
	var W := s.body_w
	kit.add_primitive(MeshKit.sphere(0.5, 12, 8), Transform3D(Basis(Vector3.RIGHT, -0.35).scaled(Vector3(W, H, s.body_len)), Vector3.ZERO), skin, 0.0, 0.03,
		null, func(p: Vector3) -> Color:
			if p.y < -H * 0.25:
				return skin.lightened(0.4)
			match pattern:
				"spots": return spot if sin(p.x * freq) * sin(p.z * freq * 0.9) > 0.6 else skin
				"stripes": return spot if absf(p.x) < W * 0.08 or absf(absf(p.x) - W * 0.3) < W * 0.05 else skin
				"marbled": return spot if sin(p.x * freq * 0.6 + sin(p.z * freq * 0.5) * 2.0) > 0.5 else skin
			return skin)
	for side in [-1.0, 1.0]:
		# Folded hind legs: thigh and shin tucked along the body's sides.
		kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(Basis(Vector3.UP, side * 0.35).scaled(Vector3(size * 0.16, size * 0.14, size * 0.38)), Vector3(side * W * 0.5, -H * 0.15, s.body_len * 0.2)), skin, 0.0, 0.03)
		kit.add_primitive(MeshKit.sphere(0.5, 8, 5), Transform3D(Basis.from_scale(Vector3(size * 0.2, size * 0.04, size * 0.16)), Vector3(side * W * 0.55, -H * 0.42, s.body_len * 0.38)), skin.darkened(0.1), 0.0, 0.03)
	s.body_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(0.5, 10, 6), Transform3D(Basis.from_scale(Vector3(W * 0.95, H * 0.55, size * 0.4)), Vector3.ZERO), skin, 0.0, 0.03)
	var iris := Color.from_hsv(rng.randf_range(0.05, 0.18) if rng.randf() < 0.7 else rng.randf(), 0.8, 0.85)
	var bulge := rng.randf_range(0.08, 0.12)
	for side in [-1.0, 1.0]:
		var e := Vector3(side * W * 0.3, H * 0.28, -size * 0.04)
		kit.add_primitive(MeshKit.sphere(size * bulge, 8, 6), Transform3D(Basis(), e), skin, 0.0, 0.03)
		kit.add_primitive(MeshKit.sphere(size * bulge * 0.7, 8, 6), Transform3D(Basis(), e + Vector3(side * size * 0.03, size * 0.03, -size * 0.04)), iris, 0.0, 0.0)
		kit.add_primitive(MeshKit.sphere(size * bulge * 0.35, 6, 4), Transform3D(Basis(), e + Vector3(side * size * 0.05, size * 0.05, -size * 0.07)), Color(0.04, 0.04, 0.04), 0.0, 0.0)
	s.head_mesh = kit.commit(material)
	s.head_pivot = Vector3(0, H * 0.18, -s.body_len * 0.42)
	kit = MeshKit.new(rng.randi())   # small front legs
	kit.loft([Vector3(0, 0, 0), Vector3(0, -s.leg_len * 2.0, -size * 0.03)], [size * 0.035, size * 0.03], 5, skin)
	s.leg_mesh = kit.commit(material)
	s.leg_offsets = [Vector3(-W * 0.3, -H * 0.2, -s.body_len * 0.25), Vector3(W * 0.3, -H * 0.2, -s.body_len * 0.25)]
	s.call_sound = SoundGen.creature_call("croak", size, rng)
	return s


## Birds that land (two kinds in the jungle, one in the woods) and one that soars over the dry lands, each made up for
## the world: colours, bill, crest, tail and wings. `kind` is the niche: parrot (bright, hooked bill), toucan (dark,
## huge bill), songbird (small, plain), vulture (big, bare-headed, soaring).
func _make_perch_bird(rng: RandomNumberGenerator, kind: String) -> Species:
	var s := Species.new()
	s.role = "bird"
	s.bird_kind = "soar" if kind == "vulture" else "perch"
	s.label = {"parrot": "Screecher", "toucan": "Bigbill", "songbird": "Songbird", "vulture": "Soaring carrion bird"}[kind]
	s.id = "%s_%d" % [kind, species.size()]
	s.name = NameGen.species_name(rng, "bird")
	match kind:
		"parrot": s.biome_pref = {Biome.JUNGLE: 1.0}
		"toucan": s.biome_pref = {Biome.JUNGLE: 0.8}
		"songbird": s.biome_pref = {Biome.FOREST: 1.0, Biome.AUTUMN: 1.0, Biome.MEADOW: 0.7, Biome.TAIGA: 0.6, Biome.MARSH: 0.5}
		"vulture": s.biome_pref = {Biome.DESERT: 1.0, Biome.BADLANDS: 1.0, Biome.DRYLANDS: 0.9}
	s.size = {"parrot": 0.5, "toucan": 0.46, "songbird": 0.18, "vulture": 0.75}[kind] * rng.randf_range(0.8, 1.2)
	var size := s.size
	var main: Color
	var wing_col: Color
	var belly: Color
	var bill: Color
	match kind:
		"parrot":
			main = Color.from_hsv(rng.randf(), rng.randf_range(0.7, 0.9), rng.randf_range(0.7, 0.9))
			wing_col = Color.from_hsv(fposmod(main.h + rng.randf_range(0.2, 0.6), 1.0), rng.randf_range(0.6, 0.85), rng.randf_range(0.6, 0.85))
			belly = Color.from_hsv(fposmod(main.h + rng.randf_range(-0.15, 0.15), 1.0), 0.75, 0.9)
			bill = [Color(0.85, 0.82, 0.75), Color(0.15, 0.14, 0.14), Color(0.9, 0.6, 0.2)][rng.randi() % 3]
		"toucan":
			main = _scheme(rng, ["dark", "dark", "cave", "olive"])
			wing_col = main.darkened(0.1)
			belly = Color.from_hsv(rng.randf(), rng.randf_range(0.4, 0.8), rng.randf_range(0.8, 0.98))
			bill = Color.from_hsv(rng.randf_range(0.0, 0.18) if rng.randf() < 0.7 else rng.randf(), rng.randf_range(0.7, 0.9), rng.randf_range(0.8, 0.98))
		"songbird":
			main = _coat(rng).lightened(0.1)
			wing_col = main.darkened(rng.randf_range(0.2, 0.4))
			belly = Color.from_hsv(rng.randf(), rng.randf_range(0.3, 0.7), 0.9)
			bill = Color(0.3, 0.25, 0.2)
		_:
			main = _scheme(rng, ["dark", "dark", "stone", "russet"])
			wing_col = main.darkened(0.25)
			belly = main.lightened(0.1)
			bill = Color(0.85, 0.8, 0.7)
	if _pal.exotic and kind in ["parrot", "songbird"]:
		main = Color.from_hsv(fposmod(main.h + _exotic_shift, 1.0), main.s, main.v)
	var kit := MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(0.5, 10, 6), Transform3D(Basis().scaled(Vector3(size * 0.5, size * 0.5, size)), Vector3.ZERO), main, 0.0, 0.05,
		null, func(p: Vector3) -> Color: return belly if p.y < -size * 0.05 and p.z < size * 0.1 else main)
	var head_c := Vector3(0, size * 0.22, -size * 0.5)
	var head_col := main
	if kind == "vulture":   # a bare head
		head_col = [Color(0.75, 0.45, 0.42), Color(0.8, 0.25, 0.2), Color(0.6, 0.6, 0.62), Color(0.9, 0.85, 0.8)][rng.randi() % 4]
	kit.add_primitive(MeshKit.sphere(size * 0.22, 9, 6), Transform3D(Basis(), head_c), head_col, 0.0, 0.05)
	match kind:
		"toucan":
			var bl := rng.randf_range(0.65, 1.0)
			kit.loft([head_c + Vector3(0, 0, -size * 0.15), head_c + Vector3(0, -size * 0.04, -size * bl * 0.6), head_c + Vector3(0, -size * 0.12, -size * bl)], [size * 0.13, size * 0.1, size * 0.03], 8, bill,
				func(t: float, _a: float) -> Color: return bill.darkened(0.7) if t > 0.9 else bill)
			kit.add_primitive(MeshKit.sphere(size * 0.11, 7, 5), Transform3D(Basis.from_scale(Vector3(1.3, 1, 0.4)), head_c + Vector3(0, -size * 0.02, 0.0)), belly, 0.0, 0.0)
		"parrot":
			kit.loft([head_c + Vector3(0, size * 0.02, -size * 0.18), head_c + Vector3(0, -size * 0.06, -size * 0.3), head_c + Vector3(0, -size * 0.16, -size * 0.28)], [size * 0.08, size * 0.05, size * 0.015], 7, bill)
		"vulture":
			kit.loft([head_c + Vector3(0, 0, -size * 0.15), head_c + Vector3(0, -size * 0.06, -size * 0.32)], [size * 0.06, size * 0.02], 6, bill)
			kit.add_primitive(MeshKit.sphere(size * 0.2, 8, 5), Transform3D(Basis.from_scale(Vector3(1.4, 0.6, 1.0)), head_c + Vector3(0, -size * 0.15, size * 0.18)), main.lightened(rng.randf_range(0.3, 0.6)), 0.05, 0.05)   # neck ruff
		_:
			kit.add_primitive(MeshKit.cylinder(0.0, size * 0.05, size * 0.2, 6), Transform3D(Basis(Vector3.RIGHT, -PI / 2), head_c + Vector3(0, -size * 0.02, -size * 0.25)), bill, 0.0, 0.0)
	if kind != "vulture" and rng.randf() < 0.3:   # a crest
		for k in 3:
			kit.loft([head_c + Vector3((k - 1) * size * 0.04, size * 0.15, 0), head_c + Vector3((k - 1) * size * 0.07, size * 0.36, size * 0.15)], [size * 0.03, size * 0.008], 4, wing_col.lightened(0.2))
	for side in [-1.0, 1.0]:
		kit.add_primitive(MeshKit.sphere(size * 0.045, 6, 4), Transform3D(Basis(), head_c + Vector3(side * size * 0.17, size * 0.05, -size * 0.06)), Color(0.04, 0.04, 0.04), 0.0, 0.0)
	var tail_len := size * (rng.randf_range(0.8, 1.4) if kind == "parrot" else rng.randf_range(0.45, 0.8))
	kit.add_primitive(MeshKit.sphere(0.5, 8, 4), Transform3D(Basis().scaled(Vector3(size * 0.3, size * 0.06, tail_len)), Vector3(0, 0.0, size * 0.35 + tail_len * 0.45)), wing_col, 0.0, 0.04)
	# Little legs and toes, for perching.
	for side in [-1.0, 1.0]:
		kit.loft([Vector3(side * size * 0.1, -size * 0.2, 0), Vector3(side * size * 0.1, -size * 0.38, 0)], [size * 0.025, size * 0.02], 4, Color(0.4, 0.35, 0.3))
	s.body_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	var span := size * (rng.randf_range(1.9, 2.5) if kind == "vulture" else rng.randf_range(1.0, 1.4))
	kit.add_primitive(MeshKit.sphere(0.5, 9, 4), Transform3D(Basis().scaled(Vector3(span, size * 0.05, size * (0.6 if kind == "vulture" else 0.5))), Vector3(span * 0.5, 0, 0)), wing_col, 0.0, 0.05)
	s.wing_mesh = kit.commit(material)
	s.call_sound = SoundGen.creature_call("squawk" if kind in ["parrot", "toucan"] else ("hiss" if kind == "vulture" else "bird"), size, rng)
	return s
