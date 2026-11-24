class_name HelpScreen
extends Control
## Help (the Esc menu, the main menu and the Online screen): how to play,
## one topic at a time, picked from the list on the left. Keys in the text
## are read from the live bindings, so they follow the Key binds screen,
## and show controller buttons when you're playing on a controller.

signal closed

const PANEL_WIDTH := 1300.0

## [title, tooltip, text]. {action} becomes that action's key in bold.
const TOPICS := [
	["Controls", "Every key and controller button, as you have them set.", "@controls"],
	["Getting started", "The menus, First Shift, saving and the station.",
		"""[b]First time?[/b] Pick [b]First Shift[/b] on the main menu: a step-by-step walk through the job, from the station door to booking your first prisoner. It never touches your saved city.

[b]Single Player / New City[/b] starts a fresh city. [b]Continue[/b] brings back your saved one: the station's pay, everything bought at the armoury, how far each story has got, the time of day, the weather and the kit you were carrying.

You start at the police station's front door. The patrol cars are parked out front, the custody bay is round the side, and the armoury counter is just inside the door.

[b]Esc[/b] (Menu on a controller) opens the game menu: Resume, Help, Settings, Leave. Playing alone the game pauses; online it carries on and your officer just stands still.

The clock is top left (a game day lasts 48 minutes) with the station's pay next to it. Jobs are listed under it with their distance and street. The mini map is bottom left, and every job has a marker on screen (see Mini map and markers). The line at the bottom of the screen always says what {interact} does where you're standing."""],
	["Moving", "Walking, sprinting, stances, cover, climbing and ropes.",
		"""[b]Walking and running.[/b] Walking is your normal pace; hold {sprint} to sprint. {walk} switches between walking and running (on a controller, tap L3; tilting the stick part way also walks). Gun holstered you stroll; gun out it's a tactical walk.

[b]Stance.[/b] {stance}: tap to crouch, tap again to stand. Hold it to lie prone. Hold it while running to roll (a slide when sprinting). {prone} and {dive} do prone and roll on their own.

[b]Jump, vault, climb.[/b] {jump} jumps. Run at a low wall, a car bonnet or a smashed window and you vault it; at a ledge you pull yourself up.

[b]Cover.[/b] {cover} puts your back to the nearest wall, car or ledge (low cover: you duck behind it). Hold {aim} to peek out and aim; fire without aiming to blind fire. Hold a direction and press {cover} to run to the next cover that way, or round the corner. Move away, or press {cover} again, to leave.

[b]Doors.[/b] Every building can be entered. Locked doors: {kick} them in.

[b]Towers and roofs.[/b] Downtown towers have a lift by the stairs: {interact} at the door calls it, {interact} inside picks the floor (or a number key, 0 for G). Most buildings have stairs up to a hut on the roof.

[b]Grapple hook[/b] (armoury, Gear): hold {aim} at a building from outside and press {interact} to be hauled up onto the roof. At a roof edge facing out, {interact} goes over on the rope: move forward to climb, back to slide, {sprint} drops fast, {jump} swings you in through the window in front of you, {interact} lets go."""],
	["Guns and fighting", "Aiming, reloading, picking up guns, melee and grenades.",
		"""[b]Your pistol.[/b] You start with it holstered: {holster} draws it (or just hold {aim}). Hold {aim} to aim, {fire} to fire at the dot in the middle of the screen, {reload} to reload. Rounds in the gun and spare rounds are bottom right.

[b]Shooting well.[/b] A gun just raised takes a moment to settle, and shots on the move go wide: stop, aim, then fire. A head shot drops a crook. Getting hit hurts, so use cover. Walking keeps your aim steadier than running.

[b]Holster when you can.[/b] People get nervous round a drawn gun, and undercover it gives you away.

[b]Enemy guns.[/b] When a crook gives up they toss their gun. {interact} picks it up, but you only get the rounds loaded in it: no spare ammo. {holster} drops it.

[b]Hands.[/b] {punch} punches (while sprinting: a shoulder barge). {kick} kicks, and kicks doors in. A punch or a gun in the face makes most suspects give up.

[b]Grenades[/b] (once the armoury has them): {throw} throws the picked one at the dot, {grenade_next} picks smoke, CS gas or flashbang. You carry two of each, refilled at a patrol car's boot.
 • Smoke: a thick cloud nobody can see or shoot through. Cross a street or reach a downed friend.
 • CS gas: anyone in it coughs and can't aim; most give up. It gets you too.
 • Flashbang: stuns anyone who sees it for a few seconds. Don't look at it yourself.
Some armed crooks carry frag grenades. Listen for the clink, look for the red GRENADE! warning, and move.

[b]Second slot.[/b] With breach charges or C4 in your loadout, {weapon_2} gets them out: aim and fire to stick one on. {weapon_1} goes back to the pistol.

[b]Things break.[/b] Furniture, glass and walls break. Red barrels and gas bottles explode and start fires; shoot a red extinguisher to put fires out round it. Badly shot cars catch fire and blow up."""],
	["Arrests and orders", "Shouting orders, cuffing, prisoners and booking.",
		"""[b]Shout.[/b] {shout} shouts an order at whoever you're facing: "Drop the weapon!", "Hold it right there!", "Hands on your head!". They might do it, or tell you where to go. Unarmed people mostly listen; armed ones less; hard gang fighters rarely, unless they're hurt, alone or looking down your gun. Every order they ignore makes the next one harder to ignore.

[b]Cuff.[/b] When someone is on their knees, hold {interact} next to them to cuff them. Then they walk with you.

[b]Prisoners.[/b] {shout} next to your prisoner tells them to stay put; again and they follow you. Leave one alone too long and they may run for it, still in cuffs: shout, {punch} or {kick} them, or hold {interact} to grab them.

[b]Booking.[/b] Walk them to a patrol car and press {interact} at a door to put them in the back, then drive to the custody bay at the side of the station and stop there. Or just walk them to the bay.

[b]Undercover[/b] (plain clothes from the armoury): crooks take you for anyone on the street until you draw your gun, shout, turn up in a marked car or hang about too close. Watch the suspicion meter."""],
	["Mini map and markers", "The map in the corner and finding the job.",
		"""[b]The mini map[/b] is bottom left. Grey lines are roads, the dark blocks are buildings and the blue one is the police station. You're the white arrow; the other officers are arrows in their ping colours, and the small blue dots are patrol cars.

[b]Up is the way you're looking.[/b] The small map turns with the camera (the N on the rim shows north) and zooms out as you drive faster. Turn that off under Settings > Gameplay to keep north up.

{minimap} switches it between small, large (the whole city, north up) and off.

[b]Finding the job.[/b] Each job is a pulsing red dot (orange for traffic jobs and car thefts), with a line along the roads from you to the nearest one. A job off the map sits on its rim, pointing the way.

[b]On screen[/b] every job has a pin over it with what it is and how far, seen through walls, and a tall beam of light over the spot shows above the rooftops. When it's off screen, a big arrow at the edge points the way to turn, with the distance.

[b]Prisoners.[/b] While anyone has a prisoner, the custody bay shows as a blue square on the map and a blue pin on screen. A cuffed prisoner doing a runner shows in orange."""],
	["Driving", "Getting in, lights and siren, passengers, pursuits.",
		"""[b]Getting in.[/b] {interact} at a car door gets you in (the nearest free seat); {interact} again gets you out. {stance} moves you to the next free seat. Three officers fit in one car. {interact} at any civilian car, van, lorry or motorbike takes it: the driver is pulled out.

[b]Driving.[/b] {move_forward} accelerate, {move_back} brake and reverse, {move_left} / {move_right} steer, {handbrake} handbrake, {horn} horn. {torch} cycles the lights: lights, lights and wail, yelp, off. Traffic pulls over for the siren.

[b]Passengers[/b] hold {aim} to lean out of the window and shoot.

[b]The boot.[/b] Hold {interact} at a patrol car's boot for ammo, first aid and grenades.

[b]Pursuits.[/b] Ram the car, box it in or shoot it up and the driver bails and runs. Rain makes the roads slippery."""],
	["Jobs and the city", "Dispatch, stories, pay and what happens round town.",
		"""[b]Dispatch.[/b] One job at a time. Calls come in on the radio, with the details on screen; after each job there's a quiet spell before the next. Victims tell you what the suspect looks like and which way they went.

[b]Chance encounters.[/b] Some crimes just happen up the street with no call: walk up and they're yours.

[b]Stories.[/b] Three running stories come up between jobs. The same people come back, and if they got away last time they're armed and they remember you.

[b]Pay.[/b] Every job closed and every suspect brought in pays the station. Story characters brought in alive pay a bonus.

[b]The city.[/b] Day follows the clock; the weather changes now and then. Crashes, fires and burglar alarms just happen: get there and stay a while. Knocked-down buildings get cleared and rebuilt by council repair crews over the following days."""],
	["Armoury and kit", "Spending the station's pay: guns, upgrades, gear.",
		"""[b]The armoury[/b] is the yellow circle just inside the station door: {interact} opens it. Spend the station's pay on pistols, bench upgrades, rounds, body armour, pouches, grenades, the grapple hook, cars, plain clothes and a firing range.

Each of you picks your own pistol, rounds and loadout (ammo backpack, breach charges or C4, or a tactical torch). Station buys are shared by everyone.

[b]The gun bench[/b] shows your pistol in 3D with every upgrade the station owns. Point at a pistol or an upgrade in the list to see it there. Drag to turn it, wheel to zoom (controller: right stick and triggers).

[b]The range[/b] (once bought) is out the back: {interact} on the blue circle starts a 30 second run. Shoot the red targets, not the blue."""],
	["Getting hurt", "Wounds, first aid, going down, reviving and dragging.",
		"""[b]Wounds.[/b] A leg wound makes you limp (no sprint), an arm wound shakes your aim, bleeding drains health. Your wounds are listed bottom right.

[b]First aid.[/b] Hold {interact} to treat yourself, or stand next to a hurt teammate and hold {interact} to treat them. Each use patches one wound. You carry three; the car boot fixes everything and refills the pouch.

[b]Going down.[/b] At zero health you go down. A teammate holds {interact} on you to get you up where you are, or after the wait press {reload} to respawn at the start with full health and ammo. On your own you get up by yourself after 30 seconds.

[b]Dragging.[/b] Hold {drag} next to a downed teammate to grab their collar and drag them into cover. Let go to drop them."""],
	["Playing online", "Hosting, joining and opening the port.",
		"""Up to three officers. Choose [b]Online[/b] on the main menu.

[b]Hosting.[/b] Press Host. The game asks your router to open port 27015 by itself and shows the address to give your friends (with a button to copy it). When everyone is in, press Start the game.

[b]Joining.[/b] Type the host's address and port 27015 and press Join.

If Windows Firewall asks, allow The Popo on private and public networks.

If the router doesn't open the port: forward UDP port 27015 to the host PC's local address in the router's settings (see How to play.txt for the steps). A warning about CGNAT means your internet provider shares one address between customers; ask them for a public IP.

The host's Gameplay rules (friendly fire) count for everyone. Gore is only on your own screen."""],
	["Settings tips", "Frame rate, gore, sound and the camera.",
		"""[b]Frame rate.[/b] Settings > Graphics > Apply a preset. Epic is the one to play on at 4K; Max is for screenshots. BENCHMARK on the main menu measures your frame rate in the same city every time. F11 shows the frame rate counter.

[b]Gore[/b] (Gameplay) goes from Off to Extreme. It's only on your screen.

[b]Sound[/b] has a slider for each part: gunshots outside and inside, background, engines, music and the police radio.

[b]Camera.[/b] Mouse look speed, how tightly the camera follows and camera shake are under Gameplay. {cam_zoom_in} / {cam_zoom_out} move the camera in and out.

[b]Keys.[/b] Settings > Gameplay > Change keys, or the button on the Controls page here. Every action can be moved, for keyboard and mouse and for a controller.

Hover over any setting for what it does."""],
]

var _list: VBoxContainer
var _text: RichTextLabel
var _topic := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var centre := func():
		var side := maxi(40, int((size.x - PANEL_WIDTH) / 2.0))
		margin.add_theme_constant_override("margin_left", side)
		margin.add_theme_constant_override("margin_right", side)
	resized.connect(centre)
	centre.call()
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	col.add_child(top)
	top.add_child(UiTheme.title("HELP", 34, UiTheme.ACCENT))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var keys := Button.new()
	keys.text = "Change key binds..."
	keys.tooltip_text = "Move any action to another key, mouse button or controller button."
	keys.pressed.connect(func():
		var ks := KeyBindsScreen.new()
		ks.closed.connect(func(): _show(_topic); keys.grab_focus())
		add_child(ks))
	top.add_child(keys)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size.x = 120
	back.tooltip_text = "Close help (Esc)."
	back.pressed.connect(close)
	top.add_child(back)

	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 20)
	col.add_child(row)
	var side_panel := PanelContainer.new()
	row.add_child(side_panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	side_panel.add_child(_list)
	for i in TOPICS.size():
		var b := Button.new()
		b.text = TOPICS[i][0]
		b.tooltip_text = TOPICS[i][1]
		b.custom_minimum_size = Vector2(250, 44)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.pressed.connect(_show.bind(i))
		b.focus_entered.connect(_show.bind(i))
		_list.add_child(b)
	var page := PanelContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(page)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_text.focus_mode = Control.FOCUS_NONE
	_text.add_theme_font_size_override("normal_font_size", 19)
	_text.add_theme_font_size_override("bold_font_size", 19)
	_text.add_theme_color_override("default_color", UiTheme.TEXT)
	_text.add_theme_constant_override("line_separation", 4)
	page.add_child(_text)
	_show(0)
	(_list.get_child(0) as Button).grab_focus.call_deferred()


func close() -> void:
	closed.emit()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("back_to_launcher") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.3 \
			and (event as InputEventJoypadMotion).axis == JOY_AXIS_RIGHT_Y:
		_text.get_v_scroll_bar().value += (event as InputEventJoypadMotion).axis_value * 40.0


func _show(i: int) -> void:
	_topic = i
	for j in _list.get_child_count():
		(_list.get_child(j) as Button).set_pressed_no_signal(j == i)
	var body: String = TOPICS[i][2]
	_text.text = ("[font_size=26][color=#%s]%s[/color][/font_size]\n\n" % [UiTheme.ACCENT.to_html(false), TOPICS[i][0]]) + \
		(controls_text() if body == "@controls" else fill(body))
	_text.scroll_to_line(0)


## Swaps {action} for that action's key, in bold.
static func fill(body: String) -> String:
	var out := body
	for pair in Controls.REBINDABLE:
		var tag := "{%s}" % pair[0]
		if out.contains(tag):
			out = out.replace(tag, "[b][color=#%s]%s[/color][/b]" % [UiTheme.ACCENT.to_html(false), Controls.key_name(pair[0])])
	return out


## Every action with its keyboard / mouse key and its controller button.
static func controls_text() -> String:
	var acc := UiTheme.ACCENT.to_html(false)
	var dim := UiTheme.DIM.to_html(false)
	var t := "Change any of them with [b]Change key binds[/b] (top right).\n"
	for g in Controls.GROUPS:
		t += "\n[font_size=22][color=#%s]%s[/color][/font_size]\n" % [acc, g[0]]
		t += "[table=3]"
		t += "[cell][color=#%s]Action[/color]        [/cell][cell][color=#%s]Keyboard / mouse[/color]    [/cell][cell][color=#%s]Controller[/color][/cell]" % [dim, dim, dim]
		for a in g[1]:
			var pc := Controls.pc_event(a)
			var pe := Controls.pad_event(a)
			var pad := Controls.describe_pad(pe) if pe else "-"
			if a.begins_with("move_"):
				pad = "Left stick"
			elif a == "walk" and pe == null:
				pad = "Tap L3"
			t += "[cell]%s        [/cell][cell][b]%s[/b]    [/cell][cell][b]%s[/b][/cell]" % [
				Controls.action_name(a), Controls.describe(pc) if pc else "-", pad]
		t += "[/table]\n"
	t += "\n[font_size=22][color=#%s]Always[/color][/font_size]\n" % acc
	t += "Mouse (right stick): look round.   [b]Esc[/b] (Menu): the game menu.   [b]F3[/b]: network overlay.   [b]F11[/b]: frame rate.\n"
	t += "Host only: [b]N[/b] moves the clock on three hours, [b]K[/b] changes the weather, [b]J[/b] calls in a job now.\n"
	return t
