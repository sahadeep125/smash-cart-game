## Network session and lobby (autoload "Net").
##
## Two transports share the same game code (Godot's high-level multiplayer + RPCs):
## - "lan": ENet over UDP (desktop and mobile), with LAN discovery.
## - "online": SupabasePeer, relayed through a Supabase Realtime channel (any platform).
## The host (peer 1) owns the lobby, starts the match and simulates bots and combat.
extends Node

signal lobby_changed
## Joining failed or the session ended; `reason` is shown to the player.
signal session_ended(reason: String)
signal joined_lobby

const GAME_VERSION := "0.3"
const LAN_PORT := 24680
const MAX_LAN_PLAYERS := 16
## Supabase's free tier allows 100 messages/s for the whole project, and every
## broadcast counts once per receiver, so online rooms stay small.
const MAX_ONLINE_PLAYERS := 4
const GAME_SCENE := "res://scenes/game.tscn"
const LOBBY_SCENE := "res://scenes/lobby.tscn"
const MENU_SCENE := "res://scenes/main_menu.tscn"

## "" (offline), "lan" or "online".
var transport := ""
var room_code := ""
var host_address := ""
## Lobby roster: [{peer: int, name: String, team: int, weapon: String}]
var players: Array = []
## Match settings chosen by the host.
var config := {"mode": "ffa", "team_count": 2, "team_size": 4, "ai_count": 3,
	"ai_difficulty": 0.6, "duration": 180.0, "map": Maps.DEFAULT}
var in_match := false
var discovery: LanDiscovery

var _pending_name := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	discovery = LanDiscovery.new()
	discovery.name = "LanDiscovery"
	add_child(discovery)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(_delta: float) -> void:
	# A SupabasePeer that dies on its own (timeouts, kicks) is noticed here.
	if transport == "online" and multiplayer.multiplayer_peer is SupabasePeer:
		var p := multiplayer.multiplayer_peer as SupabasePeer
		if p.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
			_end_session(p.last_error if p.last_error != "" else "Disconnected")


# --- Queries ------------------------------------------------------------------------

func is_active() -> bool:
	return transport != "" and multiplayer.has_multiplayer_peer() \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)


func is_host() -> bool:
	return is_active() and multiplayer.is_server()


func is_client() -> bool:
	return is_active() and not multiplayer.is_server()


func get_my_peer_id() -> int:
	return multiplayer.get_unique_id() if is_active() else 1


func max_players() -> int:
	return MAX_ONLINE_PLAYERS if transport == "online" else MAX_LAN_PLAYERS


## Snapshot / state send rates per second for the current transport.
func snapshot_rate() -> float:
	return 6.0 if transport == "online" else 20.0


func client_state_rate() -> float:
	return 4.0 if transport == "online" else 20.0


# --- Hosting and joining ----------------------------------------------------------------

func host_lan(player_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(LAN_PORT, MAX_LAN_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = "lan"
	_start_hosting(player_name)
	discovery.advertise(_beacon_info())
	return OK


func join_lan(address: String, player_name: String) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address.strip_edges(), LAN_PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = "lan"
	host_address = address
	_pending_name = player_name
	return OK


func host_online(player_name: String) -> Error:
	leave()
	if not Settings.has_online_config():
		return ERR_UNCONFIGURED
	var peer := SupabasePeer.new()
	room_code = SupabasePeer.make_room_code()
	var err := peer.host(Settings.supabase_url, Settings.supabase_anon_key, room_code)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = "online"
	_start_hosting(player_name)
	return OK


func join_online(code: String, player_name: String) -> Error:
	leave()
	if not Settings.has_online_config():
		return ERR_UNCONFIGURED
	var peer := SupabasePeer.new()
	room_code = code.strip_edges().to_upper()
	var err := peer.join(Settings.supabase_url, Settings.supabase_anon_key, room_code)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	transport = "online"
	_pending_name = player_name
	return OK


## Closes any session and goes back to offline mode (no scene change).
func leave() -> void:
	discovery.stop()
	if is_active():
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	transport = ""
	players.clear()
	in_match = false
	room_code = ""


# --- Lobby actions --------------------------------------------------------------------

## Host: change match settings and tell everyone.
func set_config(values: Dictionary) -> void:
	if not is_host():
		return
	for k in values:
		config[k] = values[k]
	config["team_count"] = clampi(int(config["team_count"]), 2, Teams.MAX_TEAMS)
	config["team_size"] = clampi(int(config["team_size"]), 1, Teams.MAX_TEAM_SIZE)
	config["ai_count"] = clampi(int(config["ai_count"]), 0, MatchSetup.MAX_KARTS - 1)
	var map := str(config.get("map", Maps.DEFAULT))
	config["map"] = map if map == Maps.RANDOM or Maps.has_map(map) else Maps.DEFAULT
	_rebalance_teams()
	_broadcast_lobby()


## Any peer: ask to play for `team`.
func request_team(team: int) -> void:
	if is_host():
		_set_team(1, team)
	elif is_client():
		_rpc_set_team.rpc_id(1, team)


## Any peer: choose the weapon we start each life with (see Loadout).
func request_weapon(weapon: String) -> void:
	weapon = Loadout.sanitize(weapon)
	if is_host():
		_set_weapon(1, weapon)
	elif is_client():
		_rpc_set_weapon.rpc_id(1, weapon)


## Host: start the match for everyone.
func start_match() -> void:
	if not is_host():
		return
	var setup := MatchSetup.build(str(config["mode"]), players, int(config["ai_count"]),
		int(config["team_count"]), int(config["team_size"]), float(config["duration"]),
		float(config["ai_difficulty"]))
	# Resolve "random" once here so every peer loads the same map.
	setup["map"] = Maps.resolve(str(config.get("map", Maps.DEFAULT)))
	multiplayer.multiplayer_peer.refuse_new_connections = true
	discovery.stop()
	_rpc_start_match.rpc(MatchSetup.to_wire(setup))


## Host: everyone back to the lobby after a match.
func return_to_lobby() -> void:
	if is_host():
		_rpc_back_to_lobby.rpc()


# --- RPCs ---------------------------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_hello(player_name: String, version: String) -> void:
	if not is_host():
		return
	var from := multiplayer.get_remote_sender_id()
	var reason := ""
	if version != GAME_VERSION:
		reason = "Version mismatch (host %s, you %s)" % [GAME_VERSION, version]
	elif in_match:
		reason = "The match has already started"
	elif players.size() >= max_players():
		reason = "The game is full"
	if reason != "":
		_rpc_rejected.rpc_id(from, reason)
		get_tree().create_timer(0.5).timeout.connect(func() -> void:
			if is_active():
				multiplayer.multiplayer_peer.disconnect_peer(from))
		return
	players.append({"peer": from, "name": _unique_name(player_name.strip_edges().substr(0, 14)), "team": -1, "weapon": ""})
	_rebalance_teams()
	_broadcast_lobby()


@rpc("authority", "reliable")
func _rpc_rejected(reason: String) -> void:
	_end_session(reason)


@rpc("authority", "reliable")
func _rpc_lobby(p_players: Array, p_config: Dictionary) -> void:
	var first := players.is_empty()
	players = p_players
	config = p_config
	if first:
		joined_lobby.emit()
		if Settings.weapon_pick != "":
			request_weapon(Settings.weapon_pick)
	lobby_changed.emit()


@rpc("any_peer", "reliable")
func _rpc_set_team(team: int) -> void:
	if is_host():
		_set_team(multiplayer.get_remote_sender_id(), team)


@rpc("any_peer", "reliable")
func _rpc_set_weapon(weapon: String) -> void:
	if is_host():
		_set_weapon(multiplayer.get_remote_sender_id(), Loadout.sanitize(weapon))


@rpc("authority", "reliable", "call_local")
func _rpc_start_match(setup_wire: Dictionary) -> void:
	in_match = true
	GameState.reset()
	GameState.set_setup(MatchSetup.from_wire(setup_wire))
	get_tree().paused = false
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


@rpc("authority", "reliable", "call_local")
func _rpc_back_to_lobby() -> void:
	in_match = false
	GameState.reset()
	get_tree().paused = false
	if is_host():
		multiplayer.multiplayer_peer.refuse_new_connections = false
		if transport == "lan":
			discovery.advertise(_beacon_info())
	get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


# --- Internals ----------------------------------------------------------------------

func _start_hosting(player_name: String) -> void:
	players = [{"peer": 1, "name": player_name.strip_edges().substr(0, 14), "team": 0, "weapon": Settings.weapon_pick}]
	in_match = false
	lobby_changed.emit()


func _beacon_info() -> Dictionary:
	return {"name": players[0]["name"] if not players.is_empty() else "Host",
		"players": players.size(), "mode": config["mode"], "port": LAN_PORT, "version": GAME_VERSION}


func _broadcast_lobby() -> void:
	if not is_host():
		return
	if multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		_rpc_lobby.rpc(players, config)
	discovery.update_info(_beacon_info())
	lobby_changed.emit()


func _set_team(peer: int, team: int) -> void:
	team = clampi(team, 0, int(config["team_count"]) - 1)
	var count := 0
	for p in players:
		if int(p["team"]) == team and int(p["peer"]) != peer:
			count += 1
	if count >= int(config["team_size"]):
		return
	for p in players:
		if int(p["peer"]) == peer:
			p["team"] = team
	_broadcast_lobby()


func _set_weapon(peer: int, weapon: String) -> void:
	for p in players:
		if int(p["peer"]) == peer:
			p["weapon"] = weapon
	_broadcast_lobby()


## Puts every player on a valid team with room, keeping choices where possible.
func _rebalance_teams() -> void:
	var tc := int(config["team_count"])
	var ts := int(config["team_size"])
	var counts := []
	counts.resize(tc)
	counts.fill(0)
	for p in players:
		var t := int(p["team"])
		if t >= 0 and t < tc and int(counts[t]) < ts:
			counts[t] = int(counts[t]) + 1
		else:
			p["team"] = -1
	for p in players:
		if int(p["team"]) == -1:
			var best := 0
			for t in tc:
				if int(counts[t]) < int(counts[best]):
					best = t
			p["team"] = best
			counts[best] = int(counts[best]) + 1


func _unique_name(n: String) -> String:
	if n == "":
		n = "Player"
	var name := n
	var i := 2
	while players.any(func(p: Dictionary) -> bool: return p["name"] == name):
		name = "%s %d" % [n, i]
		i += 1
	return name


func _on_peer_connected(_id: int) -> void:
	pass  # the client introduces itself with _rpc_hello


func _on_peer_disconnected(id: int) -> void:
	if not is_host():
		return
	var before := players.size()
	players = players.filter(func(p: Dictionary) -> bool: return int(p["peer"]) != id)
	if players.size() != before and not in_match:
		_broadcast_lobby()


func _on_connected_to_server() -> void:
	_rpc_hello.rpc_id(1, _pending_name, GAME_VERSION)


func _on_connection_failed() -> void:
	_end_session("Could not connect to the host")


func _on_server_disconnected() -> void:
	_end_session("The host left the game")


func _end_session(reason: String) -> void:
	if transport == "":
		return
	leave()
	GameState.reset()
	get_tree().paused = false
	_last_end_reason = reason
	session_ended.emit(reason)
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path != LOBBY_SCENE:
		get_tree().change_scene_to_file.call_deferred(LOBBY_SCENE)


## Reason for the last session end, shown by the lobby screen after a scene change.
var _last_end_reason := ""


func take_end_reason() -> String:
	var r := _last_end_reason
	_last_end_reason = ""
	return r
