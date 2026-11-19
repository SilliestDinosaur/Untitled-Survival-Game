class_name CraftSession
extends Node3D
## A crafting minigame at a station. The view glides to the station and the piece lies on it while you work:
## turning food on a spit over the campfire, pumping the forge's bellows to smelt ore, heating a head and hammering
## it on the anvil, shaping a tool on the workbench, or knapping a stone head by hand.
## Doing well only makes it faster. Nothing moves unless you act, and nothing is used up until an item is done
## (finishing sends the ordinary craft request, so the host checks it as before). Shift-crafted batches run back
## to back. Esc, right click or a movement key stops; so does getting hurt.

signal ended

enum Mode { COOK, SMELT, SMITH, CARVE, KNAP }

const TOOL_TYPES := ["hatchet", "pickaxe", "spear", "knife"]
const INGOTS := ["ingot_t2", "ingot_t3", "dusk_ingot"]

## Timing: how much a strike moves the work along, by how well it was timed.
const PERFECT_Q := 0.7
const GOOD_Q := 0.25
const MISS_GAIN := 0.03
const MISS_LOCK := 0.5      ## a fumble: a moment before you can strike again (so mashing is slow)
const HIT_LOCK := 0.22
## The forge: hold to pump the bellows. Progress only while the fire is hot enough, fastest in the band.
const HEAT_UP := 0.7
const HEAT_DOWN := 0.4
const HEAT_BAND := Vector2(0.6, 0.85)
const HEAT_WARM := 0.4
const SMITH_HEAT_SHARE := 0.3   ## the part of a forged tool's progress spent heating it

var player: Node
var recipe: Dictionary
var mode: int = Mode.CARVE
var left := 1
var made := 0
var progress := 0.0
var heat := 0.15
var cue_t := 0.0           ## the timing cue's phase (0..1-ish)
var target := 0.5          ## the workbench mark, along the piece (0..1)
var phase := 0             ## smithing: 0 heating, 1 hammering
var feedback := {}         ## {"text", "color", "age"}: the last strike's grade, shown briefly

var _station := {}         ## {"kind", "pos", "yaw"} of the station being used
var _xf := Transform3D()   ## the station's frame
var _cam: Camera3D
var _work: MeshInstance3D
var _glow: MeshInstance3D
var _striker_pivot: Node3D
var _striker_rest := Basis()
var _props: Node3D
var _layer: CanvasLayer
var _overlay: Control
var _lock := 0.0
var _busy := true          ## gliding in or out, or waiting on the finished item
var _closing := false
var _side := Vector3.BACK  ## campfire: which side you're watching from
var _turn := 0.0           ## campfire: the spit's turn
var _done := false         ## the finished item is showing

static var _mat: ShaderMaterial


## Which minigame a recipe uses, or -1 to craft it at once.
static func mode_for(r: Dictionary) -> int:
	var out: String = r.out
	if r.at == "campfire" and r.group == "Food":
		return Mode.COOK
	if out in INGOTS:
		return Mode.SMELT
	var info := ItemDB.info(out)
	if info.get("kind", "") == "tool" and String(info.get("tool", {}).get("type", "")) in TOOL_TYPES:
		match String(r.at):
			"forge": return Mode.SMITH
			"workbench": return Mode.CARVE
			"": return Mode.KNAP
	return -1


## Why a craft can't start right now ("" if it can).
static func problem(p: Node, r: Dictionary) -> String:
	if GameActions.craftable_count(p.inventory, r) < 1:
		return "Missing ingredients"
	if r.at != "" and _nearest_station(p.global_position, r.at).is_empty():
		return "Needs a %s nearby" % Recipes.STATION_NAMES[r.at]
	return ""


static func _nearest_station(pos: Vector3, kind: String) -> Dictionary:
	var best := {}
	var best_d := Recipes.STATION_RANGE
	for id: String in Game.structures:
		var st: Dictionary = Game.structures[id]
		if st.kind != kind:
			continue
		var p: Array = st.pos
		var at := Vector3(p[0], p[1], p[2])
		var d := at.distance_to(pos)
		if d <= best_d:
			best_d = d
			best = {"kind": kind, "pos": at, "yaw": float(st.get("yaw", 0.0))}
	return best


func begin(p: Node, r: Dictionary, times: int) -> void:
	player = p
	recipe = r
	mode = mode_for(r)
	left = maxi(times, 1)
	if not _mat:
		_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.3, "stroke_scale": 3.0, "edge_pool": 0.1})
	if r.at != "":
		_station = _nearest_station(player.global_position, r.at)
		_xf = Transform3D(Basis(Vector3.UP, float(_station.yaw)), _station.pos)
	player.crafting = self
	player.viewmodel.visible = false
	player.stats.damaged.connect(_on_hurt)
	player.stats.died.connect(_on_died)
	_layer = CanvasLayer.new()
	_layer.layer = 3
	add_child(_layer)
	_overlay = CraftOverlay.new()
	_overlay.session = self
	_layer.add_child(_overlay)
	_build_props()
	_setup_piece()
	if mode == Mode.KNAP:
		_busy = false   # by hand: you're already looking at it
		return
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_transform = player.camera.global_transform
	_cam.fov = player.camera.fov
	_cam.current = true
	_glide(_view(), func() -> void: _busy = false)


# --- Views and pieces ----------------------------------------------------------------------

## Where the camera looks from and at for the current step, as a global transform.
func _view() -> Transform3D:
	var from := Vector3.ZERO
	var at := Vector3.ZERO
	match mode:
		Mode.COOK:
			var c: Vector3 = _station.pos
			return _look(c + _side * 1.35 + Vector3(0, 1.2, 0), c + Vector3(0, 0.66, 0))
		Mode.SMELT:
			from = Vector3(0.18, 1.0, -1.5)
			at = Vector3(0, 0.48, -0.62)
		Mode.SMITH:
			if phase == 0:
				from = Vector3(0.3, 1.05, -1.55)
				at = Vector3(0.1, 0.5, -0.62)
			else:
				from = Vector3(1.3, 1.4, -1.05)
				at = Vector3(0.95, 0.67, -0.2)
		Mode.CARVE:
			var s := _bench_side()
			from = Vector3(0.0, 1.62, s * 1.0)
			at = Vector3(0.0, 0.84, s * 0.05)
	return _look(_xf * from, _xf * at)


static func _look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


## Which long side of the workbench you're standing at (+1 or -1 along its local z).
func _bench_side() -> float:
	var local: Vector3 = _xf.affine_inverse() * player.global_position
	return 1.0 if local.z >= 0.0 else -1.0


func _glide(to: Transform3D, then: Callable) -> void:
	var from := _cam.global_transform
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: _cam.global_transform = from.interpolate_with(to, w), 0.0, 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(then)


## Things the station needs for this job that it doesn't have already: a spit or a pot over the campfire.
func _build_props() -> void:
	_props = Node3D.new()
	add_child(_props)
	if mode != Mode.COOK:
		return
	var to_player: Vector3 = player.global_position - _station.pos
	to_player.y = 0.0
	_side = to_player.normalized() if to_player.length() > 0.1 else Vector3.BACK
	var along := _side.cross(Vector3.UP).normalized()   # the spit runs across your view
	var k := MeshKit.new(5)
	var bark := Color(0.42, 0.3, 0.2)
	for s in [-1.0, 1.0]:   # two forked uprights
		var foot: Vector3 = along * 0.52 * s
		k.loft([foot, foot + Vector3(0, 0.92, 0)], [0.024, 0.02], 7, bark, Callable(), Callable(), true, true, 0.004)
		for f in [-1.0, 1.0]:
			k.loft([foot + Vector3(0, 0.84, 0), foot + Vector3(0, 0.97, 0) + _side * 0.05 * f], [0.014, 0.01], 5, bark, Callable(), Callable(), true, true)
	k.loft([along * -0.62 + Vector3(0, 0.88, 0), along * 0.62 + Vector3(0, 0.88, 0)], [0.013, 0.013], 7, bark.lightened(0.1), Callable(), Callable(), true, true)
	if recipe.out == "stew":   # a pot hung from the crossbar on a cord
		k.loft([Vector3(0, 0.88, 0), Vector3(0, 0.74, 0)], [0.006, 0.006], 5, Color(0.6, 0.5, 0.35))
		var iron := Color(0.2, 0.19, 0.2)
		k.add_primitive(MeshKit.cylinder(0.15, 0.12, 0.17, 16), Transform3D(Basis(), Vector3(0, 0.66, 0)), iron, 0.0, 0.05)
		k.add_primitive(MeshKit.cylinder(0.135, 0.135, 0.01, 16), Transform3D(Basis(), Vector3(0, 0.745, 0)), Color(0.5, 0.28, 0.16), 0.0, 0.04)
	var mi := MeshInstance3D.new()
	mi.mesh = k.commit(_mat)
	_props.add_child(mi)
	mi.global_position = _station.pos


## Lay the piece being made where it's worked on, and the tool that strikes it.
func _setup_piece() -> void:
	if _work:
		_work.queue_free()
	if _glow:
		_glow.queue_free()
		_glow = null
	_work = MeshInstance3D.new()
	_work.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_work.mesh = _spoon() if _piece_item() == "" else ItemModels.mesh_for(_piece_item(), _mat)
	_work.scale = Vector3.ONE * _piece_scale()
	if mode == Mode.KNAP:
		player.camera.add_child(_work)
	else:
		add_child(_work)
	_place_piece()
	if mode in [Mode.SMELT, Mode.SMITH]:
		_glow = MeshInstance3D.new()
		_glow.mesh = _work.mesh
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.albedo_color = Color(0, 0, 0)
		_glow.material_override = gm
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_glow.scale = Vector3.ONE * 1.02
		_work.add_child(_glow)
	_setup_striker()


## What lies on the station while you work: the raw food or ore going in, or the tool taking shape.
func _piece_item() -> String:
	match mode:
		Mode.COOK:
			if recipe.out == "stew":
				return ""   # a spoon in the pot
			return String(recipe.needs.keys()[0])
		Mode.SMELT:
			for item: String in recipe.needs:
				if item != "wood":
					return item
		Mode.KNAP:   # the stone being shaped into a head; the tool itself appears when it's done
			for item: String in ["flint", "stone"]:
				if recipe.needs.has(item):
					return item
	return String(recipe.out)


## A wooden spoon standing in the stew pot, for stirring.
func _spoon() -> ArrayMesh:
	var k := MeshKit.new(4)
	var wood := Color(0.62, 0.45, 0.28)
	k.loft([Vector3(0.0, -0.05, 0), Vector3(0.0, 0.32, 0)], [0.02, 0.017], 7, wood, Callable(), Callable(), true, true)
	k.add_primitive(MeshKit.sphere(0.045, 8, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.3)), Vector3(0.0, -0.06, 0)), wood.darkened(0.15), 0.0, 0.03)
	return k.commit(_mat)


func _piece_scale() -> float:
	if _done:   # the finished item, at a size that suits where it is
		match mode:
			Mode.KNAP: return 0.45
			Mode.COOK: return 1.0 if recipe.out == "stew" else 2.0
	match mode:
		Mode.COOK: return 1.0 if recipe.out == "stew" else 3.0
		Mode.SMELT: return 1.6
		Mode.KNAP: return 1.0
	return 1.0


func _place_piece() -> void:
	var sc := _piece_scale()
	match mode:
		Mode.COOK:
			if recipe.out == "stew":   # the spoon leans in the pot
				_work.global_transform = Transform3D(Basis(Vector3.UP, _turn) * Basis(Vector3.BACK, 0.35), _station.pos + Vector3(0, 0.72, 0))
			else:                      # skewered at the middle of the spit
				var along := _side.cross(Vector3.UP).normalized()
				_set_centred(Basis(along, _turn) * Basis(Vector3.UP, 0.4), _station.pos + Vector3(0, 0.88, 0), sc)
		Mode.SMELT:
			_set_centred(_xf.basis * Basis(Vector3.UP, 0.5), _xf * Vector3(0, 0.5, -0.62), sc)
		Mode.SMITH:
			var head := _head_y()
			if phase == 0:   # the head in the coals, the handle sticking out toward you
				_work.global_transform = _xf * Transform3D(Basis(Vector3.RIGHT, PI * 0.5 - 0.1) * Basis(Vector3.UP, PI * 0.5), Vector3(0.05, 0.47, -0.6 - head))
			else:            # lying on the anvil, blade flat, the head over the middle of the face
				var b := Basis(Vector3.UP, 0.3)
				_work.global_transform = _xf * Transform3D(b * _lying(), Vector3(0.95, 0.68, -0.2) + b * Vector3(head - 0.04, 0, 0))
		Mode.CARVE:
			_work.global_transform = _xf * Transform3D(_lying(), Vector3(_head_y() - 0.12, 0.875, _bench_side() * 0.08))
		Mode.KNAP:   # held up in front of you, a little below the middle of the view
			var t := Transform3D(Basis(Vector3.RIGHT, 0.5) * Basis(Vector3.UP, 0.6), Vector3(-0.02, -0.11, -0.42))
			_work.transform = Transform3D(t.basis.scaled(Vector3.ONE * sc), t.origin - t.basis.scaled(Vector3.ONE * sc) * _work.mesh.get_aabb().get_center())


## Puts the piece so the middle of its model (not its origin, which can be at one end) is at `at`.
func _set_centred(basis: Basis, at: Vector3, sc: float) -> void:
	var b := basis.scaled(Vector3.ONE * sc)
	var c := _work.mesh.get_aabb().get_center() if _work.mesh else Vector3.ZERO
	_work.global_transform = Transform3D(b, at - b * c)


## How far up the handle a tool's head (or blade) is: most of the way to its top.
func _head_y() -> float:
	if not is_instance_valid(_work) or not _work.mesh:
		return 0.34
	return _work.mesh.get_aabb().end.y * 0.82


## A tool lying flat: the handle along x (butt to the right), the head's face horizontal.
static func _lying() -> Basis:
	return Basis(Vector3.BACK, PI * 0.5)


## The point being struck (or watched), in world space.
func work_point() -> Vector3:
	if not is_instance_valid(_work):
		return global_position
	match mode:
		Mode.COOK, Mode.SMELT, Mode.KNAP:
			if _work.mesh:
				return _work.global_transform * _work.mesh.get_aabb().get_center()
			return _work.global_position
	return _work.global_transform * Vector3(0, _head_y(), 0)


func _setup_striker() -> void:
	if _striker_pivot:
		_striker_pivot.queue_free()
		_striker_pivot = null
	if mode in [Mode.COOK, Mode.SMELT] or (mode == Mode.SMITH and phase == 0):
		return   # nothing to strike with yet
	var tool_id := "rock" if mode == Mode.KNAP else "hammer"
	var mi := MeshInstance3D.new()
	mi.mesh = ItemModels.mesh_for(tool_id, _mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_striker_pivot = Node3D.new()
	_striker_pivot.add_child(mi)
	if mode == Mode.KNAP:
		# The striking rock in your other hand, off to the right.
		player.camera.add_child(_striker_pivot)
		_striker_pivot.position = Vector3(0.17, -0.16, -0.4)
		mi.scale = Vector3.ONE * 0.55
		_striker_pivot.basis = Basis(Vector3.FORWARD, 0.6)
		return
	add_child(_striker_pivot)
	# The hammer comes in from the side away from you; its handle points at the piece, its face down.
	var hit := work_point()
	var cam_pos := _view().origin
	var away := (hit - cam_pos)
	away.y = 0.0
	away = away.normalized()
	var side := away.cross(Vector3.UP).normalized()
	_striker_pivot.global_position = hit - side * 0.33 + Vector3(0, 0.1, 0)   # the head's lower face meets the piece
	var y_axis := side   # from the pivot toward the piece
	var z_axis := Vector3.UP
	_striker_rest = Basis(y_axis.cross(z_axis), y_axis, z_axis).orthonormalized() * Basis(Vector3.RIGHT, 0.8)
	_striker_pivot.global_basis = _striker_rest


# --- Playing --------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if feedback.has("age"):
		feedback.age += delta
	if _busy or _closing:
		return
	_lock = maxf(_lock - delta, 0.0)
	var holding := Input.is_action_pressed("attack")
	match mode:
		Mode.SMELT:
			_pump(delta, holding, 0.2)
		Mode.SMITH:
			if phase == 0:
				_pump(delta, holding, 0.26)
				if progress >= SMITH_HEAT_SHARE:
					_to_anvil()
			else:
				_advance_cue(delta)
				_cool(delta)
		_:
			_advance_cue(delta)
	if _glow:
		var glow := smoothstep(0.3, 0.9, heat)
		(_glow.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.42, 0.1) * glow * 0.9
	if progress >= 1.0:
		_finish_item()


## Bellows: holding pumps the heat up, letting go lets it fall. The work goes fastest in the hot band.
func _pump(delta: float, holding: bool, rate: float) -> void:
	heat = clampf(heat + (HEAT_UP if holding else -HEAT_DOWN) * delta, 0.0, 1.0)
	if heat >= HEAT_BAND.x and heat <= HEAT_BAND.y:
		progress += rate * delta
	elif heat >= HEAT_WARM and heat < HEAT_BAND.x:
		progress += rate * 0.3 * delta
	if holding and fmod(Time.get_ticks_msec() / 1000.0, 0.45) < delta:
		Audio.play_3d("swoosh", work_point(), -14.0, 0.55)


func _cool(delta: float) -> void:
	heat = maxf(heat - 0.12 * delta, 0.35)   # the head cools slowly on the anvil


## The cue's speed and how a strike is graded, per game.
func _advance_cue(delta: float) -> void:
	match mode:
		Mode.COOK:
			cue_t += delta / 1.1
			if cue_t > 1.0:
				cue_t = 0.0   # missed the moment: it just comes round again
		Mode.CARVE:
			cue_t += delta / 0.75
		_:   # a ring closing on the strike point
			cue_t += delta / 0.85
			if cue_t > 1.3:
				cue_t = 0.0


## The sweep marker's place along the piece (workbench).
func sweep_pos() -> float:
	return pingpong(cue_t, 1.0)


func _quality() -> float:
	match mode:
		Mode.COOK:
			return clampf(1.0 - absf(cue_t - 0.85) / 0.12, 0.0, 1.0)
		Mode.CARVE:
			return clampf(1.0 - absf(sweep_pos() - target) / 0.11, 0.0, 1.0)
	return clampf(1.0 - absf(cue_t - 1.0) / 0.2, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	# While working, the game's other keys wait: Esc, right click and walking away stop instead.
	if event is InputEventMouseMotion:
		return
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		stop()
		return
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		if event.is_action_pressed(a):
			stop()
			return
	if event.is_action_pressed("attack"):
		strike()


## A click: a strike, a turn of the spit, or (at the forge) the start of a pump.
func strike() -> void:
	if _busy or _closing or _lock > 0.0:
		return
	if mode == Mode.SMELT or (mode == Mode.SMITH and phase == 0):
		return   # pumping is holding, handled each frame
	var q := _quality()
	var gain := MISS_GAIN
	if q >= PERFECT_Q:
		gain = 0.2
		feedback = {"text": "Perfect!", "color": Color(0.75, 1.0, 0.6), "age": 0.0}
	elif q >= GOOD_Q:
		gain = lerpf(0.08, 0.2, q)
		feedback = {"text": "Good", "color": Color(1.0, 0.92, 0.6), "age": 0.0}
	else:
		feedback = {"text": "Miss", "color": Color(1.0, 0.6, 0.5), "age": 0.0}
	if mode == Mode.COOK:
		gain *= 0.85
	elif mode == Mode.SMITH:
		gain *= 1.0 - SMITH_HEAT_SHARE
	progress += gain
	_lock = HIT_LOCK if q >= GOOD_Q else MISS_LOCK
	_show_strike(q >= GOOD_Q)
	match mode:
		Mode.COOK:
			cue_t = 0.0   # turned: the other side starts browning
		Mode.CARVE:
			# A new mark, well away from where the marker is now.
			var u := sweep_pos()
			target = clampf(fposmod(u + randf_range(0.3, 0.7), 1.0), 0.15, 0.85)
		_:
			cue_t = 0.0


func _show_strike(good: bool) -> void:
	var at := work_point()
	match mode:
		Mode.COOK:
			create_tween().tween_method(_set_turn, _turn, _turn + PI, 0.25).set_trans(Tween.TRANS_SINE)
			Audio.play_3d("rustle", at, -6.0, 0.7 if good else 0.5)
			if good:
				Effects.chips(self, at, Color(1.0, 0.75, 0.4), 5, 0.025, 1.2)   # spitting fat
			return
	if _striker_pivot and mode == Mode.KNAP:
		# The rock knocks against the edge of the head and comes back.
		var rest := _striker_pivot.position
		var hit_at: Vector3 = player.camera.to_local(at) + Vector3(0.05, 0.0, 0.0)
		var tw := create_tween()
		tw.tween_property(_striker_pivot, "position", hit_at, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_striker_pivot, "position", rest, 0.18).set_trans(Tween.TRANS_SINE)
	elif _striker_pivot:
		var tw := create_tween()
		tw.tween_property(_striker_pivot, "basis", _striker_rest * Basis(Vector3.RIGHT, -0.8), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_striker_pivot, "basis", _striker_rest, 0.18).set_trans(Tween.TRANS_SINE)
	match mode:
		Mode.SMITH:
			Audio.play_3d("clink", at, -2.0, randf_range(0.95, 1.1) if good else 0.8)
			Effects.chips(self, at, Color(1.0, 0.6, 0.2), 8 if good else 3, 0.02, 3.0)   # sparks
		Mode.CARVE:
			Audio.play_3d("chop", at, -4.0, randf_range(1.1, 1.3) if good else 0.9)
			Effects.chips(self, at, Color(0.72, 0.55, 0.36), 7 if good else 3, 0.03, 2.0)   # shavings
		Mode.KNAP:
			Audio.play("clink", -6.0, randf_range(1.3, 1.5) if good else 1.0)
			Effects.chips(player.camera, at, Color(0.55, 0.56, 0.6), 6 if good else 2, 0.015, 1.2)   # flakes


## The spit's turn (the food on it rolls over the fire).
func _set_turn(a: float) -> void:
	_turn = a
	if is_instance_valid(_work) and not _done:
		_place_piece()   # the spit rolls the food over, or the spoon goes round the pot


## Smithing: hot enough, so the head goes to the anvil.
func _to_anvil() -> void:
	phase = 1
	cue_t = 0.0
	_busy = true
	_place_piece()
	_setup_striker()
	_glide(_view(), func() -> void: _busy = false)


# --- Finishing ------------------------------------------------------------------------------

func _finish_item() -> void:
	_busy = true
	progress = 1.0
	Net.request("craft", {"recipe": recipe.id, "pos": player.global_position, "times": 1}, func(res: Dictionary) -> void:
		if _closing:
			return
		if not res.get("ok", false):
			player.hint.emit(String(res.get("reason", "Couldn't finish it")))
			stop()
			return
		made += 1
		left -= 1
		_show_done()
		var more := left > 0 and CraftSession.problem(player, recipe) == ""
		get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
			if _closing:
				return
			if more:
				_next()
			else:
				stop()))


## The finished thing pops up where the work was.
func _show_done() -> void:
	feedback = {"text": "Made %s" % ItemDB.display_name(recipe.out), "color": Color(1.0, 0.95, 0.8), "age": 0.0}
	Audio.play(Audio.sfx.pickup, -4.0)
	if not is_instance_valid(_work):
		return
	_done = true
	_work.mesh = ItemModels.mesh_for(String(recipe.out), _mat)
	if mode == Mode.COOK and recipe.out == "stew":   # a bowl of it, lifted out of the pot
		_work.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 1.6), _station.pos + Vector3(0, 0.8, 0) + _side * 0.25)
	else:
		_place_piece()
	if _glow:
		_glow.visible = false
	var tw := create_tween()
	var up := _work.position + (Vector3(0, 0.06, 0) if mode == Mode.KNAP else Vector3(0, 0.12, 0))
	tw.tween_property(_work, "position", up, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The next one of a batch.
func _next() -> void:
	progress = 0.0
	cue_t = 0.0
	feedback = {}
	_done = false
	if mode == Mode.SMITH and phase == 1:
		phase = 0
		_setup_piece()
		_glide(_view(), func() -> void: _busy = false)
		return
	_setup_piece()
	_busy = false


func _on_hurt(_amount: float) -> void:
	stop()


func _on_died() -> void:
	stop(true)


## Leave the station: the view glides back to your eyes and you're free to move. `at_once` skips the glide (dying,
## or leaving the world, when the camera is about to be taken over anyway).
func stop(at_once := false) -> void:
	if _closing:
		return
	_closing = true
	if player.stats.damaged.is_connected(_on_hurt):
		player.stats.damaged.disconnect(_on_hurt)
	if player.stats.died.is_connected(_on_died):
		player.stats.died.disconnect(_on_died)
	_layer.visible = false
	var finish := func() -> void:
		if player.active:
			player.camera.current = true
		player.crafting = null
		player.viewmodel.visible = true
		if is_instance_valid(_work):
			_work.queue_free()
		if is_instance_valid(_striker_pivot):
			_striker_pivot.queue_free()
		ended.emit()
		queue_free()
	if _cam and not at_once:
		_glide(player.camera.global_transform, finish)
	else:
		finish.call()
