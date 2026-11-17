class_name CaveScene
extends Node3D
## The underground network (see Caves.network), built as one scene: the rock is a set of tunnels
## and chambers you stand inside, with inward-facing faces and matching collision. Every entrance
## has a way out next to where it lands.

var net: Dictionary
var _bats: Array = []     ## [{node, center, phase, radius, speed}]
var _glow_lights: Array = []
var _time := 0.0


func build(network: Dictionary, entrance_roots: Array) -> void:
	net = network
	var nodes: Array = network.nodes
	var rock: Color = Game.palette.rock.darkened(0.35)
	var kit := MeshKit.new(hash([Game.world_seed, "cave"]))
	for e: Array in network.edges:
		var a: Dictionary = nodes[e[0]]
		var b: Dictionary = nodes[e[1]]
		var mid: Vector3 = (a.p + b.p) * 0.5
		var jitter := Vector3(sin(a.p.x * 0.13 + b.p.z * 0.07), 0.0, cos(a.p.z * 0.11 + b.p.x * 0.05)) * minf(a.p.distance_to(b.p) * 0.12, 1.2)
		var path := [a.p, mid + jitter, b.p]
		var radii := [float(a.r), lerpf(float(a.r), float(b.r), 0.5) * 0.92, float(b.r)]
		kit.loft(path, radii, 9, rock, func(t: float, ang: float) -> Color: return rock.lightened(sin(ang * 5.0 + t * 9.0) * 0.04), Callable(), true, true, 0.3)
	for r: int in network.rooms:
		var n: Dictionary = nodes[r]
		kit.add_primitive(MeshKit.sphere(float(n.r) * 0.95, 14, 9), Transform3D(Basis(), n.p), rock, 0.35, 0.05)
	var inward := _inward_arrays(kit)
	var mi := MeshInstance3D.new()
	mi.name = "Rock"
	mi.mesh = inward.mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "RockBody"
	body.collision_layer = TerrainChunk.LAYER_SOLID
	body.collision_mask = 0
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(inward.faces)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	_build_glowcaps(network)
	_build_bats(network)
	_build_chests(network)
	_build_exits(nodes, entrance_roots)


## The rock's surface turned inside out: the same triangles reversed, normals pointing in.
func _inward_arrays(kit: MeshKit) -> Dictionary:
	var v := kit.verts
	var n := kit.normals
	var c := kit.colors
	var V := PackedVector3Array()
	var N := PackedVector3Array()
	var C := PackedColorArray()
	for i in range(0, v.size() - 2, 3):
		V.append(v[i]); V.append(v[i + 2]); V.append(v[i + 1])
		N.append(-n[i]); N.append(-n[i + 2]); N.append(-n[i + 1])
		C.append(c[i]); C.append(c[i + 2]); C.append(c[i + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = V
	arrays[Mesh.ARRAY_NORMAL] = N
	arrays[Mesh.ARRAY_COLOR] = C
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ArtStyle.painted({"brush_strength": 0.3, "rim_amount": 0.2}))
	return {"mesh": mesh, "faces": V}


func _build_glowcaps(network: Dictionary) -> void:
	var kinds := ["glowcap_0", "glowcap_1", "glowcap_2"]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "glow"])
	var k := 0
	for g: Vector3 in network.glow:
		var key: String = kinds[rng.randi() % kinds.size()]
		if not Game.flora.meshes.has(key):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = Game.flora.meshes[key]
		mi.position = g
		mi.rotation.y = rng.randf() * TAU
		mi.scale = Vector3.ONE * rng.randf_range(0.8, 1.3)
		add_child(mi)
		if k % 6 == 0:   # some of them light the place up
			var light := OmniLight3D.new()
			light.light_color = Game.palette.glow
			light.light_energy = 0.9
			light.omni_range = 8.0
			light.omni_attenuation = 1.5
			light.position = g + Vector3(0, 0.5, 0)
			add_child(light)
			_glow_lights.append(light)
		k += 1


func _build_bats(network: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([Game.world_seed, "bats"])
	var kit := MeshKit.new(7)
	var fur := Color(0.16, 0.13, 0.15)
	kit.add_primitive(MeshKit.sphere(0.1, 8, 5), Transform3D(Basis.from_scale(Vector3(1, 0.9, 1.4)), Vector3.ZERO), fur, 0.0, 0.05)
	kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(0.24, 0.12), Vector2(0.3, -0.02), Vector2(0.18, -0.08), Vector2(0.06, -0.04)]),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0.02, 0, 0)), 0.01, 0.005, fur.lightened(0.05), fur.lightened(0.2), 0.5)
	kit.extrude(PackedVector2Array([Vector2(0, 0), Vector2(-0.24, 0.12), Vector2(-0.3, -0.02), Vector2(-0.18, -0.08), Vector2(-0.06, -0.04)]),
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-0.02, 0, 0)), 0.01, 0.005, fur.lightened(0.05), fur.lightened(0.2), 0.5)
	var mesh: ArrayMesh = kit.commit(ArtStyle.painted({"brush_strength": 0.1, "rim_amount": 0.4}))
	for b: Vector3 in network.bats:
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = b
		add_child(node)
		_bats.append({"node": node, "center": b, "phase": rng.randf() * TAU, "radius": rng.randf_range(1.5, 3.0), "speed": rng.randf_range(0.7, 1.4)})


func _build_chests(network: Dictionary) -> void:
	var wood := Color(0.36, 0.25, 0.17)
	var k := 0
	for c: Vector3 in network.chests:
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
		k += 1


func _cube(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


## One way out per entrance, where it lands.
func _build_exits(nodes: Array, entrance_roots: Array) -> void:
	for e in entrance_roots.size():
		var at: Vector3 = nodes[entrance_roots[e]].p + Vector3(0, 0.3, 0)
		var body := StaticBody3D.new()
		body.collision_layer = TerrainChunk.LAYER_INTERACT
		body.collision_mask = 0
		body.position = at
		body.set_meta("cave_exit", e)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 1.0
		cs.shape = sh
		body.add_child(cs)
		add_child(body)


## Where the player arrives from entrance `e`, in world space.
func spawn_for(e: int) -> Vector3:
	return net.nodes[net.roots[e]].p + Vector3(0, 0.6, 0)


func _process(delta: float) -> void:
	_time += delta
	for b: Dictionary in _bats:
		var t := _time * float(b.speed) + float(b.phase)
		var c: Vector3 = b.center
		var node: Node3D = b.node
		node.position = c + Vector3(cos(t) * float(b.radius), sin(t * 1.7) * 0.35 + 0.2, sin(t) * float(b.radius))
		node.rotation.y = -t + PI * 0.5
	for light: OmniLight3D in _glow_lights:
		light.light_energy = 0.8 + sin(_time * 1.3 + light.position.x) * 0.12
