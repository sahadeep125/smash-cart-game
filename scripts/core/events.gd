## Global signal bus (autoload "Events").
## Modules talk to each other through these signals instead of direct references.
extends Node

# --- Combat ---------------------------------------------------------------
## A kart lost all its health. killer may be null (e.g. self-damage / hazard).
signal kart_killed(victim: Node, killer: Node, weapon_id: String)
## A kart came back after its respawn delay.
signal kart_respawned(kart: Node)
## A kart picked up a weapon from a crate.
signal weapon_picked_up(kart: Node, weapon_id: String)
## Visual feedback: something exploded at a world position.
signal explosion_happened(position: Vector3, radius: float)
## Ask the follow camera to shake (0..1 strength).
signal camera_shake_requested(strength: float)

# --- Match flow -----------------------------------------------------------
signal match_started()
## Emitted every time the visible second changes.
signal match_time_changed(seconds_left: float)
## results: Array of Dictionary {name, kills, deaths, is_player}, sorted best first.
signal match_ended(results: Array)
signal score_changed(kart_name: String, kills: int, deaths: int)
