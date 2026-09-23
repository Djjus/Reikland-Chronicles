extends Node2D
## The game's launch splash screen — an animated ~5 second sequence
## (per the request): helmet appears center first, then the sword and
## axe fly in from either side, then a banner with the title drops
## down from above, then a comet streaks in overhead, and finally an
## orc's head pops up from below. Skippable at any time via any key
## press or mouse click, then transitions to the Main Menu.

@onready var background: Sprite2D = $Background
@onready var vignette: ColorRect = $Vignette
@onready var helmet: Sprite2D = $Helmet
@onready var sword: Sprite2D = $Sword
@onready var axe: Sprite2D = $Axe
@onready var banner: Sprite2D = $Banner
@onready var comet: Sprite2D = $Comet
@onready var orc_head: Sprite2D = $OrcHead
@onready var title_top: Label = $BannerLabel/TitleTop
@onready var title_bottom: Label = $BannerLabel/TitleBottom
@onready var skip_label: Label = $BannerLabel/SkipLabel

## Final resting positions/rotations/scales for each element — the
## values every Sprite2D above starts away from, so the Tween below
## has somewhere real to animate toward.
const HELMET_SCALE := Vector2(1.725, 1.725)
const SWORD_END_POS := Vector2(735, 405)
const SWORD_END_ROT := -0.55
const AXE_END_POS := Vector2(1200, 405)
const AXE_END_ROT := 0.5
const BANNER_END_POS := Vector2(960, 840)
const COMET_END_POS := Vector2(1140, 90)
const COMET_END_ROT := 0.55
const ORC_END_POS := Vector2(1590, 960)

var _skippable := false
var _finished := false

func _ready() -> void:
	vignette.color = Color(0, 0, 0, 1)
	_run_sequence()

func _run_sequence() -> void:
	var tw := create_tween()
	tw.set_parallel(false)

	## Background reveal
	tw.tween_property(vignette, "color:a", 0.0, 0.4)
	tw.tween_callback(func(): _skippable = true)

	## Helmet appears centre-first, with a small overshoot for a bit of
	## weight/punch rather than a flat linear pop-in.
	tw.tween_property(helmet, "modulate:a", 1.0, 0.35)
	tw.parallel().tween_property(helmet, "scale", HELMET_SCALE * 1.15, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(helmet, "scale", HELMET_SCALE, 0.2).set_trans(Tween.TRANS_SINE)

	## Sword flies in from the left, axe from the right, at the same time.
	tw.tween_property(sword, "position", SWORD_END_POS, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(sword, "rotation", SWORD_END_ROT, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(axe, "position", AXE_END_POS, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(axe, "rotation", AXE_END_ROT, 0.8).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	## Banner drops down from above, with the title text fading in
	## partway through the drop rather than waiting for it to land.
	tw.tween_property(banner, "position", BANNER_END_POS, 0.7).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(title_top, "modulate:a", 1.0, 0.5).set_delay(0.25)
	tw.parallel().tween_property(title_bottom, "modulate:a", 1.0, 0.5).set_delay(0.35)

	## Comet streaks in overhead.
	tw.tween_property(comet, "position", COMET_END_POS, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(comet, "rotation", COMET_END_ROT, 0.75)

	## The orc's head pops up from below.
	tw.tween_property(orc_head, "position", ORC_END_POS, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	## Skip hint fades in, then a short hold so the finished scene can
	## actually be seen before transitioning away.
	tw.tween_property(skip_label, "modulate:a", 1.0, 0.3)
	tw.tween_interval(0.7)

	tw.tween_callback(_finish)

func _finish() -> void:
	if _finished:
		return
	_finished = true
	var tw := create_tween()
	tw.tween_property(vignette, "color:a", 1.0, 0.5)
	tw.tween_callback(_go_to_main_menu)

func _go_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if _finished or not _skippable:
		return
	if event is InputEventKey and event.pressed:
		_skip()
	elif event is InputEventMouseButton and event.pressed:
		_skip()

func _skip() -> void:
	if _finished:
		return
	# Stop whatever's still animating and jump every element straight
	# to its final resting pose before fading out, so a skip still
	# reads as "the whole scene", not a half-finished freeze-frame.
	for tw in get_tree().get_processed_tweens():
		tw.kill()
	helmet.modulate.a = 1.0
	helmet.scale = HELMET_SCALE
	sword.position = SWORD_END_POS
	sword.rotation = SWORD_END_ROT
	axe.position = AXE_END_POS
	axe.rotation = AXE_END_ROT
	banner.position = BANNER_END_POS
	title_top.modulate.a = 1.0
	title_bottom.modulate.a = 1.0
	comet.position = COMET_END_POS
	comet.rotation = COMET_END_ROT
	orc_head.position = ORC_END_POS
	skip_label.modulate.a = 1.0
	_finish()
