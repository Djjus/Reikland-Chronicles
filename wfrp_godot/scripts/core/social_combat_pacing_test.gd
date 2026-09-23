extends RefCounted
class_name SocialCombatPacingTest
## Verifies the three pacing/variety changes added per an explicit
## request: "we need to limit the attempts somehow, and stop the same
## character repeating the same action (one he's best at) each round"
## (a hard round cap, and a once-per-NPC-per-character Attack Type
## restriction — both on SocialCombatEncounter), plus the follow-up "it
## would be nice the conversation would evolve with each roll rather
## than only take place at the start and after all rolls are done"
## (SocialEncounterScreen._maybe_show_npc_reaction(), driven by the new
## SocialEncounterDefinition.npc_reaction_lines field).
##
## Cases 1-3 exercise SocialCombatEncounter's own new methods directly,
## no screen needed. Cases 4-7 drive a real SocialEncounter.tscn
## instance, same convention social_combat_conditions_test.gd/social_
## combat_maneuvers_test.gd already established.

static func _find_buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result

## Deliberately the LAST match, not the first: _clear() frees old panel
## children via queue_free(), which doesn't actually remove them from
## the tree until the next idle frame — a rebuild that happens without
## an intervening awaited frame (as Case 4 below does, right after the
## screen's own initial auto-render) leaves the OLD, soon-to-be-freed
## button(s) still present as earlier siblings ahead of the genuinely
## current rebuild's own buttons. Same reasoning, same fix, as
## offhand_attack_test.gd's own _find_button().
static func _find_button_starting_with(node: Node, prefix: String) -> Button:
	var last: Button = null
	for btn in _find_buttons(node):
		if String(btn.text).begins_with(prefix):
			last = btn
	return last

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	## --- Case 1: round_limit_reached() (MAX_ROUNDS = 6) -----------------
	var bare_encounter := SocialCombatEncounter.new()
	var bare_pc := Character.new()
	bare_pc.allegiance = "ally"
	bare_pc.characteristics = CharacteristicSet.new()
	var bare_npc := Character.new()
	bare_npc.allegiance = "adversary"
	bare_npc.characteristics = CharacteristicSet.new()
	bare_encounter.add_combatant(bare_pc)
	bare_encounter.add_combatant(bare_npc)
	bare_encounter.roll_initiative()
	var all_within_cap_ok := true
	for r in range(1, SocialCombatEncounter.MAX_ROUNDS + 1):
		bare_encounter.round_number = r
		if bare_encounter.round_limit_reached():
			all_within_cap_ok = false
	checks.append(["round_limit_reached() is false for every round 1..MAX_ROUNDS", all_within_cap_ok])
	bare_encounter.round_number = SocialCombatEncounter.MAX_ROUNDS + 1
	checks.append(["round_limit_reached() is true the round after MAX_ROUNDS", bare_encounter.round_limit_reached()])

	## --- Case 2: used_attack_types is scoped per (character, npc) ------
	var scope_encounter := SocialCombatEncounter.new()
	var scope_pc := Character.new()
	var scope_npc_a := Character.new()
	var scope_npc_b := Character.new()
	checks.append(["Unmarked Attack Type starts unused", not scope_encounter.has_used_attack_type(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.INTIMIDATE)])
	scope_encounter.mark_attack_type_used(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.INTIMIDATE)
	checks.append(["Marking Intimidate used against npc_a is reflected back", scope_encounter.has_used_attack_type(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.INTIMIDATE)])
	checks.append(["...but a DIFFERENT Attack Type against the same npc is still fresh", not scope_encounter.has_used_attack_type(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.CHARM)])
	checks.append(["...and the SAME Attack Type against a DIFFERENT npc is still fresh", not scope_encounter.has_used_attack_type(scope_pc, scope_npc_b, SocialCombatResolver.AttackType.INTIMIDATE)])
	scope_encounter.mark_attack_type_used(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.INTIMIDATE)   ## idempotent re-mark
	checks.append(["Re-marking the same (character, npc, type) doesn't duplicate or error", scope_encounter.has_used_attack_type(scope_pc, scope_npc_a, SocialCombatResolver.AttackType.INTIMIDATE)])

	## --- Case 2b: the actual fix — a used Attack Type comes back on
	## cooldown after ATTACK_TYPE_REFRESH_ROUNDS rounds, per the real
	## balance bug report ("momentum snowballs and... they can only pass
	## until the NPC slowly beats them all") this corrects. Marked at
	## round_number 1 (roll_initiative() below sets it there); the
	## refresh window is 2, so it should still be blocked at round 2 and
	## free again by round 3.
	var refresh_encounter := SocialCombatEncounter.new()
	var refresh_pc := Character.new()
	refresh_pc.allegiance = "ally"
	refresh_pc.characteristics = CharacteristicSet.new()
	var refresh_npc := Character.new()
	refresh_npc.allegiance = "adversary"
	refresh_npc.characteristics = CharacteristicSet.new()
	refresh_encounter.add_combatant(refresh_pc)
	refresh_encounter.add_combatant(refresh_npc)
	refresh_encounter.roll_initiative()   ## sets round_number = 1
	refresh_encounter.mark_attack_type_used(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE)
	checks.append(["Refresh: freshly used, 2 rounds still remain on cooldown", refresh_encounter.rounds_until_attack_type_available(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE) == 2])
	refresh_encounter.round_number = 2
	checks.append(["Refresh: still blocked the round right after use", refresh_encounter.has_used_attack_type(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE)])
	checks.append(["Refresh: exactly 1 round remains on cooldown at round 2", refresh_encounter.rounds_until_attack_type_available(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE) == 1])
	refresh_encounter.round_number = 3
	checks.append(["Refresh: available again 2 rounds after use", not refresh_encounter.has_used_attack_type(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE)])
	checks.append(["Refresh: rounds_until_attack_type_available() reports 0 once it's free", refresh_encounter.rounds_until_attack_type_available(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE) == 0])
	## Re-using it re-starts the cooldown from the new round, not the old one.
	refresh_encounter.mark_attack_type_used(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE)
	checks.append(["Refresh: re-using it resets the cooldown to count from THIS use", refresh_encounter.rounds_until_attack_type_available(refresh_pc, refresh_npc, SocialCombatResolver.AttackType.INTIMIDATE) == 2])

	## --- Case 3: has_any_attack_type_available() -----------------------
	var avail_encounter := SocialCombatEncounter.new()
	var avail_pc := Character.new()
	avail_pc.skill_advances["Research"] = 1   ## Research is Advanced — needs real training for can_use() to allow Reason
	var avail_npc_a := Character.new()
	var avail_npc_b := Character.new()
	checks.append(["A fresh character has at least one Attack Type available against a fresh NPC", avail_encounter.has_any_attack_type_available(avail_pc, avail_npc_a)])
	for attack_type in [SocialCombatResolver.AttackType.INTIMIDATE, SocialCombatResolver.AttackType.CHARM,
			SocialCombatResolver.AttackType.NEEDLE, SocialCombatResolver.AttackType.REASON]:
		avail_encounter.mark_attack_type_used(avail_pc, avail_npc_a, attack_type)
	checks.append(["Once all 4 trained Attack Types are spent against npc_a, none remain available there", not avail_encounter.has_any_attack_type_available(avail_pc, avail_npc_a)])
	checks.append(["...but npc_b (never attacked) still has a fresh set available", avail_encounter.has_any_attack_type_available(avail_pc, avail_npc_b)])

	## --- Screen-driven cases (4-7) --------------------------------------
	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var pc: Character = game_state.player_character
	pc.skill_advances["Research"] = 1
	pc.fortune_points = 0

	var scene_res: PackedScene = load("res://scenes/SocialEncounter.tscn")
	var screen: Control = scene_res.instantiate()
	tree.get_root().add_child(screen)
	for i in range(10):
		await tree.process_frame

	checks.append(["Screen started a real Social Combat", screen.social_combat != null])
	var npc_a: Character = screen.npc_characters[0] if not screen.npc_characters.is_empty() else null
	checks.append(["A real NPC exists to target", npc_a != null])

	if screen.social_combat == null or npc_a == null:
		var all_pass_early := true
		for chk in checks:
			print(("PASS  " if chk[1] else "FAIL  ") + chk[0])
			if not chk[1]:
				all_pass_early = false
		print("RESULT (Social Combat Pacing): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	screen.selected_npc_target = npc_a

	## --- Case 4: the button for an already-used Attack Type against the
	## CURRENT target is disabled and reads "already tried"; a fresh one
	## is still a live, enabled button. -----------------------------------
	screen.social_combat.mark_attack_type_used(pc, npc_a, SocialCombatResolver.AttackType.INTIMIDATE)
	screen._show_attack_buttons(pc)
	var intimidate_btn := _find_button_starting_with(screen.action_container, "Intimidate")
	checks.append(["An already-used Attack Type's button exists", intimidate_btn != null])
	if intimidate_btn != null:
		checks.append(["...and is disabled", intimidate_btn.disabled])
		checks.append(["...and its text says it's on cooldown, not gone forever", String(intimidate_btn.text).contains("cooldown")])
	var charm_btn := _find_button_starting_with(screen.action_container, "Charm")
	checks.append(["A never-used Attack Type's button exists", charm_btn != null])
	if charm_btn != null:
		checks.append(["...and is still enabled", not charm_btn.disabled])

	## --- Case 4b: the actual screen-level fix — once
	## ATTACK_TYPE_REFRESH_ROUNDS rounds have passed, that same Intimidate
	## button is a live, enabled button again rather than staying disabled
	## for the rest of the encounter.
	screen.social_combat.round_number += SocialCombatEncounter.ATTACK_TYPE_REFRESH_ROUNDS
	screen._show_attack_buttons(pc)
	var intimidate_btn_refreshed := _find_button_starting_with(screen.action_container, "Intimidate")
	checks.append(["An Attack Type comes back off cooldown after ATTACK_TYPE_REFRESH_ROUNDS rounds", intimidate_btn_refreshed != null and not intimidate_btn_refreshed.disabled])

	## --- Case 5: hitting the round cap ends the encounter as a
	## non-reward stalemate, same shape as any other loss. ----------------
	screen.chosen_situation = {}   ## deterministic: never the is_combat hand-off branch
	screen.encounter_over = false
	screen.social_combat.round_number = SocialCombatEncounter.MAX_ROUNDS + 1
	screen._advance_social_combat_turn()
	await tree.process_frame
	checks.append(["Hitting the round cap sets encounter_over", screen.encounter_over])
	checks.append(["...and shows the Return button (same _finish() path every other ending uses)", screen.return_button.visible])
	var saw_stalemate_notice := false
	for entry in screen.history:
		if String(entry.get("notice", "")).contains("drags on"):
			saw_stalemate_notice = true
	checks.append(["...with its own distinct 'drags on' notice explaining why", saw_stalemate_notice])

	## --- Case 6: NPC reaction lines fire progressively as Composure
	## actually drops, and never once it's hit 0. -------------------------
	checks.append(["Every encounter now ships at least one npc_reaction_lines entry", not screen.encounter_def.npc_reaction_lines.is_empty()])
	var reaction_prefix := "[i][color=#c9a35c]"
	screen._npc_reactions_shown.erase(npc_a)
	npc_a.composure_max = 90
	npc_a.composure_current = 90
	screen._maybe_show_npc_reaction(npc_a)
	checks.append(["No reaction yet at full Composure", screen._npc_reactions_shown.get(npc_a, 0) == 0])
	npc_a.composure_current = 50   ## 50/90 ~= 55%, at/below the first (66%) threshold
	screen._maybe_show_npc_reaction(npc_a)
	checks.append(["First reaction line fires once Composure crosses ~66%", screen._npc_reactions_shown.get(npc_a, 0) == 1])
	checks.append(["...and it was actually logged to history", String(screen.history[0].get("notice", "")).begins_with(reaction_prefix)])
	npc_a.composure_current = 20   ## 20/90 ~= 22%, at/below the second (33%) threshold
	screen._maybe_show_npc_reaction(npc_a)
	checks.append(["Second reaction line fires once Composure crosses ~33%", screen._npc_reactions_shown.get(npc_a, 0) == screen.encounter_def.npc_reaction_lines.size()])
	var shown_before_zero: int = screen._npc_reactions_shown.get(npc_a, 0)
	npc_a.composure_current = 0
	screen._maybe_show_npc_reaction(npc_a)
	checks.append(["Composure hitting 0 shows no further reaction (that's success_reveal's own moment)", screen._npc_reactions_shown.get(npc_a, 0) == shown_before_zero])

	## Catch-up: a single big hit that skips straight past both
	## thresholds in one blow still shows both lines, in order, not just
	## the nearer one.
	screen._npc_reactions_shown.erase(npc_a)
	npc_a.composure_current = 90
	var history_size_before: int = screen.history.size()
	npc_a.composure_current = 5   ## below BOTH thresholds at once
	screen._maybe_show_npc_reaction(npc_a)
	checks.append(["A single big drop past both thresholds catches up and shows both lines", screen._npc_reactions_shown.get(npc_a, 0) == screen.encounter_def.npc_reaction_lines.size()])
	checks.append(["...logging one new history entry per line shown", screen.history.size() - history_size_before == screen.encounter_def.npc_reaction_lines.size()])

	## --- Case 7: once every Attack Type is spent against the only
	## target AND Rapport can't afford any Maneuver, a Pass fallback
	## appears so the character is never left with nothing pressable. ----
	for attack_type in [SocialCombatResolver.AttackType.INTIMIDATE, SocialCombatResolver.AttackType.CHARM,
			SocialCombatResolver.AttackType.NEEDLE, SocialCombatResolver.AttackType.REASON]:
		screen.social_combat.mark_attack_type_used(pc, npc_a, attack_type)
	screen.social_combat.rapport_pool.current = 0
	screen._show_attack_buttons(pc)
	var pass_btn := _find_button_starting_with(screen.action_container, "Pass")
	checks.append(["A Pass fallback appears once every Attack Type is spent and no Maneuver is affordable", pass_btn != null])

	screen.queue_free()

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Pacing): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
