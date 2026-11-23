class_name ArmouryScreen
extends CanvasLayer
## Phase 3.5: the armoury counter. Buy kit for the station with its pay,
## and pick your own pistol and rounds. The game carries on behind it.

static var _open: ArmouryScreen

var armoury: Armoury
var pawn_getter: Callable
var _cat := 0
var _list: VBoxContainer
var _money: Label
var _tabs: HBoxContainer
## The 3D inspection bench beside the list, and what it shows: a pistol
## (the one you carry until you point at another) and an upgrade to try on.
var _bench: GunBench
var _bench_name: Label
var _bench_parts: Label
var _look_pistol := -1
var _try := -1


static func open(tree: SceneTree, a: Armoury, pawn: Callable) -> void:
	if is_instance_valid(_open):
		return
	var s := ArmouryScreen.new()
	s.armoury = a
	s.pawn_getter = pawn
	tree.root.add_child(s)


static func is_open() -> bool:
	return is_instance_valid(_open)


func _ready() -> void:
	_open = self
	layer = 70
	PlayerInput.blocked = true
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(1500, 780)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_child(UiTheme.title("STATION ARMOURY", 30, UiTheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	_money = UiTheme.title("", 26)
	head.add_child(_money)
	box.add_child(head)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	box.add_child(_tabs)
	for i in Armoury.CAT_NAMES.size():
		var b := Button.new()
		b.text = Armoury.CAT_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(140, 42)
		b.pressed.connect(func(): _cat = i; _try = -1; _look_pistol = -1; _fill(); _show_bench())
		_tabs.add_child(b)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 16)
	box.add_child(split)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 640
	side.add_theme_constant_override("separation", 6)
	split.add_child(side)
	_bench = GunBench.new()
	_bench.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bench.custom_minimum_size = Vector2(640, 440)
	side.add_child(_bench)
	_bench_name = UiTheme.title("", 24, UiTheme.ACCENT)
	side.add_child(_bench_name)
	_bench_parts = UiTheme.title("", 16)
	_bench_parts.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bench_parts.custom_minimum_size.y = 46
	side.add_child(_bench_parts)
	side.add_child(UiTheme.title("Drag to turn it, wheel to zoom.  Pad: right stick turns, triggers zoom.", 14, UiTheme.DIM))
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)
	var foot := HBoxContainer.new()
	var hint := UiTheme.title("Kit is bought for the whole station. Esc / B to close.", 16, UiTheme.DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(160, 44)
	close.pressed.connect(close_screen)
	foot.add_child(close)
	box.add_child(foot)
	if armoury:
		armoury.changed.connect(_fill)
	if armoury and armoury.dispatcher:
		armoury.dispatcher.paid.connect(func(_a, _t): _fill())
	_fill()
	_show_bench()
	(_tabs.get_child(0) as Button).grab_focus.call_deferred()


func close_screen() -> void:
	PlayerInput.blocked = false
	_open = null
	queue_free()


func _officer() -> Officer:
	return pawn_getter.call() as Officer if pawn_getter.is_valid() else null


func _fill() -> void:
	if not is_inside_tree():
		return
	var pay: int = armoury.dispatcher.pay if armoury and armoury.dispatcher else 0
	_money.text = "Station pay: £%s" % DispatchHud._money(pay)
	for i in _tabs.get_child_count():
		(_tabs.get_child(i) as Button).button_pressed = i == _cat
	for c in _list.get_children():
		c.queue_free()
	var o := _officer()
	for i in Armoury.ITEMS.size():
		var it: Dictionary = Armoury.ITEMS[i]
		if it.cat != _cat:
			continue
		_list.add_child(_row(i, it, pay, o))
	if _cat == Armoury.Cat.LOADOUT:
		var on := o != null and Armoury.gear_of(o.kit) == Armoury.Gear.NONE
		var row0 := _row_frame("Nothing extra", "Travel light.", "")
		_row_button(row0, "Carrying" if on else "Carry", not on and o != null,
			func(): armoury.set_kit(o.kit & 7, Armoury.ammo_of(o.kit), Armoury.Gear.NONE))
		_list.add_child(row0)
		_list.move_child(row0, 0)
	if _cat == Armoury.Cat.AMMO:
		# Standard rounds: always there.
		var row := _row_frame("Standard", "Plain full metal jacket.", "")
		_row_button(row, "Load" if o == null or Armoury.ammo_of(o.kit) != Armoury.Ammo.STANDARD else "Loaded",
			o != null and Armoury.ammo_of(o.kit) != Armoury.Ammo.STANDARD,
			func(): armoury.set_kit(o.kit & 7, Armoury.Ammo.STANDARD))
		_list.add_child(row)
		_list.move_child(row, 0)
	_show_bench()


func _row(i: int, it: Dictionary, pay: int, o: Officer) -> Control:
	var about := Armoury.item_about(i)
	if it.has("pistol"):
		var p: Dictionary = Armoury.PISTOLS[it.pistol]
		about += "\n%d rounds · %.0f damage · %d shots a second · %.1f s reload" % [
			Armoury.mag_size(it.pistol), float(p.dmg), int(round(1.0 / float(p.gap))), Armoury.reload_time(it.pistol)]
	var row := _row_frame(Armoury.item_name(i), about, "" if Armoury.owns(i) else "£%s" % DispatchHud._money(int(it.price)))
	_bench_hover(row, i, it)
	var why := Armoury.why_not(i, pay)
	if Armoury.owns(i):
		if it.has("pistol"):
			var carrying := o != null and (o.kit & 7) == int(it.pistol)
			_row_button(row, "Carrying" if carrying else "Carry", not carrying and o != null,
				func(): armoury.set_kit(it.pistol, Armoury.ammo_of(o.kit)))
		elif i == Armoury.PLAIN:
			var wearing := o != null and o.plain
			_row_button(row, "Back in uniform" if wearing else "Wear them", o != null,
				func(): armoury.set_plain(not o.plain))
		elif it.has("gear"):
			var on := o != null and Armoury.gear_of(o.kit) == int(it.gear)
			_row_button(row, "Carrying" if on else "Carry", not on and o != null,
				func(): armoury.set_kit(o.kit & 7, Armoury.ammo_of(o.kit), it.gear))
		elif it.has("ammo"):
			var loaded := o != null and Armoury.ammo_of(o.kit) == int(it.ammo)
			_row_button(row, "Loaded" if loaded else "Load", not loaded and o != null,
				func(): armoury.set_kit(o.kit & 7, it.ammo))
		else:
			_row_button(row, "Owned", false, func(): pass)
	else:
		_row_button(row, "Buy" if why == "" else why.capitalize(), why == "", func(): armoury.buy(i))
	return row


func _row_frame(name: String, about: String, price: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_child(UiTheme.title(name, 22))
	var a := UiTheme.title(about, 15, UiTheme.DIM)
	a.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(a)
	row.add_child(text)
	var pl := UiTheme.title(price, 20, UiTheme.ACCENT)
	pl.custom_minimum_size.x = 90
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(pl)
	return row


func _row_button(row: HBoxContainer, text: String, enabled: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(190, 44)
	b.disabled = not enabled
	b.pressed.connect(cb)
	row.add_child(b)


## Pointing at a row (mouse over it, or its button focused on a pad) puts
## that pistol on the bench, or tries that upgrade on.
func _bench_hover(row: Control, i: int, it: Dictionary) -> void:
	var look := func():
		if it.has("pistol"):
			_look_pistol = int(it.pistol)
			_try = -1
		elif i in [Armoury.EXT_MAG, Armoury.COMPENSATOR, Armoury.MATCH_BARREL, Armoury.SPEED_LOAD]:
			_try = i
		elif i == Armoury.GEAR_ITEM[Armoury.Gear.TORCH]:
			_try = GunBench.TORCH
		else:
			return
		_show_bench()
	row.mouse_entered.connect(look)
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.child_entered_tree.connect(func(c: Node):
		if c is Button:
			(c as Button).focus_entered.connect(look)
			(c as Button).mouse_entered.connect(look))


## What the bench shows: the pistol, with the station's upgrades fitted, the
## torch if you carry it, and whatever upgrade you're pointing at.
func _show_bench() -> void:
	if _bench == null:
		return
	var o := _officer()
	var p := _look_pistol
	if p < 0:
		p = (o.kit & 7) if o else 0
	p = clampi(p, 0, Armoury.PISTOLS.size() - 1)
	var mask := 0
	var names: PackedStringArray = []
	for bit in [Armoury.EXT_MAG, Armoury.COMPENSATOR, Armoury.MATCH_BARREL, Armoury.SPEED_LOAD]:
		if Armoury.owns(bit):
			mask |= 1 << bit
			names.append(_part_name(bit, p))
	var torch_on := o != null and Armoury.gear_of(o.kit) == Armoury.Gear.TORCH
	if torch_on:
		mask |= 1 << GunBench.TORCH
		names.append("tactical torch")
	var trying := ""
	if _try >= 0 and (mask & (1 << _try)) == 0:
		mask |= 1 << _try
		trying = _part_name(_try, p)
	_bench.show_gun(p, mask)
	var carried := o != null and (o.kit & 7) == p
	_bench_name.text = String(Armoury.PISTOLS[p].name) + ("  (yours)" if carried else "")
	var t := "Fitted: " + (", ".join(names) if names.size() > 0 else "nothing yet, it's factory standard")
	if trying != "":
		t += "\nTrying on: " + trying + ("" if _try == GunBench.TORCH or Armoury.owns(_try) else " (not bought)")
	_bench_parts.text = t


func _part_name(bit: int, p: int) -> String:
	match bit:
		Armoury.EXT_MAG:
			return "9-shot cylinder" if p == 3 else "extended magazine"
		Armoury.COMPENSATOR:
			return "compensator"
		Armoury.MATCH_BARREL:
			return "match barrel"
		Armoury.SPEED_LOAD:
			return "speed loader" if p == 3 else "flared magwell"
		GunBench.TORCH:
			return "tactical torch"
	return ""


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_screen()
