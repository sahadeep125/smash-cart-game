## On-screen touch controls. Drives the same input actions as the keyboard
## (via Input.action_press / action_release), so gameplay code is input-agnostic.
##
## Left half: floating steering joystick (horizontal axis -> steer_left / steer_right).
## Right side: big GAS button plus BRAKE, DRIFT and FIRE.
## Every finger is tracked by its touch index, so steering + gas + fire work together.
class_name TouchControls
extends Control

const DEADZONE := 0.12
const HIT_SLOP := 1.2

## Button definitions: action -> {label, color, scale}. Scale is relative to the
## shorter viewport side.
const BUTTONS := {
	"accelerate": {"label": "GAS", "color": Color("19c3b1"), "scale": 0.15},
	"brake": {"label": "BRAKE", "color": Color("5d6a9c"), "scale": 0.09},
	"drift": {"label": "DRIFT", "color": Color("ffd23f"), "scale": 0.09},
	"fire": {"label": "FIRE", "color": Color("ff7a1a"), "scale": 0.125},
}

## touch index -> action name (button touches)
var _button_touches: Dictionary = {}
## touch index steering the joystick (-1 = none)
var _stick_touch := -1
var _stick_origin := Vector2.ZERO
var _stick_knob := Vector2.ZERO
var _steer_value := 0.0

## Layout cache, recomputed on resize.
var _centers: Dictionary = {}
var _radii: Dictionary = {}
var _stick_rest := Vector2.ZERO
var _stick_radius := 80.0
var _stick_zone := Rect2()
var _safe_margins := Vector4.ZERO  # left, top, right, bottom


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Pass-through: we read touches in _input and only consume the ones that
	# land on our widgets, so other UI (pause button etc.) keeps working.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_VISIBILITY_CHANGED:
			if not is_visible_in_tree():
				release_all()
		NOTIFICATION_EXIT_TREE, NOTIFICATION_PAUSED, \
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, \
		NOTIFICATION_APPLICATION_PAUSED:
			release_all()


func _input(event: InputEvent) -> void:
	if handle_event(event):
		get_viewport().set_input_as_handled()


## Processes a touch event. Returns true when it was consumed by a widget.
## Public so tests (and integrators) can feed events directly.
func handle_event(event: InputEvent) -> bool:
	if not is_visible_in_tree():
		return false
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			return _on_touch_down(st.index, st.position)
		return _on_touch_up(st.index)
	if event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if sd.index == _stick_touch:
			_update_stick(sd.position)
			return true
		return _button_touches.has(sd.index)
	return false


# --- Touch handling -------------------------------------------------------------

func _on_touch_down(index: int, pos: Vector2) -> bool:
	# A re-used index without a release: drop the old state first.
	_on_touch_up(index)
	for action in _centers:
		if pos.distance_to(_centers[action]) <= float(_radii[action]) * HIT_SLOP:
			_button_touches[index] = action
			Input.action_press(action, 1.0)
			queue_redraw()
			return true
	if _stick_touch == -1 and _stick_zone.has_point(pos):
		_stick_touch = index
		_stick_origin = pos
		_update_stick(pos)
		return true
	return false


func _on_touch_up(index: int) -> bool:
	if _button_touches.has(index):
		var action: String = _button_touches[index]
		_button_touches.erase(index)
		if not _button_touches.values().has(action):
			Input.action_release(action)
		queue_redraw()
		return true
	if index == _stick_touch:
		_stick_touch = -1
		_set_steer(0.0)
		_stick_knob = Vector2.ZERO
		queue_redraw()
		return true
	return false


func _update_stick(pos: Vector2) -> void:
	var offset := pos - _stick_origin
	if offset.length() > _stick_radius:
		# Drag the origin along so the stick never feels "stuck" at the edge.
		_stick_origin = pos - offset.normalized() * _stick_radius
		offset = pos - _stick_origin
	_stick_knob = offset
	var x := clampf(offset.x / _stick_radius, -1.0, 1.0)
	if absf(x) < DEADZONE:
		x = 0.0
	else:
		x = signf(x) * inverse_lerp(DEADZONE, 1.0, absf(x))
	_set_steer(x)
	queue_redraw()


func _set_steer(value: float) -> void:
	_steer_value = value
	if value < 0.0:
		Input.action_release("steer_right")
		Input.action_press("steer_left", -value)
	elif value > 0.0:
		Input.action_release("steer_left")
		Input.action_press("steer_right", value)
	else:
		Input.action_release("steer_left")
		Input.action_release("steer_right")


## Releases every action this control may hold.
func release_all() -> void:
	for action in BUTTONS:
		if _button_touches.values().has(action):
			Input.action_release(action)
	_button_touches.clear()
	if _stick_touch != -1 or _steer_value != 0.0:
		Input.action_release("steer_left")
		Input.action_release("steer_right")
	_stick_touch = -1
	_steer_value = 0.0
	_stick_knob = Vector2.ZERO
	queue_redraw()


# --- Layout ---------------------------------------------------------------------

func _area_size() -> Vector2:
	if size.x > 1.0 and size.y > 1.0:
		return size
	if is_inside_tree():
		return get_viewport().get_visible_rect().size
	return Vector2(1280, 720)


func _compute_safe_margins(vp: Vector2) -> Vector4:
	# Insets from notches / rounded corners, converted to viewport units.
	var margins := Vector4.ZERO
	if DisplayServer.get_name() == "headless":
		return margins
	var screen := Vector2(DisplayServer.screen_get_size())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return margins
	var win := Vector2(DisplayServer.window_get_size())
	# Only meaningful when the game covers the screen (mobile / fullscreen).
	if win.distance_to(screen) > 4.0:
		return margins
	var k := vp / screen
	margins = Vector4(
		safe.position.x * k.x,
		safe.position.y * k.y,
		(screen.x - safe.end.x) * k.x,
		(screen.y - safe.end.y) * k.y)
	var cap := Vector4(vp.x, vp.y, vp.x, vp.y) * 0.15
	return Vector4(clampf(margins.x, 0, cap.x), clampf(margins.y, 0, cap.y),
		clampf(margins.z, 0, cap.z), clampf(margins.w, 0, cap.w))


func _layout() -> void:
	var vp := _area_size()
	_safe_margins = _compute_safe_margins(vp)
	var unit := minf(vp.x, vp.y)
	var pad := unit * 0.035
	var m := unit * 0.05
	var right := vp.x - m - _safe_margins.z
	var bottom := vp.y - m - _safe_margins.w
	var left := m + _safe_margins.x

	for action in BUTTONS:
		_radii[action] = unit * float(BUTTONS[action]["scale"])
	var rg: float = _radii["accelerate"]
	var rb: float = _radii["brake"]
	var rd: float = _radii["drift"]
	var rf: float = _radii["fire"]
	var gas := Vector2(right - rg, bottom - rg)
	_centers["accelerate"] = gas
	_centers["brake"] = Vector2(gas.x - rg - rb - pad, bottom - rb)
	_centers["fire"] = Vector2(gas.x - rg * 0.15, gas.y - rg - rf - pad)
	_centers["drift"] = Vector2(gas.x - rg - rd - pad * 1.5, gas.y - rg - rd * 0.4 - pad * 1.5)

	_stick_radius = unit * 0.15
	_stick_rest = Vector2(left + _stick_radius * 1.3, bottom - _stick_radius * 1.1)
	# Steering zone: left ~45% of the screen, below the top HUD strip.
	var top := vp.y * 0.28
	_stick_zone = Rect2(Vector2(0, top), Vector2(vp.x * 0.45, vp.y - top))
	if _stick_touch == -1:
		_stick_origin = _stick_rest
	queue_redraw()


## Screen-space center of a button (for tests / tutorials).
func get_button_center(action: String) -> Vector2:
	return _centers.get(action, Vector2.ZERO)


func get_button_radius(action: String) -> float:
	return float(_radii.get(action, 0.0))


func get_stick_rest_center() -> Vector2:
	return _stick_rest


func get_stick_radius() -> float:
	return _stick_radius


func get_steer_value() -> float:
	return _steer_value


# --- Drawing --------------------------------------------------------------------

func _draw() -> void:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	# Joystick
	var origin := _stick_origin if _stick_touch != -1 else _stick_rest
	draw_circle(origin, _stick_radius, Color(0.05, 0.07, 0.15, 0.35))
	draw_arc(origin, _stick_radius, 0, TAU, 48, Color(1, 1, 1, 0.45), 4.0, true)
	var arrow_off := _stick_radius * 0.72
	_draw_arrow(origin + Vector2(-arrow_off, 0), -1.0)
	_draw_arrow(origin + Vector2(arrow_off, 0), 1.0)
	var knob_alpha := 0.85 if _stick_touch != -1 else 0.55
	draw_circle(origin + _stick_knob, _stick_radius * 0.42, Color(1, 1, 1, knob_alpha))
	draw_circle(origin + _stick_knob, _stick_radius * 0.3, Color(0.1, 0.76, 0.69, knob_alpha))

	# Buttons
	var held := _button_touches.values()
	for action in _centers:
		var c: Vector2 = _centers[action]
		var r: float = _radii[action]
		var col: Color = BUTTONS[action]["color"]
		var pressed := held.has(action)
		var fill := col.darkened(0.3) if pressed else col
		fill.a = 0.85 if pressed else 0.6
		draw_circle(c, r, fill)
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.8 if pressed else 0.5), 4.0, true)
		var text: String = BUTTONS[action]["label"]
		var fs := int(clampf(r * 0.42, 14, 48))
		var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var tp := c + Vector2(-ts.x * 0.5, fs * 0.35)
		draw_string_outline(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 6, Color(0.04, 0.06, 0.13, 0.9))
		draw_string(font, tp, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


func _draw_arrow(at: Vector2, dir: float) -> void:
	var s := _stick_radius * 0.14
	var pts := PackedVector2Array([
		at + Vector2(dir * s, 0),
		at + Vector2(-dir * s * 0.6, -s),
		at + Vector2(-dir * s * 0.6, s)])
	draw_colored_polygon(pts, Color(1, 1, 1, 0.5))
