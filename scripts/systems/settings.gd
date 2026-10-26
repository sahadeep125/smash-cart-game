## Player settings (autoload "Settings").
## Persisted to user://settings.cfg and applied to the audio buses.
extends Node

signal settings_changed

const SAVE_PATH := "user://settings.cfg"
const SECTION := "settings"
const TOUCH_MODES: Array[String] = ["auto", "on", "off"]
## Named difficulty presets used by the settings screen.
const DIFFICULTY_PRESETS := {"Easy": 0.3, "Normal": 0.6, "Hard": 0.9}

var master_volume: float = 0.8
var sfx_volume: float = 0.8
var music_volume: float = 0.6
## "auto", "on" or "off".
var touch_controls: String = "auto"
var ai_count: int = 5
var ai_difficulty: float = 0.6
var camera_shake: bool = true
var show_fps: bool = false
var player_name: String = ""
## "ffa" or "tdm" for solo matches against bots.
var game_mode: String = "ffa"
var team_count: int = 2
var team_size: int = 4
## Online play through Supabase Realtime (your own free project; see README).
var supabase_url: String = ""
var supabase_anon_key: String = ""

## Where save()/load_settings() read and write. Tests may point this elsewhere.
var save_path: String = SAVE_PATH


func _ready() -> void:
	_ensure_bus("SFX")
	_ensure_bus("Music")
	load_settings()


# --- Persistence ------------------------------------------------------------

func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(SECTION, "master_volume", master_volume)
	cfg.set_value(SECTION, "sfx_volume", sfx_volume)
	cfg.set_value(SECTION, "music_volume", music_volume)
	cfg.set_value(SECTION, "touch_controls", touch_controls)
	cfg.set_value(SECTION, "ai_count", ai_count)
	cfg.set_value(SECTION, "ai_difficulty", ai_difficulty)
	cfg.set_value(SECTION, "camera_shake", camera_shake)
	cfg.set_value(SECTION, "show_fps", show_fps)
	cfg.set_value(SECTION, "player_name", player_name)
	cfg.set_value(SECTION, "game_mode", game_mode)
	cfg.set_value(SECTION, "team_count", team_count)
	cfg.set_value(SECTION, "team_size", team_size)
	cfg.set_value(SECTION, "supabase_url", supabase_url)
	cfg.set_value(SECTION, "supabase_anon_key", supabase_anon_key)
	var err := cfg.save(save_path)
	if err != OK:
		push_warning("Settings: could not save %s (error %d)" % [save_path, err])
	apply()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK:
		master_volume = clampf(float(cfg.get_value(SECTION, "master_volume", master_volume)), 0.0, 1.0)
		sfx_volume = clampf(float(cfg.get_value(SECTION, "sfx_volume", sfx_volume)), 0.0, 1.0)
		music_volume = clampf(float(cfg.get_value(SECTION, "music_volume", music_volume)), 0.0, 1.0)
		var mode := str(cfg.get_value(SECTION, "touch_controls", touch_controls))
		touch_controls = mode if mode in TOUCH_MODES else "auto"
		ai_count = clampi(int(cfg.get_value(SECTION, "ai_count", ai_count)), 1, 15)
		ai_difficulty = clampf(float(cfg.get_value(SECTION, "ai_difficulty", ai_difficulty)), 0.0, 1.0)
		camera_shake = bool(cfg.get_value(SECTION, "camera_shake", camera_shake))
		show_fps = bool(cfg.get_value(SECTION, "show_fps", show_fps))
		player_name = str(cfg.get_value(SECTION, "player_name", player_name)).substr(0, 14)
		game_mode = "tdm" if str(cfg.get_value(SECTION, "game_mode", game_mode)) == "tdm" else "ffa"
		team_count = clampi(int(cfg.get_value(SECTION, "team_count", team_count)), 2, 4)
		team_size = clampi(int(cfg.get_value(SECTION, "team_size", team_size)), 1, 4)
		supabase_url = str(cfg.get_value(SECTION, "supabase_url", supabase_url)).strip_edges()
		supabase_anon_key = str(cfg.get_value(SECTION, "supabase_anon_key", supabase_anon_key)).strip_edges()
	apply()


## Push the current values to the engine and notify listeners.
func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Music", music_volume)
	settings_changed.emit()


# --- Queries ----------------------------------------------------------------

func get_player_name() -> String:
	var n := player_name.strip_edges()
	return n if n != "" else "Player"


func has_online_config() -> bool:
	return (supabase_url.begins_with("https://") or supabase_url.begins_with("http://")) and supabase_anon_key.length() > 20

func should_show_touch_controls() -> bool:
	match touch_controls:
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available() \
		or OS.has_feature("mobile") \
		or OS.has_feature("web_android") \
		or OS.has_feature("web_ios")


## Returns the preset name ("Easy"/"Normal"/"Hard") closest to ai_difficulty.
func get_difficulty_name() -> String:
	var best := "Normal"
	var best_dist := INF
	for preset_name in DIFFICULTY_PRESETS:
		var dist := absf(float(DIFFICULTY_PRESETS[preset_name]) - ai_difficulty)
		if dist < best_dist:
			best_dist = dist
			best = preset_name
	return best


# --- Audio helpers ----------------------------------------------------------

func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)
