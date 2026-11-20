extends Node3D
## Keeps a living population around the focus point (the player, or the menu camera):
## herds of grazers and beasts, critters in the grass, and bird flocks overhead.
## Animals far away are removed and new ones appear out of sight.

@export var max_animals := 14
@export var max_critters := 8
@export var max_flocks := 2
@export var max_perchers := 2   ## groups of birds sitting about in the trees and on logs
@export var max_small := 5      ## frogs, lizards and snakes near the player

var focus: Node3D
var player: Node3D

var _animals: Array[Node3D] = []
var _by_net_id := {}           ## host: net id -> Animal; guest: net id -> puppet
var _next_net_id := 1
var _puppet_seen := {}         ## guest: net id -> seconds since last update
var _critters: Array[Node3D] = []
var _flocks: Array[Node3D] = []
var _perchers: Array[Node3D] = []
var _timer := 0.0
var _lair_beasts := {}         ## host: lair index -> its beast
var _lair_cleared := {}        ## host: lair index -> play time its beast was killed (it returns after a while)
const LAIR_WAKE := 45.0        ## a lair's beast is there when someone comes this close
const LAIR_RETURN := 1200.0    ## seconds before a killed lair beast's place is taken again
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	Game.world_changed.connect(clear)


func clear() -> void:
	for list in [_animals, _critters, _flocks, _perchers]:
		for n in list:
			n.queue_free()
		list.clear()
	_by_net_id.clear()
	_puppet_seen.clear()
	_lair_beasts.clear()
	_lair_cleared.clear()


func find_animal(id: int) -> Node:
	var a: Node = _by_net_id.get(id)
	return a if is_instance_valid(a) else null


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
	_cull(_critters, center, 75.0)
	_cull(_flocks, center, 320.0)
	_cull(_perchers, center, 90.0)
	if Net.is_client():
		# Animals are the host's; critters and birds are just scenery, so each game has its own.
		_age_puppets(0.5)
	else:
		# Keep herds around every player (the host simulates them all).
		var centers: Array = [center]
		var targets: Array = [player]
		if Net.is_host():
			targets = Net.animal_targets()
			for t in targets:
				if t != player and t != focus:
					centers.append((t as Node3D).global_position)
		_cull_multi(_animals, centers, 210.0)
		for a in _animals:
			if is_instance_valid(a):
				a.targets = targets
		if _animals.size() < max_animals + (centers.size() - 1) * 8:
			var c: Vector3 = centers[_rng.randi() % centers.size()]
			if _rng.randf() < 0.3:
				_spawn_shore(c)
			else:
				_spawn_herd(c)
		var small := 0
		for a in _animals:
			if is_instance_valid(a) and (a as Animal).species.role == "small":
				small += 1
		if small < max_small:
			_spawn_small(centers[_rng.randi() % centers.size()])
		_tend_lairs(centers)
	if _critters.size() < max_critters:
		_spawn_critter(center)
	if _flocks.size() < max_flocks:
		_spawn_flock(center)
	if _perchers.size() < max_perchers:
		_spawn_perchers(center)


func _cull_multi(list: Array[Node3D], centers: Array, max_dist: float) -> void:
	for i in range(list.size() - 1, -1, -1):
		var n := list[i]
		if not is_instance_valid(n):
			list.remove_at(i)
			continue
		var near := false
		for c: Vector3 in centers:
			var d := n.global_position - c
			d.y = 0.0
			if d.length() <= max_dist:
				near = true
				break
		if not near:
			_by_net_id.erase(n.get("net_id"))
			n.queue_free()
			list.remove_at(i)


# --- Guest side: puppets mirroring the host's animals --------------------------------------

## [[net id, species index, position, yaw, state, dead], ...] from the host.
func apply_puppets(list: Array) -> void:
	for e: Array in list:
		var id: int = e[0]
		var a: Animal = find_animal(id)
		if not a:
			var si: int = e[1]
			if si < 0 or si >= Game.fauna.species.size():
				continue
			a = Animal.new()
			add_child(a)
			a.setup(Game.fauna.species[si], e[2], player)
			a.net_id = id
			a.species_index = si
			a.puppet = true
			a.rotation.y = e[3]
			a._net_pos = e[2]
			a._net_yaw = e[3]
			_by_net_id[id] = a
			_animals.append(a)
			a.removed.connect(func(x: Animal) -> void:
				_animals.erase(x)
				_by_net_id.erase(x.net_id))
		a.net_update(e[2], e[3], e[4], e[5])
		_puppet_seen[id] = 0.0


func puppet_event(id: int, what: String) -> void:
	var a: Animal = find_animal(id)
	if not a:
		return
	match what:
		"hit": a.puppet_hit()
		"consumed": a.consume_carcass()


## Puppets the host stopped sending (despawned, or out of range) fade away.
func _age_puppets(dt: float) -> void:
	for id: int in _puppet_seen.keys():
		_puppet_seen[id] += dt
		if _puppet_seen[id] > 2.0:
			_puppet_seen.erase(id)
			var a: Node = find_animal(id)
			_by_net_id.erase(id)
			if a:
				_animals.erase(a)
				a.queue_free()


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
		if h > 2.5 and h < 50.0 and Game.world_gen.get_normal(x, z).y > 0.82 and not Game.world_gen.near_river(x, z, 1.0):
			return Vector3(x, h, z)
	return null


## Pick a species that likes the biome at this spot.
func _pick_species(roles: Array, pos: Vector3) -> FaunaLibrary.Species:
	var gen: WorldGen = Game.world_gen
	var weights := gen.biome_weights_at(pos.x, pos.z, pos.y)
	var options: Array = []
	var total := 0.0
	# Altitude biomes aren't in the climate weights: add them so mountain species turn up there.
	if pos.y > 52.0:
		weights[WorldGen.Biome.HIGHLANDS] = 1.5
	if pos.y > 74.0:
		weights[WorldGen.Biome.SNOW] = 1.5
	var night := Game.is_night()
	for s in Game.fauna.species:
		if s.role in roles and s.habitat != "cave":   # cave beasts only turn up in their lairs
			var w := 0.0
			for b: int in weights:
				w += weights[b] * s.biome_pref.get(b, 0.02)
			# Night animals mostly come out after dark, day animals stay hidden at night.
			if (s.active == "night" and not night) or (s.active == "day" and night):
				w *= 0.12
			options.append([s, w])
			total += w
	var roll := _rng.randf() * total
	for o: Array in options:
		roll -= o[1]
		if roll <= 0.0:
			return o[0]
	return options[-1][0] if not options.is_empty() else null


func _spawn_herd(center: Vector3, at: Variant = null, sp: FaunaLibrary.Species = null) -> void:
	var spot: Variant = at if at != null else _ring_spot(center, 70.0, 150.0)
	if spot == null:
		return
	# Territorial beasts are rarer than grazers.
	if sp == null:
		var roles := ["defensive"] if _rng.randf() < 0.25 else ["grazer"]
		sp = _pick_species(roles, spot)
	if not sp:
		return
	# One herd shares a member list (for spreading alarm) and follows its first animal.
	var herd: Array = []
	for i in _rng.randi_range(sp.herd.x, sp.herd.y):
		var p: Vector3 = spot + Vector3(_rng.randf_range(-6, 6), 0, _rng.randf_range(-6, 6))
		var h: float = Game.world_gen.get_height(p.x, p.z)
		if not sp.swims and (h < 2.0 or Game.world_gen.near_river(p.x, p.z, 0.5)):
			continue
		if sp.swims and h < -4.0:
			continue
		var a := Animal.new()
		add_child(a)
		a.setup(sp, Vector3(p.x, h, p.z), player)
		a.net_id = _next_net_id
		a.species_index = Game.fauna.species.find(sp)
		_by_net_id[a.net_id] = a
		_next_net_id += 1
		a.herd = herd
		a.leader = herd[0] if not herd.is_empty() else null
		herd.append(a)
		a.removed.connect(func(x: Animal) -> void:
			_animals.erase(x)
			_by_net_id.erase(x.net_id))
		_animals.append(a)


## Cave beasts: one in each lair someone is near (unless it was killed not long ago).
func _tend_lairs(centers: Array) -> void:
	var plan: Dictionary = Game.world_gen.caves if Game.world_gen else {}
	if not plan.has("lairs"):
		return
	var sp: FaunaLibrary.Species = null
	for s in Game.fauna.species:
		if s.habitat == "cave":
			sp = s
	if sp == null:
		return
	for i in plan.lairs.size():
		var lair: Vector3 = plan.lairs[i]
		var b: Variant = _lair_beasts.get(i)
		if b != null and is_instance_valid(b):
			if (b as Animal).dead and not _lair_cleared.has(i):
				_lair_cleared[i] = Game.play_time
			continue
		_lair_beasts.erase(i)
		if _lair_cleared.has(i) and Game.play_time - float(_lair_cleared[i]) < LAIR_RETURN:
			continue
		_lair_cleared.erase(i)
		var near := false
		for c: Vector3 in centers:
			if c.distance_to(lair) < LAIR_WAKE:
				near = true
		if not near:
			continue
		var a := Animal.new()
		add_child(a)
		a.setup(sp, lair, player)
		a.net_id = _next_net_id
		a.species_index = Game.fauna.species.find(sp)
		_by_net_id[a.net_id] = a
		_next_net_id += 1
		a.removed.connect(func(x: Animal) -> void:
			_animals.erase(x)
			_by_net_id.erase(x.net_id))
		_animals.append(a)
		_lair_beasts[i] = a


## Animals of the water's edge (otters, herons, frogs, seals, penguins) along a river bank or a shore.
func _spawn_shore(center: Vector3) -> void:
	var gen: WorldGen = Game.world_gen
	for i in 10:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(50.0, 140.0)
		var x := center.x + cos(a) * d
		var z := center.z + sin(a) * d
		if x < 10.0 or z < 10.0 or x > Game.WORLD_SIZE - 10.0 or z > Game.WORLD_SIZE - 10.0:
			continue
		var h := gen.get_height(x, z)
		var shore := (h > 0.2 and h < 2.2) or (h > 2.0 and gen.near_river(x, z, 4.0) and not gen.near_river(x, z, -0.5))
		if not shore:
			continue
		var weights := gen.biome_weights_at(x, z, h)
		var options: Array = []
		var total := 0.0
		for s in Game.fauna.species:
			if s.habitat != "water" or s.role == "bird":
				continue
			var w := 0.05
			for b: int in weights:
				w += weights[b] * s.biome_pref.get(b, 0.0)
			options.append([s, w])
			total += w
		var roll := _rng.randf() * total
		for o: Array in options:
			roll -= o[1]
			if roll <= 0.0:
				_spawn_herd(center, Vector3(x, h, z), o[0])
				return
		return


## Small animals (frogs, lizards, snakes) a little way off: they keep near the ground and out of the way.
func _spawn_small(center: Vector3) -> void:
	var spot: Variant = _ring_spot(center, 30.0, 70.0)
	if spot == null:
		return
	var sp := _pick_species(["small"], spot)
	if sp:
		_spawn_herd(center, spot, sp)


func _spawn_perchers(center: Vector3) -> void:
	var spot: Variant = _ring_spot(center, 18.0, 45.0)
	if spot == null:
		return
	var weights := Game.world_gen.biome_weights_at(spot.x, spot.z, spot.y)
	var options: Array = []
	var total := 0.0
	for s in Game.fauna.species:
		if s.role != "bird" or s.bird_kind != "perch":
			continue
		var w := 0.0
		for b: int in weights:
			w += weights[b] * s.biome_pref.get(b, 0.0)
		if w > 0.05:
			options.append([s, w])
			total += w
	if options.is_empty():
		return
	var roll := _rng.randf() * total
	var pick: FaunaLibrary.Species = options[-1][0]
	for o: Array in options:
		roll -= o[1]
		if roll <= 0.0:
			pick = o[0]
			break
	var g := PerchBirds.new()
	add_child(g)
	if g.setup(pick, spot, player):
		_perchers.append(g)
	else:
		g.queue_free()


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
	# Vultures over the dry lands; otherwise one of the circling kinds.
	var weights := Game.world_gen.biome_weights_at(spot.x, spot.z, spot.y)
	var dry: float = weights.get(WorldGen.Biome.DESERT, 0.0) + weights.get(WorldGen.Biome.BADLANDS, 0.0) + weights.get(WorldGen.Biome.DRYLANDS, 0.0)
	var birds := Game.fauna.by_role("bird").filter(func(b: FaunaLibrary.Species) -> bool: return b.bird_kind == ("soar" if dry > 0.5 and _rng.randf() < 0.6 else "flock"))
	if birds.is_empty():
		birds = Game.fauna.by_role("bird").filter(func(b: FaunaLibrary.Species) -> bool: return b.bird_kind == "flock")
	if birds.is_empty():
		return
	var f := BirdFlock.new()
	add_child(f)
	f.setup(birds[_rng.randi() % birds.size()], spot + Vector3.UP * 30.0)
	_flocks.append(f)
