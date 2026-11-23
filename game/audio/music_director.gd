class_name MusicDirector
extends Node
## Wave 5, Phase 5.2: music under the game. A quiet patrol bed most of the
## time; when shots go off within earshot, or you're running with the
## siren on, it crossfades into the action track, and back down a while
## after it's gone quiet. (The title theme plays on the main menu.)

const PATROL := "res://assets/audio/music/patrol.ogg"
const ACTION := "res://assets/audio/music/action.ogg"
const MENU := "res://assets/audio/music/menu.ogg"
const HOLD := 14.0           # seconds the action music stays after the last shot
const PATROL_DB := -12.0
const ACTION_DB := -6.0
const SILENT_DB := -60.0

var pawn_getter: Callable
var patrol: AudioStreamPlayer
var action: AudioStreamPlayer
## 0 calm .. 1 full action, eased.
var heat := 0.0


func _ready() -> void:
	patrol = make_player(PATROL, PATROL_DB)
	action = make_player(ACTION, SILENT_DB)
	add_child(patrol)
	add_child(action)
	patrol.play()
	action.play()


static func make_player(path: String, db: float) -> AudioStreamPlayer:
	Sfx.ensure_buses()
	var p := AudioStreamPlayer.new()
	var s := load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = true
	p.stream = s
	p.bus = Sfx.BUS_MUSIC
	p.volume_db = db
	return p


func wanted() -> float:
	var since := (Time.get_ticks_msec() - Sfx.last_shot_ms) / 1000.0
	if since < HOLD:
		return 1.0
	var o := pawn_getter.call() as Officer if pawn_getter.is_valid() else null
	if o and o.car and is_instance_valid(o.car) and o.car.siren > 0:
		return 0.7
	return 0.0


func _process(delta: float) -> void:
	var w := wanted()
	heat = move_toward(heat, w, delta / (2.0 if w > heat else 7.0))
	action.volume_db = lerpf(SILENT_DB, ACTION_DB, sqrt(heat)) if heat > 0.001 else SILENT_DB
	patrol.volume_db = lerpf(PATROL_DB, SILENT_DB, sqrt(heat))
