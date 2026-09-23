extends RefCounted
class_name FlamingSwordOfRhuinTest
## Real feature, per the explicit request: "Flaming Sword of Rhuin"
## used to be a pure flavor-text spell — casting it succeeded, showed
## its summary, and did nothing mechanically at all (is_magic_missile,
## inflicts_condition, and is_area_of_effect were all empty/false, so
## it fell straight into _apply_cast_spell_outcome's generic "else:
## extra.append(spell.summary)" catch-all). Per the follow-up: "let's
## wire it up. IT should only allow casting it on swords, and
## temporarily replace the sword's normal stats. overcast should allow
## more targets and duration only, not extra dmg."
##
## Covers: the Sword-only target restriction (_characters_wielding_
## sword), the actual weapon-stat replacement (fixed SB+6 Damage plus
## Impact — CORRECTED from this feature's original v0.3.85 "+Willpower
## Bonus" guess, per the follow-up request "turn the sword from SB+4 to
## SB+6, and add Impact") and its automatic Duration-based revert
## (Character.get_equipped_weapon/tick_active_buffs, and field_
## encounter_screen.gd's own stale-cache self-heal in _weapon_for), the
## Fortune-redo idempotency fix (re-deriving from the canonical
## weapon_db entry rather than whatever's already equipped), the
## Ablaze-on-hit effect via _show_attack_cards, Flaming Sword's own
## dedicated Overcast (Duration/Targets only, explicitly no Damage
## column), and the newer fix forcing an immediate revert on _end_battle
## even mid-Duration (per "should turn back to a sword if the field
## encounter ends").

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "Aes"
	pc.equipped_weapon = "Sword"

	## A second living party member, same construction pattern
	## blessing_overcast_test.gd already established for this exact
	## need — a real Character, not just the solo default protagonist —
	## so the Sword-only restriction's EXCLUSION side (a Dagger-wielder)
	## and the Overcast Targets column (a second genuine Sword-wielder)
	## both have someone real to test against.
	var ally := Character.new()
	ally.character_name = "FlamingSwordFredi"
	ally.race = pc.race
	ally.characteristics = pc.characteristics.duplicate()
	ally.wounds_max = 999
	ally.wounds_current = 999
	ally.equipped_weapon = "Dagger"
	if GameState.party.size() < 2:
		GameState.party.append(ally)

	GameState.pending_encounter_monster_names = ["Giant Rat", "Giant Rat"]
	var fe = load("res://scenes/FieldEncounter.tscn").instantiate()
	tree.get_root().add_child(fe)
	for i in range(5):
		await tree.process_frame

	## fe.player rotates to whichever party member's Turn is active by
	## the time a few frames have passed (a real 2-person party, not a
	## fixed solo protagonist) — pinned explicitly to `pc`, same
	## reasoning blessing_overcast_test.gd's own comment gives, so every
	## assertion below is about the Sword-wielder deterministically,
	## regardless of initiative.
	fe.player = pc
	var player: Character = pc
	checks.append(["setup: a second living party member exists to test against", fe.encounter != null and fe.encounter.get_living("ally").has(ally)])

	## --- THE FIX: only Sword-wielders are valid targets -----------------
	var wielders: Array = fe._characters_wielding_sword()
	checks.append(["THE FIX: the Sword-wielding player is offered as a valid target", wielders.has(player)])
	if ally != null:
		checks.append(["THE FIX: the Dagger-wielding ally is correctly excluded", not wielders.has(ally)])

	var spell: SpellDefinition = GameData.spell_db.find_by_name("Flaming Sword of Rhuin")
	checks.append(["setup: Flaming Sword of Rhuin exists in the spell database", spell != null])

	## --- THE FIX: casting it actually replaces the wielder's weapon
	## stats, for real ------------------------------------------------------
	var wb: int = player.get_characteristic_bonus("willpower")
	var base_sword: WeaponDefinition = GameData.weapon_db.find_by_name("Sword")
	var cast_success := MagicResolver.CastResult.new()
	cast_success.success = true
	var fake_test_result := TestResolver.TestResult.new()
	fake_test_result.target = 50
	fake_test_result.roll = 10
	fake_test_result.success = true
	fake_test_result.success_levels = 4
	cast_success.test_result = fake_test_result
	fe._apply_cast_spell_outcome(cast_success, spell, "Flaming Sword of Rhuin", player, false)
	var enchanted: WeaponDefinition = fe._weapon_for(player)
	checks.append(["THE FIX: the wielder's weapon is now genuinely renamed 'Flaming Sword of Rhuin'", enchanted.weapon_name == "Flaming Sword of Rhuin"])
	checks.append(["THE FIX: its Damage is a fixed SB+6, replacing the plain Sword's own SB+4 outright (not stacked on top of it)", enchanted.damage_flat == 6])
	checks.append(["THE FIX: it also gains the Impact Quality", enchanted.qualities.has("Impact")])
	checks.append(["THE FIX: Duration is set to Willpower Bonus Rounds", player.flaming_sword_rounds_remaining == wb])
	checks.append(["the original weapon_db Sword entry itself is untouched — a real .duplicate(true), not a shared mutation", base_sword.weapon_name == "Sword" and base_sword.damage_flat != enchanted.damage_flat and not base_sword.qualities.has("Impact")])

	## --- Newer fix: the enchant also self-heals the instant there's no
	## live field encounter running at all, independent of the per-Round
	## timer -- per the report "Elrohir currently still has Flaming sword
	## out of combat and can not clear it... re-equipping to the main
	## hand turns it back into flaming sword." Simulates "already out in
	## the overworld with a stuck timer from before this fix existed" by
	## flipping the flag directly rather than tearing the whole FieldEncounter
	## scene down, then restores it so the rest of this test (still using
	## the same live `fe`) keeps behaving like a real ongoing encounter.
	GameState.in_field_encounter = false
	checks.append(["THE FIX: leaving a live field encounter immediately reverts the enchant, even with the per-Round timer still nonzero", player.get_equipped_weapon().weapon_name == "Sword" and player.flaming_sword_rounds_remaining == 0])
	GameState.in_field_encounter = true

	## --- Redo-idempotency fix: re-applying the outcome (simulating a
	## Fortune Point redo) must NOT stack the Damage bonus a second time ---
	fe._apply_cast_spell_outcome(cast_success, spell, "Flaming Sword of Rhuin", player, true)
	var enchanted_after_redo: WeaponDefinition = fe._weapon_for(player)
	checks.append(["THE FIX: a redo (re-applying the same cast outcome) does not stack the Damage bonus a second time", enchanted_after_redo.damage_flat == 6])

	## --- Ablaze on a successful hit while wielding it --------------------
	## Both grabbed up front, before either attack -- get_living() only
	## ever returns the still-living roster, so re-querying it after the
	## first forced-critical hit could easily have killed monster #1 and
	## shifted monster #2 down to index 0, silently aiming the "contrast"
	## check below at the wrong (or a now out-of-bounds) Character.
	## Padded Wounds so neither hit can accidentally defeat its target
	## and suppress the Condition-on-hit check (same reasoning an
	## earlier T'Essla's Arc test already established for this exact
	## class of false negative).
	var living_monsters: Array = fe.encounter.get_living("adversary")
	var monster: Character = living_monsters[0]
	var monster2: Character = living_monsters[1]
	monster.wounds_max = 999
	monster.wounds_current = 999
	monster2.wounds_max = 999
	monster2.wounds_current = 999
	var pool = fe.encounter.advantage_pool
	var hit_result := CombatResolver.resolve_melee_attack(player, monster, enchanted, pool, null, "", false, 0, 0, 1, [], 0, [], 99, false, [], [], "")
	checks.append(["setup: the forced roll genuinely landed a hit", hit_result.hit])
	fe._show_attack_cards(player, monster, enchanted.weapon_name, hit_result)
	checks.append(["THE FIX: a successful hit with the Flaming Sword sets the target Ablaze", int(monster.conditions.get("Ablaze", 0)) >= 1])

	## --- Contrast: a normal (non-enchanted) Sword hit does NOT inflict
	## Ablaze ---------------------------------------------------------------
	var normal_hit := CombatResolver.resolve_melee_attack(player, monster2, base_sword, pool, null, "", false, 0, 0, 1, [], 0, [], 99, false, [], [], "")
	fe._show_attack_cards(player, monster2, base_sword.weapon_name, normal_hit)
	checks.append(["contrast: a normal Sword hit (not the enchanted one) never applies Ablaze", not monster2.conditions.has("Ablaze")])

	## --- Automatic revert once Duration runs out -------------------------
	for i in range(wb):
		player.tick_active_buffs()
	checks.append(["THE FIX: Character.get_equipped_weapon() stops returning the enchant once Duration hits 0", player.get_equipped_weapon().weapon_name == "Sword"])
	checks.append(["THE FIX: _weapon_for()'s own stale-cache check reverts too, without ever calling _resolve_weapon manually", fe._weapon_for(player).weapon_name == "Sword"])
	checks.append(["reverted: the wielder is offered again as a valid Sword target now that the enchant is over", fe._characters_wielding_sword().has(player)])

	## --- Overcast: Duration multiplies, Targets adds another Sword-
	## wielder, and there is NO Damage column at all -----------------------
	if ally != null:
		ally.equipped_weapon = "Sword"   ## give the ally a real Sword too, so Targets has a genuine candidate
		## _weapon_for()'s own cache (`weapons[c]`) is only ever self-
		## healing for a STALE FLAMING enchant (see its own comment) — a
		## plain direct mutation of equipped_weapon like the line above
		## is exactly what the real weapon-switch free action itself
		## always follows with a fresh `weapons[c] = _resolve_weapon(c)`
		## (see _on_switch_weapon); erasing the cache here mirrors that
		## so _characters_wielding_sword()'s very next call actually
		## re-resolves the ally to their new Sword instead of quietly
		## keeping the earlier cached Dagger forever.
		fe.weapons.erase(ally)
	fe.player = player
	fe._apply_cast_spell_outcome(cast_success, spell, "Flaming Sword of Rhuin", player, false)
	var shape: Dictionary = {}
	## Re-derive the exact shape _on_cast_spell would have handed to
	## _offer_flaming_sword_overcast, the same way the real cast flow
	## does (delta["flaming_sword_shape"]) -- easiest to just rebuild it
	## directly here rather than threading it back out of the private
	## apply function's return value a second time.
	shape = {"real_weapon_name": "Sword", "rounds": wb}
	fe._offer_flaming_sword_overcast(player, 4, shape)   ## 4 SL -> 2 full stages available
	for i in range(3): await tree.process_frame
	checks.append(["setup: the Flaming Sword Overcast picker is genuinely open", fe.awaiting_overcast_choice])

	var pickers := _find_option_buttons(fe.target_container)
	checks.append(["THE FIX: no third (Damage) column exists at all — only Duration and Targets", pickers.size() == 2])

	if pickers.size() >= 2:
		pickers[0].selected = 1   ## Duration: 2 SL -> x2
		pickers[0].item_selected.emit(1)
		pickers[1].selected = 1   ## Targets: 2 SL -> +1
		pickers[1].item_selected.emit(1)
	var ally_btn: Button = _find_button_containing(fe.target_container, ally.character_name) if ally != null else null
	checks.append(["setup: a toggle button for the ally Sword-wielder was offered", ally_btn != null])
	if ally_btn != null:
		ally_btn.button_pressed = true
		ally_btn.pressed.emit()
	if is_instance_valid(fe._active_overcast_confirm_button):
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["cleanup: the Overcast prompt closed after a valid confirm", not fe.awaiting_overcast_choice])

	checks.append(["THE FIX: Duration was multiplied (x2) on the original target", player.flaming_sword_rounds_remaining == wb * 2])
	if ally != null:
		checks.append(["THE FIX: the extra chosen target (ally) also got the enchant, at the same multiplied Duration", ally.flaming_sword_rounds_remaining == wb * 2])
		checks.append(["THE FIX: overcast never adds extra Damage — the extra target gets the exact same fixed SB+6, not scaled up", fe._weapon_for(ally).damage_flat == 6])
		checks.append(["THE FIX: the extra target's enchant also gains Impact", fe._weapon_for(ally).qualities.has("Impact")])

	## --- Revert on battle end, even mid-Duration --------------------------
	checks.append(["setup: the enchant is still active (mid-Duration) going into battle end", player.flaming_sword_rounds_remaining > 0])
	fe._end_battle(true)
	checks.append(["THE FIX: ending the battle immediately reverts the enchant, even mid-Duration", player.flaming_sword_rounds_remaining == 0 and player.get_equipped_weapon().weapon_name == "Sword"])
	if ally != null:
		checks.append(["THE FIX: ending the battle reverts every enchanted combatant, not just the original caster's target", ally.flaming_sword_rounds_remaining == 0 and ally.get_equipped_weapon().weapon_name == "Sword"])

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
	print("RESULT (Flaming Sword of Rhuin): ", "ALL PASS" if all_pass else "SOME FAILED")
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

## Depth-first search for a Button whose text CONTAINS `substr` — unlike
## blessing_overcast_test.gd's own exact-match _find_button_named, this
## screen's own Targets candidate buttons are labelled
## "Name (WeaponName)", not just the bare name.
static func _find_button_containing(root: Node, substr: String) -> Button:
	if root is Button and String(root.text).contains(substr):
		return root
	for child in root.get_children():
		var found: Button = _find_button_containing(child, substr)
		if found != null:
			return found
	return null
