# Kart Clash architecture and module contracts

Everything is built in GDScript and mostly constructed in code (procedural low-poly
meshes, no imported models), so the project has no binary assets and every part can
be tested headless.

## Folders and owners

| Folder | Owner | Contents |
|---|---|---|
| `scripts/core/` | integration | `events.gd` signal bus (autoload `Events`) |
| `scripts/game/`, `scenes/game.tscn` | integration | `game.gd` composes one match |
| `scripts/kart/` | Kart & Arena | `kart.gd`, `kart_model.gd`, `player_controller.gd`, `ai_driver.gd` |
| `scripts/arena/` | Kart & Arena | `arena.gd` (geometry, obstacles, spawn markers) |
| `scripts/camera/` | Kart & Arena | `follow_camera.gd` |
| `scripts/combat/` | Combat | health, weapons, crates, projectiles, explosions, respawn |
| `scripts/ui/`, `scenes/main_menu.tscn` | UI & Game Systems | menu, HUD, touch controls, match end, settings screen |
| `scripts/systems/` | UI & Game Systems | autoloads `Settings` and `GameState` (timer, scores) |

## Physics layers

1 world, 2 karts, 3 projectiles, 4 pickups (named in `project.godot`).

## Input actions (defined in project.godot)

`accelerate` (W/Up), `brake` (S/Down, also reverse), `steer_left` (A/Left),
`steer_right` (D/Right), `drift` (Shift), `fire` (Space), `pause` (Esc/P).
Touch controls drive these same actions with `Input.action_press(action, strength)`,
so gameplay code never needs to know whether input came from touch or keyboard.

## Contracts

### Kart (`scripts/kart/kart.gd`, `class_name Kart extends CharacterBody3D`)
- In group `"karts"`. Collision layer 2, mask 1|2.
- `var kart_name: String`, `var kart_color: Color`, `var is_player: bool`
- `var alive: bool` (read-only for others)
- Control inputs, written each frame by a controller child:
  `var throttle: float` (-1..1), `var steer: float` (-1..1), `var drift_held: bool`
- `signal fire_requested` — controllers call `request_fire()`, which emits it
  (only while alive and controls enabled).
- `var controls_enabled: bool` — when false the kart coasts to a stop.
- `func setup(p_name: String, p_color: Color, p_is_player: bool) -> void` (call before add_child)
- `func get_health() -> Health` / `func get_weapon_holder() -> WeaponHolder` — return the
  child node named `"Health"` / `"WeaponHolder"` (or null).
- `func get_muzzle_transform() -> Transform3D` — global transform at the kart's nose,
  -Z is forward (Godot convention).
- `func get_forward() -> Vector3` — global forward (−basis.z, flattened).
- `func apply_knockback(impulse: Vector3) -> void`
- `func set_alive(value: bool) -> void` — false: hide, disable collision and controls.
- `func respawn_at(xform: Transform3D) -> void` — teleport, zero velocity, set_alive(true).
- `func get_speed() -> float`

### Controllers (children of a Kart)
- `PlayerController` (`player_controller.gd`) reads the input actions above.
- `AIDriver` (`ai_driver.gd`, `var difficulty: float` 0..1): goes for crates in group
  `"weapon_crates"` (that return `is_available() == true`) when unarmed, chases the
  nearest alive enemy kart when armed, calls `request_fire()` when the target is roughly
  in front (or behind, for mines: `WeaponHolder.current_weapon_id == "mine"`),
  avoids walls with raycasts and recovers when stuck.

### Arena (`scripts/arena/arena.gd`, `class_name Arena extends Node3D`)
- Builds floor, perimeter walls, obstacles, ramps on `_ready()`; collision layer 1.
- Adds `Marker3D` children in group `"spawn_points"` (>= 8) and `"crate_spawns"` (>= 8).
- `func get_spawn_points() -> Array[Marker3D]`, `func get_crate_spawn_points() -> Array[Marker3D]`
- Adds its own lighting (`DirectionalLight3D`) and `WorldEnvironment`.

### FollowCamera (`scripts/camera/follow_camera.gd`, `class_name FollowCamera extends Camera3D`)
- `var target: Node3D`; smooth chase from behind and above, looks ahead with speed,
  doesn't clip into walls too badly. Listens to `Events.camera_shake_requested`.

### Combat (`scripts/combat/`)
- `Health` (`class_name Health extends Node`, node name `"Health"`):
  `max_health`, `current_health`, `signal health_changed(current: float, max: float)`,
  `signal died(killer: Node)`, `func take_damage(amount: float, source: Node, weapon_id := "") -> void`,
  `func heal(amount)`, `func reset()`, `func is_dead()`, brief spawn invulnerability.
  On death emits `Events.kart_killed(victim_kart, killer_kart, weapon_id)`.
- `WeaponHolder` (`class_name WeaponHolder extends Node`, node name `"WeaponHolder"`):
  connects to parent kart's `fire_requested`. `var current_weapon_id: String` ("" = none),
  `var ammo: int`, `signal weapon_changed(weapon_id: String, ammo: int)`,
  `func give_weapon(id: String)`, `func give_random_weapon()`, `func has_weapon() -> bool`,
  `func fire()`, `func clear()`.
- `WeaponDB` (`weapon_db.gd`, static data): ids `"rocket"`, `"machine_gun"`, `"mine"`
  (plus optional extras), each with display name, ammo, cooldown, damage, icon color.
  `static func get_display_name(id) -> String`, `static func get_color(id) -> Color`,
  `static func all_ids() -> Array[String]`.
- `WeaponCrate` (`class_name WeaponCrate extends Area3D`, group `"weapon_crates"`):
  original "?"-free design (glowing spinning crate), gives a random weapon to a kart
  without one, hides and respawns after a delay. `func is_available() -> bool`.
- Projectiles / explosions / mines as their own scripts.
- `RespawnManager` (`class_name RespawnManager extends Node`): listens to
  `Events.kart_killed`, calls `kart.set_alive(false)`, after `respawn_delay` (3 s) picks a
  spawn point away from other karts, `kart.respawn_at(...)`, resets health and weapon,
  emits `Events.kart_respawned`. Respects `GameState.is_running()` (no respawn after match end).

### Systems (`scripts/systems/`)
- `Settings` autoload: `master_volume`, `sfx_volume`, `music_volume`, `touch_controls`
  ("auto"/"on"/"off"), `ai_count` (1..7, default 5), `ai_difficulty` (0..1),
  `camera_shake` (bool), `show_fps` (bool); `func save()`, `func load_settings()`
  (`user://settings.cfg`), `func should_show_touch_controls() -> bool`,
  `signal settings_changed`.
- `GameState` autoload: `match_duration := 180.0`, `func start_match(karts: Array)`,
  `func end_match()`, `func is_running() -> bool`, `func get_time_left() -> float`,
  `func get_score(kart_name) -> Dictionary`, `func get_results() -> Array`;
  `set_paused_clock(paused)` (used for the start countdown), `reset()`, `get_rank(name)`;
  counts kills/deaths from `Events.kart_killed` (a null killer or a self-kill only counts a
  death); emits the match signals in `events.gd`.

### UI (`scripts/ui/`)
- `main_menu.tscn` (main scene): title/branding, Play → `res://scenes/game.tscn`,
  Settings panel, Quit (hidden on web/mobile).
- `HUD` (`class_name HUD extends CanvasLayer`): `func bind_player(kart: Kart)` — health bar,
  current weapon + ammo, timer, kill counter, kill feed, small leaderboard, pause button,
  touch controls (`TouchControls` control) when `Settings.should_show_touch_controls()`.
- Pause menu (resume / restart / main menu) and match-end screen (rankings, Play again,
  Main menu) driven by `Events.match_ended`.

### Game (`scripts/game/game.gd`) — integration
Builds Arena, player Kart (+Health, WeaponHolder, PlayerController), `Settings.ai_count` AI
karts, crates at crate spawns, RespawnManager, FollowCamera, HUD; then
`GameState.start_match(karts)`.
