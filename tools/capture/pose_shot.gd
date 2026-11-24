extends Node
## Civilian poses: idle, walk and run with nothing in the hands.
##   xvfb-run -a godot --path . res://tools/capture/pose_shot.tscn -- <out_dir>

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var first := int(a[2]) if a.size() > 2 else 0
	var count := int(a[3]) if a.size() > 3 else 99
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	get_tree().root.size = Vector2i(1000, 520)
	ProtoWorld.environment(self)
	ProtoWorld.sun(self)
	ProtoWorld.ground(self, 30.0)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.5, 3.5 + 1.9 * count)
	cam.look_at(Vector3(0, 0.95, 0))
	cam.current = true
	cam.fov = 28
	var poses := [["idle", "civ_phone", 0.0], ["idle", "civ_texting", 0.0], ["walk", "civ_pockets", 1.3], ["idle", "civ_arms_folded", 0.0], ["walk", "civ_hands_behind", 1.0], ["idle", "work_dig", 0.0], ["idle", "work_hammer", 0.0]]
	poses = poses.slice(first, first + count)
	cam.position = Vector3(0, 1.5, 3.5 + 1.9 * poses.size())
	cam.look_at(Vector3(0, 0.95, 0))
	var rigs: Array = []
	for i in poses.size():
		var r := OfficerRig.new()
		r.position = Vector3((i - (poses.size() - 1) * 0.5) * 1.3, 0, 0)
		r.rotation_degrees.y = 35
		add_child(r)
		rigs.append(r)
	await get_tree().process_frame
	for i in poses.size():
		SuspectLook.apply(rigs[i].model, 5 + i)
		EnemyGuns.show_in_hand(rigs[i].model, EnemyGuns.NONE)
	var t := float(OS.get_cmdline_user_args()[1]) if OS.get_cmdline_user_args().size() > 1 else 0.6
	for f in int(t * 60):
		for i in poses.size():
			rigs[i].update_pose(poses[i][0], poses[i][1], poses[i][2], 1.0 / 60.0)
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out + "/poses_%d.png" % first)
	get_tree().quit()
