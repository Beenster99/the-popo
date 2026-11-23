class_name FirstShift
extends CanvasLayer
## Wave 5, Phase 5.3: the first shift. A walk-through of the job, one step
## at a time, from the station door to booking your first prisoner. Each
## step says what to press (from the live key bindings) and moves on when
## you've done it. Calls stay off until the shift is over; the tutorial
## city is never saved over your own.

const STEPS := [
	{"id": "walk", "title": "On your feet", "text": "Walk to the blue light. {move_forward}{move_left}{move_back}{move_right} to move, {sprint} to run. The mouse looks round."},
	{"id": "draw", "title": "Your sidearm", "text": "Draw your pistol: {holster}."},
	{"id": "fire", "title": "Aim and fire", "text": "Hold {aim} to aim, {fire} to fire. Fire three shots into the air (or at that wall)."},
	{"id": "reload", "title": "Reload", "text": "Reload: {reload}. Spare rounds are shown bottom right."},
	{"id": "holster", "title": "Put it away", "text": "Holster it again: {holster}. People get nervous round a drawn gun."},
	{"id": "car", "title": "Patrol car", "text": "Get in one of the patrol cars out front: walk up and press {interact}."},
	{"id": "siren", "title": "Lights and siren", "text": "Lights and siren: {torch} in the car (press again to change the siren, again for off). {horn} is the horn. Traffic pulls over for the siren."},
	{"id": "call", "title": "Your first call", "text": "Dispatch has a job for you. Drive to the marker (the radio says where)."},
	{"id": "arrest", "title": "Make the arrest", "text": "Shout {shout} (\"Police! Get down!\"). When they give up, hold {interact} next to them to cuff them. If they run: chase, {punch} or {kick}."},
	{"id": "escort", "title": "Bring them in", "text": "They follow you while cuffed. Walk them to a patrol car and press {interact} to put them in."},
	{"id": "book", "title": "Booking", "text": "Drive to the custody bay at the side of the station (the marker) and stop there. They're booked when you stop."},
	{"id": "done", "title": "Shift's yours", "text": "That's the job. Calls will come in on the radio now. Spend the station's pay at the armoury counter inside the door (F)."},
]

var city: City
var step := 0
var _shots := 0
var _t := 0.0
var _marker: MeshInstance3D
var _target := Vector3.INF
var _call := -1
var _suspect: Suspect
var _title: Label
var _text: Label
var _count: Label
var _done_t := -1.0


func _ready() -> void:
	layer = 40
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 0)
	panel.position = Vector2(0, 70)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	center.offset_top = 60
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var head := HBoxContainer.new()
	_title = UiTheme.title("", 26, UiTheme.ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_count = UiTheme.title("", 16, UiTheme.DIM)
	head.add_child(_count)
	box.add_child(head)
	_text = UiTheme.title("", 19)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size.x = 720
	box.add_child(_text)
	_marker = _make_marker()
	if city:
		city.add_child(_marker)
	_show()


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()


func current() -> String:
	return STEPS[mini(step, STEPS.size() - 1)].id


## The step's text with the keys filled in from the live bindings.
static func fill(text: String) -> String:
	var out := text
	for pair in Controls.REBINDABLE:
		var a: String = pair[0]
		if out.contains("{%s}" % a):
			var ev := Controls.pc_event(a)
			out = out.replace("{%s}" % a, "[%s]" % (Controls.describe(ev) if ev else "?"))
	return out


func _show() -> void:
	var s: Dictionary = STEPS[mini(step, STEPS.size() - 1)]
	_title.text = String(s.title).to_upper()
	_text.text = fill(s.text)
	_count.text = "FIRST SHIFT  %d / %d" % [mini(step + 1, STEPS.size()), STEPS.size()]


func _officer() -> Officer:
	return city.sync.my_pawn() as Officer if city and city.sync else null


func advance() -> void:
	step += 1
	_t = 0.0
	_target = Vector3.INF
	if city and city.dispatch:
		city.dispatch.say("TRAINING: %s" % STEPS[mini(step, STEPS.size() - 1)].title)
	_show()
	if current() == "done":
		_done_t = 12.0
		if city and city.dispatch:
			city.dispatch.enabled = true


func _physics_process(delta: float) -> void:
	var o := _officer()
	if o == null or city == null:
		return
	_t += delta
	if _done_t >= 0.0:
		_done_t -= delta
		if _done_t <= 0.0:
			queue_free()
		return
	match current():
		"walk":
			if _target == Vector3.INF:
				var st: Dictionary = city.gen.station()
				_target = o.global_position - (st.v as Vector3) * 9.0
			if _flat(o.global_position, _target) < 2.0:
				advance()
		"draw":
			if not o.holstered and o.holster_t <= 0.0:
				advance()
		"fire":
			if not o.fired.is_connected(_on_fired):
				_shots = 0
				o.fired.connect(_on_fired)
			if _shots >= 3:
				o.fired.disconnect(_on_fired)
				advance()
		"reload":
			if o.reload_t > 0.0 or (_t > 8.0 and o.ammo >= o.mag_size()):
				advance()
		"holster":
			if o.holstered:
				advance()
		"car":
			var pc: Node3D = _nearest_car(o)
			_target = pc.global_position if pc else Vector3.INF
			if o.state == Officer.S.VEHICLE:
				advance()
		"siren":
			if o.car and o.car.siren > 0:
				advance()
			elif _t > 20.0:
				advance()   # don't hold them up over it
		"call":
			if _call < 0:
				_start_call()
			if _suspect and is_instance_valid(_suspect):
				_target = _suspect.global_position
				if _flat(o.global_position, _target) < 14.0:
					advance()
		"arrest":
			if _suspect == null or not is_instance_valid(_suspect):
				_skip_to("done")
				return
			_target = _suspect.global_position
			if _suspect.state in [Suspect.S.CUFFED, Suspect.S.IN_CAR]:
				advance()
			elif _suspect.state in [Suspect.S.DOWN, Suspect.S.BOOKED]:
				_skip_to("done")
		"escort":
			if _suspect == null or not is_instance_valid(_suspect) or _suspect.state in [Suspect.S.DOWN, Suspect.S.BOOKED]:
				_skip_to("done")
				return
			var pc: Node3D = _nearest_car(o)
			_target = pc.global_position if pc else Vector3.INF
			if _suspect.state == Suspect.S.IN_CAR:
				advance()
		"book":
			_target = city.dispatch.bay_position()
			if _suspect == null or not is_instance_valid(_suspect) or _suspect.state in [Suspect.S.BOOKED, Suspect.S.DOWN]:
				advance()
	_place_marker()


func _skip_to(id: String) -> void:
	while current() != id and step < STEPS.size() - 1:
		step += 1
	step -= 1
	advance()


func _on_fired(_origin: Vector3, _dir: Vector3, alt: bool) -> void:
	if not alt:
		_shots += 1


func _start_call() -> void:
	var d := city.dispatch
	for i in 6:
		_call = d.start_call(Dispatcher.Kind.SHOPLIFT)
		if _call > 0:
			break
	if _call <= 0:
		_call = 0
		_skip_to("done")
		return
	var c: Dictionary = d.calls[_call]
	if not (c.suspects as Array).is_empty():
		_suspect = d.suspects.get(c.suspects[0])
	if _suspect:
		_suspect.fighter = false


func _nearest_car(o: Officer) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for pc in city.police_cars:
		var d := (pc as Node3D).global_position.distance_to(o.global_position)
		if d < bd:
			bd = d
			best = pc
	return best


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _place_marker() -> void:
	if not is_instance_valid(_marker):
		return
	_marker.visible = _target != Vector3.INF
	if _marker.visible:
		_marker.global_position = Vector3(_target.x, _target.y + 3.0, _target.z)


func _make_marker() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = "TrainingMarker"
	var c := CylinderMesh.new()
	c.top_radius = 0.6
	c.bottom_radius = 0.6
	c.height = 6.0
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.3, 0.85, 1.0, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.visible = false
	return mi
