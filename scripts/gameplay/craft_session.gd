class_name CraftSession
extends Node3D
## A crafting minigame at a station, in steps. The view goes to the station (or, by hand, stays with you) and the
## piece is there while you work, changing as you go: a stone is knapped into a head, a handle is hewn from a rough
## block, the head is seated and lashed, a glowing bar is hammered into shape and quenched, ore is loaded, melted and
## poured, meat browns on the spit, a stew darkens as it's stirred.
## Each step is one short mechanic: a ring closing on the strike point, a marker sweeping past a mark, a part swaying
## over its place, a dial coming round, the bellows' heat, circling the mouse to wind a binding, or pouring to a line.
## Doing well only makes it faster. Nothing moves unless you act, and nothing is used up until an item is done
## (finishing sends the ordinary craft request, so the host checks it as before). Shift-crafted batches run back
## to back. Esc, right click or a movement key stops; so do getting hurt, dying and leaving the world.

signal ended

enum Mode { COOK, SMELT, SMITH, CARVE, KNAP }
## Every step is a movement of the mouse (a hand on the screen, see ptr):
##   FLICK  aim at the glowing spot and flick down (knapping, hammering, driving a wedge, knocking an ingot out)
##   DRAG   press on a piece and drag it into place (fitting a head, seating, hafting, loading ore, adding food)
##   SAW    steady side-to-side strokes (shaping a handle)
##   PUMP   up-and-down strokes (the bellows)
##   TILT   move sideways to tip the crucible, back to stop pouring
##   STIR   circle at a steady pace (stirring the pot, turning the spit)
##   WRAP   circle to wind a binding on
##   DIP    drag the hot blade into the water and hold it there
enum Mech { FLICK, DRAG, SAW, PUMP, TILT, STIR, WRAP, DIP }

const TOOL_TYPES := ["hatchet", "pickaxe", "spear", "knife"]
const INGOTS := ["ingot_t2", "ingot_t3", "dusk_ingot"]

## Timing: a strike's grade by how well it was timed, and what each grade is worth (of one action's share).
const PERFECT_Q := 0.7
const GOOD_Q := 0.25
const FLICK_LEN := 55.0      ## pixels of quick downward movement that make a strike
const FLICK_WINDOW := 0.16   ## ...within this long
const FLICK_AIM := 55.0      ## how far off the spot (pixels) a strike still lands
const SNAP := 46.0           ## a dragged piece lets go into place within this many pixels of its spot
const SAW_STROKE := 70.0     ## pixels of a stroke that counts
const SAW_STROKES := 8.0
const STIR_PACE := Vector2(2.2, 10.0)   ## radians a second: slower does little, faster slops about
const STIR_TURNS := 4.0
const DIP_HOLD := 1.1
const GRAB := 80.0           ## press within this many pixels of a piece to pick it up
const PUMP_STROKE := 40.0    ## pixels of a bellows stroke that counts
const PUMP_HEAT := 0.075     ## each stroke stokes the fire this much...
const HEAT_FADE := 0.16      ## ...and it dies back this much a second
const MISS_SHARE := 0.15
const MISS_LOCK := 0.5      ## a fumble: a moment before you can strike again (so mashing is slow)
const HIT_LOCK := 0.22
## The forge: hold to pump the bellows. It only works while hot enough, fastest in the band.
const HEAT_BAND := Vector2(0.6, 0.85)
const HEAT_WARM := 0.4
## Winding a binding: circles of the mouse, at least this far from the middle (pixels).
const WRAP_RADIUS := 40.0
const WRAP_TURNS := 3.0     ## full circles to wind a whole binding
## Pouring: hold to pour, let go with the mould filled to the band; over the top spills.
const POUR_RATE := 0.4
const POUR_BAND := Vector2(0.8, 0.95)
## Where things sit at the forge (station-local): the crucible on the coals at the mouth, the bucket by the anvil.
const CRUCIBLE_AT := Vector3(0.0, 0.82, -0.05)
const MOULD_AT := Vector3(0.95, 0.65, -0.2)
## A crucible's outline, spun round its axis (MeshKit.lathe): out across the base, up the outside, over the rolled
## rim, down the inside and in across its floor. The inside is a real hollow.
const CRUCIBLE_PROFILE := [Vector2(0.0, 0.0), Vector2(0.05, 0.0), Vector2(0.058, 0.006), Vector2(0.072, 0.05), Vector2(0.083, 0.11),
	Vector2(0.09, 0.128), Vector2(0.087, 0.138), Vector2(0.079, 0.139), Vector2(0.073, 0.13), Vector2(0.064, 0.08),
	Vector2(0.05, 0.034), Vector2(0.041, 0.022), Vector2(0.0, 0.02)]
const CRUCIBLE_LIP := Vector3(0.0, 0.138, 0.088)   ## where it pours from (the lip that dips when it tips)
## A cooking pot's outline, the same way: an iron belly, a lip, the inside down to its floor.
const POT_PROFILE := [Vector2(0.0, 0.0), Vector2(0.1, 0.0), Vector2(0.13, 0.03), Vector2(0.152, 0.09), Vector2(0.15, 0.15),
	Vector2(0.16, 0.168), Vector2(0.155, 0.176), Vector2(0.142, 0.17), Vector2(0.14, 0.15), Vector2(0.142, 0.09),
	Vector2(0.12, 0.034), Vector2(0.09, 0.012), Vector2(0.0, 0.012)]
const POT_BASE := 0.575   ## the pot's foot above the campfire's ground
## A water bucket: staved wood, its inside down to the floor (the water is a disc inside it).
const BUCKET_PROFILE := [Vector2(0.0, 0.0), Vector2(0.14, 0.0), Vector2(0.162, 0.3), Vector2(0.152, 0.306), Vector2(0.142, 0.296),
	Vector2(0.124, 0.02), Vector2(0.0, 0.02)]
const BUCKET_AT := Vector3(0.55, 0.0, -0.75)

var player: Node
var recipe: Dictionary
var mode: int = Mode.CARVE
var left := 1
var made := 0
var steps: Array = []      ## [{mech, id, n, say, view, dur}]
var step := 0              ## index into steps
var step_t := 0.0          ## progress through the current step, 0..1
var progress := 0.0        ## through the whole item, 0..1 (the bar)
var heat := 0.15
var fill := 0.0            ## pouring: how full the mould is
var wrap_vec := Vector2(0, -60)   ## winding: where the mouse is round the middle
var feedback := {}         ## {"text", "color", "age"}: the last action's grade, shown briefly
var ptr := Vector2.ZERO    ## the hand on the screen (pixels), moved by the mouse
var pressed := false       ## the action button is down
var tilt := 0.0            ## pouring: how far the crucible is tipped (0..1)
var turn_rate := 0.0       ## stirring / turning: radians a second, eased
var hold_t := 0.0          ## dipping: how long it's been held in the water
var pouring := false
var drag_node: Node3D            ## dragging: the piece being moved
var dragging := false
var _drag_from := Transform3D()      ## where it's picked up from (global)
var _drag_home_xf := Transform3D()   ## where it goes (global)
var _drag_focus := Vector3.ZERO      ## the point on it that has to reach its place (its own space)
var _drag_depth := 1.0
var _grab := Vector3.ZERO
var _snapping := false
var _in_water := false
var _dips := 0
var _spot_local := Vector3.ZERO      ## striking: the glowing spot, on the piece
var _impact := 0.0                   ## a blow landing (seconds left of it)
var _impact_at := Vector3.ZERO
var _hist: Array = []                ## the hand's recent positions (x, y, time), to catch a flick
var _anchor := Vector2.ZERO          ## the middle of a step's movement on the screen
var _counted := false
var _striker_side := Vector3.RIGHT
var _was_pouring := false
var _spills := 0
var _sound_acc := 0.0
var _nag_t := 0.0
var _stroke := 0.0
var _stroke_dir := 0
var _stroke_drift := 0.0
var strokes := 0
var _pump_dir := 0
var _pump_len := 0.0
var _stir_acc := 0.0
var _sample_t := 0.0
var _q_sum := 0.0
var _q_n := 0
var _auto_side := 1.0

var _station := {}         ## {"kind", "pos", "yaw"} of the station being used
var _xf := Transform3D()   ## the station's frame
var _cam: Camera3D
var _view_key := ""
var _piece: MeshInstance3D     ## the thing being made
var _part: MeshInstance3D      ## a part being fitted to it (a handle sliding in, a head being seated)
var _glow: MeshInstance3D
var _striker_pivot: Node3D
var _striker_rest := Basis()
var _props: Node3D
var _crossbar: MeshInstance3D  ## campfire spit
var _pot_surface: MeshInstance3D
var _crucible: Node3D
var _lumps: Array[MeshInstance3D] = []
var _pool: MeshInstance3D      ## molten metal in the crucible
var _stream: MeshInstance3D    ## the pour
var _mould_fill: MeshInstance3D
var _ingot: MeshInstance3D
var _dropper: MeshInstance3D   ## the scoop of ore / the ingredient swaying over its place
var _layer: CanvasLayer
var _overlay: Control
var _lock := 0.0
var _busy := true          ## gliding, or between steps, or waiting on the finished item
var _closing := false
var _done := false         ## the finished item is showing
var _side := Vector3.BACK  ## campfire: which side you're watching from
var _turn := 0.0           ## campfire: the spit's turn
var _char := 0.0           ## campfire: how much the food caught when a turn was missed (cosmetic)
var _drops := 0            ## things dropped in this step
var _tint_mat: ShaderMaterial
var _molten_mat: StandardMaterial3D
var _last_stage := ""
var _spoon_mesh: ArrayMesh
var _fx: Node3D                ## the station's running eye candy (bubbles, steam, sawdust in the air, heat haze)
var _shimmer: MeshInstance3D   ## heat haze over hot metal
var _bubbles: CPUParticles3D
var _steam: CPUParticles3D
var _focus := 0.0              ## the camera's focus distance (eased)
var _dof: DofBlur
const COALS := Vector3(0.0, 0.98, -0.05)   ## the forge's fire bed, in its own frame

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


# --- The steps of each craft ---------------------------------------------------------------

func _plan() -> Array:
	var tool_type := String(ItemDB.info(recipe.out).get("tool", {}).get("type", ""))
	var knife := tool_type == "knife"
	var spear := tool_type == "spear"
	match mode:
		Mode.KNAP:
			var plan := [{"mech": Mech.FLICK, "id": "knap", "n": 5, "view": "hand", "say": "Aim at the glowing spot and flick the mouse down, to knap flakes off"}]
			if knife:
				plan.append({"mech": Mech.WRAP, "id": "grip", "view": "hand", "say": "Circle the mouse to wind the cord grip on"})
			else:
				plan.append({"mech": Mech.DRAG, "id": "fit", "n": 1, "view": "hand", "say": "Hold {key} on the shaft and drag it up into the head"})
				if spear:
					plan.append({"mech": Mech.WRAP, "id": "socket", "view": "hand", "say": "Circle the mouse to bind the socket on"})
				else:
					plan.append({"mech": Mech.FLICK, "id": "wedge", "n": 2, "view": "hand", "say": "Flick down on the glowing spot, to drive the wedge home"})
			return plan
		Mode.CARVE:
			var plan := [{"mech": Mech.SAW, "id": "shape", "view": "bench", "say": "Long, steady strokes side to side, to shape the handle"},
				{"mech": Mech.DRAG, "id": "seat", "n": 1, "view": "bench", "say": "Hold {key} on the head and drag it down onto the handle"}]
			if spear:
				plan.append({"mech": Mech.WRAP, "id": "socket", "view": "bench", "say": "Circle the mouse to bind the socket on"})
			if not spear:   # a spear's socket holds it; axes and picks get a wedge, knives a guard
				plan.append({"mech": Mech.FLICK, "id": "wedge", "n": 2, "view": "bench", "say": "Flick down on the glowing spot, to drive the wedge home" if not knife else "Flick down on the glowing spot, to fit the guard"})
			return plan
		Mode.SMITH:
			return [{"mech": Mech.PUMP, "id": "heat", "dur": 2.5, "view": "mouth", "say": "Pump the bellows: move the mouse up and down"},
				{"mech": Mech.FLICK, "id": "hammer", "n": 5, "view": "anvil", "say": "Aim at the glowing spot and flick down, to hammer it out"},
				{"mech": Mech.DIP, "id": "quench", "n": 1, "view": "quench", "say": "Hold {key} on the blade: drag it into the water and keep it under"},
				{"mech": Mech.DRAG, "id": "haft", "n": 1, "view": "anvil", "say": "Hold {key} on the handle and drag it up into the head"}]
		Mode.SMELT:
			return [{"mech": Mech.DRAG, "id": "load", "n": 3, "view": "mouth", "say": "Hold {key} on the ore and drag it into the crucible"},
				{"mech": Mech.PUMP, "id": "melt", "dur": 3.0, "view": "mouth", "say": "Pump the bellows: move the mouse up and down"},
				{"mech": Mech.TILT, "id": "pour", "view": "anvil", "say": "Move right to tip the crucible; back left at the line"},
				{"mech": Mech.FLICK, "id": "tap", "n": 2, "view": "anvil", "say": "Flick down on the mould, to knock the ingot out"}]
		_:
			if recipe.out == "stew":
				return [{"mech": Mech.DRAG, "id": "add", "n": 3, "view": "fire", "say": "Hold {key} on each thing and drag it into the pot"},
					{"mech": Mech.STIR, "id": "stir", "view": "fire", "say": "Stir: circle the mouse, not too fast"}]
			return [{"mech": Mech.DRAG, "id": "skewer", "n": 1, "view": "fire", "say": "Hold {key} on the spit and push it through the food"},
				{"mech": Mech.STIR, "id": "cook", "view": "fire", "say": "Turn the spit: circle the mouse, steady"}]


func cur() -> Dictionary:
	return steps[mini(step, steps.size() - 1)] if not steps.is_empty() else {}


func mech() -> int:
	return int(cur().get("mech", Mech.FLICK))


func step_id() -> String:
	return String(cur().get("id", ""))


# --- Starting -------------------------------------------------------------------------------

func begin(p: Node, r: Dictionary, times: int) -> void:
	player = p
	recipe = r
	mode = mode_for(r)
	left = maxi(times, 1)
	if not _mat:
		_mat = ArtStyle.painted({"brush_strength": 0.16, "rim_amount": 0.3, "stroke_scale": 3.0, "edge_pool": 0.1})
	_tint_mat = _mat.duplicate() as ShaderMaterial
	_molten_mat = StandardMaterial3D.new()
	_molten_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_molten_mat.albedo_color = Color(1.0, 0.55, 0.15)
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
	# The minigame's own camera (knapping too: it looks down at the stone in your hands), made first so the pieces
	# held in front of it can hang from it.
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.global_transform = player.camera.global_transform
	_cam.fov = player.camera.fov
	_cam.current = true
	_cam.set_meta("own_focus", true)   # (CameraFx leaves this one's depth of field to us)
	_dof = DofBlur.attach(_cam)
	_build_props()
	_build_fx()
	_start_item()
	_go_to_view(_step_ready)


## A fresh item: the first step, the raw piece.
func _start_item() -> void:
	steps = _plan()
	step = 0
	_reset_step_state()
	progress = 0.0
	_q_sum = 0.0
	_q_n = 0
	_char = 0.0
	_done = false
	_last_stage = ""
	feedback = {}
	if mode in [Mode.SMITH, Mode.SMELT]:
		heat = maxf(heat, 0.15)
	_tint_mat.set_shader_parameter("tint_color", Color.WHITE)
	_reset_props()
	_refresh()
	_setup_striker()
	_drag_setup()


# --- Views ----------------------------------------------------------------------------------

## Field of view at a station: narrower than walking about, so the work fills a medium shot (the station stays in
## view around it) without the camera crowding in.
const STATION_FOV := 50.0
## Knapping by hand: the view drops a little and tips down to the stone held low in front of you.
const HAND_DROP := 0.12
const HAND_PITCH := -0.62


## Where the camera looks from and at for a view, as a global transform. Each one is aimed at the middle of the work.
func _view(key: String) -> Transform3D:
	var from := Vector3.ZERO
	var at := Vector3.ZERO
	match key:
		"hand":
			var pc: Transform3D = player.camera.global_transform
			var fwd := -pc.basis.z
			var yaw := atan2(-fwd.x, -fwd.z)
			return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, HAND_PITCH), pc.origin - Vector3(0, HAND_DROP, 0))
		"fire":   # the spit and the fire under it
			var c: Vector3 = _station.pos
			return _look(c + _side * 1.6 + Vector3(0, 1.32, 0), c + Vector3(0, 0.8, 0))
		"mouth":   # over the hearth's fire, from the front
			from = Vector3(0.28, 1.7, -1.35)
			at = Vector3(0.0, 0.86, -0.05)
		"quench":   # stepped back: the anvil and the bucket beside it
			from = Vector3(1.55, 1.5, -1.3)
			at = Vector3(0.76, 0.42, -0.42)
		"anvil":   # the anvil's face, with the stump and the hearth's corner around it
			from = Vector3(1.32, 1.4, -1.14)
			at = Vector3(0.88, 0.68, -0.23)
		"bench":   # the piece on the bench top, the bench around it
			var s := _bench_side()
			from = Vector3(0.06, 1.62, s * 1.08)
			at = Vector3(0.06, 0.87, s * 0.07)
	return _look(_xf * from, _xf * at)


func _view_fov(key: String) -> float:
	return player.camera.fov if key == "hand" else STATION_FOV


## What hand-held pieces hang from: the minigame's camera (or the player's, before it exists).
func _holder() -> Node3D:
	return _cam if _cam else player.camera


static func _look(from: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


## Which long side of the workbench you're standing at (+1 or -1 along its local z).
func _bench_side() -> float:
	var local: Vector3 = _xf.affine_inverse() * player.global_position
	return 1.0 if local.z >= 0.0 else -1.0


## Glide to the current step's view (if it's a different one), then carry on.
func _go_to_view(then: Callable) -> void:
	var key := String(cur().get("view", ""))
	if _cam == null or key == _view_key:
		_view_key = key
		then.call()
		return
	_view_key = key
	_glide(_view(key), then, _view_fov(key))


func _glide(to: Transform3D, then: Callable, fov := -1.0) -> void:
	var from := _cam.global_transform
	var fov_from := _cam.fov
	var fov_to := fov if fov > 0.0 else fov_from
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void:
		_cam.global_transform = from.interpolate_with(to, w)
		_cam.fov = lerpf(fov_from, fov_to, w), 0.0, 1.0, 0.55) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_callback(then)


# --- Props: what the station needs for this job --------------------------------------------

func _build_props() -> void:
	_props = Node3D.new()
	add_child(_props)
	match mode:
		Mode.COOK: _build_spit()
		Mode.SMELT: _build_foundry()
		Mode.SMITH: _build_bucket()


## The running effects for this station's work: a pot on the boil, a smoking spit, heat haze over hot metal,
## sawdust hanging over the bench.
func _build_fx() -> void:
	_fx = Node3D.new()
	add_child(_fx)
	match mode:
		Mode.COOK:
			if recipe.out == "stew" and _pot_surface:
				_bubbles = Effects.bubbles(_inner_radius(POT_PROFILE, 0.13) * 0.7, Color(0.55, 0.42, 0.3))
				_fx.add_child(_bubbles)
				_steam = Effects.smoke(0.3, Color(0.92, 0.93, 0.96))
				_fx.add_child(_steam)
			else:
				_steam = Effects.smoke(0.25, Color(0.5, 0.48, 0.46))   # fat smoking off the meat
				_fx.add_child(_steam)
		Mode.SMELT, Mode.SMITH:
			_shimmer = Effects.shimmer(Vector2(0.35, 0.55))
			_fx.add_child(_shimmer)
		Mode.CARVE:
			var dust := Effects.motes(Vector3(0.5, 0.25, 0.35), Color(0.9, 0.78, 0.55), 26)
			_fx.add_child(dust)
			dust.global_position = _xf * Vector3(0.06, 1.05, _bench_side() * 0.07)
		Mode.KNAP:
			var grit := Effects.motes(Vector3(0.3, 0.2, 0.3), Color(0.8, 0.8, 0.82), 12)
			_holder().add_child(grit)
			grit.position = Vector3(0, -0.1, -0.5)


## Each frame: keep the running effects with the work, and the camera focused on it.
func _update_fx(delta: float) -> void:
	if _bubbles and _pot_surface:
		_bubbles.global_position = _pot_surface.global_position + Vector3(0, 0.008, 0)
		_bubbles.emitting = not _done
	if _steam:
		_steam.global_position = _pot_surface.global_position + Vector3(0, 0.02, 0) if _pot_surface else work_point()
		_steam.emitting = not _done
	if _shimmer:
		var hot := 0.0
		if mode == Mode.SMITH and is_instance_valid(_piece):
			_shimmer.global_position = work_point() + Vector3(0, 0.03, 0)
			if step_id() in ["heat", "hammer", "quench"] and not (step_id() == "quench" and step_t >= 1.0):
				hot = smoothstep(0.35, 0.9, heat)
		elif mode == Mode.SMELT and _crucible:
			_shimmer.global_position = _crucible.global_position + Vector3(0, 0.12, 0)
			hot = smoothstep(0.3, 0.85, heat) if step_id() != "load" else 0.3
		Effects.set_shimmer(_shimmer, hot if not _done else 0.0)
	# Depth of field: sharp on the work, the station's surroundings going soft behind it.
	if _dof:
		var d := _cam.global_position.distance_to(work_point())
		_focus = d if _focus <= 0.0 else lerpf(_focus, d, 1.0 - exp(-6.0 * delta))
		_dof.set_blur(_focus + 0.3, 1.6, 0.6 if Settings.depth_of_field else 0.0)


## A perfect strike: the bits fly in slow motion, a flash, and the view punches in a touch.
func _perfect_fx(show: Callable) -> void:
	var at := work_point()
	Effects.slow_motion(0.5, show)
	Effects.twinkle(self, at + Vector3(0, 0.04, 0), Color(0.85, 1.0, 0.65), 6, 0.3)
	var hot := mode in [Mode.SMITH, Mode.SMELT]
	Effects.flash(self, at + Vector3(0, 0.15, 0), Color(1.0, 0.6, 0.3) if hot else Color(1.0, 0.95, 0.8), 1.6 if hot else 0.8, 2.0, 0.3)
	_punch(2.5)


## Zoom in a little and back (a perfect strike, a finished piece).
func _punch(degrees: float) -> void:
	if _cam == null or not Settings.camera_shake:
		return
	var base := _view_fov(_view_key) if _view_key != "" else _cam.fov
	var tw := create_tween()
	tw.tween_property(_cam, "fov", base - degrees, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(_cam, "fov", base, 0.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _mesh_node(mesh: Mesh, parent: Node3D, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mat:
		mi.material_override = mat
	parent.add_child(mi)
	return mi


## Over the campfire: two forked uprights and a crossbar spit (or a pot hung from it, for stew).
func _build_spit() -> void:
	var to_player: Vector3 = player.global_position - _station.pos
	to_player.y = 0.0
	_side = to_player.normalized() if to_player.length() > 0.1 else Vector3.BACK
	var along := _side.cross(Vector3.UP).normalized()   # the spit runs across your view
	var k := MeshKit.new(5)
	var bark := Color(0.42, 0.3, 0.2)
	for s in [-1.0, 1.0]:
		var foot: Vector3 = along * 0.52 * s
		k.loft([foot, foot + Vector3(0, 0.92, 0)], [0.024, 0.02], 7, bark, Callable(), Callable(), true, true, 0.004)
		for f in [-1.0, 1.0]:
			k.loft([foot + Vector3(0, 0.84, 0), foot + Vector3(0, 0.97, 0) + _side * 0.05 * f], [0.014, 0.01], 5, bark, Callable(), Callable(), true, true)
	if recipe.out == "stew":   # a pot hung from the crossbar on a cord
		k.loft([along * -0.62 + Vector3(0, 0.88, 0), along * 0.62 + Vector3(0, 0.88, 0)], [0.013, 0.013], 7, bark.lightened(0.1), Callable(), Callable(), true, true)
		k.loft([Vector3(0, 0.88, 0), Vector3(0, 0.83, 0)], [0.006, 0.006], 5, Color(0.6, 0.5, 0.35))
		# A hollow iron pot (open at the top, its inside down to a floor), hung by a wire bail from the cord.
		var iron := Color(0.2, 0.19, 0.2)
		k.lathe(POT_PROFILE, 18, iron, func(t: float, _a: float) -> Color: return iron.darkened(0.25) if t > 0.62 else iron, Transform3D(Basis(), Vector3(0, POT_BASE, 0)))
		var bail: Array = []
		for i in 9:
			var a := PI * i / 8.0
			bail.append(along * cos(a) * 0.162 + Vector3(0, POT_BASE + 0.16 + sin(a) * 0.08, 0))
		k.loft(bail, bail.map(func(_p: Vector3) -> float: return 0.005), 5, Color(0.3, 0.3, 0.32))
		var surf := StandardMaterial3D.new()
		surf.albedo_color = Color(0.4, 0.5, 0.58)
		surf.roughness = 0.4
		# The stew: a disc inside the pot, as wide as the pot is there (it rises as things go in).
		var fill_y := POT_BASE + 0.13
		var r := _inner_radius(POT_PROFILE, 0.13) - 0.003
		_pot_surface = _mesh_node(MeshKit.cylinder(r, r, 0.012, 18), _props, surf)
		_pot_surface.position = _station.pos + Vector3(0, fill_y, 0)
	else:
		var kb := MeshKit.new(6)   # the crossbar on its own: it's pushed through the food to skewer it
		kb.loft([along * -0.62, along * 0.62], [0.013, 0.013], 7, bark.lightened(0.1), Callable(), Callable(), true, true)
		_crossbar = _mesh_node(kb.commit(_mat), _props)
	_mesh_node(k.commit(_mat), _props).position = _station.pos


const LUMP_SCALE := 0.44   ## the ore lumps in the crucible (its inside is about 0.1 across where they lie)


## A lump of ore in the crucible at its resting place (its meta "rest": turn and where its middle goes), at `scl`: it
## shrinks about its own middle as it melts.
func _place_lump(lump: MeshInstance3D, scl: float) -> void:
	var rest: Transform3D = lump.get_meta("rest")
	var c := lump.mesh.get_aabb().get_center() if lump.mesh else Vector3.ZERO
	var b := rest.basis.scaled_local(Vector3.ONE * scl)
	lump.transform = Transform3D(b, rest.origin - b * c)


## At the forge: a clay crucible in the coals, an iron mould on the anvil, the molten metal and its pour.
func _build_foundry() -> void:
	var k := MeshKit.new(7)
	var clay := Color(0.55, 0.36, 0.26)
	# A real hollow crucible: sooty clay outside, a rolled rim, a charred inside down to its floor.
	k.lathe(CRUCIBLE_PROFILE, 16, clay, func(t: float, _a: float) -> Color:
		if t > 0.6:
			return Color(0.16, 0.11, 0.08)   # inside: charred
		return clay.darkened(0.35 * (1.0 - clampf(t / 0.45, 0.0, 1.0))))
	_crucible = Node3D.new()
	_props.add_child(_crucible)
	_mesh_node(k.commit(_mat), _crucible)
	# The melt: a disc sized each frame to the inside of the crucible where it stands.
	_pool = _mesh_node(MeshKit.cylinder(1.0, 1.0, 0.01, 16), _crucible, _molten_mat)
	var ore := ""
	for item: String in recipe.needs:
		if item != "wood" and item != "charcoal":   # the fuel isn't what goes in the crucible
			ore = item
			break
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Three lumps settled in the bottom of the crucible round its middle, the last on top of the other two. Placed by
	# the middle of their shape (an ore's model isn't centred on its origin), small enough to sit inside its walls.
	var spots := [Vector3(0.016, 0.05, 0.009), Vector3(-0.016, 0.052, 0.009), Vector3(0.0, 0.074, -0.012)]
	for i in 3:
		var lump := _mesh_node(ItemModels.mesh_for(ore, _mat), _crucible)
		lump.set_meta("rest", Transform3D(Basis.from_euler(Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)), spots[i]))
		_place_lump(lump, LUMP_SCALE)
		_lumps.append(lump)
	var mk := MeshKit.new(8)   # the mould: an iron block with an ingot-shaped hollow
	var iron := Color(0.24, 0.23, 0.25)
	# A base and four walls standing on it, the walls sunk a little into the base and the end walls a little
	# into the side walls, so no two faces lie on each other (they'd flicker).
	for b: Array in [[Vector3(0.256, 0.03, 0.136), Vector3(0, 0.015, 0)],
			[Vector3(0.262, 0.034, 0.03), Vector3(0, 0.043, 0.055)], [Vector3(0.262, 0.034, 0.03), Vector3(0, 0.043, -0.055)],
			[Vector3(0.03, 0.034, 0.084), Vector3(0.115, 0.043, 0)], [Vector3(0.03, 0.034, 0.084), Vector3(-0.115, 0.043, 0)]]:
		var box := BoxMesh.new()
		box.size = b[0]
		mk.add_primitive(box, Transform3D(Basis(), b[1]), iron, 0.0, 0.03)
	var mould := _mesh_node(mk.commit(_mat), _props)
	mould.global_transform = _xf * Transform3D(Basis(Vector3.UP, 0.3), MOULD_AT)
	# The metal in the mould fills its hollow from the floor up, a hair inside its walls.
	var fill_box := BoxMesh.new()
	fill_box.size = Vector3(0.196, 1.0, 0.076)
	_mould_fill = _mesh_node(fill_box, mould, _molten_mat)
	_set_mould_fill(0.0)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.012
	cyl.height = 1.0
	_stream = _mesh_node(cyl, _props, _molten_mat)
	_ingot = _mesh_node(ItemModels.mesh_for(String(recipe.out), _tint_mat), _props)
	_dropper = _mesh_node(ItemModels.mesh_for(ore, _mat), _props)


## Beside the anvil: a bucket of water to quench in.
func _build_bucket() -> void:
	var k := MeshKit.new(9)
	var wood := Color(0.45, 0.32, 0.2)
	# A hollow staved bucket (darker staves every other one), and iron hoops just proud of its sides.
	k.lathe(BUCKET_PROFILE, 16, wood, func(t: float, a: float) -> Color:
		return wood.darkened(0.2) if t > 0.6 else (wood.lightened(0.05) if int(floor(a / TAU * 16.0)) % 2 == 0 else wood))
	for y in [0.06, 0.24]:
		var r0: float = 0.14 + 0.022 * y / 0.3 + 0.002
		var hoop := [Vector2(r0, y - 0.0125), Vector2(r0 + 0.008, y - 0.0125), Vector2(r0 + 0.008, y + 0.0125), Vector2(r0, y + 0.0125), Vector2(r0, y - 0.0125)]
		k.lathe(hoop, 16, Color(0.3, 0.3, 0.32))
	# The water: a disc inside, as wide as the bucket is there.
	var wr := _inner_radius(BUCKET_PROFILE, 0.26) - 0.003
	k.add_primitive(MeshKit.cylinder(wr, wr, 0.008, 16), Transform3D(Basis(), Vector3(0, 0.26, 0)), Color(0.25, 0.4, 0.5), 0.0, 0.0)
	var bucket := _mesh_node(k.commit(_mat), _props)
	bucket.global_position = _xf * BUCKET_AT


## Back to the start of an item: the ore in the crucible, the mould empty, the spit out of the food.
func _reset_props() -> void:
	if _crucible:
		_crucible.global_transform = _xf * Transform3D(Basis(), CRUCIBLE_AT)
		for l in _lumps:
			l.visible = false
			_place_lump(l, LUMP_SCALE)
		_pool.visible = false
		_stream.visible = false
		_mould_fill.visible = false
		_ingot.visible = false
		_dropper.visible = false
	if _pot_surface:
		(_pot_surface.material_override as StandardMaterial3D).albedo_color = Color(0.4, 0.5, 0.58)


# --- The piece, as it changes ---------------------------------------------------------------

## The tool at a stage (see ItemModels.tool_stage), rounded so it's rebuilt a few times a step, not every frame.
func _tool(st: Dictionary) -> ArrayMesh:
	var q := {}
	for k: String in st:
		q[k] = snappedf(float(st[k]), 0.125) if float(st[k]) >= 0.0 else -1.0
	return ItemModels.tool_stage(String(recipe.out), q, _tint_mat)


## Show the piece for where we are: the right model at the right stage, in the right place.
func _refresh() -> void:
	if not _piece:
		_piece = MeshInstance3D.new()
		_piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_piece.material_override = null
		if mode == Mode.KNAP:
			_holder().add_child(_piece)
		else:
			add_child(_piece)
	if not _part:
		_part = MeshInstance3D.new()
		_part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mode == Mode.KNAP:
			_holder().add_child(_part)
		else:
			add_child(_part)
	_part.visible = false
	if _done:
		return
	var id := step_id()
	var s := step_t
	match mode:
		Mode.KNAP, Mode.CARVE, Mode.SMITH:
			_refresh_tool(id, s)
		Mode.SMELT:
			_refresh_smelt(id, s)
		Mode.COOK:
			_refresh_food(id, s)
	_update_glow()


func _refresh_tool(id: String, s: float) -> void:
	var where := _where()
	var knife := String(ItemDB.info(recipe.out).get("tool", {}).get("type", "")) == "knife"
	var stage := {}
	var part_stage := {}
	match id:
		"knap":
			stage = {"head": s, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"fit":
			stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": -1.0, "handle": 1.0, "lash": 0.0, "wedge": 0.0}
		"grip":
			stage = {"head": 1.0, "handle": 1.0, "lash": s, "wedge": 1.0}
		"socket":
			stage = {"head": 1.0, "handle": 1.0, "lash": s, "wedge": 1.0}
		"shape":
			stage = {"head": -1.0, "handle": s, "lash": 0.0, "wedge": 0.0}
		"seat":
			stage = {"head": -1.0, "handle": 1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"wedge":
			stage = {"head": 1.0, "handle": 1.0, "lash": 1.0, "wedge": s if s > 0.0 else 0.01}
		"heat":
			stage = {"head": 0.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"hammer", "quench":
			stage = {"head": s if id == "hammer" else 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"haft":
			stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": -1.0, "handle": 1.0, "lash": 1.0 if not knife else 0.0, "wedge": 1.0 if not knife else 0.0}
	var key := "%s|%s|%s|%s" % [id, str(stage), str(part_stage), where]
	if key != _last_stage:
		_last_stage = key
		_piece.mesh = _tool(stage)
		if not (dragging or _snapping) or drag_node != _piece:
			_piece.transform = _tool_place(where)
		if not part_stage.is_empty():
			_part.mesh = _tool(part_stage)   # (it's put in place by the dragging)
	_part.visible = not part_stage.is_empty()


## Where a tool lies for each place: in your hand (in front of the camera), on the bench, in the coals, on the anvil.
func _tool_place(where: String) -> Transform3D:
	var head := _head_y()
	match where:
		"hand":
			var sc := 2.0 if step_id() == "knap" else 0.7
			# Turned a quarter so the head's broad face is toward you (not its edge), leaning a little to the left.
			var b := (Basis(Vector3.FORWARD, -0.35) * Basis(Vector3.RIGHT, 0.25) * Basis(Vector3.UP, PI * 0.5)).scaled(Vector3.ONE * sc)
			# The head sits in the middle of the view, close (the view looks down at your hands).
			return Transform3D(b, Vector3(0.0, -0.02, -0.36) - b * Vector3(0, head, 0))
		"bench":
			return _global_to_local(_xf * Transform3D(_lying(), Vector3(head - 0.12, 0.875, _bench_side() * 0.08)))
		"coals":
			# Lying on the coals, the head in the fire and the tang out to the right.
			var bc := Basis(Vector3.UP, 0.15)
			return _global_to_local(_xf * Transform3D(bc * _lying(), Vector3(0.0, 0.86, -0.05) + bc * Vector3(head, 0, 0)))
		_:   # anvil: lying flat, the head over the middle of the face
			var b := Basis(Vector3.UP, 0.3)
			return _global_to_local(_xf * Transform3D(b * _lying(), Vector3(0.95, 0.68, -0.2) + b * Vector3(head - 0.04, 0, 0)))


## This node sits at the world origin, so a global transform is also its children's local one.
func _global_to_local(xf: Transform3D) -> Transform3D:
	return global_transform.affine_inverse() * xf


## How far up the handle a tool's head is: most of the way to its top (from the finished model).
func _head_y() -> float:
	var full := ItemModels.mesh_for(String(recipe.out), _mat)
	return full.get_aabb().end.y * 0.82 if full else 0.34


## A tool lying flat: the handle along x, the head's face horizontal.
static func _lying() -> Basis:
	return Basis(Vector3.BACK, PI * 0.5)


func _refresh_smelt(id: String, s: float) -> void:
	_piece.mesh = null
	match id:
		"load":
			for i in _lumps.size():
				_lumps[i].visible = i < _drops
			_dropper.visible = true   # (it's moved by the dragging)
		"melt":
			_dropper.visible = false
			_pool.visible = s > 0.05
			_set_pool_level(0.02 + 0.08 * s)
			for l in _lumps:
				l.visible = s < 0.95
				_place_lump(l, LUMP_SCALE * (1.0 - s))
		"pour":
			for l in _lumps:
				l.visible = false
			_pool.visible = true
			# Held with its pouring lip over the mould, tipped by how hard you're pouring; the melt drains as the
			# mould fills.
			var tip := lerpf(0.2, 1.3, tilt)
			var axis := (_xf.basis * Vector3(1, 0, 0)).normalized()
			var b := Basis(axis, tip) * _xf.basis.orthonormalized()
			var mould := (_mould_fill.get_parent() as Node3D).global_transform
			var into := mould * Vector3(0, 0.031 + 0.029 * fill, 0)
			var lip_at := into + Vector3(0, 0.22, 0)
			_crucible.global_transform = Transform3D(b, lip_at - b * CRUCIBLE_LIP)
			# The melt lies level whatever the tilt, low in the crucible, small enough to stay inside it.
			_pool.visible = fill < 0.97
			var r := 0.045 * (1.0 - fill * 0.6)
			_pool.global_transform = Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), _crucible.global_transform * Vector3(0, 0.055, 0.0))
			_set_mould_fill(fill)
			_stream.visible = pouring
			if _stream.visible:
				# From the lip straight down into the mould.
				var lip: Vector3 = _crucible.global_transform * CRUCIBLE_LIP
				var dir := lip - into
				var y := dir.normalized()
				var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
				_stream.global_transform = Transform3D(Basis(x, y, x.cross(y)).scaled(Vector3(1, dir.length(), 1)), (lip + into) * 0.5)
		"tap":
			_stream.visible = false
			_crucible.global_transform = _xf * Transform3D(Basis(), CRUCIBLE_AT)
			_pool.visible = false
			_set_mould_fill(1.0)
			_mould_fill.visible = s < 0.99
			_ingot.visible = s > 0.0
			var m := (_mould_fill.get_parent() as Node3D).global_transform
			_ingot.global_transform = Transform3D(m.basis.scaled(Vector3.ONE * 1.3), m * Vector3(0, 0.05 + 0.08 * s, 0))
			_tint_mat.set_shader_parameter("tint_color", Color(1.0, 0.6, 0.35).lerp(Color.WHITE, s))


func _refresh_food(id: String, s: float) -> void:
	var stew: bool = recipe.out == "stew"
	if stew:
		var add_t := float(_drops) / 3.0 if id == "add" else 1.0
		var stir_t := s if id == "stir" else 0.0
		var col := Color(0.4, 0.5, 0.58).lerp(Color(0.5, 0.33, 0.2), add_t * 0.55 + stir_t * 0.45)
		(_pot_surface.material_override as StandardMaterial3D).albedo_color = col
		if not _spoon_mesh:
			_spoon_mesh = _spoon()
		_piece.mesh = _spoon_mesh
		_piece.global_transform = Transform3D(Basis(Vector3.UP, _turn) * Basis(Vector3.BACK, 0.35), _station.pos + Vector3(0, 0.72, 0))
		if id == "add":
			_part.visible = true
			var ingredients := _stew_ingredients()
			_part.mesh = ItemModels.mesh_for(ingredients[mini(_drops, ingredients.size() - 1)], _mat)   # (moved by the dragging)
		return
	var along := _side.cross(Vector3.UP).normalized()
	var item := String(recipe.needs.keys()[0])
	_piece.mesh = ItemModels.mesh_for(item, _tint_mat)
	_piece.material_override = null
	_set_centred(_piece, Basis(along, _turn) * Basis(Vector3.UP, 0.4), _station.pos + Vector3(0, 0.88, 0), 3.0)
	# Skewering: the spit slides in through the food.
	if _crossbar and id != "skewer":   # (while skewering, the dragging moves it)
		_crossbar.global_position = _station.pos + Vector3(0, 0.88, 0)
	# Browning as it cooks (and a little charring wherever a turn was missed).
	var cooked := s if id == "cook" else 0.0
	var tint := Color.WHITE.lerp(Color(0.62, 0.42, 0.3), cooked).darkened(minf(_char, 0.35))
	_tint_mat.set_shader_parameter("tint_color", tint)


func _stew_ingredients() -> Array:
	var out := []
	for item: String in recipe.needs:
		if item != "wood":
			out.append(item)
	while out.size() < 3:
		out.append(out[0] if not out.is_empty() else "berries")
	return out


## Puts a piece so the middle of its model (not its origin, which can be at one end) is at `at`.
func _set_centred(mi: MeshInstance3D, basis: Basis, at: Vector3, sc: float) -> void:
	var b := basis.scaled(Vector3.ONE * sc)
	var c := mi.mesh.get_aabb().get_center() if mi.mesh else Vector3.ZERO
	mi.global_transform = Transform3D(b, at - b * c)


## A wooden spoon standing in the stew pot, for stirring.
func _spoon() -> ArrayMesh:
	var k := MeshKit.new(4)
	var wood := Color(0.62, 0.45, 0.28)
	k.loft([Vector3(0.0, -0.05, 0), Vector3(0.0, 0.32, 0)], [0.02, 0.017], 7, wood, Callable(), Callable(), true, true)
	k.add_primitive(MeshKit.sphere(0.045, 8, 6), Transform3D(Basis.from_scale(Vector3(1.0, 0.5, 1.3)), Vector3(0.0, -0.06, 0)), wood.darkened(0.15), 0.0, 0.03)
	return k.commit(_mat)


## Heat: the bar glows in the coals and while it's hammered, cooling as it's worked; quenched, it goes dark.
func _update_glow() -> void:
	if mode != Mode.SMITH or not _piece:
		return
	if not _glow:
		_glow = MeshInstance3D.new()
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_glow.material_override = gm
		_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_piece.add_child(_glow)
	_glow.mesh = _piece.mesh
	_glow.scale = Vector3.ONE * 1.01
	var id := step_id()
	var g := 0.0
	if id in ["heat", "hammer"]:
		g = smoothstep(0.3, 0.9, heat)
	elif id == "quench":
		g = smoothstep(0.3, 0.9, heat) * (1.0 - step_t)
	(_glow.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.42, 0.1) * g * 0.9
	_tint_mat.set_shader_parameter("tint_color", Color.WHITE.darkened(0.25) if id in ["haft"] or (id == "quench" and step_t >= 1.0) else Color.WHITE)


## The point being struck (or watched), in world space.
func work_point() -> Vector3:
	match mode:
		Mode.SMELT:
			match step_id():
				"load": return _crucible.global_position + Vector3(0, 0.12, 0) if _crucible else global_position
				"melt": return _crucible.global_position + Vector3(0, 0.1, 0)
				_: return (_mould_fill.get_parent() as Node3D).global_position + Vector3(0, 0.05, 0)
		Mode.COOK:
			if recipe.out == "stew":
				return _station.pos + Vector3(0, 0.78, 0)
			return _station.pos + Vector3(0, 0.88, 0)
	if not is_instance_valid(_piece) or not _piece.mesh:
		return global_position
	if mode == Mode.KNAP and step_id() == "knap":
		return _piece.global_transform * _piece.mesh.get_aabb().get_center()
	# A tool: its head sits near the top of the handle.
	return _piece.global_transform * Vector3(0, _head_y(), 0)


func _setup_striker() -> void:
	if _striker_pivot:
		_striker_pivot.queue_free()
		_striker_pivot = null
	if not mech() in [Mech.FLICK, Mech.SAW]:
		return   # nothing in the other hand this step
	var tool_id := "knife_t1" if mech() == Mech.SAW else ("rock" if mode == Mode.KNAP else "hammer")
	var mi := MeshInstance3D.new()
	mi.mesh = ItemModels.mesh_for(tool_id, _mat)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_striker_pivot = Node3D.new()
	_striker_pivot.add_child(mi)
	if mode == Mode.KNAP:
		# The striking rock in your other hand, off to the right.
		_holder().add_child(_striker_pivot)
		_striker_pivot.position = Vector3(0.17, -0.16, -0.4)
		mi.scale = Vector3.ONE * 0.55
		_striker_pivot.basis = Basis(Vector3.FORWARD, 0.6)
		return
	add_child(_striker_pivot)
	if mech() == Mech.SAW:
		# A knife lying across the handle, its edge down, shaving along it.
		mi.scale = Vector3.ONE * 1.7
		mi.rotation = Vector3(0, 0, PI * 0.5)
		_striker_pivot.global_position = work_point()
		_striker_pivot.global_basis = _xf.basis * Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.FORWARD, 0.5)
		return
	# The hammer comes in from the side; its handle points at the piece, its face down.
	var hit := work_point()
	var cam_pos := _view(String(cur().get("view", "anvil"))).origin
	var away := hit - cam_pos
	away.y = 0.0
	away = away.normalized()
	var side := away.cross(Vector3.UP).normalized()
	_striker_side = side
	_striker_pivot.global_position = hit - side * 0.33 + Vector3(0, 0.1, 0)   # the head's lower face meets the piece
	var y_axis := side   # from the pivot toward the piece
	var z_axis := Vector3.UP
	_striker_rest = Basis(y_axis.cross(z_axis), y_axis, z_axis).orthonormalized() * Basis(Vector3.RIGHT, 0.8)
	_striker_pivot.global_basis = _striker_rest


# --- Playing --------------------------------------------------------------------------------

## Screen pixels scale with the window (the gestures were tuned at 720 px tall).
func ui_scale() -> float:
	return maxf(get_viewport().get_visible_rect().size.y / 720.0, 0.5)


## Where a world point is on the screen.
func screen(p: Vector3) -> Vector2:
	if _cam and not _cam.is_position_behind(p):
		return _cam.unproject_position(p)
	return get_viewport().get_visible_rect().size * 0.5


## How far in front of the camera a point is (along its view).
func _depth(p: Vector3) -> float:
	return maxf(-(_cam.global_transform.affine_inverse() * p).z, 0.05)


## The point under the hand on the plane facing the camera `depth` in front of it.
func _under_ptr(depth: float) -> Vector3:
	return _cam.project_position(ptr, depth)


func _process(delta: float) -> void:
	if feedback.has("age"):
		feedback.age += delta
	_nag_t = maxf(_nag_t - delta, 0.0)
	if not _closing:
		_update_fx(delta)
	if _busy or _closing:
		return
	_lock = maxf(_lock - delta, 0.0)
	_impact = maxf(_impact - delta, 0.0)
	match mech():
		Mech.PUMP:
			_pump(delta)
		Mech.TILT:
			_pour(delta)
		Mech.STIR:
			_stir(delta)
	if mode == Mode.SMITH and step_id() in ["hammer", "quench"]:
		heat = maxf(heat - 0.07 * delta, 0.35)   # the bar cools slowly on the anvil
	progress = (step + clampf(step_t, 0.0, 1.0)) / maxf(steps.size(), 1.0)
	_refresh()
	if mech() in [Mech.DRAG, Mech.DIP]:
		_drag_process(delta)
	_update_striker(delta)
	if step_t >= 1.0 and not _snapping:
		_next_step()


## Every bit of mouse movement: the hand moves, and the step reads the movement its own way.
func move(rel: Vector2) -> void:
	if _busy or _closing:
		return
	var before := ptr
	var vp := get_viewport().get_visible_rect().size
	ptr = (ptr + rel).clamp(Vector2.ZERO, vp)
	var sc := ui_scale()
	match mech():
		Mech.FLICK:
			_flick_track(before)
		Mech.SAW:
			# The hand stays in a band round the work (the strokes are read from the movement itself).
			ptr = ptr.clamp(_anchor - Vector2(170, 45) * sc, _anchor + Vector2(170, 45) * sc)
			_saw_track(rel)
		Mech.PUMP:
			ptr = ptr.clamp(_anchor - Vector2(30, 110) * sc, _anchor + Vector2(30, 110) * sc)
			_pump_track(rel)
		Mech.TILT:
			tilt = clampf(tilt + rel.x / (220.0 * sc), 0.0, 1.0)
			ptr = _anchor + Vector2((tilt - 0.5) * 220.0 * sc, 0)
		Mech.STIR, Mech.WRAP:
			_circle(rel)


func press() -> void:
	pressed = true
	if not _busy and not _closing and mech() in [Mech.DRAG, Mech.DIP]:
		_try_grab()


func release() -> void:
	pressed = false
	if dragging and not _closing:
		_let_go()


func _sample(q: float) -> void:
	_q_sum += clampf(q, 0.0, 1.0)
	_q_n += 1


## How clean the work on this item has been so far (0..1).
func quality() -> float:
	return _q_sum / _q_n if _q_n > 0 else 0.7


func _say(text: String, col := Color(1.0, 0.92, 0.6)) -> void:
	feedback = {"text": text, "color": col, "age": 0.0}


## A gentle nudge (too fast, not steady...), not more than about once a second.
func _nag(text: String) -> void:
	if _nag_t > 0.0:
		return
	_nag_t = 1.1
	_say(text, Color(1.0, 0.75, 0.55))


# Striking: aim at the glowing spot and flick down through it.

## Where to strike next, on the piece (or the wedge's top, or the mould).
func spot_world() -> Vector3:
	if is_instance_valid(_piece) and _piece.mesh:
		match step_id():
			"knap", "hammer":
				return _piece.global_transform * _spot_local
			"wedge":
				return _piece.global_transform * Vector3(0, _piece.mesh.get_aabb().end.y - 0.012, 0)
	return work_point()


## A fresh spot somewhere on the piece, well away from the last one.
func _new_spot() -> void:
	if not is_instance_valid(_piece) or not _piece.mesh or not step_id() in ["knap", "hammer"]:
		return
	var bb := _piece.mesh.get_aabb()
	var was := screen(spot_world())
	var best := _spot_local
	for i in 10:
		var u := Vector3(randf_range(0.22, 0.78), randf_range(0.22, 0.78), randf_range(0.3, 0.7))
		best = bb.position + bb.size * u
		if screen(_piece.global_transform * best).distance_to(was) > 40.0 * ui_scale():
			break
	_spot_local = best


func _flick_track(before: Vector2) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_hist.append(Vector3(before.x, before.y, now))
	while _hist.size() > 1 and now - _hist[0].z > FLICK_WINDOW:
		_hist.pop_front()
	var top: Vector3 = _hist[0]
	for h: Vector3 in _hist:
		if h.y < top.y:
			top = h
	if ptr.y - top.y >= FLICK_LEN * ui_scale() and _lock <= 0.0:
		_hist.clear()
		strike(Vector2(top.x, top.y), ptr)


## A blow along the flick from `a` to `b`: graded by how close it passes to the spot.
func strike(a: Vector2, b: Vector2) -> void:
	if _busy or _closing or _lock > 0.0 or mech() != Mech.FLICK:
		return
	var sp := screen(spot_world())
	var near := Geometry2D.get_closest_point_to_segment(sp, a, b)
	var q := clampf(1.0 - near.distance_to(sp) / (FLICK_AIM * ui_scale()), 0.0, 1.0)
	var n := float(cur().get("n", 1))
	var gain := MISS_SHARE / n
	if q >= PERFECT_Q:
		gain = 1.0 / n
		_say("Perfect!", Color(0.75, 1.0, 0.6))
	elif q >= GOOD_Q:
		gain = lerpf(0.45, 1.0, q) / n
		_say("Good")
	else:
		_say("Missed the spot", Color(1.0, 0.6, 0.5))
	_sample(q)
	var good := q >= GOOD_Q
	_lock = HIT_LOCK if good else MISS_LOCK
	# Where the blow lands: on the spot, or off it where the flick went.
	_impact_at = spot_world() if good else _cam.project_position(near, _depth(spot_world()))
	_impact = 0.12
	step_t = minf(step_t + gain, 1.0)
	if q >= PERFECT_Q:
		_perfect_fx(func() -> void: _show_strike(good))
	else:
		_show_strike(good)
	if good:
		_new_spot()


## The striking rock (knapping) or hammer follows the hand, hovering just over the work; at a blow it lands.
func _update_striker(delta: float) -> void:
	if not _striker_pivot:
		return
	var hit := spot_world()
	var at := _under_ptr(_depth(hit))
	var k := 1.0 - exp(-30.0 * delta)
	if mech() == Mech.SAW:
		# The knife rides along the handle, under the hand.
		var a := _piece.global_transform * Vector3(0, 0.02, 0)
		var b := work_point()
		var on := Geometry3D.get_closest_point_to_segment(at, a, b)
		_striker_pivot.global_position = _striker_pivot.global_position.lerp(on + Vector3(0, 0.03, 0), k)
		return
	var landing := _impact > 0.0
	if landing:
		at = _impact_at
		k = 1.0
	if mode == Mode.KNAP:
		# A little in front of the stone (toward you) but right under the hand, its edge at the hand's point.
		var lift := 0.0 if landing else 0.012
		var near := _cam.project_position(ptr, maxf(_depth(hit) - 0.06, 0.1)) if not landing else at.lerp(_cam.global_position, 0.15)
		var local := _holder().to_local(near) + Vector3(0.028, lift, 0.0)
		_striker_pivot.position = _striker_pivot.position.lerp(local, k)
		return
	# (The rest pose is raised for a swing; tipped down 0.8 it lies flat on the work. Hovering, it's held just
	# above the hand's point, a little cocked.)
	var pivot := at - _striker_side * 0.33 + Vector3(0, 0.1, 0)
	_striker_pivot.global_position = _striker_pivot.global_position.lerp(pivot, k)
	_striker_pivot.global_basis = _striker_rest * Basis(Vector3.RIGHT, -0.8 if landing else -0.55)


# Strokes: the bench (side to side) and the bellows (up and down).

func _saw_track(rel: Vector2) -> void:
	var dir := int(signf(rel.x)) if absf(rel.x) > 0.5 else 0
	if dir != 0 and dir != _stroke_dir:
		_stroke_dir = dir
		_stroke = 0.0
		_stroke_drift = 0.0
		_counted = false
	_stroke += absf(rel.x)
	_stroke_drift += absf(rel.y)
	if not _counted and _stroke >= SAW_STROKE * ui_scale():
		_counted = true
		# Clean if the stroke ran straight along (little up-and-down wobble in it).
		var q := clampf(1.0 - _stroke_drift / (_stroke * 0.55), 0.0, 1.0)
		_sample(q)
		strokes += 1
		step_t = minf(step_t + 1.0 / SAW_STROKES, 1.0)
		var at := _striker_pivot.global_position if _striker_pivot else work_point()
		Audio.play_3d("chop", at, -7.0, randf_range(1.25, 1.45) if q >= GOOD_Q else 0.95)
		Effects.splinters(self, at, Color(0.82, 0.66, 0.46), Color(0.72, 0.55, 0.36), 5 if q >= GOOD_Q else 2, 0.3)
		if q < 0.4:
			_nag("Steady: keep it straight")


func _pump_track(rel: Vector2) -> void:
	var dir := int(signf(rel.y)) if absf(rel.y) > 0.5 else 0
	if dir != 0 and dir != _pump_dir:
		_pump_dir = dir
		_pump_len = 0.0
		_counted = false
	_pump_len += absf(rel.y)
	if not _counted and _pump_len >= PUMP_STROKE * ui_scale():
		_counted = true
		heat = minf(heat + PUMP_HEAT, 1.0)
		Audio.play_3d("swoosh", work_point(), -13.0, 0.5 if dir > 0 else 0.6)
		# Each push of the bellows throws a shower of embers off the coals, bigger the hotter they are.
		var coals: Vector3 = _xf * COALS
		Effects.sparks(self, coals, Color(1.0, 0.55, 0.18), roundi(3 + heat * 8.0), 1.2 + heat * 1.8)
		if heat > 0.5 and dir > 0:
			Effects.flash(self, coals + Vector3(0, 0.2, 0), Color(1.0, 0.5, 0.2), 0.8 * heat, 2.5, 0.35)


## Bellows: each stroke stokes the fire, which dies back between them. The work goes fastest in the hot band.
func _pump(delta: float) -> void:
	heat = clampf(heat - HEAT_FADE * delta, 0.0, 1.0)
	var rate := 1.0 / float(cur().get("dur", 3.0))
	if heat >= HEAT_BAND.x and heat <= HEAT_BAND.y:
		step_t += rate * delta
	elif heat >= HEAT_WARM and heat < HEAT_BAND.x:
		step_t += rate * 0.3 * delta
	elif heat > HEAT_BAND.y:
		_nag("Too hot: ease off")
	_sample_t += delta
	if _sample_t >= 0.3 and heat >= HEAT_WARM:
		_sample_t = 0.0
		_sample(1.0 if heat <= HEAT_BAND.y and heat >= HEAT_BAND.x else (0.7 if heat < HEAT_BAND.x else 0.25))


## Pouring: the further it's tipped, the faster it pours. Tip it back at the line; over the top spills (and the
## mould has to be topped up again, a little later: speed only, nothing lost).
func _pour(delta: float) -> void:
	var rate := POUR_RATE * smoothstep(0.3, 1.0, tilt)
	pouring = rate > 0.01
	if pouring:
		fill += rate * delta
		if fill > 1.0:
			fill = 0.55
			_spills += 1
			_say("Spilled!", Color(1.0, 0.6, 0.5))
			Effects.sparks(self, work_point(), Color(1.0, 0.55, 0.15), 10, 1.8)
			Effects.dust(self, work_point(), Color(0.4, 0.38, 0.36), 3, 0.15, 0.6)   # a puff of smoke
	elif _was_pouring:   # just tipped back
		if fill >= POUR_BAND.x:
			# Right on the line is clean; a bit over it (short of spilling) less so.
			var q := 1.0 if fill <= POUR_BAND.y else clampf(1.0 - (fill - POUR_BAND.y) / 0.05, 0.3, 1.0)
			q *= pow(0.6, _spills)
			_sample(q)
			step_t = 1.0
			if q >= PERFECT_Q:
				_say("Perfect!", Color(0.75, 1.0, 0.6))
				_perfect_fx(func() -> void: Effects.sparks(self, work_point(), Color(1.0, 0.6, 0.2), 10, 1.5))
			else:
				_say("Good")
		else:
			_say("More")
	_was_pouring = pouring
	if step_t < 1.0:
		step_t = minf(fill / POUR_BAND.x, 0.99) if fill > 0.0 else 0.0


# Circling: winding a binding on, stirring, turning the spit.

func _circle(rel: Vector2) -> void:
	var sc := ui_scale()
	var before := wrap_vec
	wrap_vec = (wrap_vec + rel).limit_length(140.0 * sc)
	if before.length() < WRAP_RADIUS * sc or wrap_vec.length() < WRAP_RADIUS * sc:
		return
	var turned := angle_difference(before.angle(), wrap_vec.angle())
	if mech() == Mech.WRAP:
		var t := absf(turned)
		step_t += minf(t, 0.6) / (TAU * WRAP_TURNS)
		if fmod(step_t * WRAP_TURNS * 4.0, 1.0) < minf(t, 0.6) / (TAU / 4.0) * 0.25:
			Audio.play_3d("rustle", work_point(), -12.0, 1.4)
		return
	_stir_acc += absf(turned)
	_turn += turned * (1.0 if recipe.out == "stew" else 0.6)   # the spoon goes round with you; the spit turns


## Stirring and turning: progress with every bit of circling, best at a steady pace.
func _stir(delta: float) -> void:
	var turned := _stir_acc
	_stir_acc = 0.0
	turn_rate = lerpf(turn_rate, turned / maxf(delta, 1e-4), 1.0 - exp(-5.0 * delta))
	var gain := turned
	var stew: bool = recipe.out == "stew"
	if turn_rate > STIR_PACE.y:
		gain *= 0.35
		_nag("Too fast: it's slopping about" if stew else "Too fast: it won't cook")
		if stew and randf() < delta * 3.0:
			Effects.splash(self, work_point(), 0.25)
	elif turn_rate < STIR_PACE.x:
		gain *= 0.6
		if not stew and turn_rate < 0.6:
			_char += 0.03 * delta   # left sitting over the fire, it catches
	step_t = minf(step_t + gain / (TAU * STIR_TURNS), 1.0)
	_sample_t += delta
	if _sample_t >= 0.3 and turn_rate > 0.5:
		_sample_t = 0.0
		_sample(1.0 if turn_rate >= STIR_PACE.x and turn_rate <= STIR_PACE.y else (0.3 if turn_rate > STIR_PACE.y else 0.7))
	# A slurp of the stew, a sizzle off the spit, every half turn or so.
	_sound_acc += turned
	if _sound_acc > PI:
		_sound_acc = 0.0
		var at := work_point()
		Audio.play_3d("rustle", at, -9.0, 0.7 if stew else 0.55)
		if not stew:
			Effects.chips(self, at, Color(1.0, 0.75, 0.4), 3, 0.02, 1.2)   # spitting fat
			Effects.steam(self, at, 2, 0.12)


# Dragging: press on a piece and drag it into place (or into the water, and hold it there).

## What's dragged this step, where it starts, where it goes, and the point on it that has to reach its place.
func _drag_setup() -> void:
	dragging = false
	drag_node = null
	if step_t >= 1.0:
		return
	match step_id():
		"fit", "seat", "haft":
			drag_node = _part
			var up := -1.0 if step_id() != "seat" else 1.0   # a shaft comes up from below, a head down from above
			var parent := _part.get_parent() as Node3D
			var home := _tool_place(_where())
			_drag_home_xf = parent.global_transform * home
			_drag_from = parent.global_transform * Transform3D(home.basis, home.origin + home.basis * Vector3(0, up * 0.3, 0.07))
			_drag_focus = Vector3(0, _head_y(), 0)
		"skewer":
			drag_node = _crossbar
			var along := _side.cross(Vector3.UP).normalized()
			var c: Vector3 = _station.pos + Vector3(0, 0.88, 0)
			_drag_home_xf = Transform3D(Basis(), c)
			_drag_from = Transform3D(Basis(), c + along * 0.55)
			_drag_focus = along * 0.22   # a hand's width in from where it sticks out
		"load":
			drag_node = _dropper
			_dropper.visible = true
			# Held by the middle of the lump, and let go right over the middle of the crucible's mouth.
			var lb := Basis.from_scale(Vector3.ONE * 0.75)
			var lc := _dropper.mesh.get_aabb().get_center() if _dropper.mesh else Vector3.ZERO
			_drag_home_xf = Transform3D(lb, _crucible.global_position + Vector3(0, 0.2, 0) - lb * lc)
			_drag_from = Transform3D(lb, _xf * Vector3(-0.32, 0.95, -0.22) - lb * lc)
			_drag_focus = lc
		"add":
			drag_node = _part
			var along := _side.cross(Vector3.UP).normalized()
			var b := Basis.from_scale(Vector3.ONE * 2.0)
			var c := _part.mesh.get_aabb().get_center() if _part.mesh else Vector3.ZERO
			_drag_home_xf = Transform3D(b, _station.pos + Vector3(0, POT_BASE + 0.24, 0) - b * c)
			_drag_from = Transform3D(b, _station.pos + Vector3(0, 0.98, 0) + along * 0.42 - b * c)
			_drag_focus = c
		"quench":
			drag_node = _piece
			_drag_from = _piece.global_transform
			_drag_focus = Vector3(0, _head_y(), 0)
			var water: Vector3 = _xf * (BUCKET_AT + Vector3(0, 0.26, 0))
			_drag_home_xf = Transform3D(_drag_from.basis, _drag_from.origin + (water - _drag_from * _drag_focus))
	if drag_node:
		drag_node.global_transform = _drag_from


## The dragged piece's point that has to reach its place, now and when it's there.
func drag_focus() -> Vector3:
	return drag_node.global_transform * _drag_focus if drag_node else work_point()


func drag_target() -> Vector3:
	return _drag_home_xf * _drag_focus


func _try_grab() -> void:
	if drag_node == null or dragging or _snapping or step_t >= 1.0 or hold_t >= DIP_HOLD:
		return
	if ptr.distance_to(screen(drag_focus())) > GRAB * ui_scale():
		_nag("Grab it: move onto it first")
		return
	dragging = true
	_drag_depth = _depth(drag_node.global_position)
	_grab = drag_node.global_position - _under_ptr(_drag_depth)
	Audio.play_3d("rustle", drag_focus(), -12.0, 1.3)


## Each frame: the piece follows the hand while it's held; quenching, it hisses while it's under.
func _drag_process(delta: float) -> void:
	if drag_node == null or _snapping or step_t >= 1.0:
		return
	if not dragging:
		drag_node.global_transform = _drag_from
		return
	var xf := Transform3D(_drag_from.basis, _under_ptr(_drag_depth) + _grab)
	if mech() == Mech.DIP:
		var under := screen(xf * _drag_focus).distance_to(screen(drag_target())) < SNAP * 1.5 * ui_scale()
		if under:
			# In the water: it sinks in, hissing and steaming, cooling as it's held there.
			xf = Transform3D(_drag_from.basis, _drag_home_xf.origin - Vector3(0, 0.03, 0))
			if hold_t == 0.0 or not _in_water:
				var water := drag_target()
				Audio.play_3d("swoosh", water, -2.0, 1.6)
				Effects.splash(self, water, 0.3)
			_in_water = true
			hold_t += delta
			_sample_t += delta
			if _sample_t > 0.15:
				_sample_t = 0.0
				Effects.steam(self, drag_target() + Vector3(0, 0.05, 0), 3, 0.2)
			step_t = minf(hold_t / DIP_HOLD, 0.99)
			if hold_t >= DIP_HOLD:
				_sample(1.0 if _dips == 0 else 0.6)
				_say("Quenched", Color(0.75, 1.0, 0.6))
				dragging = false
				_back_home(func() -> void: step_t = 1.0)
		elif _in_water:
			_in_water = false
			_dips += 1   # pulled out too soon: it'll have to go back in
			_nag("Hold it under")
	drag_node.global_transform = xf


## Let go: close enough to its place, it goes home; otherwise it drops back where it was.
func _let_go() -> void:
	dragging = false
	if mech() == Mech.DIP:
		if step_t < 1.0:
			_back_home(Callable())
		return
	var d := screen(drag_focus()).distance_to(screen(drag_target()))
	var snap := SNAP * ui_scale()
	if d > snap:
		_say("Not quite", Color(1.0, 0.75, 0.55))
		Audio.play_3d("thud", drag_focus(), -12.0, 1.3)
		_back_home(Callable())
		return
	var q := clampf(1.0 - d / snap, 0.0, 1.0)
	_sample(q)
	_say("Perfect!" if q >= PERFECT_Q else "Good", Color(0.75, 1.0, 0.6) if q >= PERFECT_Q else Color(1.0, 0.92, 0.6))
	_snapping = true
	var node := drag_node
	var from := node.global_transform
	var to := _drag_home_xf
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: node.global_transform = from.interpolate_with(to, w), 0.0, 1.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	if step_id() in ["load", "add"]:   # it falls in
		var sunk := Transform3D(to.basis, to.origin - Vector3(0, 0.12, 0))
		tw.tween_method(func(w: float) -> void: node.global_transform = to.interpolate_with(sunk, w), 0.0, 1.0, 0.1)
	tw.tween_callback(func() -> void:
		_snapping = false
		if q >= PERFECT_Q:
			_perfect_fx(func() -> void: _show_drop(true))
		else:
			_show_drop(true)
		_drops += 1
		step_t = minf(step_t + 1.0 / float(cur().get("n", 1)), 1.0)
		if step_t < 1.0:
			_refresh()
			_drag_setup())


## Back to where it was picked up from.
func _back_home(then: Callable) -> void:
	_snapping = true
	var node := drag_node
	var from := node.global_transform
	var to := _drag_from
	var tw := create_tween()
	tw.tween_method(func(w: float) -> void: node.global_transform = from.interpolate_with(to, w), 0.0, 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		_snapping = false
		_in_water = false
		if then.is_valid():
			then.call())


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseMotion:
		move((event as InputEventMouseMotion).relative)
		return
	# While working, the game's other keys wait: Esc, right click and walking away stop instead.
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
		stop()
		return
	for a in ["move_forward", "move_back", "move_left", "move_right", "jump"]:
		if event.is_action_pressed(a):
			stop()
			return
	if event.is_action_pressed("attack"):
		press()
	elif event.is_action_released("attack"):
		release()


func _show_drop(good: bool) -> void:
	var at := work_point()
	if not good:
		Audio.play_3d("thud", at, -10.0, 1.3)
		return
	match step_id():
		"load":
			Audio.play_3d("clink", at, -6.0, 0.8)
			Effects.sparks(self, at, Color(1.0, 0.6, 0.2), 5, 1.2)
		"add":
			Audio.play_3d("rustle", at, -4.0, 0.6)
			Effects.splash(self, at, 0.35)
		_:
			Audio.play_3d("chop", at, -6.0, 1.4)


func _show_strike(good: bool) -> void:
	var at := _impact_at
	match mode:
		Mode.SMITH, Mode.SMELT:
			Audio.play_3d("clink", at, -2.0, randf_range(0.95, 1.1) if good else 0.8)
			Effects.sparks(self, at, Color(1.0, 0.6, 0.2), 12 if good else 4, 3.0 if good else 1.8)
		Mode.CARVE:
			Audio.play_3d("thud", at, -4.0, 1.2)
		Mode.KNAP:
			Audio.play("clink", -6.0, randf_range(1.3, 1.5) if good else 1.0)
			Effects.chips(_holder(), at, Color(0.55, 0.56, 0.6), 6 if good else 2, 0.015, 1.2)   # flakes
			if good:
				Effects.sparks(_holder(), at, Color(1.0, 0.85, 0.6), 3, 1.5)


## Which place the piece is worked in this step.
func _where() -> String:
	return "hand" if mode == Mode.KNAP else ("bench" if mode == Mode.CARVE else ("coals" if step_id() == "heat" else "anvil"))


## A step's fresh start: everything that counts movement goes back to zero.
func _reset_step_state() -> void:
	step_t = 0.0
	_drops = 0
	fill = 0.0
	tilt = 0.0
	pouring = false
	_was_pouring = false
	_spills = 0
	turn_rate = 0.0
	hold_t = 0.0
	_dips = 0
	_in_water = false
	strokes = 0
	_stroke_dir = 0
	_pump_dir = 0
	_counted = false
	_hist.clear()
	dragging = false
	_snapping = false
	_impact = 0.0
	wrap_vec = Vector2(0, -60) * ui_scale()


## Once the view has settled on a step: the hand starts in the middle of the work, ready.
func _step_ready() -> void:
	_busy = false
	_anchor = screen(work_point())
	ptr = _anchor + (Vector2(0, -60) * ui_scale() if mech() == Mech.FLICK else Vector2.ZERO)
	if mech() == Mech.SAW:
		_anchor += Vector2(0, 90) * ui_scale()
		ptr = _anchor
	if mech() == Mech.PUMP:   # off to the side, clear of the fire
		_anchor += Vector2(-190, 30) * ui_scale()
		ptr = _anchor
	if mech() == Mech.TILT:
		_anchor += Vector2(0, 110) * ui_scale()
		ptr = _anchor - Vector2(110, 0) * ui_scale()
	_new_spot()
	_drag_setup()


## On to the next step (the view moves if it needs to), or the item's done.
func _next_step() -> void:
	step_t = 1.0
	if step + 1 >= steps.size():
		_finish_item()
		return
	step += 1
	_reset_step_state()
	_last_stage = ""
	_busy = true
	_refresh()
	_setup_striker()
	_drag_setup()
	_go_to_view(_step_ready)


# --- Finishing ------------------------------------------------------------------------------

func _finish_item() -> void:
	_busy = true
	progress = 1.0
	var q := quality()
	Net.request("craft", {"recipe": recipe.id, "pos": player.global_position, "times": 1, "quality": q}, func(res: Dictionary) -> void:
		if _closing:
			return
		if not res.get("ok", false):
			player.hint.emit(String(res.get("reason", "Couldn't finish it")))
			stop()
			return
		made += 1
		left -= 1
		_show_done(q, int(res.get("extra", 0)))
		var more := left > 0 and CraftSession.problem(player, recipe) == ""
		get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
			if _closing:
				return
			if more:
				_next()
			else:
				stop()))


## The finished thing, where the work was.
func _show_done(q := 0.7, extra := 0) -> void:
	var text := "Made %s" % ItemDB.display_name(recipe.out)
	if extra > 0:
		text += "  +%d" % extra
	var col := Color(1.0, 0.95, 0.8)
	if q >= GameActions.FINE_WORK:
		text = "Fine work!  " + text
		col = Color(0.8, 1.0, 0.65)
	elif q < 0.4:
		text += "  (rough)"
	feedback = {"text": text, "color": col, "age": 0.0, "long": true}
	Audio.play(Audio.sfx.chime, -4.0)
	_done = true
	if _part:
		_part.visible = false
	if _glow:
		_glow.visible = false
	_tint_mat.set_shader_parameter("tint_color", Color.WHITE)
	# A finishing flourish: a ring of light round it, a flash, a twinkle, and the view pushing in.
	var fin := work_point() + Vector3(0, 0.08, 0)
	Effects.slow_motion(0.6, func() -> void:
		Effects.ring(self, fin, Color(1.0, 0.9, 0.55), 22, 0.45)
		Effects.twinkle(self, fin, Color(1.0, 0.92, 0.6), 9, 0.35))
	Effects.flash(self, fin + Vector3(0, 0.2, 0), Color(1.0, 0.92, 0.75), 1.4, 2.5, 0.6)
	_punch(4.0)
	match mode:
		Mode.SMELT:
			_ingot.global_transform = Transform3D(_ingot.global_basis, _ingot.global_position + Vector3(0, 0.05, 0))
			return
		Mode.COOK:
			_piece.mesh = ItemModels.mesh_for(String(recipe.out), _mat)
			var at: Vector3 = _station.pos + (Vector3(0, 0.8, 0) + _side * 0.25 if recipe.out == "stew" else Vector3(0, 0.88, 0))
			_set_centred(_piece, Basis(), at, 2.0)
		_:
			_piece.mesh = ItemModels.mesh_for(String(recipe.out), _mat)
	var tw := create_tween()
	tw.tween_property(_piece, "position", _piece.position + Vector3(0, 0.05 if mode == Mode.KNAP else 0.12, 0), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The next one of a batch.
func _next() -> void:
	if _glow:
		_glow.visible = true
	_start_item()
	_busy = true
	_go_to_view(_step_ready)


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
		for n in [_piece, _part, _striker_pivot]:
			if is_instance_valid(n):
				n.queue_free()
		ended.emit()
		queue_free()
	if _cam and not at_once:
		_glide(player.camera.global_transform, finish, player.camera.fov)
	else:
		finish.call()


# --- Tests ------------------------------------------------------------------------------------

## Plays the current step well (for the automated tests), with the same mouse movements a player makes: flicks
## through the spot, drags each piece to its place, long straight strokes, steady pumping and circling, a pour to
## the line.
func autoplay(delta: float) -> void:
	if _busy or _closing:
		return
	var sc := ui_scale()
	match mech():
		Mech.FLICK:
			if _lock > 0.0 or _impact > 0.0:
				return
			var above := screen(spot_world()) - Vector2(0, 12) * sc
			if ptr.distance_to(above) > 1.0:
				_hist.clear()
				move(above - ptr)
				_hist.clear()
			else:
				move(Vector2(0, FLICK_LEN + 20.0) * sc)
		Mech.DRAG, Mech.DIP:
			if _snapping or drag_node == null:
				return
			if not dragging:
				var f := screen(drag_focus())
				if ptr.distance_to(f) > 1.0:
					move(f - ptr)
				else:
					press()
				return
			var to := screen(drag_target()) - screen(drag_focus())
			if mech() == Mech.DIP and _in_water:
				return   # hold it under
			if to.length() > 1.0:
				move(to.limit_length(30.0 * sc))
			elif mech() == Mech.DRAG:
				release()
		Mech.SAW:
			move(Vector2(110.0 * _auto_side, 0) * sc)
			_auto_side = -_auto_side
		Mech.PUMP:
			if heat < 0.68:
				move(Vector2(0, 60.0 * _auto_side) * sc)
				_auto_side = -_auto_side
		Mech.TILT:
			if fill < 0.86:
				if tilt < 1.0:
					move(Vector2(40.0, 0) * sc)
			else:
				move(Vector2(-400.0, 0) * sc)
		Mech.STIR, Mech.WRAP:
			move(wrap_vec.rotated(5.5 * clampf(delta, 1.0 / 120.0, 0.1)) - wrap_vec)


## How wide the inside of a lathed vessel is at height y (its inner wall: the profile from its rim's peak onward).
static func _inner_radius(profile: Array, y: float) -> float:
	var top := 0
	for i in profile.size():
		if (profile[i] as Vector2).y > (profile[top] as Vector2).y:
			top = i
	for i in range(top, profile.size() - 1):
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		if (a.y >= y and b.y <= y) and absf(a.y - b.y) > 1e-6:
			return lerpf(a.x, b.x, (a.y - y) / (a.y - b.y))
	return (profile[profile.size() - 2] as Vector2).x


## The melt standing at height y in the (upright) crucible: a level disc as wide as the inside there.
func _set_pool_level(y: float) -> void:
	var r := _inner_radius(CRUCIBLE_PROFILE, y) - 0.002
	_pool.transform = Transform3D(Basis.from_scale(Vector3(r, 1.0, r)), Vector3(0, y, 0))


## The metal in the mould, `f` full: from the hollow's floor up.
func _set_mould_fill(f: float) -> void:
	var h := maxf(0.029 * f, 0.0005)
	_mould_fill.transform = Transform3D(Basis.from_scale(Vector3(1, h, 1)), Vector3(0, 0.0305 + h * 0.5, 0))
	_mould_fill.visible = f > 0.02
