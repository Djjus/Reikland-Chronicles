extends RefCounted
class_name ChoicePromptKeyboardFocusTest
## Regression test for the user report "combat getting stuck sometimes on
## creature's turn" (screenshots: Turn Order highlighting a monster as
## current, an empty-looking bottom prompt panel, no visible way forward).
##
## ROOT CAUSE (confirmed by reading every button-menu builder in this file
## and grepping every call site of _auto_focus_default_button()): three
## player-facing choice prompts — _handle_critical_wound_on_player()'s own
## Accept/Deflect prompt, _handle_fatal_moment()'s own Fate Point offer, and
## _on_spend_resolve()'s own Spend Resolve menu — were the only button
## menus in this whole file that never called _auto_focus_default_button()
## after building their buttons. Every other menu here does (13 other call
## sites). Combined with two other already-deliberate facts about these
## exact three prompts (see awaiting_critical_wound_choice/awaiting_fatal_
## moment_choice/awaiting_resolve_choice's own declaration comments and
## _unhandled_input's KEY_ENTER branch): Enter is intentionally absorbed
## here (does nothing) to avoid an old crash, and KEY_SPACE's own branch in
## _unhandled_input only ever handles awaiting_incapacitated_turn/
## awaiting_continue. So with no button focused, NEITHER Enter NOR Space
## did anything at all when one of these three prompts was open — and per
## this project's own standing instruction ("Space button is the main way
## to accepting choice thought menu's in the game"), a player would press
## Space, see nothing happen, and reasonably conclude the game had frozen.
## A monster landing a Critical Wound on the player-controlled character
## (exactly the "creature's turn" framing of the report) is precisely when
## _handle_critical_wound_on_player() (and potentially _handle_fatal_
## moment(), if it kills the target) fires.
##
## THE FIX: all three now call _auto_focus_default_button() (via
## _active_primary_hotkey_button, same convention as every other prompt in
## this file), so a button is genuinely focused the instant the prompt
## appears — Space now works immediately, through Godot's own built-in
## ui_accept binding, with no code changes needed to _unhandled_input at
## all (Enter stays intentionally unbound from ui_accept — see
## _setup_wasd_navigation — so this cannot reopen the old Enter/
## awaiting_player_target crash these flags were split out to fix). Each
## prompt's default is deliberately the safe/no-resource-spent option
## (Accept the wound, Accept your fate, Cancel) rather than whichever
## button happened to be built first, so an accidental Space press can
## never burn a Fate Point, spend Resolve, or strip a Condition the player
## didn't mean to.
##
## Case 1: Critical Wound prompt defaults to Accept (not Deflect).
## Case 2: Fatal Moment prompt (with Fate Points available) defaults to
## Accept your fate (not either Fate-Point-spending option).
## Case 3: Fatal Moment prompt (no Fate Points left) defaults to its only
## button ("...").
## Case 4: Spend Resolve prompt defaults to Cancel (not the first real
## option offered).
## Each case also confirms the default button is genuinely focused
## (has_focus()) and carries the "[Space]" hint, matching this file's own
## "Continue [Space]" convention for every other Space-activatable prompt.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "FocusTester"
	pc.equipped_armour = ["Leather Jack"]
	pc.armour_damage.clear()

	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	Dice.rng.seed = 2
	seed(2)

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	await tree.process_frame
	await tree.process_frame

	var player: Character = fe.player
	fe.awaiting_player_target = false
	fe.selected_target = null

	## --- Case 1: Critical Wound prompt (deflectable) ---
	var cw_result := CombatResolver.AttackResult.new()
	cw_result.critical_wound_location = "Body"
	cw_result.critical_wound_causes_death = false
	cw_result.critical_wound_entry = {
		"name": "Test Gash",
		"flavor": "A testing wound, nothing more.",
		"wounds": "1",
		"conditions": {},
		"test_or_condition": {},
		"amputation": "",
	}
	fe._active_primary_hotkey_button = null
	fe._handle_critical_wound_on_player(cw_result)
	for i in range(3): await tree.process_frame

	checks.append(["Case 1 setup: the Critical Wound prompt is genuinely open", fe.awaiting_critical_wound_choice])
	var accept_btn: Button = _find_button_containing(fe.target_container, "Accept the wound")
	checks.append(["Case 1 setup: a real Accept button exists", accept_btn != null])
	if accept_btn != null:
		checks.append(["THE FIX: Accept is the real Space/WASD-focus default, not Deflect or anything else", fe._active_primary_hotkey_button == accept_btn])
		checks.append(["THE FIX: Accept is genuinely focused right now (Space would activate it immediately)", accept_btn.has_focus()])
		checks.append(["THE FIX: Accept carries the [Space] hint, matching this file's own convention", accept_btn.text.find("[Space]") != -1])

	## Close the prompt cleanly (click Accept) before moving on.
	if accept_btn != null:
		accept_btn.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["Case 1 cleanup: the prompt closed normally", not fe.awaiting_critical_wound_choice])

	## --- Case 2: Fatal Moment prompt, Fate Points available ---
	player.fate_points = 2
	fe._active_primary_hotkey_button = null
	fe._handle_fatal_moment({}, "", "test: a real fatal moment")
	for i in range(3): await tree.process_frame

	checks.append(["Case 2 setup: the Fatal Moment prompt is genuinely open", fe.awaiting_fatal_moment_choice])
	var fatal_accept_btn: Button = _find_button_containing(fe.target_container, "Accept your fate")
	checks.append(["Case 2 setup: a real 'Accept your fate' button exists", fatal_accept_btn != null])
	var die_another_day_btn: Button = _find_button_containing(fe.target_container, "Die Another Day")
	checks.append(["Case 2 setup: a real 'Die Another Day' button also exists (real choice, not the only option)", die_another_day_btn != null])
	if fatal_accept_btn != null:
		checks.append(["THE FIX: 'Accept your fate' is the real Space/WASD-focus default, NOT a Fate-Point-spending option", fe._active_primary_hotkey_button == fatal_accept_btn])
		checks.append(["THE FIX: 'Accept your fate' is genuinely focused right now", fatal_accept_btn.has_focus()])
		checks.append(["THE FIX: 'Accept your fate' carries the [Space] hint", fatal_accept_btn.text.find("[Space]") != -1])
		checks.append(["safety check: an accidental Space press could not have spent a Fate Point (Die Another Day is NOT the default)", fe._active_primary_hotkey_button != die_another_day_btn])
		fatal_accept_btn.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["Case 2 cleanup: the prompt closed normally", not fe.awaiting_fatal_moment_choice])
	checks.append(["Case 2 cleanup: no Fate Point was actually spent (Accept your fate was chosen)", player.fate_points == 2])

	## --- Case 3: Fatal Moment prompt, no Fate Points left ---
	player.fate_points = 0
	fe._active_primary_hotkey_button = null
	fe._handle_fatal_moment({}, "", "test: a fatal moment with no Fate left")
	for i in range(3): await tree.process_frame

	checks.append(["Case 3 setup: the Fatal Moment prompt is genuinely open", fe.awaiting_fatal_moment_choice])
	var continue_btn: Button = _find_button_containing(fe.target_container, "...")
	checks.append(["Case 3 setup: a real fallback continue button exists", continue_btn != null])
	if continue_btn != null:
		checks.append(["THE FIX: the only available button is the real Space/WASD-focus default", fe._active_primary_hotkey_button == continue_btn])
		checks.append(["THE FIX: it is genuinely focused right now", continue_btn.has_focus()])
		continue_btn.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["Case 3 cleanup: the prompt closed normally", not fe.awaiting_fatal_moment_choice])

	## --- Case 4: Spend Resolve prompt ---
	player.resolve = 2
	player.critical_wound_penalties = [{"characteristic": "toughness", "amount": -10}]
	player.conditions = {"Prone": 1}
	fe.awaiting_player_target = true
	fe.action_used_this_turn = false
	fe._active_primary_hotkey_button = null
	fe._on_spend_resolve()
	for i in range(3): await tree.process_frame

	checks.append(["Case 4 setup: the Spend Resolve prompt is genuinely open", fe.awaiting_resolve_choice])
	var cancel_btn: Button = _find_button_containing(fe.target_container, "Cancel")
	checks.append(["Case 4 setup: a real Cancel button exists", cancel_btn != null])
	var ignore_crit_btn: Button = _find_button_containing(fe.target_container, "Ignore all Critical Wound")
	checks.append(["Case 4 setup: a real, spendable option also exists (Cancel isn't the only choice)", ignore_crit_btn != null])
	if cancel_btn != null:
		checks.append(["THE FIX: Cancel is the real Space/WASD-focus default, not whichever real option was built first", fe._active_primary_hotkey_button == cancel_btn])
		checks.append(["THE FIX: Cancel is genuinely focused right now", cancel_btn.has_focus()])
		checks.append(["THE FIX: Cancel carries the [Space] hint", cancel_btn.text.find("[Space]") != -1])
		checks.append(["safety check: an accidental Space press could not have spent Resolve (the real option is NOT the default)", fe._active_primary_hotkey_button != ignore_crit_btn])
		cancel_btn.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["Case 4 cleanup: the prompt closed normally", not fe.awaiting_resolve_choice])
	checks.append(["Case 4 cleanup: no Resolve was actually spent (Cancel was chosen)", player.resolve == 2])

	fe.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Choice Prompt Keyboard Focus): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search for a Button whose text CONTAINS `substr` anywhere
## under `root` — mirrors end_turn_wasd_focus_no_target_test.gd's own
## helper of the same shape (the real menu nests several plain Container
## layers deep).
static func _find_button_containing(root: Node, substr: String) -> Button:
	for child in root.get_children():
		if child is Button and String(child.text).find(substr) != -1:
			return child
		if child.get_child_count() > 0:
			var found: Button = _find_button_containing(child, substr)
			if found != null:
				return found
	return null
