class_name SfxSync
extends Node
## Plays gameplay sounds for everyone. The host decides that a shot or a hit
## happened, plays it, and tells the clients, who play the same sound with
## their own ears (so each player hears their own walls and rooms).

const MSG_SOUND := 40
const MSG_BULLET := 41       # host -> all: where a bullet went and what it hit
const MSG_HIT := 42          # host -> all: a punch, kick or barge landed
enum Kind { GUNSHOT, IMPACT, GLASS_BREAK }


func _ready() -> void:
	Sfx.ensure_buses()
	Net.register(MSG_SOUND, _on_msg)
	Net.register(MSG_BULLET, _on_bullet)
	Net.register(MSG_HIT, _on_hit)


func _exit_tree() -> void:
	Net.unregister(MSG_SOUND)
	Net.unregister(MSG_BULLET)
	Net.unregister(MSG_HIT)


## kind: 0/1 handgun, 2 shotgun (sent in the surface byte).
func gunshot(pos: Vector3, kind := 0) -> void:
	_send(Kind.GUNSHOT, pos, kind, 1.0)


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
	var sb := b.get_u8()
	var surface: String = Sfx.SURFACES[mini(sb, Sfx.SURFACES.size() - 1)]
	var strength := b.get_u8() / 100.0
	if kind == Kind.GUNSHOT:
		Sfx.shot(self, pos, sb)
	elif kind == Kind.GLASS_BREAK:
		Sfx.glass_break(self, pos)
	else:
		Sfx.impact(self, pos, surface, strength)


## Host: a bullet flew from a to b and hit a surface (what: 0 world, 1 a
## person, 2 nothing). Everyone hears the hit, and the crack if it passed
## their head. shooter: the peer who fired (0 for a suspect).
func bullet(a: Vector3, b: Vector3, surface: String, what: int, shooter := 0) -> void:
	var buf := StreamPeerBuffer.new()
	for v in [a, b]:
		buf.put_float(v.x)
		buf.put_float(v.y)
		buf.put_float(v.z)
	buf.put_u8(maxi(Sfx.SURFACES.find(surface), 0))
	buf.put_u8(what)
	buf.put_u32(shooter)
	if Net.is_host() and Net.is_online():
		Net.broadcast(MSG_BULLET, buf.data_array, Net.UNRELIABLE)
	buf.seek(0)
	_play_bullet(buf)


func _on_bullet(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_play_bullet(b)


func _play_bullet(b: StreamPeerBuffer) -> void:
	var a := Vector3(b.get_float(), b.get_float(), b.get_float())
	var e := Vector3(b.get_float(), b.get_float(), b.get_float())
	var surface: String = Sfx.SURFACES[mini(b.get_u8(), Sfx.SURFACES.size() - 1)]
	var what := b.get_u8()
	var shooter := b.get_u32()
	var mine := shooter != 0 and shooter == Net.my_id()
	Sfx.bullet(self, a, e, surface, what, mine)
	if mine and what == 1:
		Feel.hit_marker(get_tree())


## Host: a blow landed at pos. what: 0 a person, else the surface index + 1.
func melee_hit(pos: Vector3, what: int, hard := false) -> void:
	var buf := StreamPeerBuffer.new()
	buf.put_float(pos.x)
	buf.put_float(pos.y)
	buf.put_float(pos.z)
	buf.put_u8(what | (128 if hard else 0))
	if Net.is_host() and Net.is_online():
		Net.broadcast(MSG_HIT, buf.data_array, Net.UNRELIABLE)
	buf.seek(0)
	_play_hit(buf)


func _on_hit(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	_play_hit(b)


func _play_hit(b: StreamPeerBuffer) -> void:
	var pos := Vector3(b.get_float(), b.get_float(), b.get_float())
	var w := b.get_u8()
	var hard := (w & 128) != 0
	w &= 127
	if w == 0:
		Sfx.play(self, "punch", pos, 2.0 if hard else -1.0, 30.0, 0.08)
		Sfx.play(self, "body_hit", pos, -6.0, 25.0, 0.1)
	else:
		Sfx.impact(self, pos, Sfx.SURFACES[mini(w - 1, Sfx.SURFACES.size() - 1)], 1.0 if hard else 0.7)
