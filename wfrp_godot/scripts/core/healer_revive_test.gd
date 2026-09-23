extends RefCounted
class_name HealerReviveTest
## Regression/functional test for the Healer screen's own half of the
## party-wipe/permadeath rework ("If the entire party dies move them...
## to the Temple of Shallya... where they should be able to heal to
## revive. And give healers the ability to get Fate points while
## holding the secret cheat button"): a genuinely dead character
## (Character.is_dead) gets a real Revive action instead of the normal
## Wounds/Conditions/Critical Wound rows (which don't make sense for a
## corpse), priced well above any of those; a live Fate-grant testing
## button exists and works, gated the same held-Shift+Ctrl way this
## project's other cheat buttons already are (character_menu_screen.gd's
## own _xp_cheat_button, advancement_screen.gd's own _test_mode_active())
## -- input simulation for a genuinely-held key isn't practical in a
## headless test, so this checks the handler function itself rather than
## the live key-polling _process() visibility toggle, same scope every
## other test in this project stops at for that established pattern.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var dead_char: Character = GameState.player_character
	dead_char.character_name = "Doomed Davrin"
	dead_char.is_dead = true
	dead_char.wounds_current = 0
	dead_char.wounds_max = 10
	dead_char.gold_crowns = 0
	dead_char.silver_shillings = 0
	dead_char.brass_pennies = 0

	var hs = load("res://scenes/Healer.tscn").instantiate()
	tree.get_root().add_child(hs)
	for i in range(3):
		await tree.process_frame

	checks.append(["setup: the healer screen loaded the real dead character", hs.character == dead_char])
	checks.append(["dead character: the Revive row is shown instead of the normal Wounds row", hs.revive_row.visible and not hs.wounds_row.visible])
	checks.append(["dead character: Revive is disabled when the purse can't afford it (0 coin)", hs.revive_button.disabled])

	## Can't afford it -- a real click should be a safe no-op, no state
	## change, same "can't afford" convention every other transaction on
	## this screen already uses.
	hs._on_revive()
	checks.append(["can't-afford revive: still dead, still 0 Wounds -- the attempt was refused, not silently free", dead_char.is_dead and dead_char.wounds_current == 0])

	## Now hand them enough coin for the real price (12 Shillings = 144d
	## = 12 GC's worth, using Brass Pennies directly for a simple exact
	## check against REVIVE_PRICE_PENNIES).
	dead_char.brass_pennies = hs.REVIVE_PRICE_PENNIES
	hs._rebuild_all()
	checks.append(["affordable revive: Revive is now enabled", not hs.revive_button.disabled])
	var pennies_before: int = dead_char.get_total_pennies()
	hs._on_revive()
	checks.append(["THE FIX: revive actually clears is_dead", not dead_char.is_dead])
	checks.append(["THE FIX: revive brings them back at exactly 1 Wound (same floor Fate's own Die Another Day/How Did That Miss? use), not a full heal", dead_char.wounds_current == 1])
	checks.append(["revive: the real price was actually charged", pennies_before - dead_char.get_total_pennies() == hs.REVIVE_PRICE_PENNIES])
	checks.append(["revive: the normal Wounds row reappears now that they're alive again, Revive row hides", hs.wounds_row.visible and not hs.revive_row.visible])

	## Fate cheat: grants a Fate Point to whoever's currently being
	## treated, free, regardless of purse or alive/dead state.
	var fate_before: int = dead_char.fate_points
	hs._on_fate_cheat()
	checks.append(["fate cheat: grants exactly 1 Fate Point to the character currently being treated", dead_char.fate_points == fate_before + 1])

	## Also works on a still-dead character (e.g. testing a revive scenario
	## before actually paying for it) -- independent of revive_row's own
	## visibility, per that button's own doc comment.
	dead_char.is_dead = true
	var fate_before2: int = dead_char.fate_points
	hs._on_fate_cheat()
	checks.append(["fate cheat: also works on a dead character (purely a testing aid, not gated on being alive)", dead_char.fate_points == fate_before2 + 1])

	hs.queue_free()
	await tree.process_frame

	## Sanity check on a perfectly ordinary, alive, undamaged character:
	## the Revive row must never show for someone who was never dead.
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var alive_char: Character = GameState.player_character
	alive_char.is_dead = false
	var hs2 = load("res://scenes/Healer.tscn").instantiate()
	tree.get_root().add_child(hs2)
	for i in range(3):
		await tree.process_frame
	checks.append(["alive character: Revive row never shows, normal Wounds row does", not hs2.revive_row.visible and hs2.wounds_row.visible])
	hs2.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Healer Revive): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
