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
		ai_count = clampi(int(cfg.get_value(SECTION, "ai_count", ai_count)), 1, 7)
		ai_difficulty = clampf(float(cfg.get_value(SECTION, "ai_difficulty", ai_difficulty)), 0.0, 1.0)
		camera_shake = bool(cfg.get_value(SECTION, "camera_shake", camera_shake))
		show_fps = bool(cfg.get_value(SECTION, "show_fps", show_fps))
	apply()


## Push the current values to the engine and notify listeners.
func apply() -> void:
	_set_bus_volume("Master", master_volume)
	_set_bus_volume("SFX", sfx_volume)
	_set_bus_volume("Music", music_volume)
	settings_changed.emit()


# --- Queries ----------------------------------------------------------------

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
