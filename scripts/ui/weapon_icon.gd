## Small vector icon for a weapon, drawn in code (no image assets).
## Use as a Control, or call WeaponIcon.draw_icon() from any CanvasItem._draw().
class_name WeaponIcon
extends Control

var weapon_id: String = "":
	set(value):
		weapon_id = value
		queue_redraw()
var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(44, 44)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, Color(color, 0.95) if weapon_id != "" else Color(1, 1, 1, 0.15))
	draw_icon(self, weapon_id, c, r * 0.72, Color(0.05, 0.07, 0.15))


static func draw_icon(ci: CanvasItem, id: String, c: Vector2, r: float, ink: Color) -> void:
	match id:
		"rocket":
			# Rocket pointing up-right with fins and a flame.
			var dir := Vector2(1, -1).normalized()
			var side := Vector2(-dir.y, dir.x)
			var tip := c + dir * r
			var tail := c - dir * r * 0.55
			ci.draw_colored_polygon(PackedVector2Array([
				tip, c + dir * r * 0.4 + side * r * 0.28, tail + side * r * 0.28,
				tail - side * r * 0.28, c + dir * r * 0.4 - side * r * 0.28]), ink)
			ci.draw_colored_polygon(PackedVector2Array([
				tail + side * r * 0.28, tail + side * r * 0.6 - dir * r * 0.3, tail - dir * r * 0.05]), ink)
			ci.draw_colored_polygon(PackedVector2Array([
				tail - side * r * 0.28, tail - side * r * 0.6 - dir * r * 0.3, tail - dir * r * 0.05]), ink)
			ci.draw_colored_polygon(PackedVector2Array([
				tail + side * r * 0.15, tail - side * r * 0.15, tail - dir * r * 0.55]), Color(1, 0.85, 0.3))
		"machine_gun":
			# Twin barrels with a grip.
			for off: float in [-0.25, 0.25]:
				ci.draw_rect(Rect2(c + Vector2(-r * 0.9, r * off - r * 0.1), Vector2(r * 1.8, r * 0.2)), ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.9, -r * 0.42), Vector2(r * 0.7, r * 0.84)), ink)
			ci.draw_rect(Rect2(c + Vector2(-r * 0.6, r * 0.3), Vector2(r * 0.3, r * 0.6)), ink)
		"mine":
			# Disc with spikes and a red light.
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				ci.draw_line(c + d * r * 0.5, c + d * r * 0.95, ink, maxf(r * 0.16, 2.0))
			ci.draw_circle(c, r * 0.62, ink)
			ci.draw_circle(c, r * 0.22, Color(1.0, 0.3, 0.25))
		"shield":
			# Shield crest.
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r), c + Vector2(r * 0.85, -r * 0.6), c + Vector2(r * 0.7, r * 0.3),
				c + Vector2(0, r), c + Vector2(-r * 0.7, r * 0.3), c + Vector2(-r * 0.85, -r * 0.6)]), ink)
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -r * 0.6), c + Vector2(r * 0.45, -r * 0.35), c + Vector2(0, r * 0.55)]),
				Color(1, 1, 1, 0.5))
		_:
			# Empty slot: a dashed ring.
			for i in 8:
				var a := TAU * float(i) / 8.0
				ci.draw_arc(c, r * 0.7, a, a + TAU / 16.0, 4, Color(1, 1, 1, 0.5), maxf(r * 0.12, 2.0))
