## Keeps a networked match in sync. Lives at /root/Game/MatchSync on every peer.
##
## Host (authoritative): simulates bots, combat, crates, respawns and the clock, and
## sends snapshots plus reliable events (kills, respawns, rockets, mines, explosions).
## Each human simulates their own kart's driving locally and sends its state to the
## host, so steering never waits for the network; the host fires weapons for them.
class_name MatchSync
extends Node

const READY_TIMEOUT := 10.0
const WEAPON_IDS: Array[String] = ["", "rocket", "machine_gun", "mine", "shield"]
const FIRING_WINDOW := 0.2

var game: Node
var _authority := false
var _send_timer := 0.0
var _ready_peers: Dictionary = {}
var _ready_wait := 0.0
var _started := false
## Host: kart id -> last state its owner sent; trigger expiry (seconds, host clock).
var _client_states: Dictionary = {}
var _trigger_until: Dictionary = {}
## Host: kart id -> time of the last shot (for client-side machine-gun visuals).
var _last_shot: Dictionary = {}
var _clock := 0.0
var _mine_counter := 0
## Client: mine net id -> visual Mine; kart id -> seconds of firing left / gun cooldown.
var _mines: Dictionary = {}
var _remote_firing: Dictionary = {}
var _gun_cooldown: Dictionary = {}


func setup_match(p_game: Node) -> void:
	game = p_game
	_authority = Net.is_host()
	for kart: Kart in game.karts:
		var holder := kart.get_weapon_holder()
		if _authority:
			holder.weapon_fired.connect(_on_weapon_fired.bind(kart.net_id))
			if kart.remote:
				kart.remote_knockback.connect(_on_remote_knockback.bind(kart))
	if _authority:
		Events.kart_killed.connect(_on_kart_killed)
		Events.kart_respawned.connect(_on_kart_respawned)
		Events.projectile_spawned.connect(_on_projectile_spawned)
		Events.explosion_fx.connect(_on_explosion_fx)
		Events.match_ended.connect(_on_match_ended)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		_ready_peers[1] = true
		_check_all_ready()
	else:
		_rpc_ready.rpc_id(1)


func _physics_process(delta: float) -> void:
	_clock += delta
	if _authority:
		_host_tick(delta)
	else:
		_client_tick(delta)


# --- Host ------------------------------------------------------------------------

func _host_tick(delta: float) -> void:
	if not _started:
		_ready_wait += delta
		if _ready_wait >= READY_TIMEOUT:
			_begin()
		return
	# Fire for remote players whose trigger is held.
	for id in _trigger_until:
		if _clock < float(_trigger_until[id]):
			var kart: Kart = game.get_kart(id)
			if kart:
				kart.request_fire()
	_send_timer += delta
	if _send_timer >= 1.0 / Net.snapshot_rate():
		_send_timer = 0.0
		_rpc_snapshot.rpc(_build_snapshot())


func _build_snapshot() -> Array:
	var crates := 0
	for i in game.crates.size():
		if (game.crates[i] as WeaponCrate).is_available():
			crates |= 1 << i
	var karts := []
	for kart: Kart in game.karts:
		var state: Array = _client_states.get(kart.net_id, []) if kart.remote else kart.net_get_state()
		if state.is_empty():
			state = kart.net_get_state()
		var h := kart.get_health()
		var w := kart.get_weapon_holder()
		var firing := _clock - float(_last_shot.get(kart.net_id, -10.0)) < FIRING_WINDOW
		karts.append([kart.net_id, state, int(ceil(h.current_health)), snappedf(h.get_invulnerable_time(), 0.1),
			WEAPON_IDS.find(w.current_weapon_id), w.ammo, firing])
	return [snappedf(GameState.get_time_left(), 0.01), crates, karts]


func _check_all_ready() -> void:
	if _started:
		return
	for p in multiplayer.get_peers():
		if not _ready_peers.has(p):
			return
	_begin()


func _begin() -> void:
	if _started:
		return
	_started = true
	_rpc_begin.rpc()
	game.start_match()


func _on_weapon_fired(_id: String, kart_id: int) -> void:
	_last_shot[kart_id] = _clock


func _on_remote_knockback(impulse: Vector3, kart: Kart) -> void:
	var owner := _owner_of(kart.net_id)
	if owner > 1:
		_rpc_knockback.rpc_id(owner, kart.net_id, impulse)


func _on_kart_killed(victim: Node, killer: Node, weapon_id: String) -> void:
	var vid := int(victim.get("net_id")) if victim else -1
	var kid := int(killer.get("net_id")) if killer and is_instance_valid(killer) else -1
	# Scores are sent after GameState has counted this kill.
	_send_kill.call_deferred(vid, kid, weapon_id)


func _send_kill(vid: int, kid: int, weapon_id: String) -> void:
	_rpc_kill.rpc(vid, kid, weapon_id, GameState.get_results())


func _on_kart_respawned(kart: Node) -> void:
	var k := kart as Kart
	if k:
		_rpc_respawn.rpc(k.net_id, k.global_position, k.rotation.y)


func _on_projectile_spawned(kind: String, owner: Node, origin: Vector3, direction: Vector3, node: Node) -> void:
	var oid := int(owner.get("net_id")) if owner else -1
	if kind == "rocket":
		_rpc_rocket.rpc(oid, origin, direction)
	elif kind == "mine" and node is Mine:
		_mine_counter += 1
		var m := node as Mine
		m.net_id = _mine_counter
		_rpc_mine.rpc(oid, m.net_id, m.global_position if m.is_inside_tree() else origin)
		m.tree_exiting.connect(func() -> void:
			if is_inside_tree():
				_rpc_mine_gone.rpc(m.net_id))


func _on_explosion_fx(position: Vector3, radius: float, color: Color, shake: float) -> void:
	_rpc_explosion.rpc(position, radius, color, shake)


func _on_match_ended(results: Array) -> void:
	_rpc_match_end.rpc(results)


func _on_peer_disconnected(peer: int) -> void:
	for kart: Kart in game.karts:
		if _owner_of(kart.net_id) == peer:
			game.give_kart_to_ai(kart)
			_client_states.erase(kart.net_id)
			_trigger_until.erase(kart.net_id)
			if kart.remote_knockback.is_connected(_on_remote_knockback):
				kart.remote_knockback.disconnect(_on_remote_knockback)
	_ready_peers.erase(peer)
	_check_all_ready()


func _owner_of(kart_id: int) -> int:
	for s in game.setup["slots"]:
		if int(s["id"]) == kart_id:
			return int(s["peer"])
	return 0


# --- Client ----------------------------------------------------------------------

func _client_tick(delta: float) -> void:
	_send_timer += delta
	var me: Kart = game.player
	if me and GameState.is_running() and _send_timer >= 1.0 / Net.client_state_rate():
		_send_timer = 0.0
		_rpc_client_state.rpc_id(1, me.net_id, me.net_get_state(), me.net_trigger)
		me.net_trigger = false
	# Machine-gun tracers for karts the host says are firing.
	for id in _remote_firing.keys():
		_remote_firing[id] = float(_remote_firing[id]) - delta
		if float(_remote_firing[id]) <= 0.0:
			_remote_firing.erase(id)
			continue
		_gun_cooldown[id] = float(_gun_cooldown.get(id, 0.0)) - delta
		if float(_gun_cooldown[id]) <= 0.0:
			_gun_cooldown[id] = WeaponDB.get_cooldown("machine_gun")
			_spawn_visual_bullet(game.get_kart(id))


func _spawn_visual_bullet(kart: Kart) -> void:
	if kart == null or not kart.alive:
		return
	var muzzle := kart.get_muzzle_transform()
	var data := WeaponDB.get_data("machine_gun")
	var spread := deg_to_rad(float(data.get("spread", 2.0)))
	var dir := (-muzzle.basis.z).rotated(Vector3.UP, randf_range(-spread, spread))
	var b := BulletProjectile.new()
	b.visual_only = true
	b.setup(kart, muzzle.origin, dir, data, maxf(kart.get_forward_speed(), 0.0))
	CombatUtil.get_projectile_root(self).add_child(b)
	CombatSfx.play("shot", muzzle.origin, self)
	kart.get_weapon_holder().weapon_fired.emit("machine_gun")


## Client: ask the host to change the loadout of our kart (applies from the next life).
func send_loadout(kart_id: int, weapon: String) -> void:
	if is_inside_tree() and not _authority:
		_rpc_loadout.rpc_id(1, kart_id, weapon)


# --- RPCs: client -> host ------------------------------------------------------------

@rpc("any_peer", "reliable")
func _rpc_loadout(kart_id: int, weapon: String) -> void:
	if not _authority or not is_inside_tree() or _owner_of(kart_id) != multiplayer.get_remote_sender_id():
		return
	var kart: Kart = game.get_kart(kart_id)
	if kart != null:
		kart.loadout = Loadout.sanitize(weapon)


@rpc("any_peer", "reliable")
func _rpc_ready() -> void:
	if _authority and is_inside_tree():
		_ready_peers[multiplayer.get_remote_sender_id()] = true
		_check_all_ready()


@rpc("any_peer", "unreliable_ordered")
func _rpc_client_state(kart_id: int, state: Array, trigger: bool) -> void:
	if not _authority or not is_inside_tree() or _owner_of(kart_id) != multiplayer.get_remote_sender_id():
		return
	var kart: Kart = game.get_kart(kart_id)
	if kart == null or not kart.remote:
		return
	_client_states[kart_id] = state
	if kart.alive:
		kart.net_apply_state(state)
	if trigger:
		_trigger_until[kart_id] = _clock + 1.0 / Net.client_state_rate() + 0.05


# --- RPCs: host -> clients ------------------------------------------------------------

@rpc("authority", "reliable")
func _rpc_begin() -> void:
	_started = true
	game.start_match()


@rpc("authority", "unreliable_ordered")
func _rpc_snapshot(snap: Array) -> void:
	if snap.size() < 3 or game == null:
		return
	GameState.apply_remote_time(float(snap[0]))
	var crates := int(snap[1])
	for i in game.crates.size():
		(game.crates[i] as WeaponCrate).net_set_available((crates >> i) & 1 == 1)
	for entry in snap[2]:
		var kart: Kart = game.get_kart(int(entry[0]))
		if kart == null:
			continue
		if kart.remote and kart.alive:
			kart.net_apply_state(entry[1])
		var h := kart.get_health()
		if kart.alive:
			h.net_set(float(entry[2]), float(entry[3]))
		var wi := int(entry[4])
		kart.get_weapon_holder().net_set(WEAPON_IDS[wi] if wi >= 0 and wi < WEAPON_IDS.size() else "", int(entry[5]))
		if bool(entry[6]) and kart.get_weapon_holder().current_weapon_id == "machine_gun":
			_remote_firing[kart.net_id] = 1.0 / Net.snapshot_rate() + 0.05


@rpc("authority", "reliable")
func _rpc_knockback(kart_id: int, impulse: Vector3) -> void:
	var kart: Kart = game.get_kart(kart_id)
	if kart and not kart.remote:
		kart.apply_knockback(impulse)


@rpc("authority", "reliable")
func _rpc_kill(victim_id: int, killer_id: int, weapon_id: String, results: Array) -> void:
	var victim: Kart = game.get_kart(victim_id)
	var killer: Kart = game.get_kart(killer_id)
	if victim:
		victim.get_health().net_kill(killer, weapon_id)
	GameState.apply_remote_scores(results)


@rpc("authority", "reliable")
func _rpc_respawn(kart_id: int, pos: Vector3, yaw: float) -> void:
	var kart: Kart = game.get_kart(kart_id)
	if kart:
		game.respawner.net_respawn(kart, Transform3D(Basis(Vector3.UP, yaw), pos))


@rpc("authority", "reliable")
func _rpc_rocket(owner_id: int, origin: Vector3, direction: Vector3) -> void:
	var r := RocketProjectile.new()
	r.visual_only = true
	r.setup(game.get_kart(owner_id), origin, direction, WeaponDB.get_data("rocket"))
	CombatUtil.get_projectile_root(self).add_child(r)
	CombatSfx.play("rocket", origin, self)
	var kart: Kart = game.get_kart(owner_id)
	if kart:
		kart.get_weapon_holder().weapon_fired.emit("rocket")


@rpc("authority", "reliable")
func _rpc_mine(owner_id: int, mine_id: int, pos: Vector3) -> void:
	var m := Mine.new()
	m.visual_only = true
	m.net_id = mine_id
	m.setup(game.get_kart(owner_id), pos, WeaponDB.get_data("mine"))
	CombatUtil.get_projectile_root(self).add_child(m)
	_mines[mine_id] = m
	CombatSfx.play("drop", pos, self)


@rpc("authority", "reliable")
func _rpc_mine_gone(mine_id: int) -> void:
	var m: Variant = _mines.get(mine_id)
	_mines.erase(mine_id)
	if is_instance_valid(m):
		(m as Mine).queue_free()


@rpc("authority", "reliable")
func _rpc_explosion(position: Vector3, radius: float, color: Color, shake: float) -> void:
	Explosion.spawn(CombatUtil.get_projectile_root(self), position, radius, 0.0, null, "", 0.0, shake, color)


@rpc("authority", "reliable")
func _rpc_match_end(results: Array) -> void:
	var my_id: int = game.player.net_id if game.player else -1
	GameState.end_match_remote(results, my_id)
