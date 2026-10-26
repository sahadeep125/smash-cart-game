## Match state (autoload "GameState"): countdown timer and per-kart scores.
## The timer only runs in _process, so it stops while the tree is paused.
extends Node

var match_duration := 180.0
## "ffa" (free-for-all) or "tdm" (team deathmatch).
var mode := "ffa"
## Setup for the next game scene (see MatchSetup); empty = solo match from Settings.
var _pending_setup: Dictionary = {}
## False on networked clients: the host owns the clock and ends the match.
var authority := true

var _running := false
var _clock_paused := false
var _time_left := 0.0
var _last_whole_second := -1
## kart_name -> {name, kills, deaths, is_player, team, kart_id}
var _scores: Dictionary = {}
## Registration order, used as a stable tiebreaker.
var _order: Array[String] = []
var _results: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	Events.kart_killed.connect(_on_kart_killed)


func _process(delta: float) -> void:
	if not _running or _clock_paused or not authority:
		return
	_time_left = maxf(_time_left - delta, 0.0)
	var whole := int(ceil(_time_left))
	if whole != _last_whole_second:
		_last_whole_second = whole
		Events.match_time_changed.emit(_time_left)
	if _time_left <= 0.0:
		end_match()


# --- Public API ---------------------------------------------------------------

func start_match(karts: Array) -> void:
	_scores.clear()
	_order.clear()
	_results.clear()
	for kart in karts:
		if kart == null:
			continue
		_register(_name_of(kart), _is_player(kart), _team_of(kart), _id_of(kart))
	_clock_paused = false
	_time_left = match_duration
	_last_whole_second = int(ceil(_time_left))
	_running = true
	Events.match_started.emit()
	Events.match_time_changed.emit(_time_left)


func end_match() -> void:
	if not _running:
		return
	_running = false
	_clock_paused = false
	_time_left = maxf(_time_left, 0.0)
	var tree := get_tree()
	if tree:
		for kart in tree.get_nodes_in_group("karts"):
			if "controls_enabled" in kart:
				kart.controls_enabled = false
	_results = _build_results()
	Events.match_ended.emit(_results.duplicate(true))


## Stops any match silently (no match_ended) and clears scores.
## Call before leaving / reloading the game scene mid-match.
func reset() -> void:
	authority = true
	_running = false
	_clock_paused = false
	_time_left = match_duration
	_scores.clear()
	_order.clear()
	_results.clear()


## While true the match stays "running" (scores count) but the clock does not tick.
## Used for the pre-match countdown.
func set_paused_clock(paused: bool) -> void:
	_clock_paused = paused


func is_clock_paused() -> bool:
	return _clock_paused


func is_running() -> bool:
	return _running


func get_time_left() -> float:
	return _time_left


## Returns {name, kills, deaths, is_player}; zeroes for unknown names.
func get_score(kart_name: String) -> Dictionary:
	if _scores.has(kart_name):
		return (_scores[kart_name] as Dictionary).duplicate()
	return {"name": kart_name, "kills": 0, "deaths": 0, "is_player": false}


## Sorted standings (kills desc, deaths asc). Live during a match, final after it.
func get_results() -> Array:
	if not _running and not _results.is_empty():
		return _results.duplicate(true)
	return _build_results()


func set_setup(setup: Dictionary) -> void:
	_pending_setup = setup


## Returns and clears the pending setup.
func take_setup() -> Dictionary:
	var s := _pending_setup
	_pending_setup = {}
	return s


## Networked clients: the host ended the match with these results.
func end_match_remote(results: Array, my_kart_id: int) -> void:
	if not _running:
		return
	_running = false
	for r in results:
		r["is_player"] = int(r.get("kart_id", -1)) == my_kart_id
	apply_remote_scores(results)
	var tree := get_tree()
	if tree:
		for kart in tree.get_nodes_in_group("karts"):
			if "controls_enabled" in kart:
				kart.controls_enabled = false
	_results = results
	Events.match_ended.emit(_results.duplicate(true))


func is_team_mode() -> bool:
	return mode == "tdm"


## Team standings for Team Deathmatch, best first:
## [{team, name, color, kills, deaths, members}].
func get_team_standings() -> Array:
	var by_team := {}
	for n in _order:
		var e: Dictionary = _scores[n]
		var t := int(e.get("team", -1))
		if t < 0:
			continue
		if not by_team.has(t):
			by_team[t] = {"team": t, "name": Teams.team_name(t), "color": Teams.team_color(t),
				"kills": 0, "deaths": 0, "members": 0}
		var d: Dictionary = by_team[t]
		d["kills"] = int(d["kills"]) + int(e["kills"])
		d["deaths"] = int(d["deaths"]) + int(e["deaths"])
		d["members"] = int(d["members"]) + 1
	var list: Array = by_team.values()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["kills"] != b["kills"]:
			return a["kills"] > b["kills"]
		if a["deaths"] != b["deaths"]:
			return a["deaths"] < b["deaths"]
		return a["team"] < b["team"])
	return list


## Overwrites scores with a host's authoritative copy (networked clients).
func apply_remote_scores(entries: Array) -> void:
	for e in entries:
		var n := str(e.get("name", ""))
		if n == "":
			continue
		var is_me := false
		if _scores.has(n):
			is_me = bool(_scores[n].get("is_player", false))
		else:
			_order.append(n)
		var copy: Dictionary = (e as Dictionary).duplicate()
		copy["is_player"] = is_me
		_scores[n] = copy


## Sets the clock from the host (networked clients).
func apply_remote_time(seconds_left: float) -> void:
	_time_left = maxf(seconds_left, 0.0)
	var whole := int(ceil(_time_left))
	if whole != _last_whole_second:
		_last_whole_second = whole
		Events.match_time_changed.emit(_time_left)


## 1-based rank of a kart in the current standings (0 if unknown).
func get_rank(kart_name: String) -> int:
	var results := _build_results()
	for i in results.size():
		if results[i]["name"] == kart_name:
			return i + 1
	return 0


# --- Internals ----------------------------------------------------------------

func _on_kart_killed(victim: Node, killer: Node, _weapon_id: String) -> void:
	if not _running or victim == null:
		return
	var victim_name := _name_of(victim)
	_register(victim_name, _is_player(victim), _team_of(victim), _id_of(victim))
	var v: Dictionary = _scores[victim_name]
	v["deaths"] = int(v["deaths"]) + 1
	Events.score_changed.emit(victim_name, int(v["kills"]), int(v["deaths"]))
	if killer == null or killer == victim or not is_instance_valid(killer):
		return
	var killer_name := _name_of(killer)
	if killer_name == victim_name:
		return
	if mode == "tdm" and _team_of(killer) >= 0 and _team_of(killer) == _team_of(victim):
		return  # team kills never score
	_register(killer_name, _is_player(killer), _team_of(killer), _id_of(killer))
	var k: Dictionary = _scores[killer_name]
	k["kills"] = int(k["kills"]) + 1
	Events.score_changed.emit(killer_name, int(k["kills"]), int(k["deaths"]))


func _register(kart_name: String, player: bool, team := -1, kart_id := -1) -> void:
	if _scores.has(kart_name):
		return
	_scores[kart_name] = {"name": kart_name, "kills": 0, "deaths": 0, "is_player": player,
		"team": team, "kart_id": kart_id}
	_order.append(kart_name)


func _build_results() -> Array:
	var list: Array = []
	for n in _order:
		var entry: Dictionary = (_scores[n] as Dictionary).duplicate()
		entry["order"] = _order.find(n)
		list.append(entry)
	list.sort_custom(_compare_results)
	for entry in list:
		entry.erase("order")
	return list


static func _compare_results(a: Dictionary, b: Dictionary) -> bool:
	if a["kills"] != b["kills"]:
		return a["kills"] > b["kills"]
	if a["deaths"] != b["deaths"]:
		return a["deaths"] < b["deaths"]
	return a["order"] < b["order"]


static func _name_of(kart: Object) -> String:
	if kart != null and "kart_name" in kart:
		var n := str(kart.kart_name)
		if n != "":
			return n
	if kart is Node:
		return str((kart as Node).name)
	return "?"


static func _team_of(kart: Object) -> int:
	if kart != null and is_instance_valid(kart) and "team" in kart:
		return int(kart.team)
	return -1


static func _id_of(kart: Object) -> int:
	if kart != null and is_instance_valid(kart) and "net_id" in kart:
		return int(kart.net_id)
	return -1


static func _is_player(kart: Object) -> bool:
	return kart != null and "is_player" in kart and bool(kart.is_player)
