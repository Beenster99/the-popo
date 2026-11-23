class_name PoliceRadio
extends Node
## Wave 5, Phase 5.2: the radio on your shoulder. Every line dispatch says
## comes with a key-up click and the squelch as they let go.
##
## 2026-11-23 (beenster: "the chatter is undiscernible so it's more of a
## distraction"): no more mumbling. Dispatch now reads each job out in a
## clear voice (assets/audio/radio/<stem>.ogg, matched to the line on screen
## by assets/audio/radio/lines.json); lines with no recording (weather,
## council, and so on) are just a short click on the screen text. Other
## units only talk now and then, quietly, and only when nothing is going on.

const CHATTER := Vector2(150.0, 300.0)   # seconds between other units' chatter
const LINES_PATH := "res://assets/audio/radio/lines.json"
const VOICE_DB := -2.0
const CHATTER_DB := -10.0

var dispatcher: Dispatcher
var player: AudioStreamPlayer
var _queue: Array = []        # [stream, db] parts still to play
var _chatter_t := 60.0
var _rng := RandomNumberGenerator.new()
var _said := 0                # chatter lines used (they go round in order)
## Lines heard (for tests), and the last spoken stem.
var lines := 0
var last_voice := ""

static var _table := {}


func _ready() -> void:
	_rng.randomize()
	_chatter_t = _rng.randf_range(90.0, 180.0)
	Sfx.ensure_buses()
	player = AudioStreamPlayer.new()
	player.bus = Sfx.BUS_RADIO
	player.volume_db = -4.0
	add_child(player)
	player.finished.connect(_next)
	if dispatcher:
		dispatcher.radio.connect(talk)


static func table() -> Dictionary:
	if _table.is_empty():
		var f := FileAccess.open(LINES_PATH, FileAccess.READ)
		if f:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_table = d
	return _table


## The recorded line for this text on the screen ("" for none).
static func voice_for(text: String) -> String:
	var who := text.get_slice(":", 0)
	if who not in ["DISPATCH", "CUSTODY"]:
		return ""
	var body := text.substr(who.length() + 1).strip_edges().to_lower()
	for row in table().get("dispatch", []):
		if body.contains(String(row[1]).to_lower()):
			return String(row[0])
	return ""


## A line on the radio: key up, the voice if there is one, squelch.
func talk(text: String) -> void:
	lines += 1
	var stem := voice_for(text)
	last_voice = stem
	if stem == "" and _queue.size() > 2:
		return   # a busy channel: the screen text will do
	_key(stem, VOICE_DB)


func _key(stem: String, db: float) -> void:
	_queue.append([Sfx.stream("radio_key", _rng.randi_range(1, Sfx.COUNTS.radio_key)), db - 2.0])
	if stem != "":
		var s := load("res://assets/audio/radio/%s.ogg" % stem) as AudioStream
		if s:
			_queue.append([s, db])
	_queue.append([Sfx.stream("radio_unkey", _rng.randi_range(1, Sfx.COUNTS.radio_unkey)), db - 2.0])
	if _queue.size() > 12:
		_queue = _queue.slice(_queue.size() - 12)
	if not player.playing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		return
	var part: Array = _queue.pop_front()
	player.stream = part[0]
	player.pitch_scale = 1.0
	player.volume_db = part[1]
	player.play()


func _process(delta: float) -> void:
	# Only on a quiet shift: never over a job.
	if dispatcher and dispatcher.has_method("active_calls") and not dispatcher.active_calls().is_empty():
		return
	_chatter_t -= delta
	if _chatter_t <= 0.0:
		_chatter_t = _rng.randf_range(CHATTER.x, CHATTER.y)
		var ch: Array = table().get("chatter", [])
		if ch.is_empty() or not _queue.is_empty() or player.playing:
			return
		_key(String(ch[_said % ch.size()][0]), CHATTER_DB)
		_said += 1
