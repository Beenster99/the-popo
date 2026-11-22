extends Node
## Drives the listening room for a recorded run (movie maker): test guns,
## the shotgun by your ears, bullets past your head, a blast, and the
## player's own shots and reload. For checking levels by ear or by meter:
##   godot --path . --write-movie out.avi --fixed-fps 30 --quit-after 600 res://tools/capture/listen_room.tscn

var room: Node
var t := 0.0
var step := 0
const SCRIPT := [[1.0, KEY_5], [2.5, KEY_6], [4.0, KEY_7], [5.5, KEY_8], [8.0, KEY_9], [10.5, KEY_0]]


func _ready() -> void:
	room = load("res://prototypes/p07_sound/sound.tscn").instantiate()
	add_child(room)


func _process(delta: float) -> void:
	t += delta
	if step < SCRIPT.size() and t >= SCRIPT[step][0]:
		var e := InputEventKey.new()
		e.keycode = SCRIPT[step][1]
		e.pressed = true
		room._unhandled_input(e)
		print("%.2f  key %s" % [t, OS.get_keycode_string(SCRIPT[step][1])])
		step += 1
	var o: Officer = room.sync.my_pawn() if room and room.sync else null
	if o and t > 13.0 and t < 14.0 and o.ammo > 10:
		o.holstered = false
		o.ammo -= 1   # the sound side sees a shot go off
		print("%.2f  own shot" % t)
