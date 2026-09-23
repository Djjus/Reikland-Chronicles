extends RefCounted
class_name RollCardBuilder

## Per the request ("make all numbers bold"): a single shared bold font
## variation, lazily created and reused by every boxed_label() call
## rather than a fresh FontVariation per number — embolden thickens the
## theme's regular font without needing a separate bold font asset.
static var _bold_font: FontVariation = null
static func _get_bold_font() -> FontVariation:
	if _bold_font == null:
		_bold_font = FontVariation.new()
		_bold_font.variation_embolden = 1.2
	return _bold_font
## Shared roll-card rendering, per the request: social encounters
## should use the same visual roll cards combat already does, rather
## than plain text. Extracted from FieldEncounterScreen's own
## _build_roll_card()/_boxed_label() (which were already fully
## self-contained, operating only on the passed-in `data` dict) so
## both FieldEncounterScreen and SocialEncounterScreen render
## identical cards from the exact same code, not two copies that
## could quietly drift apart.
##
## Per the request: every size in this file — font sizes, card width,
## margins, borders, corner radii — is doubled from its own original
## value. The cards had become too small to comfortably read at
## current display resolutions; doubling was the direct, requested
## fix rather than a smaller incremental bump.
##
## Per the follow-up request ("stop hiding information on historic roll
## cards... make the current roll card the same size as historic ones"):
## `compact` now controls ONLY sizing (card width, borders, margins,
## font sizes) — every piece of information (modifiers, the full SL
## breakdown itemisation and its Talent-name line, the damage
## breakdown itemisation and its own name line, and the Effects list)
## renders regardless of `compact`. Previously `compact` also stripped
## all of that content, which is what made historic log entries read
## as a bare one-liner compared to the newest card's full detail. Every
## caller now passes the same `compact` value for every entry (see
## FieldEncounterScreen._rebuild_history_display), so the newest and
## historic cards are visually identical in size, both showing
## everything.
##
## Per the follow-up request ("make the Roll cards 30% smaller"): every
## size below — card width, borders, corner radii, margins,
## separations, font sizes — is scaled to 70% of its own prior value
## (rounded to the nearest pixel/point). Kept as one uniform scale
## rather than shrinking some sizes more than others, same approach as
## the original doubling above.
##
## Per the same follow-up ("make the attack card the same size as the
## defence card"): an attacker's card carries rows a defender's never
## does (Hit Location, the boxed Damage breakdown, its own name line)
## — with those rows built as a single-line HBoxContainer/Label, a long
## damage breakdown (Weapon+SL+Impact+Talent+Buff) or a long list of
## named SL bonuses could force the whole card wider than the shared
## minimum width, which is exactly what made attack cards visibly
## bigger than defence cards. The two rows that can grow unbounded —
## the boxed Damage breakdown and the boxed SL breakdown — now use
## HFlowContainer instead of HBoxContainer (wraps onto a second line at
## the card's own fixed width instead of stretching it), and their
## "named sources" lines below each now wrap (AUTOWRAP_WORD) instead of
## forcing a single long line. Every card — attack or defence — is now
## bounded by the same fixed minimum width from `custom_minimum_size`.
##
## Per the follow-up request ("align the defence card the same way as
## the attack card — text left, numbers right"): the Roll vs Target and
## Success Level rows used to mirror their layout on a defender's card
## (numbers on the left, caption on the right) so an attacker's and a
## defender's card would "face" each other across the middle when shown
## side by side. Every card now reads the same way regardless of side —
## caption/label on the left, numbers on the right — so `is_defender`
## no longer changes row ordering anywhere in this file.
## Per the follow-up request (Social Encounter opposed rolls): the
## Skill-Test-vs-Resist card pair is shown side by side, and the two
## cards reading identically (caption-left, numbers-right on BOTH)
## meant the numbers on the right-hand ("opposing") card sat at the
## far outer edge instead of facing the other card's own numbers
## across the middle. `data["mirror_layout"]` flips just the Roll vs
## Target and Success Level rows for that one card (numbers on the
## left, caption on the right) so the two cards visually face off —
## opt-in per card via the data dict rather than a global change, so
## FieldEncounterScreen's own attacker/defender cards (which already
## went through the opposite change at the earlier request "align the
## defence card the same way as the attack card") are unaffected.
##
## Per the follow-up request ("shrink the size of all roll cards by
## 40%"): every size below — card width, borders, corner radii,
## margins, separations, font sizes — is scaled to 60% of its own
## prior value (rounded to the nearest pixel/point), same uniform-scale
## approach as the earlier 70% pass. Applies to build_roll_card,
## boxed_label, _event_header, _event_shell, build_fumble_card, and
## build_critical_wound_card alike — every card this file draws.
##
## Per the same follow-up ("make all numbers ... bold"): every number
## this file displays is rendered through boxed_label() (the
## yellow/red highlighted values — roll, target, SL, Damage, Wounds,
## Critical/Fumble roll), so boxed_label() now applies BOLD_FONT to its
## Label instead of the theme's regular weight — one change covers
## every numeric display in every card.
##
## Per the follow-up request ("make all combat log roll card 20%
## bigger"): every function below now takes an optional `size_scale`
## (default 1.0, i.e. no change) that multiplies every size that would
## otherwise apply to a COMPACT card only — card width, borders,
## margins, separations, corner-adjacent spacing, font sizes — via the
## _cvali()/_cvalf() helpers just below. The non-compact ("large") size
## of each of those same properties is never touched, and neither is
## anything when size_scale is left at its 1.0 default. Only
## FieldEncounterScreen's own Combat Log (_rebuild_history_display,
## which always builds every card compact) passes a non-default
## size_scale, so SocialEncounter/ScriptedNpcEncounter/
## WildernessEncounter's own historic (also-compact) cards are
## unaffected — this was a request about the Combat Log specifically,
## not every compact card everywhere.
static func _cvali(compact_value: int, large_value: int, compact: bool, size_scale: float) -> int:
	return int(round(compact_value * size_scale)) if compact else large_value

static func _cvalf(compact_value: float, large_value: float, compact: bool, size_scale: float) -> float:
	return (compact_value * size_scale) if compact else large_value

## For sizes that don't currently differ between compact/large (a fixed
## separation, corner radius, etc.) but should still grow when a
## caller asks for bigger compact cards — scales `value` only while
## `compact` is true, otherwise returns it unchanged (matching this
## whole file's existing "large cards are never touched by `compact`
## sizing" convention).
static func _scalei(value: int, compact: bool, size_scale: float) -> int:
	return int(round(value * size_scale)) if compact else value

static func build_roll_card(data: Dictionary, compact: bool = false, size_scale: float = 1.0) -> PanelContainer:
	var test: TestResolver.TestResult = data["test"]
	var side: String = data.get("side", "ally")
	var mirror: bool = data.get("mirror_layout", false)
	var header_color := Color(0.55, 0.18, 0.16) if side == "ally" else Color(0.2, 0.32, 0.5)
	## The losing side of an opposed roll gets its header darkened
	## further, on top of the whole-card dim applied later — a plain
	## modulate alone left the red/blue header too close in brightness
	## to the winner's to read as "lost" at a glance.
	if data.get("dimmed", false):
		header_color = header_color.darkened(0.45)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_cvalf(185, 252, compact, size_scale), 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.11, 0.08, 1)
	card_style.border_width_left = _cvali(1, 2, compact, size_scale)
	card_style.border_width_top = _cvali(1, 2, compact, size_scale)
	card_style.border_width_right = _cvali(1, 2, compact, size_scale)
	card_style.border_width_bottom = _cvali(1, 2, compact, size_scale)
	card_style.border_color = Color(0.72, 0.58, 0.27, 1)
	card_style.corner_radius_top_left = _scalei(5, compact, size_scale)
	card_style.corner_radius_top_right = _scalei(5, compact, size_scale)
	card_style.corner_radius_bottom_left = _scalei(5, compact, size_scale)
	card_style.corner_radius_bottom_right = _scalei(5, compact, size_scale)
	card.add_theme_stylebox_override("panel", card_style)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	card.add_child(outer)

	## Header
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = header_color
	header_style.corner_radius_top_left = _scalei(4, compact, size_scale)
	header_style.corner_radius_top_right = _scalei(4, compact, size_scale)
	header_style.content_margin_left = _scalei(8, compact, size_scale)
	header_style.content_margin_right = _scalei(8, compact, size_scale)
	header_style.content_margin_top = _cvali(4, 5, compact, size_scale)
	header_style.content_margin_bottom = _cvali(4, 5, compact, size_scale)
	header_panel.add_theme_stylebox_override("panel", header_style)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = data.get("character_name", "")
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_font_size_override("font_size", _cvali(9, 11, compact, size_scale))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(name_label)
	var title_lbl := Label.new()
	title_lbl.text = data.get("title", "")
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	title_lbl.add_theme_font_size_override("font_size", _cvali(11, 14, compact, size_scale))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(title_lbl)
	if data.get("subtitle", "") != "":
		var sub_label := Label.new()
		sub_label.text = data["subtitle"]
		sub_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		sub_label.add_theme_font_size_override("font_size", _scalei(9, compact, size_scale))
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		header_box.add_child(sub_label)
	header_panel.add_child(header_box)
	outer.add_child(header_panel)

	## Body
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _cvali(2, 4, compact, size_scale))
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", _cvali(7, 8, compact, size_scale))
	body_margin.add_theme_constant_override("margin_right", _cvali(7, 8, compact, size_scale))
	body_margin.add_theme_constant_override("margin_top", _cvali(4, 7, compact, size_scale))
	body_margin.add_theme_constant_override("margin_bottom", _cvali(4, 7, compact, size_scale))
	body_margin.add_child(body)
	outer.add_child(body_margin)

	for mod: Dictionary in test.target_modifiers:
		var mod_label := Label.new()
		mod_label.text = "Modifier: %s +%d" % [mod["name"], mod["amount"]]
		mod_label.add_theme_font_size_override("font_size", _cvali(7, 9, compact, size_scale))
		mod_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		mod_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(mod_label)

	## Roll vs Target
	## Per the request: every card now reads the same way regardless of
	## attacker/defender side — caption on the left, numbers on the
	## right — rather than the defender's row being mirrored (numbers
	## left, caption right) to "face" the attacker's card.
	var rvt_row := HBoxContainer.new()
	rvt_row.add_theme_constant_override("separation", _scalei(5, compact, size_scale))
	var rvt_caption := Label.new()
	rvt_caption.text = "Roll vs Target"
	rvt_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	rvt_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rvt_vs_label := Label.new()
	rvt_vs_label.text = "vs"
	rvt_vs_label.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	var rvt_roll_box := boxed_label(str(test.roll), test.success, compact, size_scale)
	var rvt_target_box := boxed_label(str(test.target), test.success, compact, size_scale)
	if mirror:
		rvt_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		rvt_row.add_child(rvt_roll_box)
		rvt_row.add_child(rvt_vs_label)
		rvt_row.add_child(rvt_target_box)
		rvt_row.add_child(rvt_caption)
	else:
		rvt_row.add_child(rvt_caption)
		rvt_row.add_child(rvt_roll_box)
		rvt_row.add_child(rvt_vs_label)
		rvt_row.add_child(rvt_target_box)
	body.add_child(rvt_row)

	## Success Level breakdown — the full itemisation now shows
	## regardless of `compact` (see the class-level comment above); a
	## failed roll is still the one case that always collapses to just
	## the plain total. Talent SL bonuses only ever apply on a
	## successful Test (TestResolver never subtracts them into
	## base_success_levels on a failure) — showing the "+2 Dual
	## Wielder" itemisation on a failed roll was genuinely misleading,
	## since the bonus never actually changed the result: it looked
	## like "‑3 + 2 = ‑3", arithmetic that doesn't add up on screen even
	## though the underlying rule (bonuses don't rescue a failure) is
	## correct. Failed rolls now just show the plain total, with no
	## breakdown and no Talent name — nothing to show, since nothing
	## was actually applied.
	## A single HFlowContainer for the whole row (caption AND numbers
	## together) rather than an HBoxContainer with the caption set to
	## expand-fill: an expand-fill sibling only ever gives a nested flow
	## container ITS OWN minimum width (the widest single child), which
	## would make it wrap far more aggressively than the card's actual
	## available width allows. Putting everything in one top-level flow
	## container instead means the whole row is bounded by the card's
	## own fixed width and wraps onto a second line exactly when it
	## needs to, rather than stretching the card wider (see the
	## class-level comment on why this matters for keeping attack/
	## defence cards the same size).
	## Per the request: caption on the left, numbers on the right,
	## same as every other row now — no more defender-side mirroring.
	##
	## Per the follow-up request ("move the SL and Damage number in the
	## roll cards to the far right of the box"), then the further
	## follow-up ("move ALL the numbers to the right, not just the
	## result"): the caption stays put on the left in `sl_row`, but
	## EVERYTHING numeric — the base value, every breakdown entry, the
	## "=" sign, and the final total — now lives together in `sl_numbers`,
	## a single expand-fill HFlowContainer with `alignment = ALIGNMENT_END`
	## so that whole group hugs the card's right edge as one unit (and
	## still wraps as a unit if it's too wide for one line), rather than
	## the breakdown sitting right after the caption and only the final
	## total drifting off alone further right.
	## A single-term result (no real addition/subtraction — e.g. a plain
	## "+7" with no Talent/situational bonuses) still shows that number
	## only once, not "+7 = +7".
	var sl_row := HBoxContainer.new()
	sl_row.add_theme_constant_override("separation", _scalei(4, compact, size_scale))
	var sl_caption := Label.new()
	sl_caption.text = "SL" if compact else "Success Level"
	sl_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	var sl_numbers := HFlowContainer.new()
	sl_numbers.add_theme_constant_override("h_separation", _scalei(4, compact, size_scale))
	sl_numbers.add_theme_constant_override("v_separation", _scalei(1, compact, size_scale))
	sl_numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl_numbers.alignment = FlowContainer.ALIGNMENT_BEGIN if mirror else FlowContainer.ALIGNMENT_END
	if not test.success or test.sl_breakdown.is_empty():
		sl_numbers.add_child(boxed_label("%+d" % test.success_levels, test.success, true, size_scale))
	else:
		sl_numbers.add_child(boxed_label("%+d" % test.base_success_levels, test.success, false, size_scale))
		for entry: Dictionary in test.sl_breakdown:
			var amount: int = entry["amount"]
			var sign_lbl := Label.new()
			sign_lbl.text = "+" if amount >= 0 else "−"
			sl_numbers.add_child(sign_lbl)
			sl_numbers.add_child(boxed_label(str(abs(amount)), test.success, true, size_scale))
		var eq_lbl := Label.new()
		eq_lbl.text = "="
		sl_numbers.add_child(eq_lbl)
		sl_numbers.add_child(boxed_label("%+d" % test.success_levels, test.success, false, size_scale))
	if mirror:
		sl_row.add_child(sl_numbers)
		sl_row.add_child(sl_caption)
	else:
		sl_row.add_child(sl_caption)
		sl_row.add_child(sl_numbers)
	body.add_child(sl_row)
	if test.success and not test.sl_breakdown.is_empty():
		var names: Array[String] = []
		for entry: Dictionary in test.sl_breakdown:
			names.append("%+d %s" % [entry["amount"], entry["name"]])
		var names_label := Label.new()
		names_label.text = ", ".join(names)
		names_label.add_theme_font_size_override("font_size", _cvali(6, 8, compact, size_scale))
		names_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.4))
		names_label.autowrap_mode = TextServer.AUTOWRAP_WORD
		body.add_child(names_label)

	if data.has("hit_location"):
		var hl_row := HBoxContainer.new()
		var hl_caption := Label.new()
		hl_caption.text = "Hit: " if compact else "Hit Location: "
		hl_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
		hl_row.add_child(hl_caption)
		var hl_value := Label.new()
		hl_value.text = data["hit_location"]
		hl_value.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
		hl_value.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
		hl_row.add_child(hl_value)
		body.add_child(hl_row)

	if data.has("damage"):
		## Same right-hugging group as the SL row above (see its own
		## comment) — the "Damage" caption stays on the left in
		## `dmg_row`, while every number (each breakdown entry, the Size
		## multiplier note, the "=" sign, and the final total) lives
		## together in `dmg_numbers`, a single expand-fill HFlowContainer
		## with `alignment = ALIGNMENT_END` hugging the card's right edge
		## as one unit. A single-term result (one damage source, no Size
		## multiplier — nothing actually added/multiplied) shows its
		## number once rather than duplicating it.
		var dmg_row := HBoxContainer.new()
		dmg_row.add_theme_constant_override("separation", _scalei(4, compact, size_scale))
		var dmg_caption := Label.new()
		dmg_caption.text = "Damage"
		dmg_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
		dmg_row.add_child(dmg_caption)
		var dmg_numbers := HFlowContainer.new()
		dmg_numbers.add_theme_constant_override("h_separation", _scalei(4, compact, size_scale))
		dmg_numbers.add_theme_constant_override("v_separation", _scalei(1, compact, size_scale))
		dmg_numbers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dmg_numbers.alignment = FlowContainer.ALIGNMENT_END
		## Per the request: every damage source shown as its own boxed
		## number, not folded into descriptive text — "5+13=18" style,
		## matching the SL row's own breakdown just above.
		var dmg_breakdown: Array = data.get("damage_breakdown", [])
		var dmg_multiplier: int = data.get("damage_multiplier", 1)
		if dmg_breakdown.size() > 1 or dmg_multiplier > 1:
			for i in range(dmg_breakdown.size()):
				var entry: Dictionary = dmg_breakdown[i]
				if i > 0:
					var plus_lbl := Label.new()
					plus_lbl.text = "+"
					dmg_numbers.add_child(plus_lbl)
				dmg_numbers.add_child(boxed_label(str(entry["amount"]), true, true, size_scale))
			if dmg_multiplier > 1:
				var mult_lbl := Label.new()
				mult_lbl.text = "×%d (Size)" % dmg_multiplier
				dmg_numbers.add_child(mult_lbl)
			var eq_dmg_lbl := Label.new()
			eq_dmg_lbl.text = "="
			dmg_numbers.add_child(eq_dmg_lbl)
			dmg_numbers.add_child(boxed_label(str(data["damage"]), true, compact, size_scale))
		else:
			dmg_numbers.add_child(boxed_label(str(data["damage"]), true, compact, size_scale))
		dmg_row.add_child(dmg_numbers)
		body.add_child(dmg_row)
		## Names for each source, shown below the boxed breakdown —
		## same pattern as the SL row's own names line.
		if not dmg_breakdown.is_empty():
			var dmg_names: Array[String] = []
			for entry: Dictionary in dmg_breakdown:
				dmg_names.append("%d %s" % [entry["amount"], entry["name"]])
			var dmg_names_label := Label.new()
			dmg_names_label.text = ", ".join(dmg_names)
			dmg_names_label.add_theme_font_size_override("font_size", _cvali(6, 8, compact, size_scale))
			dmg_names_label.add_theme_color_override("font_color", Color(0.55, 0.75, 0.4))
			dmg_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			body.add_child(dmg_names_label)

	## Per the request: the actual Wounds a target took (after Toughness
	## Bonus/Armour soak) now lives on the card itself, right under the
	## raw pre-soak Damage row above, instead of only appearing in the
	## plain-text notice line below the card(s). `data["targets_hit"]`
	## is a list so multi-target effects (Blast, Soulfire, Twin-tailed
	## Comet) can show every target hit, not just one — see
	## FieldEncounterScreen for exactly which card each entry lands on
	## (the defender's own card for an opposed roll, the single/
	## attacker's card otherwise).
	var targets_hit: Array = data.get("targets_hit", [])
	if not targets_hit.is_empty():
		for entry: Dictionary in targets_hit:
			var th_label := Label.new()
			var mitigated: int = entry.get("mitigated", 0)
			th_label.text = "%s: %d Wound(s)%s" % [entry["name"], entry["wounds"], (" (%d mitigated)" % mitigated) if mitigated > 0 else ""]
			th_label.add_theme_font_size_override("font_size", _cvali(7, 9, compact, size_scale))
			th_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
			th_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			body.add_child(th_label)

	var effects: Array = data.get("effects", [])
	if not effects.is_empty():
		var eff_header := Label.new()
		eff_header.text = "Effects"
		eff_header.add_theme_font_size_override("font_size", _cvali(6, 8, compact, size_scale))
		eff_header.add_theme_color_override("font_color", Color(0.55, 0.5, 0.42))
		body.add_child(eff_header)
		for e: Variant in effects:
			var eff_label := Label.new()
			eff_label.text = "• " + str(e)
			eff_label.add_theme_font_size_override("font_size", _cvali(7, 9, compact, size_scale))
			eff_label.autowrap_mode = TextServer.AUTOWRAP_WORD
			body.add_child(eff_label)

	## Dims the losing side of an opposed roll — a clear, immediate "who
	## actually won this exchange" cue rather than making the player
	## compare two Success Level numbers themselves. Only set on cards
	## that are genuinely part of an opposition (attacker/defender
	## pairs); a solo Test (Assess, Heal Self) never carries this key.
	if data.get("dimmed", false):
		card.modulate = Color(0.68, 0.68, 0.68, 1)

	return card

## A small highlighted "boxed number" matching the reference sheet's
## yellow-highlighted roll/SL values. `small` shrinks it for the
## individual +N modifier boxes in the Success Level row. `size_scale`
## (see build_roll_card's own class-level comment) scales the `small`
## sizing only, same convention as everywhere else in this file.
static func boxed_label(text: String, positive: bool, small: bool = false, size_scale: float = 1.0) -> PanelContainer:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.75, 0.62, 0.2) if positive else Color(0.5, 0.3, 0.25)
	style.corner_radius_top_left = _scalei(2, small, size_scale)
	style.corner_radius_top_right = _scalei(2, small, size_scale)
	style.corner_radius_bottom_left = _scalei(2, small, size_scale)
	style.corner_radius_bottom_right = _scalei(2, small, size_scale)
	style.content_margin_left = _cvali(5, 7, small, size_scale)
	style.content_margin_right = _cvali(5, 7, small, size_scale)
	style.content_margin_top = _scalei(2, small, size_scale)
	style.content_margin_bottom = _scalei(2, small, size_scale)
	box.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.1, 0.08, 0.05))
	label.add_theme_font_size_override("font_size", _cvali(9, 12, small, size_scale))
	## Per the request ("make all numbers bold"): every number this
	## file displays is highlighted through this one boxed_label()
	## helper, so applying the shared bold font variation here alone
	## covers every numeric value in every card.
	label.add_theme_font_override("font", _get_bold_font())
	## Per the request: the project's theme applies a font shadow to
	## every Label by default, which reads fine against the game's own
	## dark backgrounds but genuinely hurt legibility here — dark text
	## on a bright yellow box, plus a dark shadow, gave these numbers an
	## engraved, hard-to-read look. Overridden to fully transparent so
	## this one widget opts out without touching the shadow anywhere else.
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))
	box.add_child(label)
	return box

## Shared red header for the Fumble/Critical Wound cards below — same
## panel/label structure as build_roll_card()'s own header, factored out
## since both new card types use an identical look (per the request,
## styled after a reference sheet showing a red-headered "Fumble" card
## and a red-headered "Critical Roll" card, each with the character's
## name above the card's title).
static func _event_header(character_name: String, title: String, compact: bool, size_scale: float = 1.0) -> PanelContainer:
	var header_panel := PanelContainer.new()
	var header_style := StyleBoxFlat.new()
	header_style.bg_color = Color(0.55, 0.14, 0.12)
	header_style.corner_radius_top_left = _scalei(4, compact, size_scale)
	header_style.corner_radius_top_right = _scalei(4, compact, size_scale)
	header_style.content_margin_left = _scalei(8, compact, size_scale)
	header_style.content_margin_right = _scalei(8, compact, size_scale)
	header_style.content_margin_top = _cvali(4, 5, compact, size_scale)
	header_style.content_margin_bottom = _cvali(4, 5, compact, size_scale)
	header_panel.add_theme_stylebox_override("panel", header_style)
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = character_name
	name_label.add_theme_color_override("font_color", Color(1, 1, 1))
	name_label.add_theme_font_size_override("font_size", _cvali(9, 11, compact, size_scale))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(name_label)
	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	title_lbl.add_theme_font_size_override("font_size", _cvali(11, 14, compact, size_scale))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(title_lbl)
	header_panel.add_child(header_box)
	return header_panel

## The card's own shell (border, background, minimum width) — identical
## to build_roll_card()'s, factored out for the same reason as
## _event_header() above.
##
## Per a real, confirmed bug ("move the banner of the roll card box to
## the top"): this used to add `body_margin` to `outer` itself before
## returning, so build_fumble_card()/build_critical_wound_card()'s own
## later `outer.add_child(_event_header(...))` call appended the header
## AFTER the body — landing the red Fumble/Critical Wound banner at the
## BOTTOM of the card instead of the top, confirmed directly from a
## screenshot of the shipped card. Fixed by leaving `body_margin`
## un-added here — the caller now adds the header first, then
## `body_margin` second, so `outer`'s child order (and therefore the
## rendered top-to-bottom order) is correct: banner on top, body below.
static func _event_shell(compact: bool, size_scale: float = 1.0) -> Dictionary:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(_cvalf(185, 252, compact, size_scale), 0)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.14, 0.11, 0.08, 1)
	card_style.border_width_left = _cvali(1, 2, compact, size_scale)
	card_style.border_width_top = _cvali(1, 2, compact, size_scale)
	card_style.border_width_right = _cvali(1, 2, compact, size_scale)
	card_style.border_width_bottom = _cvali(1, 2, compact, size_scale)
	card_style.border_color = Color(0.72, 0.58, 0.27, 1)
	card_style.corner_radius_top_left = _scalei(5, compact, size_scale)
	card_style.corner_radius_top_right = _scalei(5, compact, size_scale)
	card_style.corner_radius_bottom_left = _scalei(5, compact, size_scale)
	card_style.corner_radius_bottom_right = _scalei(5, compact, size_scale)
	card.add_theme_stylebox_override("panel", card_style)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	card.add_child(outer)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", _cvali(2, 4, compact, size_scale))
	var body_margin := MarginContainer.new()
	body_margin.add_theme_constant_override("margin_left", _cvali(7, 8, compact, size_scale))
	body_margin.add_theme_constant_override("margin_right", _cvali(7, 8, compact, size_scale))
	body_margin.add_theme_constant_override("margin_top", _cvali(4, 7, compact, size_scale))
	body_margin.add_theme_constant_override("margin_bottom", _cvali(4, 7, compact, size_scale))
	body_margin.add_child(body)
	return {"card": card, "outer": outer, "body": body, "body_margin": body_margin}

## A dedicated Fumble (Oops! Table) card, replacing the old plain-text
## "Fumble: <text>" notice line — styled after the reference sheet's
## red-headered "Fumble" card (boxed "Fumble Roll: 100" number, then the
## table result's own text below). `data`: character_name, roll, text.
static func build_fumble_card(data: Dictionary, compact: bool = false, size_scale: float = 1.0) -> PanelContainer:
	var shell := _event_shell(compact, size_scale)
	var card: PanelContainer = shell["card"]
	var outer: VBoxContainer = shell["outer"]
	var body: VBoxContainer = shell["body"]
	## Per the fix above: header added first, `body_margin` second, so
	## the banner renders at the top of the card, not the bottom.
	outer.add_child(_event_header(data.get("character_name", ""), "Fumble", compact, size_scale))
	outer.add_child(shell["body_margin"])

	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", _scalei(5, compact, size_scale))
	var roll_caption := Label.new()
	roll_caption.text = "Fumble Roll"
	roll_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	roll_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_row.add_child(roll_caption)
	roll_row.add_child(boxed_label(str(data.get("roll", 0)), false, compact, size_scale))
	body.add_child(roll_row)

	var text_label := Label.new()
	text_label.text = data.get("text", "")
	text_label.add_theme_font_size_override("font_size", _cvali(7, 9, compact, size_scale))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(text_label)

	return card

## A dedicated Critical Wound card, replacing the old plain-text
## "Critical Wound (roll N): <name> (<location>) — <flavor>" notice
## line — styled after the reference sheet's red-headered "Critical
## Roll" card. `data`: character_name, roll, overkill_bonus, location,
## name, flavor, wounds.
static func build_critical_wound_card(data: Dictionary, compact: bool = false, size_scale: float = 1.0) -> PanelContainer:
	var shell := _event_shell(compact, size_scale)
	var card: PanelContainer = shell["card"]
	var outer: VBoxContainer = shell["outer"]
	var body: VBoxContainer = shell["body"]
	## Per the fix above: header added first, `body_margin` second, so
	## the banner renders at the top of the card, not the bottom.
	outer.add_child(_event_header(data.get("character_name", ""), "Critical Wound", compact, size_scale))
	outer.add_child(shell["body_margin"])

	var loc_row := HBoxContainer.new()
	loc_row.add_theme_constant_override("separation", _scalei(5, compact, size_scale))
	var loc_caption := Label.new()
	loc_caption.text = "Location"
	loc_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	loc_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loc_row.add_child(loc_caption)
	var loc_value := Label.new()
	loc_value.text = data.get("location", "")
	loc_value.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	loc_value.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	loc_row.add_child(loc_value)
	body.add_child(loc_row)

	var roll_row := HBoxContainer.new()
	roll_row.add_theme_constant_override("separation", _scalei(5, compact, size_scale))
	var roll_caption := Label.new()
	roll_caption.text = "Critical Roll"
	roll_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
	roll_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	roll_row.add_child(roll_caption)
	roll_row.add_child(boxed_label(str(data.get("roll", 0)), true, compact, size_scale))
	body.add_child(roll_row)
	var overkill_bonus: int = data.get("overkill_bonus", 0)
	if overkill_bonus > 0:
		var overkill_label := Label.new()
		overkill_label.text = "(includes +%d overkill bonus)" % overkill_bonus
		overkill_label.add_theme_font_size_override("font_size", _cvali(6, 8, compact, size_scale))
		overkill_label.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
		body.add_child(overkill_label)

	var name_label := Label.new()
	name_label.text = data.get("name", "")
	name_label.add_theme_font_size_override("font_size", _cvali(8, 11, compact, size_scale))
	name_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(name_label)

	var flavor_label := Label.new()
	flavor_label.text = data.get("flavor", "")
	flavor_label.add_theme_font_size_override("font_size", _cvali(7, 9, compact, size_scale))
	flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.add_child(flavor_label)

	## Per the follow-up request: this is the Critical Wound TABLE's own
	## separate "Wounds" column (see field_encounter_screen.gd's own
	## comment where this card is built) — not the normal hit's damage,
	## which the Defence card just above this one already showed on its
	## own terms. "hide_wounds" (set by the caller) skips this row
	## entirely: when the target was already at 0 Wounds before this hit,
	## or the result is a Death-tier entry, the table's Wounds number is
	## meaningless — only whether they end up unconscious or dead matters.
	if not data.get("hide_wounds", false):
		var wounds_row := HBoxContainer.new()
		wounds_row.add_theme_constant_override("separation", _scalei(5, compact, size_scale))
		var wounds_caption := Label.new()
		wounds_caption.text = "Wounds"
		wounds_caption.add_theme_font_size_override("font_size", _cvali(8, 12, compact, size_scale))
		wounds_caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wounds_row.add_child(wounds_caption)
		wounds_row.add_child(boxed_label(str(data.get("wounds", 0)), true, compact, size_scale))
		body.add_child(wounds_row)

	return card

## --- Status / hotkeys / misc ------------------------------------------
