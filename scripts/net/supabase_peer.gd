## MultiplayerPeer that relays Godot's multiplayer packets through a Supabase Realtime
## "broadcast" channel, so online play needs no game server of our own: the host's
## game is the authority and Supabase only forwards messages.
##
## Protocol: Phoenix channels over a WebSocket (vsn 1.0.0, JSON). Every room is the
## channel "realtime:kartclash-<ROOM>". Packets are batched (several Godot packets per
## broadcast) and sent at most `send_rate` times per second to respect Supabase's
## messages-per-second quota. Every broadcast reaches every member of the room, so
## each message carries its target and peers drop what isn't for them.
class_name SupabasePeer
extends MultiplayerPeerExtension

const TOPIC_PREFIX := "realtime:kartclash-"
const HEARTBEAT_INTERVAL := 20.0
const PING_INTERVAL := 2.0
const PEER_TIMEOUT := 10.0
const JOIN_TIMEOUT := 8.0
const MAX_PACKET := 64 * 1024

## Broadcast batches per second (each batch counts once per receiver on Supabase).
var send_rate := 12.0
## Set when the connection fails or closes, for the UI.
var last_error := ""

var _ws := WebSocketPeer.new()
var _topic := ""
var _is_host := false
var _unique_id := 0
var _status := MultiplayerPeer.CONNECTION_DISCONNECTED
var _joined_channel := false
var _ref := 0
var _join_ref := ""
var _target := 0
var _channel := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _refuse := false
## Incoming Godot packets: [from, channel, mode, PackedByteArray]
var _incoming: Array = []
## Outgoing Godot packets: [to, channel, mode, base64]
var _outgoing: Array = []
## Connected remote peers -> seconds since last message.
var _peers: Dictionary = {}
var _clock := 0.0
var _last_tick := 0
var _since_flush := 0.0
var _since_heartbeat := 0.0
var _since_ping := 0.0
var _since_start := 0.0


## Creates the room `room` and becomes peer 1 (the host).
func host(supabase_url: String, anon_key: String, room: String) -> Error:
	_is_host = true
	_unique_id = 1
	return _open(supabase_url, anon_key, room)


## Joins the room `room` hosted by someone else.
func join(supabase_url: String, anon_key: String, room: String) -> Error:
	_is_host = false
	_unique_id = 2 + (randi() % 0x7ffffff0)
	return _open(supabase_url, anon_key, room)


static func make_room_code() -> String:
	const CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in 5:
		code += CHARS[randi() % CHARS.length()]
	return code


## https://ref.supabase.co -> wss://ref.supabase.co/realtime/v1/websocket?... (http -> ws for local tests).
static func realtime_url(supabase_url: String, anon_key: String) -> String:
	var base := supabase_url.strip_edges().trim_suffix("/")
	if base.begins_with("https://"):
		base = "wss://" + base.substr(8)
	elif base.begins_with("http://"):
		base = "ws://" + base.substr(7)
	return "%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [base, anon_key.uri_encode()]


func _open(supabase_url: String, anon_key: String, room: String) -> Error:
	_topic = TOPIC_PREFIX + room.to_upper()
	_status = MultiplayerPeer.CONNECTION_CONNECTING
	_last_tick = Time.get_ticks_msec()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(realtime_url(supabase_url, anon_key))
	if err != OK:
		_status = MultiplayerPeer.CONNECTION_DISCONNECTED
		last_error = "Could not open the connection (error %d)" % err
	return err


# --- MultiplayerPeerExtension ---------------------------------------------------

func _get_unique_id() -> int:
	return _unique_id


func _is_server() -> bool:
	return _is_host


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return _status


func _is_server_relay_supported() -> bool:
	return false


func _set_target_peer(peer: int) -> void:
	_target = peer


func _set_transfer_channel(channel: int) -> void:
	_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_refuse_new_connections(enable: bool) -> void:
	_refuse = enable


func _is_refusing_new_connections() -> bool:
	return _refuse


func _get_max_packet_size() -> int:
	return MAX_PACKET


func _get_available_packet_count() -> int:
	return _incoming.size()


func _get_packet_peer() -> int:
	return int(_incoming[0][0]) if not _incoming.is_empty() else 0


func _get_packet_channel() -> int:
	return int(_incoming[0][1]) if not _incoming.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return int(_incoming[0][2]) as MultiplayerPeer.TransferMode if not _incoming.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_script() -> PackedByteArray:
	if _incoming.is_empty():
		return PackedByteArray()
	var p: Array = _incoming.pop_front()
	return p[3]


func _put_packet_script(buffer: PackedByteArray) -> Error:
	if _status != MultiplayerPeer.CONNECTION_CONNECTED:
		return ERR_UNCONFIGURED
	# Unreliable packets (snapshots) only keep the newest copy per target and channel.
	if _mode != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
		for i in range(_outgoing.size() - 1, -1, -1):
			var o: Array = _outgoing[i]
			if o[0] == _target and o[1] == _channel and o[2] != MultiplayerPeer.TRANSFER_MODE_RELIABLE:
				_outgoing.remove_at(i)
				break
	_outgoing.append([_target, _channel, int(_mode), Marshalls.raw_to_base64(buffer)])
	return OK


func _disconnect_peer(peer: int, _force: bool) -> void:
	if _is_host and _peers.has(peer):
		_send_event("kick", {"to": peer})
		_drop_peer(peer)


func _close() -> void:
	if _joined_channel:
		_send_event("bye", {})
		_send_phx(_topic, "phx_leave", {})
	_ws.close()
	_joined_channel = false
	for id in _peers.keys():
		_drop_peer(id)
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED


func _poll() -> void:
	var now := Time.get_ticks_msec()
	var dt := float(now - _last_tick) / 1000.0
	_last_tick = now
	_since_start += dt
	_ws.poll()
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		if _status != MultiplayerPeer.CONNECTION_DISCONNECTED:
			if last_error == "":
				last_error = "Connection closed (%d %s)" % [_ws.get_close_code(), _ws.get_close_reason()]
			_fail()
		return
	if state != WebSocketPeer.STATE_OPEN:
		if _since_start > JOIN_TIMEOUT and _status == MultiplayerPeer.CONNECTION_CONNECTING:
			last_error = "Could not reach the Supabase server"
			_close()
		return
	if _ref == 0:
		_join_channel()
	while _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		var msg: Variant = JSON.parse_string(text)
		if msg is Dictionary:
			_handle_phx(msg)

	_since_heartbeat += dt
	if _since_heartbeat >= HEARTBEAT_INTERVAL:
		_since_heartbeat = 0.0
		_send_phx("phoenix", "heartbeat", {})

	if _status == MultiplayerPeer.CONNECTION_CONNECTING and not _is_host:
		_since_ping += dt
		if _joined_channel and _since_ping >= 1.0:
			_since_ping = 0.0
			_send_event("hello", {})
		if _since_start > JOIN_TIMEOUT:
			last_error = "No game found with that room code"
			_close()
			return

	if _status == MultiplayerPeer.CONNECTION_CONNECTED:
		for id in _peers.keys():
			_peers[id] = float(_peers[id]) + dt
			if float(_peers[id]) > PEER_TIMEOUT:
				_drop_peer(id)
				if not _is_host:
					last_error = "Lost connection to the host"
					_close()
					return
		_since_ping += dt
		_since_flush += dt
		if not _outgoing.is_empty() and _since_flush >= 1.0 / send_rate:
			_flush()
		elif _since_ping >= PING_INTERVAL:
			_since_ping = 0.0
			_send_event("ping", {})


# --- Phoenix / Realtime ----------------------------------------------------------

func _join_channel() -> void:
	_ref += 1
	_join_ref = str(_ref)
	_ws.send_text(JSON.stringify({
		"topic": _topic, "event": "phx_join", "ref": _join_ref, "join_ref": _join_ref,
		"payload": {"config": {"broadcast": {"self": false, "ack": false},
			"presence": {"enabled": false}, "private": false}},
	}))


func _send_phx(topic: String, event: String, payload: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	_ref += 1
	var msg := {"topic": topic, "event": event, "payload": payload, "ref": str(_ref)}
	if topic == _topic:
		msg["join_ref"] = _join_ref
	_ws.send_text(JSON.stringify(msg))


## Sends one Realtime broadcast to the room. `data` gets our id as "f".
func _send_event(event: String, data: Dictionary) -> void:
	if not _joined_channel:
		return
	data["f"] = _unique_id
	_send_phx(_topic, "broadcast", {"type": "broadcast", "event": event, "payload": data})


func _flush() -> void:
	_since_flush = 0.0
	_since_ping = 0.0
	_send_event("pk", {"b": _outgoing})
	_outgoing = []


func _handle_phx(msg: Dictionary) -> void:
	var event := str(msg.get("event", ""))
	var payload: Variant = msg.get("payload", {})
	match event:
		"phx_reply":
			if str(msg.get("ref", "")) == _join_ref and not _joined_channel:
				var status := str((payload as Dictionary).get("status", "")) if payload is Dictionary else ""
				if status == "ok":
					_joined_channel = true
					if _is_host:
						_status = MultiplayerPeer.CONNECTION_CONNECTED
				else:
					last_error = "Supabase refused the room: %s" % JSON.stringify((payload as Dictionary).get("response", {}))
					_close()
		"phx_error", "phx_close":
			if str(msg.get("topic", "")) == _topic:
				last_error = "The room channel closed"
				_close()
		"system":
			if payload is Dictionary and str(payload.get("status", "")) == "error":
				last_error = "Supabase: %s" % str(payload.get("message", "error"))
		"broadcast":
			if payload is Dictionary:
				_handle_broadcast(str(payload.get("event", "")), payload.get("payload", {}))


func _handle_broadcast(event: String, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var from := int(data.get("f", 0))
	if from == 0 or from == _unique_id:
		return
	var to := int(data.get("to", 0))
	if to != 0 and to != _unique_id:
		if event != "pk":
			return
	match event:
		"hello":
			if _is_host and _status == MultiplayerPeer.CONNECTION_CONNECTED:
				if _refuse:
					_send_event("reject", {"to": from, "reason": "The game has already started"})
				elif not _peers.has(from):
					_peers[from] = 0.0
					_send_event("welcome", {"to": from})
					peer_connected.emit(from)
				else:
					_send_event("welcome", {"to": from})
		"welcome":
			if not _is_host and from == 1 and _status == MultiplayerPeer.CONNECTION_CONNECTING:
				_peers[1] = 0.0
				_status = MultiplayerPeer.CONNECTION_CONNECTED
				peer_connected.emit(1)
		"reject", "kick":
			if not _is_host and from == 1:
				last_error = str(data.get("reason", "The host closed the connection"))
				_close()
		"bye":
			if _peers.has(from):
				_drop_peer(from)
				if not _is_host and from == 1:
					last_error = "The host left the game"
					_close()
		"ping":
			if _peers.has(from):
				_peers[from] = 0.0
		"pk":
			if not _peers.has(from):
				return
			_peers[from] = 0.0
			var batch: Variant = data.get("b", [])
			if not (batch is Array):
				return
			for p in batch:
				if not (p is Array) or (p as Array).size() < 4:
					continue
				var target := int(p[0])
				# Target 0 = everyone; negative = everyone except that peer.
				if target == 0 or target == _unique_id or (target < 0 and -target != _unique_id):
					_incoming.append([from, int(p[1]), int(p[2]), Marshalls.base64_to_raw(str(p[3]))])


func _drop_peer(id: int) -> void:
	if _peers.erase(id):
		peer_disconnected.emit(id)


func _fail() -> void:
	_joined_channel = false
	for id in _peers.keys():
		_drop_peer(id)
	_status = MultiplayerPeer.CONNECTION_DISCONNECTED
