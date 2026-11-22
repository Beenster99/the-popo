extends Node
## Two-process driving latency test (see run_car_test.sh). For each driving
## authority mode the client floors the throttle and we time how long until
## the client sees its own car move 3 cm. Then the client drives into the
## barrier line and both sides report the dent depth on the client's car.

var role: String
var phase := "connect"
var t := 0.0
var cars: CarSync
var mode_i := 0
var start_pos := Vector3.ZERO
var press_t := 0.0
var drift := Vector3.ZERO
var results := []


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	role = a[0]
	# Both processes add fake delay, so each takes half the requested round trip.
	Net.sim_latency_ms = float(a[2]) * 0.5
	Net.sim_loss = float(a[3])
	if role == "host":
		Net.host(int(a[1]))
	else:
		Net.join("127.0.0.1", int(a[1]))


func _car() -> Car:
	return cars.cars[1]


func _physics_process(delta: float) -> void:
	t += delta
	if t > 40.0:
		print("TIMEOUT %s mode %d speed %.3f" % [phase, mode_i, _car().linear_velocity.length() if cars else -1.0])
		get_tree().quit(2)
	match phase:
		"connect":
			if role == "host" and Net.slots.size() == 2:
				Net.load_scene_for_all("res://prototypes/p04_car/car.tscn")
				phase = "scene"
			elif role == "client" and get_tree().current_scene and get_tree().current_scene.get("cars") != null:
				phase = "scene"
		"scene":
			var s := get_tree().current_scene
			if s and s.get("cars") != null:
				cars = s.cars
				Input.action_release("move_forward")
				phase = "mode"
				t = 0.0
		"mode":
			if t > 1.5:
				if role == "host":
					cars.set_mode(CarSync.Mode.HOST if mode_i == 0 else CarSync.Mode.DRIVER)
				phase = "arm"
				t = 0.0
		"arm":
			# Wait for the car to stop. A car that is still creeping after 5 s
			# (the proxy on a slow machine can jitter) is armed anyway, and its
			# creep is subtracted from the measurement below.
			# The client also waits until the host's mode change has reached it.
			var want := CarSync.Mode.HOST if mode_i == 0 else CarSync.Mode.DRIVER
			if cars.mode != want:
				t = 0.0  # give the car time to settle after the hand-over
				return
			var speed := _car().linear_velocity.length()
			if (t > 1.5 and speed < 0.05) or (t > 5.0 and speed < 0.6):
				start_pos = _car().global_position
				drift = _car().linear_velocity if speed >= 0.05 else Vector3.ZERO
				press_t = t
				if role == "client":
					Input.action_press("move_forward")
				phase = "measure"
		"measure":
			var moved := _car().global_position - start_pos - drift * (t - press_t)
			if role == "client" and moved.dot(_car().global_transform.basis.z) > 0.03:
				results.append(["host" if mode_i == 0 else "driver", (t - press_t) * 1000.0])
				Input.action_release("move_forward")
				phase = "stop"
				t = 0.0
			elif role == "host" and t > 3.0:
				phase = "stop"
				t = 0.0
		"stop":
			if t > 3.0:
				mode_i += 1
				if mode_i >= 2:
					if role == "client":
						for r in results:
							print("LATENCY %s %.0f" % r)
					phase = "done"
				else:
					phase = "mode"
				t = 0.0
		"done":
			if t > 1.0:
				get_tree().quit(0)
