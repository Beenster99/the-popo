extends Node
## People going about their day stand relaxed: phone, texting, pockets,
## folded arms, hands behind, digging or hammering. Only police and crooks
## hold guns.
var t


func test_daily_clips_loaded() -> void:
	var m: Node = OfficerRig.MODEL.instantiate()
	var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
	var sk: Skeleton3D = m.find_children("*", "Skeleton3D", true, false)[0]
	var lib := OfficerClips.library(ap, sk)
	for n in ["civ_phone", "civ_texting", "civ_pockets", "civ_arms_folded", "civ_hands_behind", "work_dig", "work_hammer"]:
		t.check(lib.has_animation(n), n + " loaded")
		t.check(n in OfficerRig.UPPER_STATES, n + " is an upper-body state")
		t.check(n not in OfficerClips.mocap_clips, n + " is not counted as mocap")
	m.free()


func test_daily_upper_never_a_gun_hold() -> void:
	var seen := {}
	for look in 60:
		for sp in [0.0, 1.2, 3.5]:
			for worker in [false, true]:
				var u := Suspect.daily_upper(look, worker, sp)
				t.check(u not in ["aim_hold", "ready_hold"], "no gun hold (%s)" % u)
				seen[u] = true
	t.check(seen.size() >= 6, "a mix of everyday poses (%d)" % seen.size())
	t.check(Suspect.daily_upper(4, true, 0.0) in ["work_dig", "work_hammer"], "a worker stood still works")
	t.check(Suspect.daily_upper(5, false, 3.5) == "none", "running: arms free")


func test_civilian_shows_no_gun_and_holds_phone() -> void:
	ProtoWorld.ground(self, 30.0)
	var r := OfficerRig.new()
	add_child(r)
	await get_tree().process_frame
	EnemyGuns.show_in_hand(r.model, EnemyGuns.NONE)
	for i in 5:
		r.update_pose("idle", "civ_phone", 0.0, 0.016)
		await get_tree().process_frame
	var slide := r.model.find_child("gun_slide", true, false) as Node3D
	t.check(slide == null or not slide.visible, "gun hidden")
	var phone := r.find_child("held_phone", true, false) as Node3D
	t.check(phone != null and phone.is_visible_in_tree(), "phone in hand")
	r.update_pose("idle", "work_dig", 0.0, 0.016)
	await get_tree().process_frame
	t.check(phone != null and not phone.is_visible_in_tree(), "phone put away for the shovel")
	var shovel := r.find_child("held_shovel", true, false) as Node3D
	t.check(shovel != null and shovel.is_visible_in_tree(), "shovel out")
	r.queue_free()
