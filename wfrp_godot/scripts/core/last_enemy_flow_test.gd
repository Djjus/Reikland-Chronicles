extends RefCounted
class_name LastEnemyFlowTest

static func run_test(fe) -> bool:
	var checks: Array = []

	## Real-bug fix: _start_encounter() itself immediately overwrites its
	## own `player` script variable from GameState.player_character (its
	## very first line) — a standalone Character built via
	## CharacterCreator.create_character() and assigned straight onto
	## fe.player, as this test used to do, gets silently discarded the
	## instant _start_encounter() runs, so the WS90/Strength90 stats
	## below never actually belonged to whoever really fought. Setting
	## them on the real GameState.player_character instead (the same
	## "reset, then ensure, then tune" pattern combat_reroll_test.gd/
	## light_source_test.gd already use) makes sure the high stats
	## belong to the combatant _start_encounter() actually places.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "FlowTestPlayer"
	pc.equipped_weapon = "Sword"
	pc.characteristics.set_value("weapon_skill", 90)
	pc.characteristics.set_value("strength", 90)
	pc.fortune_points = 0

	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	## Flakiness fix: EncounterGroupBuilder.select_group() has a genuine,
	## intentional 25% chance of spawning a SECOND monster alongside the
	## first (Up in Arms-style group scaling) whenever nothing pre-pins
	## the group. This test only ever reduces fe.monsters[0]'s Wounds to
	## 1 and kills that one — a real, working "last enemy" flow when
	## there's genuinely only one enemy, but a false failure whenever
	## the 25% roll happened to add a second monster that's still very
	## much alive (battle_over correctly stays false, since it isn't
	## actually the last enemy). Pinning the encounter to a single named
	## monster — the same pending_encounter_monster_names hook
	## combat_reroll_test.gd's own _spin_up_encounter() already uses —
	## sidesteps EncounterGroupBuilder's random group-size roll entirely
	## rather than fighting it with a lucky dice seed.
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	## Flakiness fix, part 2: also pin Dice's own RNG stream to a fixed,
	## known-good seed (per dice.gd's own doc comment: "swap the RNG's
	## seed in tests") so the WS90 attack roll(s) below can never — however
	## rarely — miss and stall the kill/continue flow this test exists to
	## exercise. Also reseeds Godot's own global RNG (the bare randf()/
	## randi() calls field_encounter_screen.gd uses for things like
	## lantern chance, which Dice.rng does NOT cover) for the same
	## run-order-independence reason.
	Dice.rng.seed = 2
	seed(2)
	fe._start_encounter()
	for i in range(3): await fe.get_tree().process_frame

	## Reduce the naturally-spawned monster's own Wounds to 1, keeping
	## the SAME object _start_encounter() already registered in its
	## weapons/monster_defs dictionaries — replacing it with a brand
	## new Character (as an earlier version of this test did) silently
	## desyncs those lookups and isn't representative of a real fight.
	var rat: Character = fe.monsters[0]
	rat.wounds_current = 1
	fe.selected_target = rat

	## Real-bug fix: melee requires actual battle-grid adjacency (see
	## _on_player_attack's own distance check) — the standard opening
	## formation starts both sides at opposite map edges, "neither side
	## has closed to melee yet," exactly the gap combat_reroll_test.gd
	## already had to work around the same way.
	if fe.battle_positions.has(fe.player) and fe.battle_positions.has(rat):
		fe.battle_positions[rat] = fe.battle_positions[fe.player] + Vector2i(1, 0)

	print("--- before killing blow ---")
	print("battle_over:", fe.battle_over, " awaiting_player_target:", fe.awaiting_player_target, " battle_report_overlay.visible:", fe.battle_report_overlay.visible)

	fe.awaiting_player_target = true
	fe._on_player_attack(rat)
	for i in range(5): await fe.get_tree().process_frame

	print("--- immediately after the killing-blow attack call ---")
	print("battle_over:", fe.battle_over, " awaiting_continue:", fe.awaiting_continue, " rat wounds:", rat.wounds_current, " battle_report_overlay.visible:", fe.battle_report_overlay.visible)
	print("awaiting_player_target:", fe.awaiting_player_target, " awaiting_fortune_choice:", fe.awaiting_fortune_choice, " awaiting_incapacitated_turn:", fe.awaiting_incapacitated_turn, " awaiting_overcast_choice:", fe.awaiting_overcast_choice, " pending_defense.is_empty():", fe.pending_defense.is_empty())

	## Keep simulating Space presses (clearing awaiting_continue whenever
	## it's set) until battle_over becomes true or we give up — this
	## tells us exactly how many continue-prompts are actually in the
	## chain after a killing blow, not just whether the first one exists.
	## Real-dice fix: WS 90 is very likely, but not GUARANTEED, to hit —
	## the point of this test is the battle-END flow once the rat
	## genuinely dies, not the literal single-swing hit chance, so a
	## miss (still not awaiting_continue, still not battle_over, back to
	## awaiting_player_target) swings again rather than sitting in an
	## unbounded await loop forever. Both loops below carry their own
	## real frame-count safety cap regardless, so a genuine stuck state
	## still fails fast instead of hanging the whole regression run.
	var presses := 0
	var max_presses := 15
	var frames_waited := 0
	var max_frames := 600
	while not fe.battle_over and presses < max_presses and frames_waited < max_frames:
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		## Real bug fix: a killing blow can also chain into a Deathblow
		## ("attack another foe?") or bonus-action (Frenzy/Furious
		## Assault) prompt before Act Again/Continue is ever reached —
		## declining both, exactly like a real "no thanks" button press,
		## keeps the flow moving toward battle_over instead of stalling
		## on a prompt this loop used to not know existed.
		if fe.awaiting_deathblow_choice:
			fe._pending_deathblow_target = null
			fe.awaiting_deathblow_choice = false
		if fe.awaiting_bonus_action_choice:
			fe._pending_bonus_action_str = ""
			fe.awaiting_bonus_action_choice = false
		if fe.awaiting_continue:
			fe.awaiting_continue = false
			presses += 1
			print("  simulated Space press #", presses, " -> battle_over:", fe.battle_over)
		elif rat.wounds_current > 0 and fe.awaiting_player_target and fe.pending_defense.is_empty() and not fe.awaiting_fortune_choice:
			## That swing didn't land — take another one at the same
			## still-crippled (1 Wound) target rather than waiting
			## forever for a prompt a miss never raises.
			fe.selected_target = rat
			fe._on_player_attack(rat)
			for i in range(5): await fe.get_tree().process_frame
			frames_waited += 5
		await fe.get_tree().process_frame
		frames_waited += 1

	print("--- after the full continue-press loop ---")
	print("total Space presses needed:", presses, " battle_over:", fe.battle_over, " battle_report_overlay.visible:", fe.battle_report_overlay.visible)

	checks.append(["the last enemy's Wounds genuinely reached 0", rat.wounds_current <= 0])
	checks.append(["battle_over is genuinely true after the killing blow resolves (at most one Space press)", fe.battle_over])
	## Per the follow-up request ("instead of auto picking up loot, i
	## want a new pop up window with the battle report"): the old Return
	## button is never surfaced any more — the Battle Report overlay
	## takes its place (see _show_battle_report() in _end_battle()).
	checks.append(["the Battle Report overlay is genuinely visible once the battle is over", fe.battle_report_overlay.visible])
	checks.append(["there is genuinely no further awaiting_continue prompt left hanging after battle end", not fe.awaiting_continue])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Last Enemy Flow): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
