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

const MSG_ASK := 95      # client -> host: send me the block as it is
const MSG_STATE := 96    # host -> client: here it is
const SAVE_PATH := "user://saves/block.save"
const MAGIC := 0x504F504F   # "POPO"
const VERSION := 3
const SAVE_EVERY := 20.0

signal caught_up

var world: DestructionWorld
var props: PropWorld
var cars: CarSync
var dispatch: Dispatcher
var seed_value := 0
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
		if dirty or _cars_changed():
			save()


func _cars_changed() -> bool:
	# Dents and wrecks don't signal; a cheap look at the dent count does.
	var n := 0
	for c in cars.cars:
		n += (c as Car).dent_log.size()
	var changed: bool = n != int(get_meta("dents", -1))
	set_meta("dents", n)
	return changed


# --- Saving ----------------------------------------------------------------------

func save() -> bool:
	var b := StreamPeerBuffer.new()
	b.put_u32(MAGIC)
	b.put_u16(VERSION)
	b.put_utf8_string(str(ProjectSettings.get_setting("application/config/version", "dev")))
	b.put_u32(seed_value)
	b.put_u8(KitLibrary.detail)
	b.put_64(int(Time.get_unix_time_from_system()))
	write(b)
	DirAccess.make_dir_recursive_absolute(SAVE_PATH.get_base_dir())
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
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
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var data := FileAccess.get_file_as_bytes(SAVE_PATH)
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
	dirty = false
	return true


static func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
