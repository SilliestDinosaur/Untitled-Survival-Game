extends Node3D
## Shows the items lying in the world (Game.pickups) as small bobbing bundles you can pick up.
## Pure view of shared data: when the data changes (here or, later, from the host), it re-syncs.

## How long a dropped item lies (its longest side, in metres), by tool type; other kinds below.
const TOOL_LENGTH := {"hatchet": 0.5, "pickaxe": 0.5, "hammer": 0.5, "spear": 0.7, "knife": 0.3, "torch": 0.4, "rock": 0.15, "plan": 0.35}
const PLACEABLE_LENGTH := 0.3
const ITEM_LENGTH := 0.2
const REST_HEIGHT := 0.02   ## the bottom of a dropped item sits this far above the ground

var _nodes := {}   # pickup id -> Node3D
var _bundle: ArrayMesh
var _materials := {}


func _ready() -> void:
	Game.pickups_changed.connect(_sync)
	Game.world_changed.connect(_sync)
	var k := MeshKit.new(3)
	k.add_primitive(MeshKit.sphere(0.16, 10, 6), Transform3D(Basis.from_scale(Vector3(1.1, 0.75, 1.0)), Vector3(0, 0.1, 0)), Color(1, 1, 1), 0.05, 0.08)
	k.add_primitive(MeshKit.sphere(0.07, 8, 5), Transform3D(Basis.from_scale(Vector3(1.2, 0.7, 1.2)), Vector3(0, 0.22, 0)), Color(0.85, 0.85, 0.85), 0.0, 0.05)
	k.add_primitive(MeshKit.cylinder(0.05, 0.05, 0.02, 8), Transform3D(Basis(), Vector3(0, 0.185, 0)), Color(0.6, 0.5, 0.35), 0.0, 0.0)
	_bundle = k.commit(null)
	_sync()


func _sync() -> void:
	for id: String in _nodes.keys():
		if not Game.pickups.has(id):
			_nodes[id].queue_free()
			_nodes.erase(id)
	for id: String in Game.pickups:
		if not _nodes.has(id):
			_nodes[id] = _make(Game.pickups[id])


func _make(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var pos: Array = p.pos
	root.position = Vector3(pos[0], pos[1], pos[2])
	var mi := MeshInstance3D.new()
	# The real item model, sized by its own bounds so every dropped item is the same size for its kind, and
	# lying on the ground (a tool's length runs along it).
	var mesh: ArrayMesh = ItemModels.mesh_for(p.item, _item_material())
	var box := mesh.get_aabb()
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var info: Dictionary = ItemDB.info(p.item)
	var is_tool: bool = info.get("kind", "") == "tool"
	var length := ITEM_LENGTH
	if is_tool:
		length = TOOL_LENGTH.get(String(info.get("tool", {}).get("type", "")), 0.4)
	elif info.get("kind", "") == "placeable":
		length = PLACEABLE_LENGTH
	var s := length / maxf(longest, 0.001)
	var lie := Vector3(0, 0, PI * 0.5) if is_tool and box.size.y >= longest - 0.001 else Vector3.ZERO
	var orient := Basis.from_euler(lie) * Basis.from_scale(Vector3.ONE * s)
	mi.mesh = mesh
	mi.transform = Transform3D(orient, Vector3.ZERO)
	var bounds: AABB = mi.transform * box
	root.set_meta("lift", REST_HEIGHT - bounds.position.y)
	mi.position.y = float(root.get_meta("lift"))
	root.add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = TerrainChunk.LAYER_INTERACT
	body.collision_mask = 0
	body.set_meta("pickup", p.id)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.35
	cs.shape = shape
	cs.position.y = 0.15
	body.add_child(cs)
	root.add_child(body)
	root.set_meta("phase", randf() * TAU)
	add_child(root)
	return root


var _item_mat: Material

func _item_material() -> Material:
	if not _item_mat:
		_item_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.45, "stroke_scale": 3.0})
	return _item_mat


func _tinted(col: Color) -> Material:
	var key := col.to_html()
	if not _materials.has(key):
		var m := ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.45})
		m.set_shader_parameter("tint_color", col)
		_materials[key] = m
	return _materials[key]


func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	for id: String in _nodes:
		var n: Node3D = _nodes[id]
		var mi := n.get_child(0) as Node3D
		mi.position.y = float(n.get_meta("lift")) + sin(t * 2.0 + float(n.get_meta("phase"))) * 0.02
		mi.rotate_y(delta * 0.6)
