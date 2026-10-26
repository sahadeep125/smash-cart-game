## Team Deathmatch rules test (offline).
## Run: godot --headless --fixed-fps 60 --path . res://tests/team_test.tscn
extends Node

var _passed := 0
var _failed := 0


func _ready() -> void:
	if get_tree().current_scene == self:
		var driver: Node = (get_script() as GDScript).new()
		driver.name = "TeamTestDriver"
		get_tree().root.add_child.call_deferred(driver)
		return
	_run()


func _run() -> void:
	# MatchSetup: 3 teams of 4 with one human.
	var setup := MatchSetup.build("tdm", [{"peer": 1, "name": "You", "team": 2}], 0, 3, 4, 60.0, 0.6)
	var slots: Array = setup["slots"]
	_check("12 slots for 3 teams of 4", slots.size() == 12)
	var per_team := {}
	for s in slots:
		per_team[s["team"]] = int(per_team.get(s["team"], 0)) + 1
	_check("4 per team", per_team.get(0) == 4 and per_team.get(1) == 4 and per_team.get(2) == 4)
	_check("human kept requested team", slots.filter(func(s: Dictionary) -> bool: return s["peer"] == 1)[0]["team"] == 2)
	var wire := MatchSetup.from_wire(MatchSetup.to_wire(setup))
	_check("setup survives the wire format", wire["slots"].size() == 12 and wire["slots"][5]["color"] is Color)
	var ffa := MatchSetup.build("ffa", [{"peer": 1, "name": "You"}], 15, 2, 4, 60.0, 0.6)
	_check("FFA caps at 16 karts", (ffa["slots"] as Array).size() == 16)

	# Full TDM match scene: 2 teams of 2.
	GameState.match_duration = 60.0
	GameState.set_setup(MatchSetup.build("tdm", [{"peer": 1, "name": "You", "team": 0}], 0, 2, 2, 60.0, 0.6))
	get_tree().change_scene_to_file("res://scenes/game.tscn")
	await _seconds(0.5)
	var game := get_tree().current_scene
	var karts: Array = game.get("karts")
	var me: Kart = game.get("player")
	var ally: Kart = null
	var enemy: Kart = null
	for k: Kart in karts:
		if k != me and k.team == me.team:
			ally = k
		elif k.team != me.team:
			enemy = k
	_check("ally and enemy exist", ally != null and enemy != null)
	_check("team colours differ", ally.kart_color != enemy.kart_color and absf(ally.kart_color.h - me.kart_color.h) < 0.05)
	_check("allies recognised", me.is_ally(ally) and not me.is_ally(enemy) and CombatUtil.are_allies(me, ally))
	_check("bots have name tags", ally.get_node_or_null("NameTag") != null)
	_check("GameState in team mode", GameState.is_team_mode())
	await _seconds(4.0)  # countdown + spawn protection

	var ally_hp := ally.get_health()
	var enemy_hp := enemy.get_health()
	ally_hp.set_invulnerable(0.0)
	enemy_hp.set_invulnerable(0.0)
	CombatUtil.deal_damage(ally, 30.0, me, "rocket")
	_check("no friendly fire", is_equal_approx(ally_hp.current_health, ally_hp.max_health))
	CombatUtil.deal_damage(enemy, 30.0, me, "rocket")
	_check("enemies take damage", enemy_hp.current_health < enemy_hp.max_health)
	var root := CombatUtil.get_projectile_root(game)
	ally.global_position = me.global_position + Vector3(3, 0, 0)
	Explosion.spawn(root, ally.global_position + Vector3.UP * 0.5, 4.0, 50.0, me, "rocket")
	await _seconds(0.2)
	_check("own explosion spares teammates", is_equal_approx(ally_hp.current_health, ally_hp.max_health))

	enemy_hp.take_damage(500.0, me, "rocket")
	await _seconds(0.1)
	_check("enemy kill scores for the team", int(GameState.get_score(me.kart_name)["kills"]) == 1)
	var standings := GameState.get_team_standings()
	_check("team standings lead with my team", standings.size() == 2 and int(standings[0]["team"]) == me.team and int(standings[0]["kills"]) == 1)

	var ai := ally.get_node_or_null("AIDriver") as AIDriver
	var picked: Kart = ai.call("_pick_enemy") if ai else null
	_check("bot never targets a teammate", picked == null or picked.team != ally.team)

	GameState.end_match()
	await _seconds(1.6)
	var end_screen: MatchEndScreen = game.get("hud").match_end_screen
	_check("team win banner", end_screen.is_shown() and end_screen.get_banner_text() == "YOUR TEAM WINS!")
	print("TEAM RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)


func _check(label: String, ok: bool) -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])


func _seconds(s: float) -> void:
	await get_tree().create_timer(s, true, true).timeout
