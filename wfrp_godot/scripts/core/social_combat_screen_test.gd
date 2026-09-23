extends RefCounted
class_name SocialCombatScreenTest
## Screen-level regression test for the full Social Combat loop (Design
## Doc "Social Combat — Design Doc v1", Slice 1) — drives a real
## SocialEncounter.tscn instance end-to-end via synthetic button
## presses (same technique the one-off scripts/tools/ smoke test used
## while building this feature, kept here permanently as a real
## assertion-based test) to catch the kind of bug unit tests on
## SocialCombatEncounter/SocialCombatResolver alone can't: a hang in the
## turn loop, a UI rebuild that never shows a usable button, Composure
## bars that never update, or a win/loss that never reaches _finish()/
## the combat handoff.

static func _find_buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()

	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen: Control = scene_res.instantiate()
	tree.get_root().add_child(screen)

	for i in range(10):
		await tree.process_frame

	checks.append(["Screen starts a real Social Combat (social_combat != null)", screen.social_combat != null])
	checks.append(["At least one NPC is seated", not screen.npc_characters.is_empty()])
	checks.append(["At least one living party member is seated", screen.social_combat != null and not screen.social_combat.get_living("ally").is_empty()])
	## Composure was actually computed (Willpower + Cool), not left at
	## Character's own bare default of 1/1 (see character.gd's own
	## comment on composure_current/composure_max).
	var pc: Character = game_state.player_character
	checks.append(["Party Composure was computed above the bare Character default of 1", pc.composure_max > 1])

	if screen.social_combat == null or screen.npc_characters.is_empty():
		## Nothing further to meaningfully check — report what we have and bail.
		var all_pass_early := true
		for chk in checks:
			var label: String = chk[0]
			var passed: bool = chk[1]
			print(("PASS  " if passed else "FAIL  ") + label)
			if not passed:
				all_pass_early = false
		print("RESULT (Social Combat Screen): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	## Drive the encounter to completion — prefer "Continue" whenever
	## it's on offer (this also means the Fortune-spend prompt never
	## gets stuck spending Fortune Points forever), otherwise the first
	## enabled non-toggle button (an Attack Type, or a skill button),
	## same technique as the one-off tools/ smoke script this was
	## promoted from.
	##
	## CORRECTED per a real, confirmed bug this test itself caught (once
	## Composure was halved, per the "too much health" request, losses —
	## and the Corruption-resist path in particular — got common enough
	## to actually surface it): the loop used to stop as soon as
	## screen.encounter_over went true, but _resolve_failure() sets that
	## flag BEFORE awaiting _apply_social_combat_loss_consequences() (see
	## that function's own comment — it has to be awaited so a combat
	## hand-off can't cut a still-open Fortune prompt off mid-way). That
	## means a genuinely pending Corruption-resist Fortune/Dark-Deal
	## prompt could still be on screen, waiting for a click, the exact
	## moment this loop decided the encounter was "done" and stopped
	## driving buttons — leaving _finish() (and Return button.visible)
	## never reached for the rest of the run. The real stopping condition
	## is one of the two things that ACTUALLY end this screen's own
	## involvement: the Return button lighting up (_finish() ran), or the
	## screen itself going away entirely (a combat hand-off changed the
	## scene) — not encounter_over, which can go true well before either
	## of those actually happens.
	var iterations := 0
	var reached_terminal_state := false
	while iterations < 500:
		if not is_instance_valid(screen) or not is_instance_valid(screen.return_button):
			reached_terminal_state = true   ## the scene changed away (combat hand-off) — screen/its children are gone
			break
		if screen.return_button.visible:
			reached_terminal_state = true   ## a real _finish() ran
			break
		if not game_state.pending_encounter_monster_names.is_empty():
			reached_terminal_state = true   ## combat hand-off requested, scene change imminent
			break
		await tree.process_frame
		iterations += 1
		var buttons := _find_buttons(screen.action_container)
		var enabled: Array = []
		for b in buttons:
			if is_instance_valid(b) and not b.disabled:
				enabled.append(b)
		if enabled.is_empty():
			continue
		var chosen: Button = null
		for b in enabled:
			if b.text == "Continue":
				chosen = b
				break
		if chosen == null:
			for b in enabled:
				if not b.toggle_mode:
					chosen = b
					break
		if chosen == null:
			chosen = enabled[0]
		chosen.emit_signal("pressed")

	checks.append(["The encounter resolved within 500 driven turns (no hang)", reached_terminal_state])

	## A win OR a loss can legitimately hand off into real physical
	## combat (chosen_situation.is_combat) instead of ever calling
	## _finish() on this screen at all — that handoff actually firing is
	## just as valid a resolution as the Return button lighting up.
	var combat_handoff: bool = not game_state.pending_encounter_monster_names.is_empty()
	if not combat_handoff:
		checks.append(["Return button is enabled once the encounter resolves (no combat handoff)",
			is_instance_valid(screen.return_button) and not screen.return_button.disabled])

	## Whichever side lost should show it — either every NPC's Composure
	## hit 0, or every present party member's did (Design Doc Section 8)
	## — unless the encounter escaped into a physical fight instead, or
	## (per the round-cap request) neither side broke the other before
	## SocialCombatEncounter.MAX_ROUNDS ran out and it ended as a
	## stalemate instead — a real, now-legitimate third way for a
	## non-combat-handoff resolution to end with both sides still above
	## 0 Composure.
	if not combat_handoff and screen.social_combat != null:
		var npcs_out: bool = screen.social_combat.all_npcs_defeated()
		var party_out: bool = screen.social_combat.all_party_defeated()
		var stalemated: bool = screen.social_combat.round_limit_reached()
		checks.append(["A non-combat-handoff resolution ended with one whole side's Composure at 0, or hit the round cap", npcs_out or party_out or stalemated])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Screen): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
