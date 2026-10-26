## Map choice: a card per map with a top-down preview drawn from the map's own
## layout, plus a "Random" card. Used on the Play screen and in the multiplayer room.
class_name MapPicker
extends HFlowContainer

signal picked(map_id: String)

var selected: String = Maps.DEFAULT:
	set(value):
		selected = value if value == Maps.RANDOM or Maps.has_map(value) else Maps.DEFAULT
		_refresh()
## When false the cards only show the choice (clients in a multiplayer room).
var editable := true:
	set(value):
		editable = value
		for id in _cards:
			(_cards[id] as Button).disabled = not value

var _cards := {}
var _card_size := Vector2(190, 200)


func _init(card_size := Vector2(190, 200)) -> void:
	_card_size = card_size
	add_theme_constant_override("h_separation", 12)
	add_theme_constant_override("v_separation", 12)
	alignment = FlowContainer.ALIGNMENT_CENTER
	var ids: Array[String] = Maps.ids()
	ids.append(Maps.RANDOM)
	for id in ids:
		var card := _make_card(id)
		_cards[id] = card
		add_child(card)
	_refresh()


func _make_card(id: String) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = _card_size
	b.tooltip_text = str(Maps.info(id)["blurb"]) if id != Maps.RANDOM else "A different map every match."
	b.pressed.connect(func() -> void:
		selected = id
		picked.emit(id))
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 8
	v.offset_bottom = -6
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 4)
	b.add_child(v)
	var preview := MapPreview.new()
	preview.map_id = id
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(preview)
	var l := Label.new()
	l.text = Maps.display_name(id)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 17)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	return b


func _refresh() -> void:
	for id in _cards:
		var b: Button = _cards[id]
		var on: bool = id == selected
		b.set_pressed_no_signal(on)
		var col: Color = Maps.info(id)["accent"] if id != Maps.RANDOM else ThemeBuilder.TEAL
		var box := ThemeBuilder.make_box(Color(col, 0.22) if on else ThemeBuilder.NAVY_LIGHT, 14,
			col if on else Color(1, 1, 1, 0.12), 4 if on else 2)
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			b.add_theme_stylebox_override(state, box)
