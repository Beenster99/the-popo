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
	_name.text = Officer.WEAPON_NAME.to_upper()
	_mag.text = str(o.ammo)
	_mag.add_theme_color_override("font_color", Color(1.0, 0.4, 0.35) if o.ammo <= 3 else Color.WHITE)
	_spare.text = "  / %d" % o.reserve
	var s := ""
	if o.is_reloading():
		s = "RELOADING"
	elif o.holstered:
		s = "HOLSTERED"
	elif o.ammo == 0 and o.reserve == 0:
		s = "OUT OF AMMO"
	elif o.ammo == 0:
		s = "EMPTY - RELOAD"
	_state.text = s
	_state.visible = s != ""
	_bar.visible = o.is_reloading() or o.treat_t > 0.0 or o._boot_t > 0.0
	if o.is_reloading():
		_bar.value = 1.0 - o.reload_t / Officer.RELOAD_TIME
	elif o._boot_t > 0.0:
		_bar.value = o._boot_t / Officer.BOOT_TIME
	elif o.treat_t > 0.0:
		_bar.value = o.treat_t / o.treat_time()
	var wounds := Officer.injury_names(o.injuries)
	_health.text = "%s\nFIRST AID %d" % ["  ".join(wounds), o.pouch] if not wounds.is_empty() else "FIRST AID %d" % o.pouch
	_health.add_theme_color_override("font_color", Color(1.0, 0.45, 0.4) if not wounds.is_empty() else Color(0.7, 0.75, 0.8))
	_hint.text = _prompt(o)


## One line on what the use key does here.
func _prompt(o: Officer) -> String:
	var use := Controls.describe(Controls.pc_event("interact"))
	if o.in_car():
		var parts: PackedStringArray = ["%s get out" % use, "%s change seat" % Controls.describe(Controls.pc_event("stance"))]
		if o.seat == 0:
			parts.append("%s lights / siren" % Controls.describe(Controls.pc_event("torch")))
			parts.append("%s horn" % Controls.describe(Controls.pc_event("horn")))
		else:
			parts.append("%s lean out and aim" % Controls.describe(Controls.pc_event("aim")))
		return "   ".join(parts)
	if o.state not in [Officer.S.MOVE, Officer.S.CROUCH]:
		return ""
	for c in o.get_tree().get_nodes_in_group("police_cars"):
		var pc := c as PoliceCar
		var bp := pc.boot_point()
		if Vector2(bp.x - o.global_position.x, bp.z - o.global_position.z).length() < Officer.BOOT_RANGE:
			return "Hold %s: ammo and first aid from the boot" % use
		for i in 4:
			var dp := pc.door_point(i)
			if Vector2(dp.x - o.global_position.x, dp.z - o.global_position.z).length() < Officer.ENTER_RANGE:
				return "%s get in" % use
	if o.pouch > 0:
		var tt := o.treat_target()
		if tt == o:
			return "Hold %s: treat your wound" % use
		elif tt:
			return "Hold %s: treat your teammate" % use
	return ""
