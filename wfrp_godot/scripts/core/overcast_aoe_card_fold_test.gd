extends RefCounted
class_name OvercastAoeCardFoldTest
## Regression test for the user report (with a screenshot of a Blast
## spell's roll card): "overcast dmg should be adding dmg after
## mitigation, can we update the roll card dmg rather then add the green
## text afterwards."
##
## ROOT CAUSE: _offer_overcasting_aoe() (the Blast/AoE counterpart of the
## single-target _offer_overcasting()) applied the Overcast bonus's real,
## combined Wounds directly to each target, but only ever ANNOUNCED that
## combined total in a separate plain-text green notice appended below
## the roll card — the card itself, already rendered by
## _apply_cast_spell_outcome_aoe() with the pre-Overcast numbers, was
## never touched again. So a player who spent SL on Overcast Damage saw
## the card's own boxed Damage row and each target's "N Wound(s) (M
## mitigated)" line stay exactly as they were before the spend, with the
## real, final numbers only ever showing up as a disconnected line of
## green text underneath — exactly what the two (visually identical)
## screenshots in the report show. The single-target spell path already
## had the correct behaviour (see _offer_overcasting()'s own "fold the
## Overcast bonus into the card's own boxed Damage row" comment, and
## _last_damage_spell_hit's own declaration comment) — the AoE path's own
## _last_aoe_damage_hits doc comment even already CLAIMED to use "the
## same fold-in pattern," but the implementation never actually did.
##
## THE FIX: _offer_overcasting_aoe() now mutates the exact same live
## Dictionary/Array objects the roll card renders from (_last_aoe_card_
## data's own "damage" key, _last_aoe_damage_breakdown's own Array, and
## each hit's own "hit_entry" dict's "wounds"/"mitigated" keys) and calls
## _rebuild_history_display() once, instead of leaving the card stale and
## posting a separate notice. No more green text is added at all for a
## successful fold — the card itself now shows the true, final numbers.
##
## This test drives _apply_cast_spell_outcome_aoe() and
## _offer_overcasting_aoe() directly (bypassing the full cast-targeting
## UI flow, same as critical_wound_deflect_input_test.gd's own approach
## for a different prompt), casting "Blast" (damage_flat 3, the exact
## spell from the report) against two monsters with different Toughness/
## Armour (so their post-Overcast mitigation genuinely differs), then
## confirms:
## (1) before Overcast: the card's boxed Damage total and each target's
##     Wounds/mitigated line show the plain pre-Overcast numbers.
## (2) after Overcast: the SAME card object's Damage total and breakdown
##     reflect the combined (base + Overcast) value, each target's own
##     Wounds/mitigated line is recomputed against that combined value
##     (not just re-announced in text), the targets' actual Wounds
##     reflect the higher total exactly once (no double-application),
##     and no new "Overcast" notice text was added to the log.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	pc.character_name = "OvercastTester"

	var no_pool: Array[String] = []
	GameState.current_field_difficulty_tier = 0
	GameState.current_field_monster_pool = no_pool
	GameState.current_field_habitat = ""
	GameState.dungeon_state = {}
	GameState.pending_dungeon_theme_id = "sewer"
	GameState.dungeon_entry_requested = true   ## real dungeon-entry signal, see end_turn_wasd_focus_no_target_test.gd's own identical setup
	Dice.rng.seed = 3
	seed(3)

	var scene: PackedScene = load("res://scenes/FieldEncounter.tscn")
	var fe: Node = scene.instantiate()
	tree.get_root().add_child.call_deferred(fe)
	for i in range(6):
		await tree.process_frame

	var player: Character = fe.player
	## Pin Willpower so the spell's own Damage/Willpower Bonus breakdown
	## is fully deterministic (dmg = damage_flat(3) + WP Bonus).
	player.characteristics.willpower = 30   ## WP Bonus 3
	fe.player = player

	var spell: SpellDefinition = GameData.spell_db.find_by_name("Blast")
	checks.append(["setup: found the real Blast spell (damage_flat 3, is_area_of_effect)", spell != null and spell.is_magic_missile and spell.is_area_of_effect])
	if spell == null:
		print("RESULT (Overcast AoE Card Fold): SETUP FAILED (missing Blast spell)")
		fe.queue_free()
		return false

	## Two named monsters, spawned directly (bypassing the random
	## encounter group builder) so their Toughness can be pinned to give
	## them genuinely different soak below — same _spawn_monsters_during_
	## exploration() approach end_turn_wasd_focus_no_target_test.gd's own
	## Case 3 already uses.
	var entrance: Vector2i = fe.dungeon_state.get("entrance_pos", Vector2i.ZERO)
	fe._spawn_monsters_during_exploration(["Giant Rat", "Giant Rat"], entrance, null)
	for i in range(3):
		await tree.process_frame
	checks.append(["setup: at least 2 real monsters exist to target", fe.monsters.size() >= 2])
	if fe.monsters.size() < 2:
		print("RESULT (Overcast AoE Card Fold): SETUP FAILED (need 2 monsters)")
		fe.queue_free()
		return false
	var m1: Character = fe.monsters[fe.monsters.size() - 2]
	var m2: Character = fe.monsters[fe.monsters.size() - 1]
	## Different soak (Toughness + Body Armour) so the two targets'
	## post-Overcast mitigation genuinely differs — a meaningful check
	## that each is recomputed individually, not just copy-pasted.
	m1.characteristics.toughness = 20   ## TB 2, no armour -> soak 2
	m1.equipped_armour = []
	m1.armour_damage.clear()
	m2.characteristics.toughness = 40   ## TB 4, no armour -> soak 4
	m2.equipped_armour = []
	m2.armour_damage.clear()
	m1.wounds_max = 30
	m1.wounds_current = 30
	m2.wounds_max = 30
	m2.wounds_current = 30

	var cast_result := MagicResolver.CastResult.new()
	cast_result.success = true
	cast_result.critical = false
	var tr := TestResolver.TestResult.new()
	tr.target = 90
	tr.roll = 20
	tr.success = true
	tr.success_levels = 7
	tr.base_success_levels = 7
	tr.base_target = 90
	cast_result.test_result = tr

	## dmg = damage_flat(3) + WP Bonus(3) = 6. m1 soak 2 -> 4 Wounds
	## (mitigated 2). m2 soak 4 -> 2 Wounds (mitigated 4).
	fe._apply_cast_spell_outcome_aoe(cast_result, spell, "Blast", [m1, m2], false)
	for i in range(3): await tree.process_frame

	checks.append(["setup: the base cast genuinely dealt Wounds to both targets", m1.wounds_current == 26 and m2.wounds_current == 28])
	checks.append(["setup: a real card was tracked for a possible later Overcast fold", not fe._last_aoe_card_data.is_empty()])
	checks.append(["setup: the card's own Damage total shows the plain pre-Overcast value (6)", int(fe._last_aoe_card_data.get("damage", -1)) == 6])
	var breakdown_before: Array = fe._last_aoe_damage_breakdown
	checks.append(["setup: the breakdown has no Overcast row yet", not breakdown_before.any(func(b): return b.get("name", "") == "Overcast")])

	var hit_entries: Dictionary = {}   ## target -> hit_entry, for convenience below
	for hit in fe._last_aoe_damage_hits:
		hit_entries[hit["target"]] = hit.get("hit_entry", {})
	checks.append(["setup: m1's own tracked hit_entry shows the plain pre-Overcast Wounds/mitigated (4/2)", int(hit_entries.get(m1, {}).get("wounds", -1)) == 4 and int(hit_entries.get(m1, {}).get("mitigated", -1)) == 2])
	checks.append(["setup: m2's own tracked hit_entry shows the plain pre-Overcast Wounds/mitigated (2/4)", int(hit_entries.get(m2, {}).get("wounds", -1)) == 2 and int(hit_entries.get(m2, {}).get("mitigated", -1)) == 4])

	var history_size_before: int = fe.history.size()

	## Now spend Overcast SL on Damage — fire _offer_overcasting_aoe(),
	## which suspends on its own `while awaiting_overcast_choice: await
	## ...` loop exactly like a real player's own Magic/Prayers column
	## choice would.
	fe._offer_overcasting_aoe(spell, "Blast", 4)
	for i in range(3): await tree.process_frame
	checks.append(["setup: the Overcast Damage prompt is genuinely open", fe.awaiting_overcast_choice])

	## Pick the real "Damage: X SL -> +N Damage" option (not "skip") and
	## confirm — same as a real click on the dropdown + Confirm button.
	var damage_picker: OptionButton = null
	for child in fe.target_container.get_children():
		damage_picker = _find_option_button(child)
		if damage_picker != null:
			break
	checks.append(["setup: a real Damage spend dropdown was offered", damage_picker != null])
	var picked_damage_bonus := 0
	if damage_picker != null and damage_picker.item_count > 1:
		damage_picker.selected = 1
		damage_picker.item_selected.emit(1)
		var label: String = damage_picker.get_item_text(1)
		## "Damage: X SL -> +N Damage" -- pull N back out to compute the
		## expected combined totals below without hard-coding a value
		## that depends on the Winds of Magic table.
		var arrow_idx := label.find("+")
		if arrow_idx != -1:
			picked_damage_bonus = int(label.substr(arrow_idx + 1).split(" ")[0])
	checks.append(["setup: a real, positive Overcast Damage bonus was actually offered", picked_damage_bonus > 0])

	if is_instance_valid(fe._active_overcast_confirm_button):
		fe._active_overcast_confirm_button.pressed.emit()
	for i in range(3): await tree.process_frame
	checks.append(["cleanup: the Overcast prompt closed after confirming", not fe.awaiting_overcast_choice])

	var combined_dmg := 6 + picked_damage_bonus
	var expected_m1_wounds: int = max(1, combined_dmg - 2)
	var expected_m2_wounds: int = max(1, combined_dmg - 4)

	## --- THE FIX: the card itself, not a separate notice, now shows the
	## real combined numbers ---
	checks.append(["THE FIX: the card's own boxed Damage total was updated to the combined (base + Overcast) value", int(fe._last_aoe_card_data.get("damage", -1)) == combined_dmg])
	var breakdown_after: Array = fe._last_aoe_damage_breakdown
	checks.append(["THE FIX: an 'Overcast' row was appended to the SAME breakdown list the card renders from", breakdown_after.any(func(b): return b.get("name", "") == "Overcast" and int(b.get("amount", -1)) == picked_damage_bonus)])
	checks.append(["THE FIX: m1's own tracked hit_entry was updated in place to the recombined Wounds/mitigated", int(hit_entries.get(m1, {}).get("wounds", -1)) == expected_m1_wounds and int(hit_entries.get(m1, {}).get("mitigated", -1)) == max(0, combined_dmg - expected_m1_wounds)])
	checks.append(["THE FIX: m2's own tracked hit_entry was updated in place too, with its OWN (different) mitigation", int(hit_entries.get(m2, {}).get("wounds", -1)) == expected_m2_wounds and int(hit_entries.get(m2, {}).get("mitigated", -1)) == max(0, combined_dmg - expected_m2_wounds)])

	## --- Real Wounds were adjusted exactly once (reversed, then
	## re-applied combined) — not double-counted ---
	checks.append(["m1's real Wounds reflect the combined total exactly once (no double-application)", m1.wounds_current == 30 - expected_m1_wounds])
	checks.append(["m2's real Wounds reflect the combined total exactly once (no double-application)", m2.wounds_current == 30 - expected_m2_wounds])

	## --- No separate green "Overcast (...)" notice was posted; the fold
	## happened entirely inside the existing card via _rebuild_history_
	## display(), not a new history entry ---
	checks.append(["no extra history entry was created for the Overcast fold (folded into the existing card instead)", fe.history.size() == history_size_before])
	var found_overcast_notice := false
	for entry in fe.history:
		for seg in entry.get("segments", []):
			if seg.get("kind", "") == "notice" and String(seg.get("text", "")).findn("Overcast") != -1:
				found_overcast_notice = true
	checks.append(["THE FIX: no separate plain-text 'Overcast (...)' notice was added — the card itself is the only place the numbers show now", not found_overcast_notice])

	fe.queue_free()
	await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Overcast AoE Card Fold): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass

## Depth-first search for the first OptionButton anywhere under `root` —
## the Overcast column nests a couple of plain Container layers deep.
static func _find_option_button(root: Node) -> OptionButton:
	if root is OptionButton:
		return root
	for child in root.get_children():
		var found: OptionButton = _find_option_button(child)
		if found != null:
			return found
	return null
