class_name NetOverlay
extends CanvasLayer
## F3 network debug overlay: ping, bandwidth in and out, snapshot rate, and
## sliders for fake latency, jitter and packet loss.

var extra_lines: Callable  # optional: returns a String with prototype stats
var _label: Label
var _panel: PanelContainer


func _ready() -> void:
	layer = 50
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	add_child(_panel)
	var v := VBoxContainer.new()
	_panel.add_child(v)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	v.add_child(_label)
	v.add_child(_slider("Fake round trip (ms)", 0, 400, Net.sim_latency_ms, func(x): Net.sim_latency_ms = x))
	v.add_child(_slider("Jitter (ms)", 0, 100, Net.sim_jitter_ms, func(x): Net.sim_jitter_ms = x))
	v.add_child(_slider("Packet loss (%)", 0, 30, Net.sim_loss * 100.0, func(x): Net.sim_loss = x / 100.0))


func _slider(title: String, lo: float, hi: float, value: float, cb: Callable) -> Control:
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = title
	l.custom_minimum_size.x = 170
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1
	s.value = value
	s.custom_minimum_size.x = 160
	var val := Label.new()
	val.text = str(int(value))
	s.value_changed.connect(func(x): cb.call(x); val.text = str(int(x)))
	h.add_child(s)
	h.add_child(val)
	return h


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_net_overlay"):
		_panel.visible = not _panel.visible


func _process(_delta: float) -> void:
	if not _panel.visible:
		return
	var role := "offline" if not Net.is_online() else ("host" if Net.is_host() else "client")
	var t := "%s  ·  %d/%d players  ·  %d fps\n" % [role, Net.slots.size(), Net.MAX_PLAYERS, Engine.get_frames_per_second()]
	t += "ping %d ms   in %.1f kbps   out %.1f kbps\n" % [Net.rtt_ms(), Net.kbps_in, Net.kbps_out]
	t += "packets in %d/s  out %d/s   snapshots %d/s" % [Net.packets_in_per_s, Net.packets_out_per_s, Net.rate("snapshots")]
	if extra_lines.is_valid():
		t += "\n" + str(extra_lines.call())
	_label.text = t
