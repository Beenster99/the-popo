extends SceneTree
## Headless test runner. Usage:
##   godot --headless --path . -s res://tests/runner.gd [-- filter]
## Runs every test_* method in res://tests/unit/test_*.gd. A test method may be
## a coroutine (await frames). Exits with code 1 if any test fails.

## Counts engine and script errors raised while a test runs, so a test that
## crashes part-way is reported as a failure instead of passing silently.
class ErrorCounter extends Logger:
	var count := 0
	var last := ""
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, editor_notify: bool, error_type: int, script_backtrace: Array[ScriptBacktrace]) -> void:
		count += 1
		last = "%s %s (%s:%d)" % [code, rationale, file, line]
	func _log_message(_message: String, _error: bool) -> void:
		pass

var errors := ErrorCounter.new()
var failures := 0
var passed := 0
var _current := ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.add_logger(errors)
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var dir := DirAccess.open("res://tests/unit")
	var files := Array(dir.get_files()).filter(func(f): return f.begins_with("test_") and f.ends_with(".gd"))
	files.sort()
	for f in files:
		var script: GDScript = load("res://tests/unit/" + f)
		if script == null or not script.can_instantiate():
			failures += 1
			printerr("  FAIL ", f, "  does not compile")
			continue
		for m in script.get_script_method_list():
			var mname: String = m.name
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (f + ":" + mname).contains(filter):
				continue
			_current = f + ":" + mname
			var inst: Object = script.new()
			if inst is Node:
				root.add_child(inst)
			inst.set("t", self)
			var before := failures
			var errs_before := errors.count
			await inst.call(mname)
			if errors.count > errs_before:
				check(false, "%d engine/script error(s), last: %s" % [errors.count - errs_before, errors.last])
			if inst is Node:
				inst.queue_free()
			if failures == before:
				passed += 1
				print("  ok   ", _current)
	print("\n%d passed, %d failed" % [passed, failures])
	quit(1 if failures > 0 else 0)


func check(cond: bool, msg := "") -> void:
	if not cond:
		failures += 1
		printerr("  FAIL ", _current, "  ", msg)


func near(a: float, b: float, eps: float, msg := "") -> void:
	check(absf(a - b) <= eps, "%s (%f vs %f)" % [msg, a, b])
