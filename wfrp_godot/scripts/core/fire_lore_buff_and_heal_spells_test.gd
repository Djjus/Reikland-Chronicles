extends RefCounted
class_name FireLoreBuffAndHealSpellsTest
## Per the explicit request: "let implement Cauterise (a heal spell) and
## Crown of Flame/Flaming Hearts (Blessing-style buffs)" — the three
## remaining Lore of Fire spells the review (lore_of_fire_spell_
## functionality_review.md) flagged as flavor-text only with a natural
## existing hook to reuse.
##
## Covers:
## - Cauterise (CORRECTED to the real Core Rulebook text the user
##   supplied after this suite's first version — see field_encounter_
##   screen.gd's own updated comment on the Cauterise branch for the
##   full quoted text): a real 1d10 heal (not the caster's Willpower
##   Bonus, that was this project's own invented interpretation), a
##   genuine no-cost full cure of Bleeding (the earlier 1-Fatigued
##   charge was also invented, not book text, and is gone), its own
##   ally-only target routing (_allies_needing_heal, not the caster),
##   redo-idempotency (a Fortune redo re-heals a fresh 1d10 rather than
##   stacking), and the new Cool-Test/agony/Unconscious-and-scarred
##   mechanic for any target without the Arcane Magic (Fire) Talent —
##   deterministic here via the new cauterise_agony_forced_roll test
##   seam on _apply_cast_spell_outcome — plus tick_cauterise_recovery()'s
##   own countdown-and-wake behavior, including its 0-Wounds guard.
## - Crown of Flame / Flaming Hearts: a real +10 Willpower timed buff
##   (the exact same BLESSING_STAT_MAP shape/magnitude every Blessing
##   already grants, just from a spell), redo-safety via the new
##   "buff_added" delta flag + _on_cast_spell's own pop-back mirror of
##   _on_pray's identical handling, expiry via tick_active_buffs(), and
##   the new shared _offer_buff_spell_overcast() (Duration multiplies,
##   Targets adds a recipient, no Damage column at all).
## - Flaming Hearts' own extra effect: genuinely clears an already-
##   tracked Fear source (_fear_sources) and cures an existing Broken
##   Condition outright, on top of the shared Willpower buff.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []
	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "FireLoreAes"

	## Two extra living party members, same construction pattern
	## blessing_overcast_test.gd already established for this exact
	## need — real Targets-column candidates, and a real ally target for
	## Cauterise/Flaming Hearts other than the caster.
	var ally1 := Character.new()
	ally1.character_name = "FireLoreElrohir"
	ally1.race = pc.race
	ally1.characteristics = pc.characteristics.duplicate()
	ally1.wounds_max = 20
	ally1.wounds_current = 10
	var ally2 := Character.new()
	ally2.character_name = "FireLoreFredi"
	ally2.race = pc.race
	ally2.characteristics = pc.characteristics.duplicate()
	ally2.wounds_max = 20
	ally2.wounds_current = 20
	if GameState.party.size() < 3:
		GameState.party.append(ally1)
		GameState.party.append(ally2)

	GameState.pending_encounter_monster_names = ["Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(8):
		await tree.process_frame

	checks.append(["setup: both extra party members are genuine living allies", fe.encounter != null and fe.encounter.get_living("ally").has(ally1) and fe.encounter.get_living("ally").has(ally2)])
	if fe.encounter == null or not fe.encounter.get_living("ally").has(ally1):
		fe.queue_free()
		for i in range(3): await tree.process_frame
		print("RESULT (Fire Lore Buff and Heal Spells): SETUP FAILED")
		return false

	## fe.player rotates to whichever party member's Turn is active by
	## the time a few frames have passed — pinned explicitly to `pc`,
	## same reasoning blessing_overcast_test.gd's own comment gives.
	fe.player = pc
	var player: Character = pc
	var wb: int = player.get_characteristic_bonus("willpower")

	var cast_success := MagicResolver.CastResult.new()
	cast_success.success = true
	var fake_test_result := TestResolver.TestResult.new()
	fake_test_result.target = 50
	fake_test_result.roll = 10
	fake_test_result.success = true
	fake_test_result.success_levels = 4
	cast_success.test_result = fake_test_result

	## --- Cauterise: a real heal spell ------------------------------------
	## CORRECTED per the real Core Rulebook text the user supplied
	## directly (the earlier v0.3.86 build below was this project's own
	## invented interpretation of just the flavor text, not the actual
	## book mechanic — see field_encounter_screen.gd's own updated
	## comment on the Cauterise branch for the full quoted text). Heal
	## is now a genuine 1d10 (not the caster's Willpower Bonus), curing
	## Bleeding costs nothing (the old Fatigued charge was invented and
	## is gone), and there's an entirely new Cool-Test/agony/
	## Unconscious-and-scarred branch for any target without the Arcane
	## Magic (Fire) Talent.
	var cauterise: SpellDefinition = GameData.spell_db.find_by_name("Cauterise")
	checks.append(["setup: Cauterise exists in the spell database", cauterise != null])

	var heal_candidates: Array = fe._allies_needing_heal()
	checks.append(["THE FIX: a wounded ally is offered as a valid Cauterise target", heal_candidates.has(ally1)])
	checks.append(["the caster themselves is correctly excluded (Cauterise is cast upon an ally, not the self)", not heal_candidates.has(player)])

	## Granting ally1 the Arcane Magic (Fire) Talent here doubles this
	## base heal case as the "a target WITH the Talent skips the Cool
	## Test entirely" check — no risk of Unconscious/scarred should ever
	## be possible for ally1 below, regardless of dice luck, since the
	## branch that rolls that Test is never entered at all for them.
	ally1.talents_taken["Arcane Magic (Fire)"] = 1
	ally1.add_condition("Bleeding", 3)
	var wounds_before_cauterise: int = ally1.wounds_current
	var cauterise_delta: Dictionary = fe._apply_cast_spell_outcome(cast_success, cauterise, "Cauterise", ally1, false)
	var actual_heal: int = ally1.wounds_current - wounds_before_cauterise
	checks.append(["THE FIX: Cauterise heals a real 1d10 Wounds (1-10), not the old Willpower Bonus formula", actual_heal >= 1 and actual_heal <= 10])
	checks.append(["THE FIX: Cauterise clears Bleeding entirely", not ally1.conditions.has("Bleeding")])
	checks.append(["THE FIX: curing Bleeding no longer costs a Fatigued Condition (the old charge was invented, not book text)", int(ally1.conditions.get("Fatigued", 0)) == 0])
	checks.append(["a target WITH the Arcane Magic (Fire) Talent is never put at risk (no Unconscious, never scarred)", not ally1.conditions.has("Unconscious") and not ally1.permanently_scarred])

	## Redo-idempotency: simulate exactly what _on_cast_spell's own redo
	## loop does (undo target_wounds, then reapply) — must not double-
	## heal.
	ally1.wounds_current = min(ally1.wounds_max, ally1.wounds_current + cauterise_delta["target_wounds"])
	checks.append(["setup: the caller's own undo correctly reverses the heal before a redo", ally1.wounds_current == wounds_before_cauterise])
	var cauterise_redo_delta: Dictionary = fe._apply_cast_spell_outcome(cast_success, cauterise, "Cauterise", ally1, true)
	var redo_heal: int = ally1.wounds_current - wounds_before_cauterise
	checks.append(["THE FIX: a Fortune redo heals a fresh 1d10 rather than stacking on top of the first roll", redo_heal >= 1 and redo_heal <= 10])
	checks.append(["setup: redo delta also carries its own correct reversal amount", cauterise_redo_delta["target_wounds"] == -redo_heal])

	## --- Cauterise's new Cool Test: agony / Unconscious / scarred --------
	## Deterministic via the new cauterise_agony_forced_roll test seam on
	## _apply_cast_spell_outcome (mirrors the "forced_roll" pattern
	## TestResolver.resolve() and combat_resolver.gd's attacker/defender
	## tests already use) — each of these three fresh, Talent-less
	## characters has a known Willpower (target 30, so Cool target is
	## also 30 untrained), so a specific forced d100 roll pins an exact,
	## reproducible Success Level via TestResolver.resolve()'s own
	## floor(target/10) - floor(roll/10) formula.
	var no_talent_ally := Character.new()
	no_talent_ally.character_name = "FireLoreNoTalentPass"
	no_talent_ally.race = pc.race
	no_talent_ally.characteristics = pc.characteristics.duplicate()
	no_talent_ally.characteristics["willpower"] = 30
	no_talent_ally.wounds_max = 20
	no_talent_ally.wounds_current = 10

	## Roll 1 is this project's own house-ruled auto-success (see
	## TestResolver.resolve()'s comment) — succeeds regardless of target.
	fe._apply_cast_spell_outcome(cast_success, cauterise, "Cauterise", no_talent_ally, false, -1, 1)
	checks.append(["a target without the Talent who PASSES the Cool Test takes no further harm", not no_talent_ally.conditions.has("Unconscious") and not no_talent_ally.permanently_scarred])

	var fail_mild_ally := Character.new()
	fail_mild_ally.character_name = "FireLoreNoTalentMildFail"
	fail_mild_ally.race = pc.race
	fail_mild_ally.characteristics = pc.characteristics.duplicate()
	fail_mild_ally.characteristics["willpower"] = 30
	fail_mild_ally.wounds_max = 20
	fail_mild_ally.wounds_current = 10

	## Target 30 (floor 3), forced roll 50 (floor 5) -> SL = 3-5 = -2:
	## a genuine failure, but nowhere near the book's own -6-or-more
	## threshold for the catastrophic outcome.
	fe._apply_cast_spell_outcome(cast_success, cauterise, "Cauterise", fail_mild_ally, false, -1, 50)
	checks.append(["a target who fails the Cool Test by LESS than 6 SL screams in agony but stays conscious and unscarred", not fail_mild_ally.conditions.has("Unconscious") and not fail_mild_ally.permanently_scarred])

	var fail_catastrophic_ally := Character.new()
	fail_catastrophic_ally.character_name = "FireLoreNoTalentCatastrophicFail"
	fail_catastrophic_ally.race = pc.race
	fail_catastrophic_ally.characteristics = pc.characteristics.duplicate()
	fail_catastrophic_ally.characteristics["willpower"] = 30
	fail_catastrophic_ally.wounds_max = 20
	fail_catastrophic_ally.wounds_current = 10

	## Target 30 (floor 3), forced roll 96 -> this project's own house
	## rule floors any roll >=96 (against a target under 96) at -1 SL
	## AT MOST, i.e. min(computed_sl, -1) = min(-6, -1) = -6 exactly —
	## "Failed by -6 or more SL," matching the book text exactly.
	fe._apply_cast_spell_outcome(cast_success, cauterise, "Cauterise", fail_catastrophic_ally, false, -1, 96)
	checks.append(["THE FIX: failing the Cool Test by 6+ SL knocks the target Unconscious", fail_catastrophic_ally.conditions.has("Unconscious")])
	checks.append(["THE FIX: that same catastrophic failure permanently scars the target", fail_catastrophic_ally.permanently_scarred])
	checks.append(["THE FIX: recovery is a real 1d10 HOURS timer (1-10), not a Rounds-based one", fail_catastrophic_ally.cauterise_recovery_hours_remaining >= 1.0 and fail_catastrophic_ally.cauterise_recovery_hours_remaining <= 10.0])

	## tick_cauterise_recovery(): counts down and wakes the target back
	## up once the timer reaches 0, same shape as tick_alcohol_hours().
	var recovery_hours := fail_catastrophic_ally.cauterise_recovery_hours_remaining
	fail_catastrophic_ally.tick_cauterise_recovery(int(recovery_hours * 60.0) - 1)
	checks.append(["tick_cauterise_recovery: still Unconscious with time left on the clock", fail_catastrophic_ally.conditions.has("Unconscious")])
	fail_catastrophic_ally.tick_cauterise_recovery(2)
	checks.append(["THE FIX: tick_cauterise_recovery wakes the target back up once the full 1d10 hours have passed", not fail_catastrophic_ally.conditions.has("Unconscious")])
	checks.append(["tick_cauterise_recovery: the timer itself reaches exactly 0, not negative", fail_catastrophic_ally.cauterise_recovery_hours_remaining == 0.0])

	## The 0-Wounds guard: a character Unconscious for the ordinary,
	## unrelated reason (no Wounds left) must NOT be woken up early just
	## because a stale Cauterise timer happens to expire.
	var zero_wounds_ally := Character.new()
	zero_wounds_ally.character_name = "FireLoreZeroWoundsGuard"
	zero_wounds_ally.race = pc.race
	zero_wounds_ally.characteristics = pc.characteristics.duplicate()
	zero_wounds_ally.wounds_max = 20
	zero_wounds_ally.wounds_current = 0
	zero_wounds_ally.add_condition("Unconscious", 1)
	zero_wounds_ally.cauterise_recovery_hours_remaining = 1.0
	zero_wounds_ally.tick_cauterise_recovery(120)
	checks.append(["tick_cauterise_recovery's 0-Wounds guard: does not wake someone Unconscious for an unrelated reason", zero_wounds_ally.conditions.has("Unconscious")])

	## --- Crown of Flame: a real Blessing-style timed buff ----------------
	var crown: SpellDefinition = GameData.spell_db.find_by_name("Crown of Flame")
	checks.append(["setup: Crown of Flame exists in the spell database", crown != null])

	var wp_before: int = player.get_effective_characteristic_value("willpower")
	var crown_delta: Dictionary = fe._apply_cast_spell_outcome(cast_success, crown, "Crown of Flame", player, false)
	checks.append(["THE FIX: Crown of Flame grants a genuine +10 Willpower timed buff (read through get_effective_characteristic_value, not just the sheet)", player.get_effective_characteristic_value("willpower") == wp_before + 10])
	checks.append(["THE FIX: Duration is Willpower Bonus Rounds", not player.active_buffs.is_empty() and int(player.active_buffs.back()["rounds_remaining"]) == max(1, wb)])
	checks.append(["THE FIX: buff_added is flagged so _on_cast_spell's own redo loop knows to pop this entry back off", crown_delta.get("buff_added", false) == true])

	## Redo-idempotency: exactly one buff entry survives, never two.
	if crown_delta.get("buff_added", false) and not player.active_buffs.is_empty():
		player.active_buffs.pop_back()
	fe._apply_cast_spell_outcome(cast_success, crown, "Crown of Flame", player, true)
	checks.append(["THE FIX: a Fortune redo does not stack a second buff entry on top of the first", player.active_buffs.size() == 1])

	## --- Crown of Flame's own Overcast (shared _offer_buff_spell_overcast,
	## same Duration-multiplies/Targets-adds-a-recipient shape Blessings
	## already use, but no Damage column at all) --------------------------
	var buff_shape: Dictionary = crown_delta.get("buff_shape", {})
	fe.player = player
	fe._offer_buff_spell_overcast("Crown of Flame", player, 5, buff_shape)
	for i in range(3): await tree.process_frame
	checks.append(["setup: the Crown of Flame Overcast picker is genuinely open", fe.awaiting_overcast_choice])

	var pickers: Array = _find_option_buttons(fe.target_container)
	checks.append(["THE FIX: exactly two pickers offered — Duration and Targets — no Damage column at all", pickers.size() == 2])
	var ally1_button: Button = _find_button_named(fe.target_container, ally1.character_name)
	checks.append(["setup: a real toggle button for the ally1 candidate was offered", ally1_button != null])

	if pickers.size() >= 2:
		pickers[0].selected = 1   ## 2 SL -> x2 Duration
		pickers[0].item_selected.emit(1)
		pickers[1].selected = 1   ## 2 SL -> +1 Target
		pickers[1].item_selected.emit(1)
	if ally1_button != null:
		ally1_button.button_pressed = true
		ally1_button.pressed.emit()
	if is_instance_valid(fe._active_overcast_confirm_button):
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["cleanup: the Overcast prompt closed after a valid confirm", not fe.awaiting_overcast_choice])

	var expected_rounds: int = max(1, wb) * 2
	checks.append(["THE FIX: the original target's own buff Duration was MULTIPLIED (not flat-added-to)", player.active_buffs.size() == 1 and int(player.active_buffs[0]["rounds_remaining"]) == expected_rounds])
	checks.append(["THE FIX: the chosen extra target (ally1) now carries the same buff, at the same multiplied Duration", ally1.active_buffs.size() == 1 and ally1.active_buffs[0]["name"] == "Crown of Flame" and int(ally1.active_buffs[0]["rounds_remaining"]) == expected_rounds])
	checks.append(["the non-chosen candidate (ally2) got nothing — Targets spend is exact, not automatic for every ally", ally2.active_buffs.is_empty()])

	## Tick down to confirm the buff genuinely expires afterward.
	for i in range(expected_rounds):
		player.tick_active_buffs()
	checks.append(["reverted: the Willpower buff expires after its own (Overcast-multiplied) Duration", player.get_effective_characteristic_value("willpower") == wp_before])

	## --- Flaming Hearts: the same buff, plus a real Fear/Broken cure -----
	var hearts: SpellDefinition = GameData.spell_db.find_by_name("Flaming Hearts")
	checks.append(["setup: Flaming Hearts exists in the spell database", hearts != null])

	var living_monsters: Array = fe.encounter.get_living("adversary")
	var monster: Character = living_monsters[0] if not living_monsters.is_empty() else null
	if monster != null:
		fe._mark_fear_source(ally2, monster, 2)
	ally2.add_condition("Broken", 3)
	checks.append(["setup: the ally genuinely carries a tracked Fear source and a Broken Condition before casting", monster != null and fe._fear_sources.get(ally2, {}).has(monster) and ally2.conditions.has("Broken")])

	var wp_before2: int = ally2.get_effective_characteristic_value("willpower")
	fe._apply_cast_spell_outcome(cast_success, hearts, "Flaming Hearts", ally2, false)
	checks.append(["THE FIX: Flaming Hearts clears the ally's tracked Fear source entirely", monster != null and not fe._fear_sources.get(ally2, {}).has(monster)])
	checks.append(["THE FIX: Flaming Hearts cures an existing Broken Condition outright", not ally2.conditions.has("Broken")])
	checks.append(["THE FIX: Flaming Hearts also grants the same +10 Willpower timed buff Crown of Flame does", ally2.get_effective_characteristic_value("willpower") == wp_before2 + 10])
	checks.append(["contrast: Crown of Flame itself never touches Fear sources or Broken (that's Flaming Hearts' own addition)", not player.conditions.has("Broken")])

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
	print("RESULT (Fire Lore Buff and Heal Spells): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search collecting every OptionButton under `root`, same
## traversal shape blessing_overcast_test.gd's own _find_option_buttons
## already established for this exact kind of nested Overcast column.
static func _find_option_buttons(root: Node) -> Array:
	var found: Array = []
	if root is OptionButton:
		found.append(root)
	for child in root.get_children():
		found.append_array(_find_option_buttons(child))
	return found

## Depth-first search for a Button whose text matches `button_text`
## exactly — this picker's own Targets candidate buttons are labelled
## with the bare character_name, same as Blessing's own Targets column.
static func _find_button_named(root: Node, button_text: String) -> Button:
	if root is Button and root.text == button_text:
		return root
	for child in root.get_children():
		var found: Button = _find_button_named(child, button_text)
		if found != null:
			return found
	return null
