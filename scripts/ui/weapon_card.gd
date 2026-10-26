## Big bottom-centre card showing the held weapon: icon, name and ammo pips.
## Pops when a weapon is picked up and flashes on each shot.
class_name WeaponCard
extends PanelContainer

var _icon: WeaponIcon
var _name: Label
var _pips: HBoxContainer
var _hint: Label
var _style: StyleBoxFlat
var _pop := 1.0
var _weapon_id := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style = ThemeBuilder.make_box(Color(ThemeBuilder.NAVY, 0.82), 18, Color(1, 1, 1, 0.3), 3)
	_style.content_margin_left = 14
	_style.content_margin_right = 18
	_style.content_margin_top = 8
	_style.content_margin_bottom = 8
	add_theme_stylebox_override("panel", _style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = WeaponIcon.new()
	_icon.custom_minimum_size = Vector2(58, 58)
	row.add_child(_icon)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(col)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 26)
	col.add_child(_name)
	_pips = HBoxContainer.new()
	_pips.add_theme_constant_override("separation", 4)
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_pips)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	col.add_child(_hint)


func show_weapon(id: String, ammo: int, display_name: String, color: Color, hint: String) -> void:
	var picked := id != "" and id != _weapon_id
	_weapon_id = id
	_icon.weapon_id = id
	_icon.color = color
	_style.border_color = Color(color, 0.9) if id != "" else Color(1, 1, 1, 0.3)
	for c in _pips.get_children():
		c.queue_free()
	if id == "":
		_name.text = "NO WEAPON"
		_name.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
		_hint.text = "Drive through a crate"
		_hint.visible = true
		modulate.a = 0.75
		return
	modulate.a = 1.0
	_name.text = display_name.to_upper()
	_name.add_theme_color_override("font_color", color.lightened(0.25))
	_hint.text = hint
	_hint.visible = hint != ""
	var shown := mini(ammo, 30)
	var big := ammo <= 6
	for i in shown:
		var pip := ColorRect.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.color = color
		pip.custom_minimum_size = Vector2(14, 14) if big else Vector2(4, 12)
		_pips.add_child(pip)
	if picked:
		_pop = 0.0


func _process(delta: float) -> void:
	if _pop < 1.0:
		_pop = minf(_pop + delta * 3.5, 1.0)
		var s := 1.0 + sin(_pop * PI) * 0.25
		pivot_offset = size * 0.5
		scale = Vector2(s, s)
	else:
		scale = Vector2.ONE
