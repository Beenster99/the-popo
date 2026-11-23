class_name Armoury
extends Node
## Wave 3, Phase 3.5: progression. The station's pay buys kit at the
## armoury counter just inside the station door, for everyone (it's one
## station): pistols, upgrades, ammo types, tactical gear, vehicles, and new
## parts of the station itself. Each officer picks which pistol they carry
## and what it's loaded with. (Saving between sessions is Phase 4.4.)
##
## The host keeps what's been bought (one bit per item) and tells everyone;
## clients ask the host to buy or to change their kit.

enum Cat { PISTOL, UPGRADE, AMMO, GEAR, LOADOUT, UNDERCOVER, VEHICLE, STATION }
const CAT_NAMES := ["Pistols", "Bench", "Ammo", "Gear", "Loadout", "Undercover", "Vehicles", "Station"]

## Pistols (index = the pistol number an officer carries, bits 0-2 of kit).
## mag, dmg per bullet, gap s between shots, spread degrees, kick, reload s;
## weight: how heavy the shot sounds (pitch down, more boom).
const PISTOLS := [
	{"name": "Service pistol", "weight": 1.0, "mag": 15, "dmg": 25.0, "gap": 0.18, "spread": 0.4, "kick": 1.0, "reload": 1.7,
		"about": "The 9 mm you were issued. Fifteen rounds, does the job."},
	{"name": "Compact 9mm", "weight": 0.85, "mag": 12, "dmg": 22.0, "gap": 0.13, "spread": 0.6, "kick": 0.8, "reload": 1.35,
		"about": "Small and quick: fast follow-up shots and a fast reload."},
	{"name": "Heavy .45", "weight": 1.35, "mag": 8, "dmg": 40.0, "gap": 0.27, "spread": 0.35, "kick": 1.6, "reload": 1.9,
		"about": "Big slow rounds that knock people down."},
	{"name": ".357 Revolver", "weight": 1.6, "mag": 6, "dmg": 58.0, "gap": 0.42, "spread": 0.22, "kick": 2.1, "reload": 2.6,
		"about": "Six shots, each one a hammer blow. Slow to reload."},
	{"name": "Match pistol", "weight": 1.05, "mag": 10, "dmg": 30.0, "gap": 0.2, "spread": 0.12, "kick": 0.9, "reload": 1.6,
		"about": "Target barrel and trigger: hits exactly where you point."},
	{"name": "Machine pistol", "weight": 0.8, "mag": 20, "dmg": 17.0, "gap": 0.065, "spread": 1.1, "kick": 0.7, "reload": 1.8,
		"about": "Hold the trigger down. Empties in a second and a half."},
]
enum Ammo { STANDARD, HOLLOW, AP }
const AMMO_NAMES := ["Standard", "Hollow point", "Armour piercing"]

## Everything for sale. bit = its index here. A pistol item's "pistol" is
## its number in PISTOLS; needs = another item bought first.
const ITEMS := [
	{"cat": Cat.PISTOL, "pistol": 0, "price": 0},
	{"cat": Cat.PISTOL, "pistol": 1, "price": 600},
	{"cat": Cat.PISTOL, "pistol": 2, "price": 1200},
	{"cat": Cat.PISTOL, "pistol": 3, "price": 1800},
	{"cat": Cat.PISTOL, "pistol": 4, "price": 2200},
	{"cat": Cat.PISTOL, "pistol": 5, "price": 3000},
	{"cat": Cat.UPGRADE, "name": "Extended magazines", "price": 800, "about": "Half as many rounds again in every pistol."},
	{"cat": Cat.UPGRADE, "name": "Compensators", "price": 700, "about": "Less kick: the gun comes back on target quicker."},
	{"cat": Cat.UPGRADE, "name": "Match barrels", "price": 900, "about": "Tighter shots from every pistol."},
	{"cat": Cat.UPGRADE, "name": "Speed loaders", "price": 600, "about": "Reloads take a third less time."},
	{"cat": Cat.AMMO, "ammo": Ammo.HOLLOW, "name": "Hollow point", "price": 500, "about": "A third more damage to people."},
	{"cat": Cat.AMMO, "ammo": Ammo.AP, "name": "Armour piercing", "price": 900, "about": "Goes through car doors, glass and thin walls."},
	{"cat": Cat.GEAR, "name": "Body armour", "price": 1200, "about": "Plates under the vest: a third less damage from everything."},
	{"cat": Cat.GEAR, "name": "Ammo pouches", "price": 400, "about": "Carry 150 spare rounds instead of 90."},
	{"cat": Cat.VEHICLE, "name": "Interceptor", "price": 2500, "needs": 16, "about": "A tuned patrol car: quicker and faster flat out."},
	{"cat": Cat.VEHICLE, "name": "Prisoner van", "price": 3000, "needs": 16, "about": "Room for a whole gang in the back."},
	{"cat": Cat.STATION, "name": "Garage", "price": 1500, "about": "A vehicle garage beside the station. Needed for new vehicles."},
	{"cat": Cat.STATION, "name": "Firing range", "price": 1500, "about": "A range out the back of the station: timed target runs, and don't shoot the civilians."},
	# Phase 3.6: loadouts. Each officer carries one of these as well as the pistol.
	{"cat": Cat.LOADOUT, "gear": 1, "name": "Ammo backpack", "price": 700, "about": "Another 90 spare rounds on your back."},
	{"cat": Cat.LOADOUT, "gear": 2, "name": "Breach charges", "price": 900, "about": "Three small charges (2, then aim and fire): stick one on a door or a wall and stand back."},
	{"cat": Cat.LOADOUT, "gear": 3, "name": "C4", "price": 1800, "about": "Two big charges (2, then aim and fire). Brings down walls. Mind your mates."},
	{"cat": Cat.LOADOUT, "gear": 4, "name": "Tactical torch", "price": 300, "about": "A torch twice as bright that reaches twice as far."},
	# Phase 3.7: undercover.
	{"cat": Cat.UNDERCOVER, "name": "Plain clothes", "price": 1000, "about": "Street clothes from the locker. Crooks take you for anyone until you draw, shout, turn up in a marked car or hang about too close."},
	{"cat": Cat.UNDERCOVER, "name": "Unmarked car", "price": 2000, "needs": 16, "about": "A plain grey saloon. Nobody looks twice at it."},
	# Throwables (2026-11-23): every officer carries two of each the station owns.
	{"cat": Cat.GEAR, "name": "Smoke grenades", "price": 300, "about": "Two each. A thick grey cloud for half a minute: crooks can't shoot what they can't see. Throw with Q (pad: D-pad right), 3 picks which."},
	{"cat": Cat.GEAR, "name": "CS gas", "price": 500, "about": "Two each. A stinging cloud: anyone in it coughs and can't aim, and most crooks stumble out and give up. Mind your mates."},
	{"cat": Cat.GEAR, "name": "Flashbangs", "price": 700, "about": "Two each. A blinding flash and a deafening bang: anyone looking is stunned for a few seconds."},
	# v0.10.0: rooftops.
	{"cat": Cat.GEAR, "name": "Grapple hook", "price": 1500, "about": "Everyone carries a grapple launcher and rope. Aim at a roof edge and press the use key to be hauled up onto the roof. At a roof edge, press the use key to abseil down; W/S to climb or slide, Shift to drop fast, Space to swing in through a window."},
]
enum Gear { NONE, BACKPACK, BREACH, C4, TORCH }
const GEAR_NAMES := ["Nothing", "Ammo backpack", "Breach charges", "C4", "Tactical torch"]
const GEAR_ITEM := [-1, 18, 19, 20, 21]
const EXT_MAG := 6
const COMPENSATOR := 7
const MATCH_BARREL := 8
const SPEED_LOAD := 9
const HOLLOW := 10
const AP := 11
const ARMOUR := 12
const POUCHES := 13
const INTERCEPTOR := 14
const VAN := 15
const GARAGE := 16
const RANGE := 17
const PLAIN := 22
const UNMARKED := 23
const SMOKE_ITEM := 24
const GAS_ITEM := 25
const FLASH_ITEM := 26
## Item of each throwable (Grenades.Kind smoke, gas, flash).
const NADE_ITEMS := [SMOKE_ITEM, GAS_ITEM, FLASH_ITEM]
const GRAPPLE := 27

const MSG_BUY := 100      # client -> host: buy item (u8)
const MSG_KIT := 101      # client -> host: my kit (u8)
const MSG_OWNED := 102    # host -> all: what's been bought (u32)
const MSG_PLAIN := 106    # client -> host: plain clothes on or off (u8)

## Bought items, one bit each (the service pistol always). Static so the
## officers' sums work without a reference; reset when the city goes.
static var owned := 1
static var current: Armoury

signal changed

var dispatcher: Dispatcher
var sync: PawnSync
## Where the counter is (inside the station door).
var counter := Vector3.INF
const REACH := 2.4
var _send_t := 0.0


static func owns(i: int) -> bool:
	return (owned & (1 << i)) != 0


static func item_name(i: int) -> String:
	var it: Dictionary = ITEMS[i]
	return PISTOLS[it.pistol].name if it.has("pistol") else String(it.name)


static func item_about(i: int) -> String:
	var it: Dictionary = ITEMS[i]
	return PISTOLS[it.pistol].about if it.has("pistol") else String(it.about)


## Why item i can't be bought now ("" if it can).
static func why_not(i: int, pay: int) -> String:
	if owns(i):
		return "owned"
	var it: Dictionary = ITEMS[i]
	if it.has("needs") and not owns(it.needs):
		return "needs the %s" % item_name(it.needs)
	if pay < int(it.price):
		return "not enough pay"
	return ""


# --- one officer's kit: bits 0-2 pistol, 3-4 ammo, 5-7 loadout ----------------------

static func pistol_of(kit: int) -> Dictionary:
	return PISTOLS[clampi(kit & 7, 0, PISTOLS.size() - 1)]


static func ammo_of(kit: int) -> int:
	return (kit >> 3) & 3


static func gear_of(kit: int) -> int:
	return (kit >> 5) & 7


static func make_kit(pistol: int, ammo: int, gear := 0) -> int:
	return (pistol & 7) | ((ammo & 3) << 3) | ((gear & 7) << 5)


## Charges carried with this loadout, and how big they go off.
static func charges_max(kit: int) -> int:
	return {Gear.BREACH: 3, Gear.C4: 2}.get(gear_of(kit), 0)


static func charge_blast(kit: int) -> Dictionary:
	if gear_of(kit) == Gear.C4:
		return {"radius": 4.8, "damage": 280.0, "strength": 12.0, "fuse": 3.0}
	return {"radius": 1.9, "damage": 170.0, "strength": 7.0, "fuse": 2.0}


static func mag_size(kit: int) -> int:
	var m: int = pistol_of(kit).mag
	return int(ceil(m * 1.5)) if owns(EXT_MAG) else m


static func fire_gap(kit: int) -> float:
	return pistol_of(kit).gap


static func reload_time(kit: int) -> float:
	return float(pistol_of(kit).reload) * (0.67 if owns(SPEED_LOAD) else 1.0)


static func spread(kit: int) -> float:
	return float(pistol_of(kit).spread) * (0.6 if owns(MATCH_BARREL) else 1.0)


static func kick(kit: int) -> float:
	return float(pistol_of(kit).kick) * (0.6 if owns(COMPENSATOR) else 1.0)


static func damage(kit: int) -> float:
	return float(pistol_of(kit).dmg) * (1.33 if ammo_of(kit) == Ammo.HOLLOW else 1.0)


static func reserve_max(kit := 0) -> int:
	return (150 if owns(POUCHES) else 90) + (90 if gear_of(kit) == Gear.BACKPACK else 0)


static func armour_k() -> float:
	return 0.67 if owns(ARMOUR) else 1.0


# --- the node ------------------------------------------------------------------------

func _ready() -> void:
	owned = 1
	current = self
	Net.register(MSG_BUY, _on_buy)
	Net.register(MSG_KIT, _on_kit)
	Net.register(MSG_OWNED, _on_owned)
	Net.register(MSG_PLAIN, _on_plain)
	Net.register(Charge.MSG_CHARGE, _on_charge)


func _exit_tree() -> void:
	owned = 1
	if current == self:
		current = null
	Net.unregister(MSG_BUY)
	Net.unregister(MSG_KIT)
	Net.unregister(MSG_OWNED)
	Net.unregister(MSG_PLAIN)
	Net.unregister(Charge.MSG_CHARGE)


func _physics_process(delta: float) -> void:
	if not Net.is_host() or not Net.is_online():
		return
	_send_t -= delta
	if _send_t <= 0.0:
		_send_t = 2.0   # now and then, for anyone who joined late
		_broadcast()


func near_counter(p: Vector3) -> bool:
	return counter != Vector3.INF and p.distance_to(counter) < REACH


## Anyone: buy item i for the station.
func buy(i: int) -> void:
	if Net.is_host():
		_buy(i)
	else:
		var b := StreamPeerBuffer.new()
		b.put_u8(i)
		Net.send(1, MSG_BUY, b.data_array)


## Anyone: carry this pistol with this ammo.
func set_kit(pistol: int, ammo: int, gear := -1) -> void:
	var o0 := sync.my_pawn() as Officer if sync else null
	if gear < 0:
		gear = gear_of(o0.kit) if o0 else 0
	var k := make_kit(pistol, ammo, gear)
	if Net.is_host():
		var o := sync.my_pawn() as Officer if sync else null
		if o:
			o.set_kit(k)
	else:
		var b := StreamPeerBuffer.new()
		b.put_u8(k)
		Net.send(1, MSG_KIT, b.data_array)


func _buy(i: int) -> bool:
	if i < 0 or i >= ITEMS.size() or dispatcher == null:
		return false
	if why_not(i, dispatcher.pay) != "":
		return false
	dispatcher.pay -= int(ITEMS[i].price)
	dispatcher.paid.emit(-int(ITEMS[i].price), dispatcher.pay)
	owned |= 1 << i
	dispatcher.say("ARMOURY: the station's bought the %s." % item_name(i))
	# New throwables go straight into everyone's pouches.
	var nk := NADE_ITEMS.find(i)
	if nk >= 0:
		for n in get_tree().get_nodes_in_group("officers"):
			if n is Officer:
				(n as Officer).nades = Grenades.with_count((n as Officer).nades, nk, Grenades.CARRY)
	_broadcast()
	changed.emit()
	return true


func _broadcast() -> void:
	if Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_u32(owned)
		Net.broadcast(MSG_OWNED, b.data_array)


func _on_buy(_from: int, data: PackedByteArray) -> void:
	if Net.is_host() and data.size() >= 1:
		_buy(data[0])


func _on_kit(from: int, data: PackedByteArray) -> void:
	if not Net.is_host() or data.size() < 1 or sync == null:
		return
	var o := sync.pawns.get(from) as Officer
	if o:
		o.set_kit(data[0])


func _on_owned(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var m := b.get_u32()
	if m != owned:
		owned = m
		changed.emit()


func _on_charge(_from: int, data: PackedByteArray) -> void:
	if not Net.is_host():
		Charge.on_placed(get_parent(), data)


## Anyone: change into plain clothes, or back into uniform.
func set_plain(on: bool) -> void:
	if Net.is_host():
		var o := sync.my_pawn() as Officer if sync else null
		if o:
			o.set_plain(on)
	else:
		Net.send(1, MSG_PLAIN, PackedByteArray([1 if on else 0]))


func _on_plain(from: int, data: PackedByteArray) -> void:
	if not Net.is_host() or data.size() < 1 or sync == null:
		return
	var o := sync.pawns.get(from) as Officer
	if o:
		o.set_plain(data[0] == 1)
