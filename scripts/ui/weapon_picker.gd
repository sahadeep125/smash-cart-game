## Row of tiles for choosing a loadout (the weapon you start each life with).
## Used on the Play screen, in the multiplayer room and on the respawn screen.
class_name WeaponPicker
extends HFlowContainer

signal picked(weapon: String)

var selected: String = "":
	set(value):
		selected = Loadout.sanitize(value)
		_refresh()

var _tiles := {}
var _tile_size := Vector2(128, 116)


func _init(tile_size := Vector2(128, 116)) -> void:
	_tile_size = tile_size
	add_theme_constant_override("h_separation", 10)
	add_theme_constant_override("v_separation", 10)
	alignment = FlowContainer.ALIGNMENT_CENTER
	for id in Loadout.choices():
		var tile := _make_tile(id)
		_tiles[id] = tile
		add_child(tile)
	_refresh()


func _make_tile(id: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = _tile_size
	b.pressed.connect(func() -> void:
		selected = id
		picked.emit(id))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	var icon := _LoadoutIcon.new()
	icon.weapon = id
	icon.custom_minimum_size = Vector2(_tile_size.y * 0.5, _tile_size.y * 0.5)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(icon)
	var l := Label.new()
	l.text = Loadout.label(id)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", int(clampf(_tile_size.y * 0.15, 13, 18)))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	return b


func _refresh() -> void:
	for id in _tiles:
		var b: Button = _tiles[id]
		b.set_pressed_no_signal(id == selected)
		var col := _accent(id)
		var on: bool = id == selected
		var box := ThemeBuilder.make_box(Color(col, 0.30) if on else ThemeBuilder.NAVY_LIGHT, 14,
			col if on else Color(1, 1, 1, 0.12), 4 if on else 2)
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
			b.add_theme_stylebox_override(state, box)


static func _accent(id: String) -> Color:
	if WeaponDB.has_weapon(id):
		return WeaponDB.get_color(id)
	return ThemeBuilder.TEAL if id == Loadout.RANDOM else Color(0.75, 0.78, 0.9)


## Icon for one choice: the weapon's icon, a "?" die for Random, a crate for none.
class _LoadoutIcon:
	extends Control

	var weapon := ""

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := minf(size.x, size.y) * 0.5
		var c := size * 0.5
		var ink := Color(0.05, 0.07, 0.15)
		draw_circle(c, r, WeaponPicker._accent(weapon))
		if WeaponDB.has_weapon(weapon):
			WeaponIcon.draw_icon(self, weapon, c, r * 0.72, ink)
		elif weapon == Loadout.RANDOM:
			var font := get_theme_default_font()
			var fs := int(r * 1.3)
			draw_string(font, c + Vector2(-r, fs * 0.36), "?", HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ink)
		else:
			# Weapon crate.
			var s := r * 0.55
			draw_rect(Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), ink, false, maxf(r * 0.12, 2.0))
			draw_line(c - Vector2(s, s), c + Vector2(s, s), ink, maxf(r * 0.1, 2.0))
			draw_line(c + Vector2(-s, s), c + Vector2(s, -s), ink, maxf(r * 0.1, 2.0))
