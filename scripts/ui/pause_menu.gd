## Pause overlay: Resume / Restart / Settings / Main menu.
## Pauses the scene tree while open; the "pause" action toggles it.
class_name PauseMenu
extends CanvasLayer

signal resumed
signal opened

const GAME_SCENE := "res://scenes/game.tscn"
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _root: Control
var _resume_button: Button
var _settings: SettingsPanel


func _init() -> void:
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = ThemeBuilder.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(ThemeBuilder.NAVY_DARK, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	panel.add_child(box)
	box.add_child(ThemeBuilder.make_header("PAUSED"))

	_resume_button = ThemeBuilder.make_button("Resume")
	_resume_button.pressed.connect(close)
	box.add_child(_resume_button)
	var restart := ThemeBuilder.make_button("Restart", true)
	restart.pressed.connect(_on_restart)
	# A networked match can't be restarted by one player.
	restart.visible = not Net.is_active()
	box.add_child(restart)
	var settings_btn := ThemeBuilder.make_button("Settings", true)
	settings_btn.pressed.connect(_on_settings)
	box.add_child(settings_btn)
	var menu := ThemeBuilder.make_button("Main menu", true)
	menu.pressed.connect(_on_main_menu)
	box.add_child(menu)

	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _resume_button.grab_focus())
	_root.add_child(_settings)


func is_open() -> bool:
	return _root.visible


func open() -> void:
	if _root.visible or not _can_pause():
		return
	_root.visible = true
	# Networked matches keep running for everyone else.
	if not Net.is_active():
		get_tree().paused = true
	_resume_button.grab_focus()
	opened.emit()


func close() -> void:
	if not _root.visible:
		return
	if _settings.visible:
		_settings.close()
	_root.visible = false
	get_tree().paused = false
	resumed.emit()


func toggle() -> void:
	if _root.visible:
		close()
	else:
		open()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _settings.visible:
			_settings.close()
		else:
			toggle()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Auto-pause when the app goes to the background (mobile / browser tab).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		open()
	elif what == NOTIFICATION_EXIT_TREE and _root.visible:
		get_tree().paused = false


func _can_pause() -> bool:
	return is_inside_tree() and GameState.is_running()


func _on_settings() -> void:
	_settings.open()


func _on_restart() -> void:
	_leave_to(GAME_SCENE)


func _on_main_menu() -> void:
	Net.leave()
	_leave_to(MAIN_MENU_SCENE)


func _leave_to(path: String) -> void:
	var tree := get_tree()
	tree.paused = false
	GameState.reset()
	if path == GAME_SCENE and tree.current_scene and tree.current_scene.scene_file_path == GAME_SCENE:
		tree.reload_current_scene()
	else:
		tree.change_scene_to_file(path)
