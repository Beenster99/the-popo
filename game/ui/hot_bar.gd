class_name HotBar
extends CanvasLayer
## The shortcut bar along the bottom of the screen (beenster, 2026-11-24):
## pistol, charge, smoke, CS gas, flashbang, first aid and grapple, each with
## its key and how many you have. The one in your hand is lit; empty slots
## are dimmed. Number keys pick (PlayerInput.pick_slot), D-pad left / right
## on a controller step along it, and fire uses what's in hand.

const SLOT_W := 82.0
const SLOT_H := 78.0
const GAP := 6.0
const BOTTOM := 22.0
const NAMES := ["Pistol", "Charge", "Smoke", "CS gas", "Flash", "First aid", "Grapple"]
const NADE_COLS := [Color("b8bcc4"), Color("d8d24a"), Color("f2f2f2")]

var pawn_getter: Callable
var _bar: Control
var _font: Font


func _ready() -> void:
	layer = 5
	_bar = Control.new()
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.anchor_left = 0.5
	_bar.anchor_right = 0.5
	_bar.anchor_top = 1.0
	_bar.anchor_bottom = 1.0
	var w := width()
	_bar.offset_left = -w / 2.0
	_bar.offset_right = w / 2.0
	_bar.offset_top = -BOTTOM - SLOT_H - 18.0
	_bar.offset_bottom = -BOTTOM
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_font = ThemeDB.fallback_font


static func width() -> float:
	return PlayerInput.SLOT_ACTIONS.size() * (SLOT_W + GAP) - GAP


## Height the bar takes at the bottom, for prompts to sit above it.
static func height() -> float:
	return BOTTOM + SLOT_H + 18.0 if bool(Settings.values.get("hotbar", true)) else 0.0


func _officer() -> Officer:
	var o = pawn_getter.call() if pawn_getter.is_valid() else null
	return o as Officer if o is Officer and is_instance_valid(o) else null


func _process(_delta: float) -> void:
	var o := _officer()
	_bar.visible = o != null and bool(Settings.values.get("hotbar", true)) and not o.in_car() \
		and not PauseMenu.is_open()
	if _bar.visible:
		_bar.queue_redraw()


## "x2", "3", "" (no count), or "-" for none.
static func count_text(i: int, o: Officer) -> String:
	match i:
		PlayerInput.Slot.PISTOL:
			return "%d" % (o.gun_ammo if o.gun != EnemyGuns.NONE else o.ammo)
		PlayerInput.Slot.GEAR:
			return "x%d" % o.charges if o.charges > 0 else "-"
		PlayerInput.Slot.SMOKE, PlayerInput.Slot.GAS, PlayerInput.Slot.FLASH:
			var k := i - PlayerInput.Slot.SMOKE
			if not Armoury.owns(Armoury.NADE_ITEMS[k]):
				return "-"
			return "x%d" % Grenades.count(o.nades, k)
		PlayerInput.Slot.AID:
			return "x%d" % o.pouch
		PlayerInput.Slot.GRAPPLE:
			return "" if Armoury.owns(Armoury.GRAPPLE) else "-"
	return ""


static func slot_name(i: int, o: Officer) -> String:
	if i == PlayerInput.Slot.GEAR and o:
		var g := Armoury.gear_of(o.kit)
		if g == Armoury.Gear.BREACH:
			return "Breach"
		if g == Armoury.Gear.C4:
			return "C4"
	if i == PlayerInput.Slot.PISTOL and o and o.gun != EnemyGuns.NONE:
		return String(EnemyGuns.NAMES[o.gun]).capitalize()
	return NAMES[i]


func _draw_bar() -> void:
	var o := _officer()
	if o == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	var pad := PlayerInput.using_pad
	for i in PlayerInput.SLOT_ACTIONS.size():
		var r := Rect2(i * (SLOT_W + GAP), 18.0, SLOT_W, SLOT_H)
		var ready := PlayerInput.slot_ready(i, o)
		var sel := i == PlayerInput.slot
		var refused := i == PlayerInput.slot_refused and now - PlayerInput.slot_refused_at < 0.6
		var bg := Color(0.05, 0.06, 0.09, 0.78 if sel else 0.6)
		if refused:
			bg = Color(0.45, 0.08, 0.06, 0.8)
		_bar.draw_rect(r, bg)
		if sel:
			_bar.draw_rect(r.grow(1.0), UiTheme.ACCENT, false, 3.0)
		else:
			_bar.draw_rect(r, Color(1, 1, 1, 0.14), false, 1.0)
		var a := 1.0 if ready else 0.32
		_icon(i, r.get_center() + Vector2(0, -6), Color(1, 1, 1, a) if not sel else UiTheme.ACCENT, o)
		# Key, top left.
		var key := "" if pad else Controls.key_name(PlayerInput.SLOT_ACTIONS[i])
		if key != "" and key != "-":
			_bar.draw_string(_font, r.position + Vector2(6, 16), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(UiTheme.ACCENT, 0.9 * maxf(a, 0.6)))
		# Count, top right.
		var c := count_text(i, o)
		if c != "":
			_bar.draw_string(_font, r.position + Vector2(0, 16), c, HORIZONTAL_ALIGNMENT_RIGHT, SLOT_W - 6, 14,
				Color(1, 1, 1, 0.9 * a))
		# Name, bottom.
		_bar.draw_string(_font, r.position + Vector2(0, SLOT_H - 7), slot_name(i, o), HORIZONTAL_ALIGNMENT_CENTER, SLOT_W, 13,
			Color(UiTheme.TEXT, a) if not sel else UiTheme.ACCENT)
	# What fire does now, over the bar.
	var hint := _fire_hint(o)
	if pad:
		hint = ("D-pad left / right picks   " + hint).strip_edges()
	_bar.draw_string(_font, Vector2(0, 12), hint, HORIZONTAL_ALIGNMENT_CENTER, width(), 14, Color(1, 1, 1, 0.75))


func _fire_hint(o: Officer) -> String:
	var f := Controls.key_name("fire")
	match PlayerInput.slot:
		PlayerInput.Slot.GEAR:
			return "aim, %s sticks one on" % f
		PlayerInput.Slot.SMOKE, PlayerInput.Slot.GAS, PlayerInput.Slot.FLASH:
			return "%s throws at the dot" % f
		PlayerInput.Slot.AID:
			var tt := o.treat_target()
			return "hold %s: first aid on %s" % [f, "yourself" if tt == o else "your teammate"] if tt else "nobody hurt (first aid)"
		PlayerInput.Slot.GRAPPLE:
			return "aim at a building, %s fires the hook" % f
	return ""


## Simple flat icons, drawn so they need no image files.
func _icon(i: int, c: Vector2, col: Color, o: Officer) -> void:
	match i:
		PlayerInput.Slot.PISTOL:
			_bar.draw_rect(Rect2(c + Vector2(-16, -9), Vector2(30, 8)), col)          # slide
			_bar.draw_colored_polygon(PackedVector2Array([c + Vector2(-14, -1), c + Vector2(-4, -1),
				c + Vector2(-2, 12), c + Vector2(-11, 12)]), col)                    # grip
			_bar.draw_arc(c + Vector2(-1, 1), 4.0, 0.0, PI, 8, col, 2.0)            # trigger guard
		PlayerInput.Slot.GEAR:
			_bar.draw_rect(Rect2(c + Vector2(-13, -8), Vector2(26, 16)), col)
			_bar.draw_rect(Rect2(c + Vector2(-9, -4), Vector2(8, 8)), Color(0.85, 0.15, 0.1, col.a))
			_bar.draw_line(c + Vector2(13, -2), c + Vector2(19, -10), col, 2.0)
		PlayerInput.Slot.SMOKE, PlayerInput.Slot.GAS, PlayerInput.Slot.FLASH:
			var nc: Color = NADE_COLS[i - PlayerInput.Slot.SMOKE]
			nc.a = col.a
			_bar.draw_rect(Rect2(c + Vector2(-7, -10), Vector2(14, 22)), nc)
			_bar.draw_rect(Rect2(c + Vector2(-4, -14), Vector2(8, 4)), col)
			_bar.draw_arc(c + Vector2(6, -14), 4.0, -PI, 0.0, 8, col, 2.0)          # ring
		PlayerInput.Slot.AID:
			_bar.draw_rect(Rect2(c + Vector2(-13, -10), Vector2(26, 20)), Color(0.95, 0.95, 0.95, col.a))
			var red := Color(0.85, 0.12, 0.12, col.a)
			_bar.draw_rect(Rect2(c + Vector2(-3, -7), Vector2(6, 14)), red)
			_bar.draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 6)), red)
		PlayerInput.Slot.GRAPPLE:
			_bar.draw_line(c + Vector2(0, 12), c + Vector2(0, -8), col, 3.0)
			_bar.draw_arc(c + Vector2(-6, -8), 6.0, -PI, 0.0, 10, col, 2.5)
			_bar.draw_arc(c + Vector2(6, -8), 6.0, -PI, 0.0, 10, col, 2.5)
			_bar.draw_arc(c + Vector2(0, 14), 3.0, 0.0, TAU, 10, col, 2.0)
