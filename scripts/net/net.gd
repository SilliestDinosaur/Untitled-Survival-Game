extends Node
## Co-op multiplayer (autoloaded as "Net"). Peer-to-peer with the host as the authority:
##
## - The host plays their own save and "opens it to friends". It listens on UDP PORT, asks the
##   router to forward that port with UPnP, and shows an invite code (its address, encoded).
##   A LAN code works for friends on the same network without any router help.
## - A guest enters the code, says hello, and gets a snapshot of the world (seed + changes),
##   plus their saved character if they've played in this world before.
## - Anything that changes the world goes through request(): the host runs it with the
##   guest's player id (GameActions), then broadcasts the result (resource changes, dropped
##   items, structures, inventories). Visuals and sounds stay on each machine.
## - Players send their pose to everyone; the host simulates animals and sends their positions.
##
## Offline, request() just runs the action locally, so single-player uses the same code path.

signal status_changed(text: String)          ## progress / error text for menus
signal invite_ready                          ## invite / LAN codes are known (host)
signal joined(snapshot: Dictionary)          ## guest: the host's world arrived
signal session_ended(reason: String)         ## disconnected, kicked, or host left
signal roster_changed                        ## someone joined or left
signal player_message(text: String)          ## "X joined" etc. for the HUD
signal games_changed                         ## the list of games on this network changed

const DISCOVERY_PORT := 24681                ## LAN beacon: hosts announce here, menus listen
const BEACON_SECONDS := 1.0
const BEACON_TIMEOUT := 4.0

const PORT := 24680
const MAX_PLAYERS := 4
const PROTOCOL := 3
const POSE_RATE := 1.0 / 15.0
const ANIMAL_RATE := 0.1
const ANIMAL_RANGE := 170.0
## Code alphabet: no 0/O/1/I so codes are easy to read out loud.
const ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

enum Mode { OFFLINE, HOST, CLIENT }

var mode := Mode.OFFLINE
var port := PORT
var invite_code := ""        ## works over the internet (if UPnP opened the port)
var lan_code := ""           ## works on the same network
var upnp_state := ""         ## "" | working | ok | failed
var public_ip := ""
var players := {}            ## peer id -> {name, uid, color}
var use_upnp := true         ## tests turn this off
var host_on_start := false   ## "Open to friends" switch on the New World / Load screens
var _host_name := ""
## Games heard on this network: ip -> {name, world, port, seen}
var found_games := {}
var _beacon: PacketPeerUDP
var _beacon_timer := 0.0
var _listener: PacketPeerUDP

## Set by Main.
var main: Node
var world: Node
var player: Node
var wildlife: Node

var avatars := {}            ## peer id -> RemotePlayer (everyone but me)
var _avatar_root: Node3D
var _requests := {}          ## request id -> Callable
var _next_request := 1
var _pose_timer := 0.0
var _animal_timer := 0.0
var _time_timer := 0.0
var _report_timer := 0.0
var _swings := 0
var _inv_dirty := {}         ## peer id -> {added: {}, broke: ""}
var _upnp: UPNP
var _upnp_thread: Thread
var _rng := RandomNumberGenerator.new()
var _join_timeout := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(func() -> void: _fail("Couldn't reach that game. Check the code, and that the host's game is open."))
	multiplayer.server_disconnected.connect(func() -> void: _end("The host closed the game."))
	Game.pickups_changed.connect(func() -> void:
		if is_host():
			_set_pickups.rpc(Game.pickups))
	Game.structures_changed.connect(func() -> void:
		if is_host():
			_set_structures.rpc(Game.structures))


func is_online() -> bool:
	return mode != Mode.OFFLINE


## Guest: the name of whoever's world this is.
func host_name() -> String:
	return _host_name


func is_host() -> bool:
	return mode == Mode.HOST


func is_client() -> bool:
	return mode == Mode.CLIENT


## This machine's peer id (1 for the host and offline).
func my_id() -> int:
	return multiplayer.get_unique_id() if is_online() else 1


## My player id in GameActions terms: the host and offline player are LOCAL_PLAYER (1);
## on the host, guests are their peer ids.
func player_count() -> int:
	return players.size() + 1 if is_online() else 1


# --- Hosting ---------------------------------------------------------------------------

## Open the current world to friends.
func host() -> bool:
	if is_online():
		return true
	var peer := ENetMultiplayerPeer.new()
	var err := ERR_CANT_CREATE
	for p in [PORT, PORT + 1, PORT + 2, PORT + 3]:
		err = peer.create_server(p, MAX_PLAYERS - 1)
		if err == OK:
			port = p
			break
	if err != OK:
		status_changed.emit("Couldn't open a port for multiplayer (is another copy running?)")
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	players.clear()
	_start_beacon()
	_make_avatar_root()
	lan_code = encode_code(_local_ip(), port)
	invite_code = ""
	public_ip = ""
	if use_upnp:
		upnp_state = "working"
		status_changed.emit("Opening your router for friends...")
		_upnp_thread = Thread.new()
		_upnp_thread.start(_upnp_open.bind(port))
	else:
		upnp_state = "failed"
	invite_ready.emit()
	roster_changed.emit()
	return true


## Runs on a thread: UPnP discovery can take a couple of seconds.
func _upnp_open(p: int) -> void:
	var u := UPNP.new()
	var ok := false
	var ip := ""
	if u.discover(2000, 2, "InternetGatewayDevice") == UPNP.UPNP_RESULT_SUCCESS and u.get_gateway() and u.get_gateway().is_valid_gateway():
		var r := u.add_port_mapping(p, p, "Untitled Survival", "UDP", 0)
		ip = u.query_external_address()
		ok = r == UPNP.UPNP_RESULT_SUCCESS and ip != ""
	call_deferred("_upnp_done", ok, ip, u)


func _upnp_done(ok: bool, ip: String, u: UPNP) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	if not is_host():
		return
	_upnp = u if ok else null
	upnp_state = "ok" if ok else "failed"
	public_ip = ip
	invite_code = encode_code(ip, port) if ok else ""
	status_changed.emit("Ready: share your invite code." if ok else
		"Friends on this Wi-Fi can join automatically (no code needed). For internet play, forward UDP port %d or use a virtual LAN (Tailscale, ZeroTier, Radmin) and share that address." % port)
	invite_ready.emit()


# --- Joining ---------------------------------------------------------------------------

## Join a friend's game. `code` is an invite code, a LAN code, or a plain address (ip or ip:port).
func join(code: String) -> bool:
	if is_online():
		stop()
	var target := decode_code(code)
	if target.is_empty():
		status_changed.emit("That code doesn't look right.")
		return false
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(String(target.ip), int(target.port)) != OK:
		status_changed.emit("Couldn't start connecting.")
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	players.clear()
	_join_timeout = 12.0
	status_changed.emit("Connecting to %s..." % code.strip_edges().to_upper())
	return true


func _on_connected() -> void:
	_join_timeout = 12.0
	status_changed.emit("Connected. Getting the world...")
	_hello.rpc_id(1, PROTOCOL, Settings.player_name, Settings.player_uid, Settings.player_color)


@rpc("any_peer", "reliable")
func _hello(protocol: int, pname: String, uid: String, color: int) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if protocol != PROTOCOL:
		_refuse.rpc_id(peer, "Different game versions: update both copies of the game.")
		_kick_later(peer)
		return
	if players.size() >= MAX_PLAYERS - 1:
		_refuse.rpc_id(peer, "That game is full (%d players)." % MAX_PLAYERS)
		_kick_later(peer)
		return
	for p: int in players:
		if players[p].uid == uid:
			uid += "_2"   # same copy joined twice (testing on one machine)
	pname = pname.strip_edges().substr(0, 20)
	if pname == "":
		pname = "Wanderer"
	players[peer] = {"name": pname, "uid": uid, "color": color}
	# Their character in this world, if they've been here before.
	var saved: Dictionary = Game.guests.get(uid, {})
	var inv := Game.inventory_of(peer)
	if saved.has("inventory"):
		inv.from_data(saved.inventory)
	else:
		inv.clear(true)
		inv.add("rock", 1, true)
	_watch_inventory(peer, inv)
	var snap := Game.snapshot()
	snap.you = saved
	snap.spawn = [player.spawn_point.x, player.spawn_point.y, player.spawn_point.z] if player else [0, 0, 0]
	snap.inventory = inv.to_data()
	snap.players = _roster_with_host()
	_welcome.rpc_id(peer, snap)
	_spawn_avatar(peer)
	_roster.rpc(_roster_with_host())
	roster_changed.emit()
	player_message.emit("%s joined" % pname)


func _roster_with_host() -> Dictionary:
	var r := players.duplicate(true)
	r[1] = {"name": Settings.player_name, "uid": Settings.player_uid, "color": Settings.player_color}
	return r


@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	_end(reason)


func _kick_later(peer: int) -> void:
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if multiplayer.multiplayer_peer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(peer))


@rpc("authority", "reliable")
func _welcome(snap: Dictionary) -> void:
	_join_timeout = 0.0
	_make_avatar_root()
	var roster: Dictionary = snap.players
	players.clear()
	for p: int in roster:
		if p != my_id():
			players[p] = roster[p]
	_host_name = String(roster.get(1, {}).get("name", "your friend"))
	Game.apply_snapshot(snap)
	var inv := Game.inventory_of(Game.LOCAL_PLAYER)
	inv.from_data(snap.inventory)
	inv.remote = true
	for p: int in players:
		_spawn_avatar(p)
	status_changed.emit("")
	joined.emit(snap)
	roster_changed.emit()


@rpc("authority", "reliable")
func _roster(roster: Dictionary) -> void:
	var before := players.keys()
	players.clear()
	for p: int in roster:
		if p != my_id():
			players[p] = roster[p]
			if not avatars.has(p):
				_spawn_avatar(p)
				if not before.has(p):
					player_message.emit("%s joined" % roster[p].name)
	for p: int in avatars.keys():
		if not players.has(p):
			player_message.emit("%s left" % avatars[p].display_name)
			avatars[p].queue_free()
			avatars.erase(p)
	roster_changed.emit()


func _on_peer_connected(_peer: int) -> void:
	pass   # the guest introduces itself with _hello


func _on_peer_disconnected(peer: int) -> void:
	if not is_host() or not players.has(peer):
		return
	var info: Dictionary = players[peer]
	_store_guest(peer)
	players.erase(peer)
	Game.inventories.erase(peer)
	_inv_dirty.erase(peer)
	if avatars.has(peer):
		avatars[peer].queue_free()
		avatars.erase(peer)
	_roster.rpc(_roster_with_host())
	roster_changed.emit()
	player_message.emit("%s left" % info.name)


func store_all_guests() -> void:
	for p: int in players:
		_store_guest(p)


## Keep a guest's character in the host's save.
func _store_guest(peer: int) -> void:
	if not players.has(peer):
		return
	var uid: String = players[peer].uid
	var data: Dictionary = Game.guests.get(uid, {})
	data.inventory = Game.inventory_of(peer).to_data()
	data.name = players[peer].name
	Game.guests[uid] = data


# --- Leaving ---------------------------------------------------------------------------

## Close the session (host: everyone is disconnected; guest: leave the host's game).
func stop() -> void:
	if is_host():
		for p: int in players:
			_store_guest(p)
		_stop_beacon()
		if _upnp:
			_upnp.delete_port_mapping(port, "UDP")
			_upnp = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	var was_client := is_client()
	mode = Mode.OFFLINE
	players.clear()
	for a in avatars.values():
		a.queue_free()
	avatars.clear()
	_requests.clear()
	_inv_dirty.clear()
	invite_code = ""
	lan_code = ""
	upnp_state = ""
	if was_client:
		Game.net_client = false
		Game.inventory_of(Game.LOCAL_PLAYER).remote = false
	roster_changed.emit()


func _fail(reason: String) -> void:
	stop()
	status_changed.emit(reason)
	session_ended.emit(reason)


func _end(reason: String) -> void:
	var was := is_online()
	stop()
	if was:
		session_ended.emit(reason)


func _exit_tree() -> void:
	_stop_beacon()
	stop_listening()
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
	if _upnp:
		_upnp.delete_port_mapping(port, "UDP")


# --- Actions --------------------------------------------------------------------------

## Do something that changes the world. Runs now (offline / host) or asks the host (guest);
## `done` gets the result dictionary either way.
func request(action: String, args: Dictionary, done := Callable()) -> void:
	if is_client():
		var id := _next_request
		_next_request += 1
		if done.is_valid():
			_requests[id] = done
		_req.rpc_id(1, id, action, args)
		return
	var res := run_action(Game.LOCAL_PLAYER, my_id(), action, args)
	if done.is_valid():
		done.call(res)


@rpc("any_peer", "reliable")
func _req(id: int, action: String, args: Dictionary) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	if not players.has(peer):
		return
	var res := run_action(peer, peer, action, args)
	_flush_inventory(peer)   # their inventory change arrives before the reply
	_reply.rpc_id(peer, id, res)


@rpc("authority", "reliable")
func _reply(id: int, res: Dictionary) -> void:
	var cb: Callable = _requests.get(id, Callable())
	_requests.erase(id)
	if cb.is_valid():
		cb.call(res)


## The authority's side of every action. pid = inventory owner, peer = network id.
func run_action(pid: int, peer: int, action: String, a: Dictionary) -> Dictionary:
	var inv := Game.inventory_of(pid)
	if a.has("slot") and action != "drop":
		inv.selected = clampi(int(a.slot), 0, Inventory.HOTBAR_SIZE - 1)
	match action:
		"hit_resource":
			var r := _resource_ref(String(a.id), String(a.kind), String(a.get("key", "")))
			var res := GameActions.hit_resource_r(pid, r, _rng)
			if res.ok:
				_drop_overflow(res.items, a.get("pos", Vector3.ZERO))
				var st := {"by": peer, "fx": res.target, "pos": a.get("pos", Vector3.ZERO), "from": a.get("from", Vector3.ZERO), "t": Game.play_time}
				if res.destroyed:
					st.removed = true
				else:
					st.hp = res.hp
				_broadcast_resource(String(a.id), st)
			return res
		"harvest_resource":
			var r := _resource_ref(String(a.id), String(a.kind), String(a.get("key", "")))
			var res := GameActions.harvest_resource_r(pid, r, _rng)
			if res.ok:
				_drop_overflow(res.items, a.get("pos", Vector3.ZERO))
				var st := {"by": peer, "t": Game.play_time, "from": a.get("from", Vector3.ZERO)}
				if res.picked_up:
					st.removed = true
				else:
					st.bare = true
				_broadcast_resource(String(a.id), st)
			return res
		"pick_up":
			return {"got": GameActions.pick_up(pid, String(a.pickup))}
		"drop":
			return {"id": GameActions.drop(pid, int(a.slot), int(a.amount), a.pos)}
		"craft":
			return GameActions.craft(pid, String(a.recipe), a.pos, int(a.get("times", 1)))
		"place":
			var placed := GameActions.place_structure(pid, int(a.slot), a.pos, float(a.yaw))
			_shape_ground(placed)
			return placed
		"place_blueprint":
			var laid := GameActions.place_blueprint(pid, String(a.kind), a.pos, float(a.yaw))
			_shape_ground(laid)
			return laid
		"hit_structure":
			return GameActions.hit_structure(pid, String(a.structure))
		"toggle_door":
			return GameActions.toggle_door(pid, String(a.structure))
		"consume":
			return GameActions.consume(pid)
		"hit_animal":
			var animal := _animal(int(a.animal))
			if not animal:
				return {"ok": false}
			var res := GameActions.hit_animal(pid, animal, a.get("from", Vector3.ZERO))
			if res.get("ok", false):
				_animal_event.rpc(int(a.animal), "hit")
			return res
		"carcass":
			var animal := _animal(int(a.animal))
			if not animal:
				return {"ok": false}
			var res := GameActions.harvest_carcass(pid, animal, _rng)
			if res.get("ok", false):
				_drop_overflow(res.items, animal.global_position)
				if res.destroyed:
					animal.consume_carcass()
					_animal_event.rpc(int(a.animal), "consumed")
			return res
		"inv":
			match String(a.op):
				"move": inv.move(int(a.a), int(a.b))
				"split": inv.split(int(a.a), int(a.b))
				"quick": inv.quick_move(int(a.a))
			return {"ok": true}
		"reset":
			GameActions.drop_all(inv, a.get("pos", Vector3.ZERO))
			inv.clear(true)
			inv.add("rock", 1, true)
			inv.changed.emit()
			return {"ok": true}
		"debug_add":
			return {"got": inv.add(String(a.item), int(a.count))}
	return {"ok": false}


## The record for a tree/rock/plant: the loaded one if the host has it, else rebuilt from ids.
func _resource_ref(id: String, kind: String, key: String) -> Dictionary:
	if world:
		var found: Array = world.find_resource(id)
		if not found.is_empty():
			return found[0].resources[found[1]]
	var info: Dictionary = FloraLibrary.KINDS.get(kind, {})
	return {"id": id, "kind": kind, "key": key, "hp": float(Game.resource_hp.get(id, info.get("hp", 50))),
		"removed": Game.is_removed(id)}


func _drop_overflow(items: Dictionary, at: Vector3) -> void:
	for k: String in items:
		if k.begins_with("_overflow_"):
			GameActions.spawn_pickup(k.trim_prefix("_overflow_"), items[k], -1, at + Vector3(_rng.randf_range(-0.4, 0.4), 0.3, _rng.randf_range(-0.4, 0.4)))


## Where something was just placed, shape the ground for it: a floor's slab levels the ground under it (at the
## height the host worked out, shared with its neighbours); anything else just clears ground that pokes into it.
func _shape_ground(placed: Dictionary) -> void:
	if not placed.get("ok", false):
		return
	var kind: String = placed.get("kind", "")
	var cells: Array = []
	if kind in GameActions.FLOOR_KINDS:
		cells = TerrainEdit.level_ground(placed.pos, 1.5, 1.5, 0.0, placed.pos.y)
	else:
		var rect := Vector2(1.5, 0.25) if kind in GameActions.EDGE_KINDS else Vector2(1.5, 1.5)
		cells = TerrainEdit.clear_rect(placed.pos, rect.x, rect.y, float(placed.get("yaw", 0.0)), placed.pos.y)
	if not cells.is_empty():
		TerrainEdit.commit(cells)
		if is_host():
			_terrain_cells.rpc(cells)


func _broadcast_resource(id: String, st: Dictionary) -> void:
	if world:
		world.apply_resource_change(id, st)
	if is_host():
		_resource_changed.rpc(id, st)


@rpc("authority", "reliable")
func _resource_changed(id: String, st: Dictionary) -> void:
	if world:
		world.apply_resource_change(id, st)


## Everyone applies the same cell changes, so the ground matches on every machine.
@rpc("authority", "reliable")
func _terrain_cells(cells: Array) -> void:
	TerrainEdit.commit(cells)


@rpc("authority", "reliable")
func _set_pickups(p: Dictionary) -> void:
	Game.pickups = p
	Game.pickups_changed.emit()


@rpc("authority", "reliable")
func _set_structures(s: Dictionary) -> void:
	Game.structures = s
	Game.structures_changed.emit()


# --- Inventories (host -> guest) ---------------------------------------------------------

func _watch_inventory(peer: int, inv: Inventory) -> void:
	if inv.has_meta("watched"):
		return
	inv.set_meta("watched", true)
	inv.changed.connect(func() -> void:
		if players.has(peer):
			_inv_dirty[peer] = _inv_dirty.get(peer, {"added": {}, "broke": ""}))
	inv.item_added.connect(func(id: String, n: int) -> void:
		if players.has(peer):
			var d: Dictionary = _inv_dirty.get(peer, {"added": {}, "broke": ""})
			d.added[id] = int(d.added.get(id, 0)) + n
			_inv_dirty[peer] = d)
	inv.tool_broke.connect(func(id: String) -> void:
		if players.has(peer):
			var d: Dictionary = _inv_dirty.get(peer, {"added": {}, "broke": ""})
			d.broke = id
			_inv_dirty[peer] = d)


func _flush_inventory(peer: int) -> void:
	if not _inv_dirty.has(peer):
		return
	var d: Dictionary = _inv_dirty[peer]
	_inv_dirty.erase(peer)
	_set_inventory.rpc_id(peer, Game.inventory_of(peer).to_data(), d.added, d.broke)


@rpc("authority", "reliable")
func _set_inventory(data: Dictionary, added: Dictionary, broke: String) -> void:
	var inv := Game.inventory_of(Game.LOCAL_PLAYER)
	inv.from_data(data, true)
	for id: String in added:
		inv.item_added.emit(id, int(added[id]))
	if broke != "":
		inv.tool_broke.emit(broke)


# --- Poses, time, animals ------------------------------------------------------------------

## Host: announce this game to everyone on the local network, every second.
func _start_beacon() -> void:
	_beacon = PacketPeerUDP.new()
	_beacon.set_broadcast_enabled(true)
	if _beacon.set_dest_address("255.255.255.255", DISCOVERY_PORT) != OK:
		_beacon = null
		return
	_beacon_timer = 0.0


func _stop_beacon() -> void:
	if _beacon:
		_beacon.close()
		_beacon = null


## Menus: start listening for games on this network (cheap; stop when the menu closes).
func start_listening() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	# Several hosts can share the machine (tests); if the port is busy, we just can't listen.
	if _listener.bind(DISCOVERY_PORT, "*") != OK:
		_listener = null


func stop_listening() -> void:
	if _listener:
		_listener.close()
		_listener = null
	found_games.clear()


func _listen_for_games(delta: float) -> void:
	if not _listener:
		return
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var msg := _listener.get_packet().get_string_from_utf8()
		var ip := _listener.get_packet_ip()
		var data = JSON.parse_string(msg)
		if typeof(data) != TYPE_DICTIONARY or int(data.get("v", 0)) != PROTOCOL:
			continue
		if is_host() and ip == _local_ip():   # my own announcement
			continue
		var entry := {"name": String(data.get("n", "Friend")), "world": String(data.get("w", "")), "port": int(data.get("p", PORT)), "seen": 0.0}
		if not found_games.has(ip) or found_games[ip].name != entry.name or found_games[ip].world != entry.world:
			changed = true
		found_games[ip] = entry
	for ip: String in found_games.keys():
		found_games[ip].seen += delta
		if found_games[ip].seen > BEACON_TIMEOUT:
			found_games.erase(ip)
			changed = true
		else:
			found_games[ip].seen = minf(found_games[ip].seen, BEACON_TIMEOUT)
	if changed:
		games_changed.emit()


func _send_beacon() -> void:
	if not _beacon:
		return
	var msg := JSON.stringify({"v": PROTOCOL, "n": Settings.player_name, "w": Game.save_name, "p": port})
	_beacon.put_packet(msg.to_utf8_buffer())


func _process(delta: float) -> void:
	_listen_for_games(delta)
	if _beacon:
		_beacon_timer -= delta
		if _beacon_timer <= 0.0:
			_beacon_timer = BEACON_SECONDS
			_send_beacon()
	if _join_timeout > 0.0:
		_join_timeout -= delta
		if _join_timeout <= 0.0 and is_client():
			_fail("No answer from that game. If you're on different networks, the host's router may be blocking it.")
	if not is_online():
		return
	for p: int in _inv_dirty.keys():
		_flush_inventory(p)
	if not player or not main or not main.is_playing():
		return
	_pose_timer -= delta
	if _pose_timer <= 0.0:
		_pose_timer = POSE_RATE
		var p: Node3D = player
		_pose.rpc(p.global_position, p.rotation.y, p.head.rotation.x, p.inventory.selected_item(), _swings, bool(p.is_sprinting))
	if is_host():
		_time_timer -= delta
		if _time_timer <= 0.0:
			_time_timer = 2.0
			_sync_time.rpc(Game.time_of_day, Game.day, Game.play_time)
		_animal_timer -= delta
		if _animal_timer <= 0.0:
			_animal_timer = ANIMAL_RATE
			_send_animals()
	else:
		_report_timer -= delta
		if _report_timer <= 0.0:
			_report_timer = 5.0
			_report.rpc_id(1, player.to_save_data())


## Called by the local player when it starts a swing (so others see it).
func note_swing() -> void:
	_swings += 1


@rpc("any_peer", "unreliable_ordered")
func _pose(pos: Vector3, yaw: float, pitch: float, held: String, swings: int, sprinting: bool) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if avatars.has(peer):
		avatars[peer].set_pose(pos, yaw, pitch, held, swings, sprinting)


@rpc("authority", "unreliable_ordered")
func _sync_time(t: float, d: int, play: float) -> void:
	# Small drift is corrected smoothly; big jumps snap.
	if absf(t - Game.time_of_day) > 0.02 or d != Game.day:
		Game.time_of_day = t
	else:
		Game.time_of_day = lerpf(Game.time_of_day, t, 0.5)
	Game.day = d
	Game.play_time = play


## A guest's character state, kept in the host's save.
@rpc("any_peer", "reliable")
func _report(data: Dictionary) -> void:
	var peer := multiplayer.get_remote_sender_id()
	if not is_host() or not players.has(peer):
		return
	data.erase("inventory")   # the host's copy is the real one
	var uid: String = players[peer].uid
	var saved: Dictionary = Game.guests.get(uid, {})
	saved.merge(data, true)
	saved.inventory = Game.inventory_of(peer).to_data()
	saved.name = players[peer].name
	Game.guests[uid] = saved


## Host: hurt a guest (an animal bit them).
func hurt_peer(peer: int, amount: float, push: Vector3) -> void:
	_hurt.rpc_id(peer, amount, push)


@rpc("authority", "reliable")
func _hurt(amount: float, push: Vector3) -> void:
	if player:
		player.stats.take_damage(amount)
		player.velocity += push
		Music.combat_ping(1.0)


func _animal(id: int) -> Node:
	return wildlife.find_animal(id) if wildlife else null


func _send_animals() -> void:
	if not wildlife:
		return
	var list: Array = wildlife.get_animals()
	for peer: int in players:
		if not avatars.has(peer):
			continue
		var center: Vector3 = avatars[peer].global_position
		var out := []
		for a in list:
			if not is_instance_valid(a) or a.net_id < 0:
				continue
			if a.global_position.distance_to(center) > ANIMAL_RANGE:
				continue
			out.append([a.net_id, a.species_index, a.global_position, a.rotation.y, int(a.state), a.dead])
		_animals.rpc_id(peer, out)


@rpc("authority", "unreliable_ordered")
func _animals(list: Array) -> void:
	if wildlife:
		wildlife.apply_puppets(list)


@rpc("authority", "reliable")
func _animal_event(id: int, what: String) -> void:
	if wildlife:
		wildlife.puppet_event(id, what)


# --- Avatars ---------------------------------------------------------------------------

func _make_avatar_root() -> void:
	if is_instance_valid(_avatar_root):
		return
	_avatar_root = Node3D.new()
	_avatar_root.name = "Players"
	if main:
		main.add_child(_avatar_root)
	else:
		add_child(_avatar_root)


func _spawn_avatar(peer: int) -> void:
	if avatars.has(peer) or not players.has(peer):
		return
	_make_avatar_root()
	var a := RemotePlayer.new()
	a.peer_id = peer
	_avatar_root.add_child(a)
	a.setup(players[peer].name, Settings.PLAYER_COLORS[int(players[peer].color) % Settings.PLAYER_COLORS.size()])
	avatars[peer] = a


## Everyone the animals should notice: me plus the other players (host only).
func animal_targets() -> Array:
	var out: Array = [player] if player else []
	for a in avatars.values():
		if a.has_pose:
			out.append(a)
	return out


# --- Codes ---------------------------------------------------------------------------

## An address as a short code: 4 bytes of IPv4 (+2 bytes of port if not the default),
## in a 32-letter alphabet, grouped for reading: e.g. "KQ7M-B3X".
static func encode_code(ip: String, p: int) -> String:
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var value := 0
	for part in parts:
		value = (value << 8) | (int(part) & 255)
	var bits := 32
	if p != PORT:
		value = (value << 16) | (p & 0xFFFF)
		bits = 48
	var chars := ""
	var count := ceili(bits / 5.0)
	for i in count:
		chars = ALPHABET[value & 31] + chars
		value >>= 5
	return chars.substr(0, 4) + "-" + chars.substr(4)


## Code (or "ip" / "ip:port") -> {ip, port}, or {} if it isn't valid.
static func decode_code(code: String) -> Dictionary:
	var c := code.strip_edges()
	if c.count(".") == 3:   # a plain address
		var host_part := c.get_slice(":", 0)
		var p := int(c.get_slice(":", 1)) if c.contains(":") else PORT
		return {"ip": host_part, "port": p}
	c = c.to_upper().replace("-", "").replace(" ", "")
	if c.length() != 7 and c.length() != 10:
		return {}
	var value := 0
	for ch in c:
		var v := ALPHABET.find(ch)
		if v < 0:
			return {}
		value = (value << 5) | v
	var p := PORT
	if c.length() == 10:
		p = value & 0xFFFF
		value >>= 16
	value &= 0xFFFFFFFF
	var ip := "%d.%d.%d.%d" % [(value >> 24) & 255, (value >> 16) & 255, (value >> 8) & 255, value & 255]
	return {"ip": ip, "port": p}


## This machine's address on the local network.
static func _local_ip() -> String:
	var best := ""
	for a in IP.get_local_addresses():
		if a.count(".") != 3 or a.begins_with("127.") or a.begins_with("169.254."):
			continue
		if a.begins_with("192.168.") or a.begins_with("10."):
			return a
		if best == "":
			best = a
	return best if best != "" else "127.0.0.1"
