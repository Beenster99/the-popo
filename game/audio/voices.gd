class_name Voices
extends Node
## Shouted orders and what the crooks shout back. The host decides who says
## what (Officer.shout picks the order, Suspect.on_shout the answer), plays it
## and tells the clients, who play the same line from the same mouth with
## their own ears. The words also pop up over the speaker's head.
##
## The recordings are placeholders made by tools/audio/make_voices.py; an
## ElevenLabs take dropped in with the same file name replaces one.

const MSG_VOICE := 140        # host -> all: who (officer or suspect) said which line
const VOICE_DIR := "res://assets/audio/voice/"
const VOICES := 3             # recordings of every line (one voice per player)
const COP := 0
const CROOK := 1

## What an order is for (Officer.shout picks one line of the kind).
enum Kind { ARMED, HANDS, STOP, GENERIC, STAY, FOLLOW, COMPLY, DEFY, PRISONER, STOPPING }

## [file stem, words, kind] in the order of tools/audio/make_voices.py.
const LINES := [
	["drop_weapon", "POLICE! DROP THE WEAPON!", Kind.ARMED],
	["drop_it", "DROP IT! DROP IT NOW!", Kind.ARMED],
	["gun_down", "PUT THE GUN DOWN! NOW!", Kind.ARMED],
	["hands_head", "HANDS ON YOUR HEAD!", Kind.HANDS],
	["get_down", "GET DOWN ON THE GROUND!", Kind.HANDS],
	["knees", "ON YOUR KNEES! HANDS WHERE I CAN SEE THEM!", Kind.HANDS],
	["hold_it", "HOLD IT RIGHT THERE!", Kind.STOP],
	["stop_police", "STOP! POLICE!", Kind.STOP],
	["dont_move", "DON'T MOVE!", Kind.STOP],
	["desist", "DESIST! DESIST NOW!", Kind.GENERIC],
	["popo", "THIS IS THE POPO!", Kind.GENERIC],
	["nobody_move", "POLICE! NOBODY MOVE!", Kind.GENERIC],
	["stay", "STAY RIGHT THERE!", Kind.STAY],
	["sit_tight", "SIT DOWN. DON'T YOU MOVE.", Kind.STAY],
	["with_me", "WITH ME. MOVE IT!", Kind.FOLLOW],
	["walk", "UP YOU GET. WALK WITH ME.", Kind.FOLLOW],
	["ok_ok", "Okay, okay! Don't shoot!", Kind.COMPLY],
	["give_up", "Alright, I give up!", Kind.COMPLY],
	["easy", "Easy! Easy! I'm doing it!", Kind.COMPLY],
	["pig", "Get lost, pig!", Kind.DEFY],
	["never", "You'll never take me alive!", Kind.DEFY],
	["make_me", "Make me!", Kind.DEFY],
	["lawyer", "I want my lawyer!", Kind.PRISONER],
	["brutality", "This is police brutality!", Kind.PRISONER],
	["stopping", "Alright! Alright! I'm stopping!", Kind.STOPPING],
]

static var current: Voices
## The most recent lines said, newest last: {who, id, line} (for tests).
static var history: Array = []
static var _cache := {}
static var _last := {}       # kind -> last line picked, so it doesn't repeat
static var _rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null
	Net.unregister(MSG_VOICE)


func _ready() -> void:
	Net.register(MSG_VOICE, _on_msg)


## A line of the kind, not the same as the last one of that kind.
static func pick(kind: int) -> int:
	var options := []
	for i in LINES.size():
		if LINES[i][2] == kind:
			options.append(i)
	if options.is_empty():
		return 0
	var i: int = options[_rng.randi_range(0, options.size() - 1)]
	if options.size() > 1 and _last.get(kind, -1) == i:
		i = options[(options.find(i) + 1) % options.size()]
	_last[kind] = i
	return i


## Host: `speaker` (an Officer or a Suspect) shouts the line, for everyone.
static func say(speaker: Node3D, line: int, delay := 0.0) -> void:
	if speaker == null or not is_instance_valid(speaker) or not speaker.is_inside_tree():
		return
	if delay > 0.0:
		var wr: WeakRef = weakref(speaker)
		speaker.get_tree().create_timer(delay).timeout.connect(func():
			var sp: Node3D = wr.get_ref()
			if sp and sp.is_inside_tree():
				say(sp, line))
		return
	var who := COP if speaker is Officer else CROOK
	var id: int = (speaker as Officer).peer_id if who == COP else (speaker as Suspect).net_id
	if current and Net.is_host() and Net.is_online():
		var b := StreamPeerBuffer.new()
		b.put_u8(who)
		b.put_u32(id)
		b.put_u8(line)
		Net.broadcast(MSG_VOICE, b.data_array, Net.RELIABLE)
	play(speaker, line)


func _on_msg(_from: int, data: PackedByteArray) -> void:
	if Net.is_host():
		return
	var b := StreamPeerBuffer.new()
	b.data_array = data
	var who := b.get_u8()
	var id := b.get_u32()
	var line := b.get_u8()
	var group := "officers" if who == COP else "suspects"
	for n in get_tree().get_nodes_in_group(group):
		if (who == COP and (n as Officer).peer_id == id) or (who == CROOK and (n as Suspect).net_id == id):
			play(n as Node3D, line)
			return


## Which of the three recordings a speaker uses (stays the same for them).
static func voice_of(speaker: Node3D) -> int:
	if speaker is Officer:
		var ids := []
		for n in speaker.get_tree().get_nodes_in_group("officers"):
			ids.append((n as Officer).peer_id)
		ids.sort()
		return 1 + maxi(ids.find((speaker as Officer).peer_id), 0) % VOICES
	return 1 + (speaker as Suspect).look % VOICES


static func stream(line: int, voice: int) -> AudioStream:
	var path := "%s%s_%d.ogg" % [VOICE_DIR, LINES[line][0], voice]
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Every machine: the speaker shouts the line (sound from their mouth, words
## over their head).
static func play(speaker: Node3D, line: int) -> void:
	if line < 0 or line >= LINES.size() or speaker == null or not speaker.is_inside_tree():
		return
	var who := COP if speaker is Officer else CROOK
	history.append({"who": who, "line": line, "id": (speaker as Officer).peer_id if who == COP else (speaker as Suspect).net_id})
	if history.size() > 32:
		history.pop_front()
	_words(speaker, LINES[line][1], who == COP)
	var st := stream(line, voice_of(speaker))
	if st == null or DisplayServer.get_name() == "headless":
		return
	Sfx.ensure_buses()
	# One shout at a time from each mouth.
	var old := speaker.get_node_or_null("Voice")
	if old:
		old.queue_free()
	var p := AudioStreamPlayer3D.new()
	p.name = "Voice"
	p.stream = st
	p.position = Vector3(0, 1.65, 0)
	p.volume_db = 6.0 if who == COP else 3.0
	p.unit_size = 9.0
	p.max_distance = 80.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	p.pitch_scale = 1.0 + _rng.randf_range(-0.03, 0.03)
	var pos := speaker.global_position + Vector3(0, 1.65, 0)
	var bus := Sfx.BUS_SFX if Sfx.zone_at(speaker.get_tree(), pos) == null else Sfx.BUS_INDOOR
	var walls := 0
	var lis: Variant = Sfx.listener_position(speaker)
	if lis != null:
		walls = Sfx.walls_between(speaker.get_viewport().world_3d.direct_space_state, pos, lis)
	p.bus = Sfx.muffled_bus(bus, walls)
	p.volume_db += Sfx.occlusion(walls).db
	speaker.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


static func _words(speaker: Node3D, text: String, cop: bool) -> void:
	var old := speaker.get_node_or_null("Words")
	if old:
		old.name = "WordsOld"
		old.queue_free()
	var l := Label3D.new()
	l.name = "Words"
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0016
	l.font_size = 30 if cop else 24
	l.outline_size = 8
	l.modulate = Color(1.0, 0.95, 0.6) if cop else Color(1.0, 1.0, 1.0)
	l.position = Vector3(0, 2.3, 0)
	speaker.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", 2.7, 1.6)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.9)
	tw.tween_callback(l.queue_free)
