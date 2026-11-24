class_name AmmoHud
extends CanvasLayer
## Bottom-right weapon panel: the gun in hand, rounds in the magazine, spare
## rounds on the belt, and a bar while reloading. Reads the local officer.

var pawn_getter: Callable   # () -> Officer, or null
var _panel: PanelContainer
var _name: Label
var _mag: Label
var _spare: Label
var _state: Label
var _bar: ProgressBar
var _health: Label
var _hint: Label
var _nades: Label


func _ready() -> void:
	layer = 5
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	sb.border_color = Color(0.95, 0.85, 0.25, 0.8)
	sb.border_width_left = 3
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_right = -24
	_panel.offset_bottom = -24
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_panel.add_child(v)
	_name = _label(15, Color(0.95, 0.85, 0.25))
	v.add_child(_name)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	_mag = _label(40, Color.WHITE)
	row.add_child(_mag)
	_spare = _label(22, Color(0.75, 0.78, 0.85))
	_spare.size_flags_vertical = Control.SIZE_SHRINK_END
	row.add_child(_spare)
	_state = _label(13, Color(1.0, 0.55, 0.4))
	v.add_child(_state)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(170, 6)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	v.add_child(_bar)
	_health = _label(14, Color(1.0, 0.45, 0.4))
	v.add_child(_health)
	_nades = _label(14, Color(0.8, 0.85, 0.9))
	v.add_child(_nades)
	# Prompts for what interact does here, bottom centre.
	_hint = _label(18, Color(1, 0.96, 0.85))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.5
	_hint.anchor_right = 0.5
	_hint.anchor_top = 1.0
	_hint.anchor_bottom = 1.0
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hint.offset_bottom = -30
	add_child(_hint)


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _process(_delta: float) -> void:
	var o: Officer = pawn_getter.call() if pawn_getter.is_valid() else null
	_panel.visible = o != null
	if o == null:
		return
	# Phase 1.5: a picked-up gun shows its own rounds, with no spare.
	var picked := o.gun != EnemyGuns.NONE
	var rounds: int = o.gun_ammo if picked else o.ammo
	_name.text = o.weapon_name().to_upper()
	_mag.text = str(rounds)
	_mag.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if rounds <= 3 else Color.WHITE)
	_spare.text = ("  no spare   %s drop" % Controls.key_name("holster")) if picked else ("  / %d" % o.reserve)
	var s := ""
	if o.is_reloading():
		s = "RELOADING"
	elif o.holstered:
		s = "HOLSTERED"
	elif picked:
		s = "" if rounds > 0 else "EMPTY"
	elif o.ammo == 0 and o.reserve == 0:
		s = "OUT OF AMMO"
	elif o.ammo == 0:
		s = "EMPTY - RELOAD"
	if PlayerInput.walk_on:
		s += ("   " if s != "" else "") + "WALK MODE"
	_state.text = s
	_state.visible = s != ""
	_bar.visible = o.is_reloading() or o.treat_t > 0.0 or o._boot_t > 0.0 or o.cuff_t > 0.0
	if o.is_reloading():
		_bar.value = 1.0 - o.reload_t / o.reload_time()
	elif o.cuff_t > 0.0:
		_bar.value = o.cuff_t / Officer.CUFF_TIME
	elif o._boot_t > 0.0:
		_bar.value = o._boot_t / Officer.BOOT_TIME
	elif o.treat_t > 0.0:
		_bar.value = o.treat_t / o.treat_time()
	var wounds := Officer.injury_names(o.injuries)
	_health.text = "%s\nFIRST AID %d" % ["  ".join(wounds), o.pouch] if not wounds.is_empty() else "FIRST AID %d" % o.pouch
	_health.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if not wounds.is_empty() else Color(0.7, 0.75, 0.8))
	_hint.text = _prompt(o)
	_nades.text = _nade_line(o)
	_nades.visible = _nades.text != ""


## The grenades carried, the picked one in brackets, and the keys.
func _nade_line(o: Officer) -> String:
	var any := false
	for k in 3:
		if Armoury.owns(Armoury.NADE_ITEMS[k]):
			any = true
	if not any:
		return ""
	var parts: PackedStringArray = []
	for k in 3:
		if not Armoury.owns(Armoury.NADE_ITEMS[k]):
			continue
		var t := "%s %d" % [Grenades.SHORT[k], Grenades.count(o.nades, k)]
		parts.append("[%s]" % t if k == PlayerInput.nade_kind else t)
	var keys := "%s throw  %s pick" % [Controls.key_name("throw"), Controls.key_name("grenade_next")]
	return "%s\n%s" % ["  ".join(parts), keys]


## "WASD" (or whatever movement keys are set), "Left stick" on a controller.
static func _move_keys() -> String:
	if PlayerInput.using_pad:
		return "Left stick"
	var k := ""
	for a in ["move_forward", "move_left", "move_back", "move_right"]:
		k += Controls.key_name(a)
	return k


## One line on what the use key does here.
func _prompt(o: Officer) -> String:
	var use := Controls.key_name("interact")
	if o.in_car():
		var parts: PackedStringArray = ["%s get out" % use, "%s change seat" % Controls.key_name("stance")]
		parts.insert(0, ("DRIVING   %s drive   %s handbrake" % [_move_keys(), Controls.key_name("handbrake")]) if o.seat == 0 else "PASSENGER (%s to move to the wheel)" % Controls.key_name("stance"))
		if o.seat == 0:
			parts.append("%s lights / siren" % Controls.key_name("torch"))
			parts.append("%s horn" % Controls.key_name("horn"))
		else:
			parts.append("%s lean out and aim" % Controls.key_name("aim"))
		return "   ".join(parts)
	if o.state == Officer.S.DOWNED:
		var r := Controls.key_name("reload")
		var up := maxf(Officer.SELF_REVIVE - o.state_t, 0.0)
		var w := o.respawn_wait()
		var first := ("%s respawn in %d" % [r, ceili(w)]) if w > 0.0 else ("%s respawn back at the start" % r)
		return "DOWN   %s   or a teammate holds %s on you   (you get up here in %d s)" % [first, use, ceili(up)]
	if o.state == Officer.S.ROPE:
		return "ON THE ROPE   %s climb   %s slide   %s drop fast   %s swing in through a window   %s let go" % [
			"Stick up" if PlayerInput.using_pad else Controls.key_name("move_forward"),
			"Stick down" if PlayerInput.using_pad else Controls.key_name("move_back"),
			Controls.key_name("sprint"), Controls.key_name("jump"), use]
	if o.state not in [Officer.S.MOVE, Officer.S.CROUCH]:
		return ""
	# v0.10.0: the grapple and the rope.
	var aim_held := (o.buttons & PlayerInput.AIM) != 0
	if aim_held and not o.grapple_plan(PlayerInput.aim_point).is_empty():
		return "%s fire the grapple: up onto the roof" % use
	if not aim_held and not o.abseil_plan().is_empty():
		return "%s abseil down the wall" % use
	var ct := o.cuff_target()
	if ct:
		return ("Hold %s: grab the runner" if ct.state == Suspect.S.CUFF_RUN else "Hold %s: cuff the suspect") % use
	var fg := o.gun_on_floor()
	if fg:
		return "%s pick up the %s (%d rounds)" % [use, String(EnemyGuns.NAMES[fg.kind]).to_lower(), fg.rounds]
	var pr := o.prisoner()
	for c in o.get_tree().get_nodes_in_group("police_cars"):
		var pc := c as PoliceCar
		var bp := pc.boot_point()
		if Vector2(bp.x - o.global_position.x, bp.z - o.global_position.z).length() < Officer.BOOT_RANGE:
			return "Hold %s: ammo and first aid from the boot" % use
		for i in 4:
			var dp := pc.door_point(i)
			if Vector2(dp.x - o.global_position.x, dp.z - o.global_position.z).length() < Officer.ENTER_RANGE + (0.4 if pr else 0.0):
				return ("%s put the suspect in the car" % use) if pr else ("%s get in" % use)
	var sh := Controls.key_name("shout")
	if pr and pr.stay:
		return "%s tell your prisoner to get up and walk with you" % sh
	if pr:
		return "Walk them to a police car (they follow you), or straight to the custody bay.   %s tell them to stay put" % sh
	if o.pouch > 0:
		var tt := o.treat_target()
		if tt == o:
			return "Hold %s: first aid on yourself (%d left)" % [use, o.pouch]
		elif tt:
			return "Hold %s: heal your teammate (%d%% health, %d first aid left)" % [use, roundi(tt.hp), o.pouch]
	return ""
