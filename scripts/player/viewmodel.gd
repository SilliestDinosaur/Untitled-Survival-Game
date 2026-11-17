class_name Viewmodel
extends Node3D
## The player's arm and held item in first person: a modeled hand gripping procedural tools,
## with per-tool swings (chop, thrust, slash), a reach for Interact, eating, and sway.

signal strike   ## the moment a swing connects
signal grab     ## the moment an Interact reach arrives

const REST := Vector3(0.25, -0.24, -0.42)
const SKIN := Color(0.86, 0.67, 0.53)
const SLEEVE := Color(0.5, 0.42, 0.33)

var _arm: MeshInstance3D
var _item: MeshInstance3D
var _mat: ShaderMaterial
var _cache := {}
var _tween: Tween
var _sway := Vector2.ZERO
var _busy := false
var _held := ""
var _held_type := ""


func _ready() -> void:
	position = REST
	rotation = Vector3(0.05, 0.12, 0.0)
	_mat = ArtStyle.painted({"brush_strength": 0.18, "rim_amount": 0.25, "stroke_scale": 2.5, "edge_pool": 0.12})
	_arm = MeshInstance3D.new()
	_arm.mesh = _build_arm()
	_arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_arm)
	_item = MeshInstance3D.new()
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_item)
	# Held items use this world's colors (materials, berries...): rebuild them per world.
	Game.world_changed.connect(func() -> void:
		_cache.clear()
		hold(_held))


## A simple, stylized hand: one rounded fist, a small thumb, wrist and sleeve.
func _build_arm() -> ArrayMesh:
	var k := MeshKit.new(5)
	k.add_primitive(MeshKit.sphere(0.5, 12, 8), Transform3D(Basis.from_scale(Vector3(0.08, 0.09, 0.085)), Vector3(0.0, 0.0, -0.005)), SKIN, 0.0, 0.03)
	k.add_primitive(MeshKit.sphere(0.5, 10, 6), Transform3D(Basis(Vector3.FORWARD, 0.5) * Basis.from_scale(Vector3(0.03, 0.045, 0.03)), Vector3(-0.035, 0.03, -0.03)), SKIN, 0.0, 0.03)
	var fb := Basis(Vector3.RIGHT, deg_to_rad(68)) * Basis(Vector3.FORWARD, deg_to_rad(-12))
	k.add_primitive(MeshKit.cylinder(0.03, 0.034, 0.08, 10), Transform3D(fb, Vector3(0.008, -0.055, 0.04)), SKIN, 0.0, 0.02)
	k.add_primitive(MeshKit.cylinder(0.04, 0.05, 0.34, 12), Transform3D(fb, Vector3(0.03, -0.12, 0.2)), SLEEVE, 0.0, 0.04)
	return k.commit(_mat)


## Show what's in the selected hotbar slot ("" = bare hand).
func hold(item_id: String) -> void:
	_held = item_id
	var info := ItemDB.info(item_id) if item_id != "" else {}
	_held_type = String(info.get("tool", {}).get("type", "")) if info.has("tool") else ""
	if item_id == "":
		_item.mesh = null
		return
	if not _cache.has(item_id):
		_cache[item_id] = _build_item(item_id, info)
	_item.mesh = _cache[item_id]


func _build_item(id: String, info: Dictionary) -> ArrayMesh:
	var k := MeshKit.new(hash(id))
	var col: Color = info.get("color", Color(0.8, 0.8, 0.8))
	if info.kind == "tool":
		var t: Dictionary = info.tool
		if t.type == "rock":
			_flint(k, Vector3(0.0, 0.03, -0.045), 0.033)
		else:
			_tool(k, t.type, int(t.tier), col)
		return k.commit(_mat)
	# Food & materials held in the fist.
	var at := Vector3(0, 0.055, -0.05)
	match String(info.get("icon", "")):
		"berries":
			for i in 9:
				var a := i * 2.4
				k.add_primitive(MeshKit.sphere(0.022, 8, 5), Transform3D(Basis(), at + Vector3(cos(a) * 0.026 * (i % 3), (i / 3) * 0.018, sin(a) * 0.026 * (i % 3))), col, 0.0, 0.05)
		"meat":
			k.add_primitive(MeshKit.sphere(0.06, 10, 6), Transform3D(Basis.from_scale(Vector3(1.3, 0.6, 1.0)), at), Color(0.78, 0.36, 0.38), 0.04, 0.06)
			k.add_primitive(MeshKit.cylinder(0.01, 0.01, 0.1, 6), Transform3D(Basis(Vector3.FORWARD, PI / 2), at + Vector3(0.08, 0, 0)), Color(0.93, 0.9, 0.84), 0.0, 0.0)
		"mushroom":
			k.add_primitive(MeshKit.cylinder(0.012, 0.016, 0.05, 7), Transform3D(Basis(), at), Color(0.92, 0.88, 0.8), 0.0, 0.02)
			k.add_primitive(MeshKit.sphere(0.04, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 0.55, 1)), at + Vector3(0, 0.03, 0)), col, 0.0, 0.04)
		"fruit", "cactus":
			k.add_primitive(MeshKit.sphere(0.045, 10, 6), Transform3D(Basis.from_scale(Vector3(1, 1.1, 1)), at), col if info.icon == "fruit" else Game.palette.cactus, 0.02, 0.05)
		"herb":
			for i in 5:
				var b := Basis(Vector3.UP, i * 1.2) * Basis(Vector3.RIGHT, 0.5)
				k.add_primitive(MeshKit.sphere(0.5, 6, 4), Transform3D(b * Basis.from_scale(Vector3(0.02, 0.07, 0.008)), at + b.y * 0.03), col, 0.0, 0.05)
		_:
			k.add_primitive(MeshKit.sphere(0.045, 9, 6), Transform3D(Basis.from_scale(Vector3(1.2, 0.8, 1)), at), col, 0.15, 0.06)
	return k.commit(_mat)


## A chipped flint rock with lighter fractured faces.
func _flint(k: MeshKit, at: Vector3, r: float) -> void:
	var stone := Color(0.42, 0.44, 0.48)
	var chipped := func(p: Vector3) -> Color:
		var d := (p - at).normalized()
		return stone.lightened(0.25) if d.dot(Vector3(0.4, 0.7, -0.6).normalized()) > 0.55 or d.dot(Vector3(-0.7, 0.2, -0.6).normalized()) > 0.7 else stone
	k.add_primitive(MeshKit.sphere(r, 7, 5), Transform3D(Basis(Vector3.UP, 0.6).scaled(Vector3(1.25, 0.85, 1.05)), at), stone, 0.35, 0.06, null, chipped)


## Procedural tool: wooden handle along +Y with a head that depends on type and tier.
func _tool(k: MeshKit, type: String, tier: int, col: Color) -> void:
	var wood := Color(0.55, 0.4, 0.26)
	var lash := Color(0.72, 0.63, 0.42)
	var head := col
	if tier == 1:
		head = Color(0.5, 0.5, 0.54)    # knapped stone
	var handle_len := 0.48 if type != "knife" else 0.11
	var top := Vector3(0, handle_len - 0.06, 0)
	if type == "spear":
		handle_len = 1.0
		top = Vector3(0, 0.75, 0)
	k.add_primitive(MeshKit.cylinder(0.014, 0.017, handle_len, 8), Transform3D(Basis(), Vector3(0, handle_len * 0.5 - 0.1, 0)), wood, 0.0, 0.04)
	var bind := func(at: Vector3) -> void:
		# Stone tools are lashed with fiber; metal ones get a collar.
		k.add_primitive(MeshKit.cylinder(0.021, 0.021, 0.035, 8), Transform3D(Basis(), at), lash if tier == 1 else head.darkened(0.25), 0.0, 0.03)
	match type:
		"hatchet":
			bind.call(top)
			k.add_primitive(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(0.022, 0.07, 0.07)), top + Vector3(0, 0, -0.035)), head.darkened(0.08), 0.0, 0.05)
			k.add_primitive(BoxMesh.new(), Transform3D(Basis(Vector3.RIGHT, 0.0).scaled(Vector3(0.012, 0.11, 0.06)), top + Vector3(0, 0, -0.09)), head.lightened(0.1), 0.0, 0.05)
		"pickaxe":
			bind.call(top)
			for side in [-1.0, 1.0]:
				var pos := top
				var dir := Vector3(0, 0.25, side).normalized()
				var r := 0.02
				for seg in 3:
					var seg_len := 0.06
					k.add_primitive(MeshKit.cylinder(r * 0.7, r, seg_len, 7), Transform3D(Basis(Quaternion(Vector3.UP, dir)), pos + dir * seg_len * 0.5), head.lightened(seg * 0.05), 0.0, 0.04)
					pos += dir * seg_len * 0.95
					dir = (dir + Vector3(0, -0.3, 0)).normalized()
					r *= 0.75
		"spear":
			bind.call(top)
			k.add_primitive(MeshKit.cylinder(0.0, 0.028, 0.13, 6), Transform3D(Basis(), top + Vector3(0, 0.08, 0)), head.lightened(0.08), 0.0, 0.05)
		"knife":
			k.add_primitive(MeshKit.cylinder(0.02, 0.02, 0.012, 8), Transform3D(Basis(), top), head.darkened(0.3), 0.0, 0.0)   # guard
			k.add_primitive(BoxMesh.new(), Transform3D(Basis.from_scale(Vector3(0.006, 0.13, 0.03)), top + Vector3(0, 0.07, 0)), head.lightened(0.15), 0.0, 0.04)
			k.add_primitive(MeshKit.cylinder(0.0, 0.015, 0.035, 4), Transform3D(Basis.from_scale(Vector3(0.4, 1, 1)), top + Vector3(0, 0.152, 0)), head.lightened(0.15), 0.0, 0.0)
	if tier == 4:   # gem tools: a glinting inset
		k.add_primitive(MeshKit.sphere(0.012, 6, 4), Transform3D(Basis(), top + Vector3(0.018, 0.01, 0)), head.lightened(0.5), 0.0, 0.0)


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
