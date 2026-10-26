## Two-process network test. Start a host and a client (see tests/run_net_test.sh):
##   godot --headless --path . res://tests/net_test.tscn -- --role=host --transport=lan
##   godot --headless --path . res://tests/net_test.tscn -- --role=client --transport=lan
## For --transport=online pass --url=http://127.0.0.1:PORT (the mock Realtime server).
## Plays a short 4v4 Team Deathmatch with bots and prints PASS/FAIL lines plus a
## RESULTS line, which the runner compares between host and client.
extends Node

const MATCH_SECONDS := 60.0
const TIMEOUT := 150.0

var role := "host"
var transport := "lan"
var url := ""
var room := "TESTR"
var players := 2
var _failed := 0
var _passed := 0
var _kills := 0
var _respawns := 0
var _ended := false
var _results: Array = []
var _elapsed := 0.0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = (get_script() as GDScript).new()
		driver.name = "NetTestDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="):
			role = a.substr(7)
		elif a.begins_with("--transport="):
			transport = a.substr(12)
		elif a.begins_with("--url="):
			url = a.substr(6)
		elif a.begins_with("--room="):
			room = a.substr(7)
		elif a.begins_with("--players="):
			players = int(a.substr(10))
	Events.kart_killed.connect(func(_v: Node, _k: Node, _w: String) -> void: _kills += 1)
	Events.kart_respawned.connect(func(_k: Node) -> void: _respawns += 1)
	Events.match_ended.connect(func(r: Array) -> void:
		_ended = true
		_results = r)
	_run()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed > TIMEOUT:
		_check("finished before timeout", false)
		_finish()


func _run() -> void:
	if transport == "online":
		Settings.supabase_url = url
		Settings.supabase_anon_key = "test-anon-key-0123456789abcdef"
	var err := OK
	if role == "host":
		if transport == "lan":
			err = Net.host_lan("Hosty")
		else:
			err = _host_online_with_code()
		_check("host started (%d)" % err, err == OK)
		Net.set_config({"mode": "tdm", "team_count": 2, "team_size": 4, "duration": MATCH_SECONDS})
		var waited := 0.0
		while Net.players.size() < players and waited < 25.0:
			await _seconds(0.25)
			waited += 0.25
		_check("clients joined the lobby", Net.players.size() == players)
		Net.request_team(0)
		await _seconds(0.5)
		Net.start_match()
	else:
		await _seconds(1.5)
		if transport == "lan":
			err = Net.join_lan("127.0.0.1", "Clienty")
		else:
			err = Net.join_online(room, "Clienty")
		_check("client connecting (%d)" % err, err == OK)
		var waited := 0.0
		while Net.players.size() < 2 and waited < 25.0:
			await _seconds(0.25)
			waited += 0.25
			if OS.get_environment("NET_DEBUG") != "":
				print("client status ", multiplayer.multiplayer_peer.get_connection_status(), " peers ", multiplayer.get_peers(), " id ", multiplayer.get_unique_id())
		_check("client sees the lobby", Net.players.size() >= 2)
		Net.request_team(1)

	# Wait for the game scene.
	var waited2 := 0.0
	while (get_tree().current_scene == null or get_tree().current_scene.scene_file_path != "res://scenes/game.tscn") and waited2 < 20.0:
		await _seconds(0.25)
		waited2 += 0.25
	var game := get_tree().current_scene
	_check("game scene loaded", game != null and game.scene_file_path == "res://scenes/game.tscn")
	if game == null or game.scene_file_path != "res://scenes/game.tscn":
		return _finish()
	await _seconds(0.5)
	var karts := get_tree().get_nodes_in_group("karts")
	_check("8 karts (2 teams of 4)", karts.size() == 8)
	var me: Kart = game.get("player")
	_check("local player kart exists", me != null)
	var teams := {}
	for k in karts:
		teams[k.get("team")] = int(teams.get(k.get("team"), 0)) + 1
	_check("two teams of four", teams.get(0, 0) == 4 and teams.get(1, 0) == 4)
	_check("players on different teams", me != null and me.team == (0 if role == "host" else 1))
	var remote_count := 0
	for k in karts:
		if k.get("remote"):
			remote_count += 1
	# Host simulates everything except the client's kart; client only its own kart.
	_check("remote kart count (%d)" % remote_count, remote_count == (players - 1 if role == "host" else 7))

	# Wait for the countdown, then drive and shoot.
	var w := 0.0
	while not me.controls_enabled and w < 15.0:
		await _seconds(0.1)
		w += 0.1
	_check("controls enabled after countdown", me.controls_enabled)
	var start := me.global_position
	var others := {}
	for k in karts:
		if k != me:
			others[k] = (k as Node3D).global_position
	var t0 := GameState.get_time_left()
	Input.action_press("accelerate")
	Input.action_press("steer_left", 0.5)
	Input.action_press("fire")
	await _seconds(3.0)
	_check("own kart drives", me.global_position.distance_to(start) > 5.0)
	var moved := 0
	for k in others:
		if (k as Node3D).global_position.distance_to(others[k]) > 2.0:
			moved += 1
	_check("other karts move on this peer (%d/7)" % moved, moved >= 5)
	_check("clock runs (%.1f -> %.1f)" % [t0, GameState.get_time_left()], GameState.get_time_left() < t0 - 1.5)

	while not _ended:
		await _seconds(0.5)
	Input.action_release("accelerate")
	Input.action_release("steer_left")
	Input.action_release("fire")
	_check("match ended", _ended)
	_check("kills seen (%d)" % _kills, _kills > 0)
	_check("respawns seen (%d)" % _respawns, _respawns > 0)
	_check("results for all 8 karts", _results.size() == 8)
	var mine := _results.filter(func(r: Dictionary) -> bool: return bool(r.get("is_player", false)))
	_check("exactly one result marked as me", mine.size() == 1 and str(mine[0]["name"]) == me.kart_name)
	var team_rows := GameState.get_team_standings()
	_check("two team standings", team_rows.size() == 2)
	var summary := []
	for r in _results:
		summary.append("%s:%d/%d" % [r["name"], int(r["kills"]), int(r["deaths"])])
	print("RESULTS ", ",".join(summary))
	print("TEAMS ", ",".join(team_rows.map(func(t: Dictionary) -> String: return "%s:%d" % [t["name"], int(t["kills"])])))

	if role == "host":
		await _seconds(2.0)
		Net.return_to_lobby()
		await _seconds(1.0)
		_check("back in lobby", get_tree().current_scene.scene_file_path == "res://scenes/lobby.tscn")
		# Stay up so every client can confirm it is still connected.
		await _seconds(8.0)
	else:
		var w2 := 0.0
		while get_tree().current_scene.scene_file_path != "res://scenes/lobby.tscn" and w2 < 10.0:
			await _seconds(0.25)
			w2 += 0.25
		_check("client followed host back to lobby", get_tree().current_scene.scene_file_path == "res://scenes/lobby.tscn")
		_check("still connected in lobby", Net.is_active() and Net.players.size() == players)
	_finish()


func _host_online_with_code() -> Error:
	# Like Net.host_online, but with a fixed room code so the client can find it.
	Net.leave()
	var peer := SupabasePeer.new()
	var err := peer.host(url, Settings.supabase_anon_key, room)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	Net.transport = "online"
	Net.room_code = room
	Net._start_hosting("Hosty")
	return OK


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[%s] %s %s" % [role, "PASS" if ok else "FAIL", label])


func _finish() -> void:
	print("[%s] NET RESULT: %d passed, %d failed" % [role, _passed, _failed])
	Net.leave()
	get_tree().quit(1 if _failed > 0 else 0)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
