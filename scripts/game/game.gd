## Composes one offline match: arena, player kart, AI karts, crates, camera and HUD.
extends Node3D

const KART_NAMES: Array[String] = ["Bolt", "Rusty", "Nova", "Pepper", "Turbo", "Mango", "Zig"]
const KART_COLORS: Array[Color] = [
	Color("#ff3b6b"), Color("#ffd23f"), Color("#9b5de5"), Color("#00bbf9"),
	Color("#f15bb5"), Color("#8ac926"), Color("#ff924c"),
]
const PLAYER_COLOR := Color("#ff7a1a")

var arena: Arena
var player: Kart
var karts: Array[Kart] = []
var camera: FollowCamera
var hud: HUD


func _ready() -> void:
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	var projectiles := Node3D.new()
	projectiles.name = "Projectiles"
	projectiles.add_to_group("projectile_root")
	add_child(projectiles)

	_spawn_crates()

	var spawns := arena.get_spawn_points()
	spawns.shuffle()
	player = _create_kart("You", PLAYER_COLOR, true, spawns[0])
	var ai_count: int = clampi(Settings.ai_count, 1, KART_NAMES.size())
	for i in ai_count:
		_create_kart(KART_NAMES[i], KART_COLORS[i], false, spawns[(i + 1) % spawns.size()])

	var respawner := RespawnManager.new()
	respawner.name = "RespawnManager"
	add_child(respawner)

	camera = FollowCamera.new()
	camera.name = "FollowCamera"
	camera.target = player
	add_child(camera)
	camera.make_current()

	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind_player(player)

	_start_match()


func _create_kart(kart_name: String, color: Color, is_player: bool, spawn: Marker3D) -> Kart:
	var kart := Kart.new()
	kart.name = "Kart_" + kart_name
	kart.setup(kart_name, color, is_player)

	var health := Health.new()
	health.name = "Health"
	kart.add_child(health)
	var holder := WeaponHolder.new()
	holder.name = "WeaponHolder"
	kart.add_child(holder)

	if is_player:
		var pc := PlayerController.new()
		pc.name = "PlayerController"
		kart.add_child(pc)
	else:
		var ai := AIDriver.new()
		ai.name = "AIDriver"
		ai.difficulty = Settings.ai_difficulty
		kart.add_child(ai)

	add_child(kart)
	kart.global_transform = spawn.global_transform
	karts.append(kart)
	return kart


func _spawn_crates() -> void:
	for marker in arena.get_crate_spawn_points():
		var crate := WeaponCrate.new()
		add_child(crate)
		crate.global_position = marker.global_position


func _start_match() -> void:
	for kart in karts:
		kart.controls_enabled = false
	GameState.start_match(karts)
	# Hold the karts during the 3-2-1 countdown; the clock starts on "GO".
	GameState.set_paused_clock(true)
	await hud.play_countdown()
	if not is_inside_tree():
		return
	GameState.set_paused_clock(false)
	for kart in karts:
		kart.controls_enabled = true
