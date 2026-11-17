class_name Viewmodel
extends Node3D
## The held item in first person (floating, no hands), with per-tool swings (chop, thrust, slash),
## a reach for Interact, eating, and sway. Models come from ItemModels.

signal strike   ## the moment a swing connects
signal grab     ## the moment an Interact reach arrives

const REST := Vector3(0.25, -0.24, -0.42)

var _item: MeshInstance3D
var _mat: ShaderMaterial
var _tween: Tween
var _sway := Vector2.ZERO
var _busy := false
var _held := ""
var _held_type := ""


func _ready() -> void:
	position = REST
	rotation = Vector3(0.05, 0.12, 0.0)
	_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.3, "stroke_scale": 3.0, "edge_pool": 0.1})
	# No hands: the held item floats in view (a clean, stylized look).
	_item = MeshInstance3D.new()
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_item)
	Game.world_changed.connect(func() -> void:
		ItemModels.clear_cache()
		hold(_held))


## Show what's in the selected hotbar slot ("" = nothing in hand).
func hold(item_id: String) -> void:
	_held = item_id
	var info := ItemDB.info(item_id) if item_id != "" else {}
	_held_type = String(info.tool.type) if info.has("tool") else ""
	if item_id == "":
		_item.mesh = null
		return
	_item.mesh = ItemModels.mesh_for(item_id, _mat)
	# Long tools lean in toward the middle of the screen; small things sit a little higher.
	if _held_type in ["hatchet", "pickaxe", "knife"]:
		_item.position = Vector3(0, -0.06, 0)
		_item.rotation = Vector3(-0.15, 0.25, 0.32)
	elif _held_type == "spear":
		_item.position = Vector3(0.02, -0.28, 0.1)
		_item.rotation = Vector3(-0.35, 0.2, 0.18)
	else:
		_item.position = Vector3(0, 0.03, 0)
		_item.rotation = Vector3(0.2, 0.5, 0.0)


func is_busy() -> bool:
	return _busy


func _start() -> Tween:
	_busy = true
	if _tween:
		_tween.kill()
	_tween = create_tween()
	return _tween


func _finish(tw: Tween, back_time: float) -> void:
	tw.tween_property(self, "rotation", Vector3(0.05, 0.12, 0.0), back_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "position", REST, back_time).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void: _busy = false)


## Swing the held tool; emits `strike` at the moment of impact.
func swing(duration: float, tool_type := "") -> void:
	if _busy:
		return
	var tw := _start()
	var wind := duration * 0.32
	var hit := duration * 0.14
	match tool_type:
		"spear":   # thrust straight ahead
			tw.tween_property(self, "position", REST + Vector3(0.02, 0.0, 0.12), wind).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(self, "rotation", Vector3(-1.35, 0.1, 0.0), wind)
			tw.tween_property(self, "position", REST + Vector3(-0.08, 0.06, -0.45), hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		"knife":   # quick diagonal slash
			tw.tween_property(self, "rotation", Vector3(0.3, 0.6, 0.7), wind).set_trans(Tween.TRANS_SINE)
			tw.parallel().tween_property(self, "position", REST + Vector3(0.08, 0.08, 0.02), wind)
			tw.tween_property(self, "rotation", Vector3(-0.6, -0.5, -0.6), hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(self, "position", REST + Vector3(-0.16, -0.04, -0.16), hit)
		_:         # overhand chop (hatchet, pickaxe, rock, fist)
			tw.tween_property(self, "rotation", Vector3(0.65, 0.2, 0.25), wind).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			tw.parallel().tween_property(self, "position", REST + Vector3(0.04, 0.13, 0.08), wind)
			tw.tween_property(self, "rotation", Vector3(-0.95, -0.12, -0.15), hit).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.parallel().tween_property(self, "position", REST + Vector3(-0.12, -0.06, -0.2), hit)
	tw.tween_callback(func() -> void: strike.emit())
	_finish(tw, duration - wind - hit)


## Interact: reach forward and close the hand; emits `grab`.
func reach() -> void:
	if _busy:
		return
	var tw := _start()
	tw.tween_property(self, "position", REST + Vector3(-0.12, 0.06, -0.26), 0.13).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(self, "rotation", Vector3(-0.35, 0.35, 0.2), 0.13)
	tw.tween_callback(func() -> void: grab.emit())
	_finish(tw, 0.18)


## Bring the held food to the mouth.
func eat(on_done: Callable) -> void:
	if _busy:
		return
	var tw := _start()
	tw.tween_property(self, "position", Vector3(0.05, -0.17, -0.26), 0.18).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(self, "rotation", Vector3(0.4, 0.5, 0), 0.18)
	tw.tween_property(self, "position", Vector3(0.05, -0.19, -0.25), 0.22)
	tw.tween_callback(on_done)
	_finish(tw, 0.25)


## Lag behind mouse movement a little, and bob while walking.
func add_sway(mouse_delta: Vector2) -> void:
	_sway += mouse_delta * 0.0004


func update_motion(delta: float, bob_phase: float, bob_amount: float) -> void:
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	_sway = _sway.clamp(Vector2(-0.06, -0.06), Vector2(0.06, 0.06))
	if not _busy:
		position = REST + Vector3(-_sway.x + cos(bob_phase) * 0.012 * bob_amount, _sway.y - absf(sin(bob_phase)) * 0.02 * bob_amount, 0)
