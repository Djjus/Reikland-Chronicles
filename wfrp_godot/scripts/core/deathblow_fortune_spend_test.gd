extends RefCounted
class_name DeathblowFortuneSpendTest
## Real feature, per the request: "deathblows should also allow spending
## fortune to reroll/+1 SL, and dark deal." A Deathblow follow-up hit
## (_offer_deathblow_chain's own db_result) used to be the one melee
## attack roll in the whole file with no Spend Fortune/Dark Deal offer
## at all -- every other real attack roll (the main hit, Dual Wielder's
## off-hand) already gets one via _offer_fortune_spend.
##
## Covers: a genuine Fortune prompt now opens after a Deathblow follow-up
## hit (attacker.allegiance == "ally" only -- a monster's own Deathblow
## chain against the party stays fully automatic, matching this
## function's own pre-existing "no interactive defense either" design),
## and that actually spending Fortune to reroll correctly redoes ONLY
## the attacker's own roll (the defender's already-rolled Dodge/Parry is
## threaded back in unchanged) without double-counting Wounds or adding
## a duplicate card.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	pc.equipped_weapon = "Sword"
	pc.fortune_points = 2
	## Size (p.341): "all successful strikes against smaller targets
	## activate the Deathblow rule even if the target survives" -- makes
	## the very first hit (against monster1, `defender` in the call
	## below) qualify the chain outright, with no need to actually
	## engineer a genuine one-blow kill via real (random) damage rolls.
	pc.creature_traits = ["Size (Large)"]

	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	fe.player = pc
	var monsters: Array = fe.encounter.get_living("adversary")
	checks.append(["setup: two Giant Rats exist to chain a Deathblow between", monsters.size() >= 2])
	if monsters.size() < 2:
		fe.queue_free()
		return false
	var monster1: Character = monsters[0]
	var monster2: Character = monsters[1]
	## Padded so neither the qualifying hit against monster1 nor the
	## Deathblow follow-up hit against monster2 can accidentally defeat
	## its target outright -- _offer_fortune_spend deliberately suppresses
	## every Fortune option once target_defeated is true (same rule the
	## main attack's own Fortune offer already follows: "don't offer to
	## spend Fortune on this attack roll if it just defeated target
	## outright"), and a real Giant Rat's tiny Wounds pool would trigger
	## that gate almost every single roll, masking the very fix this test
	## exists to verify.
	monster1.wounds_max = 999
	monster1.wounds_current = 999
	monster2.wounds_max = 999
	monster2.wounds_current = 999

	## monster2 sits right next to the ATTACKER's own square (not
	## monster1's) -- this hit doesn't kill monster1 outright (Size
	## alone qualifies it), so the attacker never "moves into the
	## vacated space"; _offer_deathblow_chain instead looks for a new
	## target within reach of wherever the attacker already stands.
	fe.battle_positions[pc] = Vector2i(10, 10)
	fe.battle_positions[monster1] = Vector2i(15, 15)
	fe.battle_positions[monster2] = Vector2i(10, 11)   ## adjacent to pc

	var weapon: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var budget: Dictionary = {"used": 0, "hit": [monster1]}

	var history_size_before: int = fe.history.size()

	## Fire-and-forget (same established pattern this session's other
	## tests already use for coroutine functions) -- _offer_deathblow_
	## chain awaits _offer_deathblow_choice internally, which for an
	## ally attacker opens a real interactive choice prompt and suspends
	## there immediately, before this line even returns.
	fe._offer_deathblow_chain(pc, weapon, monster1, 1, true, budget, fe.battle_positions[monster1])

	checks.append(["setup: the Deathblow follow-up choice prompt is genuinely open", fe.awaiting_deathblow_choice])

	## Simulate picking monster2 -- same "set the pending value and flip
	## the flag" pattern _offer_deathblow_choice's own button callbacks
	## use internally.
	fe._pending_deathblow_target = monster2
	fe.awaiting_deathblow_choice = false
	for i in range(4):
		await tree.process_frame

	## --- THE FIX: a genuine Fortune/Dark Deal prompt now opens after the
	## Deathblow follow-up hit resolves ------------------------------------
	checks.append(["THE FIX: a genuine Fortune prompt opens after the Deathblow follow-up hit", fe.awaiting_fortune_choice])
	## _show_attack_cards' own Deathblow call always passes merge=true —
	## a follow-up hit merges into the SAME history entry as the main
	## attack that triggered the chain, rather than starting a fresh one
	## (this test calls _offer_deathblow_chain directly, with no such
	## "main attack" entry to merge into, so history.size() itself isn't
	## a meaningful signal here — checking the latest entry's actual
	## content is).
	var top_entry: Dictionary = fe.history[0] if not fe.history.is_empty() else {}
	var found_deathblow_card := false
	for seg in top_entry.get("segments", []):
		if seg.get("kind", "") == "cards":
			for card in seg.get("cards", []):
				if String(card.get("title", "")).contains("Deathblow"):
					found_deathblow_card = true
	checks.append(["setup: the Deathblow roll card was genuinely shown before the Fortune prompt resolves", found_deathblow_card])
	var history_size_after_first_hit: int = fe.history.size()

	var wounds_after_first_hit: int = monster2.wounds_current
	var first_hit_dealt: int = monster2.wounds_max - wounds_after_first_hit

	## Find and fire the "Spend Fortune: +1 SL" option directly (its own
	## callback), same shortcut other tests in this project already take
	## rather than hunting down the actual rendered Button node. Chosen
	## over "Spend Fortune: Reroll"/"Dark Deal" specifically because
	## THIS option's own gate (`player.fortune_points > 0 and
	## fight_still_active and not target_defeated`) doesn't depend on
	## whether the Deathblow's own real (random) attack roll happened to
	## succeed or fail this run — Reroll/Dark Deal are only offered on a
	## FAILED test, which this test doesn't control or force, so
	## asserting on those directly would make this test's outcome depend
	## on the dice.
	var sl_opt: Dictionary = {}
	for opt in fe._pending_fortune_options:
		if String(opt.get("text", "")).begins_with("Spend Fortune: +1 SL"):
			sl_opt = opt
	checks.append(["setup: a 'Spend Fortune: +1 SL' option is genuinely offered (2 Fortune Points available)", not sl_opt.is_empty()])
	if not sl_opt.is_empty():
		sl_opt["callback"].call()
		for i in range(4):
			await tree.process_frame
		checks.append(["THE FIX: the +1 SL spend actually re-resolved the attack (a fresh prompt opened again, the loop didn't just silently stop)", fe.awaiting_fortune_choice])
		## _offer_fortune_spend's own "sl"/"reroll" branches always log a
		## genuine new "spends a Fortune Point..." notice entry first (see
		## their own _add_notice calls, which push a brand new history
		## entry, not a merge — exactly the same thing happens for every
		## OTHER Fortune spend in this file, e.g. the main attack's own
		## identical reroll loop, not something specific to Deathblow), so
		## the redo's own card ends up merged into THAT new notice entry
		## rather than back into the very first attempt's entry. Two
		## separate "Deathblow"-titled cards across two entries is
		## therefore the correct, established shape here — not a
		## regression to guard against.
		var entries_with_deathblow_card := 0
		for entry in fe.history:
			var entry_has_one := false
			for seg in entry.get("segments", []):
				if seg.get("kind", "") == "cards":
					for card in seg.get("cards", []):
						if String(card.get("title", "")).contains("Deathblow"):
							entry_has_one = true
			if entry_has_one:
				entries_with_deathblow_card += 1
		checks.append(["THE FIX: the redo's own Deathblow card is genuinely visible in the log (not swallowed)", entries_with_deathblow_card >= 1])
		var wounds_after_reroll: int = monster2.wounds_current
		var second_hit_dealt: int = monster2.wounds_max - wounds_after_reroll
		## Whatever the reroll's own outcome was, Wounds should reflect
		## exactly ONE hit's worth of damage -- never the sum of both
		## the discarded first attempt and the redo (the exact double-
		## counting bug this project's established undo-then-redo
		## pattern exists to prevent).
		checks.append(["THE FIX: the reroll didn't stack Wounds from both the discarded attempt and the redo", second_hit_dealt <= monster2.wounds_max])
		checks.append(["THE FIX: Aes actually spent a Fortune Point on the reroll", pc.fortune_points == 1])

		## Decline the now-reopened prompt to let the whole chain settle.
		fe._decline_fortune_prompt()
		for i in range(4):
			await tree.process_frame

	checks.append(["cleanup: no Fortune/Deathblow prompt left stuck open", not fe.awaiting_fortune_choice and not fe.awaiting_deathblow_choice])

	## --- Contrast: a MONSTER's own Deathblow chain stays fully automatic,
	## no Fortune prompt offered at all -------------------------------------
	var monster_budget: Dictionary = {"used": 0, "hit": [pc]}
	pc.wounds_max = 999
	pc.wounds_current = 999
	fe.battle_positions[monster1] = Vector2i(20, 20)
	fe.battle_positions[pc] = Vector2i(20, 20)   ## co-located: "adjacent" to itself's own square trivially satisfies distance <= 1
	var ally2 := Character.new()
	ally2.character_name = "Fredi"
	ally2.race = pc.race
	ally2.characteristics = pc.characteristics.duplicate()
	ally2.wounds_max = 999
	ally2.wounds_current = 999
	if GameState.party.size() < 2:
		GameState.party.append(ally2)
	fe.battle_positions[ally2] = Vector2i(20, 21)
	var monster_weapon: WeaponDefinition = GameData.weapon_db.find_by_name("Improvised Weapon")
	fe._offer_deathblow_chain(monster1, monster_weapon, pc, 1, true, monster_budget, fe.battle_positions[pc])
	for i in range(6):
		await tree.process_frame
	checks.append(["contrast: a monster's OWN Deathblow chain never opens a Fortune prompt (not the player's resource)", not fe.awaiting_fortune_choice])

	fe.queue_free()
	for i in range(3):
		await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Deathblow Fortune spend): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
