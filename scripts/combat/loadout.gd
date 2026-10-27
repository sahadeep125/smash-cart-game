## Weapon loadouts: the weapon a kart starts each life with.
## "" = none (weapons only from crates), "random" = a new random weapon every life,
## or a WeaponDB id. Crates still hand out random weapons either way.
class_name Loadout
extends RefCounted

const NONE := ""
const RANDOM := "random"


## Every choice in picker order.
static func choices() -> Array[String]:
	var out: Array[String] = [NONE, RANDOM]
	out.append_array(WeaponDB.all_ids())
	return out


static func sanitize(id: String) -> String:
	return id if id == NONE or id == RANDOM or WeaponDB.has_weapon(id) else NONE


static func label(id: String) -> String:
	match id:
		NONE:
			return "Crates only"
		RANDOM:
			return "Random"
	return WeaponDB.get_display_name(id)


## The weapon to hand out for one life ("" when the kart starts empty).
static func roll(id: String) -> String:
	if id == RANDOM:
		return WeaponDB.random_id()
	return id if WeaponDB.has_weapon(id) else ""
