## In-match heads-up display.
## Built entirely in code; call bind_player(kart) once the player kart exists.
## Also owns the touch controls, pause menu and match-end screen (auto-created).
class_name HUD
extends CanvasLayer

signal pause_requested

const WEAPON_DB_PATH := "res://scripts/combat/weapon_db.gd"
const KILL_FEED_MAX := 4
const KILL_FEED_LIFETIME := 4.5
const LOW_TIME := 30.0
const WEAPON_HINTS := {
	"rocket": "Fire: homing rocket, big blast",
	"machine_gun": "Hold fire: rapid shots",
	"mine": "Fire: drop a mine behind you",
	"shield": "Fire: 5 s of invulnerability",
}

## Seconds shown in the "Respawning in N" overlay (matches RespawnManager default).
var respawn_delay := 3.0
## Seconds per countdown step ("3", "2", "1"); "GO!" stays a bit shorter.
var countdown_step := 0.8
## Create PauseMenu and MatchEndScreen children automatically.
var auto_create_menus := true

var player: Node = null
var pause_menu: PauseMenu = null
var match_end_screen: MatchEndScreen = null

var _root: Control
var _touch: TouchControls
var _health_bar: ProgressBar
var _health_label: Label
var _health_fill: StyleBoxFlat
var _weapon_swatch: WeaponIcon
var _weapon_card: WeaponCard
var _weapon_label: Label
var _timer_label: Label
var _kills_label: Label
var _leaderboard: VBoxContainer
var _team_bar: HBoxContainer
var _radar: Radar
var _damage_flash: ColorRect
var _popup: Label
var _wrecked_by: Label
var _kill_feed: VBoxContainer
var _respawn_overlay: Control
var _respawn_label: Label
var _respawn_weapons: WeaponPicker
var _countdown_label: Label
var _fps_label: Label
var _pause_button: Button

var _weapon_db: Script = null
var _weapon_db_methods: Dictionary = {}
var _respawn_left := 0.0
var _time_left := 0.0
var _pulse_t := 0.0
var _counting_down := false


func _init() -> void:
	layer = 5
	_load_weapon_db()
	_build()


func _ready() -> void:
	Events.kart_killed.connect(_on_kart_killed)
	Events.kart_respawned.connect(_on_kart_respawned)
	Events.match_started.connect(_on_match_started)
	Events.match_time_changed.connect(_on_time_changed)
	Events.score_changed.connect(_on_score_changed)
	Events.match_ended.connect(_on_match_ended)
	Settings.settings_changed.connect(_apply_settings)
	_apply_settings()
	_set_time(GameState.get_time_left() if GameState.is_running() else GameState.match_duration)
	_refresh_leaderboard()
	if auto_create_menus:
		pause_menu = PauseMenu.new()
		add_child(pause_menu)
		match_end_screen = MatchEndScreen.new()
		add_child(match_end_screen)


func _process(delta: float) -> void:
	if _fps_label.visible:
		_fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	if _respawn_overlay.visible:
		_respawn_left = maxf(_respawn_left - delta, 0.0)
		_respawn_label.text = "Respawning in %d…" % maxi(1, int(ceil(_respawn_left)))
	# Pulse the timer when time is nearly up.
	if GameState.is_running() and _time_left <= LOW_TIME:
		_pulse_t += delta
		var s := 1.0 + 0.12 * absf(sin(_pulse_t * PI * 2.0))
		_timer_label.pivot_offset = _timer_label.size * 0.5
		_timer_label.scale = Vector2(s, s)
	else:
		_timer_label.scale = Vector2.ONE


# --- Public API -----------------------------------------------------------------

func bind_player(kart: Node) -> void:
	_unbind_player()
	player = kart
	if kart == null:
		return
	if _radar:
		_radar.player = kart as Node3D
	var health: Node = kart.get_health() if kart.has_method("get_health") else kart.get_node_or_null("Health")
	if health:
		if health.has_signal("damaged"):
			health.damaged.connect(_on_player_damaged)
		if health.has_signal("health_changed"):
			health.health_changed.connect(_on_health_changed)
		var cur := float(health.get("current_health")) if "current_health" in health else 100.0
		var mx := float(health.get("max_health")) if "max_health" in health else 100.0
		_on_health_changed(cur, mx)
	var holder: Node = kart.get_weapon_holder() if kart.has_method("get_weapon_holder") else kart.get_node_or_null("WeaponHolder")
	if holder:
		if holder.has_signal("weapon_changed"):
			holder.weapon_changed.connect(_on_weapon_changed)
		var wid := str(holder.get("current_weapon_id")) if "current_weapon_id" in holder else ""
		var ammo := int(holder.get("ammo")) if "ammo" in holder else 0
		_on_weapon_changed(wid, ammo)
	else:
		_on_weapon_changed("", 0)
	_update_kills()
	_refresh_leaderboard()


## "3, 2, 1, GO!" overlay. Await it: `await hud.play_countdown()`.
## Pausing the tree pauses the countdown too.
func play_countdown() -> void:
	if not is_inside_tree():
		await tree_entered
	_counting_down = true
	_countdown_label.visible = true
	for step in ["3", "2", "1", "GO!"]:
		_countdown_label.text = step
		var is_go: bool = step == "GO!"
		_countdown_label.add_theme_color_override("font_color",
			ThemeBuilder.TEAL_LIGHT if is_go else ThemeBuilder.ORANGE)
		_countdown_label.pivot_offset = _countdown_label.size * 0.5
		_countdown_label.scale = Vector2(1.8, 1.8)
		_countdown_label.modulate.a = 1.0
		var tw := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(_countdown_label, "scale", Vector2.ONE, countdown_step * 0.5)
		if is_go:
			break
		await get_tree().create_timer(countdown_step, false).timeout
	_counting_down = false
	# "GO!" fades out without blocking the caller.
	var fade := create_tween()
	fade.tween_interval(countdown_step * 0.6)
	fade.tween_property(_countdown_label, "modulate:a", 0.0, 0.3)
	fade.tween_callback(func() -> void: _countdown_label.visible = false)


func get_touch_controls() -> TouchControls:
	return _touch


func is_respawn_overlay_visible() -> bool:
	return _respawn_overlay.visible


func get_timer_text() -> String:
	return _timer_label.text


func get_kill_feed_count() -> int:
	var n := 0
	for c in _kill_feed.get_children():
		if not c.is_queued_for_deletion():
			n += 1
	return n


# --- Building -------------------------------------------------------------------

func _build() -> void:
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ThemeBuilder.get_theme()
	add_child(_root)

	# Touch controls go first so every other widget draws on top.
	_touch = TouchControls.new()
	_touch.name = "TouchControls"
	_touch.visible = false
	_root.add_child(_touch)

	var safe := MarginContainer.new()
	safe.name = "Safe"
	safe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	safe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		safe.add_theme_constant_override("margin_" + side, 18)
	_root.add_child(safe)

	var layer_root := Control.new()
	layer_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	safe.add_child(layer_root)

	_build_top_left(layer_root)
	_build_top_center(layer_root)
	_build_top_right(layer_root)
	_build_center(layer_root)

	_weapon_card = WeaponCard.new()
	_weapon_card.name = "WeaponCard"
	_weapon_card.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_weapon_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_weapon_card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	layer_root.add_child(_weapon_card)


func _build_top_left(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	box.add_theme_constant_override("separation", 8)
	parent.add_child(box)

	var hp_stack := Control.new()
	hp_stack.custom_minimum_size = Vector2(300, 36)
	hp_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hp_stack)
	_health_bar = ProgressBar.new()
	_health_bar.show_percentage = false
	_health_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_health_bar.max_value = 100
	_health_bar.value = 100
	_health_fill = ThemeBuilder.make_box(ThemeBuilder.TEAL, 10)
	_health_bar.add_theme_stylebox_override("fill", _health_fill)
	hp_stack.add_child(_health_bar)
	_health_label = Label.new()
	_health_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_health_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_health_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_health_label.add_theme_font_size_override("font_size", 20)
	_health_label.text = "100 / 100"
	hp_stack.add_child(_health_label)

	var weapon_panel := PanelContainer.new()
	weapon_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var wp_style := ThemeBuilder.make_box(Color(ThemeBuilder.NAVY, 0.8), 14, Color(1, 1, 1, 0.25), 2)
	wp_style.content_margin_top = 6
	wp_style.content_margin_bottom = 6
	weapon_panel.add_theme_stylebox_override("panel", wp_style)
	box.add_child(weapon_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	weapon_panel.add_child(row)
	_weapon_swatch = WeaponIcon.new()
	_weapon_swatch.custom_minimum_size = Vector2(34, 34)
	_weapon_swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_weapon_swatch)
	_weapon_label = Label.new()
	_weapon_label.add_theme_font_size_override("font_size", 24)
	row.add_child(_weapon_label)
	_on_weapon_changed("", 0)

	_fps_label = Label.new()
	_fps_label.add_theme_font_size_override("font_size", 18)
	_fps_label.add_theme_color_override("font_color", ThemeBuilder.GOLD)
	_fps_label.visible = false
	box.add_child(_fps_label)

	_radar = Radar.new()
	_radar.name = "Radar"
	box.add_child(_radar)


func _build_top_center(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(box)

	var timer_panel := PanelContainer.new()
	timer_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var tp := ThemeBuilder.make_box(Color(ThemeBuilder.NAVY, 0.85), 18, ThemeBuilder.ORANGE, 3)
	tp.content_margin_top = 2
	tp.content_margin_bottom = 2
	timer_panel.add_theme_stylebox_override("panel", tp)
	box.add_child(timer_panel)
	_timer_label = Label.new()
	_timer_label.add_theme_font_size_override("font_size", 44)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.custom_minimum_size = Vector2(150, 0)
	_timer_label.text = "3:00"
	timer_panel.add_child(_timer_label)

	# Team Deathmatch: one score chip per team, best first.
	_team_bar = HBoxContainer.new()
	_team_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_team_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_team_bar.add_theme_constant_override("separation", 8)
	box.add_child(_team_bar)

	_kill_feed = VBoxContainer.new()
	_kill_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kill_feed.add_theme_constant_override("separation", 4)
	_kill_feed.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_kill_feed)


func _build_top_right(parent: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	parent.add_child(box)

	var top_row := HBoxContainer.new()
	top_row.alignment = BoxContainer.ALIGNMENT_END
	top_row.add_theme_constant_override("separation", 12)
	box.add_child(top_row)
	_kills_label = Label.new()
	_kills_label.add_theme_font_size_override("font_size", 30)
	_kills_label.add_theme_color_override("font_color", ThemeBuilder.GOLD)
	_kills_label.text = "KILLS 0"
	_kills_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top_row.add_child(_kills_label)
	_pause_button = ThemeBuilder.make_button("II", true, Vector2(72, 72))
	_pause_button.focus_mode = Control.FOCUS_NONE
	_pause_button.tooltip_text = "Pause"
	_pause_button.pressed.connect(_on_pause_pressed)
	top_row.add_child(_pause_button)

	var lb_panel := PanelContainer.new()
	lb_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lp := ThemeBuilder.make_box(Color(ThemeBuilder.NAVY, 0.7), 12)
	lp.content_margin_top = 6
	lp.content_margin_bottom = 6
	lb_panel.add_theme_stylebox_override("panel", lp)
	box.add_child(lb_panel)
	_leaderboard = VBoxContainer.new()
	_leaderboard.add_theme_constant_override("separation", 0)
	_leaderboard.custom_minimum_size = Vector2(230, 0)
	lb_panel.add_child(_leaderboard)


func _build_center(parent: Control) -> void:
	_respawn_overlay = CenterContainer.new()
	_respawn_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_respawn_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_respawn_overlay.visible = false
	parent.add_child(_respawn_overlay)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", ThemeBuilder.make_box(Color(ThemeBuilder.RED, 0.35), 20, ThemeBuilder.RED, 3))
	_respawn_overlay.add_child(panel)
	var v := VBoxContainer.new()
	panel.add_child(v)
	var wrecked := Label.new()
	wrecked.text = "WRECKED!"
	wrecked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wrecked.add_theme_font_size_override("font_size", 56)
	wrecked.add_theme_constant_override("outline_size", 10)
	v.add_child(wrecked)
	_wrecked_by = Label.new()
	_wrecked_by.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wrecked_by.add_theme_font_size_override("font_size", 26)
	v.add_child(_wrecked_by)
	_respawn_label = Label.new()
	_respawn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_label.add_theme_font_size_override("font_size", 32)
	v.add_child(_respawn_label)
	var next := Label.new()
	next.text = "Next life, start with:"
	next.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	next.add_theme_font_size_override("font_size", 20)
	next.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	v.add_child(next)
	_respawn_weapons = WeaponPicker.new(Vector2(96, 86))
	_respawn_weapons.mouse_filter = Control.MOUSE_FILTER_PASS
	_respawn_weapons.custom_minimum_size = Vector2(560, 0)
	_respawn_weapons.picked.connect(_on_respawn_weapon_picked)
	v.add_child(_respawn_weapons)

	# Red edge flash when the player is hit.
	_damage_flash = ColorRect.new()
	_damage_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash_shader := Shader.new()
	flash_shader.code = """
shader_type canvas_item;
uniform float strength = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	COLOR = vec4(1.0, 0.1, 0.1, smoothstep(0.35, 0.75, d) * strength);
}
"""
	var flash_mat := ShaderMaterial.new()
	flash_mat.shader = flash_shader
	_damage_flash.material = flash_mat
	_damage_flash.visible = false
	parent.add_child(_damage_flash)

	# "+1 WRECKED Bolt" style popups for the player's own kills.
	_popup = ThemeBuilder.make_title_label("", 48)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.position.y -= 140
	_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_popup.modulate.a = 0.0
	parent.add_child(_popup)

	_countdown_label = ThemeBuilder.make_title_label("3", 150)
	_countdown_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.visible = false
	parent.add_child(_countdown_label)


# --- Event handlers -------------------------------------------------------------

func _unbind_player() -> void:
	if player == null or not is_instance_valid(player):
		player = null
		return
	var health: Node = player.get_node_or_null("Health")
	if player.has_method("get_health"):
		health = player.get_health()
	if health and health.has_signal("health_changed") and health.health_changed.is_connected(_on_health_changed):
		health.health_changed.disconnect(_on_health_changed)
	if health and health.has_signal("damaged") and health.damaged.is_connected(_on_player_damaged):
		health.damaged.disconnect(_on_player_damaged)
	var holder: Node = player.get_node_or_null("WeaponHolder")
	if player.has_method("get_weapon_holder"):
		holder = player.get_weapon_holder()
	if holder and holder.has_signal("weapon_changed") and holder.weapon_changed.is_connected(_on_weapon_changed):
		holder.weapon_changed.disconnect(_on_weapon_changed)
	player = null


func _on_health_changed(current: float, max_value: float) -> void:
	var mx := maxf(max_value, 1.0)
	_health_bar.max_value = mx
	_health_bar.value = clampf(current, 0.0, mx)
	_health_label.text = "%d / %d" % [int(ceil(maxf(current, 0.0))), int(mx)]
	var frac := clampf(current / mx, 0.0, 1.0)
	_health_fill.bg_color = ThemeBuilder.RED.lerp(ThemeBuilder.TEAL, smoothstep(0.15, 0.7, frac))


func _on_weapon_changed(weapon_id: String, ammo: int) -> void:
	var col := weapon_color(weapon_id) if weapon_id != "" else ThemeBuilder.TEXT_DIM
	_weapon_swatch.weapon_id = weapon_id
	_weapon_swatch.color = col
	if _weapon_card:
		_weapon_card.show_weapon(weapon_id, ammo, weapon_display_name(weapon_id) if weapon_id != "" else "",
			col, str(WEAPON_HINTS.get(weapon_id, "")))
	if _touch:
		_touch.set_weapon(weapon_id, col)
	if weapon_id == "":
		_weapon_label.text = "No weapon - grab a crate!"
		_weapon_label.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
		return
	_weapon_label.text = "%s  x%d" % [weapon_display_name(weapon_id).to_upper(), ammo]
	_weapon_label.add_theme_color_override("font_color", ThemeBuilder.TEXT)


func _on_match_started() -> void:
	_respawn_overlay.visible = false
	for c in _kill_feed.get_children():
		c.queue_free()
	_set_time(GameState.get_time_left())
	_apply_settings()
	_update_kills()
	_refresh_leaderboard()


func _on_time_changed(seconds_left: float) -> void:
	_set_time(seconds_left)


func _set_time(seconds_left: float) -> void:
	_time_left = seconds_left
	var total := int(ceil(maxf(seconds_left, 0.0)))
	_timer_label.text = "%d:%02d" % [floori(total / 60.0), total % 60]
	_timer_label.add_theme_color_override("font_color",
		ThemeBuilder.RED if seconds_left <= LOW_TIME else ThemeBuilder.TEXT)


func _on_score_changed(_kart_name: String, _kills: int, _deaths: int) -> void:
	_update_kills()
	_refresh_leaderboard()


func _on_kart_killed(victim: Node, killer: Node, weapon_id: String) -> void:
	_add_kill_feed_entry(victim, killer, weapon_id)
	if victim != null and victim == player and GameState.is_running():
		_respawn_left = respawn_delay
		_respawn_overlay.visible = true
		var by := _kart_name(killer) if killer != null and is_instance_valid(killer) and killer != victim else ""
		_wrecked_by.text = ("by %s" % by) if by != "" else ""
		_wrecked_by.visible = by != ""
		var lo: Variant = player.get("loadout")
		_respawn_weapons.selected = str(lo) if lo != null else ""
	elif killer != null and killer == player and victim != player:
		_show_popup("WRECKED %s!" % _kart_name(victim).to_upper(), ThemeBuilder.GOLD)


func _on_respawn_weapon_picked(weapon: String) -> void:
	Settings.weapon_pick = weapon
	Settings.save()
	var game := get_parent()
	if player is Kart and game != null and game.has_method("request_loadout"):
		game.call("request_loadout", player, weapon)
	elif player != null:
		player.set("loadout", weapon)


func _on_player_damaged(amount: float, _source: Node) -> void:
	if amount <= 0.0 or _damage_flash == null:
		return
	var mat := _damage_flash.material as ShaderMaterial
	_damage_flash.visible = true
	var s := clampf(0.35 + amount / 60.0, 0.35, 0.9)
	mat.set_shader_parameter("strength", s)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("strength", v), s, 0.0, 0.45)
	tw.tween_callback(func() -> void: _damage_flash.visible = false)


func _show_popup(text: String, color: Color) -> void:
	_popup.text = text
	_popup.add_theme_color_override("font_color", color)
	_popup.pivot_offset = _popup.size * 0.5
	_popup.scale = Vector2(1.6, 1.6)
	_popup.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_property(_popup, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(_popup, "modulate:a", 0.0, 0.4)


func _on_kart_respawned(kart: Node) -> void:
	if kart == player:
		_respawn_overlay.visible = false


func _on_match_ended(_results: Array) -> void:
	_respawn_overlay.visible = false
	_touch.visible = false
	_pause_button.visible = false
	_refresh_leaderboard()


func _on_pause_pressed() -> void:
	pause_requested.emit()
	if pause_menu:
		pause_menu.open()


func _apply_settings() -> void:
	_fps_label.visible = Settings.show_fps
	var match_over := not GameState.is_running() and not GameState.get_results().is_empty()
	_touch.visible = Settings.should_show_touch_controls() and not match_over
	_pause_button.visible = not match_over


# --- Kill feed / leaderboard ----------------------------------------------------

func _add_kill_feed_entry(victim: Node, killer: Node, weapon_id: String) -> void:
	var victim_name := _kart_name(victim)
	var text := ""
	if killer == null or killer == victim or not is_instance_valid(killer):
		text = "%s wiped out" % victim_name
	else:
		var weapon := weapon_display_name(weapon_id) if weapon_id != "" else "bump"
		text = "%s  [%s]  %s" % [_kart_name(killer), weapon, victim_name]
	var involves_player := player != null and (victim == player or killer == player)

	var entry := PanelContainer.new()
	entry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ThemeBuilder.ORANGE if involves_player else ThemeBuilder.NAVY
	var sb := ThemeBuilder.make_box(Color(bg, 0.75), 10)
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	entry.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	entry.add_child(l)
	_kill_feed.add_child(entry)

	# Keep only the newest KILL_FEED_MAX entries.
	var alive: Array[Node] = []
	for c in _kill_feed.get_children():
		if not c.is_queued_for_deletion():
			alive.append(c)
	while alive.size() > KILL_FEED_MAX:
		var old: Node = alive.pop_front()
		_kill_feed.remove_child(old)
		old.queue_free()

	var tw := entry.create_tween()
	tw.tween_interval(KILL_FEED_LIFETIME)
	tw.tween_property(entry, "modulate:a", 0.0, 0.6)
	tw.tween_callback(entry.queue_free)


func _update_kills() -> void:
	if player == null or not is_instance_valid(player):
		return
	var score := GameState.get_score(_kart_name(player))
	_kills_label.text = "KILLS %d" % int(score["kills"])


func _refresh_team_bar() -> void:
	for c in _team_bar.get_children():
		_team_bar.remove_child(c)
		c.queue_free()
	_team_bar.visible = GameState.is_team_mode()
	if not _team_bar.visible:
		return
	var my_team := int(player.get("team")) if player != null and is_instance_valid(player) and "team" in player else -1
	for t: Dictionary in GameState.get_team_standings():
		var chip := PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mine := int(t["team"]) == my_team
		var sb := ThemeBuilder.make_box(Color(t["color"], 0.85 if mine else 0.55), 12,
			Color.WHITE if mine else Color(0, 0, 0, 0), 3 if mine else 0)
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		chip.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = "%s  %d" % [str(t["name"]).to_upper(), int(t["kills"])]
		l.add_theme_font_size_override("font_size", 24)
		l.add_theme_constant_override("outline_size", 6)
		l.add_theme_color_override("font_outline_color", Color(0.04, 0.06, 0.13, 0.9))
		chip.add_child(l)
		_team_bar.add_child(chip)


func _refresh_leaderboard() -> void:
	_refresh_team_bar()
	for c in _leaderboard.get_children():
		_leaderboard.remove_child(c)
		c.queue_free()
	var results := GameState.get_results()
	var player_name := _kart_name(player) if player != null and is_instance_valid(player) else ""
	var player_shown := false
	for i in mini(3, results.size()):
		var r: Dictionary = results[i]
		var is_me := str(r["name"]) == player_name or bool(r.get("is_player", false))
		player_shown = player_shown or is_me
		_leaderboard.add_child(_leaderboard_row(i + 1, r, is_me))
	if not player_shown:
		for i in range(3, results.size()):
			var r: Dictionary = results[i]
			if str(r["name"]) == player_name or bool(r.get("is_player", false)):
				_leaderboard.add_child(_leaderboard_row(i + 1, r, true))
				break


func _leaderboard_row(rank: int, r: Dictionary, is_me: bool) -> Control:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col := ThemeBuilder.ORANGE_LIGHT if is_me else ThemeBuilder.TEXT
	var team := int(r.get("team", -1))
	if team >= 0:
		col = Teams.team_color(team).lightened(0.35 if is_me else 0.1)
	var rank_l := Label.new()
	rank_l.text = "%d." % rank
	rank_l.custom_minimum_size = Vector2(34, 0)
	var name_l := Label.new()
	name_l.text = ("> " if is_me else "") + str(r["name"])
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	var kills_l := Label.new()
	kills_l.text = str(r["kills"])
	kills_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for l: Label in [rank_l, name_l, kills_l]:
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", col)
		row.add_child(l)
	return row


# --- Weapon DB (loaded dynamically to avoid a hard parse dependency) ------------

func _load_weapon_db() -> void:
	if not ResourceLoader.exists(WEAPON_DB_PATH):
		return
	var s = load(WEAPON_DB_PATH)
	if s is Script:
		_weapon_db = s
		for m in _weapon_db.get_script_method_list():
			_weapon_db_methods[str(m["name"])] = true


func weapon_display_name(weapon_id: String) -> String:
	if _weapon_db and _weapon_db_methods.has("get_display_name"):
		var n = _weapon_db.call("get_display_name", weapon_id)
		if n is String and n != "":
			return n
	return weapon_id.capitalize()


func weapon_color(weapon_id: String) -> Color:
	if _weapon_db and _weapon_db_methods.has("get_color"):
		var c = _weapon_db.call("get_color", weapon_id)
		if c is Color:
			return c
	return ThemeBuilder.ORANGE


static func _kart_name(kart: Object) -> String:
	if kart == null or not is_instance_valid(kart):
		return "?"
	if "kart_name" in kart and str(kart.kart_name) != "":
		return str(kart.kart_name)
	if kart is Node:
		return str((kart as Node).name)
	return "?"
