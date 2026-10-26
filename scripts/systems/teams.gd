## Team Deathmatch team data: names and colours (static helpers, no state).
class_name Teams
extends RefCounted

const MAX_TEAMS := 4
const MAX_TEAM_SIZE := 4
const NAMES: Array[String] = ["Blaze", "Wave", "Moss", "Volt"]
const COLORS: Array[Color] = [Color("#ff4b3e"), Color("#2f8cff"), Color("#3fcf5a"), Color("#ffcc1f")]


static func team_name(team: int) -> String:
	return NAMES[team] if team >= 0 and team < NAMES.size() else "Free"


static func team_color(team: int) -> Color:
	return COLORS[team] if team >= 0 and team < COLORS.size() else Color.WHITE


## Kart body colour for the `member`-th kart of a team: same hue, varied shade.
static func member_color(team: int, member: int) -> Color:
	var base := team_color(team)
	var shades := [0.0, 0.18, -0.14, 0.32]
	var s: float = shades[member % shades.size()]
	return base.lightened(s) if s >= 0.0 else base.darkened(-s)
