class_name TerrainChunk
extends Node3D
## One 64 m square of the world. Built from data made by ChunkGenerator on a worker thread.

const LAYER_SOLID := 1          ## blocks movement (terrain, trees, rocks)
const LAYER_INTERACT := 2       ## things the crosshair can target (trees, rocks, bushes)

var coord: Vector2i
var tier := 0

## The trees, rocks and bushes on this chunk, as plain data (id, kind, key, transform, hp).
## Plain data so it can be saved or synced over the network later.
var resources: Array[Dictionary] = []

var _mmis := {}          # mesh key -> MultiMeshInstance3D
var _colliders := {}     # resource index -> CollisionShape3D
var _wobbles := {}       # resource index -> time left


func apply(c: Vector2i, t: int, data: Dictionary, flora: FloraLibrary) -> void:
	coord = c
	tier = t
	name = "Chunk_%d_%d" % [c.x, c.y]
	position = Vector3(c.x * Game.CHUNK_SIZE, 0.0, c.y * Game.CHUNK_SIZE)
	resources = data.resources
	for k in resources.size():
		var r := resources[k]
		r.index = k
		# Damage survives the chunk being rebuilt at a different detail level.
		if Game.resource_hp.has(r.id):
			r.hp = Game.resource_hp[r.id]

	_build_terrain(data, flora)
	_build_multimeshes(data.multimesh, flora)
	if tier == 0:
		_build_resource_colliders(flora)


func _build_terrain(data: Dictionary, flora: FloraLibrary) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.mesh[0]
	arrays[Mesh.ARRAY_NORMAL] = data.mesh[1]
	arrays[Mesh.ARRAY_COLOR] = data.mesh[2]
	arrays[Mesh.ARRAY_INDEX] = data.mesh[3]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, flora.terrain_material)
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	# Far terrain doesn't need to cast shadows (sun shadows only reach ~100 m anyway).
	if tier == 2:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	var heights: PackedFloat32Array = data.collision
	if heights.is_empty():
		return
	var shape := HeightMapShape3D.new()
	shape.map_width = data.collision_width
	shape.map_depth = data.collision_width
	shape.map_data = heights
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = LAYER_SOLID
	body.collision_mask = 0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(Game.CHUNK_SIZE * 0.5, 0.0, Game.CHUNK_SIZE * 0.5)  # the shape is centered
	col.scale = Vector3.ONE * float(data.step)
	body.add_child(col)
	add_child(body)


func _build_multimeshes(buffers: Dictionary, flora: FloraLibrary) -> void:
	for key: String in buffers:
		var buf: PackedFloat32Array = buffers[key]
		var kind := FloraLibrary.kind_of_key(key)
		var cat := FloraLibrary.category_of(kind)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = flora.meshes[key]
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.name = key
		mmi.multimesh = mm
		_mmis[key] = mmi
		var vis: float = FloraLibrary.VIS_RANGE[cat]
		if vis > 0.0:
			mmi.visibility_range_end = vis
			mmi.visibility_range_end_margin = 10.0
		if cat in ["grass", "flower", "fern"] or (cat in ["bush", "clutter"] and tier > 0):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_resource_colliders(flora: FloraLibrary) -> void:
	# Two bodies: solid things (trees, rocks) and walk-through things (bushes).
	# Each shape remembers which resource it belongs to, so the crosshair / tools can find it.
	var solid := StaticBody3D.new()
	solid.name = "Solid"
	solid.collision_layer = LAYER_SOLID | LAYER_INTERACT
	solid.collision_mask = 0
	var soft := StaticBody3D.new()
	soft.name = "Soft"
	soft.collision_layer = LAYER_INTERACT
	soft.collision_mask = 0
	for k in resources.size():
		var r := resources[k]
		var info: Dictionary = FloraLibrary.KINDS[r.kind]
		var t: Transform3D = r.transform
		var s := t.basis.get_scale().x
		var local := t.origin - position
		var col := CollisionShape3D.new()
		col.set_meta("resource_index", k)
		_colliders[k] = col
		col.shape = flora.shapes[info.shape]
		var lift: float = FloraLibrary.SHAPE_LIFT[info.shape]
		# Logs are long boxes that turn with the log; other shapes only need position + size.
		var rot := Basis(Vector3.UP, t.basis.get_euler().y) if info.shape == "log" else Basis()
		if r.kind == "boulder":
			s *= 1.6
		col.transform = Transform3D(rot * Basis.from_scale(Vector3.ONE * s), local + Vector3.UP * lift * s)
		(solid if FloraLibrary.KINDS[r.kind].solid else soft).add_child(col)
	add_child(solid)
	add_child(soft)


## Given a raycast hit on one of this chunk's bodies, return the resource it hit (or {}).
func resource_from_hit(body: CollisionObject3D, shape_idx: int) -> Dictionary:
	var owner_id := body.shape_find_owner(shape_idx)
	var node := body.shape_owner_get_owner(owner_id) as Node
	if node and node.has_meta("resource_index"):
		return resources[node.get_meta("resource_index")]
	return {}


# --- Gathering feedback -----------------------------------------------------------

const WOBBLE_TIME := 0.45


## Shake a tree / bush / rock that was just hit.
func wobble(index: int) -> void:
	_wobbles[index] = WOBBLE_TIME
	set_process(true)


## Hide a gathered resource and remove its collider.
func remove_resource(index: int) -> void:
	_wobbles.erase(index)
	_set_instance(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	if _colliders.has(index):
		_colliders[index].queue_free()
		_colliders.erase(index)
	resources[index].removed = true


func get_resource_mesh(index: int) -> Mesh:
	var key: String = resources[index].get("mm_key", resources[index].key)
	return _mmis[key].multimesh.mesh if _mmis.has(key) else null


func _ready() -> void:
	set_process(false)


func _process(delta: float) -> void:
	for index: int in _wobbles.keys():
		var t: float = _wobbles[index] - delta
		var r := resources[index]
		var xf: Transform3D = r.transform
		xf.origin -= position
		if t <= 0.0:
			_wobbles.erase(index)
			_set_instance(index, xf)
			continue
		_wobbles[index] = t
		# Damped sway, stronger for tall things.
		var k := t / WOBBLE_TIME
		var amount := sin((1.0 - k) * 28.0) * k * (0.06 if FloraLibrary.category_of(r.kind) == "tree" else 0.03)
		var axis := Vector3(cos(index * 1.7), 0, sin(index * 1.7)).normalized()
		_set_instance(index, Transform3D(Basis(axis, amount) * xf.basis, xf.origin))
	if _wobbles.is_empty():
		set_process(false)


func _set_instance(index: int, xf: Transform3D) -> void:
	var r := resources[index]
	if not r.has("mm_index") or not _mmis.has(r.mm_key):
		return
	_mmis[r.mm_key].multimesh.set_instance_transform(r.mm_index, xf)


## Point every MultiMesh at freshly generated meshes (after the model detail setting changes).
func swap_meshes(flora: FloraLibrary) -> void:
	for key: String in _mmis:
		if flora.meshes.has(key):
			_mmis[key].multimesh.mesh = flora.meshes[key]
