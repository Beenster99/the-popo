class_name Stories
extends Node
## Wave 3, Phase 3.3: story chains. Linked jobs about the same people, built
## from the job templates, with characters who keep their face and name
## from one job to the next, escape, come back and remember you.
##
##  THE VIPERS      a gang: a deal on the corner, a shoot-out at their yard,
##                  then the raid on their boss.
##  COUNCILLOR HALE a crooked official: a bribe handed over, a search for him
##                  in an office block, then the chase when he runs for it.
##  THE MAGPIE      a serial thief: burglaries, a car theft and the chase,
##                  slipping away more often than not.
##
## One story job runs at a time. Arrest (or drop) the named character and
## the story moves on; let them get away and that part comes round again
## later, with them better prepared: armed, fighting back, and saying so.
## The last job of a story is the big one. (Saving story progress between
## sessions is Phase 4.4.)

const GAP := Vector2(300.0, 480.0)    # s of quiet between story jobs (2026-11-23: less non-stop)
const K := Dispatcher.Kind
const FINALE_PAY := 1500   # Phase 3.4: a story finished

const CHAINS := [
	{"id": "vipers", "name": "THE VIPERS", "who": "Dex Moran", "look": 41,
		"steps": [
			{"kind": K.DEAL, "intro": "Word is the Vipers are dealing in the open. Their man Dex Moran is handing over himself."},
			{"kind": K.GANG, "intro": "The Vipers are shooting back now. Moran's at their yard with his crew."},
			{"kind": K.RAID, "who": "Ray Vance", "look": 199, "intro": "We've found the Vipers' house. Ray Vance runs the lot: bring him in."},
		],
		"done": "That's the Vipers finished. Nice work, all of you."},
	{"id": "hale", "name": "COUNCILLOR HALE", "who": "Councillor Hale", "look": 128,
		"steps": [
			{"kind": K.DEAL, "intro": "Tip-off: Councillor Hale is taking an envelope from a builder. Catch him at it."},
			{"kind": K.SEARCH, "intro": "Hale's hiding in an office block rather than answer questions. Find him."},
			{"kind": K.PURSUIT, "intro": "Hale's done a runner in a stolen car. Don't let him reach the motorway."},
		],
		"done": "Hale's in a cell. The papers are going to love this."},
	{"id": "magpie", "name": "THE MAGPIE", "who": "the Magpie", "look": 77,
		"steps": [
			{"kind": K.BURGLARY, "intro": "Another Magpie job: a break-in, nothing taken but the shiny stuff."},
			{"kind": K.SHOPLIFT, "intro": "The Magpie's been seen lifting from a shop, bold as brass."},
			{"kind": K.THEFT, "intro": "The Magpie's after a car this time. Get there before they're gone."},
			{"kind": K.PURSUIT, "intro": "The Magpie's in a stolen car, laughing at us on the radio. End it."},
		],
		"done": "The Magpie's caught at last. The city can keep its spoons."},
]
const TAUNTS := [
	"%s: You lot again? Should've brought more of you.",
	"%s: I remember you. This time I'm ready.",
	"%s: Third time lucky, officers? Not for you.",
]

var dispatcher: Dispatcher
var enabled := true
## Per chain: {step, escapes, done, dead}
var progress := {}
var _t := 50.0
var _active := {}      # call id -> chain index
var _rng := RandomNumberGenerator.new()
var _next_chain := 0


func _ready() -> void:
	_rng.randomize()
	for ch in CHAINS:
		progress[ch.id] = {"step": 0, "escapes": 0, "done": false, "dead": false}


func _physics_process(delta: float) -> void:
	if not Net.is_host() or dispatcher == null or dispatcher.city == null:
		return
	_watch()
	if not enabled or not dispatcher.enabled or not _active.is_empty() or not dispatcher.quiet():
		return
	_t -= delta
	if _t <= 0.0:
		_t = _rng.randf_range(GAP.x, GAP.y)
		start_next()


## Host: the next part of the next unfinished story. Returns the call id.
func start_next() -> int:
	for i in CHAINS.size():
		var ci := (_next_chain + i) % CHAINS.size()
		var id := start_chain(ci)
		if id > 0:
			_next_chain = ci + 1
			return id
	return -1


func start_chain(ci: int) -> int:
	var ch: Dictionary = CHAINS[ci]
	var pr: Dictionary = progress[ch.id]
	if pr.done:
		return -1
	var step: Dictionary = ch.steps[pr.step]
	var id := dispatcher.start_call(step.kind)
	if id <= 0:
		return -1
	var c: Dictionary = dispatcher.calls[id]
	c.story = ch.id
	var sus: Suspect = dispatcher.suspects.get(c.suspects[0]) if not c.suspects.is_empty() else null
	if sus == null:
		return id
	var who: String = step.get("who", ch.who)
	sus.look = int(step.get("look", ch.look))
	if sus.rig:
		SuspectLook.apply(sus.rig.model, sus.look)
	sus.set_meta("story_name", who)
	c.character = sus.net_id
	c.who = who
	# They remember you: every escape makes them readier for you.
	if pr.escapes >= 1 and step.kind not in [K.PURSUIT, K.THEFT]:
		sus.fighter = true
		if not sus.armed:
			sus.weapon = EnemyGuns.PISTOL if pr.escapes == 1 else EnemyGuns.SHOTGUN
			sus.mag = EnemyGuns.MAG[sus.weapon]
			sus._show_gun()
		sus.hp = Suspect.MAX_HP * (1.0 + 0.25 * pr.escapes)
	dispatcher.say("%s: %s" % [ch.name, step.intro])
	if pr.escapes >= 1:
		dispatcher.say(TAUNTS[mini(pr.escapes - 1, TAUNTS.size() - 1)] % who.to_upper())
	_active[id] = ci
	return id


## How each story job ends: caught moves the story on, got away repeats it.
func _watch() -> void:
	for id in _active.keys():
		var c: Dictionary = dispatcher.calls.get(id, {})
		if c.is_empty() or c.state == Dispatcher.CallState.ACTIVE:
			continue
		var ci: int = _active[id]
		_active.erase(id)
		var ch: Dictionary = CHAINS[ci]
		var pr: Dictionary = progress[ch.id]
		var sus: Suspect = dispatcher.suspects.get(c.get("character", -1))
		var caught: bool = c.state == Dispatcher.CallState.CLOSED and sus != null and sus.state in [Suspect.S.BOOKED, Suspect.S.DOWN]
		if sus != null and sus.state == Suspect.S.BOOKED and c.state == Dispatcher.CallState.LOST:
			caught = false   # "booked" by the timeout: they got away
		if caught:
			if sus.state == Suspect.S.DOWN:
				dispatcher.say("%s: %s won't be giving us any more trouble." % [ch.name, c.get("who", ch.who)])
				pr.dead = true
			pr.step += 1
			pr.escapes = 0
			if pr.step >= ch.steps.size():
				pr.done = true
				dispatcher.earn(FINALE_PAY)
				dispatcher.say("%s: %s Bonus for the station: £%d." % [ch.name, ch.done, FINALE_PAY])
			else:
				dispatcher.say("%s: that's one step closer." % ch.name)
		else:
			pr.escapes += 1
			dispatcher.say("%s: %s got away. They'll turn up again." % [ch.name, c.get("who", ch.who)])
		_t = minf(_t, _rng.randf_range(GAP.x, GAP.y))
