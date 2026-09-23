extends RefCounted
class_name DeathblowMoveIntoSquareTest
## Regression/verification test for the request ("player deathblows
## (single hit kills from full hp) should make the character who
## performed it move into the square where the enemy they succeeded the
## deathblow against"): confirms _offer_deathblow_chain() (Options,
## p.160 — see its own leading comment in field_encounter_screen.gd)
## genuinely repositions the attacker into the fallen defender's own
## square — and ONLY when a follow-up Deathblow attack is actually
## accepted, per the explicit scope confirmed for this request: move-in
## stays tied to continuing the chain (not an unconditional "any clean
## kill relocates you" rule), and applies symmetrically to whichever
## side lands the blow (same shared function serves both the player's
## own attacks and a monster's).
##
## Calls _offer_deathblow_chain() directly (same technique this
## project's own social-combat tests use for choice-branch coverage)
## rather than driving a full random attack roll to a guaranteed
## kill-from-full-HP: a real WS/Strength-driven swing can't be relied
## on to land AND one-shot a full-HP target on a fixed dice seed, so
## going through the real _on_player_attack() path would make this
## test's core assertion (did the attacker's square change) hostage to
## RNG it has nothing to do with. Uses `fe` (a live FieldEncounter.tscn
## instance the caller owns) as its fixture, matching the project's own
## `run_test(fe)` convention (see e.g. last_enemy_flow_test.gd /
## dead_monster_removed_from_map_test.gd).
##
## Real, confirmed bug found via user report AFTER this test's first
## version already reported ALL PASS ("Felix performed 2 deathblow in
## this fight, but was never moved into his targets square, and now
## cant reach the last target at all" — then reproduced again with a
## second character, Alberta, in the same session): every real call
## site erases a genuinely-killed defender from battle_positions (via
## _check_for_kill_xp() + _render_status() -> _cull_dead_monsters_from_
## map()) BEFORE _offer_deathblow_chain() ever runs, so reading
## battle_positions[defender] at that point — what this test's first
## version, and the production code, both did — always found nothing.
## _offer_deathblow_chain() now takes an explicit
## defender_square_before_hit param that every caller snapshots BEFORE
## the hit resolves, precisely so it doesn't depend on the corpse still
## being in battle_positions by the time it actually checks. Every case
## below now erases the defender from battle_positions BEFORE calling
## _offer_deathblow_chain() (reproducing exactly what the real call
## sites already do to it) while still passing the correct pre-erase
## square through the new parameter — this is what the first version of
## this test failed to reproduce, which is exactly why it missed the
## bug despite exercising the "right" code path.

static func run_test(fe) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "DeathblowMoveTestPlayer"
	pc.equipped_weapon = "Sword"   ## guaranteed melee — the book rule (and _offer_deathblow_chain's own is_ranged guard) is melee-only

	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	## Two Giant Rats, pinned, so there's always a real second adversary
	## within reach of the first one's own square once it falls.
	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat"]
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.monsters.size() >= 2 and fe.battle_positions.has(fe.player) \
		and fe.battle_positions.has(fe.monsters[0]) and fe.battle_positions.has(fe.monsters[1])
	checks.append(["setup: player + two real monsters, all with a real battle position", setup_ok])
	if not setup_ok:
		print("RESULT (Deathblow Move Into Square): SETUP FAILED")
		return false

	var rat0: Character = fe.monsters[0]
	var rat1: Character = fe.monsters[1]
	var weapon: WeaponDefinition = fe.weapons.get(fe.player)
	checks.append(["setup: player's own weapon resolved and is genuinely melee", weapon != null and not weapon.is_ranged])
	if weapon == null or weapon.is_ranged:
		print("RESULT (Deathblow Move Into Square): SETUP FAILED (no melee weapon)")
		return false

	## Deliberately distinct, deterministic squares — not wherever
	## _start_encounter()'s own opening formation happened to place
	## everyone — so a later "did the attacker's square change" check
	## can't pass by coincidence.
	var player_square := Vector2i(0, 0)
	var rat0_square := Vector2i(5, 5)
	var rat1_square := Vector2i(5, 6)   ## adjacent to rat0_square (distance 1) — the real reach check _offer_deathblow_chain runs
	fe.battle_positions[fe.player] = player_square
	fe.battle_positions[rat0] = rat0_square
	fe.battle_positions[rat1] = rat1_square

	## --- Case 1: killed outright, a real candidate in reach, and the
	## follow-up is ACCEPTED — the attacker should genuinely move into
	## rat0's own vacated square.
	rat0.wounds_current = 0   ## simulates this exact hit having just finished a full-HP target off
	var rat0_square_before_erase: Vector2i = fe.battle_positions.get(rat0, Vector2i(-1, -1))
	## Reproduces exactly what every real call site's own
	## _check_for_kill_xp() + _render_status() already does to a
	## genuinely-killed defender before _offer_deathblow_chain() ever
	## runs — see this file's own leading comment on the real bug this
	## caught. Without this erase() here, this test does not reproduce
	## the actual bug at all.
	fe.battle_positions.erase(rat0)
	var budget1: Dictionary = {"used": 0, "hit": [rat0]}
	## Not awaited here on purpose: for a player (ally) attacker,
	## _offer_deathblow_choice runs its UI-building synchronously and
	## only THEN suspends on `while awaiting_deathblow_choice: await
	## process_frame` — so by the time this call itself first yields
	## control back here, awaiting_deathblow_choice is already the real,
	## live signal to watch (same "kick off, then poll" technique
	## last_enemy_flow_test.gd already uses for _on_player_attack()).
	fe._offer_deathblow_chain(fe.player, weapon, rat0, rat0.wounds_max, true, budget1, rat0_square_before_erase)

	var saw_prompt := false
	for i in range(10):
		await fe.get_tree().process_frame
		if fe.awaiting_deathblow_choice:
			saw_prompt = true
			break
	checks.append(["Case 1: a real Deathblow follow-up prompt fired (candidate genuinely in reach)", saw_prompt])

	if saw_prompt:
		fe._pending_deathblow_target = rat1
		fe.awaiting_deathblow_choice = false
		for i in range(15):
			await fe.get_tree().process_frame
			if not fe.battle_positions.has(rat0):
				break

	checks.append(["Case 1: rat0's own square is genuinely vacated (erased from battle_positions)", not fe.battle_positions.has(rat0)])
	checks.append(["Case 1: the attacker actually moved into the square rat0 occupied", fe.battle_positions.get(fe.player, Vector2i(-99, -99)) == rat0_square])
	checks.append(["Case 1: ...and that's a real move (not just coincidentally the same square it started in)", rat0_square != player_square])
	checks.append(["Case 1: the accepted follow-up was genuinely logged against rat1 (budget bookkeeping)", budget1["hit"].has(rat1)])

	## --- Case 2: killed outright, a real candidate in reach, but the
	## follow-up is DECLINED — per the confirmed scope ("only when
	## chaining"), the attacker should NOT move just because a kill
	## happened; moving in is earned only by actually continuing the
	## chain.
	fe.battle_positions.clear()
	var player_square2 := Vector2i(0, 0)
	var rat2_square := Vector2i(5, 5)
	var rat3_square := Vector2i(5, 6)
	var rat2 := Character.new()
	rat2.character_name = "DB Test Rat A"
	rat2.allegiance = "adversary"
	rat2.wounds_max = 5
	rat2.wounds_current = 0
	var rat3 := Character.new()
	rat3.character_name = "DB Test Rat B"
	rat3.allegiance = "adversary"
	rat3.wounds_max = 5
	rat3.wounds_current = 5
	fe.encounter.turn_order.append(rat2)
	fe.encounter.turn_order.append(rat3)
	fe.battle_positions[fe.player] = player_square2
	fe.battle_positions[rat2] = rat2_square
	fe.battle_positions[rat3] = rat3_square

	var rat2_square_before_erase: Vector2i = fe.battle_positions.get(rat2, Vector2i(-1, -1))
	fe.battle_positions.erase(rat2)   ## reproduces the real call sites' own pre-Deathblow cull — see this file's leading comment
	var budget2: Dictionary = {"used": 0, "hit": [rat2]}
	fe._offer_deathblow_chain(fe.player, weapon, rat2, rat2.wounds_max, true, budget2, rat2_square_before_erase)
	var saw_prompt2 := false
	for i in range(10):
		await fe.get_tree().process_frame
		if fe.awaiting_deathblow_choice:
			saw_prompt2 = true
			break
	checks.append(["Case 2 setup: the follow-up prompt fired again (same reach as Case 1)", saw_prompt2])
	if saw_prompt2:
		fe._pending_deathblow_target = null   ## Decline
		fe.awaiting_deathblow_choice = false
		for i in range(10):
			await fe.get_tree().process_frame

	checks.append(["Case 2: declining the follow-up leaves the attacker exactly where they were — no move", fe.battle_positions.get(fe.player, Vector2i(-99, -99)) == player_square2])

	## --- Case 3: killed outright, but NO candidate anywhere in reach —
	## no prompt should even fire, and the attacker stays put.
	fe.battle_positions.clear()
	var player_square3 := Vector2i(0, 0)
	var rat4_square := Vector2i(20, 20)   ## far outside any reach radius
	var rat4 := Character.new()
	rat4.character_name = "DB Test Rat C"
	rat4.allegiance = "adversary"
	rat4.wounds_max = 5
	rat4.wounds_current = 0
	fe.encounter.turn_order.append(rat4)
	fe.battle_positions[fe.player] = player_square3
	fe.battle_positions[rat4] = rat4_square

	var rat4_square_before_erase: Vector2i = fe.battle_positions.get(rat4, Vector2i(-1, -1))
	fe.battle_positions.erase(rat4)   ## reproduces the real call sites' own pre-Deathblow cull — see this file's leading comment
	var budget3: Dictionary = {"used": 0, "hit": [rat4]}
	var chained3: bool = await fe._offer_deathblow_chain(fe.player, weapon, rat4, rat4.wounds_max, true, budget3, rat4_square_before_erase)
	checks.append(["Case 3: no candidate in reach — no follow-up offered at all", not chained3 and not fe.awaiting_deathblow_choice])
	checks.append(["Case 3: the attacker stays exactly where they were — nothing to move into", fe.battle_positions.get(fe.player, Vector2i(-99, -99)) == player_square3])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Deathblow Move Into Square): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
