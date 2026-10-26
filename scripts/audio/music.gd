## Procedural background music (autoload "Music"). Every track is composed and
## synthesised in code from a small recipe (tempo, key, chords, drum and bass
## patterns), so there are no audio files. Tracks render in small time slices across
## frames (a few ms per frame, no hitch), then loop as an AudioStreamWAV on the
## "Music" bus. Silent in headless runs.
extends Node

const MIX_RATE := 22050
const SLICE_USEC := 3000          # render budget per frame
const SEGMENT := 2048             # samples rendered per step inside a slice
const FADE_TIME := 1.2

## Track recipes. `prog` is chord roots as scale degrees (one chord per bar);
## drum patterns are 16 steps per bar ("x" = hit, "." = rest).
const TRACKS := {
	"menu": {"bpm": 104, "root": 57, "scale": [0, 2, 3, 5, 7, 8, 10], "prog": [0, 5, 2, 6], "bars": 4,
		"kick": "x.......x.......", "snare": "....x.......x...", "hat": "..x...x...x...x.",
		"bass": "x...x...x.x.....", "arp": "x.x.x.x.x.x.x.x.", "arp_wave": "tri", "lead": false, "pad": 0.5},
	"scrapyard": {"bpm": 128, "root": 52, "scale": [0, 2, 3, 5, 7, 8, 10], "prog": [0, 0, 5, 6], "bars": 4,
		"kick": "x...x...x...x...", "snare": "....x.......x...", "hat": "x.x.x.x.x.x.x.xx",
		"bass": "x.xx..x.x.xx..x.", "arp": "x..x..x.x..x..x.", "arp_wave": "square", "lead": true, "pad": 0.3},
	"harbor": {"bpm": 118, "root": 55, "scale": [0, 2, 4, 5, 7, 9, 11], "prog": [0, 4, 5, 3], "bars": 4,
		"kick": "x.......x..x....", "snare": "....x.......x...", "hat": "..x...x...x...x.",
		"bass": "x...x...x...x.x.", "arp": "x.xxx.xxx.xxx.xx", "arp_wave": "tri", "lead": true, "pad": 0.45},
	"rooftop": {"bpm": 132, "root": 50, "scale": [0, 2, 3, 5, 7, 8, 10], "prog": [0, 6, 5, 4], "bars": 4,
		"kick": "x...x...x...x...", "snare": "....x.......x..x", "hat": ".xx..xx..xx..xx.",
		"bass": "xxx.xxx.xxx.x.x.", "arp": "xxxxxxxxxxxxxxxx", "arp_wave": "saw", "lead": true, "pad": 0.35},
	"temple": {"bpm": 112, "root": 53, "scale": [0, 2, 3, 5, 7, 9, 10], "prog": [0, 3, 6, 4], "bars": 4,
		"kick": "x..x....x..x....", "snare": "....x.......x...", "hat": "x.x.xx.xx.x.xx.x",
		"bass": "x..x..x.x..x..x.", "arp": "x...x.x...x.x...", "arp_wave": "tri", "lead": true, "pad": 0.4},
}

var _player: AudioStreamPlayer
var _cache := {}
var _current := ""
var _wanted := ""
## Rendering job: {id, buf: PackedFloat32Array, notes: Array, index, offset, lp, sounds, tmp}.
var _job: Dictionary = {}
var _silent := false
var _queue: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_silent = DisplayServer.get_name() == "headless"
	_player = AudioStreamPlayer.new()
	_player.name = "MusicPlayer"
	if AudioServer.get_bus_index("Music") != -1:
		_player.bus = "Music"
	_player.volume_db = -80.0
	add_child(_player)


## Starts (or crossfades to) a track: "menu" or a map id. Unknown ids use "menu".
func play(track: String) -> void:
	if _silent:
		return
	if not TRACKS.has(track):
		track = "menu"
	_wanted = track
	if track == _current and _player.playing:
		return
	if _cache.has(track):
		_switch_to(track)
	elif _job.is_empty() or _job["id"] != track:
		_job = _start_job(track)


## Renders tracks in the background (after the current one) so they start instantly.
func prefetch(tracks: Array) -> void:
	if _silent:
		return
	for t in tracks:
		if TRACKS.has(t) and not _cache.has(t) and not _queue.has(t):
			_queue.append(t)


func stop() -> void:
	_wanted = ""
	_current = ""
	if _player.playing:
		var tw := create_tween()
		tw.tween_property(_player, "volume_db", -80.0, 0.6)
		tw.tween_callback(_player.stop)


func is_ready(track: String) -> bool:
	return _cache.has(track)


func _process(_delta: float) -> void:
	if _job.is_empty():
		while not _queue.is_empty() and _job.is_empty():
			var next: String = _queue.pop_front()
			if not _cache.has(next):
				_job = _start_job(next)
		if _job.is_empty():
			return
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < SLICE_USEC:
		if _render_step(_job):
			var id: String = _job["id"]
			_cache[id] = _finish(_job)
			_job = {}
			if _wanted == id:
				_switch_to(id)
			break


func _switch_to(track: String) -> void:
	_current = track
	_player.stream = _cache[track]
	_player.volume_db = -40.0
	_player.play()
	var tw := create_tween()
	tw.tween_property(_player, "volume_db", -6.0, FADE_TIME)


# --- Composition ---------------------------------------------------------------------

func _start_job(id: String) -> Dictionary:
	var r: Dictionary = TRACKS[id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var step := 60.0 / float(r["bpm"]) / 4.0
	var bars := int(r["bars"])
	var total := int(round(step * 16.0 * bars * MIX_RATE))
	var notes: Array = []
	var scale: Array = r["scale"]
	var root := int(r["root"])
	var prog: Array = r["prog"]
	# A two-bar lead motif, repeated with a variation in the second half.
	var motif: Array = []
	for i in 8:
		motif.append(rng.randi_range(0, 6) if rng.randf() < 0.8 else -1)
	for bar in bars:
		var degree := int(prog[bar % prog.size()])
		var chord := [_note(root, scale, degree), _note(root, scale, degree + 2), _note(root, scale, degree + 4)]
		var bar_start := bar * 16
		for s in 16:
			var at := int((bar_start + s) * step * MIX_RATE)
			if str(r["kick"])[s] == "x":
				notes.append({"v": "kick", "at": at, "len": int(0.28 * MIX_RATE), "f": 0.0, "amp": 0.9})
			if str(r["snare"])[s] == "x":
				notes.append({"v": "snare", "at": at, "len": int(0.18 * MIX_RATE), "f": 0.0, "amp": 0.45})
			if str(r["hat"])[s] == "x":
				notes.append({"v": "hat", "at": at, "len": int(0.05 * MIX_RATE), "f": 0.0, "amp": 0.16 if s % 4 else 0.22})
			if str(r["bass"])[s] == "x":
				var bn: int = chord[0] - 12 if s % 8 != 6 else chord[2] - 12
				notes.append({"v": "bass", "at": at, "len": int(step * 1.8 * MIX_RATE), "f": _hz(bn), "amp": 0.34})
			if str(r["arp"])[s] == "x":
				var an: int = chord[s % 3] + 12 + (12 if (s / 4) % 2 == 1 else 0)
				notes.append({"v": str(r["arp_wave"]), "at": at, "len": int(step * 0.9 * MIX_RATE), "f": _hz(an), "amp": 0.09})
			if bool(r["lead"]) and bar >= 2 and s % 4 == 0:
				var m: int = motif[((bar % 2) * 4 + s / 4) % motif.size()]
				if m >= 0:
					var ln := _note(root + 12, scale, degree + m)
					notes.append({"v": "lead", "at": at, "len": int(step * 3.6 * MIX_RATE), "f": _hz(ln), "amp": 0.11})
		# Pad: the whole chord, softly, for the whole bar (one voice, three detuned saws).
		if float(r["pad"]) > 0.0:
			notes.append({"v": "pad", "at": int(bar_start * step * MIX_RATE), "len": int(16 * step * MIX_RATE),
				"f": _hz(int(chord[0])), "f2": _hz(int(chord[1])), "f3": _hz(int(chord[2])), "amp": 0.05 * float(r["pad"])})
	var buf := PackedFloat32Array()
	buf.resize(total)
	return {"id": id, "buf": buf, "notes": notes, "index": 0, "offset": 0, "lp": 0.0, "noise": 1234567,
		"sounds": {}, "tmp": PackedFloat32Array()}


static func _note(root: int, scale: Array, degree: int) -> int:
	var octave := floori(float(degree) / scale.size())
	var idx := degree - octave * scale.size()
	return root + int(scale[idx]) + 12 * octave


static func _hz(midi: int) -> float:
	return 440.0 * pow(2.0, (midi - 69) / 12.0)


# --- Synthesis -------------------------------------------------------------------------

## Does one segment of work on the current note: synthesise it (once per distinct
## sound, then cached for the rest of the track) or mix it into the loop buffer.
## Returns true when every note is done.
func _render_step(job: Dictionary) -> bool:
	var notes: Array = job["notes"]
	var index: int = job["index"]
	if index >= notes.size():
		return true
	var n: Dictionary = notes[index]
	var key := "%s|%.2f|%.2f|%d" % [n["v"], n["f"], n.get("f2", 0.0), n["len"]]
	var sounds: Dictionary = job["sounds"]
	if not sounds.has(key):
		if _synth_segment(job, n):
			sounds[key] = job["tmp"]
			job["tmp"] = PackedFloat32Array()
			job["offset"] = 0
		return false
	var src: PackedFloat32Array = sounds[key]
	var buf: PackedFloat32Array = job["buf"]
	var total := buf.size()
	var offset: int = job["offset"]
	var end := mini(offset + SEGMENT * 4, src.size())
	var at: int = n["at"]
	var amp: float = n["amp"]
	for i in range(offset, end):
		var k := at + i
		if k >= total:
			k -= total  # tails wrap around so the loop is seamless
		buf[k] += src[i] * amp
	if end >= src.size():
		job["index"] = index + 1
		job["offset"] = 0
	else:
		job["offset"] = end
	return false


## Synthesises the next segment of note `n` into job.tmp. Returns true when complete.
func _synth_segment(job: Dictionary, n: Dictionary) -> bool:
	var length: int = n["len"]
	var tmp: PackedFloat32Array = job["tmp"]
	var offset: int = job["offset"]
	if offset == 0:
		tmp = PackedFloat32Array()
		tmp.resize(length)
		job["lp"] = 0.0
	var end := mini(offset + SEGMENT, length)
	var f: float = n["f"]
	var f2: float = n.get("f2", f)
	var f3: float = n.get("f3", f)
	var voice: String = n["v"]
	var lp: float = job["lp"]
	var noise: int = job["noise"]
	var inv := 1.0 / MIX_RATE
	var dur := length * inv
	for i in range(offset, end):
		var t := i * inv
		var s := 0.0
		match voice:
			"kick":
				# Sine sweeping 130 -> 45 Hz (phase is the integral of the frequency).
				s = sin(TAU * (45.0 * t + 85.0 * (1.0 - exp(-t * 28.0)) / 28.0)) * exp(-t * 9.0)
			"snare":
				noise = (noise * 1103515245 + 12345) & 0x7fffffff
				s = (float(noise) / 1073741824.0 - 1.0) * exp(-t * 22.0) * 0.8 + sin(TAU * 190.0 * t) * exp(-t * 30.0) * 0.5
			"hat":
				noise = (noise * 1103515245 + 12345) & 0x7fffffff
				var w := float(noise) / 1073741824.0 - 1.0
				s = (w - lp) * exp(-t * 70.0)
				lp = w
			"bass":
				var raw := 2.0 * fmod(f * t, 1.0) - 1.0
				lp += (raw - lp) * 0.12
				s = lp * _env(t, dur, 0.005, 0.08)
			"square":
				s = (1.0 if fmod(f * t, 1.0) < 0.5 else -1.0) * _env(t, dur, 0.003, 0.04)
			"saw":
				var raw := 2.0 * fmod(f * t, 1.0) - 1.0
				lp += (raw - lp) * 0.3
				s = lp * _env(t, dur, 0.003, 0.04)
			"tri":
				s = (1.0 - 4.0 * absf(fmod(f * t, 1.0) - 0.5)) * _env(t, dur, 0.003, 0.05)
			"lead":
				var ph := fmod(f * t + 0.02 * sin(TAU * 5.5 * t), 1.0)
				s = ((1.0 - 4.0 * absf(ph - 0.5)) * 0.7 + (1.0 if ph < 0.3 else -1.0) * 0.3) * _env(t, dur, 0.01, 0.12)
			"pad":
				var raw := 2.0 * (fmod(f * t, 1.0) + fmod(f2 * 1.004 * t, 1.0) + fmod(f3 * 0.997 * t, 1.0)) - 3.0
				lp += (raw * 0.5 - lp) * 0.04
				s = lp * _env(t, dur, 0.35, 0.5)
		tmp[i] = s
	job["tmp"] = tmp
	job["lp"] = lp
	job["noise"] = noise
	if end >= length:
		return true
	job["offset"] = end
	return false


## Attack / release envelope for a note of `length` seconds.
static func _env(t: float, length: float, attack: float, release: float) -> float:
	var a := clampf(t / attack, 0.0, 1.0)
	var r := clampf((length - t) / release, 0.0, 1.0)
	return a * r


func _finish(job: Dictionary) -> AudioStreamWAV:
	var buf: PackedFloat32Array = job["buf"]
	var peak := 0.001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.85 / peak
	var bytes := PackedByteArray()
	bytes.resize(buf.size() * 2)
	for i in buf.size():
		var v := int(clampf(buf[i] * gain, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = buf.size()
	return w


## Renders a whole track at once (tests and the WAV export tool).
func render_now(track: String) -> AudioStreamWAV:
	var job := _start_job(track)
	while not _render_step(job):
		pass
	return _finish(job)
