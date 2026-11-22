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
	_bar.visible = o.is_reloading()
	_bar.value = 1.0 - o.reload_t / Officer.RELOAD_TIME
