extends Node2D
class_name BattleFxFloatingText
## Per the request ("show a floating damage (after mitigation) float
## away from the target for a few seconds then disappear"): a small
## number that rises straight up from wherever it's spawned and fades
## out, then frees itself. Used for every attack FX below (melee,
## ranged, magic missile, AoE explosion) whenever the hit actually
## dealt damage — the caller is responsible for only spawning this
## when wounds > 0, per the request's own "if the hit causes damage."

const RISE_DISTANCE := 46.0
const DURATION := 1.6

var _label: Label
var _elapsed := 0.0
var _base_position: Vector2

func _ready() -> void:
	## Real bug (caught via a headless screenshot verification): _process()
	## below used to assign straight into `position.y`, which clobbered
	## the actual spawn position set by the caller right before
	## add_child() — the number rose from world-origin (0,0) instead of
	## from the target's own token, landing far off in the corner of the
	## map instead of floating up over the hit. Captured here, once,
	## before _process() ever runs, and every frame's Y is now computed
	## as an offset FROM this instead of overwriting position.y outright.
	_base_position = position
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_label.add_theme_constant_override("shadow_outline_size", 3)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.position = Vector2(-24, -12)
	_label.size = Vector2(48, 20)
	add_child(_label)
	set_process(true)

## `amount`: the post-mitigation Wounds dealt (already > 0, per the
## caller's own guard). `color` lets callers distinguish flavor (e.g. a
## warmer red for physical hits vs a violet tint for magic) without a
## second node type — purely cosmetic, same number either way.
func setup(amount: int, color: Color = Color(0.95, 0.35, 0.25)) -> void:
	_label.text = str(amount)
	_label.add_theme_color_override("font_color", color)

func _process(delta: float) -> void:
	_elapsed += delta
	var t: float = clampf(_elapsed / DURATION, 0.0, 1.0)
	## Eased rise (fast start, slow finish) reads better than a linear
	## float for a "damage popup" — position itself is otherwise plain
	## world-space, since this node's parent (BattleFxLayer) sits at
	## origin (0,0) in the same local pixel space battle_grid_view.gd's
	## own _draw() already uses for tokens.
	position.y = _base_position.y - RISE_DISTANCE * (1.0 - pow(1.0 - t, 2))
	## Held fully opaque for the first third, then fades — keeps the
	## number readable a beat before it starts to disappear.
	modulate.a = 1.0 if t < 0.35 else clampf(1.0 - (t - 0.35) / 0.65, 0.0, 1.0)
	if _elapsed >= DURATION:
		queue_free()
