class_name GameTips
extends CanvasLayer
## In-game tips: the first time something happens (gun out, first car,
## first job, first wound, someone gives up...), a short tip slides in at
## the right of the screen with the keys for it, then fades. Each shows
## once, ever (user://tips.cfg); Settings > Gameplay turns them off or
## brings them all back. Keys come from the live bindings, as controller
## buttons when you're on a controller.

const SAVE_PATH := "user://tips.cfg"
const SHOW_FOR := 10.0
const GAP := 2.0

## [id, text]. Conditions live in _check.
const TIPS := {
	"start": "Esc ({back}) opens the menu. Help in there has every control and how things work, and Key binds lets you change any key.",
	"move": "{walk} switches between walking and running. Hold {sprint} to sprint. {stance}: tap to crouch, hold to lie prone.",
	"gun": "Gun out. Hold {aim} to aim, {fire} fires at the dot. Stop and let it settle: shots on the move go wide. {holster} puts it away; people get nervous round a drawn gun.",
	"driver": "{torch} cycles lights and siren (traffic pulls over). {horn} horn, {handbrake} handbrake, {interact} get out. Hold {interact} at the boot for ammo and first aid.",
	"passenger": "Passenger: hold {aim} to lean out of the window and shoot. {stance} moves you to the next seat.",
	"cover": "In cover. Hold {aim} to peek and shoot; fire without aiming to blind fire. Hold a direction and press {cover} to run to the next cover.",
	"call": "A job! It's listed top left with its distance, and an arrow at the screen edge points the way. In a patrol car, {torch} puts the lights on.",
	"suspect": "Shout orders with {shout}. Not everyone listens first time. When they kneel, hold {interact} next to them to cuff them.",
	"cuff": "They've given up. Hold {interact} to cuff them.",
	"prisoner": "Your prisoner follows you. Put them in a patrol car ({interact} at a door) and drive to the custody bay at the side of the station, or walk them there. {shout} tells them to stay put.",
	"floor_gun": "{interact} picks up the gun, but you only get the rounds loaded in it. {holster} drops it again.",
	"hurt": "You're wounded (bottom right). Hold {interact} for first aid from your pouch. A patrol car's boot patches everything.",
	"down": "You're down. A teammate can hold {interact} on you to get you up, or press {reload} to respawn once the wait is over.",
	"mate_down": "A teammate is down. Hold {interact} next to them to get them up, or hold {drag} to drag them into cover first.",
	"nades": "Grenades: {throw} throws the picked one at the dot, {grenade_next} picks smoke, CS gas or flashbang.",
}

static var _seen := {}
static var _loaded := false

var pawn_getter: Callable
var dispatcher: Dispatcher
var _queue: Array[String] = []
var _panel: PanelContainer
var _label: RichTextLabel
var _showing := ""
var _t := 0.0
var _gap := 3.0
var _age := 0.0


static func enabled() -> bool:
	return bool(Settings.values.get("tips", true))


static func seen(id: String) -> bool:
	_load()
	return _seen.has(id)


static func reset() -> void:
	_seen.clear()
	_loaded = true
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK and cfg.has_section("seen"):
		for k in cfg.get_section_keys("seen"):
			_seen[k] = true


static func _mark(id: String) -> void:
	_load()
	_seen[id] = true
	var cfg := ConfigFile.new()
	for k in _seen:
		cfg.set_value("seen", k, true)
	cfg.save(SAVE_PATH)


## The tip's text with {action} swapped for its key in yellow.
static func fill(text: String) -> String:
	var out := text.replace("{back}", "Menu" if PlayerInput.using_pad else "Esc")
	for pair in Controls.REBINDABLE:
		var tag := "{%s}" % pair[0]
		if out.contains(tag):
			out = out.replace(tag, "[color=#%s][b]%s[/b][/color]" % [UiTheme.ACCENT.to_html(false), Controls.key_name(pair[0])])
	return out


func _ready() -> void:
	layer = 6
	_load()
	var root := Control.new()
	root.theme = UiTheme.get_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(UiTheme.PANEL, 0.88)
	sb.border_color = UiTheme.ACCENT
	sb.border_width_left = 4
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.offset_left = -470
	_panel.offset_right = -24
	_panel.offset_top = 190
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.modulate.a = 0.0
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(box)
	var head := UiTheme.title("TIP", 15, UiTheme.ACCENT)
	box.add_child(head)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size.x = 410
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("normal_font_size", 17)
	_label.add_theme_font_size_override("bold_font_size", 17)
	box.add_child(_label)


func want(id: String) -> void:
	if not enabled() or _seen.has(id) or id == _showing or id in _queue:
		return
	_queue.append(id)


func _process(delta: float) -> void:
	_age += delta
	if _showing != "":
		_t -= delta
		_panel.modulate.a = clampf(minf(SHOW_FOR - _t, _t) * 3.0, 0.0, 1.0)
		if _t <= 0.0 or not enabled():
			_showing = ""
			_panel.modulate.a = 0.0
			_gap = GAP
		return
	_gap -= delta
	if PauseMenu.is_open() or ArmouryScreen.is_open():
		return
	_check()
	if _gap > 0.0 or _queue.is_empty():
		return
	_showing = _queue.pop_front()
	_label.text = fill(TIPS[_showing])
	_t = SHOW_FOR
	_mark(_showing)


## Looks at what the local officer is up to and queues tips that fit.
func _check() -> void:
	if not enabled():
		return
	var o: Officer = pawn_getter.call() if pawn_getter.is_valid() else null
	if o == null or not is_instance_valid(o):
		return
	if _age > 4.0:
		want("start")
	if _age > 40.0:
		want("move")
	if o.state == Officer.S.DOWNED:
		want("down")
		return
	if o.in_car():
		want("driver" if o.seat == 0 else "passenger")
		return
	if o.gun_up():
		want("gun")
	if o.state == Officer.S.COVER:
		want("cover")
	if o.injuries != 0:
		want("hurt")
	if o.cuff_target():
		want("cuff")
	if o.prisoner():
		want("prisoner")
	if o.gun_on_floor():
		want("floor_gun")
	if o.nades != 0:
		want("nades")
	if dispatcher and not dispatcher.active_calls().is_empty():
		want("call")
		for sp in dispatcher.suspects.values():
			var su := sp as Suspect
			if su.is_free() and not su.civilian and su.global_position.distance_to(o.global_position) < 12.0:
				want("suspect")
				break
	for other in get_tree().get_nodes_in_group("officers"):
		if other != o and (other as Officer).state == Officer.S.DOWNED and (other as Node3D).global_position.distance_to(o.global_position) < 25.0:
			want("mate_down")
			break
