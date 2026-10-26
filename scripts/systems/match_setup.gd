## Builds the slot list for a match. A slot is one kart:
## {id: int, name: String, team: int (-1 in FFA), color: Color, peer: int (0 = AI),
##  weapon: String (loadout: "" = crates only, "random", or a WeaponDB id)}.
## The same setup Dictionary is sent from a network host to every client, so all
## peers create identical karts with identical ids.
class_name MatchSetup
extends RefCounted

const AI_NAMES: Array[String] = ["Bolt", "Rusty", "Nova", "Pepper", "Turbo", "Mango", "Zig",
	"Pixel", "Comet", "Fizz", "Gizmo", "Dash", "Rocco", "Juno", "Sprocket"]
const FFA_COLORS: Array[Color] = [
	Color("#ff7a1a"), Color("#ff3b6b"), Color("#ffd23f"), Color("#9b5de5"), Color("#00bbf9"),
	Color("#f15bb5"), Color("#8ac926"), Color("#ff924c"), Color("#4cc9f0"), Color("#e9ff70"),
	Color("#c77dff"), Color("#06d6a0"), Color("#ef476f"), Color("#118ab2"), Color("#ffd6a5"),
	Color("#bde0fe"),
]
const MAX_KARTS := 16


## Human players: Array of {peer: int, name: String, team: int (-1 = auto), weapon: String}.
## Bots get a random loadout whenever any human picked one, so nobody starts unarmed alone.
## FFA: humans + `ai_count` bots. TDM: `team_count` teams of `team_size`, bots fill gaps.
static func build(mode: String, humans: Array, ai_count: int, team_count: int, team_size: int,
		duration: float, ai_difficulty: float) -> Dictionary:
	var slots: Array = []
	var names_used := {}
	var bot_weapon := ""
	for h in humans:
		if str(h.get("weapon", "")) != "":
			bot_weapon = Loadout.RANDOM
	for h in humans:
		names_used[str(h.get("name", ""))] = true
	if mode == "tdm":
		team_count = clampi(team_count, 2, Teams.MAX_TEAMS)
		team_size = clampi(team_size, 1, Teams.MAX_TEAM_SIZE)
		var rosters: Array = []
		for t in team_count:
			rosters.append([])
		# Humans keep a requested team when it has room, otherwise join the smallest team.
		for h in humans:
			var want := int(h.get("team", -1))
			if want < 0 or want >= team_count or (rosters[want] as Array).size() >= team_size:
				want = _smallest_team(rosters)
			(rosters[want] as Array).append(h)
		for t in team_count:
			var members: Array = rosters[t]
			while members.size() < team_size:
				members.append({"peer": 0, "name": _bot_name(names_used), "weapon": bot_weapon})
			for m in members.size():
				var e: Dictionary = members[m]
				slots.append({"id": slots.size(), "name": str(e["name"]), "team": t,
					"color": Teams.member_color(t, m), "peer": int(e.get("peer", 0)), "weapon": Loadout.sanitize(str(e.get("weapon", "")))})
	else:
		for h in humans:
			slots.append({"id": slots.size(), "name": str(h["name"]), "team": -1,
				"color": FFA_COLORS[slots.size() % FFA_COLORS.size()], "peer": int(h.get("peer", 1)),
				"weapon": Loadout.sanitize(str(h.get("weapon", "")))})
		var bots := clampi(ai_count, 0, MAX_KARTS - slots.size())
		for i in bots:
			slots.append({"id": slots.size(), "name": _bot_name(names_used), "team": -1,
				"color": FFA_COLORS[slots.size() % FFA_COLORS.size()], "peer": 0, "weapon": bot_weapon})
	return {"mode": mode, "duration": duration, "team_count": team_count if mode == "tdm" else 0,
		"ai_difficulty": ai_difficulty, "map": Maps.DEFAULT, "slots": slots}


## Single-player match from the saved settings.
static func offline_from_settings() -> Dictionary:
	var n := Settings.player_name.strip_edges()
	var human := {"peer": 1, "name": n if n != "" else "You", "team": 0, "weapon": Settings.weapon_pick}
	var setup := build(Settings.game_mode, [human], Settings.ai_count, Settings.team_count,
		Settings.team_size, GameState.match_duration, Settings.ai_difficulty)
	setup["map"] = Maps.resolve(Settings.map_id)
	return setup


## Converts Colors to strings so a setup survives var_to_bytes / JSON (network).
static func to_wire(setup: Dictionary) -> Dictionary:
	var out := setup.duplicate(true)
	for s in out["slots"]:
		s["color"] = (s["color"] as Color).to_html()
	return out


static func from_wire(setup: Dictionary) -> Dictionary:
	var out := setup.duplicate(true)
	for s in out["slots"]:
		if s["color"] is String:
			s["color"] = Color.html(s["color"])
		s["id"] = int(s["id"])
		s["team"] = int(s["team"])
		s["peer"] = int(s["peer"])
		s["weapon"] = Loadout.sanitize(str(s.get("weapon", "")))
	return out


static func _smallest_team(rosters: Array) -> int:
	var best := 0
	for t in rosters.size():
		if (rosters[t] as Array).size() < (rosters[best] as Array).size():
			best = t
	return best


static func _bot_name(used: Dictionary) -> String:
	for n in AI_NAMES:
		if not used.has(n):
			used[n] = true
			return n
	var i := used.size()
	var name := "Bot %d" % i
	used[name] = true
	return name
