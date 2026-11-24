class_name DispatchHud
extends CanvasLayer
## Phase 1.4 HUD (no crime meter since v0.2.11): the open calls (top
## left, with distance and street), radio chatter (top centre for a few
## seconds), and markers for each call and, while anyone has a prisoner,
## the custody bay: a pin over it on screen, an arrow at the edge off it.

var dispatcher: Dispatcher
var armoury: Armoury
var pawn_getter: Callable   # () -> Officer, or null

var _calls: Label
## 2026-11-24 (beenster: "we need a little more information as well as the
## radio call"): a job card under the clock for each open job: what it is,
## the pay, the street, how far and which way, the full dispatch text, how
## many crooks (armed, shotguns, dealt with) and what to do.
var _card: RichTextLabel
var _card_box: PanelContainer
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
	var left := VBoxContainer.new()
	left.position = Vector2(20, 16)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	_calls = _label(15, Color(1, 0.96, 0.9))
	left.add_child(_calls)
	_card_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.72)
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	_card_box.add_theme_stylebox_override("panel", sb)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.visible = false
	left.add_child(_card_box)
	_card = RichTextLabel.new()
	_card.bbcode_enabled = true
	_card.fit_content = true
	_card.scroll_active = false
	_card.custom_minimum_size.x = 440
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_theme_font_size_override("normal_font_size", 14)
	_card.add_theme_font_size_override("bold_font_size", 17)
	_card.add_theme_font_size_override("italics_font_size", 14)
	_card_box.add_child(_card)
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
	var cards := PackedStringArray()
	for call in dispatcher.active_calls():
		cards.append(card_text(call, MiniMap._pos_of(o) if o else Vector3.INF))
	var bb := "\n\n".join(cards)
	if _card.text != bb:
		_card.text = bb
	_card_box.visible = not cards.is_empty()
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


## What to do on each kind of job, in a line.
const TODO := {
	Dispatcher.Kind.ROBBERY: "Get inside, make them give up or take them down. Cuff and bring them in.",
	Dispatcher.Kind.ARMED: "Approach from cover. Order them to drop it, or take them down.",
	Dispatcher.Kind.TRAFFIC: "Get behind it with lights on (siren key) and pull it over, then talk to the driver.",
	Dispatcher.Kind.GANG: "They're dug in. Use cover, flank them, smoke or flash them. Don't rush.",
	Dispatcher.Kind.THEFT: "Get there before they drive off. Cuff the thief at the car.",
	Dispatcher.Kind.PURSUIT: "Chase it down. Box it in or ram it until it stops.",
	Dispatcher.Kind.MUGGING: "Talk to the victim for a description, then find the mugger.",
	Dispatcher.Kind.SHOPLIFT: "The shopkeeper has the door. Go in and cuff the shoplifter.",
	Dispatcher.Kind.FIGHT: "Split them up: shout orders, punch if you must. Cuff them both.",
	Dispatcher.Kind.DOMESTIC: "Go in carefully, calm it down, and cuff whoever's kicking off.",
	Dispatcher.Kind.DEAL: "One's armed. Close in quietly and take them both.",
	Dispatcher.Kind.VANDAL: "Catch them before they smash the whole street.",
	Dispatcher.Kind.DRUNK: "He won't run. Talk him down or wrestle him, then cuff him.",
	Dispatcher.Kind.BURGLARY: "They're still inside. Clear the building room by room.",
	Dispatcher.Kind.RAID: "Breach the door, then clear every floor. Expect guns.",
	Dispatcher.Kind.HOSTAGE: "Get the hostages out alive. Flashbangs help; watch your fire.",
	Dispatcher.Kind.SEARCH: "Search every floor until you find him.",
	Dispatcher.Kind.GANGWAR: "Two crews fighting. Let them thin out, or go in hard.",
	Dispatcher.Kind.BANK: "Box the getaway car in first, then go in for the robbers.",
	Dispatcher.Kind.BAITCAR: "Stay out of sight in plain clothes. Let him take the car.",
	Dispatcher.Kind.BUY: "Plain clothes only. Walk up, make the buy, then take him.",
	Dispatcher.Kind.CRASH: "Secure the scene and sort out the drivers.",
	Dispatcher.Kind.FIRE: "Keep people back until the brigade arrives.",
	Dispatcher.Kind.ALARM: "Have a look round. Stay a while and it's dealt with.",
}
const COMPASS := ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]


## The job card text (BBCode) for one open call, seen from `from` (INF: no
## officer, so no distance).
func card_text(call: Dictionary, from: Vector3) -> String:
	var col := MiniMap.job_colour(call.kind).to_html(false)
	var lines := PackedStringArray()
	var pay: int = Dispatcher.PAY_JOB.get(call.kind, 0)
	lines.append("[b][color=#%s]%s[/color][/b]   [color=#9fe39f]£%s[/color]" % [col, Dispatcher.KIND_NAMES[call.kind].to_upper(), _money(pay)])
	# The street, unless the dispatch text already names where it is (the
	# marker can sit on the corner street of the building it's in).
	var where := CityGenerator.street_at(call.marker)
	var text := String(call.get("text", ""))
	var first := where.get_slice(" near ", 0)
	if text.contains(" on ") and not text.contains(first):
		where = ""
	elif text.contains(first):
		where = ""
	if from != Vector3.INF:
		var v := Vector2(call.marker.x - from.x, call.marker.z - from.z)
		var dist := int(v.length())
		var sep := "  ·  " if where != "" else ""
		if dist < 25:
			where += sep + "[b]you're here[/b]"
		else:
			# North is -Z (up on the mini map).
			var a := fposmod(atan2(v.x, -v.y), TAU)
			where += sep + "%d m %s" % [dist, COMPASS[int(round(a / (TAU / 8.0))) % 8]]
	if where != "":
		lines.append(where)
	if String(call.get("text", "")) != "":
		lines.append("[color=#c9d6e3]%s[/color]" % String(call.text))
	var br := dispatcher.brief(call)
	if br.total > 0:
		var who := "%d suspect%s" % [br.total, "" if br.total == 1 else "s"]
		var left: int = br.total - br.done
		if br.armed > 0:
			var guns := "%d armed" % br.armed
			if br.shotguns > 0:
				guns += " (%d shotgun%s)" % [br.shotguns, "" if br.shotguns == 1 else "s"]
			who += ", [color=#ff7a6a]%s[/color]" % guns
		if br.done > 0:
			who += "  ·  %d dealt with, %d to go" % [br.done, left]
		lines.append(who)
	if TODO.has(call.kind):
		lines.append("[i]%s[/i]" % TODO[call.kind])
	return "\n".join(lines)


func _has_prisoner() -> bool:
	for s in dispatcher.suspects.values():
		if (s as Suspect).state in [Suspect.S.CUFFED, Suspect.S.IN_CAR]:
			return true
	return false


## v0.15.0: every job, the custody bay (while anyone has a prisoner) and a
## cuffed runner get a marker. On screen: a pin over the spot with what it
## is and how far, seen through walls. Off screen: a big arrow at the screen
## edge that points the way to go round you (from the camera's heading, so it
## doesn't flip when the spot is behind you), with the distance.
func _draw_arrows() -> void:
	var cam := _arrows.get_viewport().get_camera_3d()
	if cam == null or dispatcher == null or not Settings.values.get("job_markers", true):
		return
	var targets := []   # [position, colour, label]
	for call in dispatcher.active_calls():
		targets.append([call.marker, MiniMap.job_colour(call.kind), Dispatcher.KIND_NAMES[call.kind].to_upper()])
	if _has_prisoner():
		targets.append([dispatcher.bay_position(), Color("4a8cff"), "CUSTODY BAY"])
	for s in dispatcher.suspects.values():
		if (s as Suspect).state == Suspect.S.CUFF_RUN:
			targets.append([(s as Suspect).global_position, Color("ff8030"), "RUNNER"])
	if targets.is_empty():
		return
	var rect := _arrows.get_rect()
	var centre := rect.size * 0.5
	var o: Node3D = pawn_getter.call() if pawn_getter.is_valid() else null
	var font := ThemeDB.fallback_font
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
	var fwd := -cam.global_transform.basis.z
	var right := cam.global_transform.basis.x
	var f2 := Vector2(fwd.x, fwd.z).normalized()
	var mm := get_parent().get_node_or_null("MiniMap") as MiniMap
	var keep_out := mm.screen_rect() if mm else Rect2()
	var r2 := Vector2(right.x, right.z).normalized()
	for t in targets:
		var p: Vector3 = t[0]
		var col: Color = t[1]
		var label: String = t[2]
		var from: Vector3 = MiniMap._pos_of(o) if o else cam.global_position
		var dist := int(Vector2(p.x - from.x, p.z - from.z).length())
		var head := p + Vector3(0, 2.4, 0)
		var sp := cam.unproject_position(head)
		var on_screen := not cam.is_position_behind(head) and Rect2(Vector2.ZERO, rect.size).grow(-60.0).has_point(sp)
		if on_screen:
			# A pin over the spot: a ring, a point down and the words over it.
			var r := 13.0 + 3.0 * pulse
			_arrows.draw_circle(sp, r + 4.0, Color(0, 0, 0, 0.55))
			_arrows.draw_circle(sp, r, col)
			_arrows.draw_circle(sp, r * 0.45, Color.WHITE)
			_arrows.draw_colored_polygon(PackedVector2Array([sp + Vector2(-8, r - 2), sp + Vector2(8, r - 2), sp + Vector2(0, r + 14)]), col)
			_text(font, sp + Vector2(0, -r - 22), label, 15, col)
			_text(font, sp + Vector2(0, -r - 6), "%d m" % dist, 15, Color.WHITE)
			continue
		# Off screen: which way round you, from the camera's heading.
		var to := Vector2(p.x - cam.global_position.x, p.z - cam.global_position.z)
		var dir := Vector2(to.dot(r2), -to.dot(f2)).normalized()
		if dir == Vector2.ZERO:
			dir = Vector2(0, 1)
		var hx := centre.x - 70.0
		var hy := centre.y - 70.0
		var edge := centre + dir * minf(hx / absf(dir.x) if absf(dir.x) > 0.0001 else INF, hy / absf(dir.y) if absf(dir.y) > 0.0001 else INF)
		# Keep clear of the mini map in the bottom left corner.
		if keep_out.size != Vector2.ZERO and keep_out.grow(30.0).has_point(edge):
			edge.y = keep_out.position.y - 40.0
		var side := Vector2(-dir.y, dir.x)
		var sc := 1.0 + 0.15 * pulse
		var tri := PackedVector2Array([edge + dir * 30.0 * sc, edge - dir * 10.0 + side * 22.0 * sc, edge - dir * 2.0, edge - dir * 10.0 - side * 22.0 * sc])
		_arrows.draw_colored_polygon(tri, Color(0, 0, 0, 0.6))
		var inner := PackedVector2Array()
		for q in tri:
			inner.append(edge + (q - edge) * 0.8)
		_arrows.draw_colored_polygon(inner, col)
		var tp := edge - dir * (44.0 + 38.0 * absf(dir.x))
		_text(font, tp + Vector2(0, -2), label, 14, col)
		_text(font, tp + Vector2(0, 16), "%d m" % dist, 16, Color.WHITE)


func _text(font: Font, centre_at: Vector2, text: String, size: int, col: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := centre_at - Vector2(w * 0.5, 0)
	_arrows.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 5, Color(0, 0, 0, 0.9))
	_arrows.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


static func _money(n: int) -> String:
	var s := str(n)
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out
