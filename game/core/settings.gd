extends Node
## Player settings (autoload "Settings"): graphics, sound, gameplay and debug.
## Every option is listed once in SCHEMA, which the Settings screen builds its
## rows from. Values are saved in user://settings.cfg and applied as they
## change. Scene parts that settings reach (the WorldEnvironment, lights,
## the isometric camera) are set as they enter the tree, so every scene
## follows the settings without knowing about them.
##
## Renderer and graphics driver live in user://override.cfg, which Godot
## reads at startup (project setting application/config/project_settings_override),
## so those two need a restart.

signal changed(key: String)

const SAVE_PATH := "user://settings.cfg"
const OVERRIDE_PATH := "user://override.cfg"
const TABS := ["Graphics", "Sound", "Gameplay", "Debug"]

const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3440x1440", "3840x2160"]
const SHADOW_SIZES := [1024, 2048, 4096, 8192, 16384]
const FPS_CAPS := [0, 30, 60, 90, 120, 144, 165, 240, 360]
const DRAW_MODES := [
	["Normal", Viewport.DEBUG_DRAW_DISABLED], ["Unshaded", Viewport.DEBUG_DRAW_UNSHADED],
	["Lighting only", Viewport.DEBUG_DRAW_LIGHTING], ["Overdraw", Viewport.DEBUG_DRAW_OVERDRAW],
	["Wireframe", Viewport.DEBUG_DRAW_WIREFRAME], ["Normals", Viewport.DEBUG_DRAW_NORMAL_BUFFER],
	["Shadow atlas", Viewport.DEBUG_DRAW_SHADOW_ATLAS], ["Sun shadow atlas", Viewport.DEBUG_DRAW_DIRECTIONAL_SHADOW_ATLAS],
	["Shadow splits", Viewport.DEBUG_DRAW_PSSM_SPLITS], ["SSAO buffer", Viewport.DEBUG_DRAW_SSAO],
	["SSIL buffer", Viewport.DEBUG_DRAW_SSIL], ["SDFGI cascades", Viewport.DEBUG_DRAW_SDFGI],
	["SDFGI probes", Viewport.DEBUG_DRAW_SDFGI_PROBES], ["GI buffer", Viewport.DEBUG_DRAW_GI_BUFFER],
	["Scene luminance", Viewport.DEBUG_DRAW_SCENE_LUMINANCE], ["No LOD", Viewport.DEBUG_DRAW_DISABLE_LOD],
	["Light clusters", Viewport.DEBUG_DRAW_CLUSTER_OMNI_LIGHTS], ["Occluders", Viewport.DEBUG_DRAW_OCCLUDERS],
	["Motion vectors", Viewport.DEBUG_DRAW_MOTION_VECTORS],
]

## [tab, key, label, kind, default, extra, help]
##   kind "head": a heading row (label only)
##   kind "bool": a tick box
##   kind "enum": extra is the option names; the value is the chosen index
##   kind "range": extra is [min, max, step, suffix]
##   kind "button": extra is the name of a method on the Settings screen
const SCHEMA := [
	# --- Graphics ---------------------------------------------------------
	["Graphics", "", "Display", "head"],
	["Graphics", "window_mode", "Window", "enum", 0, ["Windowed", "Borderless fullscreen", "Exclusive fullscreen", "Maximised"]],
	["Graphics", "resolution", "Window size (windowed)", "enum", 2, RESOLUTIONS],
	["Graphics", "screen", "Screen", "enum", 0, "@screens"],
	["Graphics", "vsync", "V-Sync", "enum", 1, ["Off", "On", "Adaptive", "Mailbox (triple buffered)"]],
	["Graphics", "max_fps", "Frame rate cap", "enum", 0, ["None", "30", "60", "90", "120", "144", "165", "240", "360"]],
	["Graphics", "renderer", "Renderer (restart)", "enum", 0, ["Forward+ (best)", "Mobile", "Compatibility (OpenGL)"],
		"Forward+ has every effect below. Mobile and Compatibility are lighter and drop some effects."],
	["Graphics", "driver", "Graphics driver (restart)", "enum", 0, ["Vulkan", "Direct3D 12"]],
	["Graphics", "", "Quality presets", "head"],
	["Graphics", "preset", "Apply a preset", "button", null, "show_presets"],
	["Graphics", "", "Resolution and anti-aliasing", "head"],
	["Graphics", "render_scale", "3D render scale", "range", 1.0, [0.25, 2.0, 0.05, "x"],
		"Below 1 draws the 3D view smaller and scales it up (faster). Above 1 supersamples (sharper, slower)."],
	["Graphics", "scaling_mode", "Upscaler", "enum", 0, ["Bilinear", "AMD FSR 1", "AMD FSR 2"]],
	["Graphics", "fsr_sharpness", "FSR sharpness (0 = sharpest)", "range", 0.2, [0.0, 2.0, 0.05, ""]],
	["Graphics", "msaa", "MSAA", "enum", 1, ["Off", "2x", "4x", "8x"]],
	["Graphics", "screen_aa", "Screen-space AA", "enum", 0, ["Off", "FXAA", "SMAA"]],
	["Graphics", "taa", "Temporal AA (TAA)", "bool", false],
	["Graphics", "debanding", "Debanding", "bool", false],
	["Graphics", "anisotropy", "Anisotropic filtering", "enum", 2, ["Off", "2x", "4x", "8x", "16x"]],
	["Graphics", "mipmap_bias", "Texture sharpness (mipmap bias)", "range", 0.0, [-2.0, 1.0, 0.1, ""]],
	["Graphics", "lod_threshold", "Level of detail (lower = more detail)", "range", 1.0, [0.0, 8.0, 0.25, "px"]],
	["Graphics", "occlusion_culling", "Occlusion culling", "bool", true,
		null, "Skips drawing what buildings hide. Big saving in the city."],
	["Graphics", "", "Shadows", "head"],
	["Graphics", "sun_shadows", "Sun shadows", "bool", true],
	["Graphics", "sun_shadow_size", "Sun shadow resolution", "enum", 2, ["1024", "2048", "4096", "8192", "16384"]],
	["Graphics", "sun_shadow_distance", "Sun shadow distance", "range", 80.0, [20.0, 400.0, 10.0, " m"]],
	["Graphics", "sun_shadow_splits", "Sun shadow splits", "enum", 2, ["1 (orthogonal)", "2", "4"]],
	["Graphics", "sun_shadow_blur", "Sun shadow softness", "range", 1.0, [0.0, 4.0, 0.1, ""]],
	["Graphics", "lamp_shadows", "Torch and lamp shadows", "bool", true],
	["Graphics", "lamp_shadow_size", "Torch and lamp shadow resolution", "enum", 2, ["1024", "2048", "4096", "8192", "16384"]],
	["Graphics", "shadow_filter", "Shadow filter quality", "enum", 2, ["Hard", "Very low", "Low", "Medium", "High", "Ultra"]],
	["Graphics", "shadow_16bit", "16-bit shadow maps (faster)", "bool", true],
	["Graphics", "", "Lighting and effects", "head"],
	["Graphics", "ssao", "Ambient occlusion (SSAO)", "bool", false],
	["Graphics", "ssao_quality", "SSAO quality", "enum", 2, ["Very low", "Low", "Medium", "High", "Ultra"]],
	["Graphics", "ssao_intensity", "SSAO strength", "range", 2.0, [0.0, 8.0, 0.1, ""]],
	["Graphics", "ssao_half", "SSAO at half resolution", "bool", false],
	["Graphics", "ssil", "Indirect light (SSIL)", "bool", false],
	["Graphics", "ssil_quality", "SSIL quality", "enum", 2, ["Very low", "Low", "Medium", "High", "Ultra"]],
	["Graphics", "ssil_half", "SSIL at half resolution", "bool", false],
	["Graphics", "ssr", "Reflections (SSR)", "bool", false],
	["Graphics", "ssr_steps", "SSR steps", "range", 64, [8, 512, 8, ""]],
	["Graphics", "ssr_roughness", "SSR rough surfaces", "enum", 1, ["Off", "Low", "Medium", "High"]],
	["Graphics", "sdfgi", "Global illumination (SDFGI)", "bool", false,
		null, "Bounced light from the whole scene. Heavy; best on a strong graphics card."],
	["Graphics", "sdfgi_rays", "SDFGI rays", "enum", 3, ["4", "8", "16", "32", "64", "96", "128"]],
	["Graphics", "sdfgi_converge", "SDFGI frames to settle", "enum", 3, ["5", "10", "15", "20", "25", "30"]],
	["Graphics", "gi_half", "GI at half resolution", "bool", false],
	["Graphics", "voxel_gi_quality", "VoxelGI quality", "enum", 1, ["Low", "High"]],
	["Graphics", "glow", "Glow / bloom", "bool", false],
	["Graphics", "glow_intensity", "Glow strength", "range", 0.8, [0.0, 4.0, 0.05, ""]],
	["Graphics", "glow_bloom", "Bloom amount", "range", 0.0, [0.0, 1.0, 0.05, ""]],
	["Graphics", "glow_bicubic", "Smooth glow upscale", "bool", true],
	["Graphics", "vol_fog", "Volumetric fog", "bool", false],
	["Graphics", "vol_fog_density", "Fog density", "range", 0.01, [0.0, 0.1, 0.002, ""]],
	["Graphics", "vol_fog_size", "Fog detail", "enum", 1, ["Low (64)", "Medium (128)", "High (256)", "Ultra (512)"]],
	["Graphics", "vol_fog_filter", "Smooth fog", "bool", true],
	["Graphics", "depth_fog", "Distance haze", "bool", false],
	["Graphics", "depth_fog_density", "Haze density", "range", 0.005, [0.0, 0.05, 0.001, ""]],
	["Graphics", "sss_quality", "Subsurface scattering", "enum", 1, ["Off", "Low", "Medium", "High"]],
	["Graphics", "roughness_limiter", "Specular anti-aliasing", "bool", false],
	["Graphics", "filter_quality", "Decal and projector filtering", "enum", 2, ["Nearest", "Linear", "Linear mipmaps", "Linear mipmaps anisotropic (best)"]],
	["Graphics", "", "Look", "head"],
	["Graphics", "outline_strength", "Outlines", "range", 0.55, [0.0, 1.0, 0.05, ""],
		null, "How dark and thick the cartoon outlines are. 0 turns them off."],
	["Graphics", "debris_detail", "Debris detail", "enum", 2, ["Chunky", "Normal", "Fine", "Very fine"],
		null, "How small things break up. Finer is more pieces, which costs frame rate in big collapses. Applies to the next block."],
	["Graphics", "", "Colour", "head"],
	["Graphics", "tonemap", "Tone mapping", "enum", 2, ["Linear", "Reinhard", "Filmic", "ACES", "AgX"]],
	["Graphics", "exposure", "Exposure", "range", 1.0, [0.25, 3.0, 0.05, ""]],
	["Graphics", "brightness", "Brightness", "range", 1.0, [0.5, 2.0, 0.05, ""]],
	["Graphics", "contrast", "Contrast", "range", 1.0, [0.5, 2.0, 0.05, ""]],
	["Graphics", "saturation", "Saturation", "range", 1.0, [0.0, 2.0, 0.05, ""]],
	# --- Sound ------------------------------------------------------------
	["Sound", "", "Volume", "head"],
	["Sound", "vol_master", "Master", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_sfx", "Effects", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_outdoor", "Outdoor gunshots", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_indoor", "Indoor sounds", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_ambience", "Background (street, rooms)", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_vehicles", "Engines and tyres", "range", 100, [0, 100, 1, "%"]],
	["Sound", "vol_music", "Music", "range", 60, [0, 100, 1, "%"]],
	["Sound", "vol_radio", "Police radio", "range", 80, [0, 100, 1, "%"]],
	["Sound", "", "Output", "head"],
	["Sound", "device", "Output device", "enum", 0, "@devices"],
	["Sound", "mute_unfocused", "Mute when the game is in the background", "bool", false],
	# --- Gameplay ---------------------------------------------------------
	["Gameplay", "", "Rules (the host's settings count when playing online)", "head"],
	["Gameplay", "gore", "Gore", "enum", 3, ["Off", "Some", "Lots", "Extreme"],
		null, "Blood sprays, splats on walls, pools, wounds and, on Extreme, bits and broken bones. Only on your screen."],
	["Gameplay", "friendly_fire", "Friendly fire", "bool", true,
		null, "Officers' bullets, punches and kicks hurt other officers. Blasts always hurt."],
	["Gameplay", "", "Camera", "head"],
	["Gameplay", "cam_rotate_speed", "Rotate speed (hold Q / E)", "range", 120.0, [30.0, 360.0, 10.0, " deg/s"]],
	["Gameplay", "tp_sensitivity", "Mouse look sensitivity", "range", 1.0, [0.2, 3.0, 0.05, "x"]],
	["Gameplay", "cam_follow", "Follow tightness", "range", 8.0, [2.0, 20.0, 0.5, ""]],
	["Gameplay", "cam_zoom", "Starting zoom", "range", 16.0, [6.0, 48.0, 1.0, ""]],
	["Gameplay", "cam_zoom_max", "Furthest zoom", "range", 48.0, [16.0, 96.0, 2.0, ""]],
	["Gameplay", "cutaway", "See inside buildings (fade walls and roofs)", "bool", true],
	["Gameplay", "camera_shake", "Camera shake", "range", 1.0, [0.0, 2.0, 0.1, ""]],
	["Gameplay", "", "Screen", "head"],
	["Gameplay", "ammo_hud", "Ammo panel", "bool", true],
	["Gameplay", "reticle", "Aiming reticle", "bool", true],
	["Gameplay", "minimap", "Mini map", "enum", 1, ["Off", "Small", "Large (whole city)"],
		null, "The map in the bottom left corner: roads, buildings, officers, jobs and the way to the nearest job. The mini map key (M) switches between Small, Large and Off."],
	["Gameplay", "minimap_rotate", "Mini map turns with the camera", "bool", true,
		null, "On: up on the small map is the way you're looking. Off: north is always up."],
	["Gameplay", "job_markers", "Job markers on screen", "bool", true,
		null, "A marker over each job with its distance, seen through walls, and an arrow at the screen edge when it's off screen."],
	["Gameplay", "tips", "Tips while playing", "bool", true,
		null, "A short tip the first time something comes up: your first car, first job, first wound and so on. Each shows once."],
	["Gameplay", "tips_reset", "Show every tip again", "button", null, "reset_tips",
		"Forget which tips you've seen, so they all come up again."],
	["Gameplay", "", "Controls", "head"],
	["Gameplay", "pad_deadzone", "Controller stick dead zone", "range", 0.2, [0.05, 0.5, 0.01, ""]],
	["Gameplay", "rebind", "Change keys...", "button", null, "open_controls"],
	# --- Debug ------------------------------------------------------------
	["Debug", "", "On screen", "head"],
	["Debug", "show_fps", "Frame rate counter", "bool", false],
	["Debug", "show_perf", "Performance details (draw calls, memory)", "bool", false],
	["Debug", "net_overlay", "Network overlay at start (F3)", "bool", false],
	["Debug", "draw_mode", "Render view", "enum", 0, "@draw_modes"],
	["Debug", "collision_shapes", "Show collision shapes (next scene)", "bool", false],
	["Debug", "", "Network testing", "head"],
	["Debug", "fake_latency", "Fake round trip", "range", 0, [0, 500, 5, " ms"]],
	["Debug", "fake_jitter", "Fake jitter", "range", 0, [0, 100, 1, " ms"]],
	["Debug", "fake_loss", "Fake packet loss", "range", 0, [0, 50, 1, "%"]],
	["Debug", "", "Test scenes", "head"],
	["Debug", "tests", "Open a test scene...", "button", null, "show_tests"],
	["Debug", "", "Simulation (single player only)", "head"],
	["Debug", "time_scale", "Game speed", "range", 1.0, [0.1, 2.0, 0.05, "x"]],
	["Debug", "", "Cheats (in game)", "head"],
	["Debug", "max_money", "Max money", "button", null, "max_money",
		"Fills the station's pay to £9,999,999 so you can buy anything at the armoury. In a game you're hosting, or playing alone."],
]

## Tooltips for the rows that have no help text in SCHEMA.
const TIPS := {
	"window_mode": "Windowed, borderless fullscreen (quick to Alt-Tab), exclusive fullscreen (can be a little faster) or a maximised window.",
	"resolution": "The window's size when Window is set to Windowed.",
	"screen": "Which monitor the game opens on.",
	"vsync": "Matches frames to your screen's refresh to stop tearing. Off gives the most frames but can tear. The frame rate can't go above the refresh rate while it's on.",
	"max_fps": "Caps the frame rate, to keep the graphics card cooler and quieter.",
	"driver": "Vulkan suits most cards. Try Direct3D 12 if the game stutters or crashes. Needs a restart.",
	"preset": "Sets everything below in one go, from Low to Max. Epic is the one to play on at 4K; Max is for screenshots.",
	"scaling_mode": "How a 3D render scale below 1 is scaled up. FSR 2 looks best and smooths edges too.",
	"fsr_sharpness": "How much FSR sharpens. 0 is sharpest.",
	"msaa": "Smooths the edges of objects. Costs frame rate, more at 4K. Not needed with FSR 2.",
	"screen_aa": "Cheap edge smoothing over the whole picture. FXAA is softer, SMAA sharper.",
	"taa": "Smooths edges over several frames. Can smear a little when moving.",
	"debanding": "Hides colour bands in skies and smooth gradients. Almost free.",
	"anisotropy": "Keeps roads and floors sharp at a slant. Almost free.",
	"mipmap_bias": "Below 0 makes textures sharper (can shimmer), above 0 softer.",
	"lod_threshold": "How soon far-off things switch to simpler models. Lower keeps more detail.",
	"sun_shadows": "Shadows from the sun and moon.",
	"sun_shadow_size": "Sharper sun shadows at higher sizes. 8192 and up need a lot of video memory.",
	"sun_shadow_distance": "How far away things still cast sun shadows. Further costs frame rate.",
	"sun_shadow_splits": "More splits keep near shadows sharp and still reach far.",
	"sun_shadow_blur": "Softens the edges of sun shadows.",
	"lamp_shadows": "Shadows from torches and blasts.",
	"lamp_shadow_size": "Sharpness of torch and lamp shadows.",
	"shadow_filter": "Smoother shadow edges at higher settings.",
	"shadow_16bit": "Uses less video memory for shadows. Rarely visible.",
	"ssao": "Darkens corners and creases so things sit in the world.",
	"ssao_quality": "Higher is smoother and costs more.",
	"ssao_intensity": "How dark the corners get.",
	"ssao_half": "Works out ambient occlusion at half resolution: faster, a bit softer.",
	"ssil": "Light bouncing off nearby surfaces, like a red wall tinting the floor.",
	"ssil_quality": "Higher is smoother and costs more.",
	"ssil_half": "Works out bounced light at half resolution: faster.",
	"ssr": "Reflections in wet roads, windows and shiny floors.",
	"ssr_steps": "More steps give cleaner reflections and cost more.",
	"ssr_roughness": "Blurry reflections on rough surfaces.",
	"sdfgi_rays": "More rays settle the light faster and cleaner.",
	"sdfgi_converge": "Frames it takes the light to settle after things change.",
	"gi_half": "Works out global illumination at half resolution: faster.",
	"voxel_gi_quality": "Quality of baked light in the interiors that use it.",
	"glow": "Bright lights glow: street lamps, light bars, fires, muzzle flashes.",
	"glow_intensity": "How strong the glow is.",
	"glow_bloom": "Makes the whole bright picture bloom a little.",
	"glow_bicubic": "Smoother glow, almost free.",
	"vol_fog": "Light shafts and fog you can see torch beams in. Heavy.",
	"vol_fog_density": "How thick the fog is.",
	"vol_fog_size": "Finer fog detail costs more.",
	"vol_fog_filter": "Smooths the fog.",
	"depth_fog": "A haze that fades the far city.",
	"depth_fog_density": "How thick the haze is.",
	"sss_quality": "Light through skin, so faces look softer.",
	"roughness_limiter": "Cuts sparkly flicker on shiny edges.",
	"filter_quality": "Sharpness of blood splats, bullet holes and torch patterns.",
	"tonemap": "How bright light is squeezed onto your screen. Filmic is the default; ACES and AgX are punchier.",
	"exposure": "Overall brightness of the lighting.",
	"brightness": "Brightens or darkens the picture.",
	"contrast": "Difference between dark and light.",
	"saturation": "How strong the colours are. 0 is black and white.",
	"vol_master": "Everything.",
	"vol_sfx": "Every sound effect: guns, impacts, glass, footsteps, voices.",
	"vol_outdoor": "Gunshots and blasts in the street.",
	"vol_indoor": "Gunshots and sounds inside buildings.",
	"vol_ambience": "The street, traffic hum, rain and rooms.",
	"vol_vehicles": "Engines, tyres and sirens.",
	"vol_music": "The title theme, patrol music and the fight music.",
	"vol_radio": "Dispatch reading out jobs, and other units' chatter.",
	"device": "Speakers or headphones to play through.",
	"mute_unfocused": "Silences the game while you're in another window.",
	"cam_rotate_speed": "Only for the old top-down test scenes.",
	"tp_sensitivity": "How fast the camera turns with the mouse.",
	"cam_follow": "How tightly the camera keeps up with you. Higher is snappier, lower is smoother.",
	"cam_zoom": "How far out the camera starts (the mouse wheel moves it in a game).",
	"cam_zoom_max": "How far out the mouse wheel can take the camera.",
	"cutaway": "Fades the floors above you inside buildings so nothing hangs over you.",
	"camera_shake": "How much blasts, gunfire and crashes shake the camera. 0 turns it off.",
	"ammo_hud": "The rounds, wounds, first aid and grenades panel at the bottom right.",
	"reticle": "The dot in the middle of the screen that shows where shots go.",
	"pad_deadzone": "How far a controller stick has to move before it counts. Raise it if your officer drifts.",
	"rebind": "Change any key, mouse button or controller button.",
	"show_fps": "Frame rate in the corner (F11 does it in a game).",
	"show_perf": "Draw calls, memory and physics bodies, for tracking down slowdowns.",
	"net_overlay": "Shows ping, packets and where you are when a game starts.",
	"draw_mode": "Debug views of how the picture is built.",
	"collision_shapes": "Draws the invisible physics shapes from the next scene on.",
	"fake_latency": "Adds lag on purpose, to test how online play feels.",
	"fake_jitter": "Makes the fake lag uneven.",
	"fake_loss": "Drops some network packets on purpose.",
	"tests": "The old test scenes: shooting range, listening room, destruction and more.",
	"time_scale": "Slows down or speeds up the game. Playing alone only.",
}


## Graphics presets: key -> value, applied over the current settings.
## v0.8.1: retuned for frame rate. Epic is the top everyday preset (aim:
## 80+ fps at 4K on a strong card): FSR 2 upscaling from 77% does the
## anti-aliasing better than MSAA + SMAA + TAA together did, at a fraction
## of the cost. Max draws at full resolution with every effect up; it is
## for screenshots, not for playing at 4K.
const PRESETS := {
	"Low": {"render_scale": 0.67, "scaling_mode": 1, "msaa": 0, "screen_aa": 1, "taa": false, "anisotropy": 1,
		"sun_shadow_size": 0, "sun_shadow_splits": 1, "sun_shadow_distance": 50.0, "lamp_shadows": false, "shadow_filter": 1,
		"ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "glow": false, "vol_fog": false, "lod_threshold": 2.0,
		"occlusion_culling": true},
	"Medium": {"render_scale": 0.77, "scaling_mode": 2, "msaa": 0, "screen_aa": 0, "taa": false, "anisotropy": 2,
		"sun_shadow_size": 1, "sun_shadow_splits": 1, "sun_shadow_distance": 60.0, "lamp_shadows": true, "lamp_shadow_size": 1,
		"shadow_filter": 2, "ssao": false, "ssil": false, "ssr": false, "sdfgi": false, "glow": true, "vol_fog": false,
		"lod_threshold": 1.0, "occlusion_culling": true},
	"High": {"render_scale": 0.77, "scaling_mode": 2, "msaa": 0, "screen_aa": 0, "taa": false, "anisotropy": 3,
		"sun_shadow_size": 2, "sun_shadow_splits": 2, "sun_shadow_distance": 80.0, "lamp_shadows": true, "lamp_shadow_size": 2,
		"shadow_filter": 2, "ssao": true, "ssao_quality": 1, "ssao_half": true, "ssil": false, "ssr": false,
		"sdfgi": false, "glow": true, "vol_fog": false, "lod_threshold": 1.0, "occlusion_culling": true},
	"Epic": {"render_scale": 0.77, "scaling_mode": 2, "fsr_sharpness": 0.2, "msaa": 0, "screen_aa": 0, "taa": false, "anisotropy": 4,
		"sun_shadow_size": 2, "sun_shadow_splits": 2, "sun_shadow_distance": 90.0, "lamp_shadows": true, "lamp_shadow_size": 2,
		"shadow_filter": 3, "shadow_16bit": true, "ssao": true, "ssao_quality": 2, "ssao_half": true,
		"ssil": true, "ssil_quality": 1, "ssil_half": true, "ssr": true, "ssr_steps": 48, "ssr_roughness": 1,
		"sdfgi": true, "sdfgi_rays": 2, "sdfgi_converge": 3, "gi_half": true, "glow": true, "vol_fog": false,
		"lod_threshold": 1.0, "occlusion_culling": true},
	"Max": {"render_scale": 1.0, "scaling_mode": 2, "msaa": 0, "screen_aa": 0, "taa": false, "anisotropy": 4,
		"sun_shadow_size": 3, "sun_shadow_splits": 2, "sun_shadow_distance": 140.0, "lamp_shadows": true,
		"lamp_shadow_size": 3, "shadow_filter": 4, "shadow_16bit": false,
		"ssao": true, "ssao_quality": 3, "ssao_half": false, "ssil": true, "ssil_quality": 3, "ssil_half": false,
		"ssr": true, "ssr_steps": 128, "ssr_roughness": 2,
		"sdfgi": true, "sdfgi_rays": 4, "gi_half": false, "glow": true, "vol_fog": true, "vol_fog_size": 2,
		"sss_quality": 2, "roughness_limiter": true, "lod_threshold": 0.5, "occlusion_culling": true},
}

var values := {}
var _fps_label: Label
var _layer: CanvasLayer


func _enter_tree() -> void:
	# Wireframe view needs wireframe copies made before meshes load.
	RenderingServer.set_debug_generate_wireframes(true)
	for e in SCHEMA:
		if e[3] in ["bool", "enum", "range"]:
			values[e[1]] = e[4]
	_load()
	get_tree().node_added.connect(_on_node_added)


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 90
	add_child(_layer)
	_fps_label = Label.new()
	# Top right (v0.15.0: the mini map has the bottom left corner).
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 4)
	_fps_label.anchor_left = 1.0
	_fps_label.anchor_right = 1.0
	_fps_label.offset_left = -420
	_fps_label.offset_right = -12
	_fps_label.offset_top = 8
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_layer.add_child(_fps_label)
	apply_all()


func entry(key: String) -> Array:
	for e in SCHEMA:
		if e[1] == key:
			return e
	return []


func get_value(key: String) -> Variant:
	return values.get(key)


## The option names of an enum entry (some are read from the machine).
func options(e: Array) -> Array:
	var o = e[5]
	if o is Array:
		return o
	match String(o):
		"@screens":
			var out := []
			for i in DisplayServer.get_screen_count():
				out.append("Screen %d (%dx%d)" % [i + 1, DisplayServer.screen_get_size(i).x, DisplayServer.screen_get_size(i).y])
			return out if not out.is_empty() else ["Screen 1"]
		"@devices":
			return Array(AudioServer.get_output_device_list())
		"@draw_modes":
			return DRAW_MODES.map(func(d): return d[0])
	return []


func set_value(key: String, v: Variant, save := true) -> void:
	if values.get(key) == v:
		return
	values[key] = v
	_apply_key(key)
	if save:
		_save()
	changed.emit(key)


func apply_preset(name: String) -> void:
	for k in PRESETS[name]:
		values[k] = PRESETS[name][k]
	_save()
	apply_all()
	changed.emit("")


func reset_tab(tab: String) -> void:
	for e in SCHEMA:
		if e[0] == tab and e[3] in ["bool", "enum", "range"]:
			values[e[1]] = e[4]
	_save()
	apply_all()
	changed.emit("")


func needs_restart() -> bool:
	return _wanted_override() != _current_override()


func restart() -> void:
	OS.set_restart_on_exit(true, OS.get_cmdline_args())
	get_tree().quit()


# --- applying -------------------------------------------------------------

func apply_all() -> void:
	_apply_display()
	_apply_viewport()
	_apply_globals()
	_apply_audio()
	_apply_debug()
	_apply_input()
	_write_override()
	_apply_scene(get_tree().root)


func _apply_input() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back", "aim_left", "aim_right", "aim_up", "aim_down"]:
		if InputMap.has_action(a):
			InputMap.action_set_deadzone(a, values.pad_deadzone)


func _apply_key(key: String) -> void:
	var tab: String = entry(key)[0] if not entry(key).is_empty() else ""
	if key in ["window_mode", "resolution", "screen", "vsync", "max_fps"]:
		_apply_display()
	elif key in ["renderer", "driver"]:
		_write_override()
	elif tab == "Sound":
		_apply_audio()
	elif tab == "Debug":
		_apply_debug()
	else:
		_apply_viewport()
		_apply_globals()
		_apply_input()
		_apply_scene(get_tree().root)


func _apply_display() -> void:
	if DisplayServer.get_name() == "headless":
		Engine.max_fps = FPS_CAPS[values.max_fps]
		return
	var scr: int = clampi(values.screen, 0, DisplayServer.get_screen_count() - 1)
	if DisplayServer.window_get_current_screen() != scr:
		DisplayServer.window_set_current_screen(scr)
	var mode: int = [DisplayServer.WINDOW_MODE_WINDOWED, DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN, DisplayServer.WINDOW_MODE_MAXIMIZED][values.window_mode]
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	if mode == DisplayServer.WINDOW_MODE_WINDOWED:
		var parts: PackedStringArray = String(RESOLUTIONS[values.resolution]).split("x")
		var size := Vector2i(int(parts[0]), int(parts[1]))
		var usable := DisplayServer.screen_get_usable_rect(scr).size
		size = size.min(usable)
		if DisplayServer.window_get_size() != size:
			DisplayServer.window_set_size(size)
			var origin := DisplayServer.screen_get_usable_rect(scr).position
			DisplayServer.window_set_position(origin + (usable - size) / 2)
	DisplayServer.window_set_vsync_mode([DisplayServer.VSYNC_DISABLED, DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE, DisplayServer.VSYNC_MAILBOX][values.vsync])
	Engine.max_fps = FPS_CAPS[values.max_fps]


func _apply_viewport() -> void:
	var vp := get_tree().root
	vp.scaling_3d_scale = values.render_scale
	vp.scaling_3d_mode = [Viewport.SCALING_3D_MODE_BILINEAR, Viewport.SCALING_3D_MODE_FSR, Viewport.SCALING_3D_MODE_FSR2][values.scaling_mode]
	vp.fsr_sharpness = values.fsr_sharpness
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_8X][values.msaa]
	vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_FXAA, Viewport.SCREEN_SPACE_AA_SMAA][values.screen_aa]
	vp.use_taa = values.taa
	vp.use_debanding = values.debanding
	vp.anisotropic_filtering_level = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X,
		Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X][values.anisotropy]
	vp.texture_mipmap_bias = values.mipmap_bias
	vp.mesh_lod_threshold = values.lod_threshold
	vp.use_occlusion_culling = values.occlusion_culling
	vp.positional_shadow_atlas_size = SHADOW_SIZES[values.lamp_shadow_size]
	vp.positional_shadow_atlas_16_bits = values.shadow_16bit
	vp.debug_draw = DRAW_MODES[clampi(values.draw_mode, 0, DRAW_MODES.size() - 1)][1]


func _apply_globals() -> void:
	Cel.set_outline_strength(values.outline_strength)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_SIZES[values.sun_shadow_size], values.shadow_16bit)
	var fq: int = values.shadow_filter
	RenderingServer.directional_soft_shadow_filter_set_quality(fq)
	RenderingServer.positional_soft_shadow_filter_set_quality(fq)
	RenderingServer.environment_set_ssao_quality(values.ssao_quality, values.ssao_half, 0.5, 2, 50.0, 300.0)
	RenderingServer.environment_set_ssil_quality(values.ssil_quality, values.ssil_half, 0.5, 4, 50.0, 300.0)
	RenderingServer.environment_set_ssr_roughness_quality(values.ssr_roughness)
	RenderingServer.environment_set_sdfgi_ray_count(values.sdfgi_rays)
	RenderingServer.environment_set_sdfgi_frames_to_converge(values.sdfgi_converge)
	RenderingServer.gi_set_use_half_resolution(values.gi_half)
	RenderingServer.voxel_gi_set_quality(values.voxel_gi_quality)
	RenderingServer.environment_glow_set_use_bicubic_upscale(values.glow_bicubic)
	var fog_size: int = [64, 128, 256, 512][values.vol_fog_size]
	RenderingServer.environment_set_volumetric_fog_volume_size(fog_size, fog_size)
	RenderingServer.environment_set_volumetric_fog_filter_active(values.vol_fog_filter)
	RenderingServer.sub_surface_scattering_set_quality(values.sss_quality)
	RenderingServer.screen_space_roughness_limiter_set_active(values.roughness_limiter, 0.25, 0.18)
	var filt: int = [0, 1, 3, 5][values.filter_quality]
	RenderingServer.decals_set_filter(filt)
	RenderingServer.light_projectors_set_filter(filt)


func _apply_scene(n: Node) -> void:
	_apply_node(n)
	for c in n.get_children():
		_apply_scene(c)


func _on_node_added(n: Node) -> void:
	if n is WorldEnvironment or n is Light3D or n is IsoCamera or n is AmmoHud or n is Reticle or n is NetOverlay:
		_apply_node.call_deferred(n)


func _apply_node(n: Node) -> void:
	if not is_instance_valid(n):
		return
	if n is WorldEnvironment and (n as WorldEnvironment).environment:
		_apply_env((n as WorldEnvironment).environment)
	elif n is DirectionalLight3D:
		var l := n as DirectionalLight3D
		l.shadow_enabled = values.sun_shadows
		l.directional_shadow_max_distance = values.sun_shadow_distance
		l.directional_shadow_mode = [DirectionalLight3D.SHADOW_ORTHOGONAL, DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS,
			DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS][values.sun_shadow_splits]
		l.shadow_blur = values.sun_shadow_blur
	elif n is OmniLight3D or n is SpotLight3D:
		# v0.8.1: only lights made to cast shadows (torches, blasts) get
		# them. Before, every lamp, light bar and fire cast one, which cost
		# more than anything else at night.
		var l := n as Light3D
		if not l.has_meta("wants_shadow"):
			l.set_meta("wants_shadow", l.shadow_enabled)
		l.shadow_enabled = values.lamp_shadows and bool(l.get_meta("wants_shadow"))
	elif n is IsoCamera:
		var c := n as IsoCamera
		c.rotate_speed_deg = values.cam_rotate_speed
		c.follow_sharpness = values.cam_follow
		c.zoom_max = values.cam_zoom_max
		if not c.has_meta("zoom_set"):
			c.set_meta("zoom_set", true)
			c.zoom = clampf(values.cam_zoom, c.zoom_min, c.zoom_max)
	elif n is AmmoHud:
		(n as CanvasLayer).visible = values.ammo_hud
	elif n is Reticle:
		n.set("visible", values.reticle)
	elif n is NetOverlay:
		var p = n.get("_panel")
		if p and not n.has_meta("shown_set"):
			n.set_meta("shown_set", true)
			p.visible = values.net_overlay


func _apply_env(env: Environment) -> void:
	env.ssao_enabled = values.ssao
	env.ssao_intensity = values.ssao_intensity
	env.ssil_enabled = values.ssil
	env.ssr_enabled = values.ssr
	env.ssr_max_steps = int(values.ssr_steps)
	env.sdfgi_enabled = values.sdfgi
	env.glow_enabled = values.glow
	env.glow_intensity = values.glow_intensity
	env.glow_bloom = values.glow_bloom
	env.volumetric_fog_enabled = values.vol_fog
	env.volumetric_fog_density = values.vol_fog_density
	env.fog_enabled = values.depth_fog
	env.fog_density = values.depth_fog_density
	env.tonemap_mode = [Environment.TONE_MAPPER_LINEAR, Environment.TONE_MAPPER_REINHARDT, Environment.TONE_MAPPER_FILMIC,
		Environment.TONE_MAPPER_ACES, Environment.TONE_MAPPER_AGX][values.tonemap]
	env.tonemap_exposure = values.exposure
	var adj: bool = values.brightness != 1.0 or values.contrast != 1.0 or values.saturation != 1.0
	env.adjustment_enabled = adj
	env.adjustment_brightness = values.brightness
	env.adjustment_contrast = values.contrast
	env.adjustment_saturation = values.saturation


func _apply_audio() -> void:
	Sfx.ensure_buses()
	_bus_volume("Master", values.vol_master)
	_bus_volume(Sfx.BUS_SFX, values.vol_sfx)
	for b in Sfx.OUTDOOR_BUSES:
		_bus_volume(b, values.vol_outdoor)
	for b in Sfx.INDOOR_BUSES:
		_bus_volume(b, values.vol_indoor)
	_bus_volume(Sfx.BUS_AMBIENCE, values.vol_ambience)
	_bus_volume(Sfx.BUS_VEHICLES, values.vol_vehicles)
	_bus_volume(Sfx.BUS_MUSIC, values.vol_music)
	_bus_volume(Sfx.BUS_RADIO, values.vol_radio)
	var devs := AudioServer.get_output_device_list()
	if devs.size() > 0:
		var want: String = devs[clampi(values.device, 0, devs.size() - 1)]
		if AudioServer.output_device != want:
			AudioServer.output_device = want


func _bus_volume(bus: String, pct: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0:
		return
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(pct / 100.0, 0.0001)))
	AudioServer.set_bus_mute(i, pct <= 0.0)


func _apply_debug() -> void:
	Net.sim_latency_ms = values.fake_latency
	Net.sim_jitter_ms = values.fake_jitter
	Net.sim_loss = values.fake_loss / 100.0
	get_tree().debug_collisions_hint = values.collision_shapes
	Engine.time_scale = values.time_scale if not Net.is_online() else 1.0
	get_tree().root.debug_draw = DRAW_MODES[clampi(values.draw_mode, 0, DRAW_MODES.size() - 1)][1]
	for n in get_tree().root.find_children("*", "NetOverlay", true, false):
		var p = n.get("_panel")
		if p:
			p.visible = values.net_overlay


func _process(_delta: float) -> void:
	if _fps_label == null:
		return
	_fps_label.visible = values.show_fps or values.show_perf
	if not _fps_label.visible:
		return
	var t := "%d fps  (%.1f ms)" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0)]
	if values.show_perf:
		t += "\ndraw calls %d   objects %d   primitives %dk" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0)]
		t += "\nvideo memory %d MB   memory %d MB   physics bodies %d" % [
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0),
			int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0),
			Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)]
		t += "\nrender scale %.2f   %s" % [values.render_scale, RenderingServer.get_video_adapter_name()]
	_fps_label.text = t


func _notification(what: int) -> void:
	if not values.has("mute_unfocused"):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and values.mute_unfocused:
		AudioServer.set_bus_mute(0, true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		AudioServer.set_bus_mute(0, values.vol_master <= 0)


# --- saving ---------------------------------------------------------------

func _save() -> void:
	var cfg := ConfigFile.new()
	for e in SCHEMA:
		if e[3] in ["bool", "enum", "range"]:
			cfg.set_value(e[0], e[1], values[e[1]])
	cfg.set_value("Meta", "rev", REV)
	cfg.save(SAVE_PATH)


## v0.8.1: settings saved by older builds get these reset to the new
## defaults once (the performance pass changed what they should be).
const REV := 2
const REV_RESET := {2: ["occlusion_culling", "sun_shadow_distance", "lod_threshold"]}


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var rev: int = cfg.get_value("Meta", "rev", 1)
	for e in SCHEMA:
		if e[3] in ["bool", "enum", "range"] and cfg.has_section_key(e[0], e[1]):
			var v = cfg.get_value(e[0], e[1])
			if typeof(v) == typeof(e[4]) or (e[3] == "range" and typeof(v) in [TYPE_INT, TYPE_FLOAT]):
				values[e[1]] = v
	for r in REV_RESET:
		if rev < r:
			for k in REV_RESET[r]:
				values[k] = entry(k)[4]
	if rev < REV:
		_save()


func _wanted_override() -> Dictionary:
	return {
		"rendering_method": ["forward_plus", "mobile", "gl_compatibility"][values.renderer],
		"driver": ["vulkan", "d3d12"][values.driver],
	}


func _current_override() -> Dictionary:
	var method := String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "forward_plus"))
	var drv := RenderingServer.get_current_rendering_driver_name()
	return {"rendering_method": method, "driver": "d3d12" if drv == "d3d12" else ("vulkan" if drv == "vulkan" else _wanted_override().driver)}


func _write_override() -> void:
	var w := _wanted_override()
	var cfg := ConfigFile.new()
	cfg.set_value("rendering", "renderer/rendering_method", w.rendering_method)
	cfg.set_value("rendering", "rendering_device/driver.windows", w.driver)
	cfg.save(OVERRIDE_PATH)
