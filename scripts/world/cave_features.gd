class_name CaveFeatures
extends Node3D
## The things inside caves that aren't ground: supply chests, glowing fungus and bats, placed where
## the cave plan put them. The rock itself comes from VoxelTerrain, so these simply stand in the
## real caves. Built once per world.

var _bats: Array = []     ## [{node, center, phase, radius, speed}]
var _lights: Array = []
var _time := 0.0


func build(plan: Dictionary) -> void:
	if plan.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "features"])
	_build_chests(plan.chests)
	_build_glowcaps(plan.glow, rng)
	_build_bats(plan.bats, rng)


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
		if not Game.flora.meshes.has(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Game.flora.meshes[key]
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


func _build_bats(bats: Array, rng: RandomNumberGenerator) -> void:
	var kit := MeshKit.new(7)
	var fur := Color(0.16, 0.13, 0.15)
	kit.add_primitive(MeshKit.sphere(0.1, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 0.9, 1.4)), Vector3.ZERO), fur, 0.0, 0.05)
	kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0.24, 0.12), Vector2(0.3, -0.02), Vector2(0.18, -0.08), Vector2(0.06, -0.04)]),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.02, 0, 0)), 0.01, 0.005, fur.lightened(0.05), fur.lightened(0.2), 0.5)
	kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(-0.24, 0.12), Vector2(-0.3, -0.02), Vector2(-0.18, -0.08), Vector2(-0.06, -0.04)]),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.02, 0, 0)), 0.01, 0.005, fur.lightened(0.05), fur.lightened(0.2), 0.5)
	var mesh: ArrayMesh = kit.commit(ArtStyle.painted({"brush_strength": 0.1, "rim_amount": 0.4}))
	for b: Vector3 in bats:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = b
		add_child(node)
		_bats.append({"node": node, "center": b, "phase": rng.randf() * TAU, "radius": rng.randf_range(1.5, 3.0), "speed": rng.randf_range(0.7, 1.4)})


func _cube(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _process(delta: float) -> void:
	_time += delta
	for b: Dictionary in _bats:
		var t := _time * float(b.speed) + float(b.phase)
		var c: Vector3 = b.center
		var node: Node3D = b.node
		node.position = c + Vector3(cos(t) * float(b.radius), sin(t * 1.7) * 0.35 + 0.2, sin(t) * float(b.radius))
		node.rotation.y = -t + PI * 0.5
	for light: OmniLight3D in _lights:
		light.light_energy = 0.8 + sin(_time * 1.3 + light.position.x) * 0.12
