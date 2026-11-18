class_name TorchGlow
extends Node3D
## The burning tip of a held torch: a flickering flame and the light it throws. Used for your own torch in first
## person and for other players' torches, so a friend's torch lights a cave the same way yours does.
## Add it as a child of the torch model; it sits at the model's tip.

const TIP := Vector3(0, 0.33, 0)
const LIGHT_ABOVE_TIP := 0.09
const CAVE_CHECK := 0.5   ## seconds between underground checks

var _light: OmniLight3D
var _flame: MeshInstance3D
var _t := 0.0
var _check := 0.0
var _underground := false


func _ready() -> void:
	position = TIP
	_t = randf() * 10.0   # torches side by side don't flicker in step
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.65, 0.32)
	_light.omni_range = 14.0
	_light.omni_attenuation = 1.3
	_light.shadow_enabled = false
	_light.position = Vector3(0, LIGHT_ABOVE_TIP, 0)
	add_child(_light)
	_flame = MeshInstance3D.new()
	_flame.mesh = ItemModels.torch_flame()
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flame)


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	_check -= delta
	if _check <= 0.0:
		_check = CAVE_CHECK
		# Underground it's always night, whatever the clock says (checked where this torch is, not where you are).
		_underground = Game.world_gen != null and Caves.void_distance(Game.world_gen.caves, global_position) < 0.0
	var dark := 1.0 if _underground else 1.0 - Game.daylight()
	var flicker := 0.85 + 0.1 * sin(_t * 13.0) + 0.06 * sin(_t * 29.0)
	_light.light_energy = flicker * lerpf(0.6, 1.8, dark)
	_flame.scale = Vector3(1.0, flicker * 1.15, 1.0)
	_flame.rotation.y = _t * 1.5
