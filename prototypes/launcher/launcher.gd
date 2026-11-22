extends Control
## Wave 0 launcher: host or join a game, see the lobby, and pick a prototype.
## The host picks the prototype and everyone in the lobby loads it.

const PROTOTYPES := [
	["0.1 Pipeline check (Blender asset with collision)", "res://prototypes/p01_pipeline/pipeline.tscn"],
	["0.2 Two players in one room", "res://prototypes/p02_netroom/netroom.tscn"],
	["0.3 Destruction spike", "res://prototypes/p03_destruction/destruction.tscn"],
	["0.3 Destruction stress test", "res://prototypes/p03_destruction/stress.tscn"],
	["0.4 Car spike", "res://prototypes/p04_car/car.tscn"],
	["0.5 Look spike (cel shading, camera, roofs)", "res://prototypes/p05_look/look.tscn"],
	["0.6 Movement and animation course", "res://prototypes/p06_movement/movement.tscn"],
	["0.7 Sound spike", "res://prototypes/p07_sound/sound.tscn"],
	["1.1 City block (generated, breakable)", "res://prototypes/p08_block/block.tscn"],
	["1.2 Training yard (movement, cover, melee, revive)", "res://prototypes/p09_yard/yard.tscn"],
]

var _name: LineEdit
var _addr: LineEdit
var _port: SpinBox
var _status: Label
var _lobby: ItemList
var _list: VBoxContainer
var _internet: Label
var _copy: Button


func _ready() -> void:
	theme = UiTheme.get_theme()
	var cfg := ConfigFile.new()
	cfg.load("user://launcher.cfg")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1b2230")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 40)
	margin.add_child(root)

	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 420
	root.add_child(left)
	var title := Label.new()
	title.text = "ONLINE  ·  v%s" % ProjectSettings.get_setting("application/config/version", "dev")
	title.add_theme_font_size_override("font_size", 34)
	left.add_child(title)
	left.add_child(_label("Your name"))
	_name = LineEdit.new()
	_name.text = cfg.get_value("net", "name", "Officer")
	left.add_child(_name)
	left.add_child(_label("Host address (to join)"))
	_addr = LineEdit.new()
	_addr.text = cfg.get_value("net", "address", "127.0.0.1")
	left.add_child(_addr)
	left.add_child(_label("Port"))
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = cfg.get_value("net", "port", Net.DEFAULT_PORT)
	left.add_child(_port)
	var buttons := HBoxContainer.new()
	left.add_child(buttons)
	buttons.add_child(_button("Host", _on_host))
	buttons.add_child(_button("Join", _on_join))
	buttons.add_child(_button("Leave", func(): Net.leave(); _refresh()))
	buttons.add_child(_button("Back to menu", func(): Net.leave(); get_tree().change_scene_to_file("res://game/ui/main_menu.tscn")))
	_status = _label("Offline: you can still run every prototype on your own.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	left.add_child(_status)
	_internet = _label("")
	_internet.autowrap_mode = TextServer.AUTOWRAP_WORD
	_internet.add_theme_color_override("font_color", Color("ffd479"))
	left.add_child(_internet)
	_copy = _button("Copy address for friends", func():
		if Net.port_opener.public_ip != "":
			DisplayServer.clipboard_set("%s:%d" % [Net.port_opener.public_ip, int(_port.value)]))
	_copy.visible = false
	left.add_child(_copy)
	var po: PortOpener = Net.port_opener
	if po.state != "idle":
		_internet.text = PortOpener.describe(po.state, po.port, po.public_ip, po.router_ip)
		_copy.visible = po.public_ip != ""
	Net.port_opener.status_changed.connect(func(t):
		_internet.text = t
		_copy.visible = Net.port_opener.public_ip != "")
	left.add_child(_label("Players (max 3)"))
	_lobby = ItemList.new()
	_lobby.custom_minimum_size.y = 110
	left.add_child(_lobby)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	right.add_child(_label("Prototypes (the host picks for everyone)"))
	_list = VBoxContainer.new()
	right.add_child(_list)
	for p in PROTOTYPES:
		var b := _button(p[0], func(): _start(p[1]))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list.add_child(b)
	right.add_child(_label("\nEsc opens the menu (Settings, Leave). F3 toggles the network overlay. Q/E rotate the camera, mouse wheel zooms.\nA game controller works too."))
	right.add_child(_button("Controls...", func(): add_child(load("res://prototypes/launcher/controls_screen.gd").new())))

	Net.lobby_changed.connect(_refresh)
	Net.joined.connect(func(): _status.text = "Joined. Waiting for the host to pick a prototype."; _refresh())
	Net.join_failed.connect(func(r): _status.text = r; _refresh())
	Net.left.connect(func(): _status.text = "Disconnected."; _refresh())
	_refresh()


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


func _button(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b


func _save() -> void:
	Net.player_name = _name.text.strip_edges()
	var cfg := ConfigFile.new()
	cfg.set_value("net", "name", _name.text)
	cfg.set_value("net", "address", _addr.text)
	cfg.set_value("net", "port", int(_port.value))
	cfg.save("user://launcher.cfg")


func _on_host() -> void:
	_save()
	var err := Net.host(int(_port.value))
	_status.text = "Hosting on port %d. Friends on your home network join with this PC's local address." % int(_port.value) if err == OK else "Could not host (error %d). Is the port in use?" % err
	if err == OK:
		Net.port_opener.open(int(_port.value))
	_refresh()


func _on_join() -> void:
	_save()
	var err := Net.join(_addr.text.strip_edges(), int(_port.value))
	_status.text = "Connecting to %s:%d ..." % [_addr.text, int(_port.value)] if err == OK else "Could not start connecting (error %d)." % err


func _start(path: String) -> void:
	if Net.is_online() and not Net.is_host():
		_status.text = "Only the host picks the prototype."
		return
	_save()
	if Net.is_online():
		Net.load_scene_for_all(path)
	else:
		get_tree().change_scene_to_file(path)


func _refresh() -> void:
	_lobby.clear()
	for s in Net.slots:
		_lobby.add_item("%s%s" % [s.name, "  (host)" if s.id == 1 else ""])
	for i in range(Net.slots.size(), Net.MAX_PLAYERS):
		_lobby.add_item("· open slot")
	for b in _list.get_children():
		b.disabled = Net.is_online() and not Net.is_host()
