extends RefCounted
class_name TempleOfShallyaTest
## Regression/functional test for the request ("lets hook up The Temple
## of Shallya in Ubersreik, copy the priestess from Giessingen"): The
## Temple of Shallya (ubersreik_city_locations.tres, location_id 35) was
## previously unlocked = false with no radial action of its own —
## _radial_actions_for() had no "temple" branch at all. Now it's
## unlocked, and the party standing on it gets a real "Enter" action
## that hands off to the SAME shared Healer.tscn/healer_screen.gd
## Giessingen's own map tile already uses (this project's NPCs are
## role-based, not individually named — see npc_flavor_text.gd's own
## header comment — so "copy the priestess" means reusing that same
## screen/role, not building a second Character/screen).
##
## Deliberately gated on the exact location NAME, not just
## category == "temple" — Ubersreik has three temple-category
## locations in the Marktplatz district (Shallya, Sigmar, Verena), each
## meant for a different god, so pure category-gating (the pattern
## every other branch in _radial_actions_for uses) would incorrectly
## hand Sigmar/Verena the same Shallyan-Priest healer action too. This
## test checks both that Shallya gets the new action AND that the other
## two temples do NOT.
##
## Also checks the new two-way hand-off on healer_screen.gd's own
## _on_close(): reached via Ubersreik's Temple of Shallya (a real
## pending_healer_city_id set) returns to CityScreen with the right
## city; reached via Giessingen's own map tile (no pending id, unchanged
## existing behaviour) still falls back to Overworld.tscn exactly as it
## always has.

static func run_test(tree: SceneTree) -> bool:
	var checks: Array = []

	await tree.process_frame
	await tree.process_frame

	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_city_id = "ubersreik"

	var cs = load("res://scenes/CityScreen.tscn").instantiate()
	tree.get_root().add_child(cs)
	for i in range(5):
		await tree.process_frame

	var shallya: CityLocationDefinition = null
	var sigmar: CityLocationDefinition = null
	var verena: CityLocationDefinition = null
	for loc in cs.location_list.locations:
		if loc.location_id == 35:
			shallya = loc
		elif loc.location_id == 33:
			sigmar = loc
		elif loc.location_id == 36:
			verena = loc

	checks.append(["setup: found The Temple of Shallya (location_id 35) in the data", shallya != null])
	checks.append(["setup: found The High Temple of Sigmar (location_id 33) in the data", sigmar != null])
	checks.append(["setup: found The Temple of Verena (location_id 36) in the data", verena != null])

	if shallya != null:
		checks.append(["data: The Temple of Shallya is now unlocked", shallya.unlocked])
		checks.append(["data: The Temple of Shallya is temple-category", shallya.category == "temple"])

		## Not yet standing there: same as any other not-yet-visited
		## location, just Lore+Travel -- no premature "Enter" offer.
		var away_actions: Array = cs._radial_actions_for(shallya)
		var away_keys := []
		for a in away_actions:
			away_keys.append(a["key"])
		checks.append(["radial (travel target): Temple of Shallya (party not there) offers Lore+Travel (%s)" % str(away_keys), away_keys == ["lore", "travel"]])

		## Move the party's own token onto the Temple of Shallya's marker
		## (bypassing a real walk, same shortcut CityScreenTest's own shop
		## hours section uses) and confirm the new "here" radial offers a
		## real Enter action.
		var saved_pos: Vector2 = cs.map_view.party_token_pos
		cs.map_view.party_token_pos = shallya.map_position

		var here_actions: Array = cs._radial_actions_for(shallya)
		var here_keys := []
		for a in here_actions:
			here_keys.append(a["key"])
		checks.append(["radial (current location): Temple of Shallya (party standing on it) offers Lore+Enter (%s)" % str(here_keys), here_keys == ["lore", "pray"]])
		var enter_entry: Dictionary = {}
		for a in here_actions:
			if a["key"] == "pray":
				enter_entry = a
		checks.append(["radial: the new action's own label reads \"Enter\", matching Shop's convention for an enterable building", enter_entry.get("label", "") == "Enter"])

		## THE NAME-GATE: Sigmar and Verena are also temple-category, but
		## must NOT pick up this same action just from sharing a category
		## -- only Lore, same as any other content-less location the
		## party happens to be standing on.
		if sigmar != null:
			cs.map_view.party_token_pos = sigmar.map_position
			var sigmar_actions: Array = cs._radial_actions_for(sigmar)
			var sigmar_keys := []
			for a in sigmar_actions:
				sigmar_keys.append(a["key"])
			checks.append(["THE NAME-GATE: The High Temple of Sigmar (party standing on it) does NOT get the Shallya-only Enter action (%s)" % str(sigmar_keys), sigmar_keys == ["lore"]])
		if verena != null:
			cs.map_view.party_token_pos = verena.map_position
			var verena_actions: Array = cs._radial_actions_for(verena)
			var verena_keys := []
			for a in verena_actions:
				verena_keys.append(a["key"])
			checks.append(["THE NAME-GATE: The Temple of Verena (party standing on it) does NOT get the Shallya-only Enter action (%s)" % str(verena_keys), verena_keys == ["lore"]])

		## Restore the party's own position and dispatch a real "pray"
		## action via _on_radial_action -- the actual wiring under test,
		## not just _enter_temple() called directly. This calls
		## change_scene_to_file() (inside _enter_temple()), so per this
		## project's own established caution (see CityScreenTest's own
		## "leave city confirmed" block comment on why that one is the
		## very last thing that test does), this is deliberately this
		## test's own final CityScreen-driven action, with no further
		## awaits or CityScreen-dependent checks after it.
		cs.map_view.party_token_pos = shallya.map_position
		cs._on_location_clicked(shallya)
		cs._on_radial_action(shallya, "pray")
		checks.append(["dispatch: choosing Enter on the Temple of Shallya sets pending_healer_city_id to this city", GameState.pending_healer_city_id == "ubersreik"])

		cs.map_view.party_token_pos = saved_pos

	## healer_screen.gd's own _on_close() branching -- a separate,
	## freshly-instantiated scene (not routed through the CityScreen
	## instance above at all), so this is unaffected by the
	## change_scene_to_file() CityScreen just queued. Both branches below
	## call change_scene_to_file() themselves, so -- same caution as
	## above -- these are deliberately the very last checks this whole
	## test performs, read synchronously right after each call with no
	## intervening process_frame (the deferred scene free this queues
	## doesn't actually happen until a later process_frame lets it, per
	## CityScreenTest's own documented gotcha).
	GameState.reset_world_state()
	GameState.player_character = null
	GameState.ensure_player_character()
	GameState.pending_healer_city_id = ""
	GameState.pending_city_id = "should_not_change"
	var hs = load("res://scenes/Healer.tscn").instantiate()
	tree.get_root().add_child(hs)
	for i in range(3):
		await tree.process_frame

	hs._on_close()
	checks.append(["healer close (Giessingen tile entry, no pending healer id): pending_city_id left untouched, unchanged existing fallback behaviour", GameState.pending_city_id == "should_not_change"])
	checks.append(["healer close (Giessingen tile entry): pending_healer_city_id stays empty", GameState.pending_healer_city_id == ""])

	GameState.pending_healer_city_id = "ubersreik"
	hs._on_close()
	checks.append(["healer close (Ubersreik Temple of Shallya entry, pending healer id set): pending_city_id now set to the right city", GameState.pending_city_id == "ubersreik"])
	checks.append(["healer close (Ubersreik Temple of Shallya entry): pending_healer_city_id consumed (cleared) so it can't leak into a later visit", GameState.pending_healer_city_id == ""])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Temple Of Shallya): ", "ALL PASS (%d checks)" % checks.size() if all_pass else "SOME FAILED")
	return all_pass
