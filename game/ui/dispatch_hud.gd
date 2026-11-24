class_name DispatchHud
extends CanvasLayer
## Phase 1.4 HUD (no crime meter since v0.2.11): the open calls (top
## left), radio chatter (top centre for a few seconds), and arrows at
## the screen edge pointing to each call and, while anyone has a prisoner,
## to the custody bay.

var dispatcher: Dispatcher
var armoury: Armoury
var pawn_getter: Callable   # () -> Officer, or null

var _calls: Label
var _radio: Label
var _radio_t := 0.0
var _arrows: Control


func _ready() -> void:
	layer = 6
	var top := VBoxContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 14
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.add_theme_constant_override("separation", 4)
	add_child(top)
	_radio = _label(17, Color(0.75, 0.95, 1.0))
	_radio.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_radio.custom_minimum_size.x = 900
	_radio.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	top.add_child(_radio)
	_calls = _label(15, Color(1, 0.96, 0.9))
	_calls.position = Vector2(20, 16)
	add_child(_calls)
	_arrows = Control.new()
	_arrows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_arrows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrows.draw.connect(_draw_arrows)
	add_child(_arrows)
	if dispatcher:
		dispatcher.radio.connect(_on_radio)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 5)
	return l


func _on_radio(text: String) -> void:
	_radio.text = text
	_radio_t = 7.0
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	if o and o.is_inside_tree():
		Sfx.play(o.get_parent(), "ping", o.global_position + Vector3(0, 1.6, 0), -10.0, 400.0, 0.0)


func _process(delta: float) -> void:
	if dispatcher == null:
		return
	_radio_t -= delta
	_radio.visible = _radio_t > 0.0
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	var lines := PackedStringArray()
	if dispatcher.missions and dispatcher.city:
		lines.append("%s     £%s" % [dispatcher.missions.clock_text(), _money(dispatcher.pay)])
	for call in dispatcher.active_calls():
		var d := ""
		if o:
			d = "   %d m" % int(Vector2(call.marker.x - o.global_position.x, call.marker.z - o.global_position.z).length())
		lines.append("%s%s" % [Dispatcher.KIND_NAMES[call.kind].to_upper(), d])
	if _has_prisoner():
		lines.append("PRISONER: take them to the custody bay")
	# Phase 3.5/3.6: the armoury counter and the range mark.
	var use := Controls.key_name("interact")
	if o and armoury and not ArmouryScreen.is_open() and not PauseMenu.is_open():
		var rng := armoury.get_parent().get_node_or_null("Range") as FiringRange
		if armoury.near_counter(o.global_position):
			lines.append("%s: open the armoury" % use)
			if Input.is_action_just_pressed("interact") and not PlayerInput.blocked:
				ArmouryScreen.open(get_tree(), armoury, pawn_getter)
		elif rng and rng.near_start(o.global_position) and not rng.running:
			lines.append("%s: start a range run" % use)
			if Input.is_action_just_pressed("interact") and not PlayerInput.blocked:
				rng.ask_start()
	# v0.10.0: the tower lifts.
	if o and Lifts.current and not LiftPanel.is_open() and not PauseMenu.is_open() and not (o is Officer and (o as Officer).in_car()):
		var lp := Lifts.current.prompt_for(o.global_position)
		if lp != "":
			lines.append(lp)
			if Input.is_action_just_pressed("interact") and not PlayerInput.blocked:
				Lifts.current.use(o.global_position, get_tree())
	# Phase 3.7: undercover, and how close the nearest crook is to making you.
	if o is Officer and (o as Officer).plain:
		var worst := 0.0
		for sp in dispatcher.suspects.values():
			var su := sp as Suspect
			if su.is_free() and not su.civilian and su.part == "" and su.global_position.distance_to(o.global_position) < 15.0:
				worst = maxf(worst, su.suspicion)
		if not (o as Officer).undercover():
			lines.append("PLAIN CLOTHES (they can see you're police)")
		elif worst >= Suspect.MADE:
			lines.append("UNDERCOVER: you've been made!")
		else:
			var bars := int(round(worst * 10.0))
			lines.append("UNDERCOVER  suspicion [%s%s]" % ["|".repeat(bars), ".".repeat(10 - bars)])
	if o is Officer and PlayerInput.alt_tool and (o as Officer).charges > 0:
		lines.append("%s: %d left (1 for the pistol)" % [Armoury.GEAR_NAMES[Armoury.gear_of((o as Officer).kit)].to_upper(), (o as Officer).charges])
	_calls.text = "\n".join(lines)
	_arrows.queue_redraw()


func _has_prisoner() -> bool:
	for s in dispatcher.suspects.values():
		if (s as Suspect).state in [Suspect.S.CUFFED, Suspect.S.IN_CAR]:
			return true
	return false


## Off-screen targets get an arrow at the edge with the distance.
func _draw_arrows() -> void:
	var cam := _arrows.get_viewport().get_camera_3d()
	if cam == null or dispatcher == null:
		return
	var targets := []
	for call in dispatcher.active_calls():
		targets.append([call.marker, Color("ff5050") if call.kind not in [Dispatcher.Kind.TRAFFIC, Dispatcher.Kind.THEFT, Dispatcher.Kind.PURSUIT] else Color("ffb030")])
	if _has_prisoner():
		targets.append([dispatcher.bay_position(), Color("4a8cff")])
	# A prisoner doing a runner in cuffs.
	for s in dispatcher.suspects.values():
		if (s as Suspect).state == Suspect.S.CUFF_RUN:
			targets.append([(s as Suspect).global_position, Color("ff8030")])
	var rect := _arrows.get_rect()
	var centre := rect.size * 0.5
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	var font := ThemeDB.fallback_font
	for t in targets:
		var p: Vector3 = t[0]
		var sp := cam.unproject_position(p + Vector3(0, 1.0, 0))
		var inside := Rect2(Vector2.ZERO, rect.size).grow(-40.0).has_point(sp) and not cam.is_position_behind(p)
		if inside:
			continue
		var dir := (sp - centre).normalized()
		if dir == Vector2.ZERO:
			continue
		var edge := centre + dir * minf(absf((centre.x - 50.0) / dir.x) if dir.x != 0.0 else INF, absf((centre.y - 50.0) / dir.y) if dir.y != 0.0 else INF)
		var col: Color = t[1]
		var side := Vector2(-dir.y, dir.x)
		_arrows.draw_colored_polygon(PackedVector2Array([edge + dir * 18.0, edge - dir * 6.0 + side * 12.0, edge - dir * 6.0 - side * 12.0]), col)
		if o:
			var dist := int(Vector2(p.x - o.global_position.x, p.z - o.global_position.z).length())
			_arrows.draw_string_outline(font, edge - dir * 34.0 + Vector2(-16, 6), "%dm" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, 4, Color(0, 0, 0, 0.9))
			_arrows.draw_string(font, edge - dir * 34.0 + Vector2(-16, 6), "%dm" % dist, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, col)


static func _money(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
