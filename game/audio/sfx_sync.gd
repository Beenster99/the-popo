class_name SfxSync
extends Node
## Plays gameplay sounds for everyone. The host decides that a shot or a hit
## happened, plays it, and tells the clients, who play the same sound with
## their own ears (so each player hears their own walls and rooms).

const MSG_SOUND := 40
enum Kind { GUNSHOT, IMPACT, GLASS_BREAK }


func _ready() -> void:
	Sfx.ensure_buses()
	Net.register(MSG_SOUND, _on_msg)


func _exit_tree() -> void:
	Net.unregister(MSG_SOUND)


func gunshot(pos: Vector3) -> void:
	_send(Kind.GUNSHOT, pos, 0, 1.0)


func impact(pos: Vector3, surface: String, strength := 1.0) -> void:
	_send(Kind.IMPACT, pos, maxi(Sfx.SURFACES.find(surface), 0), strength)


func glass_break(pos: Vector3) -> void:
	_send(Kind.GLASS_BREAK, pos, 0, 1.0)


func _send(kind: int, pos: Vector3, surface: int, strength: float) -> void:
	var b := StreamPeerBuffer.new()
	b.put_u8(kind)
	b.put_float(pos.x)
	b.put_float(pos.y)
	b.put_float(pos.z)
	b.put_u8(surface)
	b.put_u8(clampi(int(strength * 100.0), 0, 255))
	if Net.is_host():
		Net.broadcast(MSG_SOUND, b.data_array, Net.UNRELIABLE)
	b.seek(0)
	_play(b)


func _on_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_play(b)


func _play(b: StreamPeerBuffer) -> void:
	var kind := b.get_u8()
	var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
	var surface: String = Sfx.SURFACES[mini(b.get_u8(), Sfx.SURFACES.size() - 1)]
	var strength := b.get_u8() / 100.0
	if kind == Kind.GUNSHOT:
		Sfx.gunshot(self, pos)
	elif kind == Kind.GLASS_BREAK:
		Sfx.glass_break(self, pos)
	else:
		Sfx.impact(self, pos, surface, strength)
