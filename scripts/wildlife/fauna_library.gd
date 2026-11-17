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


## Body plans. Each species picks one, then randomizes within its ranges.
## size, leg (x size), body_h (x size), neck (x size), neck_angle (degrees), legs, and favorite biomes.
const ARCHETYPES := {
	"slender": {"role": "grazer", "size": [0.55, 0.8], "leg": [0.85, 1.05], "body_h": [0.36, 0.44], "neck": [0.35, 0.55], "angle": [45, 65], "legs": 4,
		"biomes": {Biome.MEADOW: 1.0, Biome.FOREST: 0.7, Biome.AUTUMN: 0.8, Biome.DRYLANDS: 0.6}},
	"stocky": {"role": "grazer", "size": [0.9, 1.2], "leg": [0.55, 0.75], "body_h": [0.4, 0.5], "neck": [0.25, 0.45], "angle": [35, 55], "legs": 4,
		"biomes": {Biome.MEADOW: 0.8, Biome.FOREST: 1.0, Biome.AUTUMN: 1.0, Biome.TAIGA: 0.5}},
	"bulky": {"role": "grazer", "size": [1.4, 1.8], "leg": [0.42, 0.55], "body_h": [0.55, 0.65], "neck": [0.08, 0.18], "angle": [10, 25], "legs": 4,
		"biomes": {Biome.TAIGA: 1.0, Biome.MEADOW: 0.5, Biome.FOREST: 0.6}},
	"shellback": {"role": "grazer", "size": [0.7, 1.0], "leg": [0.18, 0.25], "body_h": [0.42, 0.5], "neck": [0.15, 0.25], "angle": [10, 25], "legs": 4,
		"biomes": {Biome.DRYLANDS: 1.0, Biome.DESERT: 1.0, Biome.MARSH: 0.8}},
	"strider": {"role": "grazer", "size": [0.9, 1.2], "leg": [1.0, 1.25], "body_h": [0.5, 0.6], "neck": [0.6, 0.8], "angle": [70, 80], "legs": 2,
		"biomes": {Biome.DRYLANDS: 1.0, Biome.DESERT: 0.8, Biome.MEADOW: 0.5}},
	"wader": {"role": "grazer", "size": [0.7, 0.95], "leg": [1.1, 1.35], "body_h": [0.34, 0.4], "neck": [0.7, 0.95], "angle": [55, 70], "legs": 4,
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


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	material = ArtStyle.painted({"brush_strength": 0.22, "rim_amount": 0.25})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	# Each world gets 4 of the 6 grazer body plans, both beasts, both critters and 2-3 birds.
	var grazers := ["slender", "stocky", "bulky", "shellback", "strider", "wader"]
	for i in range(grazers.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = grazers[i]
		grazers[i] = grazers[j]
		grazers[j] = tmp
	for arch in grazers.slice(0, 4) + ["boar", "horned", "hopper", "ferret"]:
		species.append(_make_quadruped(rng, arch))
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
	var hue := rng.randf_range(0.03, 0.12) if rng.randf() < 0.8 else rng.randf_range(0.0, 1.0)
	return Color.from_hsv(hue, rng.randf_range(0.2, 0.6), rng.randf_range(0.35, 0.8))


func _make_quadruped(rng: RandomNumberGenerator, arch: String) -> Species:
	var a: Dictionary = ARCHETYPES[arch]
	var role: String = a.role
	var s := Species.new()
	s.role = role
	s.label = ROLE_LABELS[role]
	s.id = "%s_%d" % [arch, species.size()]
	var size := rng.randf_range(a.size[0], a.size[1])
	s.size = size
	s.name = NameGen.species_name(rng, role)
	for b: int in a.biomes:
		s.biome_pref[b] = a.biomes[b] * rng.randf_range(0.7, 1.0)

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
	s.body_w = s.body_h * rng.randf_range(0.75, 0.95)
	s.leg_len = size * rng.randf_range(a.leg[0], a.leg[1])
	var leg_r := size * (0.085 if stocky else 0.06) * rng.randf_range(0.9, 1.2)
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

	# Temperament decides how close you can get before it reacts.
	s.temperament = {"slender": "skittish", "stocky": "wary", "bulky": "calm", "shellback": "calm", "strider": "wary",
		"wader": "wary", "boar": "wary", "horned": "calm", "hopper": "skittish", "ferret": "curious"}[arch]
	if role == "grazer" and rng.randf() < 0.25:
		s.temperament = "curious"
	if role != "defensive":
		s.flee_radius = {"skittish": rng.randf_range(16.0, 22.0), "wary": rng.randf_range(10.0, 14.0),
			"calm": rng.randf_range(5.0, 7.0), "curious": rng.randf_range(6.0, 8.0)}[s.temperament]

	# --- Colors & pattern ---
	var coat := _coat(rng)
	var belly := coat.lightened(rng.randf_range(0.25, 0.45))
	var accent := coat.darkened(rng.randf_range(0.3, 0.5)) if rng.randf() < 0.7 else coat.lightened(0.5)
	var pattern: String = ["none", "stripes", "spots", "saddle", "none"][rng.randi() % 5]
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

	# --- Body: chest + hips + belly (reads as an animal, not an egg), hump, tail ---
	var kit := MeshKit.new(rng.randi())
	var L := s.body_len
	var H := s.body_h
	var W := s.body_w
	var chest := Vector3(0, H * 0.06, -L * 0.2)
	var hips := Vector3(0, H * 0.02, L * 0.24)
	kit.add_primitive(MeshKit.sphere(0.5, 14, 9), Transform3D(Basis.from_scale(Vector3(W, H * 1.05, L * 0.62)), chest), coat, 0.02, 0.05, null, coat_fn)
	kit.add_primitive(MeshKit.sphere(0.5, 14, 9), Transform3D(Basis.from_scale(Vector3(W * 0.95, H * 0.95, L * 0.55)), hips), coat, 0.02, 0.05, null, coat_fn)
	kit.add_primitive(MeshKit.sphere(0.5, 12, 8), Transform3D(Basis.from_scale(Vector3(W * 0.85, H * 0.8, L * 0.6)), Vector3(0, -H * 0.08, 0)), coat, 0.02, 0.05, null, coat_fn)
	if (stocky or rng.randf() < 0.25) and arch != "shellback":
		# Shoulder hump (big and shaggy on bulky grazers).
		var hump := 1.0 if arch != "bulky" else 1.3
		kit.add_primitive(MeshKit.sphere(0.5, 12, 7), Transform3D(Basis.from_scale(Vector3(W * 0.85, H * 0.7 * hump, L * 0.42)), chest + Vector3(0, H * 0.28 * hump, 0.02)), coat, 0.07 if arch == "bulky" else 0.02, 0.05, null, coat_fn)
	if arch == "bulky":   # shaggy chest mane
		kit.add_primitive(MeshKit.sphere(0.5, 12, 7), Transform3D(Basis.from_scale(Vector3(W * 0.9, H * 0.9, L * 0.3)), chest + Vector3(0, -H * 0.15, -L * 0.2)), accent.lerp(coat, 0.5), 0.08, 0.06)
	if arch == "shellback":
		var shell := accent.lerp(coat, 0.35)
		var plates := func(p: Vector3) -> Color:
			return shell.darkened(0.25) if sin(p.x * 18.0 / size) * sin(p.z * 18.0 / size) > 0.55 else shell
		kit.add_primitive(MeshKit.sphere(0.5, 14, 8), Transform3D(Basis.from_scale(Vector3(W * 1.4, H * 1.2, L * 1.15)), Vector3(0, H * 0.3, 0)), shell, 0.03, 0.05, null, plates)
		kit.add_primitive(MeshKit.cylinder(W * 0.72, W * 0.72, H * 0.12, 16), Transform3D(Basis.from_scale(Vector3(1, 1, L * 1.15 / W)), Vector3(0, -H * 0.05, 0)), shell.darkened(0.15), 0.0, 0.03)
	var tail_len := size * rng.randf_range(0.15, 0.45)
	var tail_root := hips + Vector3(0, H * 0.25, L * 0.24)
	if arch == "ferret":
		tail_len = L * 0.85
	if arch == "strider":
		for i in 5:   # fan of tail plumes
			var tb := Basis(Vector3.UP, (i - 2) * 0.3) * Basis(Vector3.RIGHT, deg_to_rad(-125))
			kit.add_primitive(MeshKit.sphere(0.5, 7, 4), Transform3D(tb * Basis.from_scale(Vector3(size * 0.08, size * 0.35, size * 0.03)), tail_root + tb.y * size * 0.15), accent, 0.0, 0.04)
	elif role == "critter" and arch != "ferret":
		kit.add_primitive(MeshKit.sphere(size * 0.13, 9, 6), Transform3D(Basis(), tail_root), belly, 0.04, 0.05)   # puff tail
	elif arch != "shellback":
		# Tapered tail that hangs down and back, with a tuft for longer ones.
		var tb := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-150, -165) if arch != "ferret" else -110))
		kit.add_primitive(MeshKit.cylinder(size * 0.018, size * 0.05, tail_len, 8), Transform3D(tb, tail_root + tb.y * tail_len * 0.5), coat, 0.0, 0.04, null, coat_fn)
		if tail_len > size * 0.3 and arch != "ferret":
			kit.add_primitive(MeshKit.sphere(size * 0.055, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 1.8, 1)), tail_root + tb.y * tail_len), accent, 0.06, 0.04)
	s.body_mesh = kit.commit(material)

	# --- Head: neck rising from the chest, skull, tapered muzzle, jaw, eyes, ears, horns ---
	s.head_pivot = chest + Vector3(0, H * 0.22, -L * 0.24)
	kit = MeshKit.new(rng.randi())
	var neck_dir := Vector3(0, sin(neck_angle), -cos(neck_angle))
	var neck_r := H * (0.42 if stocky else 0.33)
	var neck_end := neck_dir * (neck_len + neck_r * 0.4)
	_segment(kit, Vector3.ZERO - neck_dir * neck_r * 0.3, neck_end, neck_r, neck_r * 0.72, coat, coat_fn)
	kit.add_primitive(MeshKit.sphere(neck_r * 1.05, 10, 7), Transform3D(Basis.from_scale(Vector3(1, 1.1, 1)), -neck_dir * neck_r * 0.1), coat, 0.0, 0.05, null, coat_fn)   # blend into chest
	var head_tilt := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(20, 40)))
	var fwd := head_tilt * Vector3(0, 0, -1)
	var skull := neck_end + Vector3(0, head_len * 0.12, 0) + fwd * head_len * 0.12
	kit.add_primitive(MeshKit.sphere(0.5, 12, 8), Transform3D(head_tilt * Basis.from_scale(Vector3(head_len * 0.66, head_len * 0.66, head_len * 0.78)), skull), coat, 0.0, 0.05)
	var snout_len := head_len * rng.randf_range(0.45, 0.75)
	if arch == "wader":
		snout_len = head_len * 1.5   # long beak-like bill
	elif arch == "strider":
		snout_len = head_len * 0.55
	elif arch in ["boar", "shellback"]:
		snout_len = head_len * 0.5
	var muzzle_start := skull + fwd * head_len * 0.22 + head_tilt * Vector3(0, -head_len * 0.08, 0)
	var nose := muzzle_start + fwd * snout_len
	var bill := arch in ["wader", "strider"]
	_segment(kit, muzzle_start, nose, head_len * (0.18 if bill else 0.3), head_len * (0.06 if bill else 0.2), Color(0.85, 0.65, 0.3) if bill else belly.lerp(coat, 0.45), Callable())
	if not bill:
		kit.add_primitive(MeshKit.sphere(head_len * 0.13, 8, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 0.8)), nose), Color(0.14, 0.11, 0.1), 0.0, 0.0)   # nose pad
		_segment(kit, muzzle_start + head_tilt * Vector3(0, -head_len * 0.12, 0.02), nose + head_tilt * Vector3(0, -head_len * 0.13, head_len * 0.06), head_len * 0.16, head_len * 0.11, belly, Callable())   # jaw
	for side in [-1.0, 1.0]:
		var eye := skull + head_tilt * Vector3(side * head_len * 0.3, head_len * 0.1, -head_len * 0.16)
		kit.add_primitive(MeshKit.sphere(head_len * 0.09, 9, 6), Transform3D(Basis(), eye), Color(0.07, 0.05, 0.04), 0.0, 0.0)
		kit.add_primitive(MeshKit.sphere(head_len * 0.03, 6, 4), Transform3D(Basis(), eye + Vector3(side * head_len * 0.03, head_len * 0.04, -head_len * 0.04)), Color(1, 1, 1), 0.0, 0.0)   # glint
		kit.add_primitive(MeshKit.sphere(head_len * 0.1, 8, 4), Transform3D(Basis.from_scale(Vector3(1.1, 0.45, 1.1)), eye + Vector3(0, head_len * 0.07, 0)), coat.darkened(0.08), 0.0, 0.03)   # brow
	if not arch in ["shellback", "strider", "wader"]:
		_ears(kit, rng, role, skull, head_len, coat, belly)
	_horns(kit, rng, arch, skull, head_len, size, nose)
	s.head_mesh = kit.commit(material)

	# --- Legs: jointed. Front legs nearly straight; hind legs bend back at the hock. ---
	var thigh_col := coat
	var shin_col := coat.lerp(accent, 0.35)
	var hoof := Color(0.16, 0.13, 0.11)
	var ll := s.leg_len
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(leg_r * 2.0, 9, 6), Transform3D(Basis.from_scale(Vector3(1, 1.3, 1.2)), Vector3(0, -leg_r * 0.6, 0)), thigh_col, 0.0, 0.04)
	var knee := Vector3(0, -ll * 0.5, -ll * 0.04)
	_segment(kit, Vector3(0, -leg_r, 0), knee, leg_r * 1.35, leg_r, thigh_col, Callable())
	_segment(kit, knee, Vector3(0, -ll + leg_r * 0.5, 0), leg_r, leg_r * 0.72, shin_col, Callable())
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.85, leg_r * 0.95, leg_r * 1.3, 8), Transform3D(Basis(), Vector3(0, -ll + leg_r * 0.55, -leg_r * 0.1)), hoof, 0.0, 0.0)
	s.leg_mesh = kit.commit(material)
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(leg_r * 2.4, 9, 6), Transform3D(Basis.from_scale(Vector3(1, 1.3, 1.3)), Vector3(0, -leg_r * 0.8, 0)), thigh_col, 0.0, 0.04, null, coat_fn)
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


func _ears(kit: MeshKit, rng: RandomNumberGenerator, role: String, head_c: Vector3, head_len: float, coat: Color, inner: Color) -> void:
	var style: String = "long" if role == "critter" and rng.randf() < 0.6 else ["pointy", "round", "long", "pointy"][rng.randi() % 4]
	var length := head_len * (0.9 if style == "long" else 0.4)
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
