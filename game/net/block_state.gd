class_name BlockState
extends Node
## Phase 1.7: the block's damage, kept and shared.
##
## A friend who joins a game already going asks the host for the block as it
## is: which pieces have fallen and where the rubble lies, which props are
## broken and where the rest have been knocked to, and every dent, broken
## window and wreck on the cars. (Fires, calls, suspects and dropped guns come
## in the regular broadcasts, so they need nothing here.)
##
## The host also saves the same thing to disk every little while and when
## the game ends, so "Continue" brings the same block back as it was left.
##
## Wave 4, Phase 4.4: the save also keeps the station's career: pay, what's
## been bought, how far each story has got, the clock and the weather, and
## what each officer (by name) was carrying. Only the save has these: a
## friend joining gets them from the regular broadcasts.

const MSG_ASK := 95      # client -> host: send me the block as it is
const MSG_STATE := 96    # host -> client: here it is
## Wave 2: the city saves to its own file (the Wave 1 block test scene to
## block.save); the scene sets this before anything reads it.
static var save_path := "user://saves/city.save"
const MAGIC := 0x504F504F   # "POPO"
const VERSION := 4
const SAVE_EVERY := 20.0

signal caught_up

var world: DestructionWorld
var props: PropWorld
var cars: CarSync
var dispatch: Dispatcher
var seed_value := 0
var weather: CityWeather
var sync: PawnSync
## id -> player name, for whose kit is whose.
var name_of: Callable
## Kit waiting for an officer who hasn't turned up yet: name -> [kit, plain].
var kits := {}
var _career_hash := 0
## The tutorial city is never saved over the player's own.
var no_save := false
## Host: whether anything has changed since the last save.
var dirty := false
var _save_t := SAVE_EVERY


func _ready() -> void:
	Net.register(MSG_ASK, _on_ask)
	Net.register(MSG_STATE, _on_state)
	if world:
		world.piece_broken.connect(func(_id): dirty = true)
	if props:
		props.broke.connect(func(_id, _k, _at): dirty = true)
	if world:
		world.piece_restored.connect(func(_id): dirty = true)
	if sync:
		sync.pawn_spawned.connect(_give_kit)


func _exit_tree() -> void:
	Net.unregister(MSG_ASK)
	Net.unregister(MSG_STATE)
	if Net.is_host() and dirty:
		save()


## Client: once the block is built, ask the host for its damage.
func ask() -> void:
	if Net.is_online() and not Net.is_host():
		Net.send(1, MSG_ASK, PackedByteArray(), Net.RELIABLE)


func _on_ask(from: int, _data: PackedByteArray) -> void:
	if not Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.put_u32(seed_value)
	write(b)
	Net.send(from, MSG_STATE, b.data_array, Net.RELIABLE)
	Net.count("catch-ups")


func _on_state(from: int, data: PackedByteArray) -> void:
	if from != 1 or Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u32() != seed_value:
		return   # a different block: the host has moved on
	read(b, false)
	caught_up.emit()


func write(b: StreamPeerBuffer) -> void:
	world.write_state(b)
	props.write_state(b)
	cars.write_state(b)


func read(b: StreamPeerBuffer, from_save: bool) -> void:
	world.read_state(b)
	props.read_state(b)
	cars.read_state(b, from_save)


func _physics_process(delta: float) -> void:
	if not Net.is_host():
		return
	_save_t -= delta
	if _save_t <= 0.0:
		_save_t = SAVE_EVERY
		var ch := _career_changed()
		if dirty or _cars_changed() or ch:
			save()


func _cars_changed() -> bool:
	# Dents and wrecks don't signal; a cheap look at the dent count does.
	var n := 0
	for c in cars.cars:
		n += (c as Car).dent_log.size()
	var changed: bool = n != int(get_meta("dents", -1))
	set_meta("dents", n)
	return changed


func _career_changed() -> bool:
	var b := StreamPeerBuffer.new()
	write_career(b)
	var h := hash(b.data_array)
	var changed := h != _career_hash
	_career_hash = h
	return changed


# --- Career (Phase 4.4) ----------------------------------------------------------

func write_career(b: StreamPeerBuffer) -> void:
	var m: Missions = dispatch.missions if dispatch else null
	var st: Stories = dispatch.stories if dispatch else null
	b.put_u32(dispatch.pay if dispatch else 0)
	b.put_u32(Armoury.owned)
	b.put_float(m.minute if m else Missions.START_MINUTE)
	b.put_u8(weather.kind if weather else 0)
	b.put_float(weather.wet if weather else 0.0)
	var chains: Array = st.progress.keys() if st else []
	b.put_u8(chains.size())
	for id in chains:
		var pr: Dictionary = st.progress[id]
		b.put_utf8_string(str(id))
		b.put_u8(pr.step)
		b.put_u8(pr.escapes)
		b.put_u8((1 if pr.done else 0) | (2 if pr.dead else 0))
	# Kit by officer name; anyone who isn't here keeps what they had.
	var all := kits.duplicate()
	if sync:
		for id in sync.pawns:
			var o := sync.pawns[id] as Officer
			var nm: String = name_of.call(id) if name_of.is_valid() else ""
			if o and nm != "":
				all[nm] = [o.kit, o.plain]
	b.put_u8(all.size())
	for nm in all:
		b.put_utf8_string(nm)
		b.put_u8(all[nm][0])
		b.put_u8(1 if all[nm][1] else 0)


func read_career(b: StreamPeerBuffer) -> void:
	var pay := b.get_u32()
	var owned := b.get_u32()
	var minute := b.get_float()
	var wk := b.get_u8()
	var wet := b.get_float()
	if dispatch:
		dispatch.pay = pay
		if dispatch.missions:
			dispatch.missions.minute = fposmod(minute, Missions.DAY_MINUTES)
	if owned != Armoury.owned:
		Armoury.owned = owned | 1
		if Armoury.current:
			Armoury.current._broadcast()
			Armoury.current.changed.emit()
	if weather:
		weather.kind = wk & 3
		weather._target_rain = float([0.0, 0.0, 0.6, 1.0][weather.kind])
		weather.rain = weather._target_rain
		weather.wet = wet
	var st: Stories = dispatch.stories if dispatch else null
	for i in b.get_u8():
		var id := b.get_utf8_string()
		var step := b.get_u8()
		var esc := b.get_u8()
		var flags := b.get_u8()
		if st and st.progress.has(id):
			st.progress[id] = {"step": step, "escapes": esc, "done": (flags & 1) != 0, "dead": (flags & 2) != 0}
	kits = {}
	for i in b.get_u8():
		var nm := b.get_utf8_string()
		var k := b.get_u8()
		kits[nm] = [k, b.get_u8() == 1]
	if sync:
		for id in sync.pawns:
			_give_kit(id, sync.pawns[id])


## Host: an officer turns up; if they carried something last time, they
## carry it again.
func _give_kit(id: int, p: Node) -> void:
	if not Net.is_host() or not (p is Officer) or not name_of.is_valid():
		return
	var nm: String = name_of.call(id)
	if not kits.has(nm):
		return
	var o := p as Officer
	o.set_kit(int(kits[nm][0]))
	o.set_plain(bool(kits[nm][1]))


# --- Saving ----------------------------------------------------------------------

func save() -> bool:
	if no_save:
		return false
	var b := StreamPeerBuffer.new()
	b.put_u32(MAGIC)
	b.put_u16(VERSION)
	b.put_utf8_string(str(ProjectSettings.get_setting("application/config/version", "dev")))
	b.put_u32(seed_value)
	b.put_u8(KitLibrary.detail)
	b.put_64(int(Time.get_unix_time_from_system()))
	write(b)
	write_career(b)
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save the block: %s" % FileAccess.get_open_error())
		return false
	f.store_buffer(b.data_array)
	f.close()
	dirty = false
	return true


## What is saved, without loading it: {seed, saved (unix time), version}, or
## empty when there is no usable save.
static func peek() -> Dictionary:
	var b := _open()
	if b == null:
		return {}
	var ver := b.get_utf8_string()
	var s := b.get_u32()
	var detail := b.get_u8()
	var at := b.get_64()
	return {"seed": s, "detail": detail, "saved": at, "version": ver}


static func has_save() -> bool:
	return not peek().is_empty()


static func _open() -> StreamPeerBuffer:
	if not FileAccess.file_exists(save_path):
		return null
	var data := FileAccess.get_file_as_bytes(save_path)
	if data.size() < 16:
		return null
	var b := StreamPeerBuffer.new()
	b.data_array = data
	if b.get_u32() != MAGIC or b.get_u16() != VERSION:
		return null
	return b


## Host: puts the saved damage back on a block built from the saved seed.
func load_save() -> bool:
	var b := _open()
	if b == null:
		return false
	b.get_utf8_string()
	if b.get_u32() != seed_value or b.get_u8() != KitLibrary.detail:
		return false
	b.get_64()
	read(b, true)
	if b.get_available_bytes() > 0:
		read_career(b)
	_career_changed()
	dirty = false
	return true


static func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(save_path)
