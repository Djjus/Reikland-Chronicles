extends RefCounted
class_name TravelOverloadBlockRelocationTest
## Regression test for v0.2.525 ("stuck outside Giessingen" follow-up to
## v0.2.524's Overload-travel-block fix): v0.2.524 blocked EVERY World Map
## travel action (_offer_travel/_offer_travel_to_tile) whenever the party
## was Overloaded, to replace the old nonsensical "999 day(s) travel"
## prompt with a clear explanation — but the World Map has no free WASD
## walking at all, so that blocked literally everything once already
## Overloaded and out on the map, including the one obvious way to fix it
## (walk back into a city and drop gear). Fixed by moving the real block
## to the one actual departure point, _offer_return_to_world_map(), and
## flooring Movement at 1 in _compute_travel_days()'s own rate-table
## lookup so _offer_travel/_offer_travel_to_tile never show the old 999
## sentinel again either.
##
## Drives a real Overworld scene (Giessingen's own local map), forces the
## same artificial Overload via a huge coin stack (cheapest real lever on
## get_current_encumbrance()), and confirms: (1) _offer_travel_to_tile
## still opens a real Confirm prompt with a sane, non-999 day count while
## Overloaded and already on the World Map, (2) _offer_return_to_world_map
## correctly blocks with the clear Overload explanation instead of
## opening the Leave prompt, and (3) leaving works normally again once the
## excess weight is dropped.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	var pc: Character = GameState.player_character
	GameState.pending_map_path = "res://data/maps/giessingen_village.tres"
	var ow = load("res://scenes/Overworld.tscn").instantiate()
	tree.get_root().add_child(ow)
	tree.current_scene = ow
	for i in range(15): await tree.process_frame

	## Force Overloaded (>3x carrying capacity) via a huge coin stack —
	## coin encumbrance is a real, simple contributor to
	## get_current_encumbrance(), no item definitions needed.
	var capacity: int = pc.get_carrying_capacity()
	pc.gold_crowns = int(float(capacity) * 4.0 / Character.COIN_ENCUMBRANCE_PER_COIN) + 1000
	var enc: Dictionary = pc.get_encumbrance_penalty()
	checks.append(["setup: the coin stack genuinely pushes the character into Overloaded/immobile", bool(enc.get("immobile", false))])
	checks.append(["setup: get_movement() is genuinely 0 while Overloaded (the real underlying rule, untouched)", pc.get_movement() <= 0])

	## --- (1) _offer_travel_to_tile still opens a real prompt, sane day count, no block ---
	var target_tile: Vector2i = ow.player.grid_pos + Vector2i(3, 0)
	ow._offer_travel_to_tile(target_tile)
	for i in range(5): await tree.process_frame
	checks.append(["THE BUG: _offer_travel_to_tile is NOT blocked outright while Overloaded — a real Confirm prompt opens", ow.awaiting_travel_confirm])
	checks.append(["the offered day count is sane (not the old 999 sentinel) thanks to _compute_travel_days' own Movement floor", ow._pending_travel_days < 999 and ow._pending_travel_days > 0])
	## Cancel out of it cleanly.
	ow._confirm_prompt_press_no()
	for i in range(3): await tree.process_frame
	checks.append(["the prompt closes normally on Cancel, no dangling state", not ow.awaiting_travel_confirm])

	## --- (2) _offer_return_to_world_map() genuinely blocks while Overloaded ---
	ow._offer_return_to_world_map()
	for i in range(5): await tree.process_frame
	checks.append(["THE REAL RULE: _offer_return_to_world_map() does NOT open the Leave prompt while Overloaded", not ow.awaiting_travel_confirm])
	## _show_wilderness_text's own prompt should be up instead, carrying
	## the Overload explanation.
	var showed_overload_text: bool = ow.encounter_label.visible and ow.encounter_label_text.text.findn("Overload") != -1
	checks.append(["the block shows the clear Overload explanation rather than a bare refusal", showed_overload_text])
	## Dismiss whatever wilderness-text prompt is up so nothing's left
	## hanging — _show_wilderness_text() (used for the Overload block
	## message) gates on _awaiting_wilderness_continue, not the separate
	## Y/N _awaiting_wilderness_choice flag.
	if ow._awaiting_wilderness_continue:
		ow._awaiting_wilderness_continue = false
	for i in range(5): await tree.process_frame

	## --- (3) leaving works again once the excess weight is dropped ---
	pc.gold_crowns = 0
	var enc_after: Dictionary = pc.get_encumbrance_penalty()
	checks.append(["setup: dropping the coin stack genuinely clears Overloaded/immobile", not bool(enc_after.get("immobile", false))])
	ow._offer_return_to_world_map()
	for i in range(5): await tree.process_frame
	checks.append(["leaving now opens the real Leave prompt again once the party isn't Overloaded any more", ow.awaiting_travel_confirm])
	ow._confirm_prompt_press_no()
	for i in range(5): await tree.process_frame
	checks.append(["that prompt also closes normally on Cancel", not ow.awaiting_travel_confirm])

	ow.queue_free()
	for i in range(3): await tree.process_frame

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Travel Overload Block Relocation): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
