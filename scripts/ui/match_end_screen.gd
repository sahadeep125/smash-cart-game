## Results screen shown on Events.match_ended: winner banner, ranked table,
## Play again / Main menu.
class_name MatchEndScreen
extends CanvasLayer

signal play_again_pressed
signal main_menu_pressed

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

## Seconds between match end and the screen appearing (lets the last explosion play).
var show_delay := 1.0

var _root: Control
var _banner: Label
var _subtitle: Label
var _table: VBoxContainer
var _play_again: Button
var _results: Array = []


func _init() -> void:
	layer = 15
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _ready() -> void:
	Events.match_ended.connect(_on_match_ended)
	Events.match_started.connect(hide_screen)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = ThemeBuilder.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(ThemeBuilder.NAVY_DARK, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)

	_banner = ThemeBuilder.make_title_label("YOU WIN!", 64)
	box.add_child(_banner)
	_subtitle = Label.new()
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	box.add_child(_subtitle)

	var header := _make_row(["#", "Name", "Kills", "Deaths"], false, true)
	box.add_child(header)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 300)
	box.add_child(scroll)
	_table = VBoxContainer.new()
	_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table.add_theme_constant_override("separation", 4)
	scroll.add_child(_table)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	box.add_child(buttons)
	_play_again = ThemeBuilder.make_button("Play again", false, Vector2(260, 76))
	_play_again.pressed.connect(_on_play_again)
	buttons.add_child(_play_again)
	var menu := ThemeBuilder.make_button("Main menu", true, Vector2(260, 76))
	menu.pressed.connect(_on_main_menu)
	buttons.add_child(menu)


func _make_row(cells: Array, highlight: bool, is_header := false) -> Control:
	var panel := PanelContainer.new()
	var bg := ThemeBuilder.ORANGE if highlight else ThemeBuilder.NAVY_LIGHT
	if is_header:
		bg = Color(0, 0, 0, 0)
	var sb := ThemeBuilder.make_box(Color(bg, 0.85 if highlight else 0.6), 10)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	panel.add_child(row)
	var widths := [60, 0, 110, 110]
	for i in cells.size():
		var l := Label.new()
		l.text = str(cells[i])
		if widths[i] > 0:
			l.custom_minimum_size = Vector2(widths[i], 0)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			l.clip_text = true
		if is_header:
			l.add_theme_color_override("font_color", ThemeBuilder.TEAL_LIGHT)
			l.add_theme_font_size_override("font_size", 20)
		row.add_child(l)
	return panel


# --- Public ---------------------------------------------------------------------

func is_shown() -> bool:
	return _root.visible


func get_results() -> Array:
	return _results


func get_banner_text() -> String:
	return _banner.text


## Fills and shows the screen immediately.
func show_results(results: Array) -> void:
	_results = results.duplicate(true)
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	var player_rank := 0
	for i in _results.size():
		var r: Dictionary = _results[i]
		var me := bool(r.get("is_player", false))
		if me:
			player_rank = i + 1
		_table.add_child(_make_row([i + 1, r.get("name", "?"), r.get("kills", 0), r.get("deaths", 0)], me))

	if _results.is_empty():
		_banner.text = "MATCH OVER"
		_subtitle.text = ""
	elif player_rank == 1:
		_banner.text = "YOU WIN!"
		_banner.add_theme_color_override("font_color", ThemeBuilder.GOLD)
		_subtitle.text = "Top of the arena with %d kills" % int(_results[0].get("kills", 0))
	else:
		_banner.text = "%s WINS!" % str(_results[0].get("name", "?")).to_upper()
		_banner.add_theme_color_override("font_color", ThemeBuilder.ORANGE)
		_subtitle.text = "You placed #%d" % player_rank if player_rank > 0 else ""
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)
	_play_again.grab_focus()


func hide_screen() -> void:
	_root.visible = false


func _on_match_ended(results: Array) -> void:
	if show_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(show_delay, true).timeout
	show_results(results)


func _on_play_again() -> void:
	play_again_pressed.emit()
	_leave_to(GAME_SCENE)


func _on_main_menu() -> void:
	main_menu_pressed.emit()
	_leave_to(MAIN_MENU_SCENE)


func _leave_to(path: String) -> void:
	var tree := get_tree()
	tree.paused = false
	GameState.reset()
	if path == GAME_SCENE and tree.current_scene and tree.current_scene.scene_file_path == GAME_SCENE:
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file(path)
