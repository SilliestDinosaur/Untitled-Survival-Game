class_name Animal
extends Node3D
## A four- (or two-) legged creature. Moves along the terrain (no physics, to stay cheap),
## steers around cliffs, water and trees, and reacts to the player according to its temperament:
## calm ones barely care, wary ones watch you then leave, skittish ones bolt, curious ones come
## closer. Herds share alarm. Territorial beasts warn first, then charge with a telegraphed hit.

signal removed(animal: Animal)

enum State { IDLE, GRAZE, WANDER, ALERT, FLEE, WARN, ATTACK, DEAD, HUNT, EAT, TREE, REST, DRINK }

var species: FaunaLibrary.Species
var hp := 10.0
var dead := false
var carcass_hp := 0.0
var state := State.IDLE
var player: Node3D
var herd: Array = []          ## other members of this herd (shared array)
var leader: Animal = null     ## herd leader (null = I lead)
## Multiplayer: the host's id for this animal; on guests, animals are puppets that follow the
## host's positions instead of thinking for themselves.
var net_id := -1
var species_index := -1
var puppet := false
var targets: Array = []       ## players to notice (host with guests); empty = just `player`
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _target_cd := 0.0

var _body: Node3D
var _head: Node3D
var _legs: Array[Node3D] = []
var _target := Vector3.ZERO
var _timer := 0.0
var _speed := 0.0
var _yaw := 0.0
var _desired_yaw := 0.0
var _gait := 0.0
var _attack_cd := 0.0
var _windup := -1.0
var _call_cd := 0.0
var _steer_cd := 0.0
var _look_yaw := 0.0
var _look_target := 0.0
var _look_cd := 0.0
var _breath := 0.0
var _rng := RandomNumberGenerator.new()
var _collider: StaticBody3D
var _world: Node
var _leg_base: Array[Vector3] = []   ## each leg's resting place on the body (they lift off it as they step)
var _startle := 0.0           ## a jump when something gives it a fright, easing away
var _flinch := Vector2.ZERO   ## a blow's knock (roll, pitch), easing away
var _lunge := 0.0             ## an attack's lunge forward, easing away
var home_pos := Vector3.ZERO   ## cave beasts: their lair (they never stray far from it)
# Predators and prey.
var _threat: Node3D = null      ## what it's running from (the player, or a predator)
var _prey: Animal = null        ## what it's hunting
var _hunger := 0.0              ## seconds until a predator feels like hunting
# Serpents: their body follows the head's trail.
var _segs: Array[Node3D] = []
var _gait_rot := Vector2.ZERO   ## the body-type sway (pitch, roll) added this frame, taken off again before the next
var _tail: Node3D
var _tail_t := 0.0
var _swish := 0.0               ## a quick flick of the tail (at flies), easing away
var _fidget := 0.0              ## a head shake, easing away
var _fidget_cd := 0.0
var _rest := 0.0                ## 0 standing .. 1 lying down (eased)
var _asleep := false
var young := false              ## a young one: small, keeps close to its mother (the herd's leader)
var _reach: PackedFloat32Array = []   ## each leg's stretch to meet the ground under its foot (1 = its own length)
var _reach_cd := 0.0
var _trail: Array[Vector3] = []
# Climbers: up a tree.
var in_tree := false
var _tree_top := Vector3.ZERO   ## where it sits in the canopy
var _tree_phase := ""           ## to_trunk | up | sit | hop | down
var _tree_res := {}             ## the tree it's in (it drops down if the tree is felled)
var _found_res := {}
var _hop_from := Vector3.ZERO
var _hop_t := 0.0
const TREE_TOPS := {"kapok": 20.0, "jungle_tree": 8.5, "oak": 5.0, "autumn_oak": 5.0, "birch": 6.0, "willow": 4.5, "acacia": 4.5, "palm": 6.5, "pine": 6.0, "fir": 7.0}
var _cave := false
const LAIR_LEASH := 14.0


func setup(sp: FaunaLibrary.Species, pos: Vector3, p: Node3D) -> void:
	species = sp
	player = p
	hp = sp.hp
	_cave = sp.habitat == "cave"
	home_pos = pos
	_rng.randomize()
	_yaw = _rng.randf() * TAU
	_desired_yaw = _yaw
	position = pos
	_breath = _rng.randf() * TAU
	_call_cd = _rng.randf_range(4.0, 20.0)

	_hunger = _rng.randf_range(40.0, 200.0)
	_body = Node3D.new()
	_body.position.y = _base_y()
	add_child(_body)
	add_child(CaveShade.new())   # darker when it wanders into a cave
	_body.add_child(_mesh(sp.body_mesh))
	_head = Node3D.new()
	_head.position = sp.head_pivot
	_head.add_child(_mesh(sp.head_mesh))
	_body.add_child(_head)
	if sp.tail_mesh:
		_tail = Node3D.new()
		_tail.position = sp.tail_pivot
		_tail.add_child(_mesh(sp.tail_mesh))
		_body.add_child(_tail)
	for off in sp.leg_offsets:
		var leg := Node3D.new()
		leg.position = off
		var hind: bool = off.z > 0.0 and sp.leg_offsets.size() == 4 and sp.hind_leg_mesh != null
		leg.add_child(_mesh(sp.hind_leg_mesh if hind else sp.leg_mesh))
		if sp.body == "sprawl":   # lizards: legs out to the sides
			leg.rotation.z = 0.9 if off.x > 0.0 else -0.9
		_body.add_child(leg)
		_legs.append(leg)
		_leg_base.append(off)

	# A serpent's body: segments that follow along the head's trail (placed in the world, see _animate).
	for i in sp.segs:
		var seg := Node3D.new()
		seg.top_level = true
		seg.add_child(_mesh(sp.seg_mesh))
		var k := 1.0 - float(i) / float(sp.segs) * 0.6   # tapering to the tail
		seg.scale = Vector3(k, k, 1.0)
		add_child(seg)
		seg.global_position = pos
		_segs.append(seg)
	# Hit box on the "interact" layer: the crosshair and tools can hit it, the player walks through.
	_collider = StaticBody3D.new()
	_collider.collision_layer = TerrainChunk.LAYER_INTERACT
	_collider.collision_mask = 0
	_collider.set_meta("animal", self)
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(sp.body_w * 1.2, 0.4), sp.body_h * 1.2 + sp.leg_len * 0.6, maxf(sp.body_len * 1.3, 0.5))
	# Small things still get a box you can hit (a frog's own would be a few centimetres tall).
	shape.size = Vector3(maxf(shape.size.x, 0.45), maxf(shape.size.y, 0.4), maxf(shape.size.z, 0.5))
	if sp.body == "serpent":
		shape.size = Vector3(0.6, 0.4, 0.8)
	elif sp.body == "upright":
		shape.size = Vector3(sp.body_w * 1.3, sp.body_h * 1.1, sp.body_w * 1.3)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = Vector3(0, sp.body_h * 0.6 - shape.size.y * 0.5, -sp.body_len * 0.1)
	_collider.add_child(cs)
	_body.add_child(_collider)
	_enter(State.GRAZE if _rng.randf() < 0.6 else State.IDLE)


## How high the body rides above the ground, by body type.
func _base_y() -> float:
	match species.body:
		"serpent": return species.body_h * 0.45
		"upright": return species.leg_len
		"seal": return species.body_h * 0.3
		"frog": return species.leg_len * 2.0 + species.body_h * 0.35
	return species.leg_len + species.body_h * 0.25


func _mesh(m: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = m
	return mi


func _enter(s: State) -> void:
	if s in [State.ALERT, State.FLEE] and state in [State.IDLE, State.GRAZE, State.WANDER, State.REST, State.DRINK]:
		_startle = 1.0   # it jumps
	if s != State.REST:
		_asleep = false
	state = s
	if s == State.ATTACK:
		Music.combat_ping(1.0)
	match s:
		State.IDLE:
			_timer = _rng.randf_range(2.0, 5.0)
		State.GRAZE:
			_timer = _rng.randf_range(5.0, 12.0)
		State.WANDER:
			_timer = 25.0
			_pick_wander_target()
		State.ALERT:
			_timer = _rng.randf_range(1.2, 2.5)
		State.FLEE:
			_timer = _rng.randf_range(5.0, 8.0)
			# Prey bolting from a nearby player sets the hunting mood (a little).
			if player and position.distance_to(player.global_position) < 25.0:
				Music.hunt_ping(0.15)
		State.WARN:
			_timer = 4.0
		State.ATTACK:
			_timer = 12.0
			_windup = -1.0
		State.HUNT:
			_timer = 16.0
			_call(0.8)
		State.EAT:
			_timer = _rng.randf_range(12.0, 20.0)
		State.TREE:
			_timer = _rng.randf_range(20.0, 50.0)
		State.REST:
			_timer = _rng.randf_range(25.0, 60.0) if _asleep else _rng.randf_range(10.0, 25.0)
		State.DRINK:
			_drinking = false
			_timer = 25.0   # (to get to the water; the drink itself is timed when it arrives)
	# Climbers run for a tree when frightened.
	if s == State.FLEE and species.climbs and not in_tree:
		_try_climb.call_deferred()


func _pick_wander_target() -> void:
	# Herd members drift toward their leader instead of wandering off alone.
	if is_instance_valid(leader) and not leader.dead:
		var spread := 2.0 if young else 5.0   # the young keep close by their mother
		_target = leader.position + Vector3(_rng.randf_range(-spread, spread), 0, _rng.randf_range(-spread, spread))
		return
	if _cave:   # pace about the lair
		for i in 6:
			var a := _rng.randf() * TAU
			var t := home_pos + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, LAIR_LEASH * 0.7)
			if not is_nan(_ground_at(t)):
				_target = t
				return
		_target = home_pos
		return
	# Habitat: marsh animals drift toward the water's edge, cliff dwellers toward slopes.
	var best := position
	var best_score := -1e9
	for i in 8:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(8.0, 22.0)
		var t := position + Vector3(cos(a) * d, 0, sin(a) * d)
		var h: float = Game.world_gen.get_height(t.x, t.z)
		var max_h := 80.0 if species.habitat == "steep" else 55.0
		if h >= max_h:
			continue
		if not species.swims and (h <= 2.0 or Game.world_gen.near_river(t.x, t.z, 0.0)):
			continue
		if species.swims and h < -5.0:
			continue
		var score := _rng.randf()
		match species.habitat:
			"water": score += 2.0 - minf(absf(h), 8.0) * 0.25 + (1.5 if Game.world_gen.near_river(t.x, t.z, 3.0) else 0.0)
			"steep": score += (1.0 - Game.world_gen.get_normal(t.x, t.z).y) * 6.0 + h * 0.01
		if score > best_score:
			best_score = score
			best = t
		if species.habitat == "":
			break
	_target = best


## Something scared a herd member: everyone nearby runs (from `from`, if given: a predator; else the player).
func alarm(from: Node3D = null) -> void:
	if dead or species.flee_radius <= 0.0:
		return
	_threat = from
	if in_tree:
		return   # safe up there
	if state != State.FLEE:
		_enter(State.FLEE)
	# Climbers make for a tree.
	if species.climbs:
		_try_climb()


func _alarm_herd() -> void:
	for other in herd:
		if is_instance_valid(other) and other != self and other.position.distance_to(position) < 25.0:
			other.alarm()


func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_step(delta)
		return
	if dead:
		return
	# With several players around, pay attention to whoever is closest.
	_target_cd -= delta
	if _target_cd <= 0.0 and targets.size() > 1:
		_target_cd = 0.5
		var best := 1e9
		for t in targets:
			if is_instance_valid(t):
				var d: float = (t as Node3D).global_position.distance_squared_to(position)
				if d < best:
					best = d
					player = t
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_call_cd -= delta
	_timer -= delta
	var to_player := player.global_position - position if player else Vector3(1e6, 0, 0)
	to_player.y = 0.0
	var dist := to_player.length()
	var sprinting: bool = player != null and bool(player.get("is_sprinting"))
	_perceive(dist, sprinting)
	_hunger -= delta
	if state == State.TREE:
		_tree_step(delta, dist)
		return

	var want_dir := Vector3.ZERO
	var want_speed := 0.0
	var graze := 0.0
	var alert := 0.0
	# A young one that has fallen behind its mother hurries after her.
	var behind := 0.0
	if young and is_instance_valid(leader) and not leader.dead:
		behind = Vector2(leader.position.x - position.x, leader.position.z - position.z).length()
		if behind > 7.0 and state in [State.IDLE, State.GRAZE, State.REST, State.DRINK]:
			_enter(State.WANDER)
	match state:
		State.IDLE, State.GRAZE:
			graze = 1.0 if state == State.GRAZE else 0.0
			if _timer <= 0.0:
				if not _maybe_hunt():
					var sleepy := _sleepy() or (young and is_instance_valid(leader) and leader.state == State.REST)
					if species.climbs and _rng.randf() < 0.3:
						_try_climb()
					elif _can_lie() and _rng.randf() < (0.75 if sleepy else 0.12):
						_asleep = sleepy
						_enter(State.REST)
					elif not sleepy and _rng.randf() < 0.1 and _find_water():
						_enter(State.DRINK)
					else:
						_enter(State.WANDER if _rng.randf() < 0.65 else (State.GRAZE if state == State.IDLE else State.IDLE))
		State.HUNT:
			# Run the prey down; give up if it gets away.
			if not is_instance_valid(_prey) or _prey.dead or _prey.in_tree or _timer <= 0.0:
				_prey = null
				_hunger = _rng.randf_range(30.0, 60.0)
				_enter(State.IDLE)
			else:
				var to_prey := _prey.position - position
				to_prey.y = 0.0
				var pd := to_prey.length()
				if pd > 45.0:
					_prey = null
					_enter(State.IDLE)
				elif pd < 0.8 + species.size * 0.6:
					_lunge = 1.0
					_prey.take_hit(9999.0, position)
					for other in _prey.herd:
						if is_instance_valid(other) and other != _prey:
							(other as Animal).alarm(self)
					_call(0.9)
					_enter(State.EAT)
				else:
					want_dir = to_prey.normalized()
					# A stalk while it's far, a sprint at the end.
					want_speed = species.run_speed * (0.95 if pd < 18.0 else 0.45)
					if pd < _prey.species.flee_radius * 1.4 + 4.0:
						_prey.alarm(self)
		State.EAT:
			graze = 1.0
			if is_instance_valid(_prey):
				var tp := _prey.position - position
				_desired_yaw = atan2(-tp.x, -tp.z)
			if _timer <= 0.0:
				_prey = null
				_hunger = _rng.randf_range(150.0, 320.0)
				_enter(State.WANDER)
		State.REST:
			# Lying down: up again when it's had its rest (or, asleep, when the night's over).
			if _timer <= 0.0:
				if _asleep and _sleepy():
					_timer = _rng.randf_range(20.0, 40.0)
				else:
					_asleep = false
					_enter(State.IDLE)
		State.DRINK:
			var d := _target - position
			d.y = 0.0
			if d.length() > 1.0 and _timer > 12.0:
				want_dir = d.normalized()
				want_speed = species.walk_speed
			elif d.length() > 2.5 and not _drinking:
				_enter(State.IDLE)   # never got there (the way was blocked): no drinking in the middle of a field
			else:
				if not _drinking:
					_drinking = true
					_timer = _rng.randf_range(5.0, 9.0)   # at the water: head down, drinking
					var w := _drink_at - position
					_desired_yaw = atan2(-w.x, -w.z)
				graze = 1.3
				if _timer <= 0.0:
					_drinking = false
					_enter(State.IDLE)
		State.WANDER:
			var d := _target - position
			d.y = 0.0
			if d.length() < 1.2 or _timer <= 0.0:
				_enter(State.GRAZE if _rng.randf() < 0.6 else State.IDLE)
			else:
				want_dir = d.normalized()
				want_speed = species.walk_speed * (2.2 if behind > 7.0 else 1.0)
				if young and behind > 3.0 and is_instance_valid(leader):
					_target = leader.position   # (she's moving: keep heading for her)
		State.ALERT:
			# Stand still, head up, face the player; then decide.
			alert = 1.0
			_desired_yaw = atan2(-to_player.x, -to_player.z)
			if _timer <= 0.0:
				if species.temperament == "curious" and dist > 4.0 and not sprinting:
					_enter(State.WANDER)
					_target = player.global_position - to_player.normalized() * 4.0   # come closer for a look
				elif dist < species.flee_radius:
					_enter(State.FLEE)
					_alarm_herd()
					_call()
				else:
					_enter(State.GRAZE)
		State.FLEE:
			var from := to_player
			var from_dist := dist
			if is_instance_valid(_threat) and _threat != player:
				from = _threat.global_position - position
				from.y = 0.0
				from_dist = from.length()
			want_dir = -from.normalized() if from_dist > 0.01 else Vector3.FORWARD
			want_speed = species.run_speed
			if _timer <= 0.0 and from_dist > species.flee_radius * 1.8:
				_threat = null
				_enter(State.IDLE)
		State.WARN:
			# Territorial: face the intruder, head low, snorting.
			alert = 1.0
			_desired_yaw = atan2(-to_player.x, -to_player.z)
			if _call_cd <= 0.0:
				_call_cd = 1.6
				_call(0.9)
			if dist < (1.9 if species.body == "serpent" else 3.6):
				_enter(State.ATTACK)
			elif dist > (7.0 if species.body == "serpent" else 12.0) or _timer <= 0.0:
				_enter(State.IDLE)
		State.ATTACK:
			if _timer <= 0.0 or dist > 30.0:
				_enter(State.IDLE)
			elif _windup >= 0.0:
				# Rearing back before the hit: the player can see it coming and step away.
				_windup -= delta
				_desired_yaw = atan2(-to_player.x, -to_player.z)
				if _windup < 0.0:
					if dist < 2.0 + species.size * 0.7:
						_bite()
					_attack_cd = 1.2
			elif dist > 1.5 + species.size * 0.6:
				want_dir = to_player.normalized()
				want_speed = species.run_speed
			elif _attack_cd <= 0.0:
				_windup = 0.45
				_call(0.8)

	_move(delta, want_dir, want_speed)
	_animate(delta, graze, alert)

	if _call_cd <= 0.0 and state in [State.IDLE, State.GRAZE, State.WANDER]:
		_call_cd = _rng.randf_range(10.0, 30.0)
		if dist < 60.0:
			_call()


## Makes this one young: two thirds grown (a little bigger-headed would be nice, but scale is what reads), weaker,
## and it keeps close by its mother.
func make_young() -> void:
	young = true
	scale = Vector3.ONE * 0.6
	hp *= 0.5


## Time for sleep: night for animals of the day, day for animals of the night.
func _sleepy() -> bool:
	var night := 1.0 - Game.daylight()
	match species.active:
		"day": return night > 0.6
		"night": return night < 0.3
	return false


## Whether this body can lie down (quadrupeds and the upright ones; snakes, frogs and seals already lie low).
func _can_lie() -> bool:
	return not _cave and species.body in ["quad", "upright"] and not species.swims


var _drink_at := Vector3.ZERO
var _drinking := false
## Water within a short walk (a river, a lake, a pond): heads for the dry bank beside it. False if none near.
func _find_water() -> bool:
	if _cave or species.swims:
		return false
	var g: WorldGen = Game.world_gen
	for i in 12:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(8.0, 30.0)
		var q := position + Vector3(cos(a) * d, 0, sin(a) * d)
		if g.water_level(q.x, q.z) > g.get_height(q.x, q.z) + 0.2:
			# Step back toward here until on dry ground: that's where it stands to drink.
			var back := (position - q).normalized()
			for k in 12:
				var b := q + back * (0.6 * k + 0.6)
				if g.water_level(b.x, b.z) < g.get_height(b.x, b.z) - 0.05 and g.get_normal(b.x, b.z).y > 0.75:
					_target = b
					_drink_at = q
					return true
	return false


## Decide whether the player is worth reacting to.
func _perceive(dist: float, sprinting: bool) -> void:
	if state in [State.FLEE, State.ATTACK, State.DEAD]:
		return
	if species.role == "defensive":
		if state in [State.HUNT, State.EAT, State.TREE]:
			if dist < 6.0:
				_prey = null
				_enter(State.WARN)   # disturbed at its kill
			return
		if dist < (4.5 if species.body == "serpent" else 9.0) and state != State.WARN:
			_enter(State.WARN)
		return
	if state == State.TREE:
		return
	if species.flee_radius <= 0.0:
		return
	var radius := species.flee_radius * (1.7 if sprinting else 1.0)
	if state == State.REST:
		radius *= 0.6 if _asleep else 0.85   # asleep it notices you late (and then jumps up all the faster)
	if dist < radius * 0.45:
		_enter(State.FLEE)   # far too close: bolt immediately
		_alarm_herd()
		_call()
	elif dist < radius and state != State.ALERT:
		if species.temperament == "calm" and not sprinting:
			return   # calm animals don't mind someone walking by
		_enter(State.ALERT)


## Move with a limited turn rate, steering around steep ground, water and trees.
func _move(delta: float, want_dir: Vector3, want_speed: float) -> void:
	_steer_cd -= delta
	if want_dir.length_squared() > 0.000001 and want_speed > 0.0 and _steer_cd <= 0.0:
		_steer_cd = 0.25
		_desired_yaw = _best_heading(want_dir)
	var turn_rate := (4.5 if want_speed > species.walk_speed * 1.5 else 2.2) * delta
	_yaw = rotate_toward(_yaw, _desired_yaw, turn_rate)
	# Slow down while turning sharply, speed up smoothly.
	var facing := cos(angle_difference(_yaw, _desired_yaw))
	_speed = lerpf(_speed, want_speed * clampf(facing, 0.25, 1.0), 1.0 - exp(-3.0 * delta))
	var forward := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var next := position + forward * _speed * delta
	var h: float = _ground_at(next)
	if _speed > 0.01:
		if _walkable(next, h):
			position.x = next.x
			position.z = next.z
			_gait += _speed * delta / maxf(species.leg_len * 1.6, 0.2) * PI   # stride locked to distance
		else:
			_speed *= 0.5
			_steer_cd = 0.0
	var gy := _ground_at(position)
	if not is_nan(gy):
		position.y = lerpf(position.y, gy, 1.0 - exp(-14.0 * delta))
	rotation = Vector3(0, _yaw, 0)


func _walkable(p: Vector3, h: float) -> bool:
	if _cave:   # on the cave floor, no big step up or down, and near the lair
		return not is_nan(h) and absf(h - position.y) < 0.7 and Vector2(p.x - home_pos.x, p.z - home_pos.z).length() < LAIR_LEASH
	if species.swims:   # swimmers go into the water (not out to the deep sea)
		return h > -5.0 and h < 62.0 and (h < 0.5 or Game.world_gen.get_normal(p.x, p.z).y > 0.7)
	# Wading into a river's shallows is fine; its deep middle isn't.
	return h > 1.3 and h < 62.0 and Game.world_gen.get_normal(p.x, p.z).y > 0.7 and h > Game.world_gen.water_level(p.x, p.z) - 0.6


## The ground under p: the surface, or for a cave animal the cave floor (NAN where there's no floor to stand on).
func _ground_at(p: Vector3) -> float:
	if not _cave:
		var h: float = Game.world_gen.get_height(p.x, p.z)
		if species.swims:   # afloat: swimming at the surface
			h = maxf(h, Game.world_gen.water_level(p.x, p.z) - _base_y() - species.body_h * 0.35)
		return h
	var f: Variant = Caves.floor_at(Game.world_gen.caves, Vector3(p.x, position.y + 0.9, p.z))
	return NAN if f == null else (f as Vector3).y - 0.05


## Pick the heading closest to `want` whose next few meters are walkable and free of trees.
func _best_heading(want: Vector3) -> float:
	var base := atan2(-want.x, -want.z)
	var look := maxf(2.5, species.body_len * 2.0)
	var best := base
	var best_score := -1e9
	for off in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]:
		var a: float = base + off
		var dir := Vector3(-sin(a), 0, -cos(a))
		var p := position + dir * look
		var h: float = _ground_at(p)
		if not _walkable(p, h):
			continue
		var score: float = -absf(off) - _obstacle_penalty(p)
		if score > best_score:
			best_score = score
			best = a
	return best


## Trees and rocks near a point (looked up in the loaded chunk's resource list).
func _obstacle_penalty(p: Vector3) -> float:
	if not _world:
		_world = get_node_or_null("/root/Main/World")
		if not _world:
			return 0.0
	var chunk = _world.get_chunk(_world.world_to_chunk(p))
	if not chunk:
		return 0.0
	var penalty := 0.0
	for r in chunk.resources:
		if r.get("removed", false) or not FloraLibrary.KINDS[r.kind].solid:
			continue
		var o: Vector3 = r.transform.origin
		var d := Vector2(o.x - p.x, o.z - p.z).length()
		if d < 1.6:
			penalty += (1.6 - d) * 2.0
	return penalty


func _animate(delta: float, graze: float, alert: float) -> void:
	var stride := clampf(_speed / maxf(species.run_speed, 0.1), 0.0, 1.0)
	var moving := clampf(_speed / 0.4, 0.0, 1.0)
	var swing := (0.32 + stride * 0.4) * moving
	# Walk: diagonal pairs together. Run: front pair and back pair together (bound). The gait slides from one to
	# the other as it speeds up, rather than switching.
	var run := smoothstep(0.38, 0.7, stride)
	var walk_ph := [0.0, PI, PI, 0.0]
	var run_ph := [0.0, 0.3, PI, PI + 0.3]
	for i in _legs.size():
		var off: float = (lerp_angle(walk_ph[i], run_ph[i], run) if _legs.size() == 4 else [0.0, PI][i % 2])
		var ph: float = _gait + off
		_legs[i].rotation.x = lerp_angle(_legs[i].rotation.x, sin(ph) * swing, 1.0 - exp(-20.0 * delta))
		# The foot lifts as the leg swings forward, and is planted as it pushes back.
		if i < _leg_base.size():
			var lift := maxf(cos(ph), 0.0) * 0.07 * species.size * moving
			_legs[i].position.y = lerpf(_legs[i].position.y, _leg_base[i].y + lift, 1.0 - exp(-20.0 * delta))
	# Body: bob with the steps, breathe when still, lean into turns and slopes.
	_breath += delta * 1.7
	var base_y := _base_y()
	var bob := absf(sin(_gait)) * 0.05 * species.size * moving
	_startle = move_toward(_startle, 0.0, delta * 3.0)
	_lunge = move_toward(_lunge, 0.0, delta * 4.0)
	_flinch = _flinch.lerp(Vector2.ZERO, 1.0 - exp(-8.0 * delta))
	var hop := sin(_startle * PI) * 0.14 * species.size
	_body.position.y = base_y + bob + hop + sin(_breath) * 0.006 * species.size * (1.0 - moving)
	_body.position.z = -sin(_lunge * PI) * 0.3 * species.size
	# Take off last frame's body-type sway first, so it never builds up through the easing below.
	_body.rotation.x -= _gait_rot.x
	_body.rotation.z -= _gait_rot.y
	_gait_rot = Vector2.ZERO
	var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
	var side := Vector3(-fwd.z, 0, fwd.x)
	var half := species.body_len * 0.5
	var g: WorldGen = Game.world_gen
	var pitch := 0.0 if _cave else atan2(g.get_height(position.x + fwd.x * half, position.z + fwd.z * half) - g.get_height(position.x - fwd.x * half, position.z - fwd.z * half), species.body_len)
	var roll := 0.0 if _cave else atan2(g.get_height(position.x + side.x * 0.4, position.z + side.z * 0.4) - g.get_height(position.x - side.x * 0.4, position.z - side.z * 0.4), 0.8)
	var turn_lean := clampf(angle_difference(_yaw, _desired_yaw), -0.6, 0.6) * stride * 0.25
	# A walk sways side to side with the steps; a gallop rocks fore and aft.
	var sway := sin(_gait) * 0.035 * moving * (1.0 - run)
	var rock := sin(_gait * 2.0) * 0.07 * moving * run
	_body.rotation.x = lerpf(_body.rotation.x, pitch * 0.8 + rock - _lunge * 0.15, 1.0 - exp(-8.0 * delta)) + _flinch.y
	_body.rotation.z = lerpf(_body.rotation.z, roll * 0.25 + turn_lean + sway, 1.0 - exp(-6.0 * delta)) + _flinch.x
	_leg_reach(delta)

	# Head: down to graze (with nibbles), up and still when alert, occasional glances.
	_look_cd -= delta
	if _look_cd <= 0.0:
		_look_cd = _rng.randf_range(1.5, 4.0)
		_look_target = _rng.randf_range(-0.5, 0.5) if moving < 0.5 and alert < 0.5 else 0.0
	# Alert: it looks at you.
	if alert > 0.5 and player and is_instance_valid(player) and state != State.FLEE:
		var d: Vector3 = player.global_position - global_position
		_look_target = clampf(wrapf(atan2(-d.x, -d.z) - _yaw, -PI, PI), -1.0, 1.0)
	_look_yaw = lerpf(_look_yaw, _look_target * (1.0 - graze), 1.0 - exp(-3.0 * delta))
	var head_pitch := graze * deg_to_rad(58.0) + graze * sin(_breath * 3.0) * 0.04
	if alert > 0.5:
		head_pitch = -0.2 if species.role != "defensive" else deg_to_rad(25.0)
	if state == State.FLEE:
		head_pitch = -0.1
	if _windup >= 0.0:
		head_pitch = deg_to_rad(40.0) * (1.0 - _windup / 0.45)
	head_pitch += sin(_gait * 2.0) * 0.05 * moving   # nodding with the steps
	_head.rotation.x = lerpf(_head.rotation.x, head_pitch, 1.0 - exp(-5.0 * delta))
	_head.rotation.y = _look_yaw
	# Lying down: the body sinks to the ground, the legs fold under it, the head comes down (to the ground, asleep).
	_rest = move_toward(_rest, 1.0 if state == State.REST else 0.0, delta * (0.8 if state == State.REST else 2.5))
	if _rest > 0.001:
		var lie := smoothstep(0.0, 1.0, _rest)
		_body.position.y = lerpf(_body.position.y, species.body_h * 0.42, lie)
		_body.rotation.x = lerpf(_body.rotation.x, 0.0, lie)
		_body.rotation.z = lerpf(_body.rotation.z, 0.06, lie)
		for i in _legs.size():
			var front := _leg_base[i].z < 0.0
			_legs[i].rotation.x = lerpf(_legs[i].rotation.x, -1.35 if front else 1.45, lie)
			_legs[i].scale.y = lerpf(_legs[i].scale.y, 0.75, lie)
		var head_down := deg_to_rad(55.0) if _asleep else deg_to_rad(10.0) + sin(_breath * 0.6) * 0.08
		_head.rotation.x = lerpf(_head.rotation.x, head_down, lie)
		_body.position.y += sin(_breath * 0.7) * 0.012 * species.size * lie   # slow deep breaths
	# The tail: hangs and sways a little with the gait, lifts at a run, swishes lazily when still, now and then a
	# sharp flick (flies); and a shake of the head from time to time.
	_fidget_cd -= delta
	if _fidget_cd <= 0.0 and moving < 0.3 and state in [State.IDLE, State.GRAZE, State.REST]:
		_fidget_cd = _rng.randf_range(3.0, 9.0)
		if _rng.randf() < 0.6:
			_swish = 1.0
		elif not _asleep:
			_fidget = 1.0
	_swish = move_toward(_swish, 0.0, delta * 1.6)
	_fidget = move_toward(_fidget, 0.0, delta * 2.2)
	if _fidget > 0.0:
		_head.rotation.z = sin(_fidget * TAU * 2.0) * 0.25 * _fidget
	else:
		_head.rotation.z = lerpf(_head.rotation.z, 0.0, 1.0 - exp(-8.0 * delta))
	if _tail:
		_tail_t += delta
		var lazy := sin(_tail_t * 1.3 + _breath) * 0.18 * (1.0 - moving)
		var flick := sin(_swish * TAU * 2.5) * 0.9 * _swish
		var trot := sin(_gait) * 0.12 * moving
		_tail.rotation.y = lazy + flick + trot
		_tail.rotation.x = lerpf(_tail.rotation.x, -0.45 * stride - (0.35 if alert > 0.5 else 0.0), 1.0 - exp(-4.0 * delta))
	# How each body type moves.
	match species.body:
		"serpent":
			_slither(moving)
		"upright":
			if state == State.FLEE and species.swims:   # tobogganing along on its belly
				_gait_rot.x = -1.35
				_body.position.y = species.body_w * 0.45
				for leg in _legs:
					leg.rotation.x = 1.2
			else:   # a side-to-side waddle
				_gait_rot.y = sin(_gait) * 0.18 * moving
		"seal":   # humping along on its belly
			_body.position.y += absf(sin(_gait * 0.7)) * species.body_h * 0.3 * moving
			_gait_rot.x = sin(_gait * 0.7) * 0.14 * moving
		"frog":   # hops
			_body.position.y += absf(sin(_gait * 0.5)) * species.size * 1.8 * moving
			_gait_rot.x = -absf(sin(_gait * 0.5)) * 0.4 * moving
	_body.rotation.x += _gait_rot.x
	_body.rotation.z += _gait_rot.y


## Legs reach the ground under their own feet: on a slope the body stays near level across it and each leg
## stretches or shortens to the ground below it, instead of the downhill feet hanging in the air and the uphill ones
## sinking in. Worked out a few times a second (the ground doesn't change fast), eased in between.
func _leg_reach(delta: float) -> void:
	if _legs.is_empty() or _cave or species.leg_len < 0.05 or not species.body in ["quad", "upright"] or _rest > 0.01:
		return
	if _reach.size() != _legs.size():
		_reach.resize(_legs.size())
		_reach.fill(1.0)
	_reach_cd -= delta
	if _reach_cd <= 0.0:
		_reach_cd = _rng.randf_range(0.18, 0.28)
		var g: WorldGen = Game.world_gen
		var ll := species.leg_len
		# Up a tree or afloat, the legs just hang as they are.
		var off_ground := in_tree or (species.swims and g.water_level(position.x, position.z) > g.get_height(position.x, position.z) + 0.15)
		for i in _legs.size():
			if off_ground:
				_reach[i] = 1.0
				continue
			var foot := _body.global_transform * (_leg_base[i] + Vector3(0, -ll, 0))
			var gap := foot.y - g.get_height(foot.x, foot.z)   # + in the air, - under the ground
			_reach[i] = clampf(1.0 + gap / (ll * scale.y), 0.7, 1.45)
	var k := 1.0 - exp(-10.0 * delta)
	for i in _legs.size():
		_legs[i].scale.y = lerpf(_legs[i].scale.y, _reach[i], k)


## A snake's body: the head weaves side to side, and the segments follow along the trail it leaves.
func _slither(moving: float) -> void:
	var sz := species.size
	_body.position.x = sin(_gait * 0.6) * sz * 0.16 * moving
	var head := _body.global_position
	var step := sz * 0.09
	if _trail.is_empty():
		var back := global_transform.basis.z
		for i in _segs.size() * 4 + 6:
			_trail.append(head + back * step * i)
	if _trail[0].distance_to(head) > step:
		_trail.push_front(head)
		if _trail.size() > _segs.size() * 4 + 6:
			_trail.pop_back()
	for i in _segs.size():
		var k := mini((i + 1) * 2, _trail.size() - 1)
		var at: Vector3 = _trail[k]
		var ahead: Vector3 = _trail[maxi(k - 2, 0)]
		var g: float = _ground_at(at)
		if not is_nan(g):
			at.y = g + _base_y() * (1.0 - float(i) / _segs.size() * 0.4)
		var seg := _segs[i]
		var dir := ahead - at
		if dir.length_squared() > 0.000001:
			seg.global_transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis.from_scale(_seg_scale(i)), at)
		else:
			seg.global_position = at


## A serpent segment's size: tapering toward the tail.
func _seg_scale(i: int) -> Vector3:
	var k := 1.0 - float(i) / float(maxi(_segs.size(), 1)) * 0.6
	return Vector3(k, k, 1.0)


## A predator that's hungry looks for something smaller than itself to hunt (now and then, not all the time).
func _maybe_hunt() -> bool:
	if species.diet == "herb" or _hunger > 0.0 or _cave or puppet:
		return false
	var mgr := get_parent()
	if not mgr or not mgr.has_method("get_animals"):
		return false
	var best: Animal = null
	var best_d := 35.0
	for o in mgr.get_animals():
		var a := o as Animal
		if a == null or a == self or a.dead or a.in_tree or a.species == species or a.species.role == "defensive":
			continue
		if a.species.size > species.size * 0.75:
			continue
		var d := a.position.distance_to(position)
		if d < best_d:
			best_d = d
			best = a
	if best == null:
		_hunger = _rng.randf_range(20.0, 50.0)   # nothing about: look again in a while
		return false
	_prey = best
	_enter(State.HUNT)
	return true


## Climbers: make for the nearest tree and go up it.
func _try_climb() -> void:
	if not species.climbs or in_tree or _cave or state == State.TREE:
		return
	var top: Variant = _nearest_tree(position, 18.0, Vector3.INF)
	if top == null:
		return
	_tree_top = top
	_tree_res = _found_res
	_tree_phase = "to_trunk"
	_enter(State.TREE)


## The top of the nearest tree to p within reach (where an animal sits in its crown), other than `not_at`; null if none.
func _nearest_tree(p: Vector3, reach: float, not_at: Vector3) -> Variant:
	if not _world:
		_world = get_node_or_null("/root/Main/World")
		if not _world:
			return null
	var here: Vector2i = _world.world_to_chunk(p)
	var best: Variant = null
	var best_d := reach
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var chunk = _world.get_chunk(here + Vector2i(dx, dz))
			if not chunk:
				continue
			for r: Dictionary in chunk.resources:
				if r.get("removed", false) or not TREE_TOPS.has(r.kind):
					continue
				var xf: Transform3D = r.transform
				var d := Vector2(xf.origin.x - p.x, xf.origin.z - p.z).length()
				if d < best_d and Vector2(xf.origin.x - not_at.x, xf.origin.z - not_at.z).length() > 1.0 and Game.flora.has_mesh(r.key):
					best_d = d
					_found_res = r
					# Up in the lower crown, against the trunk.
					var h: float = PerchBirds._crown(String(r.key)).y
					best = xf.origin + Vector3(0, h * xf.basis.y.length() * (0.5 if r.kind == "jungle_tree" else 0.62), 0)
	return best


## Up a tree: run to the trunk, climb, sit in the crown looking about, now and then leap to the next tree, and come
## down again once things are quiet.
func _tree_step(delta: float, dist_to_player: float) -> void:
	_breath += delta * 1.7
	if _tree_phase in ["up", "sit"] and _tree_res.get("removed", false):
		_tree_phase = "down"   # the tree was felled under it: it drops to the ground
	match _tree_phase:
		"to_trunk":
			var d := Vector3(_tree_top.x - position.x, 0, _tree_top.z - position.z)
			if d.length() < 0.7:
				_tree_phase = "up"
				in_tree = true
			elif _timer <= 0.0:
				_enter(State.IDLE)
				return
			else:
				_move(delta, d.normalized(), species.run_speed)
				_animate(delta, 0.0, 0.0)
				return
		"up":
			position.x = move_toward(position.x, _tree_top.x, delta)
			position.z = move_toward(position.z, _tree_top.z, delta)
			position.y = move_toward(position.y, _tree_top.y, 3.2 * delta)
			_gait += delta * 9.0
			_body.rotation.x = lerpf(_body.rotation.x, 1.25, 1.0 - exp(-8.0 * delta))
			if absf(position.y - _tree_top.y) < 0.05:
				_tree_phase = "sit"
		"sit":
			_body.rotation.x = lerpf(_body.rotation.x, 0.0, 1.0 - exp(-6.0 * delta))
			_look_cd -= delta
			if _look_cd <= 0.0:
				_look_cd = _rng.randf_range(0.8, 2.5)
				_look_target = _rng.randf_range(-1.0, 1.0)
			_look_yaw = lerpf(_look_yaw, _look_target, 1.0 - exp(-4.0 * delta))
			_head.rotation.y = _look_yaw
			# Leap across to the next tree now and then (more often when someone is close below).
			if _rng.randf() < delta * (0.35 if dist_to_player < 12.0 else 0.06):
				var next: Variant = _nearest_tree(position, 11.0, position)
				if next != null and (next as Vector3).distance_to(position) > 2.0:
					_hop_from = position
					_tree_top = next
					_tree_res = _found_res
					_hop_t = 0.0
					_tree_phase = "hop"
					_call(1.1)
			if _timer <= 0.0 and dist_to_player > 18.0:
				_tree_phase = "down"
		"hop":
			_hop_t = minf(_hop_t + delta / 0.85, 1.0)
			var a := _hop_from.lerp(_tree_top, _hop_t)
			position = a + Vector3.UP * sin(_hop_t * PI) * 2.2
			var d2 := _tree_top - _hop_from
			_yaw = atan2(-d2.x, -d2.z)
			_body.rotation.x = lerpf(0.4, -0.4, _hop_t)
			for leg in _legs:
				leg.rotation.x = 0.9 if _hop_t < 0.5 else -0.9
			if _hop_t >= 1.0:
				_tree_phase = "sit"
		"down":
			var ground := Game.world_gen.get_height(position.x, position.z)
			position.y = move_toward(position.y, ground, (12.0 if _tree_res.get("removed", false) else 3.0) * delta)
			_gait += delta * 9.0
			_body.rotation.x = lerpf(_body.rotation.x, -1.1, 1.0 - exp(-8.0 * delta))
			if position.y - ground < 0.05:
				in_tree = false
				_body.rotation.x = 0.0
				_enter(State.IDLE)
	rotation = Vector3(0, _yaw, 0)
	if _tree_phase in ["up", "down"]:
		for i in _legs.size():
			_legs[i].rotation.x = sin(_gait + (PI if i % 2 == 0 else 0.0)) * 0.7


func _call(pitch := 1.0) -> void:
	if species.call_sound:
		Audio.play_3d(species.call_sound, global_position + Vector3.UP, -2.0, pitch * _rng.randf_range(0.95, 1.05))


func _bite() -> void:
	_lunge = 1.0
	if not player:
		return
	var push := player.global_position - global_position
	push.y = 0.0
	var shove := push.normalized() * 6.0 + Vector3.UP * 2.5
	if player.has_method("hurt"):   # another player (we're the host): tell their game
		player.hurt(species.damage * (1.6 if species.venom else 1.0), shove)
		return
	if not player.has_method("respawn"):
		return
	player.stats.take_damage(species.damage)
	if species.venom:
		player.stats.add_effect("poison", 12.0)   # the venom works on for a while
	Music.combat_ping(1.0)
	player.velocity += shove


## Hit by the player.
func take_hit(damage: float, from: Vector3) -> void:
	if dead:
		return
	hp -= damage
	if hp <= 0.0:
		_die(from)
		_alarm_herd()
		return
	_call(1.15)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.06, 0.94, 1.06), 0.06)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
	# Knocked away from the blow.
	var local := global_transform.basis.inverse() * (global_position - from)
	_flinch = Vector2(clampf(-local.x, -1.0, 1.0) * 0.28, clampf(local.z, -1.0, 1.0) * 0.12)
	if in_tree:
		return   # it stays up there, out of reach
	if species.role == "defensive":
		_enter(State.ATTACK)
	else:
		_enter(State.FLEE)
		_alarm_herd()


func _die(from: Vector3) -> void:
	dead = true
	state = State.DEAD
	# A last, lower cry, and the body coming down.
	var sz := clampf(float(species.size), 0.5, 2.0)
	Audio.play_3d(species.call_sound, global_position + Vector3.UP, -3.0, 0.7 * _rng.randf_range(0.95, 1.05))
	get_tree().create_timer(0.35).timeout.connect(func() -> void:
		if is_instance_valid(self):
			Audio.play_3d("place_stone" if sz > 1.2 else "thud", global_position, linear_to_db(clampf(sz * 0.6, 0.35, 1.0)), 0.75 / sqrt(sz)))
	if in_tree:   # it falls out of the tree
		in_tree = false
		var tw0 := create_tween()
		tw0.tween_property(self, "position:y", Game.world_gen.get_height(position.x, position.z), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	carcass_hp = 60.0 * species.yield_scale
	_call(0.7)
	var side := 1.0 if (from - global_position).dot(global_transform.basis.x) < 0.0 else -1.0
	# It comes to rest along the ground it fell on (on a slope: not level, half in the hill and half in the air).
	var rest_pitch := 0.0
	var rest_roll := 0.0
	if not _cave and not in_tree:
		var g: WorldGen = Game.world_gen
		var fwd := Vector3(-sin(_yaw), 0, -cos(_yaw))
		var rt := Vector3(-fwd.z, 0, fwd.x)
		var half := maxf(species.body_len * 0.5, 0.2)
		var p := global_position
		rest_pitch = atan2(g.get_height(p.x + fwd.x * half, p.z + fwd.z * half) - g.get_height(p.x - fwd.x * half, p.z - fwd.z * half), half * 2.0)
		rest_roll = atan2(g.get_height(p.x + rt.x * half, p.z + rt.z * half) - g.get_height(p.x - rt.x * half, p.z - rt.z * half), half * 2.0)
	for leg in _legs:
		leg.scale.y = 1.0
	var tw := create_tween()
	# It staggers away from the blow, its legs buckle, then it goes over with its weight and settles.
	tw.tween_property(_body, "rotation:z", -side * 0.18, 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_body, "position:y", species.leg_len * 0.75 + species.body_h * 0.25, 0.16)
	tw.parallel().tween_property(_head, "rotation:x", deg_to_rad(30), 0.16)
	tw.tween_property(_body, "rotation:z", side * PI * 0.5 + rest_roll, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_body, "rotation:x", rest_pitch, 0.3)
	tw.parallel().tween_property(_body, "position:y", species.body_w * 0.55, 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(_body, "position:z", 0.0, 0.3)
	tw.parallel().tween_property(_head, "rotation:x", deg_to_rad(10), 0.42)
	# A thump and a small rebound as it lands.
	tw.tween_property(_body, "rotation:z", side * PI * 0.46 + rest_roll, 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(_body, "rotation:z", side * PI * 0.5 + rest_roll, 0.14).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	# A last kick of the legs, then still.
	for i in _legs.size():
		tw.parallel().tween_property(_legs[i], "rotation:x", 0.35 * (1 if i % 2 == 0 else -1), 0.12)
	tw.tween_interval(0.0)
	for i in _legs.size():
		tw.parallel().tween_property(_legs[i], "rotation:x", 0.12 * (1 if i % 2 == 0 else -1), 0.3).set_trans(Tween.TRANS_SINE)


## The carcass has been fully harvested.
func consume_carcass() -> void:
	if is_instance_valid(_collider):
		_collider.queue_free()
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1, 0.01, 1), 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func() -> void:
		removed.emit(self)
		queue_free())


# --- Puppets (multiplayer guests) ---------------------------------------------------------

## New position / heading / state from the host.
func net_update(pos: Vector3, yaw: float, st: int, is_dead: bool) -> void:
	_net_pos = pos
	_net_yaw = yaw
	if st != state and not dead:
		if st == State.FLEE or st == State.ATTACK:
			_call(1.05)
		if st == State.ATTACK and player and position.distance_to(player.global_position) < 30.0:
			Music.combat_ping(1.0)
		state = st as State
	if is_dead and not dead:
		_die(player.global_position if player else position + Vector3.FORWARD)


func _puppet_step(delta: float) -> void:
	if dead:
		return
	var before := position
	var k := 1.0 - exp(-10.0 * delta)
	position.x = lerpf(position.x, _net_pos.x, k)
	position.z = lerpf(position.z, _net_pos.z, k)
	var ground := _net_pos.y if (_cave or species.climbs or species.swims) else Game.world_gen.get_height(position.x, position.z)
	position.y = lerpf(position.y, ground, 1.0 - exp(-14.0 * delta))
	_yaw = lerp_angle(_yaw, _net_yaw, k)
	_desired_yaw = _net_yaw
	rotation = Vector3(0, _yaw, 0)
	var moved := Vector2(position.x - before.x, position.z - before.z).length()
	_speed = lerpf(_speed, moved / maxf(delta, 0.001), 1.0 - exp(-6.0 * delta))
	_gait += moved / maxf(species.leg_len * 1.6, 0.2) * PI
	var graze := 1.0 if (state == State.GRAZE or state == State.EAT) and _speed < 0.3 else 0.0
	var alert := 1.0 if state in [State.ALERT, State.WARN] else 0.0
	_call_cd -= delta
	if _call_cd <= 0.0:
		_call_cd = _rng.randf_range(10.0, 30.0)
		if player and position.distance_to(player.global_position) < 60.0:
			_call()
	_animate(delta, graze, alert)


## A flinch when someone hit it (the host already applied the damage).
func puppet_hit() -> void:
	if dead or not _body:
		return
	_call(1.15)
	var tw := create_tween()
	tw.tween_property(_body, "scale", Vector3(1.06, 0.94, 1.06), 0.06)
	tw.tween_property(_body, "scale", Vector3.ONE, 0.12)
