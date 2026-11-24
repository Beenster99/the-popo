class_name BenchmarkRun
extends Node
## v0.8.1: the benchmark's camera run through the city (see Perf). The same
## city (Perf.BENCH_SEED), the same route and the same blast every time.
## Street level round four junctions (as an officer sees it), then up over
## downtown, then the results.

const SETTLE := 4.0          # s to let the city wake up before measuring
const STREET_SPEED := 16.0   # m/s
const EYE := 2.4             # m above the road
const BLAST_AT := 0.35       # share of the street run where the blast goes off

var city: City
var _cam: Camera3D
var _path: Array = []        # Vector3 points (street run)
var _lens: Array = []        # running length at each point
var _street_len := 0.0
var _t := -SETTLE
var _blasted := false
var _done := false
## Per frame: [ms, gpu ms, render cpu ms, draw calls, objects]
var _samples: Array = []
var _orbit_t := 0.0
const ORBIT_TIME := 12.0
var _orbit_centre := Vector3.ZERO
## v0.23.1: the run measures with V-Sync and the frame cap off, so it shows
## how fast the game can go rather than the screen's refresh rate; the
## player's own choice comes back afterwards.
var _vsync_was := DisplayServer.VSYNC_ENABLED
var _cap_was := 0


func _ready() -> void:
	_vsync_was = DisplayServer.window_get_vsync_mode()
	_cap_was = Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 1500.0
	city.add_child(_cam)
	var g := CityGenerator.GRID
	var a := clampi(2, 0, g)
	var b := clampi(g - 1, 0, g)
	var top := clampi(1, 0, g)
	var bottom := clampi(g - 2, 0, g)
	var corners := [Vector2i(a, bottom), Vector2i(a, top), Vector2i(b, top), Vector2i(b, bottom), Vector2i(a, bottom)]
	for c in corners:
		var j: Vector3 = CityGenerator.junction(c.x, c.y)
		_path.append(Vector3(j.x, BlockGenerator.BASE_Y + EYE, j.z))
	_lens.append(0.0)
	for i in range(1, _path.size()):
		_street_len += (_path[i] as Vector3).distance_to(_path[i - 1])
		_lens.append(_street_len)
	var mid: Vector3 = CityGenerator.junction(g / 2, g / 2)
	_orbit_centre = Vector3(mid.x, 0.0, mid.z)
	_cam.global_position = _path[0]
	_cam.look_at(_path[1], Vector3.UP)
	_cam.make_current()


func _exit_tree() -> void:
	_restore_vsync()


func _restore_vsync() -> void:
	DisplayServer.window_set_vsync_mode(_vsync_was)
	Engine.max_fps = _cap_was


func _process(delta: float) -> void:
	if _done:
		return
	_cam.make_current()
	_t += delta
	if _t < 0.0:
		return
	var dist := _t * STREET_SPEED
	if dist < _street_len:
		_street(dist)
	else:
		_orbit_t += delta
		_orbit(_orbit_t / ORBIT_TIME)
		if _orbit_t >= ORBIT_TIME:
			_finish()
			return
	_samples.append([delta * 1000.0, Perf.gpu_ms(), Perf.render_cpu_ms(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0])


func _street(dist: float) -> void:
	var i := 1
	while i < _lens.size() - 1 and _lens[i] < dist:
		i += 1
	var p0: Vector3 = _path[i - 1]
	var p1: Vector3 = _path[i]
	var k: float = (dist - _lens[i - 1]) / maxf(_lens[i] - _lens[i - 1], 0.01)
	var pos := p0.lerp(p1, clampf(k, 0.0, 1.0))
	# Keep to the left-hand lane, and turn smoothly near the corners.
	var dir := (p1 - p0).normalized()
	var side := dir.cross(Vector3.UP) * -CityGenerator.LANE
	_cam.global_position = pos + side
	var ahead := dir
	if i + 1 < _path.size() and k > 0.85:
		var nxt := ((_path[i + 1] as Vector3) - p1).normalized()
		ahead = dir.lerp(nxt, (k - 0.85) / 0.15).normalized()
	_cam.look_at(_cam.global_position + ahead * 10.0 + Vector3(0, -0.6, 0), Vector3.UP)
	if not _blasted and dist > _street_len * BLAST_AT and city.world:
		_blasted = true
		# A charge against the nearest building a little way ahead.
		var at := _cam.global_position + ahead * 25.0 - side * 3.6
		at.y = BlockGenerator.BASE_Y + 1.0
		city.world.explode(at, 5.0, 900.0, 18.0)


func _orbit(k: float) -> void:
	var ang := lerpf(0.0, TAU * 0.6, k)
	var r := 150.0
	var h := lerpf(20.0, 70.0, minf(k * 2.0, 1.0))
	_cam.global_position = _orbit_centre + Vector3(cos(ang) * r, h, sin(ang) * r)
	_cam.look_at(_orbit_centre, Vector3.UP)


func _finish() -> void:
	_done = true
	_restore_vsync()
	var text := _summary()
	var where := Perf.save_report(text)
	print(text)
	_show(text, where)


static func _pct(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var s := arr.duplicate()
	s.sort()
	return s[clampi(int(s.size() * p), 0, s.size() - 1)]


static func _mean(arr: Array) -> float:
	var t := 0.0
	for v in arr:
		t += v
	return t / maxf(arr.size(), 1)


func _summary() -> String:
	var ms: Array = []
	var gpu: Array = []
	var rcpu: Array = []
	var draws: Array = []
	var objs: Array = []
	var game: Array = []
	var phys: Array = []
	for s in _samples:
		ms.append(s[0]); gpu.append(s[1]); rcpu.append(s[2]); draws.append(s[3]); objs.append(s[4]); game.append(s[5]); phys.append(s[6])
	var vp := get_viewport()
	var v: Dictionary = Settings.values
	var lines := PackedStringArray()
	lines.append("The Popo v%s benchmark   (%d frames over %.0f s)" % [
		ProjectSettings.get_setting("application/config/version", "dev"), ms.size(), _mean(ms) * ms.size() / 1000.0])
	lines.append("Average %.0f fps   1%% low %.0f fps   worst frame %.1f ms" % [
		1000.0 / maxf(_mean(ms), 0.01), 1000.0 / maxf(_pct(ms, 0.99), 0.01), _pct(ms, 1.0)])
	# (Godot's game code and physics timers hold the slowest frame of each
	# second, so they are worst cases, not averages.)
	lines.append("GPU %.1f ms avg (%.1f ms at worst 1%%)   render CPU %.1f ms   game code %.1f ms   physics %.1f ms (slowest each second)" % [
		_mean(gpu), _pct(gpu, 0.99), _mean(rcpu), _mean(game), _mean(phys)])
	lines.append("Draw calls %.0f avg, %.0f max   objects %.0f avg" % [_mean(draws), _pct(draws, 1.0), _mean(objs)])
	var scr := DisplayServer.window_get_current_screen()
	lines.append("Monitor %dx%d at %.0f Hz   window %s   (measured with V-Sync and frame cap off)" % [
		DisplayServer.screen_get_size(scr).x, DisplayServer.screen_get_size(scr).y,
		DisplayServer.screen_get_refresh_rate(scr),
		["windowed", "borderless fullscreen", "exclusive fullscreen", "maximised"][v.window_mode]])
	# (The window's real size: with stretch mode canvas_items the viewport's
	# visible rect is the 1600x900 UI layout, not what 3D draws at.)
	var win := DisplayServer.window_get_size()
	lines.append("3D drawn at %dx%d (window %dx%d, 3D scale %.2f, %s)   %s   %s" % [win.x * vp.scaling_3d_scale, win.y * vp.scaling_3d_scale, win.x, win.y, vp.scaling_3d_scale,
		["bilinear", "FSR 1", "FSR 2"][v.scaling_mode], RenderingServer.get_video_adapter_name(), OS.get_processor_name()])
	lines.append("MSAA %s  TAA %s  SSAO %s  SSIL %s  SSR %s  SDFGI %s  glow %s  fog %s  sun shadow %s/%dm/%s splits  lamp shadows %s  your vsync %s  cap %s" % [
		["off", "2x", "4x", "8x"][v.msaa], v.taa, v.ssao, v.ssil, v.ssr, v.sdfgi, v.glow, v.vol_fog,
		Settings.SHADOW_SIZES[v.sun_shadow_size], int(v.sun_shadow_distance), ["1", "2", "4"][v.sun_shadow_splits],
		v.lamp_shadows, ["off", "on", "adaptive", "mailbox"][v.vsync], "none" if v.max_fps == 0 else str(Settings.FPS_CAPS[v.max_fps])])
	return "\n".join(lines)


func _show(text: String, where: Array) -> void:
	get_tree().paused = true
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = UiTheme.get_theme()
	layer.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	col.add_child(UiTheme.title("Benchmark finished", 40, UiTheme.ACCENT))
	var body := UiTheme.title(text, 20)
	col.add_child(body)
	if not where.is_empty():
		col.add_child(UiTheme.title("Saved to " + String(where[0]), 16, UiTheme.DIM))
	var again := UiTheme.big_button("Run it again", func():
		get_tree().paused = false
		Perf.start_benchmark())
	col.add_child(again)
	col.add_child(UiTheme.big_button("Back to the menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://game/ui/main_menu.tscn")))
	again.grab_focus.call_deferred()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
