## Reusable settings screen. Edits the Settings autoload live and saves on close.
## Usage: var p := SettingsPanel.new(); add_child(p); p.open(); p.closed.connect(...)
class_name SettingsPanel
extends Control

signal closed

const TOUCH_LABELS := ["Auto", "On", "Off"]
const DIFFICULTY_NAMES := ["Easy", "Normal", "Hard"]

var _master: HSlider
var _sfx: HSlider
var _music: HSlider
var _touch: OptionButton
var _ai_count: SpinBox
var _difficulty: OptionButton
var _shake: CheckButton
var _fps: CheckButton
var _close_button: Button
var _syncing := false


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = ThemeBuilder.get_theme()
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 0)
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(580, 560)
	panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	scroll.add_child(box)

	box.add_child(ThemeBuilder.make_header("SETTINGS"))

	_master = _add_slider(box, "Master volume")
	_sfx = _add_slider(box, "Sound effects")
	_music = _add_slider(box, "Music")

	_touch = OptionButton.new()
	for l in TOUCH_LABELS:
		_touch.add_item(l)
	_add_row(box, "Touch controls", _touch)
	_touch.item_selected.connect(func(_i: int) -> void: _write_back())

	_ai_count = SpinBox.new()
	_ai_count.min_value = 1
	_ai_count.max_value = 7
	_ai_count.step = 1
	_ai_count.rounded = true
	_ai_count.custom_minimum_size = Vector2(160, 56)
	_add_row(box, "AI opponents", _ai_count)
	_ai_count.value_changed.connect(func(_v: float) -> void: _write_back())

	_difficulty = OptionButton.new()
	for d in DIFFICULTY_NAMES:
		_difficulty.add_item(d)
	_add_row(box, "AI difficulty", _difficulty)
	_difficulty.item_selected.connect(func(_i: int) -> void: _write_back())

	_shake = CheckButton.new()
	_add_row(box, "Camera shake", _shake)
	_shake.toggled.connect(func(_b: bool) -> void: _write_back())

	_fps = CheckButton.new()
	_add_row(box, "Show FPS", _fps)
	_fps.toggled.connect(func(_b: bool) -> void: _write_back())

	_close_button = ThemeBuilder.make_button("Done", true, Vector2(260, 70))
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.pressed.connect(close)
	box.add_child(_close_button)


func _add_slider(parent: Container, label_text: String) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.custom_minimum_size = Vector2(260, 40)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(_v: float) -> void: _write_back())
	_add_row(parent, label_text, s)
	return s


func _add_row(parent: Container, label_text: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(240, 0)
	l.add_theme_font_size_override("font_size", ThemeBuilder.FONT_SIZE_SMALL + 2)
	row.add_child(l)
	if control.size_flags_horizontal != Control.SIZE_EXPAND_FILL:
		control.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	row.add_child(control)
	parent.add_child(row)


# --- Public -------------------------------------------------------------------

func open() -> void:
	_read_from_settings()
	visible = true
	_close_button.grab_focus.call_deferred()


func close() -> void:
	if not visible:
		return
	_write_back()
	Settings.save()
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# --- Sync ---------------------------------------------------------------------

func _read_from_settings() -> void:
	_syncing = true
	_master.value = Settings.master_volume
	_sfx.value = Settings.sfx_volume
	_music.value = Settings.music_volume
	_touch.select(maxi(0, Settings.TOUCH_MODES.find(Settings.touch_controls)))
	_ai_count.value = Settings.ai_count
	_difficulty.select(maxi(0, DIFFICULTY_NAMES.find(Settings.get_difficulty_name())))
	_shake.button_pressed = Settings.camera_shake
	_fps.button_pressed = Settings.show_fps
	_syncing = false


func _write_back() -> void:
	if _syncing:
		return
	Settings.master_volume = _master.value
	Settings.sfx_volume = _sfx.value
	Settings.music_volume = _music.value
	Settings.touch_controls = Settings.TOUCH_MODES[clampi(_touch.selected, 0, 2)]
	Settings.ai_count = int(_ai_count.value)
	var diff_name: String = DIFFICULTY_NAMES[clampi(_difficulty.selected, 0, 2)]
	Settings.ai_difficulty = float(Settings.DIFFICULTY_PRESETS[diff_name])
	Settings.camera_shake = _shake.button_pressed
	Settings.show_fps = _fps.button_pressed
	Settings.apply()
