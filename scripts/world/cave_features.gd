class_name CaveFeatures
extends Node3D
## The things inside caves that aren't ground: supply chests and glowing fungus, placed where
## the cave plan put them. The rock itself comes from VoxelTerrain, so these simply stand in the
## real caves. Built once per world.

var _lights: Array = []
var _time := 0.0


func build(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "features"])
	_build_chests(plan.chests)
	_build_glowcaps(plan.glow, rng)


func _build_chests(chests: Array) -> void:
	var wood := Color(0.36, 0.25, 0.17)
	for k in chests.size():
		var c: Vector3 = chests[k]
		var body := StaticBody3D.new()
		body.collision_layer = TerrainChunk.LAYER_INTERACT | TerrainChunk.LAYER_SOLID
		body.collision_mask = 0
		body.position = c
		body.set_meta("cave_chest", k)
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.1, 0.7, 0.7)
		cs.shape = box
		cs.position.y = 0.35
		body.add_child(cs)
		var kit := MeshKit.new(11 + k)
		kit.add_primitive(_cube(Vector3(1.1, 0.5, 0.7)), Transform3D(Basis(), Vector3(0, 0.25, 0)), wood, 0.0, 0.04)
		kit.add_primitive(_cube(Vector3(1.14, 0.2, 0.74)), Transform3D(Basis(), Vector3(0, 0.6, 0)), wood.lightened(0.08), 0.0, 0.04)
		kit.add_primitive(_cube(Vector3(0.12, 0.2, 0.06)), Transform3D(Basis(), Vector3(0, 0.45, 0.37)), Color(0.8, 0.66, 0.3), 0.0, 0.0)
		var mi := MeshInstance3D.new()
		mi.mesh = kit.commit(ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.3}))
		body.add_child(mi)
		add_child(body)


func _build_glowcaps(glow: Array, rng: RandomNumberGenerator) -> void:
	var kinds := ["glowcap_0", "glowcap_1", "glowcap_2"]
	var k := 0
	for g: Vector3 in glow:
		var key: String = kinds[rng.randi() % kinds.size()]
		if not Game.flora.has_mesh(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Game.flora.mesh(key)
		mi.position = g
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		add_child(mi)
		if k % 10 == 0 and _lights.size() < 12:   # a few of them light the place up
			var light := OmniLight3D.new()
			light.light_color = Game.palette.glow
			light.light_energy = 0.9
			light.omni_range = 7.0
			light.omni_attenuation = 1.5
			light.position = g + Vector3(0, 0.5, 0)
			add_child(light)
			_lights.append(light)
		k += 1


func _cube(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _process(delta: float) -> void:
	_time += delta
	for light: OmniLight3D in _lights:
		light.light_energy = 0.8 + sin(_time * 1.3 + light.position.x) * 0.12
