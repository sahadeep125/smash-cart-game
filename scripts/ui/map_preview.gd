## Top-down drawing of a map, built from the map's own layout (ArenaBase.footprints),
## so previews always match the real geometry. Layouts are built once and cached.
class_name MapPreview
extends Control

static var _cache := {}

var map_id: String = Maps.DEFAULT:
	set(value):
		map_id = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(120, 120)


## {half_size, ground, wall, footprints, spawns: Array[Vector2], crates: Array[Vector2]}
static func layout(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var arena := Maps.create(id)
	arena.build_layout()
	var spawns: Array[Vector2] = []
	for m in arena.get_spawn_points():
		spawns.append(Vector2(m.position.x, m.position.z))
	var crates: Array[Vector2] = []
	for m in arena.get_crate_spawn_points():
		crates.append(Vector2(m.position.x, m.position.z))
	var data := {"half_size": arena.half_size, "ground": arena.ground_color, "wall": arena.wall_color,
		"footprints": arena.footprints.duplicate(), "spawns": spawns, "crates": crates}
	arena.free()
	_cache[id] = data
	return data


func _draw() -> void:
	var side := minf(size.x, size.y)
	var origin := (size - Vector2(side, side)) * 0.5
	if map_id == Maps.RANDOM:
		draw_rect(Rect2(origin, Vector2(side, side)), ThemeBuilder.NAVY, true)
		var font := get_theme_default_font()
		var fs := int(side * 0.55)
		draw_string(font, origin + Vector2(0, side * 0.5 + fs * 0.36), "?", HORIZONTAL_ALIGNMENT_CENTER, side, fs, ThemeBuilder.TEAL_LIGHT)
		return
	var d := layout(map_id)
	var half: float = d["half_size"]
	var scale := side / (half * 2.0 + 4.0)
	var to_px := func(p: Vector2) -> Vector2:
		return origin + Vector2(side, side) * 0.5 + p * scale
	# Walls and floor.
	draw_rect(Rect2(origin, Vector2(side, side)), d["wall"], true)
	var inner := Vector2(half, half) * 2.0 * scale
	draw_rect(Rect2(origin + (Vector2(side, side) - inner) * 0.5, inner), d["ground"], true)
	# Footprints, lowest first so raised areas draw on top.
	var fps: Array = d["footprints"]
	var sorted := fps.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("height", 0.0)) < float(b.get("height", 0.0)))
	for f in sorted:
		match str(f["kind"]):
			"zone":
				var col := Color(0.55, 0.85, 1.0, 0.85) if f["type"] == "ice" else Color(0.1, 0.95, 1.0, 0.95)
				var c: Vector2 = f["center"]
				var h: Vector2 = f["half"]
				draw_rect(Rect2(to_px.call(c - h), h * 2.0 * scale), col, true)
			"rect":
				var c: Vector2 = f["center"]
				var h: Vector2 = f["half"]
				var yaw := float(f.get("yaw", 0.0))
				var pts := PackedVector2Array()
				for corner: Vector2 in [Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)]:
					pts.append(to_px.call(c + corner.rotated(yaw)))
				draw_colored_polygon(pts, _shade(f))
			"circle":
				draw_circle(to_px.call(f["center"]), maxf(float(f["radius"]) * scale, 1.5), _shade(f))
			"poly":
				var pts := PackedVector2Array()
				for p in (f["points"] as PackedVector2Array):
					pts.append(to_px.call(p))
				draw_colored_polygon(pts, _shade(f))
	for p: Vector2 in d["crates"]:
		var q: Vector2 = to_px.call(p)
		var s := maxf(side * 0.018, 2.0)
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -s), q + Vector2(s, 0), q + Vector2(0, s), q + Vector2(-s, 0)]), Color(1, 0.85, 0.3))
	for p: Vector2 in d["spawns"]:
		draw_circle(to_px.call(p), maxf(side * 0.014, 1.5), Color(1, 1, 1, 0.8))


## Taller pieces are drawn a little lighter so height reads at a glance.
static func _shade(f: Dictionary) -> Color:
	var col: Color = f.get("color", Color.GRAY)
	return col.lightened(clampf(float(f.get("height", 0.0)) * 0.04, 0.0, 0.25))
