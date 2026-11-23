extends Node
## The armoury's 3D inspection bench: every pistol has a model, and every
## bench upgrade shows up on it as its own part.
var t


func _vis(b: GunBench, p: int, part: String) -> bool:
	var n := b.find_child("p%d_%s" % [p, part], true, false) as Node3D
	return n != null and n.is_visible_in_tree()


func test_every_pistol_and_part() -> void:
	var b := GunBench.new()
	b.size = Vector2(320, 200)
	add_child(b)
	await get_tree().process_frame
	var all := (1 << Armoury.EXT_MAG) | (1 << Armoury.COMPENSATOR) | (1 << Armoury.MATCH_BARREL) | (1 << Armoury.SPEED_LOAD) | (1 << GunBench.TORCH)
	for p in Armoury.PISTOLS.size():
		b.show_gun(p, 0)
		t.check(_vis(b, p, "mag_std") and _vis(b, p, "barrel_std"), "pistol %d bare: factory magazine and barrel" % p)
		t.check(not _vis(b, p, "mag_ext") and not _vis(b, p, "comp") and not _vis(b, p, "comp_m") and not _vis(b, p, "loader") and not _vis(b, p, "torch"), "pistol %d bare: no upgrades" % p)
		b.show_gun(p, all)
		t.check(_vis(b, p, "mag_ext") and not _vis(b, p, "mag_std"), "pistol %d: extended magazine swapped in" % p)
		t.check(_vis(b, p, "barrel_match") and not _vis(b, p, "barrel_std"), "pistol %d: match barrel swapped in" % p)
		t.check(_vis(b, p, "comp_m") and not _vis(b, p, "comp"), "pistol %d: compensator on the match barrel" % p)
		t.check(_vis(b, p, "loader") and _vis(b, p, "torch"), "pistol %d: speed loader and torch" % p)
		for q in Armoury.PISTOLS.size():
			if q != p:
				t.check(not _vis(b, q, "mag_ext") and not _vis(b, q, "mag_std"), "only pistol %d on the bench" % p)
	b.queue_free()
