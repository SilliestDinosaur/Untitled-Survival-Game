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
var _shadow_mmis := {}   # mesh key -> its shadow-only twin (near trees cast shadows from their low-poly shape)
var _colliders := {}     # resource index -> CollisionShape3D
var _wobbles := {}       # resource index -> time left
var _bare := {}          # resource index -> MeshInstance3D showing the harvested look
var _regrow_check := 0.0
var _by_id := {}         # resource id -> index
var _own := {}           # resource index -> MeshInstance3D: plants built to their own spot (vines on a rock face)


func apply(c: Vector2i, t: int, data: Dictionary, flora: FloraLibrary) -> void:
	coord = c
	tier = t
	name = "Chunk_%d_%d" % [c.x, c.y]
	position = Vector3(c.x * Game.CHUNK_SIZE, 0.0, c.y * Game.CHUNK_SIZE)
	resources = data.resources
	TerrainEdit.remember_trees(c, resources)   # so aiming a building here needn't place the chunk's trees again
	_by_id.clear()
	for k in resources.size():
		var r := resources[k]
		r.index = k
		_by_id[r.id] = k
		# Damage survives the chunk being rebuilt at a different detail level.
		if Game.resource_hp.has(r.id):
			r.hp = Game.resource_hp[r.id]

	_build_terrain(data, flora)
	_build_multimeshes(data.multimesh, flora)
	_build_own_meshes(flora)
	if tier == 0:
		_build_resource_colliders(flora)
	# Plants that were hand-harvested recently show their bare look.
	for k in resources.size():
		var r := resources[k]
		if flora.has_mesh(String(r.key) + "_bare") and Game.is_harvested(r.id) and r.has("mm_index"):
			set_bare(k, true)


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

	var tri: ConcavePolygonShape3D = data.get("collision_shape")
	if tri != null:
		# Solid ground near caves: the collider is the same triangles as the mesh, made on the worker thread
		# (see ChunkGenerator.generate).
		var tbody := StaticBody3D.new()
		tbody.name = "TerrainBody"
		tbody.collision_layer = LAYER_SOLID
		tbody.collision_mask = 0
		var tcol := CollisionShape3D.new()
		tcol.shape = tri
		tbody.add_child(tcol)
		add_child(tbody)
		return
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
		mm.mesh = flora.mesh(key)
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
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF   # dissolve out over the margin, not a hard cut
		# Shadows only where they read: tiny ground clutter and far bushes don't need them.
		var small: bool = FloraLibrary.KINDS[kind].get("shape", "") == "small"
		# Trees a little way off skip shadows too: the sun's shadow only reaches 100-160 m, and they are re-drawn into it.
		# (With long shadows, High and Ultra, the next ring of trees keeps casting them, from these far twins: else
		# tree shadows would pop onto the ground as you walk up, where the full-detail ring begins, well inside them.)
		var far_shadows: bool = Settings.shadow_quality in ["High", "Ultra"] and tier == 1
		if cat in ["grass", "flower", "fern"] or small or (cat in ["bush", "clutter"] and tier > 0) or (cat == "tree" and tier > 0 and not far_shadows):
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		# Near trees cast their shadow from their low-poly twin: the shadow can't show the difference, and the sun's
		# shadow draws every caster again in each of its cascades.
		if cat == "tree" and not key.ends_with("_lod") and flora.has_mesh(key + "_lod") \
				and mmi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var smm := MultiMesh.new()
			smm.transform_format = MultiMesh.TRANSFORM_3D
			smm.use_colors = true
			smm.mesh = flora.mesh(key + "_lod")
			smm.instance_count = mm.instance_count
			smm.buffer = buf
			var smmi := MultiMeshInstance3D.new()
			smmi.name = key + "_shadow"
			smmi.multimesh = smm
			smmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			_shadow_mmis[key] = smmi
			add_child(smmi)


## Plants with a mesh of their own (made with the chunk, on its worker): each one drawn on its own.
func _build_own_meshes(flora: FloraLibrary) -> void:
	for k in resources.size():
		var r := resources[k]
		if not r.has("vine_arrays") or r.get("removed", false):
			continue
		var arr: Array = r.vine_arrays
		r.erase("vine_arrays")
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = arr[0]
		arrays[Mesh.ARRAY_NORMAL] = arr[1]
		arrays[Mesh.ARRAY_COLOR] = arr[2]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(0, flora.mesh(String(r.key)).surface_get_material(0))
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var xf: Transform3D = r.transform
		xf.origin -= position
		mi.transform = xf
		mi.visibility_range_end = FloraLibrary.VIS_RANGE[FloraLibrary.category_of(r.kind)]
		mi.visibility_range_end_margin = 10.0
		mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_own[k] = mi


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
		elif r.kind == "mossy_log":
			s *= 1.8   # a fallen giant: about twice an ordinary log
		col.transform = Transform3D(rot * Basis.from_scale(Vector3.ONE * s), local + Vector3.UP * lift * s)
		(solid if FloraLibrary.KINDS[r.kind].solid else soft).add_child(col)
	add_child(solid)
	add_child(soft)


## Given a raycast hit on one of this chunk's bodies, return the resource it hit (or {}).
func resource_from_hit(body: CollisionObject3D, shape_idx: int) -> Dictionary:
	# The ray can report a shape that was removed this frame (the node was just gathered).
	var total := 0
	for o in body.get_shape_owners():
		total += body.shape_owner_get_shape_count(o)
	if shape_idx < 0 or shape_idx >= total:
		return {}
	var owner_id := body.shape_find_owner(shape_idx)
	var node := body.shape_owner_get_owner(owner_id) as Node
	if node and node.has_meta("resource_index"):
		return resources[node.get_meta("resource_index")]
	return {}


# --- Gathering feedback -----------------------------------------------------------

const WOBBLE_TIME := 0.35


## Shake a tree / bush / rock that was just hit.
func wobble(index: int) -> void:
	_wobbles[index] = WOBBLE_TIME
	set_process(true)


func index_of(id: String) -> int:
	return _by_id.get(id, -1)


## Hide a gathered resource and remove its collider.
func remove_resource(index: int) -> void:
	resources[index].gone = true
	_wobbles.erase(index)
	if _bare.has(index):
		_bare[index].queue_free()
		_bare.erase(index)
	_set_instance(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	if _colliders.has(index):
		_colliders[index].queue_free()
		_colliders.erase(index)
	resources[index].removed = true


## Swap a plant between its normal and harvested ("bare") look.
func set_bare(index: int, on: bool) -> void:
	var r := resources[index]
	var key := String(r.key) + "_bare"
	if on == _bare.has(index) or not Game.flora.has_mesh(key) or r.get("removed", false):
		return
	var xf: Transform3D = r.transform
	xf.origin -= position
	if on:
		var mi := MeshInstance3D.new()
		mi.mesh = Game.flora.mesh(key)
		mi.transform = xf
		add_child(mi)
		_bare[index] = mi
		_set_instance(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))
	else:
		_bare[index].queue_free()
		_bare.erase(index)
		_set_instance(index, xf)
	set_process(true)


func get_resource_mesh(index: int) -> Mesh:
	if _own.has(index):
		return (_own[index] as MeshInstance3D).mesh
	var key: String = resources[index].get("mm_key", resources[index].key)
	return _mmis[key].multimesh.mesh if _mmis.has(key) else null


func _ready() -> void:
	set_process(not _bare.is_empty())   # bare plants need regrow checks


func _process(delta: float) -> void:
	# Regrow: bare plants come back once their harvest timer runs out.
	_regrow_check -= delta
	if _regrow_check <= 0.0 and not _bare.is_empty():
		_regrow_check = 3.0
		for index: int in _bare.keys():
			if not Game.is_harvested(resources[index].id):
				set_bare(index, false)
	for index: int in _wobbles.keys():
		var t: float = _wobbles[index] - delta
		var r := resources[index]
		var xf: Transform3D = r.transform
		xf.origin -= position
		if t <= 0.0:
			_wobbles.erase(index)
			if _bare.has(index):
				_bare[index].transform = xf
			else:
				_set_instance(index, xf)
			continue
		_wobbles[index] = t
		# Damped sway, stronger for tall things.
		var k := t / WOBBLE_TIME
		# A small shiver, not a sway: the trunk barely moves, a tree's top a hand's width at most.
		var amount := sin((1.0 - k) * 30.0) * k * k * (0.018 if FloraLibrary.category_of(r.kind) == "tree" else 0.012)
		var axis := Vector3(cos(index * 1.7), 0, sin(index * 1.7)).normalized()
		var wob := Transform3D(Basis(axis, amount) * xf.basis, xf.origin)
		if _bare.has(index):
			_bare[index].transform = wob
		else:
			_set_instance(index, wob)
	if _wobbles.is_empty() and _bare.is_empty():
		set_process(false)


func _set_instance(index: int, xf: Transform3D) -> void:
	if _own.has(index):
		var mi: MeshInstance3D = _own[index]
		mi.visible = xf.basis.get_scale().length_squared() > 1e-8
		if mi.visible:
			mi.transform = xf
		return
	var r := resources[index]
	if not r.has("mm_index") or not _mmis.has(r.mm_key):
		return
	_mmis[r.mm_key].multimesh.set_instance_transform(r.mm_index, xf)
	if _shadow_mmis.has(r.mm_key):
		_shadow_mmis[r.mm_key].multimesh.set_instance_transform(r.mm_index, xf)


## Point every MultiMesh at freshly generated meshes (after the model detail setting changes).
func swap_meshes(flora: FloraLibrary) -> void:
	for key: String in _mmis:
		if flora.has_mesh(key):
			_mmis[key].multimesh.mesh = flora.mesh(key)
	for key: String in _shadow_mmis:
		_shadow_mmis[key].multimesh.mesh = flora.mesh(key + "_lod")
