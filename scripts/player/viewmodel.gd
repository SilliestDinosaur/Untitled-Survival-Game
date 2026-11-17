class_name Viewmodel
extends Node3D
## The player's arm and held item in first person, with swing / eat animations and sway.

signal strike   ## the moment a swing connects

const REST := Vector3(0.3, -0.3, -0.5)

var _arm: MeshInstance3D
var _item: MeshInstance3D
var _item_meshes := {}
var _tween: Tween
var _sway := Vector2.ZERO
var _busy := false
var _bob := 0.0
var _held := ""


func _ready() -> void:
	position = REST
	var mat := ArtStyle.painted({"brush_strength": 0.2, "rim_amount": 0.2})
	# Sleeve + hand.
	var kit := MeshKit.new(5)
	kit.add_primitive(MeshKit.cylinder(0.04, 0.05, 0.3, 10), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(75)), Vector3(0.02, -0.05, 0.17)), Color(0.55, 0.47, 0.38), 0.0, 0.04)
	kit.add_primitive(MeshKit.sphere(0.065, 10, 6), Transform3D(Basis().scaled(Vector3(1, 0.9, 1.2)), Vector3(0, -0.02, 0.0)), Color(0.86, 0.66, 0.52), 0.0, 0.03)
	_arm = MeshInstance3D.new()
	_arm.mesh = kit.commit(mat)
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arm)
	_item = MeshInstance3D.new()
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_item)
	_build_item_meshes(mat)
	# Held items use the world's palette (rock color, berry color...).
	Game.world_changed.connect(func() -> void:
		_build_item_meshes(mat)
		hold(_held))


func _build_item_meshes(mat: Material) -> void:
	var pal: WorldPalette = Game.palette
	var k := MeshKit.new(11)
	k.add_primitive(MeshKit.sphere(0.1, 10, 6), Transform3D(Basis().scaled(Vector3(1.15, 0.85, 1.0)), Vector3(0, 0.05, -0.04)), pal.rock, 0.05, 0.08)
	_item_meshes.rock = k.commit(mat)
	k = MeshKit.new(12)
	for i in 9:
		var a := i * 2.4
		k.add_primitive(MeshKit.sphere(0.028, 8, 5), Transform3D(Basis(), Vector3(cos(a) * 0.035 * (i % 3), 0.04 + (i / 3) * 0.022, sin(a) * 0.035 * (i % 3) - 0.03)), pal.berry, 0.0, 0.05)
	_item_meshes.berries = k.commit(mat)
	k = MeshKit.new(13)
	k.add_primitive(MeshKit.sphere(0.08, 10, 6), Transform3D(Basis().scaled(Vector3(1.3, 0.6, 1)), Vector3(0, 0.04, -0.04)), Color(0.78, 0.36, 0.38), 0.03, 0.06)
	k.add_primitive(MeshKit.cylinder(0.012, 0.012, 0.12, 6), Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0.1, 0.04, -0.04)), Color(0.92, 0.9, 0.84), 0.0, 0.0)
	_item_meshes.raw_meat = k.commit(mat)


## Show what's in the selected hotbar slot ("" = bare hand).
func hold(item_id: String) -> void:
	_held = item_id
	_item.mesh = _item_meshes.get(item_id)


func is_busy() -> bool:
	return _busy


## Overhand swing; emits `strike` at the moment of impact.
func swing(duration: float) -> void:
	if _busy:
		return
	_busy = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var wind := duration * 0.3
	var hit := duration * 0.15
	_tween.tween_property(self, "rotation", Vector3(0.55, 0.15, 0.25), wind).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "position", REST + Vector3(0.05, 0.12, 0.08), wind)
	_tween.tween_property(self, "rotation", Vector3(-0.9, -0.1, -0.15), hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.parallel().tween_property(self, "position", REST + Vector3(-0.12, -0.05, -0.22), hit)
	_tween.tween_callback(func() -> void: strike.emit())
	_tween.tween_property(self, "rotation", Vector3.ZERO, duration - wind - hit).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.parallel().tween_property(self, "position", REST, duration - wind - hit)
	_tween.tween_callback(func() -> void: _busy = false)


## Bring the held food to the mouth.
func eat(on_done: Callable) -> void:
	if _busy:
		return
	_busy = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "position", Vector3(0.05, -0.18, -0.28), 0.18).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(self, "rotation", Vector3(0.4, 0.5, 0), 0.18)
	_tween.tween_property(self, "position", Vector3(0.05, -0.2, -0.27), 0.25)
	_tween.tween_callback(on_done)
	_tween.tween_property(self, "position", REST, 0.25).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(self, "rotation", Vector3.ZERO, 0.25)
	_tween.tween_callback(func() -> void: _busy = false)


## Lag behind mouse movement a little, and bob while walking.
func add_sway(mouse_delta: Vector2) -> void:
	_sway += mouse_delta * 0.0004


func update_motion(delta: float, bob_phase: float, bob_amount: float) -> void:
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	_sway = _sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))
	_bob = bob_phase
	if not _busy:
		position = REST + Vector3(-_sway.x + cos(_bob) * 0.012 * bob_amount, _sway.y - absf(sin(_bob)) * 0.02 * bob_amount, 0)
