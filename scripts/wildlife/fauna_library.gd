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

const ROLE_LABELS := {"grazer": "Grazer", "defensive": "Territorial beast", "critter": "Critter", "bird": "Bird"}

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
func _biome_coat(rng: RandomNumberGenerator, scheme: String) -> Color:
	var c := _natural_coat(rng, scheme)
	# Exotic worlds keep the biome's light/dark and saturation, but in the world's strange hue.
	if _pal.exotic and scheme not in ["snow", "fungal"]:
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
	return _coat(rng)


func _make_quadruped(rng: RandomNumberGenerator, arch: String, home := -1) -> Species:
	var a: Dictionary = ARCHETYPES[arch]
	var role: String = a.role
	var tr: Dictionary = BIOME_TRAITS.get(home, {})
	var s := Species.new()
	s.role = role
	s.home = home
	s.label = ROLE_LABELS[role]
	if home >= 0:
		s.label = "%s %s" % [WorldGen.BIOME_NAMES[home], {"grazer": "grazer", "defensive": "beast", "critter": "critter"}[role]]
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
	s.body_w = s.body_h * rng.randf_range(0.75, 0.95) * float(tr.get("width", 1.0))
	s.leg_len = size * rng.randf_range(a.leg[0], a.leg[1]) * float(tr.get("leg", 1.0))
	var leg_r := size * (0.085 if stocky else 0.07) * rng.randf_range(0.9, 1.15)
	if arch in ["wader", "strider"]:
		leg_r *= 0.7
	var neck_len := size * rng.randf_range(a.neck[0], a.neck[1])
	var neck_angle := deg_to_rad(rng.randf_range(a.angle[0], a.angle[1]))
	var head_len := size * rng.randf_range(0.34, 0.46) * (0.7 if arch in ["strider", "wader", "shellback"] else 1.0)

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

	# Biome adaptations: hardier in the cold and badlands, faster on the plains and in the jungle.
	s.hp *= float(tr.get("hp", 1.0))
	s.run_speed *= float(tr.get("speed", 1.0))
	s.walk_speed *= float(tr.get("speed", 1.0))

	# Temperament decides how close you can get before it reacts.
	s.temperament = {"slender": "skittish", "stocky": "wary", "bulky": "calm", "shellback": "calm", "strider": "wary",
		"wader": "wary", "boar": "wary", "horned": "calm", "hopper": "skittish", "ferret": "curious"}[arch]
	if role == "grazer" and rng.randf() < 0.25:
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
	var pattern: String = ["none", "stripes", "spots", "saddle", "none"][rng.randi() % 5]
	if tr.has("patterns"):
		var pats: Array = tr.patterns
		pattern = pats[rng.randi() % pats.size()]
	match String(tr.get("coat", "")):
		"vivid": accent = Color.from_hsv(fposmod(coat.h + 0.5, 1.0), 0.3, 0.15) if rng.randf() < 0.5 else coat.darkened(0.6)   # bold markings
		"fungal": accent = _pal.glow   # glowing spots
		"snow": accent = coat.darkened(0.2)
		"rust": accent = _pal.badlands_cream
	var fur: bool = tr.get("fur", false)
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 3.5 / size
	var stripe_f := rng.randf_range(9.0, 16.0) / size
	var body_h := s.body_h
	var coat_fn := func(p: Vector3) -> Color:
		var c := coat
		match pattern:
			"stripes":
				if sin(p.z * stripe_f + p.y * 3.0) > 0.45 and p.y > -body_h * 0.15:
					c = accent
			"spots":
				if noise.get_noise_3dv(p) > 0.3:
					c = accent
			"saddle":
				if p.y > body_h * 0.18:
					c = accent
		if p.y < -body_h * 0.22:
			c = c.lerp(belly, 0.8)
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
	var profile := [0.55, 0.88, 0.95, 0.86, 0.92, 1.0, 0.97, 0.82, 0.62]
	for i in profile.size():
		var t := float(i) / (profile.size() - 1)
		var z := lerpf(L * 0.5, -L * 0.5, t)
		var y := sin(t * PI) * H * 0.04 + hump_h * exp(-pow((t - 0.72) / 0.16, 2.0))
		torso.append(Vector3(0, y, z))
		torso_r.append(H * 0.5 * float(profile[i]) * (1.0 + hump_h / H * exp(-pow((t - 0.72) / 0.16, 2.0))))
	var w_ratio := W / H
	var torso_coat := func(t: float, a: float) -> Color:
		# Rebuild an approximate body-space point so the coat pattern lines up.
		return coat_fn.call(Vector3(-sin(a) * W * 0.5, -cos(a) * H * 0.5, lerpf(L * 0.5, -L * 0.5, t)))
	var torso_bumps := 0.012 if arch == "bulky" else 0.0
	if fur:
		torso_bumps = maxf(torso_bumps, H * 0.05)   # thick shaggy winter coat
	kit.loft(torso, torso_r, 14, coat, torso_coat, func(t: float, a: float) -> Vector2: return Vector2(1.0, w_ratio), true, true, torso_bumps)
	if arch == "bulky" or (fur and role != "critter" and arch != "shellback"):   # shaggy chest ruff
		kit.loft([chest + Vector3(0, -H * 0.1, -L * 0.1), chest + Vector3(0, -H * 0.35, -L * 0.2), chest + Vector3(0, -H * 0.55, -L * 0.18)], [H * 0.35, H * 0.3, H * 0.12], 10, accent.lerp(coat, 0.5), Callable(), Callable(), true, true, 0.03)
	if arch == "shellback":
		var shell := accent.lerp(coat, 0.35)
		var plates := func(p: Vector3) -> Color:
			return shell.darkened(0.25) if sin(p.x * 18.0 / size) * sin(p.z * 18.0 / size) > 0.55 else shell
		kit.add_primitive(MeshKit.sphere(0.5, 16, 9), Transform3D(Basis.from_scale(Vector3(W * 1.4, H * 1.15, L * 1.12)), Vector3(0, H * 0.3, 0)), shell, 0.0, 0.03, null, plates)
		kit.loft([Vector3(0, H * 0.02, L * 0.56), Vector3(0, H * 0.02, -L * 0.56)], [W * 0.72, W * 0.72], 16, shell.darkened(0.15), Callable(),
			func(t: float, a: float) -> Vector2: return Vector2(0.22, 1.0), true, true)
	# Tail: a lofted curve from the rump.
	var tail_len := size * rng.randf_range(0.18, 0.45)
	var tail_root: Vector3 = torso[0] + Vector3(0, H * 0.2, -L * 0.02)
	if arch == "ferret":
		tail_len = L * 0.85
	if arch == "strider":
		for i in 5:   # fan of tail plumes
			var tb := Basis(Vector3.UP, (i - 2) * 0.3) * Basis(Vector3.RIGHT, deg_to_rad(-125))
			var tip := tail_root + tb.y * size * 0.35
			kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(size * 0.06, size * 0.15), Vector2(0, size * 0.36), Vector2(-size * 0.06, size * 0.15)]),
				Transform3D(tb, tail_root), size * 0.02, size * 0.01, accent, accent.lightened(0.2), 0.4)
	elif role == "critter" and arch != "ferret":
		kit.add_primitive(MeshKit.sphere(size * 0.13, 9, 6), Transform3D(Basis(), tail_root), belly, 0.04, 0.05)   # puff tail
	elif arch != "shellback":
		var droop := 0.9 if arch != "ferret" else 0.35
		var tp := [tail_root, tail_root + Vector3(0, -tail_len * 0.25 * droop, tail_len * 0.4), tail_root + Vector3(0, -tail_len * 0.75 * droop, tail_len * 0.65), tail_root + Vector3(0, -tail_len * droop, tail_len * 0.72)]
		kit.loft(tp, [size * 0.05, size * 0.04, size * 0.028, size * 0.012], 7, coat, func(t: float, a: float) -> Color: return accent if t > 0.7 else coat)
		if tail_len > size * 0.3 and arch != "ferret":
			kit.add_primitive(MeshKit.sphere(size * 0.05, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1.7, 1)), tp[3]), accent, 0.05, 0.04)
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
	var bill := arch in ["wader", "strider"]
	var back := neck_end + up * head_len * 0.05 - fwd * head_len * 0.15
	var skull := back + fwd * head_len * 0.35
	var nose := skull + fwd * (head_len * 0.3 + snout_len) - up * head_len * 0.12
	var head_path := [back, skull, skull + fwd * head_len * 0.25 - up * head_len * 0.04, nose]
	var head_r := [head_len * 0.3, head_len * 0.36, head_len * 0.27, head_len * (0.08 if bill else 0.18)]
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
	if not arch in ["shellback", "strider", "wader"]:
		_ears(kit, rng, role, skull - fwd * head_len * 0.1, head_len, coat, belly, tr.get("ears", ""))
	_horns(kit, rng, arch, skull - fwd * head_len * 0.1, head_len, size, nose)
	s.head_mesh = kit.commit(material)

	# --- Legs: jointed. Front legs nearly straight; hind legs bend back at the hock. ---
	var thigh_col := coat
	var shin_col := coat.lerp(accent, 0.35)
	var hoof := Color(0.16, 0.13, 0.11)
	var ll := s.leg_len
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(leg_r * 1.4, 9, 6), Transform3D(Basis.from_scale(Vector3(1, 1.4, 1.2)), Vector3(0, -leg_r * 0.4, 0)), thigh_col, 0.0, 0.04)
	var knee := Vector3(0, -ll * 0.5, -ll * 0.04)
	_segment(kit, Vector3(0, -leg_r, 0), knee, leg_r * 1.35, leg_r, thigh_col, Callable())
	_segment(kit, knee, Vector3(0, -ll + leg_r * 0.5, 0), leg_r, leg_r * 0.72, shin_col, Callable())
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.85, leg_r * 0.95, leg_r * 1.3, 8), Transform3D(Basis(), Vector3(0, -ll + leg_r * 0.55, -leg_r * 0.1)), hoof, 0.0, 0.0)
	s.leg_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(leg_r * 1.7, 9, 6), Transform3D(Basis.from_scale(Vector3(1, 1.4, 1.3)), Vector3(0, -leg_r * 0.5, 0)), thigh_col, 0.0, 0.04, null, coat_fn)
	var stifle := Vector3(0, -ll * 0.4, -ll * 0.1)
	var hock := Vector3(0, -ll * 0.68, ll * 0.1)
	_segment(kit, Vector3(0, -leg_r, 0), stifle, leg_r * 1.6, leg_r * 1.1, thigh_col, Callable())
	_segment(kit, stifle, hock, leg_r * 1.05, leg_r * 0.8, shin_col, Callable())
	_segment(kit, hock, Vector3(0, -ll + leg_r * 0.5, ll * 0.02), leg_r * 0.8, leg_r * 0.7, shin_col, Callable())
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.8, leg_r * 0.9, leg_r * 1.3, 8), Transform3D(Basis(), Vector3(0, -ll + leg_r * 0.55, 0)), hoof, 0.0, 0.0)
	s.hind_leg_mesh = kit.commit(material)
	var lx := W * 0.32
	var ly := -H * 0.25
	s.leg_offsets = [Vector3(-lx, ly, chest.z - L * 0.05), Vector3(lx, ly, chest.z - L * 0.05), Vector3(-lx, ly, hips.z + L * 0.05), Vector3(lx, ly, hips.z + L * 0.05)]
	if a.legs == 2:
		s.leg_offsets = [Vector3(-lx, ly, 0), Vector3(lx, ly, 0)]
		s.leg_mesh = s.hind_leg_mesh

	s.call_sound = SoundGen.creature_call(role, size, rng)
	return s


## A tapered limb/neck segment between two points (joint spheres keep it smooth).
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
	if arch in ["shellback", "strider", "wader", "hopper", "ferret"]:
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
