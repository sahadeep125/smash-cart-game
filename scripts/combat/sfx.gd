## Tiny procedural sound effects (generated AudioStreamWAV, cached). Silent when headless.
## Plays on the "SFX" bus if it exists (Settings sets its volume), else scales by
## Settings.sfx_volume directly.
class_name CombatSfx
extends RefCounted

const MIX_RATE := 22050

static var _cache: Dictionary = {}
static var _enabled: int = -1  # -1 unknown, 0 off, 1 on


static func play(kind: String, at: Vector3, from: Node, volume_db := 0.0) -> void:
	if not _is_enabled() or from == null or not from.is_inside_tree():
		return
	var stream := _get_stream(kind)
	if stream == null:
		return
	var root := CombatUtil.get_projectile_root(from)
	if root == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.unit_size = 14.0
	p.max_distance = 90.0
	p.volume_db = volume_db + _base_db(kind)
	if AudioServer.get_bus_index("SFX") != -1:
		p.bus = "SFX"
	else:
		var settings := from.get_node_or_null("/root/Settings")
		if settings != null and settings.get("sfx_volume") != null:
			p.volume_db += linear_to_db(maxf(float(settings.get("sfx_volume")), 0.0001))
	p.pitch_scale = randf_range(0.92, 1.08)
	root.add_child(p)
	p.global_position = at
	p.finished.connect(p.queue_free)
	p.play()


static func _is_enabled() -> bool:
	if _enabled == -1:
		_enabled = 0 if DisplayServer.get_name() == "headless" else 1
	return _enabled == 1


static func _base_db(kind: String) -> float:
	match kind:
		"shot":
			return -10.0
		"explosion":
			return 2.0
	return -4.0


static func _get_stream(kind: String) -> AudioStreamWAV:
	if _cache.has(kind):
		return _cache[kind]
	var s: AudioStreamWAV = null
	match kind:
		"explosion":
			s = _make(0.8, _explosion_sample)
		"shot":
			s = _make(0.09, _shot_sample)
		"rocket":
			s = _make(0.4, _rocket_sample)
		"drop":
			s = _make(0.12, _drop_sample)
		"pickup":
			s = _make(0.28, _pickup_sample)
	_cache[kind] = s
	return s


static func _make(seconds: float, gen: Callable) -> AudioStreamWAV:
	var n := int(seconds * MIX_RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var state := {"lp": 0.0, "phase": 0.0}
	for i in n:
		var t := float(i) / MIX_RATE
		var v: float = gen.call(t, seconds, state)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w


static func _explosion_sample(t: float, dur: float, st: Dictionary) -> float:
	var env := pow(1.0 - t / dur, 2.2)
	var cutoff := lerpf(0.35, 0.04, t / dur)
	st.lp = lerpf(st.lp, randf_range(-1.0, 1.0), cutoff)
	return st.lp * env * 2.2 + sin(TAU * 55.0 * t) * env * 0.4


static func _shot_sample(t: float, dur: float, st: Dictionary) -> float:
	var env := 1.0 - t / dur
	var freq := lerpf(900.0, 300.0, t / dur)
	st.phase += freq / MIX_RATE
	var square := 1.0 if fmod(st.phase, 1.0) < 0.5 else -1.0
	return (square * 0.4 + randf_range(-0.3, 0.3)) * env


static func _rocket_sample(t: float, dur: float, st: Dictionary) -> float:
	var env := sin(PI * t / dur)
	st.lp = lerpf(st.lp, randf_range(-1.0, 1.0), 0.15)
	st.phase += lerpf(200.0, 520.0, t / dur) / MIX_RATE
	return st.lp * env * 0.9 + sin(TAU * st.phase) * env * 0.2


static func _drop_sample(t: float, dur: float, st: Dictionary) -> float:
	var env := 1.0 - t / dur
	st.phase += lerpf(260.0, 120.0, t / dur) / MIX_RATE
	return sin(TAU * st.phase) * env * 0.8


static func _pickup_sample(t: float, dur: float, st: Dictionary) -> float:
	var step := int(t / dur * 3.0)
	var freq: float = [660.0, 880.0, 1320.0][clampi(step, 0, 2)]
	st.phase += freq / MIX_RATE
	return sin(TAU * st.phase) * (1.0 - t / dur) * 0.6
