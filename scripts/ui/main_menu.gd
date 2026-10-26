## Main menu: animated background, KART CLASH title, Play / Settings / How to play / Quit.
extends Control

const GAME_SCENE := "res://scenes/game.tscn"
const PLAY_SCENE := "res://scenes/lobby.tscn"

const BG_SHADER := """
shader_type canvas_item;
uniform vec4 navy : source_color = vec4(0.078, 0.106, 0.2, 1.0);
uniform vec4 navy_dark : source_color = vec4(0.043, 0.063, 0.133, 1.0);
uniform vec4 orange : source_color = vec4(1.0, 0.478, 0.102, 1.0);
uniform vec4 teal : source_color = vec4(0.098, 0.765, 0.694, 1.0);
void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.06;
	// Diagonal racing stripes drifting across a vertical navy gradient.
	float d = uv.x * 1.6 + uv.y * 0.9 - t;
	float stripe = smoothstep(0.46, 0.5, fract(d * 3.0)) * (1.0 - smoothstep(0.54, 0.58, fract(d * 3.0)));
	vec3 base = mix(navy.rgb, navy_dark.rgb, uv.y);
	vec3 accent = mix(orange.rgb, teal.rgb, 0.5 + 0.5 * sin(d * 6.2831 + TIME * 0.4));
	vec3 col = mix(base, accent, stripe * 0.16);
	// Soft glow behind the title.
	float glow = 1.0 - smoothstep(0.0, 0.55, distance(uv, vec2(0.5, 0.28)));
	col += orange.rgb * glow * 0.12;
	COLOR = vec4(col, 1.0);
}
"""

var _title: Label
var _buttons: VBoxContainer
var _play_button: Button
var _quit_button: Button
var _settings: SettingsPanel
var _how_to: Control


func _ready() -> void:
	get_tree().paused = false
	GameState.reset()
	Net.leave()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeBuilder.get_theme()
	_build_background()
	_build_menu()
	_settings = SettingsPanel.new()
	_settings.closed.connect(func() -> void: _play_button.grab_focus())
	add_child(_settings)
	_how_to = _build_how_to()
	add_child(_how_to)
	_play_button.grab_focus()
	_animate_title()


func _build_background() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.color = ThemeBuilder.NAVY
	var shader := Shader.new()
	shader.code = BG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	bg.material = mat
	add_child(bg)


func _build_menu() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_title = ThemeBuilder.make_title_label("KART CLASH", 104)
	col.add_child(_title)
	var tagline := Label.new()
	tagline.text = "Grab crates. Blast rivals. Rule the arena."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_color_override("font_color", ThemeBuilder.TEAL_LIGHT)
	col.add_child(tagline)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	col.add_child(spacer)

	_buttons = VBoxContainer.new()
	_buttons.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_buttons.add_theme_constant_override("separation", 14)
	col.add_child(_buttons)

	_play_button = ThemeBuilder.make_button("PLAY", false, Vector2(340, 88))
	_play_button.add_theme_font_size_override("font_size", 40)
	_play_button.pressed.connect(_on_play)
	_buttons.add_child(_play_button)
	var settings_btn := ThemeBuilder.make_button("Settings", true)
	settings_btn.pressed.connect(func() -> void: _settings.open())
	_buttons.add_child(settings_btn)
	var how_btn := ThemeBuilder.make_button("How to play", true)
	how_btn.pressed.connect(func() -> void: _how_to.visible = true)
	_buttons.add_child(how_btn)
	_quit_button = ThemeBuilder.make_button("Quit", true)
	_quit_button.pressed.connect(func() -> void: get_tree().quit())
	_quit_button.visible = not (OS.has_feature("web") or OS.has_feature("mobile"))
	_buttons.add_child(_quit_button)

	var version := Label.new()
	version.text = "Offline arena battles - v0.1"
	version.add_theme_font_size_override("font_size", 16)
	version.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(version)


func _build_how_to() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(ThemeBuilder.make_header("HOW TO PLAY"))

	var goal := Label.new()
	goal.text = "Drive into glowing crates to get a weapon, then wreck rivals.\nMost kills when the 3:00 timer runs out wins!"
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.add_theme_font_size_override("font_size", 22)
	box.add_child(goal)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	box.add_child(cols)
	cols.add_child(_controls_column("Keyboard", [
		["W / Up", "Accelerate"],
		["S / Down", "Brake / reverse"],
		["A D / Left Right", "Steer"],
		["Shift", "Drift"],
		["Space", "Fire"],
		["Esc / P", "Pause"],
	]))
	cols.add_child(_controls_column("Touch", [
		["Left stick", "Steer"],
		["GAS", "Accelerate"],
		["BRAKE", "Brake / reverse"],
		["DRIFT", "Drift"],
		["FIRE", "Fire"],
		["II", "Pause"],
	]))

	var back := ThemeBuilder.make_button("Got it!", false, Vector2(240, 70))
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.pressed.connect(_close_how_to)
	box.add_child(back)
	return overlay


func _close_how_to() -> void:
	_how_to.visible = false
	_play_button.grab_focus()


func _controls_column(title: String, rows: Array) -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", ThemeBuilder.ORANGE)
	t.add_theme_font_size_override("font_size", 28)
	v.add_child(t)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	v.add_child(grid)
	for r in rows:
		var k := Label.new()
		k.text = str(r[0])
		k.add_theme_color_override("font_color", ThemeBuilder.TEAL_LIGHT)
		k.add_theme_font_size_override("font_size", 20)
		grid.add_child(k)
		var a := Label.new()
		a.text = str(r[1])
		a.add_theme_font_size_override("font_size", 20)
		grid.add_child(a)
	return v


func _animate_title() -> void:
	_title.pivot_offset = _title.size * 0.5
	var tw := create_tween().set_loops()
	tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(_title, "scale", Vector2(1.04, 1.04), 1.2)
	tw.tween_property(_title, "scale", Vector2.ONE, 1.2)
	_title.resized.connect(func() -> void: _title.pivot_offset = _title.size * 0.5)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _how_to.visible:
		_close_how_to()
		get_viewport().set_input_as_handled()


func _on_play() -> void:
	# Deferred so the pressed button finishes its input handling before the menu is freed.
	get_tree().change_scene_to_file.call_deferred(PLAY_SCENE)
