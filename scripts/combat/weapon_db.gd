## Static weapon data. Ids are stable; display names are original.
class_name WeaponDB
extends RefCounted

const WEAPONS := {
	"rocket": {
		"name": "Comet Rocket",
		"ammo": 2,
		"cooldown": 0.6,
		"damage": 45.0,
		"color": Color(1.0, 0.42, 0.12),
		"auto": false,
		"weight": 1.0,
		"speed": 34.0,
		"lifetime": 3.0,
		"radius": 4.0,           # explosion radius (m)
		"knockback": 10.0,
		"homing_angle": 16.0,    # degrees, half-angle of the lock-on cone
		"homing_range": 45.0,
		"homing_turn": 2.0,      # rad/s
	},
	"machine_gun": {
		"name": "Buzz Blaster",
		"ammo": 30,
		"cooldown": 0.08,
		"damage": 4.0,
		"color": Color(1.0, 0.9, 0.25),
		"auto": true,
		"weight": 1.0,
		"speed": 110.0,
		"lifetime": 0.55,
		"spread": 2.5,           # degrees
		"knockback": 0.6,
	},
	"mine": {
		"name": "Pop Mine",
		"ammo": 3,
		"cooldown": 0.35,
		"damage": 50.0,
		"color": Color(0.95, 0.2, 0.55),
		"auto": false,
		"weight": 1.0,
		"arm_time": 0.6,
		"lifetime": 25.0,
		"trigger_radius": 1.8,
		"radius": 3.5,
		"knockback": 9.0,
	},
	"shield": {
		"name": "Bubble Shield",
		"ammo": 1,
		"cooldown": 0.5,
		"damage": 0.0,
		"color": Color(0.3, 0.85, 1.0),
		"auto": false,
		"weight": 0.5,
		"duration": 5.0,
	},
}


static func has_weapon(id: String) -> bool:
	return WEAPONS.has(id)


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for id in WEAPONS:
		out.append(String(id))
	return out


static func get_data(id: String) -> Dictionary:
	return WEAPONS.get(id, {})


static func get_stat(id: String, key: String, default: Variant = null) -> Variant:
	return get_data(id).get(key, default)


static func get_display_name(id: String) -> String:
	return String(get_stat(id, "name", ""))


static func get_color(id: String) -> Color:
	var c: Variant = get_stat(id, "color", Color(0.7, 0.7, 0.7))
	return c


static func get_ammo(id: String) -> int:
	return int(get_stat(id, "ammo", 0))


static func get_cooldown(id: String) -> float:
	return float(get_stat(id, "cooldown", 0.5))


static func get_damage(id: String) -> float:
	return float(get_stat(id, "damage", 0.0))


static func is_auto_fire(id: String) -> bool:
	return bool(get_stat(id, "auto", false))


## Weighted random weapon id.
static func random_id() -> String:
	var total := 0.0
	for id in WEAPONS:
		total += float(WEAPONS[id].get("weight", 1.0))
	var r := randf() * total
	for id in WEAPONS:
		r -= float(WEAPONS[id].get("weight", 1.0))
		if r <= 0.0:
			return String(id)
	return "rocket"
