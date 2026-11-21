extends Node3D
## Streams terrain chunks around a focus point (the player, or the menu camera).
## Chunk data is generated on worker threads; this node only turns finished data into nodes.

signal world_reset

const TIER_DISTANCE := [1, 3]   ## chunks within 1 -> tier 0 (full detail), within 3 -> tier 1, else tier 2
const MAX_JOBS := 4             ## worker threads busy at once
const APPLY_PER_FRAME := 2      ## finished chunks turned into nodes per frame (at most)
const APPLY_BUDGET_US := 6000   ## and no more once this much of the frame has gone on them

var focus: Node3D
var view_radius := 6

var _chunks := {}     # Vector2i -> TerrainChunk
var _jobs := {}       # Vector2i -> {task, job}
var _floors_seen := {}   # Rect2 -> true: the ground floors last seen (see _on_structures_changed)
var _dirty := {}      # chunk coords whose ground changed and must be rebuilt
var _water: MeshInstance3D
var _rivers: Node3D


func _ready() -> void:
	Game.terrain_changed.connect(_on_terrain_changed)
	Game.structures_changed.connect(_on_structures_changed)
	view_radius = Settings.view_radius()
	_build_water()
	Game.assets_rebuilt.connect(func() -> void:
		for c: Vector2i in _chunks:
			_chunks[c].swap_meshes(Game.flora))
	Settings.changed.connect(func() -> void: view_radius = Settings.view_radius())


func _exit_tree() -> void:
	_wait_for_jobs()


var _stream_center := Vector2i(1 << 30, 1 << 30)   ## the chunk the streaming last looked at
var _stream_timer := 0.0


func _process(delta: float) -> void:
	_collect_jobs()
	if focus:
		# Streaming only needs a look when the player enters another chunk, or now and then (for finished
		# jobs and ground changes); looking every frame rebuilt the same lists over and over.
		_stream_timer -= delta
		var center := world_to_chunk(focus.global_position)
		if center != _stream_center or _stream_timer <= 0.0:
			_stream_center = center
			_stream_timer = 0.25
			_update_chunks(focus.global_position)


## Throw away everything and start over with the current Game world (after a new seed).
func reset() -> void:
	_wait_for_jobs()
	for c: Vector2i in _chunks:
		_chunks[c].queue_free()
	_chunks.clear()
	_build_water()
	world_reset.emit()


## True when every chunk within `radius` of pos is loaded at full detail.
func is_area_ready(pos: Vector3, radius: int) -> bool:
	var center := world_to_chunk(pos)
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var c := center + Vector2i(x, z)
			if not _chunks.has(c) or _chunks[c].tier != 0:
				return false
	return true


## 0..1 progress for the loading screen.
func area_progress(pos: Vector3, radius: int) -> float:
	var center := world_to_chunk(pos)
	var total := 0
	var loaded := 0
	for z in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			total += 1
			var c := center + Vector2i(x, z)
			if _chunks.has(c) and _chunks[c].tier == 0:
				loaded += 1
	return float(loaded) / total


func world_to_chunk(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / Game.CHUNK_SIZE), floori(pos.z / Game.CHUNK_SIZE))


func get_chunk(c: Vector2i) -> TerrainChunk:
	return _chunks.get(c)


func get_chunk_count() -> int:
	return _chunks.size()


# --- Streaming -------------------------------------------------------------------

func _tier_for(dist: int) -> int:
	if dist <= TIER_DISTANCE[0]:
		return 0
	if dist <= TIER_DISTANCE[1]:
		return 1
	return 2


func _update_chunks(pos: Vector3) -> void:
	var center := world_to_chunk(pos)

	# Unload chunks that are well out of range (+1 so we don't thrash at the border).
	for c: Vector2i in _chunks.keys():
		if _cheb(c, center) > view_radius + 1:
			_chunks[c].queue_free()
			_chunks.erase(c)

	if _jobs.size() >= MAX_JOBS:
		return

	# Find what needs (re)building, closest first.
	var wanted: Array = []
	for z in range(-view_radius, view_radius + 1):
		for x in range(-view_radius, view_radius + 1):
			var c := center + Vector2i(x, z)
			if _jobs.has(c):
				continue
			var d := _cheb(c, center)
			var want := _tier_for(d)
			if _dirty.has(c) and _chunks.has(c):
				wanted.append([d * 2, c, _chunks[c].tier])   # ground changed: rebuild now
			elif not _chunks.has(c):
				wanted.append([d * 2, c, want])        # missing: highest priority
			else:
				var have: int = _chunks[c].tier
				# Upgrade right away; downgrade only once clearly out of range (avoids flicker).
				if want < have or (want > have and d > TIER_DISTANCE[min(have, 1)] + 1):
					wanted.append([d * 2 + 1, c, want])
	if wanted.is_empty():
		return
	wanted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for k in mini(MAX_JOBS - _jobs.size(), wanted.size()):
		_start_job(wanted[k][1], wanted[k][2])


func _start_job(c: Vector2i, tier: int) -> void:
	var job := {
		"coord": c,
		"tier": tier,
		"gen": Game.world_gen,
		"flora": Game.flora,
		"removed": _removed_snapshot(),
		"grass_density": Settings.grass_density(),
		"covered": _covered_in(c),
	}
	var task := WorkerThreadPool.add_task(ChunkGenerator.generate.bind(job), false, "chunk")
	_jobs[c] = {"task": task, "job": job}


## Ids that are currently gathered (not yet regrown). Copied so worker threads can read it safely.
func _removed_snapshot() -> Dictionary:
	var out := {}
	for id: String in Game.removed_resources:
		if Game.is_removed(id):
			out[id] = true
	for id: String in Game.looted:   # caches never come back
		out[id] = true
	return out


func _collect_jobs() -> void:
	var applied := 0
	var start := Time.get_ticks_usec()
	for c: Vector2i in _jobs.keys():
		# A couple a frame, but stop early once the frame's share is used.
		if applied >= APPLY_PER_FRAME or (applied > 0 and Time.get_ticks_usec() - start > APPLY_BUDGET_US):
			break
		var entry: Dictionary = _jobs[c]
		if not WorkerThreadPool.is_task_completed(entry.task):
			continue
		WorkerThreadPool.wait_for_task_completion(entry.task)
		_jobs.erase(c)
		var job: Dictionary = entry.job
		if not job.has("result") or job.get("stale", false) or job.gen != Game.world_gen:
			continue
		if focus and _cheb(c, world_to_chunk(focus.global_position)) > view_radius + 1:
			continue
		var chunk := TerrainChunk.new()
		chunk.apply(c, job.tier, job.result, Game.flora)
		_dirty.erase(c)
		if _chunks.has(c):
			_chunks[c].queue_free()   # swap in the new detail level only once it's ready
		_chunks[c] = chunk
		add_child(chunk)
		applied += 1


## The footprints (world xz) of floors at ground level over chunk c: nothing grows under them.
func _covered_in(c: Vector2i) -> Array:
	var out: Array = []
	var size := float(Game.CHUNK_SIZE)
	var area := Rect2(c.x * size - 3.0, c.y * size - 3.0, size + 6.0, size + 6.0)
	for r: Rect2 in _floor_rects():
		if area.intersects(r):
			out.append(r)
	return out


func _floor_rects() -> Array:
	var out: Array = []
	var h := GameActions.CELL * 0.5 + 0.1
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind in GameActions.FLOOR_KINDS and int(st.get("level", 0)) == 0:
			var p: Array = st.pos
			out.append(Rect2(float(p[0]) - h, float(p[2]) - h, h * 2.0, h * 2.0))
	return out


## A ground floor was laid or taken up: the chunks under it are built again (grass under it goes, or comes back).
func _on_structures_changed() -> void:
	var now := {}
	for r: Rect2 in _floor_rects():
		now[r] = true
	var touched := {}
	for r: Rect2 in now:
		if not _floors_seen.has(r):
			touched[r] = true
	for r: Rect2 in _floors_seen:
		if not now.has(r):
			touched[r] = true
	_floors_seen = now
	var size := float(Game.CHUNK_SIZE)
	for r: Rect2 in touched:
		for cz in range(floori(r.position.y / size), floori(r.end.y / size) + 1):
			for cx in range(floori(r.position.x / size), floori(r.end.x / size) + 1):
				var c := Vector2i(cx, cz)
				_dirty[c] = true
				if _jobs.has(c):
					_jobs[c].job.stale = true


## Shovel work changed these cells: mark the chunks around them for rebuilding. Chunks being
## built right now are invalidated so their old result is thrown away.
func _on_terrain_changed(cells: Array) -> void:
	var touched := {}
	for cell: Array in cells:
		var i := int(cell[0])
		var j := int(cell[1])
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var c := Vector2i(floori((i + dx) / float(Game.CHUNK_SIZE)), floori((j + dz) / float(Game.CHUNK_SIZE)))
				touched[c] = true
	for c: Vector2i in touched:
		_dirty[c] = true
		if _jobs.has(c):
			_jobs[c].job.stale = true   # _collect_jobs drops it (the worker keeps its own copy of the data)


func _wait_for_jobs() -> void:
	for c: Vector2i in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[c].task)
	_jobs.clear()


static func _cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


# --- Ocean ------------------------------------------------------------------

func _build_water() -> void:
	if not _water:
		_water = MeshInstance3D.new()
		_water.name = "Water"
		_water.add_to_group("water")
		var plane := PlaneMesh.new()
		plane.size = Vector2(Game.WORLD_SIZE * 5.0, Game.WORLD_SIZE * 5.0)
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/water.gdshader")
		mat.set_shader_parameter("ripple_a", _ripple_texture(1))
		mat.set_shader_parameter("ripple_b", _ripple_texture(2))
		plane.material = mat
		_water.mesh = plane
		_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_water.position = Vector3(Game.WORLD_SIZE * 0.5, Game.SEA_LEVEL, Game.WORLD_SIZE * 0.5)
		add_child(_water)
	var pal: WorldPalette = Game.palette
	var m := (_water.mesh as PlaneMesh).material as ShaderMaterial
	m.set_shader_parameter("shallow_color", pal.water_shallow)
	m.set_shader_parameter("deep_color", pal.water_deep)
	# The rivers' and ponds' water: the same paint, flowing.
	if not _rivers:
		_rivers = Node3D.new()
		_rivers.name = "Rivers"
		add_child(_rivers)
	if Game.world_gen:
		Rivers.build_meshes(Game.world_gen.rivers, _rivers, m)


func _ripple_texture(seed_offset: int) -> NoiseTexture2D:
	var noise := FastNoiseLite.new()
	noise.seed = seed_offset
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.as_normal_map = true
	tex.bump_strength = 6.0
	tex.noise = noise
	return tex


# --- Shared world changes ---------------------------------------------------------------

## A loaded resource by id: [chunk, index], or [] if that part of the world isn't loaded here.
func find_resource(id: String) -> Array:
	var parts := id.split("_")
	if parts.size() < 3:
		return []
	var chunk := get_chunk(Vector2i(int(parts[0]), int(parts[1])))
	if not chunk:
		return []
	var i := chunk.index_of(id)
	return [] if i < 0 else [chunk, i]


## Apply a change to a tree / rock / plant on this machine: the shared record (so chunks
## built later agree) and, if it's loaded, how it looks. Every machine runs this for every
## change, whoever caused it. st: {hp, removed, bare, t (host play time), by (peer), fx, pos, from}
func apply_resource_change(id: String, st: Dictionary) -> void:
	var t := float(st.get("t", Game.play_time))
	if st.get("removed", false):
		Game.removed_resources[id] = t
		Game.resource_hp.erase(id)
	elif st.has("hp"):
		Game.resource_hp[id] = float(st.hp)
	if st.get("bare", false):
		Game.harvested[id] = t
	var found := find_resource(id)
	var mine: bool = int(st.get("by", -1)) == Net.my_id()
	# Other players' hits: hear and see them.
	if not mine and st.has("pos"):
		var p: Vector3 = st.pos
		match String(st.get("fx", "")):
			"tree": Audio.play_3d("chop", p)
			"rock":
				var ore := not found.is_empty() and String((found[0] as TerrainChunk).resources[int(found[1])].kind).begins_with("ore")
				Audio.play_3d("ore" if ore else "clink", p, -2.0)
			"bush": Audio.play_3d("rustle", p)
	if found.is_empty():
		return
	var chunk: TerrainChunk = found[0]
	var i: int = found[1]
	var r := chunk.resources[i]
	if st.get("removed", false):
		r.removed = true
		if not r.get("gone", false):
			_remove_visual(chunk, r, st.get("from", r.transform.origin + Vector3.FORWARD))
	elif st.get("bare", false):
		chunk.set_bare(i, true)
		chunk.wobble(i)
	elif st.has("hp"):
		r.hp = float(st.hp)
		chunk.wobble(i)


func _remove_visual(chunk: TerrainChunk, r: Dictionary, from: Vector3) -> void:
	var mesh := chunk.get_resource_mesh(r.index)
	var xf: Transform3D = r.transform
	chunk.remove_resource(r.index)
	if mesh:
		if FloraLibrary.category_of(r.kind) == "tree":
			Effects.fall_tree(get_parent(), mesh, xf, xf.origin - from, Effects.bark_color(r.kind), Effects.leaf_color(r.kind))
		elif FloraLibrary.category_of(r.kind) == "rock":
			var col := Game.palette.rock
			if r.kind.begins_with("ore") or r.kind.begins_with("gem"):
				col = ItemDB.tier_info(int(r.kind.right(1))).color
			Effects.crumble(get_parent(), mesh, xf, col, true)
		else:
			Effects.crumble(get_parent(), mesh, xf, Effects.leaf_color(r.kind), false)
