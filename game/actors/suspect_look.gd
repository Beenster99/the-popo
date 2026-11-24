class_name SuspectLook
extends RefCounted
## Dresses the officer model as a civilian: no vest, badge, radio, belt kit
## or cap peak; a hoodie or tee, jeans or joggers, trainers, bare hands and
## a beanie, in colours picked from the look number.

const HIDE := ["vest", "badge", "radio", "holster", "pouch", "buckle", "cap_peak", "cap_letters", "cap_button", "spare_mag"]
const SHIRTS := [Color("b8322c"), Color("6f7378"), Color("3f6b3a"), Color("2a2a30"), Color("d9b33c"), Color("e6e2d8"),
	Color("7a4a8c"), Color("2f5f8a"), Color("2a8a86"), Color("d9772a"), Color("c96a8e"), Color("6b6b3a"), Color("8fb4d9"), Color("3a2a22")]
const TROUSERS := [Color("3b5677"), Color("232327"), Color("8a7c5e"), Color("55585e"), Color("2c3e5c"), Color("b8a47a"), Color("5a3a2a")]
const SKIN := [Color("e8c3a0"), Color("c99a74"), Color("9a6b4a"), Color("6a4630"), Color("f0d2b8")]
## Looks from WORKER up are council workers: hi-vis vest and a hard hat.
const WORKER := 240
## Looks from PARAMEDIC up are ambulance crew: dark green uniform, a yellow
## hi-vis vest, no hat.
const PARAMEDIC := 248
const MEDIC_GREEN := Color("2c4a34")
const MEDIC_VIS := Color("e8e23a")
const HI_VIS := Color("ff8a1a")
const HARD_HAT := Color("f2c81e")
const HATS := [Color("1f1f24"), Color("6b1e22"), Color("2b3a55"), Color("4a4a42"), Color("c8c2b4"), Color("d9772a"), Color("2a8a86")]


static func colours(look: int) -> Dictionary:
	var r := RandomNumberGenerator.new()
	r.seed = look * 2654435761 + 17
	return {
		"shirt": SHIRTS[r.randi_range(0, SHIRTS.size() - 1)],
		"trousers": TROUSERS[r.randi_range(0, TROUSERS.size() - 1)],
		"skin": SKIN[r.randi_range(0, SKIN.size() - 1)],
		"hat": HATS[r.randi_range(0, HATS.size() - 1)],
		"beanie": r.randf() < 0.6,
		"shoes": Color("ececec") if r.randf() < 0.4 else Color("26262a"),
	}


static func apply(model: Node, look: int) -> void:
	if model == null:
		return
	var c := colours(look)
	var worker := look >= WORKER
	var medic := look >= PARAMEDIC
	if medic:
		c.beanie = false
		c.shirt = MEDIC_GREEN
		c.trousers = MEDIC_GREEN
		c.shoes = Color("1a1a1c")
	elif worker:
		c.beanie = true
		c.hat = HARD_HAT
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var nm := String(mi.name)
		if worker and nm == "vest":
			mi.visible = true
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, Cel.material(MEDIC_VIS if medic else HI_VIS, true, 0.012))
			continue
		if nm in HIDE or ((nm == "cap") and not c.beanie):
			mi.visible = false
			continue
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var key := src.resource_name if src else ""
			var col: Variant = null
			match key:
				"shirt": col = c.shirt
				"trousers": col = c.trousers
				"skin": col = c.skin
				"cap": col = c.hat
				"boots":
					if nm.begins_with("hand") or nm.begins_with("thumb"):
						col = c.skin
					elif nm.begins_with("brow"):
						col = Color("2a2018")
					elif nm.begins_with("boot"):
						col = c.shoes
					else:
						col = Color("26262a")
			if col != null:
				mi.set_surface_override_material(i, Cel.material(col, true, 0.012))
