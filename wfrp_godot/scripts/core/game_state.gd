extends Node
## Autoloaded as "GameState". Minimal session state that needs to survive
## scene changes — the player's Character, plus where they were standing
## in the overworld before a field encounter, so returning from combat
## (on a win) drops them back in the same spot instead of resetting to
## the map's spawn point. No save/load of world state to disk (see
## README) — this only persists for the current run.

## Per the request: up to 4 controllable party members. player_character
## itself is now a computed property (below) backed by this array, so
## every one of the 200+ existing call sites across the whole project
## that reads or assigns GameState.player_character keeps working
## completely unchanged — they transparently read/write whichever
## member is currently active, with no rewrite required anywhere else.
var party: Array[Character] = []
var active_party_index: int = 0
## Prone auto-recovery spec ("out of combat characters with the Prone
## Condition automatically lose it if they have 1+ HP; in combat they
## should have the option to Stand Up instead"): true for the entire
## lifetime of FieldEncounterScreen (both its combat and exploration
## submodes — see that script's own _ready()/_exit_tree()), false
## everywhere else (world map, city, camp, Temple of Shallya). Read by
## Character.wounds_current's own setter to decide whether healing back
## above 0 Wounds should auto-clear Prone (out of combat, exactly as
## before) or leave it for the player to spend a Move/Resolve on
## (genuinely in a FieldEncounter — otherwise Stand Up/Spend Resolve
## would never have anything to do, since a heal mid-fight would already
## have silently cleared Prone for free).
var in_field_encounter: bool = false
## Per the request: party members dismissed via the Character Menu's
## Group tab — kept here (and persisted, see SaveManager/autosave
## below) so the Party Companion Maker NPC in Giessingen can offer to
## re-recruit them later with everything they left with still intact,
## rather than just discarding them.
var dismissed_companions: Array[Character] = []

var player_character: Character:
	get:
		if active_party_index >= 0 and active_party_index < party.size():
			return party[active_party_index]
		return null
	set(value):
		if value == null:
			## Every existing call site setting this to null means "no
			## active character" — clearing the whole party matches
			## that intent, not just vacating one slot.
			party.clear()
			active_party_index = 0
			return
		if active_party_index >= 0 and active_party_index < party.size():
			party[active_party_index] = value
		else:
			## First-ever assignment (a fresh character, or loading
			## into a previously-empty party) starts a brand new party
			## of one, active immediately.
			party = [value]
			active_party_index = 0

const MAX_PARTY_SIZE := 4

## Adds a new member to the party if there's room. Returns false (and
## does nothing) if the party is already full — callers should check
## this before assuming the add succeeded.
func add_party_member(character: Character) -> bool:
	if party.size() >= MAX_PARTY_SIZE:
		return false
	party.append(character)
	return true

## Per the request: Q (direction -1) cycles left, E (direction +1)
## cycles right — wraps around at both ends. A no-op on a party of 0
## or 1, since there's nothing to switch to.
func cycle_active_party_member(direction: int) -> void:
	if party.size() <= 1:
		return
	active_party_index = posmod(active_party_index + direction, party.size())

func _ready() -> void:
	## Per the repeated report of save/load "not working" on any map
	## besides Giessingen: the in-game Quit button already correctly
	## autosaved before quitting, but closing the window directly via
	## the OS's own close button (or Alt+F4/Cmd+Q) — almost certainly
	## the more common way players actually exit — bypassed that
	## entirely, silently discarding anything since the last
	## movement-triggered autosave. That's consistent with always
	## reloading into Giessingen: it's genuinely the last map an
	## autosave had actually captured, not a bug in restoring the
	## saved data itself (which was already fixed and verified twice).
	## auto_accept_quit must be turned off for NOTIFICATION_WM_CLOSE_REQUEST
	## below to actually run before the engine quits, rather than the
	## engine quitting immediately regardless.
	get_tree().auto_accept_quit = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()
		get_tree().quit()

## Which save slot the active character belongs to, so autosave (below)
## knows where to write without the player ever choosing a slot manually
## mid-session. -1 means "no active saved session" (e.g. the default
## character from ensure_player_character(), which was never created or
## loaded through the normal Character Creation flow) — autosave is a
## no-op in that case, same as before this system existed.
var current_slot: int = -1

## Saves the current player_character to current_slot, if there is one.
## This is now the ONLY way the game saves — there's no manual "Save"
## action anymore (see CharacterMenu's Switch Character tab and
## PauseMenu). Called from a periodic Timer in Overworld (every 6s,
## covering plain wandering with no other trigger), when the character
## menu closes (covers XP spends/equipment changes made while it was
## open), at real gameplay checkpoints (shop purchases, camp, healer,
## quest/encounter triggers), and before switching characters,
## returning to the main menu, or quitting — so there's never a
## meaningful window where progress could be lost.
## Per the "movement feels jerky" request: this INTENTIONALLY no longer
## runs on every single tile step (Overworld._on_player_moved used to
## call it there) — SaveManager.save_game() below is a synchronous
## JSON-serialize-and-write-to-disk call, and doing that on every tile
## during ordinary WASD walking was a real, reproducible stutter, not
## a perceived one. Don't add a call here that fires on every footstep
## again without first checking whether it can instead piggyback on an
## already-infrequent event (a menu closing, a transaction, the
## periodic timer) — this function itself has no debouncing of its
## own, so how often it's called IS how often the disk gets hit.
func autosave() -> void:
	if current_slot < 0 or party.is_empty():
		return
	SaveManager.save_game(party, active_party_index, current_slot, dismissed_companions)

## The tile the player was standing on right before an encounter
## started. Vector2i(-1, -1) is the "nothing to restore" sentinel —
## Overworld falls back to the map's normal spawn point when it sees
## this, which is also deliberately what a defeat leaves it at (see
## FieldEncounter._end_battle): losing sends you back to the map's
## default spawn (the village) rather than wherever you fell, since
## there's no reason a beaten, unconscious character would still be
## standing in the middle of a field.
var return_position: Vector2i = Vector2i(-1, -1)

## Per Phase 2 of the world-map plan: which LocalMapDefinition
## Overworld should load next, and where on it to spawn the player —
## overriding the map's own default '@' tile and map_definition_path.
## Empty/(-1,-1) means "use the Overworld scene's own defaults," so
## ordinary local play (never having travelled) is unaffected.
var pending_map_path: String = ""
var pending_map_spawn_tile: Vector2i = Vector2i(-1, -1)
## Remembers the player's own last position specifically on the World
## Map, so returning to it (from a local map, or after arriving
## somewhere) lands them back where they left off rather than always
## resetting to one fixed spot.
var world_map_player_position: Vector2i = Vector2i(-1, -1)
## Per the follow-up request's own reported bug: whichever
## LocalMapDefinition is actually active gets recorded here every time
## Overworld loads one — so returning from an encounter (which never
## explicitly sets pending_map_path) lands back on the SAME map the
## player actually left from, not always Giessingen. See
## Overworld._load_map_definition()'s own priority order.
var last_active_map_path: String = ""

## Follow-up request's own reported bug ("its not saving the city
## still, i always enter the game outside the city on the overworld
## map"): which city's own CityScreen is currently active, if any —
## "" whenever the player is anywhere else (Overworld, a local map, a
## Tavern/Shop — see below). Set by CityScreen._ready() every time it
## loads (covers arriving from Overworld AND returning from a
## Tavern/Shop visit, since both re-run _ready()); cleared by
## CityScreen's own _offer_leave_city() once a gate's "Leave City" is
## actually confirmed. Same "session state that also needs to survive
## a save/reload" treatment as last_active_map_path/
## world_map_player_position above — persisted via
## Character.to_save_dict()/from_save_dict() (see there), and read by
## MainMenu's Continue / CharacterMenu's Switch Character to route
## into CityScreen instead of always defaulting to Overworld, which is
## exactly what the reported bug looked like from the outside: every
## reload dropped the player outside the city walls regardless of
## where they actually left off. Unlike last_active_map_path, this
## does NOT need its own remembered position on top of it — per the
## follow-up request ("the only way to leave Ubersreik is now via the
## gates, we will always enter from the south gate"), CityScreen
## always spawns the party at the South Gate on a fresh entry (see
## CityScreen._party_start_position()), so simply knowing WHICH city
## to reload into is enough.
var last_active_city_id: String = ""

## Dungeon Encounter Screen: the currently-generated, in-progress
## dungeon instance — a plain Dictionary shaped like DungeonGenerator's
## own DungeonState (see that class's own header comment), non-empty
## for exactly as long as the party is inside a dungeon. Persisted
## across a save/reload via Character.to_save_dict()/from_save_dict()
## (through DungeonGenerator.to_save_data()/from_save_data(), which
## flattens the Vector2i/Rect2i values here into JSON-safe primitives)
## — same "persisted across relaunch" treatment as last_active_map_path
## above, per the explicit requirement that saving works while inside a
## dungeon. Explicitly cleared back to {} only on a successful Exit at
## the dungeon's own entrance (see field_encounter_screen.gd's own
## _do_exit_dungeon(), part of its exploration-mode support) — the
## dungeon itself only exists for as long as this is non-empty. Also
## doubles as (alongside pending_dungeon_theme_id below) the trigger
## FieldEncounterScreen checks to decide whether to start in exploration
## mode at all — see that script's _has_pending_exploration_map().
var dungeon_state: Dictionary = {}

## Real bug fix (user report: "the dungeon should also remember which
## doors have been opened when going back up or down"): every floor's
## own dungeon_state (rooms, door_open/encountered/chest_looted flags,
## explored fog-of-war visibility — everything DungeonGenerator.generate()
## builds and exploration mutates in place) used to live ONLY in the
## single `dungeon_state` slot above, which field_encounter_screen.gd's
## own _take_stairs_down()/_take_stairs_up() unconditionally OVERWROTE
## with a brand new DungeonGenerator.generate() call on every single
## floor change — so returning to a floor already visited this delve
## generated an entirely fresh layout, with every door closed again,
## every room "not yet encountered" again, and every bit of explored fog
## of war forgotten, rather than actually resuming where the party left
## it.
##
## Keyed by dungeon_floor (int) -> that floor's own dungeon_state
## Dictionary, populated the first time each floor is generated and
## reused (instead of regenerating) on every later revisit within the
## same dungeon delve. Since `dungeon_state` here and the copy stashed in
## this cache are the exact same Dictionary object for as long as a floor
## is the one currently being explored (Dictionaries are reference types
## in GDScript), every live mutation exploration makes to the current
## floor — opening a door, looting a chest, revealing new tiles — is
## automatically reflected in the cached copy too, with no extra
## bookkeeping needed to "save" a floor before leaving it.
##
## Reset to {} everywhere dungeon_state itself resets to {} (a genuinely
## new dungeon delve has no earlier floors to remember) — see
## _do_exit_dungeon()/_on_return_pressed()'s own party-wipe branch in
## field_encounter_screen.gd, and reset_world_state()'s own dungeon_state
## reset in this file. Deliberately NOT part of save data (same as
## dungeon_state's own sibling pending_* flags elsewhere in this file) —
## a full app-restart mid-dungeon still only resumes whichever ONE floor
## is currently active (dungeon_state's own existing, unchanged
## persistence); other already-visited floors regenerate fresh again
## after a restart, exactly like every floor already did before this fix
## — this only fixes the far more common same-session case of walking up
## and down between floors without ever closing the app.
var dungeon_floor_states: Dictionary = {}

## One-shot hand-off, same pending_* convention as pending_city_id
## below: which DungeonThemeDefinition (by theme_id, e.g. "sewer") the
## next exploration-mode entry should generate a brand new dungeon_state
## from. Set right before transitioning to FieldEncounter.tscn for a
## fresh dungeon — exploration mode is a first-class capability of the
## normal combat screen now, not a separate DungeonScreen scene, see
## field_encounter_screen.gd — (never set when re-entering an
## already-generated one — exploration mode prefers a non-empty
## dungeon_state over this whenever both are present); cleared once
## consumed.
var pending_dungeon_theme_id: String = ""

## Real bug fix (root cause of "all outdoor field combat encounters jump
## to the Goblin Fort dungeon"): FieldEncounterScreen._has_pending_
## exploration_map() used to gate purely on `not dungeon_state.is_empty()
## or pending_dungeon_theme_id != ""` — but dungeon_state is deliberately
## persisted across save/reload (see its own header comment, "so saving
## works while inside a dungeon") and only ever cleared by a successful
## Exit at the dungeon's own entrance tile. A party that leaves a dungeon
## visit unfinished (most reachable today: the Goblin Fort's entry ambush
## now spawns clear across the map from the entrance, at the treasure
## chest — see field_encounter_screen.gd's own _maybe_fire_goblin_fort_
## entry_ambush() — so a player who wins that fight and quits without
## first walking all the way back to the entrance and pressing "Leave"
## never clears dungeon_state at all) ends up with dungeon_state stuck
## non-empty for the rest of that save, permanently — and since EVERY
## field encounter, dungeon or not, transitions through the same
## FieldEncounter.tscn (see that scene's own _has_pending_exploration_map
## check at _ready()), every subsequent ordinary Overworld encounter
## trigger (random ambush, ruin/monolith/tomb tables, ambush markers,
## Gotheim's mob, etc. — none of which ever touch dungeon_state) got
## silently hijacked into resuming the abandoned dungeon instead of
## starting the intended normal fight, with no way out short of walking
## back into the dungeon and Exiting it properly.
##
## Fixed by decoupling "there's an in-progress dungeon somewhere" (which
## must keep surviving a save/reload so re-entering the dungeon's own
## entrance resumes it, chest state and all) from "the very next
## FieldEncounter.tscn load should resume it" (which must only ever be
## true when the party is actually walking through that dungeon's own
## entrance/gate tile right now). Set true ONLY by the small set of real
## dungeon-entry call sites (Overworld._offer_enter_goblin_fort_dungeon(),
## _offer_enter_cave_dungeon(), RatCatcherGuildScreen._on_quest_pressed())
## immediately before their own change_scene_to_file("FieldEncounter.tscn")
## — every other FieldEncounter.tscn transition in the game (plain
## wilderness combat, ambush markers, social encounters, wandering
## monster tables) never touches this, so none of them can be hijacked by
## a stale dungeon_state any more. Consumed (reset to false) the moment
## FieldEncounterScreen._ready() actually reads it, so it's a genuine
## one-shot per entry, same convention as pending_dungeon_theme_id.
## Deliberately NOT part of save data (same as every other pending_* flag
## here) — a mid-transition crash simply means the next load lands on the
## Overworld normally instead of resuming, never the other way around.
var dungeon_entry_requested: bool = false

## New City Screen feature: same "pending" convention as
## pending_map_path above, but for the new image-map City Screen
## instead of a tile-grid LocalMapDefinition — which city's own
## CityLocationDefinition data (e.g. "ubersreik") the next CityScreen
## scene should load. Set by Overworld._offer_enter_location() right
## before changing to the location's own city_screen_scene_path;
## cleared by CityScreen._ready() once read.
var pending_city_id: String = ""
## New Tavern Screen feature: same "pending" convention as
## pending_city_id above, but for returning FROM the Tavern scene back
## TO the city screen the player entered it from — set by CityScreen's
## own _enter_tavern() (the "Stay" radial action on a tavern-category
## POI) right before changing to Tavern.tscn, and read (into
## pending_city_id, so CityScreen's existing _ready() logic just works
## unchanged) by TavernScreen._on_close() right before changing back.
var pending_tavern_city_id: String = ""
## New City Shop feature (follow-up request: "copy the giessingen shop
## and put it into ubersreik... allow access via travel in the city"):
## same three-field "pending" hand-off as Tavern above, but for the
## existing shared Shop.tscn (previously only ever reached from
## Overworld's Giessingen shopkeeper tile, always as a Village-tier
## shop). Set together by CityScreen's own _enter_shop() (the "Enter"
## radial action on a shop-category POI) right before changing to
## Shop.tscn:
## - pending_shop_city_id: which CityScreen to return to on Close —
##   ShopScreen reads this once into its own _return_city_id (NOT
##   pending_city_id directly, unlike Tavern — Shop.tscn is reachable
##   from two different places, Overworld's tile AND a city's radial
##   menu, so it needs to remember which one for itself rather than
##   assuming every visit came from a city).
## - pending_shop_settlement_tier / pending_shop_settlement_name:
##   override ShopScreen's own "Village"/"the village" defaults (still
##   what a Giessingen visit gets, since Overworld's shopkeeper-tile
##   entry point never touches these) with the entered city's own
##   tier/name — see UbersreikRoadNetwork-adjacent city_screen.gd's own
##   _enter_shop() for why "City" is hardcoded there for now (single
##   city implemented so far).
var pending_shop_city_id: String = ""
var pending_shop_settlement_tier: String = ""
var pending_shop_settlement_name: String = ""
## Cordelia's Apothecary feature (spec: "hook up Cordelia's Apothecary in
## Ubersreik. She need a shop screen that will only sell Healing Draught,
## Faxtoryll, Salwort and Vitality Draught. No Repairing either."): the
## specific CityLocationDefinition.location_name of whichever shop
## _enter_shop() just sent the player into — set unconditionally for
## EVERY shop visit (not just Cordelia's), same "read once, then clear"
## convention as pending_shop_settlement_name above. ShopScreen reads
## this into its own _shop_location_name / is_apothecary — the general
## store still behaves exactly as before for any other shop name; only
## "Cordelia's Apothecary" specifically gets the restricted-stock,
## always-fully-stocked, no-Weapons/Armour/Repair-tabs treatment.
var pending_shop_location_name: String = ""
## Follow-up request ("add The Exploding Pig as the 2nd Tavern, and make
## the tavern screens distinct by adding the tavern name to the Tavern
## (- Name) title"): same "read once, then clear" convention as
## pending_shop_settlement_name above — set by CityScreen's own
## _enter_tavern() (the "Stay" radial action on a tavern-category POI)
## right alongside pending_tavern_city_id, and read into TavernScreen's
## own local field in _ready(), so a second tavern's own visit shows its
## own real name instead of every tavern reading as a generic "The
## Tavern".
var pending_tavern_name: String = ""
## Rat Catcher's Guild feature (spec: "hook up the Rat Catcher Guild in
## Ubersreik, and give him a Quest option that will trigger the Dungeon
## encounter"): same three-field-minus-one "pending" hand-off as Tavern
## above — set by CityScreen's own _enter_guild() (the "Talk" radial
## action on a guild-category POI) right before changing to
## RatCatcherGuildScreen.tscn, and read (into pending_city_id, so
## CityScreen's existing _ready() logic just works unchanged) by
## RatCatcherGuildScreen._on_close() right before changing back. No
## separate "which guild" name field is needed yet, unlike Tavern's
## pending_tavern_name — there's only the one guild so far.
var pending_guild_city_id: String = ""

## Crafting orders (p.301-302's Item Qualities/Flaws, per the request:
## "add a Crafting page to shops, allowing characters to order Crafted
## Weapon's or Armor with any amount of any quality... Crafting time
## will be 2 days per quality"): each entry is
## {"order_id": int, "character_name": String, "item_type":
## "weapon"/"armour", "item_name": String, "ready_at_minutes": int,
## "quality_count": int}. `character_name` (not a Character reference)
## so this stays plain-JSON-serializable for save/load, same reasoning
## Character.to_save_dict() already gives for storing race/career by
## name rather than embedding the resource. `ready_at_minutes` is an
## absolute time_minutes_total() reading (see that function's own
## comment on why it's the correct value to compare across day/year
## boundaries) rather than a day-of-year, so an order placed at, say,
## 6pm and requiring 2 days is genuinely ready at 6pm two days later,
## not at midnight.
##
## Per the follow-up request ("make it so User needs to pick up items
## when crafting time is finished, rather then appearing in
## inventory"): reaching ready_at_minutes no longer delivers the item
## on its own — it only means the order CAN be collected. The order
## stays in this array (still "pending" in the sense of "not yet in
## anyone's inventory") until collect_craft_order() is actually called,
## which only happens from the Crafting tab's own "Collect" button once
## the player is back in a shop with that character. This mirrors how a
## real commission works — a finished order sits at the shop until you
## come pick it up, it doesn't teleport into your pack the moment the
## smith finishes it.
var pending_craft_orders: Array = []

## Monotonic id source for pending_craft_orders entries — needed so
## collect_craft_order() can unambiguously target ONE specific order
## even if a character has two outwardly-identical orders queued (same
## item, same Quality count, placed at different times). Persisted
## alongside pending_craft_orders (see Character.to_save_dict()/
## from_save_dict()) so ids stay unique across a save/load, not just
## within one play session.
var _next_craft_order_id: int = 1

## Queues one Crafting order — called by ShopScreen's own Crafting tab
## once payment has already been deducted from the party purse.
func queue_craft_order(character_name: String, item_type: String, item_name: String, quality_count: int) -> void:
	pending_craft_orders.append({
		"order_id": _next_craft_order_id,
		"character_name": character_name,
		"item_type": item_type,
		"item_name": item_name,
		## 2 days per Quality (p.301-302's Item Quality count, not a
		## per-Quality-TYPE count — a Durable 2 + Fine order is 3
		## Qualities total, 6 days, same count price_multiplier already
		## uses), per the request's own "Crafting time will be 2 days
		## per quality."
		"ready_at_minutes": time_minutes_total() + quality_count * 2 * 24 * 60,
		"quality_count": quality_count,
	})
	_next_craft_order_id += 1

## True once an order's own lead time has actually elapsed — the
## Crafting tab uses this to decide whether to show a "ready in N days"
## countdown or a "Collect" button for a given pending order.
func is_craft_order_ready(order: Dictionary) -> bool:
	return int(order.get("ready_at_minutes", 0)) <= time_minutes_total()

## Called from the Crafting tab's own "Collect" button — delivers ONE
## specific finished order (matched by its own order_id, not just by
## character/item name, so two similar orders can't be confused with
## each other) into the ordering character's inventory and removes it
## from the pending queue. Returns false (no-op) if the order can't be
## found, isn't actually ready yet, or its own character has since left
## the party — the button itself is only ever shown when none of those
## apply, but this stays a safe standalone entry point regardless.
func collect_craft_order(order_id: int) -> bool:
	for i in range(pending_craft_orders.size()):
		var order: Dictionary = pending_craft_orders[i]
		if int(order.get("order_id", -1)) != order_id:
			continue
		if not is_craft_order_ready(order):
			return false
		var recipient: Character = null
		for member in party:
			if member.character_name == order.get("character_name", ""):
				recipient = member
				break
		if recipient == null:
			return false
		recipient.inventory.append(String(order.get("item_name", "")))
		pending_craft_orders.remove_at(i)
		return true
	return false
## Temple of Shallya feature ("hook up The Temple of Shallya in
## Ubersreik, copy the priestess from Giessingen"): same "pending"
## hand-off as Tavern/Guild above, but for the existing shared
## Healer.tscn/healer_screen.gd — the Shallyan Priest service Giessingen
## already reaches from its own map tile (see overworld.gd's
## priest_coords). "Copy the priestess" means reusing that same
## screen/role (this project's NPCs are role-based, not individually
## named — see npc_flavor_text.gd's own header comment — so there's no
## separate Character resource to actually duplicate), not building a
## second one. Set by CityScreen's own _enter_temple() (the "Enter"
## radial action on The Temple of Shallya specifically) right before
## changing to Healer.tscn; read back into pending_city_id by
## healer_screen.gd's own _on_close() right before it changes back —
## empty means "reached via Giessingen's own map tile," which keeps
## returning straight to Overworld.tscn exactly as it always has.
var pending_healer_city_id: String = ""
## New City Screen feature: remembers where the party's own group
## token was left standing in each city (city_id -> normalized
## Vector2 map_position) — keyed by city rather than a single value (a
## player could in principle visit more than one city screen across a
## save). Session-only, same as every other field on this page — not
## written to the save file (see autosave()'s own comment).
##
## Follow-up request ("the only way to leave Ubersreik is now via the
## gates, we will always enter from the south gate"): this now ONLY
## covers same-session round trips within a single city visit — e.g.
## stepping into a Tavern/Shop from wherever the party was standing and
## coming back to that exact spot — not a fresh entry into the city
## from Overworld or a save/reload, which always start at the South
## Gate regardless of what's remembered here (see
## _party_start_position()). CityScreen's own _offer_leave_city()
## erases this city's own entry once a gate's "Leave City" is
## confirmed, so the NEXT fresh entry has nothing left to fall back on
## and genuinely starts at the South Gate every time, not just the
## first time.
var city_player_positions: Dictionary = {}

## Enemy/Monster Difficulty Tier (0-5), per the request: set by the map
## (Overworld._trigger_encounter, via its own get_difficulty_tier_at())
## right before handing off to FieldEncounter, which reads this once at
## _start_encounter() to scale every spawned monster's characteristics
## — see DifficultyTiers.apply_tier_bonus(). Session-only, same
## reasoning as return_position: it describes "where the fight is
## happening," not persistent character state, so it isn't saved.
## Per the request: the combat screen's own ON/OFF toggle buttons
## (Dual Wield's queued-for-next-attack toggle, the Arcane magic
## Colour Effect display toggle) should remember whatever the player
## last set them to, even between different battles — rather than
## every new FieldEncounter always resetting Dual Wield off and
## Colour Effect on. FieldEncounterScreen reads these when a fresh
## encounter starts and writes back to them the moment either toggle
## changes (see _on_toggle_dual_wield and the Colour Effect button's
## own callback). Session-only, same as everything else on this page
## — not written to the save file.
var dual_wield_toggle_remembered: bool = false
var magic_colour_effect_remembered: bool = true

var current_field_difficulty_tier: int = 0

## Per the request ("hide monster names with ??? in the roll log"):
## monster names the party has actually identified, keyed by
## MonsterDefinition.monster_name. A monster's own automatic rolls in
## the overworld roll log overlay (see Overworld._roll_ambush_detection)
## show "???" instead of its real name until this dict gains an entry
## for it -- which happens the first time the party actually spots it
## (beats its Stealth in the ambush-detection opposed Test). Session-
## only, same as current_field_difficulty_tier above -- not written to
## the save file.
var identified_monster_names: Dictionary = {}

## As current_field_difficulty_tier, but for Social Combat (per the
## request: "we have difficulty level in combat, let's add it to social
## encounters too") — set by Overworld._on_social_marker_clicked(), via
## the same map-based get_difficulty_tier_at() field encounters use, but
## computed from the social marker's own tile rather than the player's
## current position (the marker can sit unclicked for a while, and the
## player may have wandered elsewhere by the time they finally click
## it — the encounter is happening where the marker is, not where the
## player happens to be standing). Kept as its own separate field rather
## than reusing current_field_difficulty_tier so a social encounter can
## never silently inherit a stale value left over from the last fight,
## or vice versa. Read once by SocialEncounterScreen._build_npc_roster()
## via DifficultyTiers.apply_social_npc_tier_bonus(). Session-only, same
## reasoning as current_field_difficulty_tier — it isn't saved.
var current_social_difficulty_tier: int = 0

## As current_field_difficulty_tier, but for which monster names a
## themed sub-area (a goblin fort, a bear's cave) restricts encounters
## to — empty means "use the map's full random pool," per
## MonsterDatabase.random_monster_from(). Set alongside the tier, same
## session-only reasoning.
var current_field_monster_pool: Array[String] = []
## Location-appropriate spawning, per the request: which habitat tag
## (e.g. "forest", "cave") the current field encounter is happening
## in, read from Overworld.get_habitat_at() the same way the tier and
## pool are. Empty means no habitat preference.
var current_field_habitat: String = ""
## Per the day/night & light-source-in-combat request: whether the
## battle about to start is genuinely dark — night time
## (get_night_darkness() > 0) or standing on a LocalMapDefinition
## marked is_dark_location. FieldEncounter.tscn has no other way to
## see the local map's own is_dark_location flag (that lives only in
## Overworld's own current_map_def local variable), so it's captured
## here at the scene hand-off — see Overworld._capture_battle_terrain_
## snapshot() — the same way current_field_habitat etc already are.
var pending_battle_is_dark: bool = false
## True only for a genuinely pitch-black is_dark_location map (a
## windowless dungeon/cave with no light of its own), as opposed to an
## ordinary outdoor night, which always has at least faint starlight/
## moonlight. The Night Vision Talent/Trait's own card text requires
## "at least a faint source of light" to work; Dark Vision needs
## nothing at all. Distinguishing the two lets an ordinary night fight
## work fine for a Night Vision character with no lantern of their
## own, while a truly lightless dungeon room still requires one.
var pending_battle_is_pitch_black: bool = false
## Per the request: after a field encounter, the player must move at
## least 12 tiles before another one can trigger — counts up from 0
## on every step (reset to 0 right when an encounter starts), checked
## in Overworld._on_player_moved() before the random encounter roll is
## even attempted. Lives here rather than as a local Overworld
## variable because Overworld itself is freed and rebuilt fresh each
## time the game changes to and from FieldEncounter.tscn — a plain
## script-local counter would silently reset every single fight.
var tiles_since_last_encounter: int = 999   ## starts already-cooled-down, so the very first steps of a fresh game aren't artificially safe
const ENCOUNTER_COOLDOWN_TILES := 12
## Per the ambush-detection request: set by Overworld right before
## handing off to FieldEncounter, in two different situations — a
## failed detection roll (combat starts immediately, but must use the
## exact group the roll was made against, not a fresh one) and a
## successful ambush (the player clicked the marker; same requirement,
## plus every enemy starts Surprised). Both cleared by FieldEncounter
## the moment they're read, so a later, ordinary encounter triggered
## some other way doesn't accidentally inherit stale state.
var pending_encounter_monster_names: Array[String] = []
var pending_encounter_is_player_ambush: bool = false
## Combat Encounter rework (per the request): a 9-entry passability
## snapshot (Array[bool], index (dy+1)*3+(dx+1) for dy,dx in -1..1,
## dy=dx=0 being the player's own tile) for the 3x3 field-map tiles
## centered on the player at the moment an encounter starts — set by
## Overworld._capture_battle_terrain_snapshot() right before the scene
## change to FieldEncounter.tscn, since that scene change destroys the
## Overworld instance (and its map/tile data) that knows this. Consumed
## by BattleGrid.generate_from_terrain_snapshot() to build the battle
## grid (see BattleGrid.COLS/ROWS). Empty means "no snapshot was captured" (e.g. a
## dev/test path entering FieldEncounter some other way) — BattleGrid
## falls back to an all-open grid in that case rather than failing.
var pending_battle_terrain: Array = []
## Combat Encounter rework, Phase 2: a parallel 9-entry snapshot (same
## index convention as pending_battle_terrain above), true where that
## source tile is forest ("T"/"f"). Used to mark BattleGrid squares as
## cover for the -10 Soft Cover penalty against ranged attacks — set
## alongside pending_battle_terrain by the same
## Overworld._capture_battle_terrain_snapshot() call. Empty means "no
## cover anywhere," the same safe-fallback convention as the terrain
## snapshot.
var pending_battle_cover: Array = []
## Per the follow-up request ("when the battlemap includes a large
## section of greyed out cells due to overworld map water, fill this in
## with the same tiles as overworld water rather then Grey tiles"): a
## third parallel 9-entry snapshot (same index convention as the two
## above), true where that source tile is specifically WATER (a strict
## subset of pending_battle_terrain's own true entries, which also
## covers buildings — a building block still renders as the old plain
## wall colour, only water gets real water tiles). Set alongside the
## other two by the same Overworld._capture_battle_terrain_snapshot()
## call. Empty means "no water anywhere," same safe-fallback convention.
var pending_battle_water: Array = []
## Per the request: a successful Perception check on a social marker
## reveals which NPC/encounter is waiting there — set by Overworld
## right when the marker spawns (not left to a fresh random roll),
## so whatever was revealed is guaranteed to be the encounter that
## actually happens if the marker is later clicked. Empty means "let
## SocialEncounterScreen roll its own," the same as before this system
## existed.
var pending_social_encounter_name: String = ""
## Per the request: Wilderness Events now resolve on their own real
## screen (a full scene transition), rather than as a text popup on
## top of the World Map — this carries the actual event data across.
var pending_wilderness_event: Dictionary = {}
## Per the request: set before transitioning to CharacterCreation.tscn
## from the Party Companion Maker NPC — tells that screen to skip the
## Continue/new-game flow entirely and, once the new character is
## actually finished, add them straight to the current real party
## (up to the real 4-member cap) instead of starting a fresh game.
var pending_companion_creation: bool = false
## Per the request: a Wilderness Event interrupting a World Map
## journey was permanently cancelling it — the route and remaining
## days only ever existed as local variables inside the travel loop,
## which is destroyed the moment the scene changes for the event
## itself. These persist the remaining journey here instead, so
## Overworld can resume it automatically on return, the same way the
## journey would have continued if nothing had interrupted it.
## Empty route means "no journey to resume."
var pending_resume_travel_route: Array = []
var pending_resume_travel_days_remaining: int = 0
var pending_resume_travel_destination_name: String = ""
## Per the request: carries which QuestDefinition (by quest_id, loaded
## from res://data/quests/<quest_id>.tres by convention) and which of
## its own QuestNPCDefinition entries (by npc_id) the new scripted-NPC
## encounter screen should show.
var pending_quest_id: String = ""
var pending_quest_npc_id: String = ""
## Per the request: a real monster-spawn override, read by
## FieldEncounter — keyed by monster_name (matching
## MonsterDefinition.monster_name), so any monster spawned under that
## name in the next encounter starts at the given Wounds/Conditions
## instead of full health. Cleared the moment the encounter actually
## consumes them, same one-shot pattern as pending_encounter_monster_names.
var pending_encounter_wound_override: Dictionary = {}
var pending_encounter_condition_override: Dictionary = {}
## Per the follow-up request: the NPC's name/gender and which
## situation/opening-flavor variant was rolled are now ALSO decided
## the moment the marker spawns (not left to a fresh roll when the
## encounter actually starts) — for the same reason
## pending_social_encounter_name exists: whatever a Perception check
## reveals must be exactly what actually happens.
var pending_social_npc_name: String = ""
var pending_social_npc_gender: String = ""
var pending_social_situation_index: int = -1
var pending_social_opening_flavor_index: int = -1

## The Goblin Fort's lootable chest, per the request — one specific,
## hand-placed container, not a random loot system. Originally a
## session-only overworld tile (this comment's own earlier history);
## per the Goblin Fort Dungeon rework, the chest now lives at
## dungeon_state["chest_pos"] inside the fort's own Dungeon Map, and
## its locked/looted/trap_spotted flags live directly on dungeon_state
## itself (see field_encounter_screen.gd's chest functions) rather
## than here — dungeon_state is freshly regenerated every time the
## party re-enters the fort (cleared on exit by _do_exit_dungeon()),
## which naturally gives the chest a fresh lock/stock every visit,
## replacing the old fixed-8am-reset-timer mechanic outright.

## Per the request: set right before the Village Elder quest's own
## forced idol ambush, so FieldEncounter knows THIS specific defeat
## (not any other) should cost the player the idol and all their coin.
var pending_idol_ambush: bool = false
## Coin stashed in the chest from a lost idol-ambush fight — added on
## top of whatever the chest's own next loot roll produces, then
## cleared. Per the request: "move the coins to the chest and add them
## to any already in there."
var goblin_fort_chest_stashed_bp: int = 0
var goblin_fort_chest_stashed_ss: int = 0
var goblin_fort_chest_stashed_gc: int = 0
## Per the request: set by Overworld right before transitioning to
## SocialEncounterScreen for a Talk with the Village Elder — a
## hand-written story sequence, not a random SocialEncounterDefinition,
## so it needs its own signal rather than reusing pending_social_*.
var pending_elder_encounter: bool = false

## Minutes since midnight (0-1439), advanced by the overworld as the
## player moves (see Overworld._on_player_moved). Starts at 8am — a
## reasonable time for an adventurer to set out.
var time_minutes: int = 8 * 60
## Per the request: real Movement-based travel time needs to accrue
## fractionally across several tile-steps (Movement 4 means 4 tiles
## per whole minute, i.e. 0.25 minutes per single tile-step) — this
## carries the leftover fraction between steps so time_minutes itself
## only ever advances by whole minutes, without losing precision by
## rounding every single step.
var time_minutes_fraction: float = 0.0
## Per the request: the World Map enforces a real 8-hour-per-day
## travel cap (one Stage, matching the source Travel Stages table) —
## tracks real hours travelled since the last full night's rest.
## Reset to 0 by a genuine 8+ hour Camp sleep (see camp_screen.gd's
## _on_sleep()), not by any lesser rest.
var world_map_hours_since_rest: float = 0.0
## Shown once per over-threshold day, not every single tile, so the
## player gets one clear warning rather than being nagged constantly.
var world_map_fatigue_warned_today: bool = false
## Fatigue for pushing on past the 8-hour cap is applied once per
## day of doing so, not once per tile — a single clear consequence,
## not a flood of stacking penalties for the same decision.
var world_map_fatigue_applied_today: bool = false

## Camp rework, per the request: whether the party is currently
## somewhere it makes sense to hunt/set traps for food — Camp Endeavour
## rework gates Hunting/Trap on this. Set by Overworld._open_camp()
## right before switching to the Camp scene (Overworld.is_safe_area_at()
## already answers exactly this question — "inside a defined Safe Area,
## e.g. a village" — for the tile the player is standing on; Camp itself
## has no access to the overworld map once the scene has changed, so
## this is computed once and carried across). Defaults true so opening
## Camp.tscn directly (tests, or any future non-Overworld entry point)
## doesn't unexpectedly lock out Hunting/Trap with no explanation.
var camp_is_outdoors: bool = true

## Imperial Calendar tracking, per the request — synced to the clock
## above, so the day genuinely ticks over exactly when time_minutes
## wraps past midnight rather than drifting independently of it.
## day_of_year is 0-indexed into WarhammerCalendar's own 400-day year;
## a fresh character starts at CHARACTER_CREATION_START_DAY, which
## decodes to Sigmarzeit 1 — Marktag, per the request.
var imperial_year: int = 2512
var day_of_year: int = WarhammerCalendar.CHARACTER_CREATION_START_DAY

func get_time_string() -> String:
	var h := int(time_minutes / 60.0) % 24
	var m := time_minutes % 60
	return "%02d:%02d" % [h, m]

## The Imperial Calendar's own display string for the current day,
## e.g. "Marktag, 1 Sigmarzeit 2512" — or, on an intercalary holiday,
## just its name plus the year (it has no weekday or day-of-month of
## its own to show).
func get_date_string() -> String:
	var info := WarhammerCalendar.decode(day_of_year)
	if info.is_intercalary:
		return "%s, %d" % [info.holiday_name, imperial_year]
	return "%s %d" % [info.display_string(), imperial_year]

## Per the follow-up request: "make all night times much darker with
## starker transition to day time, so its hard to see" — the
## transition windows are compressed from a full hour down to 30
## minutes each (07:00-07:30 dawn, 20:30-21:00 dusk), so day and
## night feel like two distinct states with a brief, noticeable
## hand-off between them rather than a long gradual fade. Full
## daylight (0.0 darkness) still holds flat across 07:30-20:30, and
## full night (NIGHT_DARKNESS_MAX) holds flat across 21:00-07:00.
const DAWN_START_MINUTES := 7 * 60
const DAWN_END_MINUTES := 7 * 60 + 30
const DUSK_START_MINUTES := 20 * 60 + 30
const DUSK_END_MINUTES := 21 * 60
## Per the follow-up request: "much darker... so its hard to see" —
## raised well above the old 0.7 (which only read as a bit darker
## than a daytime shadow, see WALL_SHADOW_COLOR in overworld.gd).
## 0.92 leaves the map genuinely hard to make out at night without
## going fully to a solid black screen, which is what the new light-
## source system (Lantern/Candle) exists to push back against.
const NIGHT_DARKNESS_MAX := 0.92

## Per the light-source request ("dark locations like underground caves
## and ruin battle maps"): the fixed, time-of-day-independent tint a
## LocalMapDefinition.is_dark_location map uses for its NightOverlay
## instead of get_time_of_day_color() — a cave is exactly as dark at
## high noon as at midnight. Deliberately reuses NIGHT_DARKNESS_MAX (the
## same alpha true night reaches) and a similar neutral-dark hue rather
## than a separate tunable, so "dark location" and "deep night" read as
## the same intensity of darkness, only without the day/night hue cycle
## layered on top.
func get_dark_location_color() -> Color:
	return Color(0.045, 0.05, 0.08, NIGHT_DARKNESS_MAX)

func get_night_darkness() -> float:
	var t := time_minutes
	if t >= DAWN_END_MINUTES and t <= DUSK_START_MINUTES:
		return 0.0
	if t > DAWN_START_MINUTES and t < DAWN_END_MINUTES:
		var progress: float = float(t - DAWN_START_MINUTES) / float(DAWN_END_MINUTES - DAWN_START_MINUTES)
		return lerp(NIGHT_DARKNESS_MAX, 0.0, progress)
	if t > DUSK_START_MINUTES and t < DUSK_END_MINUTES:
		var progress: float = float(t - DUSK_START_MINUTES) / float(DUSK_END_MINUTES - DUSK_START_MINUTES)
		return lerp(0.0, NIGHT_DARKNESS_MAX, progress)
	## Everything else: 21:00-07:00 (through midnight), the flat
	## full-night core.
	return NIGHT_DARKNESS_MAX

## Per the request: real light-COLOR changes across the day (not just
## darkness), keyed to the exact 12 named periods/colors from the
## reference chart the user provided (Midnight/Wee Hours/Dawn/Sunrise/
## Morning/Noon/Afternoon/Evening/Sunset/Dusk/Twilight/Night). Each
## entry is [minute_of_day, name_or_null, Color] — Color.rgb is the
## tint hue for that moment, Color.a is how strongly it's blended over
## the scene. `name_or_null` is this entry's period label, or null for
## an in-between "hold" keyframe that exists purely to shape the curve
## (see below) without introducing a new named period.
## `get_time_of_day_color()` linearly interpolates between whichever
## two entries bracket the current minute, so hue always transitions
## smoothly; `get_time_of_day_period_name()` reads the name field
## directly instead of a second, positionally-coupled array, so the
## two can never drift out of sync with each other.
##
## Per the follow-up request's "much darker... starker transition":
## night alpha is raised well above the old chart (up to ~0.90-0.92,
## matching NIGHT_DARKNESS_MAX) and, critically, the ramp into/out of
## that darkness is now compressed into the same 30-minute windows
## get_night_darkness() uses (07:00-07:30 dawn, 20:30-21:00 dusk) via
## a flat "hold" keyframe placed one minute before each ramp starts —
## instead of the old gradual multi-hour fade (05:40 Dawn -> 09:00
## Morning), day and night now read as two distinct states with a
## brief, noticeable hand-off, while still keeping the full 12-period
## hue journey (Sunrise/Evening/Sunset warmth, etc.) for daytime and
## the deep night core. The first (minute 0) and last (minute 1440)
## entries share the same Midnight color, closing the loop cleanly at
## the wrap-around.
const TIME_OF_DAY_KEYFRAMES := [
	[0,    "Midnight",  Color(0.040, 0.045, 0.075, 0.90)],   ## 00:00 Midnight
	[150,  "Wee Hours", Color(0.090, 0.100, 0.170, 0.92)],   ## 02:30 Wee Hours (deepest night)
	[419,  null,        Color(0.090, 0.100, 0.170, 0.92)],   ## 06:59 hold — stays fully dark right up to dawn
	[420,  "Dawn",      Color(0.550, 0.420, 0.420, 0.55)],   ## 07:00 = DAWN_START, stark ramp begins
	[450,  "Sunrise",   Color(0.950, 0.620, 0.450, 0.16)],   ## 07:30 = DAWN_END, ramp ends, near-day
	[540,  "Morning",   Color(0.953, 0.867, 0.667, 0.07)],   ## 09:00
	[720,  "Noon",      Color(0.961, 0.878, 0.110, 0.02)],   ## 12:00
	[900,  "Afternoon", Color(0.878, 0.757, 0.353, 0.05)],   ## 15:00
	[1080, "Evening",   Color(0.906, 0.604, 0.447, 0.13)],   ## 18:00
	[1200, "Sunset",    Color(0.933, 0.420, 0.353, 0.28)],   ## 20:00
	[1229, null,        Color(0.933, 0.420, 0.353, 0.28)],   ## 20:29 hold — stays bright right up to dusk
	[1230, "Dusk",      Color(0.420, 0.320, 0.420, 0.55)],   ## 20:30 = DUSK_START, stark ramp begins
	[1260, "Twilight",  Color(0.090, 0.100, 0.170, 0.90)],   ## 21:00 = DUSK_END, ramp ends, near-full night
	[1350, "Night",     Color(0.050, 0.055, 0.085, 0.92)],   ## 22:30 full deep night
	[1440, "Midnight",  Color(0.040, 0.045, 0.075, 0.90)],   ## wraps to 00:00 Midnight
]

func get_time_of_day_color() -> Color:
	var t := time_minutes
	var kf := TIME_OF_DAY_KEYFRAMES
	for i in range(kf.size() - 1):
		var m0: int = kf[i][0]
		var m1: int = kf[i + 1][0]
		if t >= m0 and t <= m1:
			var progress: float = float(t - m0) / float(max(m1 - m0, 1))
			return (kf[i][2] as Color).lerp(kf[i + 1][2], progress)
	return kf[0][2]

## Per the request: reads the name straight off whichever keyframe is
## currently in effect (the latest one at or before the current
## minute that actually carries a name — "hold" keyframes are null and
## skipped), rather than a second array kept in sync by hand.
func get_time_of_day_period_name() -> String:
	var t := time_minutes
	var kf := TIME_OF_DAY_KEYFRAMES
	var result: String = kf[0][1]
	for i in range(kf.size() - 1):
		var minute: int = kf[i][0]
		var period_name = kf[i][1]
		if t >= minute and period_name != null:
			result = period_name
	return result

## Per the request: the player's character covers their own Movement
## in tiles within 1 minute of game time — so a single tile takes
## 1/Movement minutes. The clock only tracks whole minutes, so any
## fraction always rounds up (never down, and never silently dropped)
## — e.g. Movement 4 means a quarter-minute per tile, which rounds up
## to a full minute passing for every tile stepped. Falls back to the
## old flat 2-minute rate if there's no real player character to read
## Movement from yet (a defensive fallback, not the normal path).
## Per the request: real Movement-based tile time — a character with
## Movement 4 covers 4 tiles in 1 minute (0.25 minutes per tile-step),
## not a flat "1 minute per tile" regardless of how fast they actually
## are. Per the request: uses the party's own slowest member, not just
## the active character — a group can only move as fast as its
## slowest member allows, matching the same real rule the World Map's
## own travel-day calculation now uses too. Movement is explicitly
## floored here before use — per the request, a fractional Movement
## value from a penalty (e.g. 3.5) always rounds down (3), never up or
## to nearest.
func minutes_per_tile_fraction() -> float:
	if player_character == null:
		return 0.5
	var slowest: int = 999
	for member in party:
		slowest = mini(slowest, floori(member.get_movement()))
	var movement: int = maxi(slowest if slowest < 999 else floori(player_character.get_movement()), 1)
	return 1.0 / float(movement)

## Per the request: the Imperial Calendar day advances exactly when
## the clock wraps past midnight, never independently of it — a
## single tick from 23:58 to 00:00 (say) is also the moment
## day_of_year (and, once every 400 days, imperial_year) rolls over.
func advance_time_one_step() -> void:
	time_minutes_fraction += minutes_per_tile_fraction()
	while time_minutes_fraction >= 1.0:
		time_minutes_fraction -= 1.0
		time_minutes += 1
		if time_minutes >= 24 * 60:
			time_minutes -= 24 * 60
			day_of_year += 1
			if day_of_year >= WarhammerCalendar.DAYS_PER_YEAR:
				day_of_year = 0
				imperial_year += 1

## Per the request: a generic real-minutes advance (for the World
## Map's own travel-stage-based time cost, which isn't a flat "1
## minute per tile" like local-map movement) — correctly wraps
## through midnight and year-end exactly like advance_time_one_step()
## above, just for an arbitrary whole number of minutes at once
## rather than one fractional tile-step.
## A real, monotonically-increasing absolute time value in minutes —
## day_of_year and imperial_year folded in alongside time_minutes, so
## comparing two readings of this always correctly reflects real
## elapsed time even across a day or year boundary. Used by the
## scripted-NPC quest system's own real time limits (an NPC's crisis
## resolving badly on its own after N real minutes), and generally
## useful anywhere "how much real time has passed since X" matters.
func time_minutes_total() -> int:
	return (imperial_year * WarhammerCalendar.DAYS_PER_YEAR + day_of_year) * 24 * 60 + time_minutes

func advance_minutes(n: int) -> void:
	if n <= 0:
		return
	time_minutes += n
	while time_minutes >= 24 * 60:
		time_minutes -= 24 * 60
		day_of_year += 1
		if day_of_year >= WarhammerCalendar.DAYS_PER_YEAR:
			day_of_year = 0
			imperial_year += 1
	## Per the request: a generic ticking-clock system — checked here
	## so every real time-advancing call in the game triggers it
	## automatically, rather than needing each call site to remember.
	if player_character != null:
		player_character.check_quest_timelines()
	## Per the follow-up request ("make sure Consume Alcohol and drunk
	## mechanic are really implemented"): same "checked here so every
	## real time-advancing call triggers it automatically" reasoning —
	## the sober-up/hangover arc's own wording ("after not drinking for
	## an hour," "wear off after 10-SL hours") is written in real
	## elapsed hours, so it has to fire for however time actually
	## passed (travel, Sleep, camp), not just a dedicated "wait" action.
	## See Character.tick_alcohol_hours()'s own comment for the full
	## mechanic and its one documented precision simplification.
	var consume_alcohol_def: SkillDefinition = GameData.skill_db.find_by_name("Consume Alcohol") if GameData != null and GameData.skill_db != null else null
	if consume_alcohol_def != null:
		var now: int = time_minutes_total()
		for member in party:
			member.tick_alcohol_hours(n, now, consume_alcohol_def)
	## Cauterise (Lore of Fire): a target who failed their Cool Test by
	## 6+ SL wakes back up "1d10 hours later" -- same "checked here so it
	## counts down for however time actually passes" reasoning as the
	## alcohol timer just above. No skill-def guard needed, it's just a
	## countdown. See Character.tick_cauterise_recovery()'s own comment.
	for member in party:
		member.tick_cauterise_recovery(n)
	## Crafting orders (see queue_craft_order() above) are no longer
	## auto-delivered on time advancing — per the follow-up request, the
	## player has to actually visit the shop and press "Collect" (see
	## GameState.collect_craft_order()) once an order's own
	## ready_at_minutes has passed. Nothing to do here any more; time
	## passing just makes is_craft_order_ready() eventually return true.

## Per Phase 2 of the world-map plan: advances the calendar by a whole
## number of days directly (for multi-day World Map travel), rather
## than one tile-step at a time. time_minutes is untouched — arriving
## after a multi-day journey doesn't reset the clock to midnight, it
## just adds whole days on top of whatever time of day it already was.
func advance_days(n: int) -> void:
	if n <= 0:
		return
	day_of_year += n
	while day_of_year >= WarhammerCalendar.DAYS_PER_YEAR:
		day_of_year -= WarhammerCalendar.DAYS_PER_YEAR
		imperial_year += 1
	if player_character != null:
		player_character.check_quest_timelines()

## Creates a default starting character if none exists yet, so the
## overworld always has someone to control. Real character creation
## (via the CharacterCreation scene) should set `player_character`
## directly before entering the overworld, in place of calling this.
func ensure_player_character() -> void:
	if player_character != null:
		return
	var human: RaceDefinition = GameData.find_race("Human")
	var soldier: CareerDefinition = GameData.find_career("Soldier")
	## Advance Characteristics: spread across Soldier's own Tier 1
	## (Brass) Advance Scheme keys — weapon_skill/toughness/willpower —
	## same as any real Soldier creation would offer, per
	## CharacterCreator.apply_advance_characteristics.
	player_character = CharacterCreator.create_character(
		"Wanderer", human, soldier,
		{"weapon_skill": 2, "toughness": 2, "willpower": 1}
	)
	player_character.allegiance = "ally"
	player_character.equipped_weapon = "Sword"
	player_character.equipped_armour = ["Leather Jack"]

## Called whenever a character is freshly created or loaded from a save,
## so a leftover return_position from a previous character/session in
## the same run can't leak into an unrelated playthrough.
func reset_world_state() -> void:
	return_position = Vector2i(-1, -1)
	time_minutes = 8 * 60
	imperial_year = 2512
	day_of_year = WarhammerCalendar.CHARACTER_CREATION_START_DAY
	## Per the follow-up request's own reported bug: the exact same
	## class of bug as time/calendar above, reintroduced when map
	## position persistence was added — reset_session_state() runs
	## AFTER load_game() has already correctly restored
	## last_active_map_path/world_map_player_position from the save
	## file, so resetting them there silently wiped every load back to
	## Giessingen regardless of where the player actually saved.
	## Belongs here instead, alongside the same time/calendar reset,
	## since this only ever needs to run for a genuinely new character.
	world_map_player_position = Vector2i(-1, -1)
	last_active_map_path = ""
	last_active_city_id = ""
	city_player_positions = {}
	## A genuinely new character has no in-progress dungeon — same
	## "only for a fresh character" treatment as last_active_map_path
	## above (an existing save's own dungeon_state is deliberately NOT
	## touched by an ordinary load; see that field's own comment).
	dungeon_state = {}
	## dungeon_floor_states caches every floor visited THIS delve, keyed
	## off the same dungeon_state above — a genuinely new character has
	## no earlier floors to remember either, so it resets right
	## alongside it. See that field's own comment for the full story.
	dungeon_floor_states = {}
	reset_session_state()

## Per the request's own reported bug: loading an existing save (via
## Continue, or Switch Character) was calling reset_world_state()
## right after load_game() had already correctly restored the
## character's own saved time/calendar — silently wiping it back to
## 8am on every single load, which is exactly what "time isn't
## saving" looks like from the outside. This covers everything
## reset_world_state() used to also reset (stale pending
## encounter/travel state from a previous session) WITHOUT touching
## time_minutes/imperial_year/day_of_year, which load_game() has
## already set correctly by the time this runs.
func reset_session_state() -> void:
	## Stale pending encounter/travel state from a previous session —
	## genuinely safe to always clear here, unlike
	## last_active_map_path/world_map_player_position above, which
	## load_game() may have just correctly restored.
	pending_map_path = ""
	pending_map_spawn_tile = Vector2i(-1, -1)
	pending_city_id = ""
	pending_tavern_city_id = ""
	pending_tavern_name = ""
	pending_shop_city_id = ""
	pending_shop_settlement_tier = ""
	pending_shop_settlement_name = ""
	pending_shop_location_name = ""
	pending_dungeon_theme_id = ""
	## Same "stale pending state from a previous session" treatment as
	## every other pending_* flag here — see this field's own header
	## comment for the full explanation of why it exists.
	dungeon_entry_requested = false
	pending_guild_city_id = ""
	pending_healer_city_id = ""
	world_map_hours_since_rest = 0.0
	world_map_fatigue_warned_today = false
	world_map_fatigue_applied_today = false
	current_field_difficulty_tier = 0
	current_social_difficulty_tier = 0
	current_field_monster_pool = []
	current_field_habitat = ""
	pending_battle_is_dark = false
	pending_battle_is_pitch_black = false
	tiles_since_last_encounter = 999
	pending_encounter_monster_names = []
	pending_encounter_is_player_ambush = false
	pending_social_encounter_name = ""
	pending_social_npc_name = ""
	pending_social_npc_gender = ""
	pending_social_situation_index = -1
	pending_social_opening_flavor_index = -1
	pending_elder_encounter = false
	pending_idol_ambush = false
	goblin_fort_chest_stashed_bp = 0
	goblin_fort_chest_stashed_ss = 0
	goblin_fort_chest_stashed_gc = 0
