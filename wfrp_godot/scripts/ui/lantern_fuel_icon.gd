extends Control
class_name LanternFuelIcon
## Per the follow-up request ("place the fuel bar on the character icon
## holding it instead... rather than a thin bar make it a little
## lantern icon which drains downward of light as its used up"): a
## tiny procedurally-drawn lantern silhouette overlaid on a party
## member's own portrait (see Overworld._build_party_panel()/
## _refresh_party_panel()) — no lantern sprite asset exists in this
## project, so it's drawn directly via _draw() rather than adding one,
## matching the pixel-simple style of everything else in the HUD.
##
## The remaining-oil level is shown as the glowing fill INSIDE the
## lantern's glass, anchored to the bottom — as fuel burns down,
## fill_pct shrinks and the glow visibly drains downward/shrinks from
## the top of the glass, leaving a shorter and shorter glowing puddle
## at the base exactly like a real oil reservoir running dry (rather
## than a generic left-to-right progress bar, per the request).

## 0.0 (empty, dark glass) - 1.0 (full glow).
var fill_pct: float = 1.0
## True while the light is actually switched on ("on"/"low") — a
## noticeably brighter glow than merely equipped-but-off, so the icon
## also doubles as an at-a-glance "is it lit right now" indicator.
var lit: bool = false

func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var frame_color := Color(0.12, 0.11, 0.09, 0.95)

	## Small ring/handle loop above the body — just enough of a
	## silhouette to read as "lantern" at a glance.
	draw_rect(Rect2(Vector2(w * 0.42, 0.0), Vector2(w * 0.16, h * 0.12)), frame_color)
	## Cap
	draw_rect(Rect2(Vector2(w * 0.22, h * 0.12), Vector2(w * 0.56, h * 0.1)), frame_color)

	var glass_rect := Rect2(Vector2(w * 0.18, h * 0.24), Vector2(w * 0.64, h * 0.58))
	## Base
	draw_rect(Rect2(Vector2(w * 0.22, glass_rect.position.y + glass_rect.size.y), Vector2(w * 0.56, h * 0.12)), frame_color)

	## Empty/unlit glass background, so the frame reads clearly even
	## when there's no fuel left to glow at all.
	draw_rect(glass_rect, Color(0.06, 0.06, 0.08, 0.9))

	if fill_pct > 0.0:
		var fill_h: float = glass_rect.size.y * clamp(fill_pct, 0.0, 1.0)
		## Anchored to the BOTTOM of the glass — this is the "drains
		## downward" behaviour the request asked for: as fill_pct
		## shrinks, the glow's top edge sinks further down the glass,
		## like an oil level actually falling, rather than a bar
		## emptying left-to-right.
		var fill_rect := Rect2(
			Vector2(glass_rect.position.x, glass_rect.position.y + glass_rect.size.y - fill_h),
			Vector2(glass_rect.size.x, fill_h)
		)
		var glow_color: Color
		if fill_pct > 0.4:
			glow_color = Color(0.98, 0.78, 0.25, 1.0) if lit else Color(0.68, 0.55, 0.25, 0.85)
		elif fill_pct > 0.15:
			glow_color = Color(0.92, 0.55, 0.15, 1.0) if lit else Color(0.65, 0.42, 0.15, 0.85)
		else:
			glow_color = Color(0.88, 0.25, 0.2, 1.0) if lit else Color(0.6, 0.22, 0.16, 0.85)
		draw_rect(fill_rect, glow_color)

	## Glass frame outline drawn last, on top of the fill, so the
	## lantern's silhouette always stays crisp regardless of fill level.
	draw_rect(glass_rect, Color(0.03, 0.03, 0.03, 0.9), false, 1.0)

## Convenience setter used by Overworld._refresh_party_panel() — takes
## care of the redraw so callers don't have to remember to.
func set_fuel(pct: float, is_lit: bool) -> void:
	fill_pct = pct
	lit = is_lit
	queue_redraw()
