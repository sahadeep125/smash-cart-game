## Play screen: solo setup, LAN and online hosting/joining, and the multiplayer room.
## Built in code like the rest of the UI. Shows the room automatically while a
## network session is active, otherwise the Solo / LAN / Online tabs.
extends Control

const MENU_SCENE := "res://scenes/main_menu.tscn"
const GAME_SCENE := "res://scenes/game.tscn"
const MODE_LABELS := ["Free-for-all", "Team Deathmatch"]
const MODES := ["ffa", "tdm"]

var _name_edit: LineEdit
var _status: Label
var _tabs: TabContainer
var _home: Control
var _room: Control
var _connecting := false

# Solo
var _solo_mode: OptionButton
var _solo_bots: SpinBox
var _solo_teams: SpinBox
var _solo_size: SpinBox
var _solo_diff: OptionButton
var _solo_ffa_rows: Array[Control] = []
var _solo_tdm_rows: Array[Control] = []

# LAN
var _lan_list: VBoxContainer
var _lan_ip: LineEdit

# Online
var _online_url: LineEdit
var _online_key: LineEdit
var _online_code: LineEdit

# Room
var _room_title: Label
var _room_info: Label
var _room_players: VBoxContainer
var _room_mode: OptionButton
var _room_bots: SpinBox
var _room_teams: SpinBox
var _room_size: SpinBox
var _room_diff: OptionButton
var _room_settings: Control
var _room_start: Button
var _room_wait: Label
var _room_ffa_rows: Array[Control] = []
var _room_tdm_rows: Array[Control] = []
var _updating := false


func _ready() -> void:
	get_tree().paused = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeBuilder.get_theme()
	var bg := ColorRect.new()
	bg.color = ThemeBuilder.NAVY_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build()
	Net.lobby_changed.connect(_refresh_room)
	Net.joined_lobby.connect(_on_joined)
	Net.session_ended.connect(_on_session_ended)
	Net.discovery.hosts_changed.connect(_on_hosts_changed)
	var reason := Net.take_end_reason()
	if reason != "":
		_set_status(reason, true)
	_show_current()


func _exit_tree() -> void:
	if not Net.is_active():
		Net.discovery.stop()


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(minf(860.0, get_viewport_rect().size.x - 32.0), 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	var back := ThemeBuilder.make_button("Back", true, Vector2(140, 60))
	back.pressed.connect(_on_back)
	top.add_child(back)
	var title := ThemeBuilder.make_title_label("PLAY", 56)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.visible = false
	col.add_child(_status)

	_home = VBoxContainer.new()
	_home.add_theme_constant_override("separation", 12)
	col.add_child(_home)
	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Your name"
	_name_edit.max_length = 14
	_name_edit.text = Settings.player_name
	_name_edit.custom_minimum_size = Vector2(0, 56)
	_name_edit.text_changed.connect(func(t: String) -> void:
		Settings.player_name = t.strip_edges()
		Settings.save())
	_row(_home, "Name", _name_edit)

	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 420)
	_tabs.add_theme_font_size_override("font_size", 30)
	_home.add_child(_tabs)
	_tabs.add_child(_build_solo())
	_tabs.add_child(_build_lan())
	_tabs.add_child(_build_online())

	_room = _build_room()
	col.add_child(_room)


func _build_solo() -> Control:
	var box := _page("Solo")
	_solo_mode = _option(MODE_LABELS)
	_solo_mode.selected = MODES.find(Settings.game_mode)
	_solo_mode.item_selected.connect(func(_i: int) -> void: _update_solo_rows())
	_row(box, "Mode", _solo_mode)
	_solo_bots = _spin(1, 15, Settings.ai_count)
	_solo_ffa_rows.append(_row(box, "Bots", _solo_bots))
	_solo_teams = _spin(2, 4, Settings.team_count)
	_solo_tdm_rows.append(_row(box, "Teams", _solo_teams))
	_solo_size = _spin(1, 4, Settings.team_size)
	_solo_tdm_rows.append(_row(box, "Karts per team", _solo_size))
	_solo_diff = _difficulty_option(Settings.ai_difficulty)
	_row(box, "Bot difficulty", _solo_diff)
	var start := ThemeBuilder.make_button("START", false, Vector2(320, 76))
	start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start.pressed.connect(_on_solo_start)
	box.add_child(start)
	_update_solo_rows()
	return box.get_parent().get_parent()


func _build_lan() -> Control:
	var box := _page("LAN")
	if not LanDiscovery.is_supported():
		var l := _note("LAN play needs the Android, iOS or desktop app: browsers can't open "
			+ "local network connections. Use Online instead.")
		box.add_child(l)
		return box.get_parent().get_parent()
	box.add_child(_note("Everyone must be on the same Wi-Fi or network."))
	var host := ThemeBuilder.make_button("Host a LAN game", false, Vector2(320, 70))
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.pressed.connect(_on_host_lan)
	box.add_child(host)
	box.add_child(ThemeBuilder.make_header("Games nearby"))
	_lan_list = VBoxContainer.new()
	_lan_list.add_theme_constant_override("separation", 8)
	box.add_child(_lan_list)
	_on_hosts_changed([])
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)
	_lan_ip = LineEdit.new()
	_lan_ip.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_lan_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lan_ip.custom_minimum_size = Vector2(0, 56)
	join_row.add_child(_lan_ip)
	var join := ThemeBuilder.make_button("Join", true, Vector2(140, 56))
	join.pressed.connect(func() -> void: _join_lan(_lan_ip.text))
	join_row.add_child(join)
	_tabs.tab_changed.connect(func(tab: int) -> void:
		if tab == 1 and not Net.is_active():
			Net.discovery.browse()
		elif not Net.is_active():
			Net.discovery.stop())
	return box.get_parent().get_parent()


func _build_online() -> Control:
	var box := _page("Online")
	box.add_child(_note("Online rooms are relayed by your own free Supabase project "
		+ "(Project Settings > API: the project URL and the anon public key). "
		+ "Up to %d players per room." % Net.MAX_ONLINE_PLAYERS))
	_online_url = LineEdit.new()
	_online_url.placeholder_text = "https://your-project.supabase.co"
	_online_url.text = Settings.supabase_url
	_online_url.custom_minimum_size = Vector2(0, 52)
	_row(box, "Supabase URL", _online_url)
	_online_key = LineEdit.new()
	_online_key.placeholder_text = "anon public key"
	_online_key.secret = true
	_online_key.text = Settings.supabase_anon_key
	_online_key.custom_minimum_size = Vector2(0, 52)
	_row(box, "Anon key", _online_key)
	var save := func() -> void:
		Settings.supabase_url = _online_url.text.strip_edges()
		Settings.supabase_anon_key = _online_key.text.strip_edges()
		Settings.save()
	_online_url.text_changed.connect(func(_t: String) -> void: save.call())
	_online_key.text_changed.connect(func(_t: String) -> void: save.call())
	var host := ThemeBuilder.make_button("Create a room", false, Vector2(320, 70))
	host.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.pressed.connect(_on_host_online)
	box.add_child(host)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 10)
	box.add_child(join_row)
	_online_code = LineEdit.new()
	_online_code.placeholder_text = "Room code"
	_online_code.max_length = 5
	_online_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_online_code.custom_minimum_size = Vector2(0, 56)
	join_row.add_child(_online_code)
	var join := ThemeBuilder.make_button("Join", true, Vector2(140, 56))
	join.pressed.connect(_on_join_online)
	join_row.add_child(join)
	return box.get_parent().get_parent()


func _build_room() -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	_room_title = ThemeBuilder.make_header("Room")
	box.add_child(_room_title)
	_room_info = _note("")
	box.add_child(_room_info)
	_room_players = VBoxContainer.new()
	_room_players.add_theme_constant_override("separation", 6)
	box.add_child(_room_players)

	var settings := VBoxContainer.new()
	settings.add_theme_constant_override("separation", 10)
	box.add_child(settings)
	_room_settings = settings
	_room_mode = _option(MODE_LABELS)
	_room_mode.item_selected.connect(func(_i: int) -> void: _push_room_config())
	_row(settings, "Mode", _room_mode)
	_room_bots = _spin(0, 15, 3)
	_room_bots.value_changed.connect(func(_v: float) -> void: _push_room_config())
	_room_ffa_rows.append(_row(settings, "Bots", _room_bots))
	_room_teams = _spin(2, 4, 2)
	_room_teams.value_changed.connect(func(_v: float) -> void: _push_room_config())
	_room_tdm_rows.append(_row(settings, "Teams", _room_teams))
	_room_size = _spin(1, 4, 4)
	_room_size.value_changed.connect(func(_v: float) -> void: _push_room_config())
	_room_tdm_rows.append(_row(settings, "Karts per team", _room_size))
	_room_diff = _difficulty_option(0.6)
	_room_diff.item_selected.connect(func(_i: int) -> void: _push_room_config())
	_row(settings, "Bot difficulty", _room_diff)

	_room_start = ThemeBuilder.make_button("START MATCH", false, Vector2(340, 76))
	_room_start.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_room_start.pressed.connect(func() -> void: Net.start_match())
	box.add_child(_room_start)
	_room_wait = _note("Waiting for the host to start…")
	box.add_child(_room_wait)
	var leave := ThemeBuilder.make_button("Leave", true, Vector2(200, 60))
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	leave.pressed.connect(_on_leave)
	box.add_child(leave)
	return panel


# --- Small builders ----------------------------------------------------------------

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	return box


func _row(parent: Container, label: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(200, 0)
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	parent.add_child(row)
	return row


func _note(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", ThemeBuilder.TEXT_DIM)
	l.add_theme_font_size_override("font_size", 18)
	return l


func _option(labels: Array) -> OptionButton:
	var o := OptionButton.new()
	for l in labels:
		o.add_item(l)
	o.custom_minimum_size = Vector2(0, 56)
	return o


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.rounded = true
	s.value = clampi(value, lo, hi)
	s.custom_minimum_size = Vector2(0, 56)
	return s


func _difficulty_option(value: float) -> OptionButton:
	var names: Array = Settings.DIFFICULTY_PRESETS.keys()
	var o := _option(names)
	var best := 0
	for i in names.size():
		if absf(float(Settings.DIFFICULTY_PRESETS[names[i]]) - value) < absf(float(Settings.DIFFICULTY_PRESETS[names[best]]) - value):
			best = i
	o.selected = best
	return o


func _difficulty_value(o: OptionButton) -> float:
	return float(Settings.DIFFICULTY_PRESETS[o.get_item_text(o.selected)])


# --- State ----------------------------------------------------------------------------

func _show_current() -> void:
	var in_room := Net.is_active() and not _connecting
	_home.visible = not in_room
	_room.visible = in_room
	if in_room:
		_refresh_room()


func _set_status(text: String, is_error := false) -> void:
	_status.text = text
	_status.visible = text != ""
	_status.add_theme_color_override("font_color", ThemeBuilder.RED if is_error else ThemeBuilder.TEAL_LIGHT)


func _player_name() -> String:
	var n := _name_edit.text.strip_edges()
	return n if n != "" else "Player"


func _update_solo_rows() -> void:
	var tdm := _solo_mode.selected == 1
	for r in _solo_ffa_rows:
		r.visible = not tdm
	for r in _solo_tdm_rows:
		r.visible = tdm


func _refresh_room() -> void:
	if not Net.is_active() or _connecting:
		return
	_updating = true
	var host := Net.is_host()
	var tdm := str(Net.config["mode"]) == "tdm"
	if Net.transport == "online":
		_room_title.text = "Room code: %s" % Net.room_code
		_room_info.text = "Friends join from Play > Online with this code."
	else:
		_room_title.text = "LAN game"
		_room_info.text = ("Others can join from Play > LAN. Your address: %s" % ", ".join(_local_ips())) if host \
			else "Connected to %s" % Net.host_address
	_room_settings.visible = true
	for c in [_room_mode, _room_bots, _room_teams, _room_size, _room_diff]:
		if c is OptionButton:
			(c as OptionButton).disabled = not host
		else:
			(c as SpinBox).editable = host
	_room_mode.selected = 1 if tdm else 0
	_room_bots.value = int(Net.config["ai_count"])
	_room_teams.value = int(Net.config["team_count"])
	_room_size.value = int(Net.config["team_size"])
	for r in _room_ffa_rows:
		r.visible = not tdm
	for r in _room_tdm_rows:
		r.visible = tdm
	_room_start.visible = host
	_room_wait.visible = not host
	_updating = false

	for c in _room_players.get_children():
		c.queue_free()
	if tdm:
		for t in int(Net.config["team_count"]):
			var header := HBoxContainer.new()
			var l := Label.new()
			l.text = "Team %s" % Teams.team_name(t)
			l.add_theme_color_override("font_color", Teams.team_color(t))
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header.add_child(l)
			var join := ThemeBuilder.make_button("Join team", true, Vector2(170, 48))
			join.pressed.connect(Net.request_team.bind(t))
			header.add_child(join)
			_room_players.add_child(header)
			var members := 0
			for p in Net.players:
				if int(p["team"]) == t:
					_room_players.add_child(_player_line(p, Teams.team_color(t)))
					members += 1
			if members < int(Net.config["team_size"]):
				_room_players.add_child(_bot_line(int(Net.config["team_size"]) - members))
	else:
		for p in Net.players:
			_room_players.add_child(_player_line(p, ThemeBuilder.TEXT))
		if int(Net.config["ai_count"]) > 0:
			_room_players.add_child(_bot_line(int(Net.config["ai_count"])))


func _player_line(p: Dictionary, color: Color) -> Label:
	var l := Label.new()
	var tags := []
	if int(p["peer"]) == 1:
		tags.append("host")
	if int(p["peer"]) == Net.get_my_peer_id():
		tags.append("you")
	l.text = "   %s%s" % [p["name"], (" (%s)" % ", ".join(tags)) if not tags.is_empty() else ""]
	l.add_theme_color_override("font_color", color)
	return l


func _bot_line(count: int) -> Label:
	var l := _note("   + %d bot%s" % [count, "" if count == 1 else "s"])
	return l


func _push_room_config() -> void:
	if _updating or not Net.is_host():
		return
	Net.set_config({"mode": MODES[_room_mode.selected], "ai_count": int(_room_bots.value),
		"team_count": int(_room_teams.value), "team_size": int(_room_size.value),
		"ai_difficulty": _difficulty_value(_room_diff)})


static func _local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or (ip.begins_with("172.") and ip.split(".").size() == 4 and int(ip.split(".")[1]) >= 16 and int(ip.split(".")[1]) <= 31):
			out.append(ip)
	return out if not out.is_empty() else ["unknown"]


# --- Actions ---------------------------------------------------------------------------

func _on_back() -> void:
	Net.leave()
	get_tree().change_scene_to_file.call_deferred(MENU_SCENE)


func _on_solo_start() -> void:
	Settings.game_mode = MODES[_solo_mode.selected]
	Settings.ai_count = int(_solo_bots.value)
	Settings.team_count = int(_solo_teams.value)
	Settings.team_size = int(_solo_size.value)
	Settings.ai_difficulty = _difficulty_value(_solo_diff)
	Settings.save()
	Net.leave()
	GameState.reset()
	GameState.set_setup(MatchSetup.offline_from_settings())
	get_tree().change_scene_to_file.call_deferred(GAME_SCENE)


func _on_host_lan() -> void:
	var err := Net.host_lan(_player_name())
	if err != OK:
		_set_status("Could not host on port %d (error %d). Is another game already hosting?" % [Net.LAN_PORT, err], true)
		return
	Net.set_config({"ai_count": 3})
	_set_status("")
	_show_current()


func _join_lan(address: String) -> void:
	if address.strip_edges() == "":
		_set_status("Type the host's IP address first.", true)
		return
	if Net.join_lan(address, _player_name()) != OK:
		_set_status("Could not start connecting.", true)
		return
	_begin_connecting("Connecting to %s…" % address)


func _on_host_online() -> void:
	if not Settings.has_online_config():
		_set_status("Enter your Supabase URL and anon key first.", true)
		return
	if Net.host_online(_player_name()) != OK:
		_set_status("Could not open the online connection.", true)
		return
	Net.set_config({"ai_count": 3})
	_set_status("")
	_show_current()


func _on_join_online() -> void:
	if not Settings.has_online_config():
		_set_status("Enter your Supabase URL and anon key first.", true)
		return
	if _online_code.text.strip_edges().length() < 4:
		_set_status("Type the room code first.", true)
		return
	if Net.join_online(_online_code.text, _player_name()) != OK:
		_set_status("Could not open the online connection.", true)
		return
	_begin_connecting("Joining room %s…" % _online_code.text.to_upper())


func _begin_connecting(text: String) -> void:
	_connecting = true
	_set_status(text)
	_show_current()


func _on_joined() -> void:
	_connecting = false
	_set_status("")
	_show_current()


func _on_session_ended(reason: String) -> void:
	_connecting = false
	Net.take_end_reason()
	_set_status(reason, true)
	_show_current()


func _on_leave() -> void:
	Net.leave()
	_set_status("")
	_show_current()


func _on_hosts_changed(hosts: Array) -> void:
	if _lan_list == null:
		return
	for c in _lan_list.get_children():
		c.queue_free()
	if hosts.is_empty():
		_lan_list.add_child(_note("Looking for games… (or type the host's IP below)"))
		return
	for h in hosts:
		var b := ThemeBuilder.make_button("%s's game  -  %d player%s" % [h.get("name", "?"), int(h.get("players", 1)),
			"" if int(h.get("players", 1)) == 1 else "s"], true, Vector2(0, 56))
		b.pressed.connect(_join_lan.bind(str(h["ip"])))
		_lan_list.add_child(b)
