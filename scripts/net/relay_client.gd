class_name RelayClient
extends Node
## A client for noray (https://github.com/foxssake/noray, MIT), the meeting server that lets players on different
## networks reach each other. It introduces a guest to a host so both can punch through their routers (each fires
## packets at the other, so each router sees the other's traffic as a reply: NAT punch-through), and when that
## can't work it relays the traffic itself.
##
## Talking to it: text commands, one per line, over TCP ("register-host", "connect <code>", ...). Where on the
## internet a machine's game socket is seen is learnt from a UDP packet that socket sends to the registrar port.

signal command(name: String, data: String)

const TCP_PORT := 8890
const REGISTRAR_PORT := 8809
const HELLO := "$rwx"   ## what the punch-through packets say ("read, written, shaken hands")

var server_ip := ""
var oid := ""              ## this machine's code on the server: a host's invite code
var pid := ""              ## the private id that proves which machine is registering an address
var _tcp := StreamPeerTCP.new()
var _buf := ""
var _inbox: Array = []     ## commands not yet taken by wait_for()


## Connect to the server ("host" or "host:port"). False if it can't be reached within a few seconds.
func open(address: String) -> bool:
	var host := address
	var p := TCP_PORT
	if address.contains(":"):
		host = address.get_slice(":", 0)
		p = int(address.get_slice(":", 1))
	server_ip = IP.resolve_hostname(host, IP.TYPE_IPV4)
	if server_ip == "" or _tcp.connect_to_host(server_ip, p) != OK:
		return false
	var until := Time.get_ticks_msec() + 5000
	while _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTING and Time.get_ticks_msec() < until:
		_tcp.poll()
		await get_tree().process_frame
	if _tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	_tcp.set_no_delay(true)
	return true


func is_open() -> bool:
	return _tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED


func close() -> void:
	_tcp.disconnect_from_host()


## Get this machine's codes. Guests register too: the server only connects machines it knows.
func register() -> bool:
	send("register-host")
	var until := Time.get_ticks_msec() + 5000
	while (oid == "" or pid == "") and Time.get_ticks_msec() < until and is_open():
		await get_tree().process_frame
	return oid != "" and pid != ""


## Guest: tell the server where a fresh UDP socket is seen from outside, and return its local port (the game's
## connection then uses that same port, so routers treat it as the same conversation). -1 if there's no answer.
func register_udp() -> int:
	var udp := PacketPeerUDP.new()
	if udp.bind(0) != OK:
		return -1
	udp.set_dest_address(server_ip, REGISTRAR_PORT)
	var local := udp.get_local_port()
	var until := Time.get_ticks_msec() + 5000
	var ok := false
	while Time.get_ticks_msec() < until and not ok:
		udp.put_packet(pid.to_utf8_buffer())   # repeated: UDP can drop it, and the server doesn't mind
		await get_tree().create_timer(0.1).timeout
		while udp.get_available_packet_count() > 0:
			ok = udp.get_packet().get_string_from_utf8() == "OK" or ok
	udp.close()
	return local if ok else -1


## Host: register the game's own socket (its answer comes back into the game's connection, which ignores it).
## Sent again every few seconds, which also keeps the router's door for that socket open.
func register_from(connection: ENetConnection) -> void:
	connection.socket_send(server_ip, REGISTRAR_PORT, pid.to_utf8_buffer())


## A blank line over the TCP connection (the server ignores it). Without it the connection carries nothing after the
## host registers, and VPNs and routers drop connections that look idle, taking the invite code with them unnoticed;
## with it, a dead connection shows up as closed within seconds, so the host can register again.
func heartbeat() -> void:
	if is_open():
		_tcp.put_data("\n".to_utf8_buffer())


func send(cmd: String, data := "") -> void:
	if is_open():
		_tcp.put_data(((cmd + " " + data) if data != "" else cmd).strip_edges().to_utf8_buffer() + "\n".to_utf8_buffer())


## The next command named one of `names` (it may already have arrived), or {} after `seconds`.
func wait_for(names: Array, seconds: float) -> Dictionary:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		for i in _inbox.size():
			if _inbox[i].name in names:
				return _inbox.pop_at(i)
		if not is_open():
			return {}
		await get_tree().process_frame
	return {}


func _process(_delta: float) -> void:
	_tcp.poll()
	if not is_open():
		return
	var n := _tcp.get_available_bytes()
	if n <= 0:
		return
	_buf += _tcp.get_utf8_string(n)
	while _buf.contains("\n"):
		var line := _buf.get_slice("\n", 0).strip_edges()
		_buf = _buf.substr(_buf.find("\n") + 1)
		if line == "":
			continue
		var cmd := line.get_slice(" ", 0)
		var data := line.substr(cmd.length() + 1) if line.contains(" ") else ""
		match cmd:
			"set-oid": oid = data
			"set-pid": pid = data
			_:
				_inbox.append({"name": cmd, "data": data})
				command.emit(cmd, data)
		if _inbox.size() > 32:
			_inbox.pop_front()


## "ip:port" from a connect reply, or {} if it's an error message instead.
static func parse_address(data: String) -> Dictionary:
	var parts := data.split(":")
	if parts.size() != 2 or not parts[1].is_valid_int() or parts[0].count(".") != 3:
		return {}
	return {"ip": parts[0], "port": int(parts[1])}


## Guest: the punch-through, from a UDP socket on `local_port`: keep sending to the other side until each has
## heard the other (or a little while has passed). True if they heard us, or at least we heard them.
static func handshake(tree: SceneTree, local_port: int, ip: String, port: int, seconds: float) -> bool:
	var udp := PacketPeerUDP.new()
	if udp.bind(local_port) != OK:
		return false
	udp.set_dest_address(ip, port)
	var heard := false
	var shook := false
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until and not shook:
		while udp.get_available_packet_count() > 0:
			var said := udp.get_packet().get_string_from_ascii()
			heard = true
			shook = said.contains("r") or shook   # they've heard us too
		udp.put_packet(("$r" if heard else "$-").to_ascii_buffer() + ("wx" if shook else "w-").to_ascii_buffer())
		await tree.create_timer(0.1).timeout
	udp.close()
	return heard


## Host: fire punch-through packets from the game's own socket at a guest (or at a relay port) for a few seconds,
## so the router lets their connection in. The game's socket can't read replies here; the guest checks those.
static func blast(tree: SceneTree, peer: ENetMultiplayerPeer, ip: String, port: int, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
			return
		peer.host.socket_send(ip, port, HELLO.to_ascii_buffer())
		await tree.create_timer(0.1).timeout
