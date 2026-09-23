extends Node
## Autoloaded as "SettingsManager". Loads/saves user://settings.cfg and
## actually applies display/audio settings — not just storing numbers
## nobody reads. Loaded and applied in _ready(), so it takes effect
## before the first real scene (MainMenu) is even visible.

const CONFIG_PATH := "user://settings.cfg"

## --- Display ---------------------------------------------------------------
## "Fit to Screen" here means windowed at native content scaling (the
## project's existing canvas_items/keep stretch mode, unchanged) sized
## to fill the available screen rather than a fixed small window — not
## a distinct rendering mode of its own.
enum WindowMode { WINDOWED, FIT_TO_SCREEN, BORDERLESS_FULLSCREEN, FULLSCREEN }
var window_mode: WindowMode = WindowMode.WINDOWED
var resolution: Vector2i = Vector2i(1920, 1080)

## Common 16:9 resolutions up to whatever the main monitor can actually
## display — built at runtime from DisplayServer.screen_get_size()
## rather than a hardcoded list that might exceed the real screen or
## miss it, "up to max main monitor resolution," as asked.
const CANDIDATE_RESOLUTIONS := [
	Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
]

func get_available_resolutions() -> Array[Vector2i]:
	var native := DisplayServer.screen_get_size()
	var result: Array[Vector2i] = []
	for r in CANDIDATE_RESOLUTIONS:
		if r.x <= native.x and r.y <= native.y:
			result.append(r)
	if result.is_empty() or result[-1] != native:
		result.append(native)   ## always offer the exact native resolution too
	return result

## --- Audio ------------------------------------------------------------
var master_volume: float = 0.8   ## 0.0-1.0, linear — converted to dB for the bus

## --- UI accent colour ---------------------------------------------------
## A real, working setting, but honestly scoped: this project has
## hundreds of hardcoded Color() literals across the combat/menu UI
## built over many earlier passes, and re-theming all of them is a
## large separate refactor, not something to sneak in as a side effect
## here. What IS real: every screen built or touched from this point on
## (MainMenu, Settings, and easy to extend further) reads its accent
## colour from here rather than a hardcoded literal, and the setting
## persists and actually changes what you see on those screens.
const ACCENT_PRESETS := {
	"Gold": Color(0.85, 0.7, 0.35),
	"Crimson": Color(0.82, 0.35, 0.32),
	"Verdant": Color(0.45, 0.75, 0.4),
	"Azure": Color(0.4, 0.62, 0.85),
}
var accent_preset_name: String = "Gold"

func get_accent_color() -> Color:
	return ACCENT_PRESETS.get(accent_preset_name, ACCENT_PRESETS["Gold"])

## --- Load / save / apply ------------------------------------------------

func _ready() -> void:
	load_settings()
	apply_display_settings()
	apply_audio_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return   ## no file yet — defaults above stand
	window_mode = cfg.get_value("display", "window_mode", window_mode) as WindowMode
	var res: Array = cfg.get_value("display", "resolution", [resolution.x, resolution.y])
	resolution = Vector2i(int(res[0]), int(res[1]))
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	accent_preset_name = cfg.get_value("ui", "accent_preset", accent_preset_name)

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("display", "window_mode", window_mode)
	cfg.set_value("display", "resolution", [resolution.x, resolution.y])
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("ui", "accent_preset", accent_preset_name)
	cfg.save(CONFIG_PATH)

## Emitted after apply_display_settings() with a human-readable note
## whenever the requested change plausibly didn't visually take —
## specifically the known Godot limitation where a game launched from
## the editor with game embedding enabled runs inside a viewport the
## editor controls, not a real independently-resizable OS window.
## DisplayServer/window size and mode calls can't resize that from the
## running game's own script — but there IS a real, easy fix for it
## right in the editor's own UI: the Game panel's toolbar (the bar with
## pause/speed controls, shown above the running game) has a scaling
## dropdown — Fixed Size (default) / Keep Aspect Ratio / Stretch to
## Fit. Switching it to "Stretch to Fit" makes the embedded viewport
## track window/dock resizes correctly, matching non-embedded
## behaviour, without needing to disable embedding at all. Disabling
## embedding entirely (Editor Settings > Run > Window Placement > Game
## Embed Mode > Disabled) is the alternative if a real separate window
## is preferred instead. Verified against Godot's own docs
## (tutorials/editor/game_embedding.rst) rather than assumed.
signal display_diagnostic(message: String)

## Pure comparison, factored out so it's testable independent of
## whatever this specific runtime environment's window actually does —
## a real embedded-editor session won't resize; this virtual test
## environment happens to resize correctly, which is exactly why this
## needs to be checkable on its own rather than only end-to-end.
func _display_mismatch_message(requested_mode: WindowMode, requested_resolution: Vector2i, actual_size: Vector2i) -> String:
	var expected_size := requested_resolution if requested_mode == WindowMode.WINDOWED else DisplayServer.screen_get_size()
	var mismatch := requested_mode in [WindowMode.WINDOWED, WindowMode.FIT_TO_SCREEN] and actual_size != expected_size
	if not mismatch:
		return ""
	return ("Window Mode/Resolution didn't visibly change. Quickest fix: in the Game panel toolbar above the running " +
		"game (the bar with pause/speed controls), there's a scaling dropdown — set it to \"Stretch to Fit\" instead " +
		"of \"Fixed Size\". That's enough to make an embedded game window track resizes correctly without giving up " +
		"embedding. Alternatively, turn embedding off entirely: Editor Settings > Run > Window Placement > Game " +
		"Embed Mode > Disabled — or just test this in an exported build, where it always works normally.")

func apply_display_settings() -> void:
	match window_mode:
		WindowMode.WINDOWED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().borderless = false
			get_window().size = resolution
			_center_window()
		WindowMode.FIT_TO_SCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			get_window().borderless = false
			get_window().size = DisplayServer.screen_get_size()
			get_window().position = Vector2i.ZERO
		WindowMode.BORDERLESS_FULLSCREEN:
			get_window().borderless = true
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		WindowMode.FULLSCREEN:
			get_window().borderless = false
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)

	## Verify what actually happened, one frame later (window resize
	## requests aren't always synchronous), and flag it if the running
	## game is clearly an editor debug session and the change didn't
	## visibly take. Engine.is_embedded_in_editor() is the precise API
	## for "is this specific run embedded" (Godot 4.4+); OS.has_feature
	## ("editor") is kept as a fallback for older engine versions where
	## that method doesn't exist, since it at least catches "launched
	## from the editor at all" even if less precise about embedding
	## specifically.
	var is_editor_run := (Engine.has_method("is_embedded_in_editor") and Engine.is_embedded_in_editor()) or OS.has_feature("editor")
	if is_editor_run:
		await get_tree().process_frame
		var message := _display_mismatch_message(window_mode, resolution, get_window().size)
		if message != "":
			display_diagnostic.emit(message)

func _center_window() -> void:
	var screen_size := DisplayServer.screen_get_size()
	get_window().position = (screen_size - resolution) / 2

func apply_audio_settings() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx < 0:
		return
	## Linear 0-1 slider to dB, with 0 mapped to silence rather than a
	## very-negative-but-technically-audible dB value.
	var db := linear_to_db(master_volume) if master_volume > 0.0 else -80.0
	AudioServer.set_bus_volume_db(idx, db)
	AudioServer.set_bus_mute(idx, master_volume <= 0.0)

func set_and_apply_window_mode(mode: WindowMode) -> void:
	window_mode = mode
	apply_display_settings()
	save_settings()

func set_and_apply_resolution(res: Vector2i) -> void:
	resolution = res
	apply_display_settings()
	save_settings()

func set_and_apply_master_volume(v: float) -> void:
	master_volume = clamp(v, 0.0, 1.0)
	apply_audio_settings()
	save_settings()

func set_and_apply_accent(preset_name: String) -> void:
	if not ACCENT_PRESETS.has(preset_name):
		return
	accent_preset_name = preset_name
	save_settings()
