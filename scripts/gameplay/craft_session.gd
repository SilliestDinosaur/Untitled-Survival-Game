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
enum Mech { RING, SWEEP, DIAL, PUMP, DROP, WRAP, POUR }

const TOOL_TYPES := ["hatchet", "pickaxe", "spear", "knife"]
const INGOTS := ["ingot_t2", "ingot_t3", "dusk_ingot"]

## Timing: a strike's grade by how well it was timed, and what each grade is worth (of one action's share).
const PERFECT_Q := 0.7
const GOOD_Q := 0.25
const MISS_SHARE := 0.15
const MISS_LOCK := 0.5      ## a fumble: a moment before you can strike again (so mashing is slow)
const HIT_LOCK := 0.22
## The forge: hold to pump the bellows. It only works while hot enough, fastest in the band.
const HEAT_UP := 0.7
const HEAT_DOWN := 0.4
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
var cue_t := 0.0           ## the timing cue's phase (0..1-ish)
var target := 0.5          ## the workbench mark, along the piece (0..1)
var fill := 0.0            ## pouring: how full the mould is
var wrap_vec := Vector2(0, -60)   ## winding: where the mouse is round the middle
var feedback := {}         ## {"text", "color", "age"}: the last action's grade, shown briefly
var test_hold := false     ## tests: hold the action button without a real input

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
var _was_holding := false
var _tint_mat: ShaderMaterial
var _molten_mat: StandardMaterial3D
var _last_stage := ""
var _spoon_mesh: ArrayMesh

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
			var plan := [{"mech": Mech.RING, "id": "knap", "n": 5, "view": "hand", "say": "Strike the stone as the ring closes, to knap it into a head"}]
			if knife:
				plan.append({"mech": Mech.WRAP, "id": "grip", "view": "hand", "say": "Circle the mouse to wind the cord grip on"})
			else:
				plan.append({"mech": Mech.DROP, "id": "fit", "n": 2, "view": "hand", "say": "Click when the shaft lines up, to fit the head on"})
				if spear:
					plan.append({"mech": Mech.WRAP, "id": "socket", "view": "hand", "say": "Circle the mouse to bind the socket on"})
				else:
					plan.append({"mech": Mech.RING, "id": "wedge", "n": 2, "view": "hand", "say": "Strike as the ring closes, to drive the wedge home"})
			return plan
		Mode.CARVE:
			var plan := [{"mech": Mech.SWEEP, "id": "shape", "n": 5, "view": "bench", "say": "Strike as the marker crosses the mark, to shape the handle"},
				{"mech": Mech.DROP, "id": "seat", "n": 2, "view": "bench", "say": "Click when the head is over the handle, to seat it"}]
			if spear:
				plan.append({"mech": Mech.WRAP, "id": "socket", "view": "bench", "say": "Circle the mouse to bind the socket on"})
			if not spear:   # a spear's socket holds it; axes and picks get a wedge, knives a guard
				plan.append({"mech": Mech.RING, "id": "wedge", "n": 2, "view": "bench", "say": "Strike as the ring closes, to drive the wedge home" if not knife else "Strike as the ring closes, to fit the guard"})
			return plan
		Mode.SMITH:
			return [{"mech": Mech.PUMP, "id": "heat", "dur": 2.5, "view": "mouth", "say": "Hold to pump the bellows and heat the bar"},
				{"mech": Mech.RING, "id": "hammer", "n": 5, "view": "anvil", "say": "Strike as the ring closes, to hammer it into shape"},
				{"mech": Mech.DIAL, "id": "quench", "n": 1, "view": "anvil", "say": "Quench it when the dial reaches the green"},
				{"mech": Mech.DROP, "id": "haft", "n": 2, "view": "anvil", "say": "Click when the handle lines up, to fit it"}]
		Mode.SMELT:
			return [{"mech": Mech.DROP, "id": "load", "n": 3, "view": "mouth", "say": "Click when the scoop is over the crucible, to load the ore"},
				{"mech": Mech.PUMP, "id": "melt", "dur": 3.0, "view": "mouth", "say": "Hold to pump the bellows and melt the ore"},
				{"mech": Mech.POUR, "id": "pour", "view": "anvil", "say": "Hold to pour. Let go when it reaches the line"},
				{"mech": Mech.RING, "id": "tap", "n": 2, "view": "anvil", "say": "Strike as the ring closes, to knock the ingot out"}]
		_:
			if recipe.out == "stew":
				return [{"mech": Mech.DROP, "id": "add", "n": 3, "view": "fire", "say": "Click when it's over the pot, to add it"},
					{"mech": Mech.DIAL, "id": "stir", "n": 6, "view": "fire", "say": "Stir when the dial reaches the green"}]
			return [{"mech": Mech.RING, "id": "skewer", "n": 1, "view": "fire", "say": "Strike as the ring closes, to skewer it"},
				{"mech": Mech.DIAL, "id": "cook", "n": 8, "view": "fire", "say": "Turn the spit when the dial reaches the green"}]


func cur() -> Dictionary:
	return steps[mini(step, steps.size() - 1)] if not steps.is_empty() else {}


func mech() -> int:
	return int(cur().get("mech", Mech.RING))


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
	_build_props()
	_start_item()
	_go_to_view(func() -> void: _busy = false)


## A fresh item: the first step, the raw piece.
func _start_item() -> void:
	steps = _plan()
	step = 0
	step_t = 0.0
	progress = 0.0
	cue_t = 0.0
	fill = 0.0
	_drops = 0
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
	for i in 3:
		var lump := _mesh_node(ItemModels.mesh_for(ore, _mat), _crucible)
		lump.position = Vector3(rng.randf_range(-0.03, 0.03), 0.1 + i * 0.012, rng.randf_range(-0.03, 0.03))
		lump.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		lump.scale = Vector3.ONE * 0.9
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
			l.scale = Vector3.ONE * 0.9
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
	var where := "hand" if mode == Mode.KNAP else ("bench" if mode == Mode.CARVE else ("coals" if id == "heat" else "anvil"))
	var knife := String(ItemDB.info(recipe.out).get("tool", {}).get("type", "")) == "knife"
	var stage := {}
	var part_stage := {}
	var part_slide := 0.0   # how far the part still has to go (0 = home)
	match id:
		"knap":
			stage = {"head": s, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"fit":
			stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": -1.0, "handle": 1.0, "lash": 0.0, "wedge": 0.0}
			part_slide = -(1.0 - s)   # the shaft comes up from below
		"grip":
			stage = {"head": 1.0, "handle": 1.0, "lash": s, "wedge": 1.0}
		"socket":
			stage = {"head": 1.0, "handle": 1.0, "lash": s, "wedge": 1.0}
		"shape":
			stage = {"head": -1.0, "handle": s, "lash": 0.0, "wedge": 0.0}
		"seat":
			stage = {"head": -1.0, "handle": 1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
			part_slide = 1.0 - s       # the head comes down from above
		"wedge":
			stage = {"head": 1.0, "handle": 1.0, "lash": 1.0, "wedge": s if s > 0.0 else 0.01}
		"heat":
			stage = {"head": 0.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"hammer", "quench":
			stage = {"head": s if id == "hammer" else 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
		"haft":
			stage = {"head": 1.0, "handle": -1.0, "lash": 0.0, "wedge": 0.0}
			part_stage = {"head": -1.0, "handle": 1.0, "lash": 1.0 if not knife else 0.0, "wedge": 1.0 if not knife else 0.0}
			part_slide = -(1.0 - s)
	var key := "%s|%s|%s|%s" % [id, str(stage), str(part_stage), where]
	if key != _last_stage or part_slide != 0.0:
		_last_stage = key
		_piece.mesh = _tool(stage)
		_piece.transform = _tool_place(where)
		if not part_stage.is_empty():
			_part.mesh = _tool(part_stage)
			_part.visible = true
			# Slides along the haft (its local y), swaying sideways (its local z) while you line it up.
			var sway := (sweep_pos() - 0.5) * 0.16 * absf(part_slide) if mech() == Mech.DROP else 0.0
			var xf := _tool_place(where)
			_part.transform = Transform3D(xf.basis, xf.origin + xf.basis * Vector3(0, part_slide * 0.28, sway))


## Where a tool lies for each place: in your hand (in front of the camera), on the bench, in the coals, on the anvil.
func _tool_place(where: String) -> Transform3D:
	var head := _head_y()
	match where:
		"hand":
			var sc := 2.0 if step_id() == "knap" else 0.7
			var b := (Basis(Vector3.FORWARD, -0.35) * Basis(Vector3.RIGHT, 0.25)).scaled(Vector3.ONE * sc)
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
			_dropper.visible = true
			var over: Vector3 = _crucible.global_position + Vector3(0, 0.38, 0)
			var sway := (_xf.basis * Vector3(1, 0, 0)) * (sweep_pos() - 0.5) * 0.3
			_dropper.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 1.2), over + sway)
		"melt":
			_dropper.visible = false
			_pool.visible = s > 0.05
			_set_pool_level(0.02 + 0.08 * s)
			for l in _lumps:
				l.visible = s < 0.95
				l.scale = Vector3.ONE * 0.9 * (1.0 - s)
		"pour":
			for l in _lumps:
				l.visible = false
			_pool.visible = true
			# Held with its pouring lip over the mould, tipped by how hard you're pouring; the melt drains as the
			# mould fills.
			var tip := 1.1 if _holding() else 0.25
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
			_stream.visible = _holding()
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
			_part.mesh = ItemModels.mesh_for(ingredients[mini(_drops, ingredients.size() - 1)], _mat)
			var along := _side.cross(Vector3.UP).normalized()
			_part.global_transform = Transform3D(Basis.from_scale(Vector3.ONE * 2.0), _station.pos + Vector3(0, 1.05, 0) + along * (sweep_pos() - 0.5) * 0.45)
		return
	var along := _side.cross(Vector3.UP).normalized()
	var item := String(recipe.needs.keys()[0])
	_piece.mesh = ItemModels.mesh_for(item, _tint_mat)
	_piece.material_override = null
	_set_centred(_piece, Basis(along, _turn) * Basis(Vector3.UP, 0.4), _station.pos + Vector3(0, 0.88, 0), 3.0)
	# Skewering: the spit slides in through the food.
	if _crossbar:
		var slide := (1.0 - s) * 0.75 if id == "skewer" else 0.0
		_crossbar.global_position = _station.pos + Vector3(0, 0.88, 0) + along * slide
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
	if not mech() in [Mech.RING, Mech.SWEEP] or step_id() in ["skewer"]:
		return   # nothing to strike with in this step
	if mode == Mode.SMELT and step_id() != "tap":
		return
	var tool_id := "rock" if mode == Mode.KNAP else "hammer"
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
	# The hammer comes in from the side; its handle points at the piece, its face down.
	var hit := work_point()
	var cam_pos := _view(String(cur().get("view", "anvil"))).origin
	var away := hit - cam_pos
	away.y = 0.0
	away = away.normalized()
	var side := away.cross(Vector3.UP).normalized()
	_striker_pivot.global_position = hit - side * 0.33 + Vector3(0, 0.1, 0)   # the head's lower face meets the piece
	var y_axis := side   # from the pivot toward the piece
	var z_axis := Vector3.UP
	_striker_rest = Basis(y_axis.cross(z_axis), y_axis, z_axis).orthonormalized() * Basis(Vector3.RIGHT, 0.8)
	_striker_pivot.global_basis = _striker_rest


# --- Playing --------------------------------------------------------------------------------

func _holding() -> bool:
	return test_hold or Input.is_action_pressed("attack")


func _process(delta: float) -> void:
	if feedback.has("age"):
		feedback.age += delta
	if _busy or _closing:
		return
	_lock = maxf(_lock - delta, 0.0)
	var holding := _holding()
	match mech():
		Mech.PUMP:
			_pump(delta, holding)
		Mech.POUR:
			_pour(delta, holding)
		Mech.WRAP:
			pass   # the mouse does it (_input)
		_:
			_advance_cue(delta)
	if mode == Mode.SMITH and step_id() in ["hammer", "quench"]:
		heat = maxf(heat - 0.07 * delta, 0.35)   # the bar cools slowly on the anvil
	_was_holding = holding
	progress = (step + clampf(step_t, 0.0, 1.0)) / maxf(steps.size(), 1.0)
	_refresh()
	if step_t >= 1.0:
		_next_step()


## Bellows: holding pumps the heat up, letting go lets it fall. The work goes fastest in the hot band.
func _pump(delta: float, holding: bool) -> void:
	heat = clampf(heat + (HEAT_UP if holding else -HEAT_DOWN) * delta, 0.0, 1.0)
	var rate := 1.0 / float(cur().get("dur", 3.0))
	if heat >= HEAT_BAND.x and heat <= HEAT_BAND.y:
		step_t += rate * delta
	elif heat >= HEAT_WARM and heat < HEAT_BAND.x:
		step_t += rate * 0.3 * delta
	if holding and fmod(Time.get_ticks_msec() / 1000.0, 0.45) < delta:
		Audio.play_3d("swoosh", work_point(), -14.0, 0.55)


## Pouring: holding tips the crucible and fills the mould. Let go at the line; over the top spills (and you pour
## again, a little later: speed only, nothing lost).
func _pour(delta: float, holding: bool) -> void:
	if holding:
		fill += POUR_RATE * delta
		if fill > 1.0:
			fill = 0.55
			feedback = {"text": "Spilled!", "color": Color(1.0, 0.6, 0.5), "age": 0.0}
			Effects.chips(self, work_point(), Color(1.0, 0.55, 0.15), 8, 0.02, 2.0)
	elif _was_holding:   # just let go
		if fill >= POUR_BAND.x and fill <= POUR_BAND.y:
			feedback = {"text": "Perfect!", "color": Color(0.75, 1.0, 0.6), "age": 0.0}
			step_t = 1.0
		elif fill < POUR_BAND.x:
			feedback = {"text": "More", "color": Color(1.0, 0.92, 0.6), "age": 0.0}
	if step_t < 1.0:
		step_t = minf(fill / POUR_BAND.x, 0.99) if fill > 0.0 else 0.0


## The cue's speed for each kind of step.
func _advance_cue(delta: float) -> void:
	match mech():
		Mech.DIAL:
			cue_t += delta / 1.1
			if cue_t > 1.0:
				cue_t = 0.0   # missed the moment: it comes round again (the food catches a little)
				if step_id() == "cook":
					_char += 0.06
		Mech.SWEEP:
			cue_t += delta / 0.75
		Mech.DROP:
			cue_t += delta / 0.9
		_:   # a ring closing on the strike point
			cue_t += delta / 0.85
			if cue_t > 1.3:
				cue_t = 0.0


## The sweep (or sway) position, 0..1.
func sweep_pos() -> float:
	return pingpong(cue_t, 1.0)


func _quality() -> float:
	match mech():
		Mech.DIAL:
			return clampf(1.0 - absf(cue_t - 0.85) / 0.12, 0.0, 1.0)
		Mech.SWEEP:
			return clampf(1.0 - absf(sweep_pos() - target) / 0.11, 0.0, 1.0)
		Mech.DROP:
			return clampf(1.0 - absf(sweep_pos() - 0.5) / 0.12, 0.0, 1.0)
	return clampf(1.0 - absf(cue_t - 1.0) / 0.2, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event is InputEventMouseMotion:
		if mech() == Mech.WRAP and not _busy:
			wrap_input((event as InputEventMouseMotion).relative)
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
		strike()


## Winding: the mouse goes round the middle; each bit of a circle winds a bit more on.
func wrap_input(relative: Vector2) -> void:
	var before := wrap_vec
	wrap_vec = (wrap_vec + relative).limit_length(140.0)
	if before.length() < WRAP_RADIUS or wrap_vec.length() < WRAP_RADIUS:
		return
	var turned := absf(angle_difference(before.angle(), wrap_vec.angle()))
	step_t += minf(turned, 0.6) / (TAU * WRAP_TURNS)
	if fmod(step_t * WRAP_TURNS * 4.0, 1.0) < minf(turned, 0.6) / (TAU / 4.0) * 0.25:
		Audio.play_3d("rustle", work_point(), -12.0, 1.4)


## A click: a strike, a turn of the spit, a stir, or letting a part go.
func strike() -> void:
	if _busy or _closing or _lock > 0.0:
		return
	if mech() in [Mech.PUMP, Mech.POUR, Mech.WRAP]:
		return   # those are holding or circling, handled each frame
	var q := _quality()
	var n := float(cur().get("n", 1))
	var gain := MISS_SHARE / n
	if q >= PERFECT_Q:
		gain = 1.0 / n
		feedback = {"text": "Perfect!", "color": Color(0.75, 1.0, 0.6), "age": 0.0}
	elif q >= GOOD_Q:
		gain = lerpf(0.45, 1.0, q) / n
		feedback = {"text": "Good", "color": Color(1.0, 0.92, 0.6), "age": 0.0}
	else:
		feedback = {"text": "Miss", "color": Color(1.0, 0.6, 0.5), "age": 0.0}
	var good := q >= GOOD_Q
	_lock = HIT_LOCK if good else MISS_LOCK
	if mech() == Mech.DROP:
		# A part or an ingredient only goes in when it's lined up; a miss just costs a moment.
		if good:
			step_t = minf(step_t + 1.0 / n, 1.0)
			_drops += 1
		_show_drop(good)
		cue_t = randf()   # it starts swaying from somewhere new
		return
	step_t = minf(step_t + gain, 1.0)
	_show_strike(good)
	match mech():
		Mech.DIAL:
			cue_t = 0.0   # turned: the other side starts again
		Mech.SWEEP:
			var u := sweep_pos()   # a new mark, well away from the marker
			target = clampf(fposmod(u + randf_range(0.3, 0.7), 1.0), 0.15, 0.85)
		_:
			cue_t = 0.0


func _show_drop(good: bool) -> void:
	var at := work_point()
	if not good:
		Audio.play_3d("thud", at, -10.0, 1.3)
		return
	match step_id():
		"load":
			Audio.play_3d("clink", at, -6.0, 0.8)
			Effects.chips(self, at, Color(1.0, 0.6, 0.2), 4, 0.015, 1.2)
		"add":
			Audio.play_3d("rustle", at, -4.0, 0.6)
			Effects.chips(self, at, Color(0.55, 0.65, 0.75), 6, 0.02, 1.5)   # a splash
		_:
			Audio.play_3d("chop", at, -6.0, 1.4)


func _show_strike(good: bool) -> void:
	var at := work_point()
	match step_id():
		"cook", "stir":
			create_tween().tween_method(func(a: float) -> void: _turn = a, _turn, _turn + PI, 0.25).set_trans(Tween.TRANS_SINE)
			Audio.play_3d("rustle", at, -6.0, 0.7 if good else 0.5)
			if good and step_id() == "cook":
				Effects.chips(self, at, Color(1.0, 0.75, 0.4), 5, 0.025, 1.2)   # spitting fat
			return
		"quench":
			if good:
				# Into the bucket and out again, hissing.
				var home := _piece.transform
				var water: Vector3 = _xf * (BUCKET_AT + Vector3(0, 0.3, 0))
				var dip := Transform3D(home.basis, home.origin + (water - work_point()))
				_busy = true
				var tw := create_tween()
				tw.tween_property(_piece, "transform", dip, 0.25).set_trans(Tween.TRANS_SINE)
				tw.tween_callback(func() -> void:
					Audio.play_3d("swoosh", water, -2.0, 1.6)
					Effects.chips(self, water + Vector3(0, 0.05, 0), Color(0.9, 0.92, 0.95), 16, 0.03, 2.5))   # steam
				tw.tween_interval(0.35)
				tw.tween_property(_piece, "transform", home, 0.25).set_trans(Tween.TRANS_SINE)
				tw.tween_callback(func() -> void: _busy = false)
			else:
				Audio.play_3d("swoosh", at, -8.0, 1.2)
			return
		"skewer":
			Audio.play_3d("chop", at, -6.0, 1.3)
			return
	if _striker_pivot and mode == Mode.KNAP:
		# The rock knocks against the edge of the stone and comes back.
		var rest := _striker_pivot.position
		var hit_at: Vector3 = _holder().to_local(at) + Vector3(0.05, 0.0, 0.0)
		var tw := create_tween()
		tw.tween_property(_striker_pivot, "position", hit_at, 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_striker_pivot, "position", rest, 0.18).set_trans(Tween.TRANS_SINE)
	elif _striker_pivot:
		var tw := create_tween()
		tw.tween_property(_striker_pivot, "basis", _striker_rest * Basis(Vector3.RIGHT, -0.8), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(_striker_pivot, "basis", _striker_rest, 0.18).set_trans(Tween.TRANS_SINE)
	match mode:
		Mode.SMITH, Mode.SMELT:
			Audio.play_3d("clink", at, -2.0, randf_range(0.95, 1.1) if good else 0.8)
			Effects.chips(self, at, Color(1.0, 0.6, 0.2), 8 if good else 3, 0.02, 3.0)   # sparks
		Mode.CARVE:
			if step_id() == "shape":
				Audio.play_3d("chop", at, -4.0, randf_range(1.1, 1.3) if good else 0.9)
				Effects.chips(self, at, Color(0.72, 0.55, 0.36), 7 if good else 3, 0.03, 2.0)   # shavings
			else:
				Audio.play_3d("thud", at, -4.0, 1.2)
		Mode.KNAP:
			Audio.play("clink", -6.0, randf_range(1.3, 1.5) if good else 1.0)
			Effects.chips(_holder(), at, Color(0.55, 0.56, 0.6), 6 if good else 2, 0.015, 1.2)   # flakes


## On to the next step (the view moves if it needs to), or the item's done.
func _next_step() -> void:
	step_t = 1.0
	if step + 1 >= steps.size():
		_finish_item()
		return
	step += 1
	step_t = 0.0
	cue_t = 0.0
	_drops = 0
	fill = 0.0
	wrap_vec = Vector2(0, -60)
	_last_stage = ""
	_busy = true
	_refresh()
	_setup_striker()
	_go_to_view(func() -> void: _busy = false)


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


## The finished thing, where the work was.
func _show_done() -> void:
	feedback = {"text": "Made %s" % ItemDB.display_name(recipe.out), "color": Color(1.0, 0.95, 0.8), "age": 0.0}
	Audio.play(Audio.sfx.pickup, -4.0)
	_done = true
	if _part:
		_part.visible = false
	if _glow:
		_glow.visible = false
	_tint_mat.set_shader_parameter("tint_color", Color.WHITE)
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
	_go_to_view(func() -> void: _busy = false)


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

## Plays the current step well (for the automated tests): strikes at the best moment, keeps the heat in the band,
## circles for a binding, pours to the line.
func autoplay(_delta: float) -> void:
	if _busy or _closing:
		test_hold = false
		return
	match mech():
		Mech.PUMP:
			test_hold = heat < 0.72
		Mech.POUR:
			test_hold = fill < 0.87
		Mech.WRAP:
			wrap_input(wrap_vec.rotated(0.3) - wrap_vec)
		_:
			test_hold = false
			if _lock > 0.0:
				return
			var ready := false
			match mech():
				Mech.DIAL: ready = absf(cue_t - 0.85) < 0.03
				Mech.SWEEP:
					target = clampf(sweep_pos(), 0.15, 0.85)
					ready = absf(sweep_pos() - target) < 0.01
				Mech.DROP: ready = absf(sweep_pos() - 0.5) < 0.03
				_: ready = absf(cue_t - 1.0) < 0.04
			if ready:
				strike()



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
