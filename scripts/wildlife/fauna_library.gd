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
	var leg_mesh: ArrayMesh
	var wing_mesh: ArrayMesh
	var call_sound: AudioStreamWAV

const ROLE_LABELS := {"grazer": "Grazer", "defensive": "Territorial beast", "critter": "Critter", "bird": "Bird"}

var species: Array[Species] = []
var material: ShaderMaterial
var _pal: WorldPalette


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	material = ArtStyle.painted({"brush_strength": 0.22, "rim_amount": 0.25})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 977 + 3
	# Three grazers of different sizes, one or two territorial beasts, critters and birds.
	for size_class in [0.6, 1.0, 1.55]:
		species.append(_make_quadruped(rng, "grazer", size_class * rng.randf_range(0.9, 1.15)))
	for i in rng.randi_range(1, 2):
		species.append(_make_quadruped(rng, "defensive", rng.randf_range(0.85, 1.15)))
	for i in 2:
		species.append(_make_quadruped(rng, "critter", rng.randf_range(0.26, 0.36)))
	for i in 2:
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


func _make_quadruped(rng: RandomNumberGenerator, role: String, size: float) -> Species:
	var s := Species.new()
	s.role = role
	s.label = ROLE_LABELS[role]
	s.id = "%s_%d" % [role, species.size()]
	s.size = size
	s.name = NameGen.species_name(rng, role)
	for b in [Biome.MEADOW, Biome.FOREST, Biome.AUTUMN, Biome.DRYLANDS]:
		s.biome_pref[b] = rng.randf_range(0.1, 1.0)

	# --- Proportions ---
	var stocky := role == "defensive"
	s.body_len = size * rng.randf_range(0.9, 1.25)
	s.body_h = size * (rng.randf_range(0.5, 0.62) if stocky else rng.randf_range(0.38, 0.5))
	s.body_w = s.body_h * rng.randf_range(0.75, 0.95)
	s.leg_len = size * (rng.randf_range(0.32, 0.45) if stocky else rng.randf_range(0.5, 0.85))
	if role == "critter":
		s.leg_len = size * rng.randf_range(0.18, 0.3)
	var leg_r := size * (0.085 if stocky else 0.065) * rng.randf_range(0.9, 1.2)
	var neck_len := size * (rng.randf_range(0.1, 0.2) if stocky else rng.randf_range(0.22, 0.5))
	var neck_angle := deg_to_rad(rng.randf_range(15, 35) if stocky else rng.randf_range(35, 65))
	var head_len := size * rng.randf_range(0.34, 0.46)

	# --- Behavior ---
	match role:
		"grazer":
			s.hp = 25.0 * pow(size, 1.6) + 10.0
			s.walk_speed = 1.2 + size * 0.4
			s.run_speed = 6.0 + size * 2.0
			s.flee_radius = rng.randf_range(11.0, 18.0)
			s.herd = Vector2i(1, 3) if size > 1.3 else Vector2i(2, 5)
			s.yield_scale = size
		"defensive":
			s.hp = 70.0 * size
			s.walk_speed = 1.1
			s.run_speed = 6.5
			s.flee_radius = 0.0
			s.damage = rng.randf_range(10.0, 15.0)
			s.herd = Vector2i(1, 2)
			s.yield_scale = 1.2 * size
		"critter":
			s.hp = 5.0
			s.walk_speed = 1.0
			s.run_speed = 5.0
			s.flee_radius = 7.0
			s.herd = Vector2i(1, 1)
			s.yield_scale = 0.2

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

	# --- Body: torso (+ optional hump) + tail ---
	var kit := MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(0.5, 14, 8), Transform3D(Basis().scaled(Vector3(s.body_w, s.body_h, s.body_len)), Vector3.ZERO), coat, 0.02, 0.05, null, coat_fn)
	if stocky or rng.randf() < 0.25:
		kit.add_primitive(MeshKit.sphere(0.5, 12, 7), Transform3D(Basis().scaled(Vector3(s.body_w * 0.9, s.body_h * 0.8, s.body_len * 0.5)), Vector3(0, s.body_h * 0.25, -s.body_len * 0.18)), coat, 0.02, 0.05, null, coat_fn)
	var tail_len := size * rng.randf_range(0.1, 0.5)
	if role == "critter" or rng.randf() < 0.3:
		kit.add_primitive(MeshKit.sphere(size * 0.12, 9, 6), Transform3D(Basis(), Vector3(0, s.body_h * 0.15, s.body_len * 0.5)), belly, 0.03, 0.05)   # puff tail
	else:
		var tb := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(-130, -160)))
		kit.add_primitive(MeshKit.cylinder(size * 0.015, size * 0.04, tail_len, 7), Transform3D(tb, Vector3(0, s.body_h * 0.2, s.body_len * 0.48) + tb.y * tail_len * 0.5), accent, 0.0, 0.04)
	s.body_mesh = kit.commit(material)

	# --- Head: neck + skull + snout + eyes + ears + horns, pivoting at the neck base ---
	s.head_pivot = Vector3(0, s.body_h * 0.22, -s.body_len * 0.4)
	kit = MeshKit.new(rng.randi())
	var neck_dir := Vector3(0, sin(neck_angle), -cos(neck_angle))
	var neck_basis := Basis(Quaternion(Vector3.UP, neck_dir))
	var neck_r := s.body_h * (0.45 if stocky else 0.36)
	kit.add_primitive(MeshKit.cylinder(neck_r * 0.75, neck_r, neck_len + neck_r, 10), Transform3D(neck_basis, neck_dir * (neck_len + neck_r) * 0.5), coat, 0.0, 0.05, null, coat_fn)
	var head_c := neck_dir * (neck_len + neck_r * 0.6) + Vector3(0, head_len * 0.1, -head_len * 0.25)
	var head_tilt := Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(10, 30)))
	kit.add_primitive(MeshKit.sphere(0.5, 12, 7), Transform3D(head_tilt * Basis.from_scale(Vector3(head_len * 0.62, head_len * 0.6, head_len)), head_c), coat, 0.0, 0.05)
	var snout_c := head_c + head_tilt * Vector3(0, -head_len * 0.12, -head_len * 0.5)
	var snout_len := head_len * rng.randf_range(0.35, 0.7)
	kit.add_primitive(MeshKit.sphere(0.5, 10, 6), Transform3D(head_tilt * Basis.from_scale(Vector3(head_len * 0.4, head_len * 0.36, snout_len)), snout_c), belly.lerp(coat, 0.4), 0.0, 0.04)
	kit.add_primitive(MeshKit.sphere(head_len * 0.06, 8, 5), Transform3D(Basis(), snout_c + head_tilt * Vector3(0, head_len * 0.05, -snout_len * 0.48)), Color(0.12, 0.1, 0.1), 0.0, 0.0)  # nose
	for side in [-1.0, 1.0]:
		var eye := head_c + head_tilt * Vector3(side * head_len * 0.3, head_len * 0.12, -head_len * 0.18)
		kit.add_primitive(MeshKit.sphere(head_len * 0.075, 8, 5), Transform3D(Basis(), eye), Color(0.06, 0.05, 0.05), 0.0, 0.0)
		kit.add_primitive(MeshKit.sphere(head_len * 0.025, 6, 4), Transform3D(Basis(), eye + Vector3(side * 0.01, head_len * 0.03, -head_len * 0.05)), Color(1, 1, 1), 0.0, 0.0)  # glint
	_ears(kit, rng, role, head_c, head_len, coat, belly)
	_horns(kit, rng, role, head_c, head_len, size, snout_c)
	s.head_mesh = kit.commit(material)

	# --- Leg (shared by all four) ---
	kit = MeshKit.new(rng.randi())
	kit.add_primitive(MeshKit.sphere(leg_r * 1.6, 9, 6), Transform3D(Basis(), Vector3(0, -leg_r * 0.5, 0)), coat, 0.0, 0.04)
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.7, leg_r, s.leg_len, 8), Transform3D(Basis(), Vector3(0, -s.leg_len * 0.5, 0)), coat.lerp(accent, 0.3), 0.0, 0.04)
	kit.add_primitive(MeshKit.cylinder(leg_r * 0.85, leg_r * 0.8, leg_r * 1.4, 8), Transform3D(Basis(), Vector3(0, -s.leg_len + leg_r * 0.6, 0)), Color(0.15, 0.12, 0.1), 0.0, 0.0)  # hoof
	s.leg_mesh = kit.commit(material)
	var lx := s.body_w * 0.3
	var lz := s.body_len * 0.32
	var ly := -s.body_h * 0.2
	s.leg_offsets = [Vector3(-lx, ly, -lz), Vector3(lx, ly, -lz), Vector3(-lx, ly, lz), Vector3(lx, ly, lz)]

	s.call_sound = SoundGen.creature_call(role, size, rng)
	return s


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


func _horns(kit: MeshKit, rng: RandomNumberGenerator, role: String, head_c: Vector3, head_len: float, size: float, snout_c: Vector3) -> void:
	var horn_col := Color.from_hsv(rng.randf_range(0.08, 0.12), 0.2, rng.randf_range(0.7, 0.9))
	if role == "defensive":
		# Tusks curving up from the snout.
		for side in [-1.0, 1.0]:
			var b := Basis(Vector3.FORWARD, side * deg_to_rad(-25)) * Basis(Vector3.RIGHT, deg_to_rad(-35))
			var length := head_len * rng.randf_range(0.45, 0.7)
			kit.add_primitive(MeshKit.cylinder(0.0, head_len * 0.06, length, 7), Transform3D(b, snout_c + Vector3(side * head_len * 0.15, 0, 0) + b.y * length * 0.45), horn_col, 0.0, 0.03)
		return
	if role == "critter" or rng.randf() < 0.35:
		return
	var style: String = ["straight", "curved", "antlers"][rng.randi() % 3]
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
