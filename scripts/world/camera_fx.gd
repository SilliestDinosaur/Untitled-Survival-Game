class_name CameraFx
extends Node
## Blurs the world behind the satchel and the pause menu (depth of field on whichever camera is showing), easing in and
## out. Runs while the game is paused. Crafting cameras manage their own focus (CraftSession).

const MENU_BLUR := 0.85
const MENU_FAR := 1.0   ## metres: everything past this goes soft

var _amount := 0.0
var _cam: Camera3D
var _blur: DofBlur


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.has_meta("own_focus"):
		return
	if cam != _cam:
		_cam = cam
		_amount = 0.0
		_blur = cam.get_node_or_null("MenuBlur") as DofBlur
		if _blur == null:
			_blur = DofBlur.attach(cam)
			_blur.name = "MenuBlur"
	var want := MENU_BLUR if Game.menu_open and Settings.depth_of_field else 0.0
	_amount = move_toward(_amount, want, delta * 4.0)
	_blur.set_blur(MENU_FAR, 4.0, _amount)
