extends Node
## The shortcut bar along the bottom (beenster, 2026-11-24).
var t


func _officer(pos: Vector3) -> Officer:
	var o := Officer.new()
	o.peer_id = 1
	o.holstered = false
	o.position = pos
	add_child(o)
	return o


func _run(o: Officer, buttons: int, frames: int) -> void:
	for i in frames:
		o.sim_step({"move": Vector2.ZERO, "buttons": buttons, "aim_yaw": 0.0, "aim_point": Vector3(0, 1, 10)}, 1.0 / 60.0)
		await get_tree().physics_frame


func test_fire_uses_what_is_in_hand() -> void:
	var P := PlayerInput
	t.check(P.slot_buttons(P.FIRE | P.AIM, P.Slot.PISTOL) == P.FIRE | P.AIM, "pistol: fire")
	t.check(P.slot_buttons(P.FIRE, P.Slot.GAS) == P.THROW, "grenade: throw")
	t.check(P.slot_buttons(P.FIRE, P.Slot.AID) == P.AID, "first aid: aid")
	t.check(P.slot_buttons(P.FIRE | P.AIM, P.Slot.GRAPPLE) == P.GRAPPLE | P.AIM, "grapple: hook")
	t.check(P.slot_buttons(P.AIM, P.Slot.GAS) == P.AIM, "nothing without fire")


func test_empty_slots_are_refused() -> void:
	ProtoWorld.ground(self, 40.0)
	var o := _officer(Vector3(0, 0.05, 0))
	await get_tree().process_frame
	var P := PlayerInput
	var owned := Armoury.owned
	Armoury.owned = 1   # nothing bought
	P.slot = P.Slot.PISTOL
	P.pick_slot(P.Slot.SMOKE, o)
	t.check(P.slot == P.Slot.PISTOL and P.slot_refused == P.Slot.SMOKE, "no smoke bought: refused")
	P.pick_slot(P.Slot.GRAPPLE, o)
	t.check(P.slot == P.Slot.PISTOL, "no grapple bought: refused")
	o.pouch = 2
	P.pick_slot(P.Slot.AID, o)
	t.check(P.slot == P.Slot.AID, "first aid picked")
	P.step_slot(1, o)
	t.check(P.slot == P.Slot.PISTOL, "next skips the empty ones round to the pistol")
	Armoury.owned = owned | (1 << Armoury.GAS_ITEM)
	o.nades = Grenades.full_pouch()
	P.pick_slot(P.Slot.GAS, o)
	t.check(P.slot == P.Slot.GAS and P.nade_kind == 1, "CS gas in hand and picked to throw")
	Armoury.owned = owned
	P.slot = P.Slot.PISTOL


## Holding fire with first aid in hand patches you up, and never cuffs or
## uses a car's boot.
func test_first_aid_from_the_bar() -> void:
	ProtoWorld.ground(self, 40.0)
	var o := _officer(Vector3(0, 0.05, 0))
	await _run(o, 0, 5)
	o.injuries = Officer.BLEED
	o.hp = 50.0
	var before := o.pouch
	await _run(o, PlayerInput.AID, int(Officer.TREAT_SELF * 60.0) + 10)
	t.check(o.injuries == 0, "wound patched")
	t.check(o.pouch == before - 1, "one dressing used")
