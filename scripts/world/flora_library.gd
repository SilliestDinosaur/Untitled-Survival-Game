class_name FloraLibrary
extends RefCounted
## Generates this world's plant and rock species from the seed: their meshes, names and rules.
## Built once per world on the main thread; worker threads only read from it.

const Biome := WorldGen.Biome

## Which trees grow in which biome: [kind, weight].
const BIOME_TREES := {
	Biome.MEADOW: [["oak", 0.7], ["birch", 0.2], ["pine", 0.1]],
	Biome.FOREST: [["pine", 0.55], ["oak", 0.45]],
	Biome.AUTUMN: [["autumn_oak", 0.6], ["birch", 0.4]],
	Biome.DRYLANDS: [["oak", 0.6], ["pine", 0.4]],
}
## Base tree density per biome (0..1 chance per placement attempt).
const BIOME_TREE_DENSITY := {
	Biome.MEADOW: 0.07, Biome.FOREST: 0.6, Biome.AUTUMN: 0.38, Biome.DRYLANDS: 0.035,
}
const BIOME_BUSH_DENSITY := {
	Biome.MEADOW: 0.25, Biome.FOREST: 0.35, Biome.AUTUMN: 0.3, Biome.DRYLANDS: 0.5,
}

## kind -> info shared by all variants of that kind.
## category: tree / bush / rock / grass / flower. solid: blocks the player.
const KINDS := {
	"pine": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 100},
	"oak": {"category": "tree", "label": "Tree", "variants": 3, "solid": true, "hp": 100},
	"autumn_oak": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 100},
	"birch": {"category": "tree", "label": "Tree", "variants": 2, "solid": true, "hp": 80},
	"bush": {"category": "bush", "label": "Shrub", "variants": 2, "solid": false, "hp": 40},
	"berry": {"category": "bush", "label": "Berry bush", "variants": 2, "solid": false, "hp": 40},
	"rock": {"category": "rock", "label": "Stone", "variants": 4, "solid": true, "hp": 150},
	"ore": {"category": "rock", "label": "Ore deposit", "variants": 2, "solid": true, "hp": 220},
	"grass": {"category": "grass", "label": "", "variants": 3, "solid": false, "hp": 0},
	"flower": {"category": "flower", "label": "", "variants": 3, "solid": false, "hp": 0},
}

## Fade-out distance per category (0 = always visible; trees are handled by chunk detail levels).
const VIS_RANGE := {"tree": 0.0, "bush": 150.0, "rock": 260.0, "grass": 60.0, "flower": 55.0}

var meshes := {}         # "pine_0" -> ArrayMesh
var variants := {}       # "pine" -> ["pine_0", "pine_1", ...]
var species_names := {}  # "pine" -> "Ember Spire"
var shapes := {}         # "tree"/"rock"/"bush" -> Shape3D

var foliage_material: ShaderMaterial
var grass_material: ShaderMaterial
var rock_material: ShaderMaterial
var terrain_material: ShaderMaterial

var _pal: WorldPalette


func _init(seed_value: int, pal: WorldPalette) -> void:
	_pal = pal
	_build_materials()
	_build_shapes()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 5
	for kind: String in KINDS:
		species_names[kind] = NameGen.species_name(rng, kind.trim_prefix("autumn_"))
		variants[kind] = []
		for i in KINDS[kind].variants:
			var key := "%s_%d" % [kind, i]
			meshes[key] = _build_mesh(kind, i, rng)
			variants[kind].append(key)


static func category_of(kind: String) -> String:
	return KINDS[kind].category


func display_name(kind: String) -> String:
	return species_names.get(kind, kind.capitalize())


# --- Materials & collision --------------------------------------------------

func _build_materials() -> void:
	foliage_material = ArtStyle.material(preload("res://shaders/foliage.gdshader"))
	grass_material = ArtStyle.material(preload("res://shaders/grass.gdshader"), {"brush_strength": 0.15})
	rock_material = ArtStyle.painted({"brush_strength": 0.4, "rim_amount": 0.1})
	terrain_material = ArtStyle.material(preload("res://shaders/terrain.gdshader"))


func _build_shapes() -> void:
	var trunk := CylinderShape3D.new()
	trunk.radius = 0.4
	trunk.height = 4.0
	shapes.tree = trunk
	var boulder := SphereShape3D.new()
	boulder.radius = 0.95
	shapes.rock = boulder
	var bush := SphereShape3D.new()
	bush.radius = 0.8
	shapes.bush = bush


# --- Mesh generation ---------------------------------------------------------

func _build_mesh(kind: String, index: int, rng: RandomNumberGenerator) -> ArrayMesh:
	var kit := MeshKit.new(rng.randi())
	match kind:
		"pine": _pine(kit, rng)
		"oak": _oak(kit, rng, _pal.oak_leaves)
		"autumn_oak": _oak(kit, rng, _pal.autumn_leaves[index % _pal.autumn_leaves.size()])
		"birch": _birch(kit, rng)
		"bush": _bush(kit, rng, false)
		"berry": _bush(kit, rng, true)
		"rock": _rock(kit, rng, false)
		"ore": _rock(kit, rng, true)
		"grass": _grass(kit, rng)
		"flower": _flower(kit, rng, _pal.flowers[index % _pal.flowers.size()])
	var cat: String = KINDS[kind].category
	var mat: Material = rock_material if cat == "rock" else (grass_material if cat in ["grass", "flower"] else foliage_material)
	return kit.commit(mat)


func _vary(c: Color, rng: RandomNumberGenerator, amount := 0.06) -> Color:
	return Color.from_hsv(fposmod(c.h + rng.randf_range(-amount, amount) * 0.3, 1.0), c.s, clampf(c.v + rng.randf_range(-amount, amount), 0, 1))


# Painterly trees: each canopy is lit as one soft volume (shared puff_center),
# with small leaf clumps on the surface to break up the silhouette.

func _pine(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(7.0, 10.5)
	var trunk_r := rng.randf_range(0.24, 0.32)
	var bark := _vary(_pal.bark, rng)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.5, trunk_r, h * 0.5, 7), Transform3D(Basis(), Vector3(0, h * 0.25, 0)), bark, 0.03)
	var tiers := rng.randi_range(3, 4)
	var base := h * rng.randf_range(0.2, 0.3)
	var radius := rng.randf_range(2.0, 2.7)
	var tier_h := (h - base) / tiers * 1.75
	var leaves := _vary(_pal.pine_leaves, rng)
	for t in tiers:
		var f := float(t) / tiers
		var r := lerpf(radius, radius * 0.45, f)
		var y := base + (h - base - tier_h) * (float(t) / (tiers - 1))
		var twist := Basis(Vector3.UP, rng.randf() * TAU)
		# Each tier is lit from its own core, so the layers read as separate soft skirts.
		kit.add_primitive(MeshKit.cylinder(0.0, r, tier_h, 9), Transform3D(twist, Vector3(0, y + tier_h * 0.5, 0)),
			leaves.lightened(f * 0.14), 0.18, 0.06, Vector3(0, y + tier_h * 0.2, 0))


func _oak(kit: MeshKit, rng: RandomNumberGenerator, leaf: Color) -> void:
	var h := rng.randf_range(2.6, 3.8)
	var trunk_r := rng.randf_range(0.3, 0.42)
	var bark := _vary(_pal.bark, rng)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.6, trunk_r, h + 0.8, 8), Transform3D(Basis(), Vector3(0, (h + 0.8) * 0.5, 0)), bark, 0.06)
	for b in rng.randi_range(2, 3):
		var yaw := rng.randf() * TAU
		var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(rng.randf_range(30, 50)))
		var length := rng.randf_range(1.2, 1.8)
		var start := Vector3(0, h * rng.randf_range(0.6, 0.9), 0)
		kit.add_primitive(MeshKit.cylinder(trunk_r * 0.22, trunk_r * 0.42, length, 6), Transform3D(tilt, start + tilt.y * length * 0.5), bark)

	var center := Vector3(0, h + 1.3, 0)
	var base_leaf := _vary(leaf, rng)
	var blobs: Array = [[center, rng.randf_range(1.9, 2.3)]]
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var d := rng.randf_range(1.1, 1.7)
		blobs.append([center + Vector3(cos(a) * d, rng.randf_range(-0.7, 0.8), sin(a) * d), rng.randf_range(1.1, 1.6)])
	for bl: Array in blobs:
		kit.add_primitive(MeshKit.sphere(bl[1], 9, 5), Transform3D(Basis().scaled(Vector3(1, 0.85, 1)), bl[0]),
			base_leaf.lightened(rng.randf_range(-0.05, 0.06)), bl[1] * 0.2, 0.07, center)
	_leaf_clumps(kit, rng, blobs, center, base_leaf, rng.randi_range(7, 10), 0.4)


func _birch(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var h := rng.randf_range(6.0, 8.5)
	var trunk_r := rng.randf_range(0.15, 0.2)
	kit.add_primitive(MeshKit.cylinder(trunk_r * 0.6, trunk_r, h, 7), Transform3D(Basis(), Vector3(0, h * 0.5, 0)), _pal.birch_bark, 0.0, 0.03)
	for i in rng.randi_range(4, 7):
		var y := rng.randf_range(0.4, h * 0.7)
		var r := lerpf(trunk_r, trunk_r * 0.6, y / h) * 1.06
		kit.add_primitive(MeshKit.cylinder(r, r, rng.randf_range(0.05, 0.12), 7), Transform3D(Basis(), Vector3(0, y, 0)), Color(0.2, 0.18, 0.17), 0.0, 0.0)
	var leaf := _vary(_pal.birch_leaves, rng)
	var center := Vector3(0, h * 0.78, 0)
	var blobs: Array = []
	var clumps := rng.randi_range(4, 6)
	for i in clumps:
		var f := float(i) / (clumps - 1)
		var r := lerpf(1.05, 0.6, f) * rng.randf_range(0.85, 1.15)
		var a := rng.randf() * TAU
		var spread := lerpf(0.75, 0.2, f)
		var pos := Vector3(cos(a) * spread, lerpf(h * 0.55, h * 0.98, f), sin(a) * spread)
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis().scaled(Vector3(1, 1.25, 1)), pos),
			leaf.lightened(rng.randf_range(-0.06, 0.08)), r * 0.22, 0.07, center)
	_leaf_clumps(kit, rng, blobs, center, leaf, 5, 0.3)


## Small leafy bumps scattered over the canopy surface.
func _leaf_clumps(kit: MeshKit, rng: RandomNumberGenerator, blobs: Array, center: Vector3, leaf: Color, count: int, size: float) -> void:
	for i in count:
		var bl: Array = blobs[rng.randi() % blobs.size()]
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 1.0), rng.randf_range(-1, 1)).normalized()
		var r := size * rng.randf_range(0.8, 1.3)
		var pos: Vector3 = bl[0] + dir * float(bl[1]) * 0.85
		kit.add_primitive(MeshKit.sphere(r, 6, 4), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(0.02, 0.12)), r * 0.2, 0.05, center)


func _bush(kit: MeshKit, rng: RandomNumberGenerator, berries: bool) -> void:
	var leaf := _vary(_pal.bush_leaves, rng)
	var center := Vector3(0, 0.45, 0)
	var blobs := []
	for i in rng.randi_range(3, 4):
		var r := rng.randf_range(0.5, 0.85)
		var pos := Vector3(rng.randf_range(-0.5, 0.5), r * 0.7, rng.randf_range(-0.5, 0.5))
		blobs.append([pos, r])
		kit.add_primitive(MeshKit.sphere(r, 8, 5), Transform3D(Basis(), pos), leaf.lightened(rng.randf_range(-0.05, 0.07)), r * 0.25, 0.07, center)
	if berries:
		for i in rng.randi_range(10, 16):
			var blob: Array = blobs[rng.randi() % blobs.size()]
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.0, 1.0), rng.randf_range(-1, 1)).normalized()
			kit.add_primitive(MeshKit.sphere(0.09, 6, 4), Transform3D(Basis(), blob[0] + dir * blob[1] * 0.95), _pal.berry, 0.0, 0.04)


func _rock(kit: MeshKit, rng: RandomNumberGenerator, ore: bool) -> void:
	var col := _vary(_pal.rock, rng, 0.05)
	var squash := Vector3(rng.randf_range(1.0, 1.4), rng.randf_range(0.65, 0.9), rng.randf_range(0.9, 1.2))
	kit.add_primitive(MeshKit.sphere(1.0, 11, 7), Transform3D(Basis().scaled(squash), Vector3(0, 0.25, 0)), col, 0.3, 0.08)
	if rng.randf() < 0.5:
		var off := Vector3(rng.randf_range(0.7, 1.1), 0.0, rng.randf_range(-0.6, 0.6))
		kit.add_primitive(MeshKit.sphere(0.55, 9, 5), Transform3D(Basis().scaled(Vector3(1, 0.8, 1)), off), col.darkened(0.06), 0.2, 0.08)
	if ore:
		for i in rng.randi_range(4, 7):
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.3, 1.0), rng.randf_range(-1, 1)).normalized()
			var length := rng.randf_range(0.6, 1.1)
			var b := Basis(Quaternion(Vector3.UP, dir))
			var pos := Vector3(dir.x * squash.x, dir.y * squash.y, dir.z * squash.z) * 0.75 + Vector3(0, 0.25, 0)
			kit.add_primitive(MeshKit.cylinder(0.0, rng.randf_range(0.12, 0.2), length, 5), Transform3D(b, pos + dir * length * 0.4),
				_vary(_pal.ore_crystal, rng, 0.08).lightened(0.1), 0.0, 0.05)


func _grass(kit: MeshKit, rng: RandomNumberGenerator) -> void:
	# Grey-ish colors: each tuft is tinted by the ground color under it at placement time.
	kit.force_up_normals = true
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, 0.3)
		var base := Vector3(cos(a) * d, -0.05, sin(a) * d)
		var yaw := rng.randf() * TAU
		var side := Vector3(cos(yaw), 0, sin(yaw)) * rng.randf_range(0.035, 0.06)
		var lean := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.05, 0.25)
		var tip := base + lean + Vector3.UP * rng.randf_range(0.35, 0.75)
		kit.add_tri(base - side, base + side, tip, Color(0.8, 0.8, 0.8), Color(0.8, 0.8, 0.8), Color(1.1, 1.1, 1.1))


func _flower(kit: MeshKit, rng: RandomNumberGenerator, petal: Color) -> void:
	kit.force_up_normals = true
	var stem := _pal.meadow_grass.darkened(0.25)
	for i in rng.randi_range(2, 4):
		var base := Vector3(rng.randf_range(-0.25, 0.25), -0.05, rng.randf_range(-0.25, 0.25))
		var top := base + Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.3, 0.55), rng.randf_range(-0.08, 0.08))
		var side := Vector3(0.025, 0, 0.02)
		kit.add_tri(base - side, base + side, top, stem)
		kit.add_primitive(MeshKit.sphere(rng.randf_range(0.06, 0.1), 5, 3), Transform3D(Basis().scaled(Vector3(1, 0.6, 1)), top), _vary(petal, rng, 0.05), 0.0, 0.03)
