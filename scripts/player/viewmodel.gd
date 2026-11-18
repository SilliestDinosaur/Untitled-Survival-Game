class_name Viewmodel
extends Node3D
## The held item in first person (floating, no hands), with per-tool swings (chop, thrust, slash),
## a reach for Interact, eating, and sway. Models come from ItemModels.

signal strike   ## the moment a swing connects
signal grab     ## the moment an Interact reach arrives

const REST := Vector3(0.25, -0.24, -0.42)

## How big each long tool is in the hand (1.0 is the model's real size: a hatchet is 0.5 m, a spear 1.3 m).
const HELD_SCALE := {"hatchet": 0.62, "pickaxe": 0.62, "knife": 0.9, "spear": 0.6}   ## (the torch stays full size: its flame is a child of the model)

var _item: MeshInstance3D
var _mat: ShaderMaterial
var _tween: Tween
var _sway := Vector2.ZERO
var _busy := false
var _held := ""
var _held_type := ""
var _torch_light: OmniLight3D
var _torch_flame: MeshInstance3D
var _t := 0.0


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
	_set_torch(_held_type == "torch")
	_item.scale = Vector3.ONE
	if item_id == "":
		_item.mesh = null
		return
	_item.mesh = ItemModels.mesh_for(item_id, _mat)
	if info.kind == "placeable":   # a miniature of the station, held like a bundle
		_item.scale = Vector3.ONE * 0.11
		_item.position = Vector3(-0.02, -0.04, 0)
		_item.rotation = Vector3(0.35, 0.6, 0.0)
		return
	_item.scale = Vector3.ONE * float(HELD_SCALE.get(_held_type, 1.0))
	# Long tools lean in toward the middle of the screen; small things sit a little higher.
	# A head's blade runs along the model's -Z, so it's turned a quarter turn to put the blade's face toward you.
	if _held_type == "pickaxe":
		# The arms point away and the broad face turns a little toward you, so the blade reads as wide.
		_pose_tool(Vector3(0.06, -0.08, 0.0), 0.5, 0.7, -0.3)
	elif _held_type == "hatchet":
		# The head points away from you, as a Minecraft tool does, and tips up a little.
		_pose_tool(Vector3(0.06, -0.08, 0.0), 0.5, 0.0, -0.3)
	elif _held_type in ["knife", "torch"]:
		# Turned so you see the face of the head, not just its edge.
		_item.position = Vector3(0, -0.06, 0)
		_item.rotation = Vector3(-0.15, 0.9, 0.3)
	elif _held_type == "spear":
		# Upright and leaning left, so the head stays in view.
		_item.position = Vector3(0.06, -0.2, 0.05)
		_item.rotation = Vector3(-0.2, 0.3, 0.55)
	else:
		_item.position = Vector3(0, 0.03, 0)
		_item.rotation = Vector3(0.2, 0.5, 0.0)


## Hold a tool the Minecraft way: the handle comes in from the bottom right and leans so the head tips up and to
## the left, while the blade's face turns toward you. `roll` leans it in the view, `turn` turns the blade about Y.
## The basis is built directly (not from Euler angles) so the lean is applied in the view's frame.
func _pose_tool(at: Vector3, roll: float, turn: float, pitch := 0.0) -> void:
	var rot := Basis(Vector3.BACK, roll) * Basis(Vector3.UP, turn) * Basis(Vector3.RIGHT, pitch)
	_item.transform = Transform3D(rot.scaled(Vector3.ONE * float(HELD_SCALE.get(_held_type, 1.0))), at)


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


## A held torch lights the area around you and has a flickering flame at its tip.
func _set_torch(on: bool) -> void:
	if on and not _torch_light:
		_torch_light = OmniLight3D.new()
		_torch_light.light_color = Color(1.0, 0.65, 0.32)
		_torch_light.omni_range = 14.0
		_torch_light.omni_attenuation = 1.3
		_torch_light.shadow_enabled = false
		_item.add_child(_torch_light)
		_torch_light.position = Vector3(0, 0.42, 0)
		_torch_flame = MeshInstance3D.new()
		_torch_flame.mesh = ItemModels.torch_flame()
		_torch_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_torch_flame.position = Vector3(0, 0.33, 0)
		_item.add_child(_torch_flame)
	if _torch_light:
		_torch_light.visible = on
		_torch_flame.visible = on


func _process(delta: float) -> void:
	if not _torch_light or not _torch_light.visible:
		return
	_t += delta
	var night := 1.0 - Game.daylight()
	var flicker := 0.85 + 0.1 * sin(_t * 13.0) + 0.06 * sin(_t * 29.0)
	_torch_light.light_energy = flicker * lerpf(0.6, 1.8, night)
	_torch_flame.scale = Vector3(1.0, flicker * 1.15, 1.0)
	_torch_flame.rotation.y = _t * 1.5
