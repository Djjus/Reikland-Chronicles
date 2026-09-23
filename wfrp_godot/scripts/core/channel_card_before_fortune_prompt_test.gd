extends RefCounted
class_name ChannelCardBeforeFortunePromptTest
## Real bug fix, per the live report ("I click channel, but it didnt
## actually do it" -> "it completed after ending the turn" -> "no it
## should of shown the roll card, but didnt"): _on_channel() used to
## build its whole "Fumble/Critical/accumulated SL" message and only
## ever call _show_single_card() at the very END of the function, AFTER
## the Spend Fortune/Dark Deal loop had already fully resolved. Every
## other Test in this file (see _apply_sprint_outcome, or _on_cast_
## spell's own _apply_cast_spell_outcome call) shows/merges its roll
## card BEFORE offering Fortune -- _offer_fortune_spend()'s own comment
## explicitly assumes the card it's attaching a prompt to already
## exists ("render as a button row in the combat log, right after the
## roll card(s) they apply to"). The fix: a new _show_channel_card()
## helper, called once before the Fortune loop and again (merged) after
## every reroll, exactly like Sprint's own shape.
##
## Covers: the Channel roll card is genuinely visible in `history`
## (added by _show_channel_card) the instant the Fortune/Dark Deal
## prompt opens -- not just after it's declined/resolved -- and that
## the eventual decline still lets the turn complete normally.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	## Guarantees "Spend Fortune: +1 SL" is always offered by
	## _offer_fortune_spend regardless of whether the Channel roll
	## itself happens to succeed or fail (that option's own gate is just
	## `player.fortune_points > 0 and fight_still_active`, independent
	## of test.success) -- removes any need to control real dice rolls
	## to guarantee a genuine Fortune prompt opens.
	pc.fortune_points = 2

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	fe.player = pc
	var player: Character = pc
	fe.awaiting_player_target = true
	fe.action_used_this_turn = false

	var history_size_before: int = fe.history.size()

	## Fire-and-forget, per this project's own established coroutine
	## pattern (see _next_turn()'s own dispatch of _do_monster_turn()):
	## _on_channel() contains awaits, so calling it WITHOUT await runs it
	## synchronously up to its first suspend point -- which, with the
	## fix in place, is now INSIDE _offer_fortune_spend()'s own
	## `while awaiting_fortune_choice: await get_tree().process_frame`
	## loop, meaning _show_channel_card() (and therefore the new history
	## entry) has already run by the time this line returns.
	fe._on_channel("Fire")

	checks.append(["setup: awaiting_player_target was consumed (the Action really started)", not fe.awaiting_player_target])
	checks.append(["setup: a genuine Fortune prompt is open (blocked inside _offer_fortune_spend)", fe.awaiting_fortune_choice])
	checks.append(["THE FIX: the Channel roll card was added to history BEFORE the Fortune prompt resolves, not after", fe.history.size() == history_size_before + 1])

	if fe.history.size() > history_size_before:
		var top_entry: Dictionary = fe.history[0]
		var found_channel_card := false
		for seg in top_entry.get("segments", []):
			if seg.get("kind", "") == "cards":
				for card in seg.get("cards", []):
					if String(card.get("title", "")).begins_with("Channel"):
						found_channel_card = true
		checks.append(["THE FIX: the new history entry genuinely contains a 'Channel (...)' card, not some other unrelated entry", found_channel_card])

	## Decline the Fortune prompt (same outcome as Enter, or clicking
	## Move/End Turn while it's open — see _decline_fortune_prompt's own
	## comment) and let the rest of _on_channel's flow (the continue
	## wait, _finish_player_action) run to completion, confirming this
	## fix didn't leave the turn stuck.
	fe._decline_fortune_prompt()
	for i in range(3):
		await tree.process_frame
	## _wait_for_continue_after_own_action() still needs an explicit
	## continue once battle_over is false and something is genuinely
	## awaiting_continue -- decline that too, the same "anything but a
	## real Fortune spend just moves on" pattern _decline_fortune_prompt
	## itself documents.
	if fe.awaiting_continue:
		fe._decline_fortune_prompt()
		for i in range(3):
			await tree.process_frame
	checks.append(["cleanup: the turn actually finished (no Fortune/Continue prompt left stuck)", not fe.awaiting_fortune_choice and not fe.awaiting_continue])

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
	print("RESULT (Channel card shown before Fortune prompt): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
