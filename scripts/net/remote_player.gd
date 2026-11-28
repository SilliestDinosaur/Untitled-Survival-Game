class_name RemotePlayer
extends Node3D
## Another player, seen in third person: a simple, friendly figure (see Avatar: a rounded torso in their shirt
## colour, a head with a painted face, their hair and hat) with whatever they're holding floating at their side,
## and their name above. Moves smoothly between the poses the network sends.
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


func setup(pname: String, look: Dictionary) -> void:
	display_name = pname
	if not _mat:
		_mat = ArtStyle.painted({"brush_strength": 0.18, "rim_amount": 0.35})
		_item_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.4, "stroke_scale": 3.0})
	var l := Avatar.clean(look)
	_body = Node3D.new()
	add_child(_body)
	add_child(CaveShade.new())   # darker in a cave, like everything else there
	var torso := MeshInstance3D.new()
	torso.mesh = Avatar.torso_mesh(Settings.PLAYER_COLORS[l.shirt], _mat)
	_body.add_child(torso)

	_head = Node3D.new()
	_head.position = Vector3(0, 1.6, 0)
	_body.add_child(_head)
	var head := MeshInstance3D.new()
	head.mesh = Avatar.head_mesh(l, _mat)
	_head.add_child(head)

	_item = MeshInstance3D.new()
	_item.position = Vector3(0.5, 0.95, -0.25)
	_item.scale = Vector3.ONE * 1.9
	_body.add_child(_item)

	_label = Label3D.new()
	_label.text = pname
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.05 + (0.15 if Avatar.HATS[l.hat] in ["Straw hat", "Feather"] else 0.0), 0)
	_label.font_size = 40
	_label.pixel_size = 0.006
	_label.outline_size = 10
	_label.modulate = Color(1, 0.97, 0.9)
	_label.outline_modulate = Color(0.1, 0.07, 0.05, 0.85)
	_label.no_depth_test = false
	_label.fixed_size = false
	add_child(_label)
	visible = false


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
