extends RefCounted
class_name SocialCombatManeuversTest
## Verifies the three Rapport-spending Tactical Maneuvers (Design Doc
## "Social Combat — Design Doc v1", Slice 2, Section 7) and the
## Flustered condition's own effect (Section 5, pulled forward just far
## enough for Bring in the Muscle to have a real payoff), driven
## directly against a real SocialEncounter.tscn instance's own
## functions rather than through button clicks — this test cares about
## the maneuvers' state changes (Rapport spent, the right flags set),
## not about re-proving the UI can be clicked (social_combat_screen_
## test.gd's own random playthrough already exercises that, and Bring
## in the Muscle's own Rapport cost (3) is above a fresh Brass-tier
## party's cap (2) anyway, so a driven playthrough could never reach it
## organically).

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	var game_state = tree.get_root().get_node("/root/GameState")
	game_state.reset_world_state()
	game_state.player_character = null
	game_state.ensure_player_character()
	var pc: Character = game_state.player_character
	## A second party member so Bring in the Muscle's own "any present
	## party member" ally-picker has a real choice, and a real Strength
	## score so its roll isn't zero.
	var ally := Character.new()
	ally.character_name = "Big Karl"
	ally.characteristics = pc.characteristics.duplicate()
	ally.characteristics.strength = 70
	ally.wounds_max = pc.wounds_max
	ally.wounds_current = pc.wounds_max
	game_state.party.append(ally)

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
		print("RESULT (Social Combat Maneuvers): ", "ALL PASS" if all_pass_early else "SOME FAILED")
		return all_pass_early

	## Force a controlled Rapport level -- bypasses the normal Charm-hit
	## accrual path (already covered incidentally by social_combat_
	## screen_test.gd's own random playthrough) so every Maneuver is
	## affordable regardless of what a fresh Brass-tier party's real cap
	## (2) would otherwise allow.
	screen.social_combat.rapport_max = 5
	screen.social_combat.rapport_pool.current = 5

	## --- Distract (1 Rapport) -------------------------------------------
	var before: int = screen.social_combat.rapport_pool.current
	screen._use_distract(pc)
	for i in range(3):
		await tree.process_frame
	checks.append(["Distract spends exactly 1 Rapport", screen.social_combat.rapport_pool.current == before - 1])
	checks.append(["Distract flags the NPC for a redirected next attack", screen.distracted_npcs.get(npc_a, false) == true])

	## --- Overwhelm (2 Rapport) ------------------------------------------
	before = screen.social_combat.rapport_pool.current
	screen._use_overwhelm(pc)
	for i in range(3):
		await tree.process_frame
	checks.append(["Overwhelm spends exactly 2 Rapport", screen.social_combat.rapport_pool.current == before - 2])
	checks.append(["Overwhelm records the current round against the NPC", screen.overwhelmed_until_round.get(npc_a, -1) == screen.social_combat.round_number])

	## --- Bring in the Muscle (3 Rapport) --------------------------------
	## Rapport is down to 2 after the two spends above -- top back up so
	## this maneuver's own 3-cost is affordable to actually exercise it.
	screen.social_combat.rapport_pool.current = 3
	before = screen.social_combat.rapport_pool.current
	screen._attempt_bring_the_muscle(pc, ally, npc_a)
	var iterations := 0
	while iterations < 60:
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
		if chosen != null:
			chosen.emit_signal("pressed")
		## Stop as soon as Rapport has actually been spent -- no need to
		## keep driving the rest of the encounter's own turns forward.
		if screen.social_combat.rapport_pool.current < before:
			break
	checks.append(["Bring in the Muscle spends exactly 3 Rapport", screen.social_combat.rapport_pool.current == before - 3])

	## --- Flustered's own effect (Design Doc Section 5) -------------------
	## Deterministic, dice-free: exercised directly against the real
	## per-turn hook rather than relying on Bring in the Muscle actually
	## landing a hit (real dice, not guaranteed every run).
	## Per a real, confirmed flake (documented across several earlier
	## sessions, and made MUCH more frequent — 5 of 6 runs, not the
	## historical "1 of 4" — by halving Composure values, see build_info's
	## own v0.3.9 changelog): the real dice-driven Distract/Overwhelm/
	## Bring in the Muscle exchanges just above can leave npc_a already at
	## or below 1 Composure by this point, so maxi(0, x-2) clamps to
	## something other than exactly composure_before-2 through no fault of
	## the Flustered code itself. This check is meant to be dice-free and
	## deterministic (per the comment above, always has been) — it just
	## forgot to also guarantee real Composure headroom before asserting
	## an exact, un-clamped -2. Restored to full here fixes that, without
	## changing what's actually being tested (Flustered's own -2 effect
	## and self-clearing behaviour).
	npc_a.composure_current = npc_a.composure_max
	npc_a.add_condition("Flustered")
	var composure_before := npc_a.composure_current
	var applied: bool = screen._apply_flustered_start_of_turn(npc_a)
	checks.append(["Flustered applies exactly -2 Composure at the start of a turn", applied and npc_a.composure_current == composure_before - 2])
	checks.append(["Flustered clears itself after applying", not npc_a.has_condition("Flustered")])
	checks.append(["A character without Flustered is left alone (no-op, no fake -2)", not screen._apply_flustered_start_of_turn(npc_a)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Social Combat Maneuvers): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass

static func _find_buttons(node: Node) -> Array:
	var result: Array = []
	for child in node.get_children():
		if child is Button:
			result.append(child)
		result.append_array(_find_buttons(child))
	return result
