extends Node3D
## Muzzle flash check: an officer fires the service pistol, the .357 and a
## sawn-off next to a wall, by day and at night; saves the flash frame and
## the smoke half a second later for each.
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . res://tools/capture/muzzle_shot.tscn -- <out_dir>

var sounds: GameSounds
var me: Officer
var sun: DirectionalLight3D
var env: Environment


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	ProtoWorld.ground(self, 80.0)
	# A wall behind the gun, to show the flash lighting things up.
	var wall := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(10, 4, 0.3)
	wall.mesh = bm
	wall.material_override = Cel.material(Color("a89c8c"), false)
	add_child(wall)
	wall.position = Vector3(0, 2, -1.6)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.glow_enabled = true
	env.glow_intensity = 0.8
	we.environment = env
	add_child(we)
	sounds = GameSounds.new()
	sounds.pawn_getter = func(): return me
	add_child(sounds)
	me = Officer.new()
	me.peer_id = 1
	me.holstered = false
	me.position = Vector3(0, 0.05, 0)
	add_child(me)
	var cam := Camera3D.new()
	cam.fov = 45.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(1.2, 1.7, 3.3)
	cam.look_at(Vector3(1.4, 1.2, 0))
	for i in 20:
		await get_tree().process_frame
	var setups := [["service", Armoury.make_kit(0, 0), EnemyGuns.NONE], ["revolver", Armoury.make_kit(3, 0), EnemyGuns.NONE], ["shotgun", 0, EnemyGuns.SHOTGUN]]
	for night in [false, true]:
		_light(night)
		for s in setups:
			me.kit = s[1]
			me.gun = s[2]
			me.gun_ammo = 5 if s[2] != EnemyGuns.NONE else 0
			me.ammo = 15
			await _shoot("%s/muzzle_%s_%s" % [out, s[0], "night" if night else "day"])
	print("muzzle shots ", MuzzleFx.count)
	get_tree().quit()


func _light(night: bool) -> void:
	sun.light_energy = 0.08 if night else 1.2
	env.background_color = Color(0.03, 0.04, 0.07) if night else Color(0.55, 0.62, 0.7)
	env.ambient_light_color = Color(0.1, 0.11, 0.16) if night else Color(0.6, 0.6, 0.65)
	MuzzleFx.smoke_shade = 0.32 if night else 1.0


func _shoot(path: String) -> void:
	# Aim off to the right, along the wall.
	var aim := Vector3(10, 1.3, 0)
	var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM, "aim_yaw": PI * 0.5, "aim_point": aim}
	for i in 40:
		me.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame
	var n := MuzzleFx.count
	cmd.buttons = PlayerInput.AIM | PlayerInput.FIRE
	# Slow time right down round the shot: the software renderer here is far
	# slower than a real PC and the flame would be gone before a frame drew.
	Engine.time_scale = 0.02
	for i in 600:
		if i % 4 == 0:
			me.sim_step(cmd, 1.0 / 60.0)
		await get_tree().process_frame
		if MuzzleFx.count != n:
			break
	cmd.buttons = PlayerInput.AIM
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path + "_flash.png")
	Engine.time_scale = 1.0
	for i in 30:
		me.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path + "_smoke.png")
	for i in 90:
		me.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame
