extends CharacterBody3D
## Top-down mover: keyboard input, or Bot steering when autoplay is on.

@export var speed := 6.0
var autoplay := false
var targets: Callable

func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if autoplay:
		dir = Bot.steer(global_position, targets.call())
	else:
		var v := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		dir = Vector3(v.x, 0.0, v.y)
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	move_and_slide()
	if dir.length() > 0.1:
		rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), 10.0 * delta)
