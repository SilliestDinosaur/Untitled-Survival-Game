extends Node3D
## Keeps a living population around the focus point (the player, or the menu camera):
## herds of grazers and beasts, critters in the grass, and bird flocks overhead.
## Animals far away are removed and new ones appear out of sight.

@export var max_animals := 14
@export var max_critters := 8
@export var max_flocks := 2

var focus: Node3D
var player: Node3D

var _animals: Array[Node3D] = []
var _critters: Array[Node3D] = []
var _flocks: Array[Node3D] = []
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Game.world_changed.connect(clear)


func clear() -> void:
	for list in [_animals, _critters, _flocks]:
		for n in list:
			n.queue_free()
		list.clear()


func get_animals() -> Array[Node3D]:
	return _animals


func _physics_process(delta: float) -> void:
	if not focus or not Game.fauna:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var center := focus.global_position
	_cull(_animals, center, 210.0)
	_cull(_critters, center, 75.0)
	_cull(_flocks, center, 320.0)
	if _animals.size() < max_animals:
		_spawn_herd(center)
	if _critters.size() < max_critters:
		_spawn_critter(center)
	if _flocks.size() < max_flocks:
		_spawn_flock(center)


func _cull(list: Array[Node3D], center: Vector3, max_dist: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var n := list[i]
		if not is_instance_valid(n):
			list.remove_at(i)
			continue
		var d := n.global_position - center
		d.y = 0.0
		if d.length() > max_dist:
			n.queue_free()
			list.remove_at(i)


## A random spot on land in a ring around the center (out of view distance for herds).
func _ring_spot(center: Vector3, near: float, far: float) -> Variant:
	for i in 6:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(near, far)
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		if x < 10.0 or z < 10.0 or x > Game.WORLD_SIZE - 10.0 or z > Game.WORLD_SIZE - 10.0:
			continue
		var h: float = Game.world_gen.get_height(x, z)
		if h > 2.5 and h < 50.0 and Game.world_gen.get_normal(x, z).y > 0.82:
			return Vector3(x, h, z)
	return null


## Pick a species that likes the biome at this spot.
func _pick_species(roles: Array, pos: Vector3) -> FaunaLibrary.Species:
	var gen: WorldGen = Game.world_gen
	var weights := gen.get_biome_weights(gen.get_climate(pos.x, pos.z, pos.y))
	var options: Array = []
	var total := 0.0
	for s in Game.fauna.species:
		if s.role in roles:
			var w := 0.0
			for b: int in weights:
				w += weights[b] * s.biome_pref.get(b, 0.3)
			options.append([s, w])
			total += w
	var roll := _rng.randf() * total
	for o: Array in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return options[-1][0] if not options.is_empty() else null


func _spawn_herd(center: Vector3) -> void:
	var spot: Variant = _ring_spot(center, 70.0, 150.0)
	if spot == null:
		return
	# Territorial beasts are rarer than grazers.
	var roles := ["defensive"] if _rng.randf() < 0.25 else ["grazer"]
	var sp := _pick_species(roles, spot)
	if not sp:
		return
	for i in _rng.randi_range(sp.herd.x, sp.herd.y):
		var p: Vector3 = spot + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		var h: float = Game.world_gen.get_height(p.x, p.z)
		if h < 2.0:
			continue
		var a := Animal.new()
		add_child(a)
		a.setup(sp, Vector3(p.x, h, p.z), player)
		a.removed.connect(func(x: Animal) -> void: _animals.erase(x))
		_animals.append(a)


func _spawn_critter(center: Vector3) -> void:
	var spot: Variant = _ring_spot(center, 25.0, 60.0)
	if spot == null:
		return
	var sp := _pick_species(["critter"], spot)
	if not sp:
		return
	var c := Critter.new()
	add_child(c)
	c.setup(sp, spot, player)
	_critters.append(c)


func _spawn_flock(center: Vector3) -> void:
	var spot: Variant = _ring_spot(center, 60.0, 200.0)
	if spot == null:
		return
	var birds := Game.fauna.by_role("bird")
	if birds.is_empty():
		return
	var f := BirdFlock.new()
	add_child(f)
	f.setup(birds[_rng.randi() % birds.size()], spot + Vector3.UP * 30.0)
	_flocks.append(f)
