class_name PoliceRadio
extends Node
## Wave 5, Phase 5.2: the radio on your shoulder. Every line dispatch says
## comes with a key-up click, a burst of a talker on the channel and the
## squelch as they let go. Between calls, other units talk on the channel
## now and then (too far off to make out). Lines wait their turn: the radio
## never talks over itself.

const CHATTER := Vector2(35.0, 90.0)   # seconds between other units' chatter

var dispatcher: Dispatcher
var player: AudioStreamPlayer
var _queue: Array = []        # [stem, variant] parts still to play
var _chatter_t := 20.0
var _rng := RandomNumberGenerator.new()
## Lines heard (for tests).
var lines := 0


func _ready() -> void:
	_rng.randomize()
	_chatter_t = _rng.randf_range(15.0, 40.0)
	Sfx.ensure_buses()
	player = AudioStreamPlayer.new()
	player.bus = Sfx.BUS_RADIO
	player.volume_db = -4.0
	add_child(player)
	player.finished.connect(_next)
	if dispatcher:
		dispatcher.radio.connect(func(text): talk(text.length()))


## A transmission about n characters long.
func talk(n: int) -> void:
	lines += 1
	_queue.append(["radio_key", _rng.randi_range(1, Sfx.COUNTS.radio_key)])
	var parts := clampi(int(n / 70.0) + 1, 1, 2)
	for i in parts:
		_queue.append(["radio_voice", _rng.randi_range(1, Sfx.COUNTS.radio_voice)])
	_queue.append(["radio_unkey", _rng.randi_range(1, Sfx.COUNTS.radio_unkey)])
	if _queue.size() > 12:
		_queue = _queue.slice(_queue.size() - 12)
	if not player.playing:
		_next()


func _next() -> void:
	if _queue.is_empty():
		return
	var part: Array = _queue.pop_front()
	player.stream = Sfx.stream(part[0], part[1])
	player.pitch_scale = _rng.randf_range(0.96, 1.04)
	player.volume_db = -4.0 if part[0] != "radio_voice" else -9.0
	player.play()


func _process(delta: float) -> void:
	_chatter_t -= delta
	if _chatter_t <= 0.0:
		_chatter_t = _rng.randf_range(CHATTER.x, CHATTER.y)
		if _queue.is_empty() and not player.playing:
			talk(_rng.randi_range(30, 120))
