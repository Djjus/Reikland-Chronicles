extends RefCounted
class_name MonsterTurnStallWatchdogTest
## Regression/safety-net test for the request ("combat flow stopped and
## i cant do anything") — two screenshots (Round 2, several turns
## already resolved in the Combat Log, Turn Order panel confirming it
## was a monster's own turn) showed a live battle completely wedged:
## no further log entry, no defense prompt, no Continue/Fortune choice,
## the bottom action panel empty, nothing clickable doing anything.
##
## Reading the actual render order of the Combat Log (see
## _rebuild_history_display()'s own comment — it renders oldest-first/
## newest-last and auto-scrolls to the bottom, even though its header
## label still says "(newest first)") confirms the screenshots really
## were showing the true latest state: the previous ally's turn had
## just finished, _next_turn() had handed off to the next combatant (an
## already-badly-hurt Highway Bandit), and then nothing else ever
## happened — no notice, no card, no prompt, forever.
##
## GDScript has no try/catch, and an exported build gives the player no
## visible console — so if _do_monster_turn()/_monster_attack() (or
## anything they call) ever hits some not-yet-understood edge case that
## halts the coroutine partway through, the whole encounter is wedged
## permanently with zero explanation, and the only way out is
## abandoning the run. Rather than only chase the one specific trigger
## (which a screenshot alone can't conclusively prove), this adds a
## genuine safety net: _start_monster_turn_watchdog() fires once per
## monster turn dispatch (see _next_turn()'s own call to it right next
## to _do_monster_turn(current)) and, if this exact combatant's own turn
## still hasn't moved on after a generous grace period AND none of the
## real "waiting on the player" flags this file already uses
## (pending_defense, awaiting_continue/awaiting_fortune_choice,
## awaiting_player_target, awaiting_deathblow_choice) are set, force-
## ends the stalled turn itself so the player is never left with a dead
## game again, regardless of what exactly stalled it.
##
## Case 1: nothing legitimate is waiting on the player and the turn
## genuinely never advances -- the watchdog force-advances it and logs
## what happened.
## Case 2: a REAL prompt (pending_defense) is up -- the watchdog must
## leave a genuine defense choice completely alone no matter how long it
## takes the player to answer it.
## Case 3: a stale/superseded watchdog (a newer turn already dispatched
## before this one's grace period elapsed) must do nothing once it
## finally fires late -- it must never reach back and yank a turn that
## has long since moved on to someone else.
##
## Uses `fe` (a live FieldEncounter.tscn instance the caller owns),
## matching this project's own `run_test(fe)` convention. Sets
## _monster_turn_watchdog_grace_seconds to a tiny real value (a genuine
## var, not a const, specifically so tests don't have to sit through the
## real 15-second production grace period) rather than driving a real
## stalled monster turn, which this project has no reliable way to force
## on demand.

static func run_test(fe) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.current_field_difficulty_tier = 0
	var no_pool: Array[String] = []
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.pending_encounter_monster_names = ["Giant Rat"]
	## Awaited, not fire-and-forget (unlike this project's other tests
	## that call _start_encounter() this way) — this test does its own
	## open-ended real-time waiting right after, and _start_encounter()
	## is itself a coroutine that ends by dispatching Turn 1 via
	## _next_turn(). A few settle frames alone don't guarantee that
	## whole chain has genuinely finished by the time this test starts
	## manipulating turn order — a still-in-flight tail end racing with
	## this test's own manipulation was the real source of this test's
	## own flakiness before this await was added, not anything wrong
	## with the fix itself.
	await fe._start_encounter()
	for i in range(5):
		await fe.get_tree().process_frame

	var setup_ok: bool = fe.monsters.size() >= 1 and fe.encounter != null
	checks.append(["setup: a real encounter with at least one monster", setup_ok])
	if not setup_ok:
		print("RESULT (Monster Turn Stall Watchdog): SETUP FAILED")
		return false

	var monster: Character = fe.monsters[0]

	## _start_encounter() already rolled initiative and kicked off Round
	## 1's own real Turn 1 dispatch on its own — if the monster happened
	## to win initiative, a genuine _do_monster_turn() (and, per the real
	## fix, its own real watchdog) is already running autonomously in the
	## background right now, fully independent of anything this test
	## does below.
	##
	## Root cause of this test's own long-standing flakiness (found by
	## tracing a reproduced failure down to _wait_for_continue(), which
	## waits via `while awaiting_continue: await get_tree().process_frame`
	## rather than a signal): that natural turn's own coroutine can be
	## suspended INSIDE that poll loop, patiently waiting for
	## awaiting_continue to go false. A plain "wait until nothing looks
	## like it's changing" drain can't see that — the flag sits there
	## true, unchanging, looking perfectly "stable" — so the old drain
	## above would happily declare quiet and move on with that coroutine
	## still alive. Then Case 1 itself would set awaiting_continue = false
	## (to simulate "nothing is waiting on the player"), which is exactly
	## what that poll loop was watching for — waking the real, unrelated
	## coroutine back up mid-test. It would then run on to its own
	## _next_turn(), moving the turn off the monster for real reasons that
	## had nothing to do with the watchdog, while the watchdog's own timer
	## (seeing the turn had already moved on) correctly no-opped instead
	## of logging a stall notice — exactly the "turn moved, but no stall
	## notice" failure pattern this test kept hitting.
	##
	## So this doesn't just wait for quiet — it actively resolves any real
	## prompt it finds still open, the same way a real player eventually
	## would, so that natural coroutine actually runs to completion (and
	## fully unwinds) instead of being left dangling mid-await for this
	## test to accidentally disturb later. Only once nothing is open AND
	## nothing has changed for several consecutive checks is it safe to
	## start forcing turns and clearing flags in the cases below.
	var quiet_current: Character = null
	var quiet_history_size: int = -1
	var stable_checks := 0
	var drain_safety := 0
	while stable_checks < 3 and drain_safety < 150:
		drain_safety += 1
		if fe.battle_over:
			break   ## nothing left to settle -- the natural dispatch already decided the fight
		if fe.awaiting_continue or fe.awaiting_fortune_choice:
			## The overwhelmingly common real prompt (per _wait_for_continue's
			## own comments, "most calls are just a narrative beat") --
			## resolve it exactly like the plain "Continue [Space]" button
			## does, so the real suspended coroutine actually proceeds.
			fe.awaiting_continue = false
			fe.awaiting_fortune_choice = false
			stable_checks = 0
		elif not fe.pending_defense.is_empty():
			## A real _prompt_player_defense() is up (the natural first
			## turn was the monster's, attacking the ally in melee) --
			## resolve it with a safe, always-available default (Dodge)
			## via the same function the real button calls, rather than
			## just clearing the flags out from under it.
			var dodge_skill: SkillDefinition = GameData.skill_db.find_by_name("Dodge")
			fe._resolve_player_defense(dodge_skill, "Dodge")
			stable_checks = 0
		elif fe.awaiting_deathblow_choice:
			## No generic safe resolution known for this one; defensively
			## clear it so a coroutine relying on it isn't left stranded
			## forever waiting for input this test never supplies.
			fe.awaiting_deathblow_choice = false
			stable_checks = 0
		await fe.get_tree().create_timer(0.2).timeout
		var now_current: Character = fe.encounter.get_current_combatant()
		var now_size: int = fe.history.size()
		var anything_open: bool = fe.awaiting_continue or fe.awaiting_fortune_choice \
			or not fe.pending_defense.is_empty() or fe.awaiting_deathblow_choice or fe.awaiting_player_target
		if now_current == quiet_current and now_size == quiet_history_size and not anything_open:
			stable_checks += 1
		else:
			stable_checks = 0
			quiet_current = now_current
			quiet_history_size = now_size
	fe._monster_turn_watchdog_token += 1

	## Force it to be this monster's own turn right now, regardless of
	## whatever the real turn order/dispatch already did on its own —
	## this test only cares about the watchdog's own logic once a
	## monster's turn is current, not about genuinely reproducing
	## whatever real gameplay path stalls it (this project has no
	## reliable way to force that on demand).
	var safety := 0
	while fe.encounter.get_current_combatant() != monster and safety < 20:
		fe.encounter.advance_turn()
		safety += 1
	checks.append(["setup: the monster is genuinely the current combatant", fe.encounter.get_current_combatant() == monster])

	## --- Case 1: nothing is legitimately waiting on the player, and the
	## turn genuinely never advances -- the watchdog should force it.
	fe.pending_defense.clear()
	fe.awaiting_continue = false
	fe.awaiting_fortune_choice = false
	fe.awaiting_player_target = false
	fe.awaiting_deathblow_choice = false
	fe._monster_turn_watchdog_grace_seconds = 0.5
	var notices_before: int = fe.history.size()
	fe._start_monster_turn_watchdog(monster)   ## fire-and-forget, exactly like the real call site
	await fe.get_tree().create_timer(4.0).timeout
	checks.append(["Case 1: a stalled monster turn with no real prompt up gets force-advanced off this monster", fe.encounter.get_current_combatant() != monster])
	checks.append(["Case 1: a notice was logged explaining what happened", fe.history.size() > notices_before])
	## Case 1's forced _next_turn() dispatches a REAL ally turn
	## (_prompt_player_turn(), the genuine production path), which can
	## itself have its own brief "thinking beat" pauses in flight — that
	## needs to fully settle before Case 2 takes its own "notices_before"
	## snapshot, or a leftover notice from THAT (not from anything this
	## test is actually exercising) can land inside Case 2's own
	## observation window and produce a false failure.
	await fe.get_tree().create_timer(1.0).timeout

	## --- Case 2: a REAL prompt (pending_defense) is up -- the watchdog
	## must never yank the turn out from under a legitimate defense
	## choice just because time passed.
	safety = 0
	while fe.encounter.get_current_combatant() != monster and safety < 20:
		fe.encounter.advance_turn()
		safety += 1
	fe.pending_defense = {"attacker": monster, "weapon": fe.weapons.get(monster), "attacker_effort": 0}
	fe._monster_turn_watchdog_grace_seconds = 0.5
	var notices_before2: int = fe.history.size()
	fe._start_monster_turn_watchdog(monster)
	await fe.get_tree().create_timer(4.0).timeout
	checks.append(["Case 2: a genuine pending_defense prompt is left completely alone -- turn NOT forced", fe.encounter.get_current_combatant() == monster])
	checks.append(["Case 2: no stall notice logged while a real prompt is up", fe.history.size() == notices_before2])
	fe.pending_defense.clear()

	## --- Case 3: a stale watchdog (a newer turn already dispatched
	## since this one started) must no-op rather than firing late.
	safety = 0
	while fe.encounter.get_current_combatant() != monster and safety < 20:
		fe.encounter.advance_turn()
		safety += 1
	fe.awaiting_continue = false
	fe.awaiting_fortune_choice = false
	fe.awaiting_player_target = false
	fe.awaiting_deathblow_choice = false
	fe._monster_turn_watchdog_grace_seconds = 0.5
	fe._start_monster_turn_watchdog(monster)   ## started...
	fe._monster_turn_watchdog_token += 1   ## ...then immediately superseded by a "newer" turn dispatch
	var notices_before3: int = fe.history.size()
	await fe.get_tree().create_timer(4.0).timeout   ## let the stale watchdog's own timer fire anyway, generous margin over the grace period above
	checks.append(["Case 3: a superseded watchdog does nothing once it finally fires late", fe.history.size() == notices_before3 and fe.encounter.get_current_combatant() == monster])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Monster Turn Stall Watchdog): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
