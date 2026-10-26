## The list of battle maps. Ids are stable (saved in settings, sent over the network).
class_name Maps
extends RefCounted

const RANDOM := "random"
const DEFAULT := "scrapyard"

const LIST := [
	{"id": "scrapyard", "name": "Sunset Scrapyard", "blurb": "Junkyard at dusk. Raised centre platform, kicker jumps.",
		"accent": Color("#ff8a3d")},
	{"id": "harbor", "name": "Frostbite Harbor", "blurb": "Frozen pond in the middle (slippery!) and two raised docks.",
		"accent": Color("#7fd3ff")},
	{"id": "rooftop", "name": "Neon Rooftops", "blurb": "Night roof with four corner decks and boost pads.",
		"accent": Color("#ff4fd8")},
	{"id": "temple", "name": "Temple Ruins", "blurb": "Jungle temple with ramps on all sides and stone heads.",
		"accent": Color("#7ed957")},
]


static func ids() -> Array[String]:
	var out: Array[String] = []
	for m in LIST:
		out.append(str(m["id"]))
	return out


static func has_map(id: String) -> bool:
	return ids().has(id)


static func info(id: String) -> Dictionary:
	for m in LIST:
		if m["id"] == id:
			return m
	return LIST[0]


static func display_name(id: String) -> String:
	if id == RANDOM:
		return "Random map"
	return str(info(id)["name"])


## Resolves "random" (and unknown ids) to a real map id.
static func resolve(id: String) -> String:
	if id == RANDOM:
		var all := ids()
		return all[randi() % all.size()]
	return id if has_map(id) else DEFAULT


static func create(id: String) -> ArenaBase:
	match resolve(id):
		"harbor":
			return FrostHarbor.new()
		"rooftop":
			return NeonRooftop.new()
		"temple":
			return TempleRuins.new()
	return Arena.new()
