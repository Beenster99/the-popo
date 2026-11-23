extends Node
## Wave 5, Phase 5.3: the first-shift tutorial walks through the job.
var t


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func test_first_shift_walks_through_the_job() -> void:
	BlockState.save_path = City.SAVE_PATH
	BlockState.delete_save()
	City.next_seed = 4242
	City.tutorial = true
	var s: City = (load("res://game/city/city.tscn") as PackedScene).instantiate()
	add_child(s)
	await _frames(30)
	var fs := s.first_shift
	t.check(fs != null and fs.current() == "walk", "the tutorial starts at the station door")
	t.check(not s.dispatch.enabled, "no calls while training")
	t.check(not FirstShift.fill(FirstShift.STEPS[0].text).contains("{"), "keys filled in: %s" % FirstShift.fill(FirstShift.STEPS[0].text))
	var o: Officer = s.sync.my_pawn()
	await _frames(2)
	o.global_position = fs._target + Vector3(0, 0.1, 0)
	await _frames(3)
	t.check(fs.current() == "draw", "walked to the light")
	o.holstered = false
	o.holster_t = 0.0
	await _frames(3)
	t.check(fs.current() == "fire", "drew the pistol")
	await _frames(2)
	for i in 3:
		o.fired.emit(o.global_position, Vector3.UP, false)
	await _frames(2)
	t.check(fs.current() == "reload", "three shots fired")
	o.reload_t = 1.0
	await _frames(2)
	o.holstered = true
	await _frames(3)
	t.check(fs.current() == "car", "reloaded and holstered")
	t.check(fs._marker.visible, "a marker over the patrol car")
	o.state = Officer.S.VEHICLE
	fs._physics_process(0.016)
	o.state = Officer.S.MOVE
	t.check(fs.current() == "siren", "in the car")
	fs._t = 30.0
	await _frames(2)
	t.check(fs.current() == "call", "siren step doesn't hold anyone up")
	await _frames(3)
	t.check(fs._call > 0 and fs._suspect != null, "dispatch sends a training call (%d)" % fs._call)
	if fs._suspect:
		o.global_position = fs._suspect.global_position + Vector3(3, 0, 0)
		await _frames(3)
		t.check(fs.current() == "arrest", "reached the call")
		fs._suspect.set_state(Suspect.S.CUFFED)
		await _frames(3)
		t.check(fs.current() == "escort", "cuffed")
		fs._suspect.set_state(Suspect.S.BOOKED)
		await _frames(3)
	t.check(fs.current() == "done" and s.dispatch.enabled, "shift's yours: calls come in now")
	t.check(not s.state.save() and not BlockState.has_save(), "the training city isn't saved")
	s.queue_free()
	await _frames(2)
