extends Node
## Performance overlay and benchmark (autoload "Perf"), v0.8.1.
##
## F11 shows or hides the overlay: frame rate, the slowest 1% of frames, how
## long the CPU (game code, physics) and the graphics card took per frame,
## draw calls, and how much of the city is awake.
##
## The benchmark (main menu, Benchmark) builds the same city every time
## (seed BENCH_SEED), flies a camera down its streets and up over downtown,
## sets off one blast on the way, and writes what it measured to
## ThePopo-benchmark.txt beside the game (and in the user folder), so the
## numbers can be compared between builds and settings.

const BENCH_SEED := 424242
const REPORT_NAME := "ThePopo-benchmark.txt"

var overlay_on := false
## Set by the menu; City reads it once when it builds.
var benchmark_pending := false

var _layer: CanvasLayer
var _label: Label
var _frames := PackedFloat32Array()   # last few seconds of frame times (ms)
var _frame_i := 0
var _t := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 95
	add_child(_layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(12, 12)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", sb)
	_layer.add_child(panel)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", Color("e8f0e0"))
	panel.add_child(_label)
	_layer.visible = false
	_frames.resize(600)
	_frames.fill(0.0)
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo and k.keycode == KEY_F11:
		overlay_on = not overlay_on
		_layer.visible = overlay_on


func _process(delta: float) -> void:
	_frames[_frame_i] = delta * 1000.0
	_frame_i = (_frame_i + 1) % _frames.size()
	if not overlay_on:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	_label.text = report_lines()


## The slowest 1% of the frames in the window, as a frame rate.
func low_1pct() -> float:
	var s := _frames.duplicate()
	s.sort()
	var worst := s[int(s.size() * 0.99)]
	return 1000.0 / maxf(worst, 0.001)


func gpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid())


func render_cpu_ms() -> float:
	return RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()) \
		+ RenderingServer.get_frame_setup_time_cpu()


func report_lines() -> String:
	var fps := Engine.get_frames_per_second()
	var vp := get_viewport()
	var size := Vector2(DisplayServer.window_get_size()) * vp.scaling_3d_scale
	var t := "%d fps   1%% low %d fps   frame %.1f ms" % [fps, low_1pct(), 1000.0 / maxf(fps, 1.0)]
	t += "\nGPU %.1f ms   render CPU %.1f ms   game code %.1f ms   physics %.1f ms" % [
		gpu_ms(), render_cpu_ms(),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	t += "\ndraw calls %d   objects %d   triangles %dk" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
	t += "\nphysics bodies awake %d   nodes %d   video memory %d MB" % [
		Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS),
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)]
	t += "\n3D at %dx%d (scale %.2f)   %s" % [size.x, size.y, vp.scaling_3d_scale, RenderingServer.get_video_adapter_name()]
	t += "\nF11 hides this"
	return t


## Main menu: start the benchmark.
func start_benchmark() -> void:
	benchmark_pending = true
	get_tree().change_scene_to_file(Scenes.GAME)


## Writes a finished benchmark's report beside the game and in the user
## folder. Returns where it went.
func save_report(text: String) -> Array:
	var out: Array = []
	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var dirs: Array = ["user://"]
	if not OS.has_feature("editor"):
		dirs.push_front(OS.get_executable_path().get_base_dir())
	for d in dirs:
		var path: String = String(d).path_join(REPORT_NAME)
		var old := ""
		if FileAccess.file_exists(path):
			old = FileAccess.get_file_as_string(path)
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			continue
		f.store_string("=== " + stamp + " ===\n" + text + "\n\n" + old)
		f.close()
		out.append(ProjectSettings.globalize_path(path))
	return out
