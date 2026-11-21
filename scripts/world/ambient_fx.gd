class_name AmbientFx
extends Node3D
## The air around you: fireflies on warm nights, leaves coming down in the woods, snow in the cold places and dust
## blowing in the dry ones. A few emitters that follow the camera (their bits stay where they are in the world), each
## started and stopped by where you are and the time of day. Nothing outside: none of it in caves.

const CHECK := 0.5   ## seconds between looks at the biome

const FIREFLY_BIOMES := [WorldGen.Biome.MEADOW, WorldGen.Biome.FOREST, WorldGen.Biome.AUTUMN, WorldGen.Biome.MARSH, WorldGen.Biome.JUNGLE]
const LEAF_BIOMES := [WorldGen.Biome.FOREST, WorldGen.Biome.AUTUMN, WorldGen.Biome.JUNGLE, WorldGen.Biome.TAIGA]
const SNOW_BIOMES := [WorldGen.Biome.SNOW, WorldGen.Biome.TUNDRA]
const DUST_BIOMES := [WorldGen.Biome.DESERT, WorldGen.Biome.BADLANDS, WorldGen.Biome.DRYLANDS]

var _fx := {}       ## name -> CPUParticles3D
var _want := {}     ## name -> strength 0..1 (0 = off)
var _check := 0.0
var _biome := -1


func _ready() -> void:
	_add("fireflies", Effects.fireflies(), Vector3(0, 0.8, 0))
	_add("leaves", Effects.falling_leaves(), Vector3(0, 7.0, 0))
	_add("snow", Effects.snowfall(), Vector3(0, 7.0, 0))
	_add("dust", Effects.dust_drift(), Vector3(0, 1.4, 0))
	_add("mist", Effects.mist(), Vector3(0, 0.9, 0))
	var motes := Effects.motes(Vector3(5, 1.6, 5), Color(0.4, 0.37, 0.33), 40)   # dust hanging in the still air of caves
	motes.emitting = false
	_add("cave_dust", motes, Vector3(0, 0.4, 0))


func _add(key: String, p: CPUParticles3D, offset: Vector3) -> void:
	p.position = offset
	p.name = key
	add_child(p)
	_fx[key] = p
	_want[key] = 0.0


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or Game.world_gen == null:
		return
	var eye := cam.global_position
	global_position = Vector3(eye.x, Game.world_gen.get_height(eye.x, eye.z), eye.z) if not Game.in_cave else eye
	_check -= delta
	if _check <= 0.0:
		_check = CHECK
		_decide(eye)
	# Started and stopped, not faded: once on they fill in over a lifetime, and once off the last ones live out
	# theirs. How thick (snow on the heights is light) is in their colour's alpha.
	for key: String in _fx:
		var p: CPUParticles3D = _fx[key]
		var want: float = _want[key]
		if (want > 0.0) != p.emitting:
			p.emitting = want > 0.0
		if want > 0.0 and not is_equal_approx(p.color.a, want):
			p.color = Color(1, 1, 1, want)


func _decide(eye: Vector3) -> void:
	for key: String in _want:
		_want[key] = 0.0
	if Settings.quality == "Low":
		return
	if Game.in_cave:
		_want.cave_dust = 1.0
		return
	var b := Game.world_gen.get_biome(eye.x, eye.z)
	var night := 1.0 - Game.daylight()
	if b in FIREFLY_BIOMES:
		_want.fireflies = smoothstep(0.55, 0.85, night)
	if b in LEAF_BIOMES:
		_want.leaves = 1.0
	if b in SNOW_BIOMES:
		_want.snow = 1.0
	elif b == WorldGen.Biome.HIGHLANDS or b == WorldGen.Biome.TAIGA:
		_want.snow = 0.25
	if b == WorldGen.Biome.JUNGLE or b == WorldGen.Biome.MARSH:
		_want.mist = 1.0 if b == WorldGen.Biome.JUNGLE else 0.6
	if b in DUST_BIOMES:
		_want.dust = 0.7 if b == WorldGen.Biome.DRYLANDS else 1.0
	if b != _biome:
		_biome = b
		var pal: WorldPalette = Game.palette
		match b:
			WorldGen.Biome.AUTUMN:
				var cols := pal.autumn_leaves
				if cols.size() > 1:   # each leaf somewhere between the autumn colours
					(_fx.leaves as CPUParticles3D).color_initial_ramp = Effects._ramp(cols[0], cols[cols.size() - 1])
				else:
					_leaf_tint(pal.oak_leaves)
			WorldGen.Biome.JUNGLE:
				_leaf_tint(pal.jungle_leaves)
			WorldGen.Biome.TAIGA:
				_leaf_tint(pal.fir_leaves.lightened(0.1))
			_:
				_leaf_tint(pal.oak_leaves)
		var dust_col := pal.badlands_ochre if b == WorldGen.Biome.BADLANDS else (pal.desert_sand if b == WorldGen.Biome.DESERT else pal.dry_grass)
		Effects.tint_ambient(_fx.dust, dust_col.lightened(0.15), 0.45)


func _leaf_tint(c: Color) -> void:
	(_fx.leaves as CPUParticles3D).color_initial_ramp = Effects._ramp(c.lightened(0.1), c.darkened(0.15))
