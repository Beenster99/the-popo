extends Node
## Guns throw a flash, flame and smoke from the muzzle, sized by calibre.
var t


func test_bigger_guns_have_bigger_flashes() -> void:
	var service := MuzzleFx.size_for(EnemyGuns.NONE, Armoury.pistol_of(Armoury.make_kit(0, 0)).weight)
	var compact := MuzzleFx.size_for(EnemyGuns.NONE, Armoury.pistol_of(Armoury.make_kit(1, 0)).weight)
	var revolver := MuzzleFx.size_for(EnemyGuns.NONE, Armoury.pistol_of(Armoury.make_kit(3, 0)).weight)
	var sawn := MuzzleFx.size_for(EnemyGuns.SHOTGUN)
	t.check(compact < service and service < revolver and revolver < sawn,
		"compact %.2f < service %.2f < .357 %.2f < sawn-off %.2f" % [compact, service, revolver, sawn])


func test_flame_and_smoke_looks_build() -> void:
	MuzzleFx._make_meshes()
	t.check(MuzzleFx._star_mesh != null and MuzzleFx._tongue_mesh != null, "flame meshes")
	var tex := MuzzleFx._star_mat.albedo_texture
	var img := tex.get_image()
	var mid := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	t.check(mid.a > 0.9 and mid.r > 0.95 and mid.b > 0.7, "the middle of the flash is white hot: %s" % [mid])
	var corner := img.get_pixel(0, 0)
	t.check(corner.a < 0.05, "and the corners are clear: %s" % [corner])
	t.check(MuzzleFx._smoke_mat.albedo_texture != null, "smoke texture")


func test_an_officer_shot_flashes() -> void:
	ProtoWorld.ground(self, 60.0)
	var sounds := GameSounds.new()
	add_child(sounds)
	var o := Officer.new()
	o.peer_id = 1
	o.holstered = false
	o.position = Vector3(0, 0.05, 0)
	add_child(o)
	for i in 3:
		await get_tree().process_frame
	var n := MuzzleFx.count
	var cmd := {"move": Vector2.ZERO, "buttons": PlayerInput.AIM | PlayerInput.FIRE, "aim_yaw": 0.0, "aim_point": Vector3(0, 1.2, 10)}
	for i in 12:
		o.sim_step(cmd, 1.0 / 60.0)
		await get_tree().physics_frame
		await get_tree().process_frame
	t.check(MuzzleFx.count > n, "the shot made a muzzle flash")
