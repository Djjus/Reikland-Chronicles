extends RefCounted
class_name PsychologyTest
## Per the request ("let implement Bestial, Broken, Fear and Terror
## fully. Let enemies run away if they need to and if they reach the
## edge of the battle map remove them from the battle (they will count
## as defeated but NOT drop any loot). IF players gain Broken, Fear or
## Terror restrict their actions and movement appropriately"):
##
## A/B — Bestial (p.338): a badly-hurt, non-Territorial Bestial creature
## genuinely flees (moves away from its threats) instead of the old
## "cowers in place" stand-in, and one that flight carries onto the
## battle grid's own edge is removed from the fight entirely — counted
## as defeated (XP awarded, same as a real kill) but never dropping loot.
## C/D — Broken (p.168): a Broken monster or player forces a flee-and-
## hide movement on its own turn instead of fighting normally.
## E/F — Broken's own end-of-Round recovery inputs: circumstance-scaled
## Test difficulty, and the "hidden out of line of sight" check (now
## meaningfully achievable thanks to the random battle obstacle scatter).
## G/H — Fear (Rating): per-character tracking (a real bug fix — this
## used to be one shared flag no matter how many allies were fighting)
## and the Extended Test that can actually shake it off mid-battle.
## I — Fear's "cannot move closer without a Cool Test" movement gate.

## Drains awaiting_continue/awaiting_fortune_choice for up to `frames`
## engine frames — the same pattern MonsterDisengageTest's own Case 2
## established for a fire-and-forget async call (_do_monster_turn/
## _prompt_player_turn's own Broken branches can go through real
## _wait_for_continue() card prompts, which would otherwise block
## forever with nothing left to clear them in a headless test run).
##
## Real, once-flaky race worth documenting: _do_monster_turn has an
## unconditional "thinking pause" (await get_tree().create_timer(0.6).
## timeout) ahead of its Regenerate/Stupid/Bestial checks — a REAL-TIME
## wait, not gated by awaiting_continue/awaiting_fortune_choice at all.
## In a headless run, engine frames can process far faster than 0.6
## real seconds' worth, so draining flags across a fixed `frames` count
## of process_frame yields does NOT guarantee that pause has actually
## elapsed — a bare (non-awaited) _do_monster_turn call can still be
## sitting inside that timer when this returns. The next test section
## then reuses the same shared Character/battle_positions state while
## that stale coroutine is still mid-flight, and when its timer finally
## does fire (for real, later), it resumes and mutates state the next
## section already moved on from — a genuine two-coroutines-on-one-
## Character race (caught via intermittent Test B failures: wolf
## sometimes never reached/finished its edge-despawn because its own
## Test A invocation was still paused on this exact timer when Test B's
## setup ran). A short real-time floor here closes it — cheap insurance
## against exactly that overlap.
static func _settle(fe, frames: int = 240) -> void:
	for i in range(frames):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
	## A fixed real-time sleep here (tried 1.0s, then 2.5s) still raced
	## occasionally under load -- guessing at one "surely long enough"
	## duration doesn't actually close the race, it just makes it rarer.
	## This instead adaptively waits in short real-time slices, draining
	## whatever flag turns up in each, until several slices in a row find
	## nothing left to drain (the coroutine has genuinely gone quiet) --
	## capped at a generous ceiling as a backstop against a truly stuck
	## coroutine. Costs at minimum QUIET_TARGET * SLICE seconds even when
	## nothing was ever mid-flight, which is fine for a permanent test.
	const SLICE := 0.25
	const QUIET_TARGET := 8
	const MAX_TOTAL := 15.0
	var quiet_slices := 0
	var total_wait := 0.0
	while quiet_slices < QUIET_TARGET and total_wait < MAX_TOTAL:
		await fe.get_tree().create_timer(SLICE).timeout
		total_wait += SLICE
		var drained := false
		if fe.awaiting_continue:
			fe.awaiting_continue = false
			drained = true
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
			drained = true
		quiet_slices = 0 if drained else quiet_slices + 1

	## Extra unconditional grace period, independent of the flag-based
	## quiet detection above. _do_monster_turn() (and the Surprised/Broken
	## branches it can take) sits on a bare, un-flagged
	## `await get_tree().create_timer(0.6).timeout` before it ever touches
	## awaiting_continue/awaiting_fortune_choice -- a straggler coroutine
	## parked on exactly that timer looks perfectly quiet to the loop
	## above (nothing to drain yet) and can then resume and mutate shared
	## state (Character positions/Wounds, xp_awarded_for, ...) well after
	## this function already returned "settled". A flat wait comfortably
	## longer than that single timer closes this without needing a second
	## flag to track every bare real-time await in the file.
	await fe.get_tree().create_timer(1.2).timeout

static func run_test(fe) -> bool:
	var checks: Array = []

	## Real test-infrastructure race, worth documenting: FieldEncounterScreen's
	## own _ready() already fires its own, real, randomly-generated
	## _start_encounter() the moment this scene enters the tree — a real
	## random monster pool can include a Fear/Terror creature, which
	## sends that FIRST (unwanted) encounter's own setup through
	## _check_fear_and_terror()'s await _wait_for_continue() chain. If
	## this test's own _settle() calls (below, scattered through every
	## section) drain awaiting_continue while that background coroutine
	## is still mid-flight, it keeps making progress in parallel with
	## everything this test does afterward — up to and including
	## reassigning the shared `player` field right out from under a
	## later section, which is exactly the flaky failure this drain
	## avoids by fully exhausting that first coroutine's own continues
	## BEFORE this test starts its own _start_encounter() call and
	## setup, rather than racing it.
	for i in range(120):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var test_player := CharacterCreator.create_character("PsychTestPlayer", human, soldier, {})
	fe.player = test_player
	var ally_b := CharacterCreator.create_character("PsychTestAllyB", human, soldier, {})
	for a in [test_player, ally_b]:
		a.equipped_weapon = "Sword"
		a.allegiance = "ally"
		a.characteristics.set_value("toughness", 40)
		a.characteristics.set_value("weapon_skill", 50)
		a.characteristics.set_value("willpower", 40)
		a.wounds_current = a.wounds_max

	var wolf_def: MonsterDefinition = GameData.monster_db.find_by_name("Wolf")
	var wolf: Character = wolf_def.to_character()
	wolf.allegiance = "adversary"
	wolf.wounds_max = 20
	wolf.wounds_current = 8   ## 40% -- triggers Bestial's own Flee threshold (<=50%)

	var goblin_def: MonsterDefinition = GameData.monster_db.find_by_name("Goblin")
	var goblin: Character = goblin_def.to_character()
	goblin.allegiance = "adversary"
	goblin.wounds_max = 200
	goblin.wounds_current = 200

	var monsters_arr: Array[Character] = [wolf, goblin]
	fe.monsters = monsters_arr
	fe.monster_defs[wolf] = wolf_def
	fe.monster_defs[goblin] = goblin_def
	var sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	fe.weapons[test_player] = sword
	fe.weapons[ally_b] = sword
	var wolf_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(wolf_def.weapon_name)
	fe.weapons[wolf] = wolf_weapon if wolf_weapon != null else sword
	var goblin_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(goblin_def.weapon_name)
	fe.weapons[goblin] = goblin_weapon if goblin_weapon != null else sword

	fe.encounter = CombatEncounter.new()
	fe.encounter.add_combatant(test_player)
	fe.encounter.add_combatant(ally_b)
	fe.encounter.add_combatant(wolf)
	fe.encounter.add_combatant(goblin)
	fe.encounter.roll_initiative()

	fe.battle_grid = BattleGrid.new()
	fe.battle_grid.generate_from_terrain_snapshot([])
	fe.battle_grid.obstacle_type.clear()   ## isolate from the random obstacle scatter -- this test wants full control over LOS/impassable squares
	fe.battle_grid.obstacle_group.clear()
	fe.battle_grid.obstacles.clear()
	fe.battle_grid.obstacle_cover.clear()
	fe.battle_grid.blocks_los.clear()
	fe.battle_grid.impassable.clear()
	fe.battle_grid.cover.clear()
	fe.battle_grid.mud.clear()
	fe.battle_over = false
	fe.melee_has_begun = true
	fe.awaiting_player_target = false
	fe.awaiting_continue = false
	fe.pending_defense.clear()
	fe.xp_awarded_for.clear()

	## Real test-infrastructure note (same family as the race documented
	## at the top of run_test()): _next_turn() (called internally at the
	## end of a monster's own turn resolution, including from inside
	## _flee_and_maybe_escape below) calls encounter.advance_turn(),
	## which just does current_turn_index += 1 and wraps. roll_initiative()
	## above left current_turn_index at -1 (nobody's had a real turn
	## yet), so the FIRST bare _do_monster_turn() call this test makes
	## advances straight to index 0 -- and if the actor being tested
	## happens to have sorted first in the random initiative order, that
	## lands right back on the SAME actor, immediately re-dispatching a
	## second real turn for it before this section's own _settle() ever
	## returns (caught via an intermittent doubled monster_turn_count on
	## the actor under test, corrupting its position/Wounds out from
	## under the very assertions checking them). Explicitly pointing
	## current_turn_index at the actor's own slot in turn_order first
	## means advance_turn() moves to whoever's genuinely NEXT instead --
	## an ally's turn just builds its action menu and returns without
	## blocking on anything this headless test would need to drive, so
	## the chain harmlessly stops there rather than ever doubling back.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(wolf)

	## --- A: Bestial flee movement ---
	fe.battle_positions.clear()
	fe.battle_positions[wolf] = Vector2i(15, 9)
	fe.battle_positions[test_player] = Vector2i(15, 10)   ## adjacent -- an ally right next to it
	fe.battle_positions[ally_b] = Vector2i(16, 9)
	fe.battle_positions[goblin] = Vector2i(1, 1)
	wolf.wounds_current = 8
	var start_pos_a: Vector2i = fe.battle_positions[wolf]
	fe._do_monster_turn(wolf)
	await _settle(fe)
	var moved_away: bool = fe.battle_positions.has(wolf) and fe.battle_positions[wolf] != start_pos_a
	checks.append(["A: a badly-hurt, non-Territorial Bestial creature genuinely moves when fleeing (not the old stand-in-in-place cower)", moved_away or not fe.battle_positions.has(wolf)])
	if fe.battle_positions.has(wolf):
		var moved_farther: bool = fe.battle_grid.distance_squares(fe.battle_positions[wolf], fe.battle_positions[test_player]) > fe.battle_grid.distance_squares(start_pos_a, fe.battle_positions[test_player])
		checks.append(["A: the Bestial flee move actually increases distance from its threats, not just moves randomly", moved_farther])

	## Defensive pin (same race family as above): if a straggler cascade
	## from test A's own _next_turn() chain is still unresolved when this
	## section's _settle() returned (e.g. a real-time await that outlasted
	## the settle window), pointing current_turn_index at the one truly
	## blocking combatant (test_player) means any FUTURE advance_turn()
	## call lands harmlessly on the action-menu-building player turn
	## instead of potentially cascading back around onto wolf or goblin
	## mid-setup for the next section.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(test_player)

	## --- B: Bestial flee reaching the map edge despawns it, no loot, but XP ---
	fe.battle_positions.clear()
	fe.battle_positions[wolf] = Vector2i(1, 9)   ## already right next to the x=0 edge
	fe.battle_positions[test_player] = Vector2i(20, 9)   ## far away, on the opposite side -- flee direction points straight at the edge
	fe.battle_positions[ally_b] = Vector2i(21, 9)
	fe.battle_positions[goblin] = Vector2i(1, 1)
	wolf.wounds_current = 8
	wolf.wounds_max = 20
	wolf.monster_movement = 10
	fe.xp_awarded_for.clear()
	var inventory_before: int = test_player.inventory.size()
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(wolf)
	fe._do_monster_turn(wolf)
	await _settle(fe)
	checks.append(["B: a Bestial creature whose flee carries it onto the battle grid's own edge is removed from battle_positions entirely", not fe.battle_positions.has(wolf)])
	checks.append(["B: it's marked defeated (0 Wounds) so get_living()/win-condition checks correctly treat it as counting as defeated", wolf.wounds_current <= 0])
	checks.append(["B: XP is still awarded for it, same as a real kill", fe.xp_awarded_for.has(wolf)])
	## Compares inventory SIZE only (not "has Uncooked Meat" in isolation)
	## -- test A above can, on some random Cool Test/damage rolls, itself
	## end in a real kill (its own free-attack punishment for wolf's
	## flee, unrelated to this despawn path) that legitimately drops real
	## meat loot into this same test_player's inventory first. A size
	## comparison against inventory_before (captured fresh right before
	## THIS action) is the actually-correct proof that THIS action —
	## the despawn — added nothing, regardless of what test A left behind.
	checks.append(["B: it does NOT drop loot (inventory size unchanged by the despawn itself)", test_player.inventory.size() == inventory_before])

	## Defensive pin -- see the identical comment after test A above.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(test_player)

	## --- C: Broken monster forced flee, doesn't attack normally ---
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(goblin)
	fe.battle_positions.clear()
	fe.battle_positions[goblin] = Vector2i(15, 9)
	fe.battle_positions[test_player] = Vector2i(15, 10)
	fe.battle_positions[ally_b] = Vector2i(3, 3)
	fe.battle_positions[wolf] = Vector2i(1, 1)
	goblin.conditions.clear()
	goblin.conditions["Broken"] = 1
	goblin.wounds_current = goblin.wounds_max
	test_player.wounds_current = test_player.wounds_max
	var start_pos_c: Vector2i = fe.battle_positions[goblin]
	var player_wounds_before_c := test_player.wounds_current
	fe._do_monster_turn(goblin)
	await _settle(fe)
	checks.append(["C: a Broken monster moves away instead of fighting normally on its own Turn", not fe.battle_positions.has(goblin) or fe.battle_positions[goblin] != start_pos_c])
	checks.append(["C: a Broken monster never actually attacks anyone on that forced-flee Turn", test_player.wounds_current == player_wounds_before_c])

	## --- D: Broken player forced flee ---
	## Deliberately NOT adjacent to a living monster here (unlike test C's
	## mirror-image monster case) — this test is specifically about the
	## forced-flee movement and turn-passing itself; whether the same
	## Flee free-attack penalty _prompt_broken_turn() now also applies is
	## already exercised structurally by test A/C's own free-attack paths
	## (which reuse the exact same _resolve_monster_free_attack/
	## _resolve_free_attack functions this one calls into), and skipping
	## it here avoids this test's own pass/fail hinging on an unrelated
	## real combat roll against test_player.
	fe.encounter.current_turn_index = fe.encounter.turn_order.find(test_player)
	fe.battle_positions.clear()
	fe.battle_positions[test_player] = Vector2i(15, 9)
	fe.battle_positions[goblin] = Vector2i(20, 9)
	fe.battle_positions[ally_b] = Vector2i(1, 1)
	fe.battle_positions[wolf] = Vector2i(2, 1)
	test_player.conditions.clear()
	test_player.conditions["Broken"] = 1
	test_player.wounds_current = test_player.wounds_max
	goblin.wounds_current = goblin.wounds_max
	var start_pos_d: Vector2i = fe.battle_positions[test_player]
	fe.movement_remaining = test_player.get_movement() * 2
	fe.player = test_player   ## belt-and-braces -- see the race documented at the top of run_test()
	fe._prompt_player_turn()
	var settle_frames := 0
	while not fe.awaiting_incapacitated_turn and settle_frames < 240:
		if fe.awaiting_continue:
			fe.awaiting_continue = false   ## drains the Flee free-attack's own Cool Test card, if goblin (adjacent at the start) got one in before the forced flee's own Continue prompt shows
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame
		settle_frames += 1
	checks.append(["D: a Broken player's turn auto-resolves into the forced flee prompt rather than the normal action menu", fe.awaiting_incapacitated_turn])
	var moved_before_continue: bool = not fe.battle_positions.has(test_player) or fe.battle_positions[test_player] != start_pos_d
	checks.append(["D: the forced flee itself already moved the Broken player away, before the player even confirms Continue", moved_before_continue])
	fe.awaiting_incapacitated_turn = false
	await _settle(fe, 60)

	## --- E: Broken recovery Test difficulty scales with circumstance ---
	fe.battle_positions.clear()
	fe.battle_positions[test_player] = Vector2i(10, 9)
	fe.battle_positions[goblin] = Vector2i(11, 9)   ## adjacent -- danger
	checks.append(["E: right next to a living enemy scores Very Hard (-30), matching the book's own 'in danger' guidance", fe._broken_recovery_modifier_for(test_player) == -30])
	fe.battle_positions[goblin] = Vector2i(29, 17)   ## far corner -- safe
	checks.append(["E: far from every living enemy scores Average (+20), matching the book's own 'safe' guidance", fe._broken_recovery_modifier_for(test_player) == 20])
	fe.battle_positions[goblin] = Vector2i(15, 9)   ## middling distance -- neither
	checks.append(["E: a middling distance falls back to this project's existing Challenging (+0) baseline", fe._broken_recovery_modifier_for(test_player) == 0])

	## --- F: hidden-from-enemies (Broken's out-of-LOS auto-recovery) ---
	fe.battle_positions[test_player] = Vector2i(5, 5)
	fe.battle_positions[goblin] = Vector2i(5, 9)
	fe.battle_grid.blocks_los.clear()
	checks.append(["F: nothing hidden yet — open ground, the enemy still has line of sight", not fe._is_hidden_from_enemies(test_player)])
	fe.battle_grid.blocks_los[Vector2i(5, 7)] = true   ## sits directly on the line between them
	checks.append(["F: an LOS-blocking obstacle square between them makes the player genuinely hidden", fe._is_hidden_from_enemies(test_player)])
	fe.battle_grid.blocks_los.clear()

	## --- G: Fear is tracked per-character now, not one shared flag ---
	fe._fear_sources.clear()
	fe._fear_rating.clear()
	fe._fear_extended_sl.clear()
	fe._mark_fear_source(ally_b, goblin, 3)
	checks.append(["G: marking ally_b as Subject to Fear from a source does NOT also mark test_player (the old shared-flag bug)", fe._fear_sources.get(ally_b, {}).has(goblin) and not fe._fear_sources.get(test_player, {}).has(goblin)])

	## --- H: Fear's Extended Test can actually shake it off mid-battle ---
	fe._fear_sources.clear()
	fe._fear_rating.clear()
	fe._fear_extended_sl.clear()
	fe._mark_fear_source(ally_b, goblin, 1)   ## Rating 1 -- accumulating just 1 net SL clears it
	ally_b.characteristics.set_value("willpower", 90)   ## pushes the Cool Test target high enough that success is very likely each attempt
	## A handful of ticks rather than just one -- a single Cool Test's SL
	## is still a real dice roll (not literally guaranteed even at a ~90
	## target), but the running Extended Test total only ever needs to
	## reach Rating 1 across as many Rounds as it takes, so repeating the
	## same per-Round tick this many times is both realistic (this is
	## exactly what several real Rounds of combat would do) and removes
	## the flakiness a single roll would carry.
	for i in range(6):
		if not fe._fear_sources.get(ally_b, {}).has(goblin):
			break
		await fe._tick_fear_extended_tests()
	checks.append(["H: a strong Cool Test result against a low Fear Rating clears it via the Extended Test", not fe._fear_sources.get(ally_b, {}).has(goblin)])

	## --- I: Fear blocks moving closer to its source without a Cool Test ---
	## test_player's own Condition set is cleared first -- still carrying
	## Broken from test D would make _enter_move_mode()'s own internal
	## _prompt_player_turn(false) call re-trigger ITS forced-flee prompt
	## before this test ever gets to the Fear gate/_try_commit_move it
	## actually wants to exercise (a real cross-test contamination bug
	## caught while stabilizing this test, not a bug in the shipped
	## Broken/Fear code itself).
	test_player.conditions.clear()
	test_player.wounds_current = test_player.wounds_max
	fe.battle_positions.clear()
	fe.battle_positions[test_player] = Vector2i(5, 9)
	fe.battle_positions[goblin] = Vector2i(25, 9)   ## far away -- plenty of room to test "closer"
	fe.battle_positions[ally_b] = Vector2i(1, 1)
	fe.battle_positions[wolf] = Vector2i(2, 1)
	fe._fear_sources.clear()
	fe._fear_rating.clear()
	fe._fear_extended_sl.clear()
	fe._mark_fear_source(test_player, goblin, 5)
	test_player.characteristics.set_value("willpower", 1)   ## near-certain Cool Test failure
	fe.movement_remaining = test_player.get_movement() * 2
	fe.player = test_player   ## belt-and-braces -- see the race documented at the top of run_test(); _try_commit_move's Fear gate reads the shared `player` field, which must be test_player for the Fear source marked above to actually apply
	fe._enter_move_mode()
	var closer_square := Vector2i(9, 9)   ## strictly closer to goblin (25,9) than the start square (5,9)
	var start_pos_i: Vector2i = fe.battle_positions[test_player]
	fe._try_commit_move(closer_square)
	await _settle(fe, 60)
	checks.append(["I: a failed Fear Cool Test cancels the whole move attempt -- the player never actually gets closer to the source", fe.battle_positions[test_player] == start_pos_i])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Psychology: Bestial/Broken/Fear/Terror): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
