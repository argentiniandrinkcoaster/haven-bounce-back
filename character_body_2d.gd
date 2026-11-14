extends CharacterBody2D


const JUMP_VELOCITY = -400.0

const ENGINE_ACCEL = 600.0   # px/s² at 100% throttle
const DRAG = 0.0024          # air drag, sets top speed (~500 px/s at full throttle)
const ROLL_RESIST = 40.0     # px/s² constant friction, so the car coasts to a stop
const BRAKE_FORCE = 900.0    # px/s² when you press against your motion
const THROTTLE_RATE = 0.6    # how fast the throttle moves per second (0.6 = 1.7s from 0 to 100%)

var throttle := 0.0          # 0.0 to 1.0
var drive_dir := 1.0         # which way the engine pushes


func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	# Throttle is a lever: hold up/down to raise or lower it, it stays where you leave it.
	throttle += Input.get_axis("throttle_down", "throttle_up") * THROTTLE_RATE * delta
	throttle = clampf(throttle, 0.0, 1.0)
	print("throttle: ", int(throttle * 100), "%  vel: ", int(velocity.x))

	# Left/right picks drive direction, or brakes if you press against your motion.
	var direction := Input.get_axis("left", "right")
	var braking := direction != 0.0 and absf(velocity.x) > 1.0 and signf(direction) != signf(velocity.x)

	if braking:
		velocity.x = move_toward(velocity.x, 0.0, BRAKE_FORCE * delta)
	else:
		if direction != 0.0:
			drive_dir = signf(direction)
		var accel := drive_dir * throttle * ENGINE_ACCEL
		accel -= DRAG * velocity.x * absf(velocity.x)   # drag grows with speed squared
		velocity.x += accel * delta
		velocity.x = move_toward(velocity.x, 0.0, ROLL_RESIST * delta)

	move_and_slide()
