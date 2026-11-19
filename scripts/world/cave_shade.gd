class_name CaveShade
extends Node
## Keeps the sky's light off a thing while it's in a cave: add one as a child of anything that moves (the held item,
## animals, other players, dropped items) and it tells the painted material how much open sky the spot sees
## (Caves.sky_seen). Torches, fires and glowing fungus aren't touched, and nothing changes in the open, so caves are
## dark by their own shape rather than by dimming the world. Things that never move use CaveShade.apply() once.

const EVERY := 0.4   ## seconds between looks (the light changes slowly as you walk in)

var _cd := 0.0
var _sky := 1.0


func _ready() -> void:
	_cd = randf() * EVERY   # spread the looks of many things over time


func _process(delta: float) -> void:
	_cd -= delta
	if _cd > 0.0:
		return
	_cd = EVERY
	var host := get_parent() as Node3D
	if host == null or not host.is_inside_tree():
		return
	var sky := at(host.global_position)
	# In a cave the look is repeated every time, so models swapped in since (another item in hand) get it too.
	if absf(sky - _sky) > 0.01 or sky < 0.99:
		_sky = sky
		apply(host, sky)


## How much open sky the spot at `p` sees (1 in the open).
static func at(p: Vector3) -> float:
	if Game.world_gen == null:
		return 1.0
	return Caves.sky_seen(Game.world_gen.caves, p)


## Set how much sky reaches every model under `node`.
static func apply(node: Node, sky: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).set_instance_shader_parameter("sky_seen", sky)
	for c in node.get_children():
		apply(c, sky)
