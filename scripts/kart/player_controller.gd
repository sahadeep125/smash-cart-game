## Reads the input actions (keyboard or touch, both drive the same actions)
## and writes them onto the parent Kart.
class_name PlayerController
extends Node

var kart: Kart


func _ready() -> void:
	kart = get_parent() as Kart
	# Run before the kart so inputs apply on the same physics frame.
	process_physics_priority = -1


func _physics_process(_delta: float) -> void:
	if kart == null:
		return
	if not kart.alive or not kart.controls_enabled:
		kart.throttle = 0.0
		kart.steer = 0.0
		kart.drift_held = false
		return
	kart.throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	kart.steer = Input.get_axis("steer_left", "steer_right")
	kart.drift_held = Input.is_action_pressed("drift")
	if Input.is_action_pressed("fire"):
		kart.request_fire()
