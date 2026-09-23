extends RefCounted
class_name PartyWipeAndReviveTest
## Regression/functional test for the reported crash ("the game crashed
## when accepting fate and letting a character die (chose not to use
## fate) while inside the Sewer") and the follow-up redesign it asked
## for: "remove the old revive mechanic... If a character dies he
## should lie on the floor where he was and simply be dead (skip his
## turn), if the entire party dies move them from any screen they are
## on to the Temple of Shallya in Ubersreik (or the healer in Giessingen
## if they are on the same map as him)... give healers the ability to
## get Fate points while holding the secret cheat button."
##
## ROOT CAUSE (confirmed by reading the crash line): _handle_fatal_moment()'s
## old no-Fate branch called get_tree().change_scene_to_file("Death.tscn")
## with no battle_over flag set first. Every caller immediately follows up
## with `await _wait_for_continue()`, whose poll loop awaits
## get_tree().process_frame -- but by the time that await actually resumes
## (the next frame), change_scene_to_file()'s deferred free had already
## torn this very node out of the tree, so get_tree() came back null and
## `.process_frame` on null threw exactly the reported error.
##
## THE FIX: no more permadeath scene at all. A character with no Fate
## left is marked Character.is_dead (new field) and left at 0 Wounds
## exactly where they fell -- no scene change, so no crash, and no
## special-casing needed for the turn-skip either, since
## CombatEncounter.is_defeated() already treats 0 Wounds as "skip this
## character" for anyone. A real party wipe (_end_battle(false), which
## used to auto-heal-to-full and drop the party for free back at the
## village -- the actual "old revive mechanic" being removed) now instead
## routes the party to a real Shallyan Priest (Ubersreik's Temple of
## Shallya by default, or Giessingen's own healer if that's the map the
## party was actually on), where a dead character can be Revived for a
## price and everyone else just pays for ordinary healing like any other
## visit.

static func run_test(fe) -> bool:
	var checks: Array = []

	## Drain any background coroutine from FieldEncounterScreen's own
	## auto-started _ready() encounter before this test's own setup
	## begins -- same reasoning as several other fe-mode tests already
	## use (see e.g. frightening_luck_test.gd's own comment).
	for i in range(120):
		if fe.awaiting_continue:
			fe.awaiting_continue = false
		if fe.awaiting_fortune_choice:
			fe._pending_choice_str = ""
			fe.awaiting_fortune_choice = false
		await fe.get_tree().process_frame

	## --- Phase 1: a lone death (party survives) never crashes, and
	## leaves the character marked dead in place rather than teleported
	## or removed. -----------------------------------------------------
	GameState.ensure_player_character()
	var human = GameData.find_race("Human")
	var soldier = GameData.find_career("Soldier")
	var dying := GameState.player_character
	dying.race = human
	dying.career = soldier
	dying.character_name = "Doomed Davrin"
	dying.fate_points = 0
	dying.wounds_max = 10
	dying.wounds_current = 1

	## Added to GameState.party BEFORE _start_encounter() runs, so the
	## real per-member loop there (encounter.add_combatant() + weapons
	## resolution) picks them up the normal way and roll_initiative()
	## actually seats them in turn_order -- add_combatant() alone (as
	## opposed to add_combatant_mid_round(), the exploration-only
	## mid-fight-arrival path) never touches turn_order by itself, so a
	## combatant added straight to a live `encounter` after the fight's
	## already started would never show up in get_living() at all.
	var survivor := Character.new()
	survivor.character_name = "Eric T"
	survivor.race = human
	survivor.characteristics = dying.characteristics.duplicate()
	survivor.allegiance = "ally"
	survivor.wounds_max = 10
	survivor.wounds_current = 10
	survivor.equipped_weapon = "Sword"
	GameState.add_party_member(survivor)

	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_habitat = ""
	fe._start_encounter()
	for i in range(3):
		await fe.get_tree().process_frame

	fe.player = dying
	checks.append(["setup: field_encounter_screen node is genuinely in the tree before the fatal moment", fe.is_inside_tree()])
	checks.append(["setup: the survivor is genuinely in turn_order (get_living includes them before anything happens)", fe.encounter.get_living("ally").has(survivor)])

	## Same "fire the async function, then poll/drive its own suspended
	## choice loop from the outside" pattern this project's other tests
	## already use for similar Y/N-style prompts (see e.g.
	## wall_edge_ui_move_test.gd's own comment on firing a real signal
	## and awaiting frames afterward, rather than awaiting the handler's
	## own return value directly) -- _handle_fatal_moment() is itself
	## `await`-driven internally (`while awaiting_fatal_moment_choice:
	## await get_tree().process_frame`), so calling it without awaiting
	## it here lets it run in the background while this test drives its
	## own prompt loop, exactly mirroring how a real player's click
	## would resolve it.
	fe._handle_fatal_moment({}, "", "test: a real fatal moment")
	var settle := 0
	while not fe.awaiting_fatal_moment_choice and settle < 60:
		await fe.get_tree().process_frame
		settle += 1
	checks.append(["setup: the fatal-moment prompt genuinely opened (no Fate left, so only the '...' option shows)", fe.awaiting_fatal_moment_choice])
	## Simulate clicking "..." (Accept your fate) -- the only option
	## offered when fate_points == 0 (see _handle_fatal_moment's own
	## else-branch button wiring).
	fe._pending_choice_str = ""
	fe.awaiting_fatal_moment_choice = false
	var settle2 := 0
	while fe._pending_choice_str == "" and not fe.player.is_dead and settle2 < 60:
		await fe.get_tree().process_frame
		settle2 += 1

	checks.append(["THE FIX: no crash -- the node is still genuinely in the tree right after the fatal moment resolves", fe.is_inside_tree()])
	checks.append(["THE FIX: the character is marked is_dead", dying.is_dead])
	checks.append(["THE FIX: the character is left at 0 Wounds, not removed from the party or teleported", dying.wounds_current == 0 and GameState.party.has(dying)])
	checks.append(["THE FIX: battle is NOT over just from one death -- the survivor is still around to keep fighting", not fe.battle_over])
	checks.append(["THE FIX: CombatEncounter already treats the dead character as defeated/skip-worthy (no bespoke turn-skip code needed)", fe.encounter.is_defeated(dying)])
	checks.append(["THE FIX: the dead character is excluded from get_living(\"ally\") but the survivor is not -- combat can continue", not fe.encounter.get_living("ally").has(dying) and fe.encounter.get_living("ally").has(survivor)])

	## The exact crash call chain: _resolve_player_defense() always
	## follows a fatal moment with `await _wait_for_continue()` --
	## reproducing that direct call is the most faithful regression
	## check that the actual reported crash line is fixed. Fired without
	## `await` (same background-coroutine pattern as _handle_fatal_moment
	## above) rather than awaited directly, since the survivor is still a
	## real living ally right now -- unlike the earlier accidental
	## early-return this test's own setup bug used to hit before it
	## added the survivor to turn_order properly, _wait_for_continue()
	## genuinely opens its own real "Continue" prompt here (both sides
	## still have someone standing), which needs driving exactly like
	## _handle_fatal_moment's own prompt did above, not a bare await.
	fe._wait_for_continue()
	var settle3 := 0
	while not fe.awaiting_continue and settle3 < 60:
		await fe.get_tree().process_frame
		settle3 += 1
	checks.append(["_wait_for_continue(): a real Continue prompt opened (both sides still have a living combatant)", fe.awaiting_continue])
	fe.awaiting_continue = false   ## simulate the real player pressing Continue
	var settle4 := 0
	while fe.awaiting_continue and settle4 < 60:
		await fe.get_tree().process_frame
		settle4 += 1
	checks.append(["THE FIX: _wait_for_continue() -- the exact call that crashed in the bug report -- now returns cleanly with no error", fe.is_inside_tree()])

	## --- Phase 2: a genuine party wipe routes to a healer instead of
	## the old free auto-heal-and-teleport-to-the-village mechanic. -----
	survivor.wounds_current = 0   ## the whole party is down now, dead or merely unconscious
	GameState.last_active_city_id = ""
	GameState.last_active_map_path = "res://data/maps/giessingen_village.tres"
	fe._end_battle(false)
	checks.append(["party wipe (Giessingen): _party_wiped is set", fe._party_wiped])
	checks.append(["party wipe (Giessingen): routes to Giessingen's own healer (empty city id), not Ubersreik, since the party was genuinely on Giessingen's own map", fe._party_wipe_healer_city_id == ""])
	checks.append(["party wipe: NOT auto-healed to full for free anymore -- the old revive mechanic this request asked to remove", dying.wounds_current == 0 and survivor.wounds_current == 0])

	## A second wipe, this time from inside a city/dungeon context (not
	## Giessingen's own map) -- should default to Ubersreik's Temple of
	## Shallya per the request's own explicit priority.
	fe._party_wiped = false
	fe._party_wipe_healer_city_id = ""
	GameState.last_active_city_id = "ubersreik"
	GameState.last_active_map_path = "res://data/maps/giessingen_village.tres"   ## deliberately still set, to prove city id wins
	fe._end_battle(false)
	checks.append(["party wipe (in a city/dungeon): routes to Ubersreik's Temple of Shallya, not Giessingen, since last_active_city_id is set", fe._party_wipe_healer_city_id == "ubersreik"])

	## A third wipe, on neither Giessingen's map nor inside any city
	## (e.g. Gotheim or any other local map) -- should still default to
	## Ubersreik, per the request's own "Temple of Shallya... (or the
	## healer in Giessingen if they are on the same map as him)" priority.
	fe._party_wiped = false
	fe._party_wipe_healer_city_id = ""
	GameState.last_active_city_id = ""
	GameState.last_active_map_path = "res://data/maps/some_other_village.tres"
	fe._end_battle(false)
	checks.append(["party wipe (a different local map entirely): still defaults to Ubersreik's Temple of Shallya", fe._party_wipe_healer_city_id == "ubersreik"])

	## --- Phase 3: _on_return_pressed() actually performs the hand-off
	## once the Battle Report closes -- checked via the real dispatch,
	## not by calling the destination logic directly, so the actual
	## wiring (not just _end_battle's own bookkeeping) is under test.
	## This is deliberately this test's own final fe-driven action --
	## change_scene_to_file() frees this very node the same way the
	## original bug's own change_scene_to_file() did (see
	## CityScreenTest's own "leave city confirmed" block comment on the
	## same project-wide caution), so nothing further reads `fe` state
	## after this. ------------------------------------------------------
	fe._hosted_by_exploration = true
	fe.dungeon_state = {"theme_id": "sewer"}
	GameState.dungeon_state = {"theme_id": "sewer"}
	GameState.pending_healer_city_id = ""
	fe._on_return_pressed()
	checks.append(["_on_return_pressed(): a party-wiped mid-dungeon fight abandons the in-progress dungeon (mirrors _do_exit_dungeon's own bookkeeping)", GameState.dungeon_state.is_empty()])
	checks.append(["_on_return_pressed(): hands off to the healer _end_battle(false) chose (\"ubersreik\", from the last wipe above)", GameState.pending_healer_city_id == "ubersreik"])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Party Wipe And Revive): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
