## Round radar: karts around the player (team colours, enemies red in FFA) and
## available weapon crates. "Up" on the radar is the player's facing direction.
class_name Radar
extends Control

const RANGE := 55.0
const REFRESH := 0.1

var player: Node3D
var _timer := 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(150, 150)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		_timer = REFRESH
		queue_redraw()


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	draw_circle(c, r, Color(0.05, 0.07, 0.15, 0.6))
	draw_arc(c, r, 0, TAU, 40, Color(1, 1, 1, 0.35), 2.0, true)
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(1, 1, 1, 0.12), 1.0, true)
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var origin := player.global_position
	var yaw := player.global_rotation.y
	var to_map := func(p: Vector3) -> Vector2:
		var d := p - origin
		# Rotate so the player's forward (-Z) points up.
		var v := Vector2(d.x, d.z).rotated(-yaw)
		v = v / RANGE * r
		if v.length() > r - 5.0:
			v = v.normalized() * (r - 5.0)
		return c + v
	for crate in get_tree().get_nodes_in_group("weapon_crates"):
		if crate.has_method("is_available") and crate.call("is_available"):
			var p: Vector2 = to_map.call((crate as Node3D).global_position)
			var s := 4.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]),
				Color(1, 1, 1, 0.75))
	var my_team: Variant = player.get("team")
	for k in get_tree().get_nodes_in_group("karts"):
		if k == player or k.get("alive") == false:
			continue
		var p: Vector2 = to_map.call((k as Node3D).global_position)
		var team: Variant = k.get("team")
		var col := Color(1.0, 0.3, 0.3)
		if team != null and int(team) >= 0:
			col = Teams.team_color(int(team))
		draw_circle(p, 5.0, Color(0.05, 0.07, 0.15, 0.9))
		draw_circle(p, 3.8, col)
		if my_team != null and int(my_team) >= 0 and team == my_team:
			draw_arc(p, 6.5, 0, TAU, 12, Color(1, 1, 1, 0.8), 1.5)
	# The player: an arrow pointing up.
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -8), c + Vector2(6, 6), c + Vector2(0, 3), c + Vector2(-6, 6)]),
		ThemeBuilder.ORANGE_LIGHT)
