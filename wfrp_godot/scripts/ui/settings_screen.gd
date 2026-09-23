extends Control

@onready var title_label: Label = %TitleLabel
@onready var back_button: Button = %BackButton
@onready var graphics_header: Label = %GraphicsHeader
@onready var audio_header: Label = %AudioHeader
@onready var ui_header: Label = %UiHeader
@onready var window_mode_option: OptionButton = %WindowModeOption
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var display_diagnostic_label: Label = %DisplayDiagnosticLabel
@onready var volume_slider: HSlider = %VolumeSlider
@onready var volume_value_label: Label = %VolumeValueLabel
@onready var accent_row: HFlowContainer = %AccentRow

const WINDOW_MODE_LABELS := {
	SettingsManager.WindowMode.WINDOWED: "Windowed",
	SettingsManager.WindowMode.FIT_TO_SCREEN: "Fit to Screen",
	SettingsManager.WindowMode.BORDERLESS_FULLSCREEN: "Borderless Fullscreen",
	SettingsManager.WindowMode.FULLSCREEN: "Fullscreen",
}

var available_resolutions: Array[Vector2i] = []

func _ready() -> void:
	_apply_accent_to_headers()
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	SettingsManager.display_diagnostic.connect(_on_display_diagnostic)

	for mode in [SettingsManager.WindowMode.WINDOWED, SettingsManager.WindowMode.FIT_TO_SCREEN,
			SettingsManager.WindowMode.BORDERLESS_FULLSCREEN, SettingsManager.WindowMode.FULLSCREEN]:
		window_mode_option.add_item(WINDOW_MODE_LABELS[mode])
	window_mode_option.selected = SettingsManager.window_mode
	window_mode_option.item_selected.connect(_on_window_mode_selected)

	available_resolutions = SettingsManager.get_available_resolutions()
	for res in available_resolutions:
		resolution_option.add_item("%d x %d" % [res.x, res.y])
	var current_idx := available_resolutions.find(SettingsManager.resolution)
	resolution_option.selected = max(current_idx, 0)
	resolution_option.item_selected.connect(_on_resolution_selected)
	resolution_option.disabled = SettingsManager.window_mode != SettingsManager.WindowMode.WINDOWED

	volume_slider.value = SettingsManager.master_volume
	volume_value_label.text = "%d%%" % int(SettingsManager.master_volume * 100)
	volume_slider.value_changed.connect(_on_volume_changed)

	_build_accent_swatches()

func _apply_accent_to_headers() -> void:
	var c := SettingsManager.get_accent_color()
	title_label.add_theme_color_override("font_color", c)
	graphics_header.add_theme_color_override("font_color", c)
	audio_header.add_theme_color_override("font_color", c)
	ui_header.add_theme_color_override("font_color", c)

func _build_accent_swatches() -> void:
	for child in accent_row.get_children():
		child.queue_free()
	for preset_name in SettingsManager.ACCENT_PRESETS.keys():
		var btn := Button.new()
		btn.text = preset_name + ("  ✓" if preset_name == SettingsManager.accent_preset_name else "")
		var swatch_style := StyleBoxFlat.new()
		swatch_style.bg_color = SettingsManager.ACCENT_PRESETS[preset_name]
		swatch_style.corner_radius_top_left = 4
		swatch_style.corner_radius_top_right = 4
		swatch_style.corner_radius_bottom_left = 4
		swatch_style.corner_radius_bottom_right = 4
		swatch_style.content_margin_left = 12
		swatch_style.content_margin_right = 12
		swatch_style.content_margin_top = 6
		swatch_style.content_margin_bottom = 6
		btn.add_theme_stylebox_override("normal", swatch_style)
		btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
		btn.pressed.connect(func():
			SettingsManager.set_and_apply_accent(preset_name)
			_apply_accent_to_headers()
			_build_accent_swatches()
		)
		accent_row.add_child(btn)

func _on_display_diagnostic(message: String) -> void:
	display_diagnostic_label.text = message
	display_diagnostic_label.visible = true

func _on_window_mode_selected(idx: int) -> void:
	display_diagnostic_label.visible = false
	SettingsManager.set_and_apply_window_mode(idx as SettingsManager.WindowMode)
	## Resolution only means anything in plain Windowed mode — Fit to
	## Screen/Fullscreen both size to the actual display instead.
	resolution_option.disabled = idx != SettingsManager.WindowMode.WINDOWED

func _on_resolution_selected(idx: int) -> void:
	if idx < 0 or idx >= available_resolutions.size():
		return
	display_diagnostic_label.visible = false
	SettingsManager.set_and_apply_resolution(available_resolutions[idx])

func _on_volume_changed(value: float) -> void:
	SettingsManager.set_and_apply_master_volume(value)
	volume_value_label.text = "%d%%" % int(value * 100)
