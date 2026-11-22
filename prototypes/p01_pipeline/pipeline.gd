extends Node3D
## Phase 0.1 pipeline check: a prop made by script in Blender appears in Godot
## with working collision. Crates rain onto three dumpsters every few seconds.

const DUMPSTER := preload("res://assets/models/props/dumpster.glb")

var _cam: IsoCamera
var _t := 0.0


func _ready() -> void:
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 40.0)
	for i in 3:
		var d: Node3D = DUMPSTER.instantiate()
		d.position = Vector3(-3.5 + i * 3.5, 0, 0)
		d.rotation_degrees.y = i * 25.0
		Cel.apply(d)
		add_child(d)
	_cam = IsoCamera.new()
	_cam.zoom = 12.0
	add_child(_cam)
	var hud := Label.new()
	hud.text = "Phase 0.1: dumpster built by tools/blender/build_pipeline_test.py, collision from its -convcolonly box. Esc to go back."
	hud.position = Vector2(16, 16)
	var cl := CanvasLayer.new()
	cl.add_child(hud)
	add_child(cl)


func _physics_process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.4
		var c := ProtoWorld.rigid_box(self, Vector3.ONE * 0.4, Vector3(randf_range(-5, 5), 6, randf_range(-1, 1)), Color.from_hsv(randf(), 0.5, 0.9), 2.0)
		get_tree().create_timer(12.0).timeout.connect(c.queue_free)
