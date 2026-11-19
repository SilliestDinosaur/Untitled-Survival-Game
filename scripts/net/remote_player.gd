class_name RemotePlayer
extends Node3D
## Another player, seen in third person: a simple, friendly figure (a rounded torso in their
## colour, a head with a painted face, no arms or legs) with whatever they're holding floating
## at their side, and their name above. Moves smoothly between the poses the network sends.
## On the host it's also what animals notice and bite.

var peer_id := 0
var display_name := ""
var has_pose := false
var is_sprinting := false

var _body: Node3D
var _head: Node3D
var _item: MeshInstance3D
var _label: Label3D
var _held := ""
var _torch: TorchGlow
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _target_pitch := 0.0
var _swings := 0
var _bob := 0.0
var _last_pos := Vector3.ZERO
var _tween: Tween

static var _mat: ShaderMaterial
static var _item_mat: ShaderMaterial


func setup(pname: String, color: Color) -> void:
	display_name = pname
	if not _mat:
		_mat = ArtStyle.painted({"brush_strength": 0.18, "rim_amount": 0.35})
		_item_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.4, "stroke_scale": 3.0})
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(pname)
	var skin: Color = [Color(0.96, 0.8, 0.66), Color(0.86, 0.66, 0.5), Color(0.68, 0.48, 0.34), Color(0.5, 0.35, 0.25), Color(0.98, 0.86, 0.74)][rng.randi() % 5]

	_body = Node3D.new()
	add_child(_body)
	add_child(CaveShade.new())   # darker in a cave, like everything else there
	var torso := MeshInstance3D.new()
	torso.mesh = _torso_mesh(color)
	_body.add_child(torso)

	_head = Node3D.new()
	_head.position = Vector3(0, 1.6, 0)
	_body.add_child(_head)
	var head := MeshInstance3D.new()
	head.mesh = _head_mesh(skin, color, rng)
	_head.add_child(head)

	_item = MeshInstance3D.new()
	_item.position = Vector3(0.5, 0.95, -0.25)
	_item.scale = Vector3.ONE * 1.9
	_body.add_child(_item)

	_label = Label3D.new()
	_label.text = pname
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.05, 0)
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color(1, 0.97, 0.9)
	_label.outline_modulate = Color(0.1, 0.07, 0.05, 0.85)
	_label.no_depth_test = false
	_label.fixed_size = false
	add_child(_label)
	visible = false


## A rounded torso: wide shoulders tapering to the waist, with a collar and a belt line.
func _torso_mesh(color: Color) -> ArrayMesh:
	var k := MeshKit.new(7)
	var path := []
	var radii := []
	var profile := [0.17, 0.25, 0.28, 0.29, 0.3, 0.31, 0.3, 0.26, 0.16]
	for i in profile.size():
		var t := float(i) / (profile.size() - 1)
		path.append(Vector3(0, 0.55 + t * 0.8, 0))
		radii.append(profile[i])
	var dark := color.darkened(0.25)
	var light := color.lightened(0.12)
	var shirt := func(t: float, a: float) -> Color:
		if t < 0.13:
			return dark            # belt / hem
		if t > 0.88:
			return light           # collar
		return color.lightened(0.05) if a > PI * 0.6 and a < PI * 1.4 else color
	var oval := func(_t: float, _a: float) -> Vector2: return Vector2(1.0, 0.72)
	k.loft(path, radii, 20, color, shirt, oval, true, true)
	return k.commit(_mat)


## A rounded head with simple painted eyes and a smile, plus a little hair tuft.
func _head_mesh(skin: Color, accent: Color, rng: RandomNumberGenerator) -> ArrayMesh:
	var k := MeshKit.new(9)
	k.add_primitive(MeshKit.sphere(0.26, 22, 16), Transform3D(Basis.from_scale(Vector3(1.0, 1.06, 0.98)), Vector3.ZERO), skin, 0.0, 0.03)
	var eye := Color(0.12, 0.09, 0.08)
	for side in [-1.0, 1.0]:
		k.add_primitive(MeshKit.sphere(0.042, 10, 7), Transform3D(Basis.from_scale(Vector3(0.8, 1.25, 0.5)), Vector3(side * 0.09, 0.04, -0.243)), eye, 0.0, 0.0)
		k.add_primitive(MeshKit.sphere(0.013, 6, 4), Transform3D(Basis(), Vector3(side * 0.09 + 0.012, 0.065, -0.262)), Color(1, 1, 1), 0.0, 0.0)
	# Smile: a short lofted arc.
	var smile := []
	var sr := []
	for i in 7:
		var t := (i / 6.0 - 0.5) * 1.4
		smile.append(Vector3(sin(t) * 0.085, -0.075 - cos(t) * 0.025 + 0.025, -0.247 + absf(t) * 0.015))
		sr.append(0.011)
	k.loft(smile, sr, 6, eye.lightened(0.15), Callable(), Callable(), true, true)
	# Hair: a cap of lumpy blobs in a colour that suits the player.
	var hair: Color = [Color(0.2, 0.14, 0.1), Color(0.45, 0.28, 0.15), Color(0.85, 0.7, 0.4), Color(0.6, 0.25, 0.12), accent.darkened(0.35)][rng.randi() % 5]
	k.add_primitive(MeshKit.sphere(0.265, 16, 10), Transform3D(Basis.from_scale(Vector3(1.03, 0.6, 1.0)), Vector3(0, 0.125, 0.025)), hair, 0.03, 0.05)
	return k.commit(_mat)


func set_pose(pos: Vector3, yaw: float, pitch: float, held: String, swings: int, sprinting: bool) -> void:
	_target_pos = pos
	_target_yaw = yaw
	_target_pitch = pitch
	is_sprinting = sprinting
	if not has_pose:
		has_pose = true
		visible = true
		global_position = pos
		rotation.y = yaw
		_last_pos = pos
	if held != _held:
		_held = held
		_item.mesh = ItemModels.mesh_for(held, _item_mat) if held != "" else null
		var info := ItemDB.info(held) if held != "" else {}
		_item.scale = Vector3.ONE * (0.18 if info.get("kind", "") == "placeable" else 1.35)
		_item.rotation = Vector3(-0.3, 0.0, 0.25) if info.get("kind", "") == "tool" else Vector3.ZERO
		_set_torch(info.get("tool", {}).get("type", "") == "torch")
	if swings != _swings:
		if swings > _swings:
			_swing()
		_swings = swings


## Their torch burns and lights the place up for everyone, just like your own.
func _set_torch(on: bool) -> void:
	if on and not _torch:
		_torch = TorchGlow.new()
		_item.add_child(_torch)
	if _torch:
		_torch.visible = on


func _swing() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_item, "rotation:x", 0.7, 0.12).set_trans(Tween.TRANS_SINE)
	_tween.tween_property(_item, "rotation:x", -1.2, 0.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(_item, "rotation:x", -0.3, 0.25).set_trans(Tween.TRANS_SINE)


## Host: an animal bit this player.
func hurt(amount: float, push: Vector3) -> void:
	Net.hurt_peer(peer_id, amount, push)


func _process(delta: float) -> void:
	if not has_pose:
		return
	# The pose is the camera's feet position; smooth toward it.
	var k := 1.0 - exp(-14.0 * delta)
	global_position = global_position.lerp(_target_pos, k)
	rotation.y = lerp_angle(rotation.y, _target_yaw, k)
	_head.rotation.x = lerp_angle(_head.rotation.x, clampf(_target_pitch, -0.8, 0.8), k)
	# Gentle hover bob, faster when moving; lean into movement.
	var moved := Vector2(global_position.x - _last_pos.x, global_position.z - _last_pos.z).length() / maxf(delta, 0.001)
	_last_pos = global_position
	var moving := clampf(moved / 5.0, 0.0, 1.5)
	_bob += delta * (2.0 + moving * 6.0)
	_body.position.y = sin(_bob) * (0.02 + moving * 0.03)
	_body.rotation.x = lerpf(_body.rotation.x, -moving * 0.12, 1.0 - exp(-6.0 * delta))
	_item.position.y = 0.92 + sin(_bob * 0.7 + 1.0) * 0.03
