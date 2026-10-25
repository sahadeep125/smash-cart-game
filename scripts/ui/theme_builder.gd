## Builds the original "Kart Clash" UI theme in code (no binary assets).
## Bright orange / teal on dark navy, bold rounded buttons, large mobile-friendly fonts.
class_name ThemeBuilder
extends RefCounted

const NAVY := Color("141b33")
const NAVY_LIGHT := Color("1f2a52")
const NAVY_DARK := Color("0b1022")
const ORANGE := Color("ff7a1a")
const ORANGE_LIGHT := Color("ffa04d")
const TEAL := Color("19c3b1")
const TEAL_LIGHT := Color("5fe3d4")
const RED := Color("ff3b4f")
const GOLD := Color("ffd23f")
const TEXT := Color("f5f7ff")
const TEXT_DIM := Color("aab3d6")

const FONT_SIZE := 26
const FONT_SIZE_SMALL := 20
const FONT_SIZE_TITLE := 96

static var _cached: Theme


## Shared theme instance (built once).
static func get_theme() -> Theme:
	if _cached == null:
		_cached = build_theme()
	return _cached


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = FONT_SIZE

	# Buttons -----------------------------------------------------------------
	t.set_stylebox("normal", "Button", make_box(ORANGE, 18, ORANGE_LIGHT.darkened(0.1), 3))
	t.set_stylebox("hover", "Button", make_box(ORANGE_LIGHT, 18, Color.WHITE, 3))
	t.set_stylebox("pressed", "Button", make_box(ORANGE.darkened(0.25), 18, ORANGE, 3))
	t.set_stylebox("focus", "Button", make_box(Color(0, 0, 0, 0), 18, TEAL_LIGHT, 4))
	t.set_stylebox("disabled", "Button", make_box(NAVY_LIGHT, 18, NAVY_LIGHT, 3))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", TEXT_DIM)
	t.set_color("font_outline_color", "Button", NAVY_DARK)
	t.set_constant("outline_size", "Button", 4)
	t.set_font_size("font_size", "Button", 30)

	# Secondary (teal) button variation
	t.add_type("TealButton")
	t.set_type_variation("TealButton", "Button")
	t.set_stylebox("normal", "TealButton", make_box(TEAL.darkened(0.15), 18, TEAL_LIGHT, 3))
	t.set_stylebox("hover", "TealButton", make_box(TEAL, 18, Color.WHITE, 3))
	t.set_stylebox("pressed", "TealButton", make_box(TEAL.darkened(0.4), 18, TEAL, 3))

	# Panels / labels ---------------------------------------------------------
	var panel := make_box(Color(NAVY, 0.96), 22, TEAL, 4)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 22
	panel.content_margin_bottom = 22
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 12
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", NAVY_DARK)
	t.set_constant("outline_size", "Label", 3)

	# Title label variation (stylised branding text)
	t.add_type("TitleLabel")
	t.set_type_variation("TitleLabel", "Label")
	t.set_font_size("font_size", "TitleLabel", FONT_SIZE_TITLE)
	t.set_color("font_color", "TitleLabel", ORANGE)
	t.set_color("font_outline_color", "TitleLabel", NAVY_DARK)
	t.set_constant("outline_size", "TitleLabel", 18)
	t.set_color("font_shadow_color", "TitleLabel", Color(TEAL, 0.9))
	t.set_constant("shadow_offset_x", "TitleLabel", 6)
	t.set_constant("shadow_offset_y", "TitleLabel", 8)
	t.set_constant("shadow_outline_size", "TitleLabel", 18)

	t.add_type("HeaderLabel")
	t.set_type_variation("HeaderLabel", "Label")
	t.set_font_size("font_size", "HeaderLabel", 42)
	t.set_color("font_color", "HeaderLabel", TEAL_LIGHT)
	t.set_constant("outline_size", "HeaderLabel", 8)

	# Sliders / checks / option buttons ---------------------------------------
	var track := make_box(NAVY_DARK, 8)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	t.set_stylebox("slider", "HSlider", track)
	var fill := make_box(TEAL, 8)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var grabber := _circle_texture(28, ORANGE)
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", _circle_texture(28, ORANGE_LIGHT))

	t.set_font_size("font_size", "CheckButton", FONT_SIZE)
	t.set_font_size("font_size", "OptionButton", FONT_SIZE)
	t.set_stylebox("normal", "OptionButton", make_box(NAVY_LIGHT, 12, TEAL, 2))
	t.set_stylebox("hover", "OptionButton", make_box(NAVY_LIGHT.lightened(0.1), 12, TEAL_LIGHT, 2))
	t.set_stylebox("pressed", "OptionButton", make_box(NAVY_DARK, 12, TEAL, 2))
	t.set_stylebox("focus", "OptionButton", make_box(Color(0, 0, 0, 0), 12, TEAL_LIGHT, 3))

	# Progress bar (health)
	t.set_stylebox("background", "ProgressBar", make_box(Color(NAVY_DARK, 0.85), 10, Color(TEXT, 0.6), 2))
	t.set_stylebox("fill", "ProgressBar", make_box(TEAL, 10))
	t.set_constant("outline_size", "ProgressBar", 3)
	return t


## Rounded flat stylebox helper.
static func make_box(bg: Color, radius := 14, border := Color(0, 0, 0, 0), border_w := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 8
	if border_w > 0:
		sb.border_color = border
		sb.set_border_width_all(border_w)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.anti_aliasing = true
	return sb


## A stylised "KART CLASH" title: big outlined orange text with teal drop shadow.
static func make_title_label(text := "KART CLASH", size := FONT_SIZE_TITLE) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "TitleLabel"
	l.add_theme_font_size_override("font_size", size)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func make_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "HeaderLabel"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func make_button(text: String, teal := false, min_size := Vector2(320, 76)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	if teal:
		b.theme_type_variation = "TealButton"
	return b


static func _circle_texture(diameter: int, color: Color) -> ImageTexture:
	var img := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var a := clampf(r - d, 0.0, 1.0)
			var c := color if d < r - 3.0 else Color.WHITE
			img.set_pixel(x, y, Color(c, a))
	return ImageTexture.create_from_image(img)
