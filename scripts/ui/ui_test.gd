## Headless UI / systems test.
## Run: godot --headless --path . res://scripts/ui/ui_test.tscn
extends Node


class StubHealth extends Node:
	signal health_changed(current: float, max: float)
	signal died(killer: Node)
	var current_health := 100.0
	var max_health := 100.0


class StubHolder extends Node:
	signal weapon_changed(weapon_id: String, ammo: int)
	var current_weapon_id := ""
	var ammo := 0


class StubKart extends Node3D:
	var kart_name := ""
	var is_player := false
	var alive := true
	var controls_enabled := true

	func _init(p_name: String, p_player: bool) -> void:
		kart_name = p_name
		is_player = p_player
		name = p_name
		var h := StubHealth.new()
		h.name = "Health"
		add_child(h)
		var w := StubHolder.new()
		w.name = "WeaponHolder"
		add_child(w)
		add_to_group("karts")

	func get_health() -> Node:
		return get_node("Health")

	func get_weapon_holder() -> Node:
		return get_node("WeaponHolder")


var _passed := 0
var _failed := 0
var _time_events := 0
var _score_events := 0
var _started := false
var _ended_results: Array = []


func check(label: String, ok: bool, detail := "") -> void:
	if ok:
		_passed += 1
		print("PASS: ", label)
	else:
		_failed += 1
		print("FAIL: ", label, ("  (" + detail + ")") if detail != "" else "")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	Events.match_time_changed.connect(func(_s: float) -> void: _time_events += 1)
	Events.score_changed.connect(func(_n: String, _k: int, _d: int) -> void: _score_events += 1)
	Events.match_started.connect(func() -> void: _started = true)
	Events.match_ended.connect(func(r: Array) -> void: _ended_results = r)

	_test_settings()
	await _test_hud_and_match()
	await _test_touch_controls()
	_test_theme_and_menus()

	print("---- %d passed, %d failed ----" % [_passed, _failed])
	print("ALL TESTS PASSED" if _failed == 0 else "SOME TESTS FAILED")
	get_tree().quit(0 if _failed == 0 else 1)


# --- Settings ---------------------------------------------------------------

func _test_settings() -> void:
	var original_path: String = Settings.save_path
	Settings.save_path = "user://ui_test_settings.cfg"
	Settings.master_volume = 0.35
	Settings.sfx_volume = 0.5
	Settings.music_volume = 0.1
	Settings.touch_controls = "on"
	Settings.ai_count = 3
	Settings.ai_difficulty = 0.9
	Settings.camera_shake = false
	Settings.show_fps = true
	Settings.save()
	# Scramble, then load back.
	Settings.master_volume = 1.0
	Settings.touch_controls = "off"
	Settings.ai_count = 7
	Settings.ai_difficulty = 0.3
	Settings.camera_shake = true
	Settings.show_fps = false
	Settings.load_settings()
	check("settings roundtrip volumes", is_equal_approx(Settings.master_volume, 0.35) and is_equal_approx(Settings.music_volume, 0.1))
	check("settings roundtrip touch/ai", Settings.touch_controls == "on" and Settings.ai_count == 3 and is_equal_approx(Settings.ai_difficulty, 0.9))
	check("settings roundtrip toggles", Settings.camera_shake == false and Settings.show_fps == true)
	check("settings difficulty name", Settings.get_difficulty_name() == "Hard")
	check("audio buses exist", AudioServer.get_bus_index("SFX") != -1 and AudioServer.get_bus_index("Music") != -1)
	var master_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Master"))
	check("master bus volume applied", is_equal_approx(master_db, linear_to_db(0.35)), str(master_db))
	check("touch 'on' -> shown", Settings.should_show_touch_controls())
	Settings.touch_controls = "off"
	check("touch 'off' -> hidden", not Settings.should_show_touch_controls())
	Settings.touch_controls = "auto"
	Settings.should_show_touch_controls()  # must not crash headless
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.save_path))
	Settings.save_path = original_path
	Settings.touch_controls = "on"
	Settings.apply()


# --- HUD + GameState ------------------------------------------------------------

func _test_hud_and_match() -> void:
	var player := StubKart.new("You", true)
	var rival_a := StubKart.new("Blaze", false)
	var rival_b := StubKart.new("Nova", false)
	for k in [player, rival_a, rival_b]:
		add_child(k)

	var hud := HUD.new()
	add_child(hud)
	hud.match_end_screen.show_delay = 0.0
	hud.countdown_step = 0.05

	GameState.match_duration = 5.0
	GameState.start_match([player, rival_a, rival_b])
	check("match_started emitted", _started)
	check("GameState running", GameState.is_running())
	GameState.set_paused_clock(true)
	hud.bind_player(player)
	# Countdown awaited in the same frame as bind_player.
	await hud.play_countdown()
	check("countdown finished", true)
	GameState._process(3.0)
	check("paused clock does not tick", is_equal_approx(GameState.get_time_left(), 5.0), str(GameState.get_time_left()))
	GameState.set_paused_clock(false)

	check("touch controls shown when 'on'", hud.get_touch_controls().visible)
	Settings.touch_controls = "off"
	Settings.apply()
	check("touch controls hidden after settings change", not hud.get_touch_controls().visible)
	Settings.touch_controls = "on"
	Settings.apply()

	# Health / weapon panels follow the stub signals.
	player.get_health().health_changed.emit(40.0, 100.0)
	check("health bar updates", hud._health_label.text == "40 / 100", hud._health_label.text)
	player.get_weapon_holder().weapon_changed.emit("rocket", 3)
	check("weapon panel updates", hud._weapon_label.text.contains("ROCKET") and hud._weapon_label.text.contains("3"), hud._weapon_label.text)

	# Timer: one match_time_changed per whole second.
	_time_events = 0
	for i in 8:
		GameState._process(0.25)
	check("time_changed once per second", _time_events == 2, str(_time_events))
	check("timer label MM:SS", hud.get_timer_text() == "0:03", hud.get_timer_text())

	# Pause menu pauses the tree.
	hud.pause_menu.open()
	check("pause menu pauses tree", get_tree().paused and hud.pause_menu.is_open())
	hud.pause_menu.close()
	check("resume unpauses tree", not get_tree().paused)

	# Kills.
	_score_events = 0
	Events.kart_killed.emit(rival_a, player, "rocket")
	Events.kart_killed.emit(rival_b, player, "mine")
	Events.kart_killed.emit(player, rival_a, "rocket")
	check("respawn overlay on player death", hud.is_respawn_overlay_visible())
	Events.kart_respawned.emit(player)
	check("respawn overlay hidden on respawn", not hud.is_respawn_overlay_visible())
	Events.kart_killed.emit(rival_b, null, "")
	Events.kart_killed.emit(rival_a, rival_a, "")
	var s_p := GameState.get_score("You")
	var s_a := GameState.get_score("Blaze")
	var s_b := GameState.get_score("Nova")
	check("player score 2/1", s_p["kills"] == 2 and s_p["deaths"] == 1, str(s_p))
	check("Blaze score 1/2", s_a["kills"] == 1 and s_a["deaths"] == 2, str(s_a))
	check("Nova score 0/2 (self/null kill = death only)", s_b["kills"] == 0 and s_b["deaths"] == 2, str(s_b))
	check("score_changed emitted", _score_events == 8, str(_score_events))
	check("kill feed capped at 4", hud.get_kill_feed_count() == 4, str(hud.get_kill_feed_count()))
	check("kill counter label", hud._kills_label.text == "KILLS 2", hud._kills_label.text)
	check("rank lookup", GameState.get_rank("You") == 1 and GameState.get_rank("Nova") == 3)

	# Run out the clock.
	GameState._process(10.0)
	await get_tree().process_frame
	check("match ended", not GameState.is_running() and _ended_results.size() == 3)
	var names := _ended_results.map(func(r: Dictionary) -> String: return r["name"])
	check("results sorted kills desc, deaths asc", names == ["You", "Blaze", "Nova"], str(names))
	check("results carry is_player", _ended_results[0]["is_player"] == true and _ended_results[1]["is_player"] == false)
	check("controls disabled at match end", not player.controls_enabled and not rival_a.controls_enabled)
	check("match end screen shown", hud.match_end_screen.is_shown())
	check("winner banner", hud.match_end_screen.get_banner_text() == "YOU WIN!", hud.match_end_screen.get_banner_text())
	check("touch controls hidden at match end", not hud.get_touch_controls().visible)
	hud.pause_menu.open()
	check("cannot pause after match end", not get_tree().paused)

	# Rival-wins banner.
	hud.match_end_screen.show_results([
		{"name": "Blaze", "kills": 4, "deaths": 0, "is_player": false},
		{"name": "You", "kills": 1, "deaths": 2, "is_player": true}])
	check("rival winner banner", hud.match_end_screen.get_banner_text() == "BLAZE WINS!", hud.match_end_screen.get_banner_text())

	hud.queue_free()
	for k in [player, rival_a, rival_b]:
		k.queue_free()
	GameState.reset()
	GameState.match_duration = 180.0
	await get_tree().process_frame


# --- Touch controls -------------------------------------------------------------

func _touch(tc: TouchControls, index: int, pos: Vector2, pressed: bool) -> bool:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	return tc.handle_event(ev)


func _drag(tc: TouchControls, index: int, pos: Vector2) -> bool:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = pos
	return tc.handle_event(ev)


func _test_touch_controls() -> void:
	var holder := Control.new()
	holder.size = Vector2(1280, 720)
	add_child(holder)
	var tc := TouchControls.new()
	holder.add_child(tc)
	await get_tree().process_frame
	tc._layout()

	var gas := tc.get_button_center("accelerate")
	var fire := tc.get_button_center("fire")
	var stick := tc.get_stick_rest_center()
	check("buttons laid out on the right", gas.x > 900 and fire.x > 800, "%s %s" % [gas, fire])
	check("stick laid out on the left", stick.x < 400 and stick.y > 360, str(stick))

	check("gas touch consumed", _touch(tc, 0, gas, true))
	check("accelerate pressed", Input.is_action_pressed("accelerate"))
	_touch(tc, 1, stick, true)
	_drag(tc, 1, stick + Vector2(tc.get_stick_radius(), 0))
	check("steer_right pressed by joystick", Input.is_action_pressed("steer_right") and Input.get_action_strength("steer_right") > 0.9,
		str(Input.get_action_strength("steer_right")))
	_drag(tc, 1, stick + Vector2(-tc.get_stick_radius() * 3.0, 0))
	check("steer_left after dragging left", Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"))
	_touch(tc, 2, fire, true)
	check("fire pressed together with gas + steer", Input.is_action_pressed("fire") and Input.is_action_pressed("accelerate") and Input.is_action_pressed("steer_left"))
	_touch(tc, 0, gas, false)
	check("gas released by its own finger", not Input.is_action_pressed("accelerate") and Input.is_action_pressed("fire"))
	_touch(tc, 1, stick, false)
	check("steer released", not Input.is_action_pressed("steer_left") and not Input.is_action_pressed("steer_right"))
	check("touch in empty area passes through", not _touch(tc, 3, Vector2(640, 60), true))

	_touch(tc, 4, tc.get_button_center("drift"), true)
	_touch(tc, 5, tc.get_button_center("brake"), true)
	check("drift + brake pressed", Input.is_action_pressed("drift") and Input.is_action_pressed("brake"))
	tc.visible = false
	check("hiding releases all actions", not Input.is_action_pressed("fire") and not Input.is_action_pressed("drift") and not Input.is_action_pressed("brake"))
	check("hidden controls ignore touches", not _touch(tc, 6, gas, true) and not Input.is_action_pressed("accelerate"))
	tc.visible = true
	_touch(tc, 7, gas, true)
	holder.queue_free()
	await get_tree().process_frame
	check("exit tree releases actions", not Input.is_action_pressed("accelerate"))


# --- Theme / menus --------------------------------------------------------------

func _test_theme_and_menus() -> void:
	var t := ThemeBuilder.get_theme()
	check("theme built", t != null and t.has_stylebox("normal", "Button"))
	var packed: PackedScene = load("res://scenes/main_menu.tscn")
	var menu := packed.instantiate()
	add_child(menu)
	check("main menu instantiates", menu.get_child_count() > 0)
	menu.queue_free()
