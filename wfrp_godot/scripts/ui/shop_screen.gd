extends Control
## A shop's stock is generated from the book's own Availability rules
## (p.291): "Common items are found in almost every corner of the
## Empire and are always assumed to be readily available." Scarce and
## Rare need a per-item roll, with the odds depending on settlement
## size — Village: Scarce 30%, Rare 15%; Town: 60%/30%; City: 90%/45%.
## Exotic is never in a normal shop's stock at all.
##
## Only Village tier is implemented right now — "up to Scarce
## availability... nothing fancy," per the request. `settlement_tier` is
## a real parameter, not hardcoded, so Town/City shops with their own
## (better) odds are a small follow-up once the map actually has more
## than one settlement to place them in. This same rule now applies to
## all three tabs (Items/Weapons/Armour), not just general goods.

const SETTLEMENT_ODDS := {
	"Village": {"Scarce": 0.30, "Rare": 0.15, "offer_rare": false},
	"Town": {"Scarce": 0.60, "Rare": 0.30, "offer_rare": true},
	"City": {"Scarce": 0.90, "Rare": 0.45, "offer_rare": true},
}
## Selling to a generic shopkeeper — the book only gives an explicit
## number (80%) for a character with a Fence/Merchant-type Career
## working Gossip and legwork; a plain "sell to the shop" transaction
## isn't priced by the book at all, so this project uses half the list
## price as a documented, reasonable default.
const SELL_FRACTION := 0.5

## Per the request ("Broken item[s] can not be repaired and have only
## 10% their original value"): a Broken armour piece (see
## Character.broken_armour) sells for a tenth of its own list price —
## salvage value only, well below the normal SELL_FRACTION every other
## sellable item gets.
const BROKEN_SELL_FRACTION := 0.1

## Per the request ("allow any ammo to be bought in 1/5/10 quantities"):
## any ItemDefinition tagged category == "Ammunition" (Arrow, Bolt, Lead
## Bullet, Elf Arrow, and so on — see core_items.tres) gets three
## quantity-buy buttons instead of the usual single "Buy" button, each
## purchasing that many units in one action rather than clicking "Buy"
## repeatedly for a whole quiver's worth.
const AMMO_BUY_QUANTITIES: Array[int] = [1, 5, 10]

## Per the request ("transfer the inventory grid layout to the shop
## windows, but leave out favorite star, and make rows more compact —
## at least half as tall vertically"): a compact cousin of
## character_menu_screen.gd's own boxed-grid row style (same faint
## tinted background, same top/bottom-only border reading as one
## continuous box, same left/right border on just the two edge cells) —
## deliberately NOT the shared exact same helper functions, since this
## version is intentionally smaller in every dimension (tighter content
## margins, smaller explicit font size) to hit "at least half as tall."
##
## Per the follow-up request ("show favourited items in all shop
## screens, and allow staring/unstaring from that screen"): this
## screen's own Party Inventory/Sell grid now DOES get a Star column
## after all (column 0, ahead of Item/Qty/Price/Actions) — see
## _add_sell_grid_row(). Bumped from 4 to 5 to make room for it.
const _SHOP_GRID_COLUMNS := 5

## Per the request ("add a column to the Buy screen between price and
## Enc to show the Item's Availability"): the three Buy tabs (Items/
## Weapons/Armour) get one more column than the Party Inventory/Sell
## grid, which stays at _SHOP_GRID_COLUMNS = 4 — kept as its own
## constant (rather than just bumping the shared one) since
## _shop_boxed_cell needs to know which grid's own column count it's
## drawing the left/right-edge border against.
const _SHOP_BUY_GRID_COLUMNS := 5

## Per the request ("separate the shop weapon list by Skill type... add
## Reach, Damage and 'Qualities and Flaws' columns"): the Weapons tab's
## own per-skill-group grids need three extra columns Items/Armour never
## need, so they get their own column count/header rather than sharing
## _SHOP_BUY_GRID_COLUMNS: Item/Price/Availability/Reach/Damage/Enc/
## Qualities and Flaws/Actions.
const _SHOP_WEAPON_GRID_COLUMNS := 8

## Per the follow-up request ("for the shop armor list, do a similar
## treatment... list them by Armor type... add Locations, APs and
## 'Qualities and Flaws'"): the Armour tab's own per-tier grids, same
## column count as the Weapons tab for the same reason (three extra
## columns Items never needs): Item/Price/Availability/Locations/APs/
## Enc/Qualities and Flaws/Actions.
const _SHOP_ARMOUR_GRID_COLUMNS := 8

static func _shop_row_style(is_left_edge: bool, is_right_edge: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1, 1, 1, 0.025)
	style.border_color = Color(0.6, 0.55, 0.45, 0.35)
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.border_width_left = 1 if is_left_edge else 0
	style.border_width_right = 1 if is_right_edge else 0
	if is_left_edge:
		style.corner_radius_top_left = 3
		style.corner_radius_bottom_left = 3
	if is_right_edge:
		style.corner_radius_top_right = 3
		style.corner_radius_bottom_right = 3
	## Deliberately much tighter than the Inventory tab's own
	## content_margin_all(4) — this, together with the smaller explicit
	## font size applied to each cell's own Label below, is what gets a
	## shop row down to at least half the Inventory grid's own row
	## height (verified by a real runtime measurement in
	## shop_grid_test.gd, not just eyeballed). Per the follow-up request
	## ("make the items rows about 10% taller"): nudged from a flat 1px
	## top/bottom up to 1.5px each — a real measured shop row went from
	## 11px to 12px (+9%). Per the further follow-up request ("give them
	## a little more height, they are a bit thin, +10%"): nudged again
	## from 1.5px to 2.1px each — a real measured shop row went from
	## 12px to 13.2px (+10%), still comfortably under half the Inventory
	## row's own height.
	style.content_margin_top = 2.1
	style.content_margin_bottom = 2.1
	style.content_margin_left = 5
	style.content_margin_right = 5
	return style

## Per the follow-up request ("make the rows a bit longer to line up
## with the right edge of Sell All, and then move the Sell buttons to
## the very right edge"): a GridContainer only lets a column absorb the
## grid's own spare width if one of the grid's DIRECT children in that
## column has SIZE_EXPAND_FILL — setting it on a nested Label deep
## inside this wrapper cell has no effect on the grid's own column
## sizing. Column 0 (Item) is the one that should soak up all the extra
## width once the grid itself is stretched to fill its parent, so the
## last column's own right edge lands flush with the panel's right edge
## (and the Sell button group, already pinned to ITS cell's own right
## edge via an expanding spacer, rides along with it).
## Per the follow-up request ("shorten the Item name column by 20% and
## give that space to the Qualities column"): most grids still just
## expand column 0 (Item) to soak up 100% of the grid's own spare
## width, same as always — `expand_columns` defaults to exactly that.
## The Weapons tab's own grid (see _new_weapon_buy_grid()) instead
## passes a column -> stretch-ratio map with TWO expanding columns
## (Item and Qualities and Flaws), so the spare width splits between
## them by ratio instead of Item taking all of it.
static func _shop_boxed_cell(control: Control, column: int, total_columns: int = _SHOP_GRID_COLUMNS, expand_columns: Dictionary = {0: 1.0}) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _shop_row_style(column == 0, column == total_columns - 1))
	if expand_columns.has(column):
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.size_flags_stretch_ratio = expand_columns[column]
	panel.add_child(control)
	return panel

## Per the request ("change the outline of the item row... make the box
## outline brighter... when hovering over a buy/sell button"): the same
## _shop_row_style() shape, just with a much brighter, more opaque gold
## border (and a faint warm background tint) — swapped in across a
## whole row's cells while the pointer is over that row's own Buy/Sell
## button(s), then swapped back out on mouse-exit. Distinct from the
## button's own hover stylebox (see _style_compact_button), which only
## ever covers the button itself — easy to miss on a row that's nearly
## as wide as the whole panel.
static func _shop_row_style_hover(is_left_edge: bool, is_right_edge: bool) -> StyleBoxFlat:
	var style := _shop_row_style(is_left_edge, is_right_edge)
	style.border_color = Color(0.95, 0.82, 0.4, 0.95)
	style.bg_color = Color(1, 0.95, 0.8, 0.06)
	return style

## Wires every Control in `triggers` (a row's own Buy/Sell button(s) —
## never Equip/Unequip/Give & Equip, which already have their own
## obvious state) AND every cell in `row_cells` itself, so hovering
## ANYWHERE over the row — not just its button(s) — brightens every
## cell in `row_cells` together (left-to-right, matching each cell's
## real column position for correct left/right-edge border rounding),
## and reverts on mouse-exit. An ammo row's three Buy 1/5/10 buttons
## (or a Sell row's Sell 1 + All (N)) all drive the same shared row
## highlight rather than each tracking independent state; `triggers`
## is still wired separately from `row_cells` (rather than relying on
## a trigger's own mouse_entered bubbling up to its containing cell)
## since a trigger sitting flush against a cell's own edge can report
## mouse_exited on the cell a frame before the trigger's mouse_entered
## fires, causing a visible highlight flicker at that boundary.
static func _wire_row_hover_highlight(row_cells: Array, triggers: Array) -> void:
	var total_columns := row_cells.size()
	var enter_row := func():
		for i in range(row_cells.size()):
			(row_cells[i] as PanelContainer).add_theme_stylebox_override("panel", _shop_row_style_hover(i == 0, i == total_columns - 1))
	var exit_row := func():
		for i in range(row_cells.size()):
			(row_cells[i] as PanelContainer).add_theme_stylebox_override("panel", _shop_row_style(i == 0, i == total_columns - 1))
	for trigger in triggers:
		trigger.mouse_entered.connect(enter_row)
		trigger.mouse_exited.connect(exit_row)
	for cell in row_cells:
		(cell as Control).mouse_entered.connect(enter_row)
		(cell as Control).mouse_exited.connect(exit_row)

static func _shop_header_cell(control: Control, expand: bool = false, stretch_ratio: float = 1.0) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)
	if expand:
		margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		margin.size_flags_stretch_ratio = stretch_ratio
	margin.add_child(control)
	return margin

## The compact font size every shop grid cell's own Label is explicitly
## overridden to — smaller than the theme's own current default Label
## size, which is what actually buys most of the "at least half as
## tall" reduction (tight content margins alone wouldn't be enough on
## their own).
const _SHOP_ROW_FONT_SIZE := 9

## A Button's own height is driven far more by its StyleBoxFlat's own
## content_margin (the theme's shared button styles use a full 6px top
## and bottom — fine for a normal button, but enough on its own to blow
## past "at least half as tall" no matter how small the label font
## gets) than by its label text — so every button placed inside a shop
## grid row's Actions cell gets its OWN compact style here instead of
## just a smaller font. Same colours/border logic as the theme's own
## button styles (see game_theme.tres) so these still read as "the
## game's buttons," just noticeably smaller ones.
static func _style_compact_button(btn: Button) -> void:
	btn.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.27, 0.21, 0.14, 1)
	normal.border_color = Color(0.72, 0.58, 0.27, 1)
	normal.border_width_left = 1
	normal.border_width_top = 1
	normal.border_width_right = 1
	normal.border_width_bottom = 1
	normal.corner_radius_top_left = 2
	normal.corner_radius_top_right = 2
	normal.corner_radius_bottom_left = 2
	normal.corner_radius_bottom_right = 2
	normal.content_margin_left = 4
	normal.content_margin_top = 0
	normal.content_margin_right = 4
	normal.content_margin_bottom = 0
	var hover: StyleBoxFlat = normal.duplicate()
	hover.bg_color = Color(0.38, 0.3, 0.18, 1)
	hover.border_color = Color(0.85, 0.7, 0.35, 1)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.bg_color = Color(0.47, 0.14, 0.13, 1)
	pressed.border_color = Color(0.85, 0.7, 0.35, 1)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(0.16, 0.13, 0.1, 1)
	disabled.border_color = Color(0.4, 0.34, 0.24, 1)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_stylebox_override("focus", hover)

static func _shop_grid_header_row(grid: GridContainer, titles: Array[String], alignments: Array[int], expand_columns: Dictionary = {0: 1.0}) -> void:
	for i in range(titles.size()):
		var lbl := Label.new()
		lbl.text = titles[i]
		lbl.horizontal_alignment = alignments[i]
		lbl.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
		lbl.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		if expand_columns.has(i):
			lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(_shop_header_cell(lbl, expand_columns.has(i), expand_columns.get(i, 1.0)))

@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var purse_label: Label = %PurseLabel
@onready var message_label: Label = %MessageLabel
@onready var items_list: VBoxContainer = %ItemsList
## Per the request ("separate the shop Weapons tab into 2 subtabs, Melee
## and Ranged. Keep all melee weapons in one, and keep Ranged + Ammo in
## the other"): the Weapons tab is now its own nested TabContainer
## (%Weapons in Shop.tscn) with two subtabs, each holding its own
## ScrollContainer + VBoxContainer — same as every other Buy tab, just
## one level deeper. See _rebuild_weapons_list().
@onready var melee_weapons_list: VBoxContainer = %MeleeList
@onready var ranged_weapons_list: VBoxContainer = %RangedList
@onready var armour_list: VBoxContainer = %ArmourList
@onready var repair_list: VBoxContainer = %RepairList
## Crafting page (per the request: "add a Crafting page to shops,
## allowing characters to order Crafted Weapon's or Armor with any
## amount of any quality") — see _rebuild_crafting_list().
@onready var crafting_list: VBoxContainer = %CraftingList
@onready var buy_tabs: TabContainer = %BuyTabs
@onready var equipped_list: VBoxContainer = %EquippedList
@onready var sell_list: VBoxContainer = %SellList
@onready var sell_all_button: Button = %SellAllButton
@onready var prev_char_button: Button = %PrevCharButton
## Per the request ("change the Shopping as: Name to character portrait +
## name and move the Enc value closer to this"): CharPortrait shows the
## same Career portrait art used everywhere else a party member is shown
## (see CareerPortraits — Character Menu header, Overworld/City top bar,
## Camp/Tavern rows, battle screen), now sitting right next to the name
## it belongs to instead of a plain text label. EncLabel moved from the
## old shared EncPurseBox (grouped with Purse) into the same box as the
## name/portrait, since Encumbrance is about who's currently shopping,
## not the party's shared purse.
@onready var char_portrait: TextureRect = %CharPortrait
@onready var char_name_label: Label = %CharNameLabel
@onready var enc_label: Label = %EncLabel
@onready var next_char_button: Button = %NextCharButton

var character: Character
var settlement_tier: String = "Village"
var settlement_name: String = "the village"
## City Shop follow-up ("copy the giessingen shop and put it into
## ubersreik... allow access via travel in the city"): set from
## GameState.pending_shop_city_id in _ready() (consumed once, same
## convention as GameState.pending_city_id) ONLY when this visit came
## from a CityScreen radial "Enter" action rather than Overworld's
## Giessingen shopkeeper tile — see _on_close() below, which branches
## on this to decide where Close actually goes.
var _return_city_id: String = ""
## Cordelia's Apothecary feature (spec: "hook up Cordelia's Apothecary
## in Ubersreik. She need a shop screen that will only sell Healing
## Draught, Faxtoryll, Salwort and Vitality Draught. No Repairing
## either... Cordelia is a Master Apothecary and will always have all
## items regardless of Availability."): `_shop_location_name` is read
## once from GameState.pending_shop_location_name (see its own
## declaration comment — set unconditionally for every shop visit, not
## just Cordelia's) into this local field, same "read once, then clear"
## convention as _return_city_id above. `is_apothecary` is the actual
## behavior gate — every other shop name leaves it false and this
## screen behaves exactly as the plain general store always has.
var _shop_location_name: String = ""
var is_apothecary: bool = false
var item_stock: Array[ItemDefinition] = []      ## rolled once per shop visit
## Per the request ("move ammo from the shop item list to the weapon
## line"): Ammunition-category ItemDefinitions (Arrow, Bolt, Lead
## Bullet, and so on) are rolled the same way as everything else in
## item_stock, but kept in this separate list and shown on the Weapons
## tab instead — see _rebuild_weapons_list()'s own Ammunition section.
var ammo_stock: Array[ItemDefinition] = []
var weapon_stock: Array[WeaponDefinition] = []
var armour_stock: Array[ArmourDefinition] = []

## --- Crafting page state (see _rebuild_crafting_list()) ----------------
## Which catalog the base-item picker is currently showing — "weapon" or
## "armour". Kept as a plain screen-level String rather than an enum
## since it's only ever compared to those two literal values here.
var _craft_type: String = "weapon"
## The base item's own name (e.g. "Sword"), picked from the FULL real
## database (GameData.weapon_db/armour_db) rather than this visit's
## rolled shop stock — a Crafting order is a bespoke commission, not
## something pulled off a shelf, so it isn't limited by what this
## particular shop happened to roll into stock today.
var _craft_base_name: String = ""
## How many instances of each Quality the player has dialed in so far.
## Durable/Fine are the two the book explicitly allows "taken multiple
## times" (see ItemQualityRules.STACKABLE_QUALITIES) — capped at 5 here
## purely as a sane UI bound (the book itself sets no upper limit, but
## an unbounded stepper inflating the price 2^N per extra point isn't a
## useful thing to let a misclick spiral into). Lightweight/Practical
## are capped at 1, since RAW never calls those two repeatable.
var _craft_quality_counts: Dictionary = {"Durable": 0, "Fine": 0, "Lightweight": 0, "Practical": 0}
const _CRAFT_QUALITY_MAX := {"Durable": 5, "Fine": 5, "Lightweight": 1, "Practical": 1}

func _ready() -> void:
	close_button.pressed.connect(_on_close)
	sell_all_button.pressed.connect(_on_sell_all)
	prev_char_button.pressed.connect(func(): _cycle_character(-1))
	next_char_button.pressed.connect(func(): _cycle_character(1))
	GameState.ensure_player_character()
	character = GameState.player_character

	## City Shop follow-up: pick up a CityScreen visit's tier/name
	## override and return-city, then clear the GameState fields so they
	## don't leak into a later, unrelated Shop visit (same "read once"
	## convention as GameState.pending_city_id elsewhere in the project).
	## Overworld's Giessingen shopkeeper-tile entry point never sets
	## these, so pending_shop_city_id stays "" there and this whole block
	## is a no-op — settlement_tier/settlement_name keep their existing
	## "Village"/"the village" defaults, unchanged from before.
	if GameState.pending_shop_city_id != "":
		_return_city_id = GameState.pending_shop_city_id
		GameState.pending_shop_city_id = ""
	if GameState.pending_shop_settlement_tier != "":
		settlement_tier = GameState.pending_shop_settlement_tier
		settlement_name = GameState.pending_shop_settlement_name
		GameState.pending_shop_settlement_tier = ""
		GameState.pending_shop_settlement_name = ""
	if GameState.pending_shop_location_name != "":
		_shop_location_name = GameState.pending_shop_location_name
		GameState.pending_shop_location_name = ""
	is_apothecary = _shop_location_name == "Cordelia's Apothecary"

	if is_apothecary:
		title_label.text = _shop_location_name
		## No Weapons/Armour/Repair/Crafting here — Cordelia deals strictly
		## in her own 4 remedies (see _roll_stock()'s own apothecary
		## branch). Tab order in Shop.tscn's own %BuyTabs is Items(0)/
		## Weapons(1)/Armour(2)/Repair(3)/Crafting(4) — Items stays
		## visible, the rest hidden.
		buy_tabs.set_tab_hidden(1, true)
		buy_tabs.set_tab_hidden(2, true)
		buy_tabs.set_tab_hidden(3, true)
		buy_tabs.set_tab_hidden(4, true)
	else:
		title_label.text = "%s — General Store" % settlement_name
		## Per the request ("crafting should not be available in the
		## Village shop, only in cities"): a proper Crafter able to work
		## Qualities into an order isn't assumed to be sitting in every
		## one-shop village — only City-tier settlements (currently just
		## Ubersreik, entered via CityScreen, which is the only place
		## that ever sets settlement_tier to "City") get the Crafting
		## tab. The Overworld's plain village General Store keeps its
		## default settlement_tier of "Village" and never sees it. Town
		## isn't wired to any real settlement yet (see SETTLEMENT_ODDS'
		## own comment above), so it's grouped with Village here too —
		## revisit this gate if/when a real Town shop exists.
		if settlement_tier != "City":
			buy_tabs.set_tab_hidden(4, true)
	_roll_stock()
	_rebuild_all()

## Per the request: lets you shop for/on behalf of any present party
## member, not just whoever's currently active on the map — mirrors the
## Character Menu's own "who am I viewing" cycling (Q/E there), kept
## independent of GameState.active_party_index for the same reason:
## browsing another member's affordability/training here shouldn't also
## change who you're controlling out on the map. Coin itself is already
## shared across the whole party (see Character.gold_crowns and
## friends), so only what's bought/sold/repaired/equipped changes with
## who's selected — the purse total never does.
func _cycle_character(direction: int) -> void:
	if GameState.party.size() <= 1:
		return
	var idx: int = GameState.party.find(character)
	if idx < 0:
		idx = 0
	idx = posmod(idx + direction, GameState.party.size())
	character = GameState.party[idx]
	_rebuild_all()

## Rolls fresh Scarce/Rare stock for this visit — a new roll each time
## you walk in, rather than a single permanent shop inventory, which
## keeps a solo game from ever permanently running out of something.
func _roll_stock() -> void:
	item_stock.clear()
	ammo_stock.clear()
	weapon_stock.clear()
	armour_stock.clear()

	## Cordelia's Apothecary spec: "will only sell Healing Draught,
	## Faxtoryll, Salwort and Vitality Draught... is a Master Apothecary
	## and will always have all items regardless of Availability." Skips
	## the normal per-item Availability roll entirely — no Scarce/Rare/
	## Exotic dice, no empty-handed visit possible — and never touches
	## weapon_stock/armour_stock (Weapons/Armour/Repair tabs are hidden
	## for her anyway, see _ready()).
	if is_apothecary:
		for wanted in ["Healing Draught", "Faxtoryll", "Salwort", "Vitality Draught"]:
			var item: ItemDefinition = GameData.item_db.find_by_name(wanted)
			if item != null:
				item_stock.append(item)
		return

	var odds: Dictionary = SETTLEMENT_ODDS.get(settlement_tier, SETTLEMENT_ODDS["Village"])

	for item in GameData.item_db.items:
		## Per the request ("the shop should not sell creature drops
		## like Bat Wing, Dog Pelt... remove them"): Trophy-category
		## items (see TrophyLookup — Rat Pelt, Boar Tusks, Bat Wing,
		## Goblin Ear, and so on) are hunted/looted, not stocked by a
		## shopkeeper — a shop never offers them for sale. This only
		## keeps them out of item_stock (what's FOR SALE); a character
		## who's actually carrying one can still sell it away in the
		## Party Inventory list, same as any other trophy — that side
		## reads straight from the character's own inventory, not this
		## rolled stock.
		if item.category == "Trophy":
			continue
		if not _rolls_in_stock(item.availability, odds):
			continue
		## Per the request ("move ammo from the shop item list to the
		## weapon line"): Ammunition-category items are rolled exactly
		## like everything else, just filed into ammo_stock instead of
		## item_stock so _rebuild_weapons_list() can show them under the
		## normal weapon listings instead of on the Items tab.
		if item.category == "Ammunition":
			ammo_stock.append(item)
		else:
			item_stock.append(item)

	for w in GameData.weapon_db.weapons:
		if w.price_pennies <= 0:
			continue   ## e.g. Improvised Weapon, Unarmed, Rock — not something a shop sells
		if _rolls_in_stock(w.availability, odds):
			weapon_stock.append(w)

	for a in GameData.armour_db.pieces:
		## The book's real, detailed piece-by-piece armour (Leather
		## Jack, Mail Coat, and so on) — already used by existing
		## monster/career/starting gear, now with real prices too. An
		## earlier pass mistakenly added a separate simplified
		## Light/Medium/Heavy system instead of pricing these; removed.
		if a.price_pennies <= 0:
			continue
		if _rolls_in_stock(a.availability, odds):
			armour_stock.append(a)

	## Per the request ("list all buy/sell items alphabetically"): the
	## Buy tabs previously listed stock in whatever order the source
	## .tres database file happened to store it in — not meaningful to a
	## player. Sorted once here per shop visit, not on every
	## _rebuild_*_list() call, since the rolled stock itself doesn't
	## change between rebuilds within the same visit (only what's been
	## bought/sold does). The Party Inventory/Sell list already sorts
	## each member's own items alphabetically (see _rebuild_sell_list's
	## own order.sort()) — this just brings the three Buy tabs in line
	## with that existing rule.
	item_stock.sort_custom(func(x: ItemDefinition, y: ItemDefinition): return x.item_name < y.item_name)
	ammo_stock.sort_custom(func(x: ItemDefinition, y: ItemDefinition): return x.item_name < y.item_name)
	weapon_stock.sort_custom(func(x: WeaponDefinition, y: WeaponDefinition): return x.weapon_name < y.weapon_name)
	armour_stock.sort_custom(func(x: ArmourDefinition, y: ArmourDefinition): return x.armour_name < y.armour_name)

func _rolls_in_stock(availability: String, odds: Dictionary) -> bool:
	match availability:
		"Common":
			return true
		"Scarce":
			return randf() < odds["Scarce"]
		"Rare":
			return odds.get("offer_rare", false) and randf() < odds["Rare"]
		_:
			return false   ## Exotic is never stocked in a normal shop (p.291)

func _rebuild_all() -> void:
	char_name_label.text = character.character_name
	## See CharPortrait's own declaration comment above.
	char_portrait.texture = CareerPortraits.get_portrait_for_character(character)
	var multiple_members := GameState.party.size() > 1
	prev_char_button.disabled = not multiple_members
	next_char_button.disabled = not multiple_members
	## Per the request ("also show select player enc x/x in the shop
	## screen"): the currently-selected shopper's own live Encumbrance
	## reading — same current/capacity values and same red-if-over-
	## capacity/green-if-not colour rule character_menu_screen.gd's own
	## header uses, so buying something that would push this character
	## over capacity is visible right here, without having to leave the
	## Shop and check the Character Menu separately.
	var enc_current := character.get_current_encumbrance()
	var enc_capacity := character.get_carrying_capacity()
	var enc_penalty := character.get_encumbrance_penalty()
	enc_label.text = "Enc: %d / %d" % [roundi(enc_current), enc_capacity]
	enc_label.add_theme_color_override("font_color", Color(0.85, 0.55, 0.5) if enc_penalty["tier"] != "None" else Color(0.6, 0.8, 0.55))
	purse_label.text = "Purse: %d GC   %d SS   %d BP" % [character.gold_crowns, character.silver_shillings, character.brass_pennies]
	_rebuild_items_list()
	_rebuild_weapons_list()
	_rebuild_armour_list()
	_rebuild_repair_list()
	_rebuild_crafting_list()
	_rebuild_equipped_list()
	_rebuild_sell_list()

## Repair (p.299's own rule: repairing armour costs a tenth of the
## piece's list price per AP restored): per the request ("shows all
## character repairable items at all times"), every repairable armour
## piece and weapon the character owns — worn/equipped or just packed —
## is listed here permanently, not just the ones currently damaged; an
## undamaged piece just reads "Nothing to repair" with no button.
## Indestructible pieces never appear here (they never take damage in
## the first place). Broken armour (AP hit 0 on every location it
## covers — see Character.broken_armour) gets listed too, but flagged
## as permanently unrepairable rather than given a cost, per the
## request ("Broken item[s] can not be repaired"). Also lists any
## weapon with durability damage from a fumbled Oops! result
## (Character.weapon_damage_taken) — see the loop below for why that
## reuses the same cost rule. Per the follow-up request ("give the shop
## Repair Tab a similar grid layout treatment to the other tabs"): all
## of this now renders into ONE shared boxed GridContainer (Item /
## Condition / Cost / Actions), split into "Armour" (repairable +
## Broken pieces) and "Weapons" sections via the same spanning
## section-header-row trick the Weapons/Armour tabs already use — see
## _add_repair_group_section_row and _add_weapon_group_section_row's own
## comment for why a shared grid (rather than one per section) is what
## keeps every row's columns aligned. _update_repair_tab_indicator()
## lights the Repair tab up red whenever anything genuinely needs
## fixing (Broken gear doesn't count — it can't be "repaired" at all,
## so it doesn't drive the indicator).
## Per the request ("make the repair tab show only damaged equipment for
## ALL characters, not just the currently selected one"): every present
## party member's own gear is checked here now, not just `character`
## (whoever's currently being shopped for) — and only pieces that
## actually need attention (damaged, or already Broken) make the list at
## all; a fully undamaged piece no longer takes up space here. Each row
## remembers its own `owner` Character so the row-builders below can
## show whose gear it is and the Repair button can charge/repair the
## right character regardless of who's currently selected in the shop
## (coin itself is a shared party purse either way — see
## Character.gold_crowns).
func _rebuild_repair_list() -> void:
	_clear(repair_list)
	var any_needs_repair := false

	var armour_rows: Array = []   ## [{owner, piece_name, ad, damage}]
	var broken_rows: Array = []   ## [{owner, piece_name, ad, count}]
	var weapon_rows: Array = []   ## [{owner, weapon_name, wd, damage}]

	for member: Character in GameState.party:
		var seen_armour: Dictionary = {}
		for piece_name in member.inventory:
			if seen_armour.has(piece_name):
				continue
			var ad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
			if ad == null or ad.is_indestructible:
				continue
			seen_armour[piece_name] = true
			## Per-location Armour Damage fix: armour_damage is now keyed
			## piece -> {location: int}, not a single flat count, since a
			## piece covering several locations (e.g. Leather Jack: Body,
			## Left Arm, Right Arm) tracks each location's own AP
			## independently — get_total_armour_damage() sums them back
			## into the one "how banged up is this?" number the Repair
			## tab wants to show.
			var damage: int = member.get_total_armour_damage(piece_name)
			if damage <= 0:
				continue
			any_needs_repair = true
			armour_rows.append({"owner": member, "piece_name": piece_name, "ad": ad, "damage": damage})

		## Broken armour — cannot be repaired, worth only a tenth of
		## value (sellable from the Party Inventory list below instead).
		## Still surfaced here (not just "damaged") since it's the most
		## urgent case of all and the row is what points the player at
		## the salvage sale.
		for piece_name in member.broken_armour.keys():
			var broken_count: int = int(member.broken_armour[piece_name])
			if broken_count <= 0:
				continue
			var bad: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
			if bad == null:
				continue
			broken_rows.append({"owner": member, "piece_name": piece_name, "ad": bad, "count": broken_count})

		## Weapon durability (Character.weapon_damage_taken) — the book
		## has no repair rule of its own for this (it's this project's
		## own extension of the fumble table's "your weapon takes 1
		## point of damage" result, see WeaponDefinition.get_weapon_damage),
		## so this reuses the same p.299 "a tenth of list price per
		## point restored" rule armour repair uses above, rather than
		## leaving a damaged weapon permanently un-fixable with no
		## in-game way to address it.
		var seen_weapons: Dictionary = {}
		for weapon_name in member.inventory:
			if seen_weapons.has(weapon_name):
				continue
			var wd: WeaponDefinition = GameData.weapon_db.find_by_name(weapon_name)
			if wd == null or wd.is_indestructible or wd.damage_flat <= 0:
				continue
			seen_weapons[weapon_name] = true
			var w_damage: int = int(member.weapon_damage_taken.get(weapon_name, 0))
			if w_damage <= 0:
				continue
			any_needs_repair = true
			weapon_rows.append({"owner": member, "weapon_name": weapon_name, "wd": wd, "damage": w_damage})

	if armour_rows.is_empty() and broken_rows.is_empty() and weapon_rows.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(nothing in the party currently needs repair)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
		repair_list.add_child(none_lbl)
		_update_repair_tab_indicator(any_needs_repair)
		return

	var grid := _new_repair_buy_grid()
	var first_section := true
	if not armour_rows.is_empty() or not broken_rows.is_empty():
		_add_repair_group_section_row(grid, "Armour", first_section)
		first_section = false
		_shop_grid_header_row(grid, _REPAIR_GRID_TITLES, _REPAIR_GRID_ALIGNMENTS)
		for row in armour_rows:
			_add_armour_repair_grid_row(grid, row["owner"], row["piece_name"], row["ad"], row["damage"])
		for row in broken_rows:
			_add_broken_armour_repair_grid_row(grid, row["owner"], row["piece_name"], row["ad"], row["count"])
	if not weapon_rows.is_empty():
		_add_repair_group_section_row(grid, "Weapons", first_section)
		first_section = false
		_shop_grid_header_row(grid, _REPAIR_GRID_TITLES, _REPAIR_GRID_ALIGNMENTS)
		for row in weapon_rows:
			_add_weapon_repair_grid_row(grid, row["owner"], row["weapon_name"], row["wd"], row["damage"])
	repair_list.add_child(grid)

	_update_repair_tab_indicator(any_needs_repair)

## Crafting page (per the request: "add a Crafting page to shops,
## allowing characters to order Crafted Weapon's or Armor with any
## amount of any quality (each one doubles the price of the item).
## Crafting time will be 2 days per quality."): lets the player pick
## any real weapon or armour piece from the FULL database (not this
## visit's rolled stock — a bespoke commission isn't limited by what's
## on the shelf today, unlike buying off the Weapons/Armour tabs) and
## dial in any combination of the 4 general Item Qualities (Durable,
## Fine, Lightweight, Practical — see ItemQualityRules; Flaws are
## deliberately not offered here, per the request's own "Do not add
## Flawed item to the shops" — nobody commissions a deliberately Shoddy
## sword), previewing the live price/Availability/lead-time before
## paying. Placing an order deducts payment immediately but does NOT
## hand over the item on the spot — it queues real in-game-time
## delivery via GameState.queue_craft_order(), since the whole point of
## the feature is that the smith genuinely needs the time to make it.
func _rebuild_crafting_list() -> void:
	_clear(crafting_list)

	var intro := Label.new()
	intro.text = "Commission a custom weapon or armour piece with any combination of Qualities. Each Quality doubles the price; the order takes 2 days per Quality to finish."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD
	intro.add_theme_font_size_override("font_size", 11)
	intro.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	crafting_list.add_child(intro)

	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 6)
	var weapon_type_btn := Button.new()
	weapon_type_btn.text = "Weapon"
	weapon_type_btn.toggle_mode = true
	weapon_type_btn.button_pressed = _craft_type == "weapon"
	weapon_type_btn.pressed.connect(func():
		_craft_type = "weapon"
		_craft_base_name = ""
		_rebuild_crafting_list())
	type_row.add_child(weapon_type_btn)
	var armour_type_btn := Button.new()
	armour_type_btn.text = "Armour"
	armour_type_btn.toggle_mode = true
	armour_type_btn.button_pressed = _craft_type == "armour"
	armour_type_btn.pressed.connect(func():
		_craft_type = "armour"
		_craft_base_name = ""
		_rebuild_crafting_list())
	type_row.add_child(armour_type_btn)
	crafting_list.add_child(type_row)

	## Base item picker — the FULL real database, not this visit's rolled
	## stock (see the function's own doc comment above). Free/improvised
	## entries (price 0 — Improvised Weapon, Unarmed, Rock) are skipped;
	## there's nothing to commission a bespoke version of. Per the request
	## ("Crafting item list should only include base items, so without
	## Fine/Durable/Lightweight etc."): also skip any entry that already
	## carries its own item_qualities/item_flaws — the static "Fine <X>"/
	## "Durable <X>"/"Lightweight <X>" shop-stock variants (and any item a
	## previous Crafting order already registered) are Quality-bearing
	## copies of some other base item, not base items themselves, so they
	## don't belong in this picker even though they live in the same
	## database. Picking Sword and adding Fine here is how you get to
	## "Fine Sword" — there's no separate need to also offer the already-
	## Fine one as its own startable base.
	var names: Array[String] = []
	if _craft_type == "weapon":
		for wd in GameData.weapon_db.weapons:
			if wd.price_pennies > 0 and wd.item_qualities.is_empty() and wd.item_flaws.is_empty():
				names.append(wd.weapon_name)
	else:
		for ad in GameData.armour_db.pieces:
			if ad.price_pennies > 0 and ad.item_qualities.is_empty() and ad.item_flaws.is_empty():
				names.append(ad.armour_name)
	names.sort()

	var picker := OptionButton.new()
	picker.add_item("(choose a base item...)")
	picker.set_item_disabled(0, true)
	var selected_idx := 0
	for i in range(names.size()):
		picker.add_item(names[i])
		if names[i] == _craft_base_name:
			selected_idx = i + 1
	picker.selected = selected_idx
	picker.item_selected.connect(func(idx: int):
		_craft_base_name = names[idx - 1] if idx >= 1 and idx - 1 < names.size() else ""
		_rebuild_crafting_list())
	crafting_list.add_child(picker)

	if _craft_base_name == "":
		return
	var base_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(_craft_base_name) if _craft_type == "weapon" else null
	var base_armour: ArmourDefinition = GameData.armour_db.find_by_name(_craft_base_name) if _craft_type == "armour" else null
	if base_weapon == null and base_armour == null:
		## The previously-chosen base item vanished from its own catalog
		## (shouldn't normally happen) — reset rather than crash.
		_craft_base_name = ""
		return

	var base_price: int = base_weapon.price_pennies if base_weapon != null else base_armour.price_pennies
	var base_availability: String = base_weapon.availability if base_weapon != null else base_armour.availability
	var base_encumbrance: int = base_weapon.encumbrance if base_weapon != null else base_armour.encumbrance

	var base_info := Label.new()
	base_info.text = "Base: %s — %s, Enc %d, %s" % [_craft_base_name, _format_price(base_price), base_encumbrance, base_availability]
	base_info.add_theme_font_size_override("font_size", 11)
	base_info.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	crafting_list.add_child(base_info)

	for quality_name in ["Durable", "Fine", "Lightweight", "Practical"]:
		crafting_list.add_child(_build_craft_quality_row(quality_name))

	var item_qualities: Array[String] = []
	var quality_count := 0
	for quality_name in ["Durable", "Fine", "Lightweight", "Practical"]:
		var n: int = int(_craft_quality_counts.get(quality_name, 0))
		if n <= 0:
			continue
		quality_count += n
		item_qualities.append(quality_name if n == 1 else "%s %d" % [quality_name, n])

	var derived := ItemQualityRules.compute_derived(base_price, base_availability, item_qualities, [], base_encumbrance)
	var days: int = quality_count * 2

	var summary := Label.new()
	if quality_count <= 0:
		summary.text = "Choose at least one Quality to place a Crafting order."
		summary.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	else:
		summary.text = "%d Quality point(s) — Price: %s, Availability: %s, ready in %d day%s." % [quality_count, _format_price(derived["price_pennies"]), derived["availability"], days, "s" if days != 1 else ""]
		summary.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD
	summary.add_theme_font_size_override("font_size", 12)
	crafting_list.add_child(summary)

	var order_btn := Button.new()
	order_btn.text = "Place Order"
	order_btn.disabled = quality_count <= 0 or character.get_total_pennies() < int(derived["price_pennies"])
	order_btn.pressed.connect(func():
		_on_place_craft_order(item_qualities, quality_count, int(derived["price_pennies"]), String(derived["availability"])))
	crafting_list.add_child(order_btn)

	var own_pending: Array = []
	for order in GameState.pending_craft_orders:
		if order.get("character_name", "") == character.character_name:
			own_pending.append(order)
	if not own_pending.is_empty():
		var pending_header := Label.new()
		pending_header.text = "Orders in progress for %s:" % character.character_name
		pending_header.add_theme_font_size_override("font_size", 11)
		pending_header.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
		crafting_list.add_child(pending_header)
		for order in own_pending:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 6)
			var row_lbl := Label.new()
			row_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			## Per the request ("make it so User needs to pick up items
			## when crafting time is finished, rather then appearing in
			## inventory"): once ready_at_minutes has passed, the order
			## just sits here waiting — it only actually lands in the
			## character's inventory once "Collect" below is pressed.
			if GameState.is_craft_order_ready(order):
				row_lbl.text = "   %s — ready for collection" % order.get("item_name", "?")
				row_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.5))
			else:
				var remaining_minutes: int = maxi(0, int(order.get("ready_at_minutes", 0)) - GameState.time_minutes_total())
				var remaining_days: int = int(ceil(remaining_minutes / (24.0 * 60.0)))
				row_lbl.text = "   %s — ready in %d day%s" % [order.get("item_name", "?"), remaining_days, "s" if remaining_days != 1 else ""]
			row_lbl.add_theme_font_size_override("font_size", 11)
			row.add_child(row_lbl)
			if GameState.is_craft_order_ready(order):
				var collect_btn := Button.new()
				collect_btn.text = "Collect"
				var order_id: int = int(order.get("order_id", -1))
				collect_btn.pressed.connect(func(): _on_collect_craft_order(order_id))
				row.add_child(collect_btn)
			crafting_list.add_child(row)

## One "<Quality Name>  [-] N [+]" stepper row, used by _rebuild_crafting_
## list() for each of the 4 general Item Qualities. Durable/Fine cap at
## 5 (a sane UI bound — see _CRAFT_QUALITY_MAX's own comment);
## Lightweight/Practical cap at 1, since RAW never calls those two
## repeatable.
func _build_craft_quality_row(quality_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = quality_name
	lbl.custom_minimum_size = Vector2(90, 0)
	row.add_child(lbl)
	var count: int = int(_craft_quality_counts.get(quality_name, 0))
	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	minus_btn.disabled = count <= 0
	minus_btn.pressed.connect(func():
		_craft_quality_counts[quality_name] = maxi(0, count - 1)
		_rebuild_crafting_list())
	row.add_child(minus_btn)
	var count_lbl := Label.new()
	count_lbl.text = str(count)
	count_lbl.custom_minimum_size = Vector2(20, 0)
	count_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(count_lbl)
	var max_count: int = int(_CRAFT_QUALITY_MAX.get(quality_name, 1))
	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	plus_btn.disabled = count >= max_count
	plus_btn.pressed.connect(func():
		_craft_quality_counts[quality_name] = mini(max_count, count + 1)
		_rebuild_crafting_list())
	row.add_child(plus_btn)
	return row

## Deducts payment, creates (or reuses, if this exact combination has
## already been ordered before — same "same name, same stats, share one
## definition" reasoning the rest of this project's item system already
## follows) the crafted item's own WeaponDefinition/ArmourDefinition,
## and queues its delivery. The item itself is NOT added to inventory
## here — it only gets there once the player later presses "Collect" on
## a ready order (see GameState.queue_craft_order()/
## collect_craft_order() for the queuing and actual hand-off).
func _on_place_craft_order(item_qualities: Array[String], quality_count: int, price: int, new_availability: String) -> void:
	if quality_count <= 0 or _craft_base_name == "":
		return
	if not character.spend_pennies(price):
		message_label.text = "You can't afford that."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return

	var composed_name := "%s %s" % [" ".join(item_qualities), _craft_base_name]
	var item_type := _craft_type

	if item_type == "weapon":
		var base: WeaponDefinition = GameData.weapon_db.find_by_name(_craft_base_name)
		if base != null and GameData.weapon_db.find_by_name(composed_name) == null:
			var wd: WeaponDefinition = base.duplicate()
			wd.weapon_name = composed_name
			wd.item_qualities = item_qualities.duplicate()
			wd.item_flaws = []
			wd.price_pennies = price
			wd.availability = new_availability
			GameData.weapon_db.weapons.append(wd)
	else:
		var base_a: ArmourDefinition = GameData.armour_db.find_by_name(_craft_base_name)
		if base_a != null and GameData.armour_db.find_by_name(composed_name) == null:
			var ad: ArmourDefinition = base_a.duplicate()
			ad.armour_name = composed_name
			ad.item_qualities = item_qualities.duplicate()
			ad.item_flaws = []
			ad.price_pennies = price
			ad.availability = new_availability
			GameData.armour_db.pieces.append(ad)

	GameState.queue_craft_order(character.character_name, item_type, composed_name, quality_count)
	var days := quality_count * 2
	message_label.text = "Ordered %s for %s — ready in %d day%s." % [composed_name, _format_price(price), days, "s" if days != 1 else ""]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	_craft_quality_counts = {"Durable": 0, "Fine": 0, "Lightweight": 0, "Practical": 0}
	GameState.autosave()
	_rebuild_all()

## Per the follow-up request ("make it so User needs to pick up items
## when crafting time is finished, rather then appearing in inventory"):
## wired to each ready order's own "Collect" button in _rebuild_
## crafting_list() above. The actual hand-off logic lives in
## GameState.collect_craft_order() (matched by order_id, not just name,
## so two similar orders for the same character can't be confused) —
## this just calls it and reports the outcome.
func _on_collect_craft_order(order_id: int) -> void:
	if GameState.collect_craft_order(order_id):
		message_label.text = "Collected your finished order."
		message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
		GameState.autosave()
	else:
		message_label.text = "That order isn't ready yet."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
	_rebuild_all()

## The Repair tab's own 4-column set — Item / Condition / Cost /
## Actions — shared constants for the same reason _WEAPON_GRID_TITLES/
## _ARMOUR_GRID_TITLES/_ITEMS_GRID_TITLES above are: _rebuild_repair_list()
## needs to add this same header more than once (once per section) to
## one shared grid.
const _SHOP_REPAIR_GRID_COLUMNS := 4
const _REPAIR_GRID_TITLES: Array[String] = ["Item", "Condition", "Cost", "Actions"]
const _REPAIR_GRID_ALIGNMENTS: Array[int] = [
	HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT,
]

## Just builds and configures the (currently empty) GridContainer
## itself — same reasoning as _new_weapon_buy_grid()/_new_armour_buy_grid()/
## _new_items_buy_grid() above.
func _new_repair_buy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _SHOP_REPAIR_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	return grid

## As _add_weapon_group_section_row()/_add_armour_tier_section_row()/
## _add_item_group_section_row() above, for the Repair tab's own
## Armour/Weapons sections.
func _add_repair_group_section_row(grid: GridContainer, group_name: String, first: bool = false) -> void:
	var header_label := Label.new()
	header_label.text = group_name
	header_label.add_theme_font_size_override("font_size", 12)
	header_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	var header_margin := MarginContainer.new()
	if not first:
		header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_margin.add_child(header_label)
	grid.add_child(header_margin)
	for i in range(_SHOP_REPAIR_GRID_COLUMNS - 1):
		grid.add_child(Control.new())

## One armour row inside the shared Repair grid — damaged (a real Cost
## + "Repair Fully" button) or undamaged ("Nothing to repair", no
## button) — see _rebuild_repair_list. `owner` is whichever party member
## actually has this piece (not necessarily the shop's currently
## selected `character`), per the request that the Repair tab cover the
## whole party — its name is shown alongside the piece so it's clear
## whose gear this is, and the Repair button charges/repairs `owner`
## specifically.
func _add_armour_repair_grid_row(grid: GridContainer, owner: Character, piece_name: String, ad: ArmourDefinition, damage: int) -> void:
	var is_worn := owner.equipped_armour.has(piece_name)
	var name_label := Label.new()
	name_label.text = "• %s (%s, %s)" % [piece_name, owner.character_name, "worn" if is_worn else "in pack"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(item_cell)

	## Total capacity across every location this piece covers (e.g.
	## Leather Jack: 1 AP x 3 locations = 3) — matches `damage` above,
	## which is now the same total-across-locations figure, not just one
	## location's own AP rating.
	var total_capacity: int = ad.armour_points * max(1, ad.locations.size())
	var condition_label := Label.new()
	condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	condition_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if damage > 0:
		condition_label.text = "%d/%d AP damaged" % [damage, total_capacity]
		condition_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	else:
		condition_label.text = "Undamaged (%d/%d AP)" % [total_capacity, total_capacity]
	var condition_cell := _shop_boxed_cell(condition_label, 1, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(condition_cell)

	var total_cost := 0
	var cost_label := Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if damage > 0:
		var cost_per_ap := int(ceil(ad.price_pennies * 0.1))
		total_cost = cost_per_ap * damage
		cost_label.text = _format_price(total_cost)
	else:
		cost_label.text = "-"
	var cost_cell := _shop_boxed_cell(cost_label, 2, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(cost_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	var repair_triggers: Array = []
	if damage > 0:
		var repair_btn := Button.new()
		repair_btn.text = "Repair Fully"
		_style_compact_button(repair_btn)
		repair_btn.disabled = owner.get_total_pennies() < total_cost
		repair_btn.pressed.connect(func(): _on_repair(owner, piece_name, total_cost))
		actions_row.add_child(repair_btn)
		repair_triggers.append(repair_btn)
	else:
		var ok_lbl := Label.new()
		ok_lbl.text = "Nothing to repair"
		ok_lbl.add_theme_font_size_override("font_size", 10)
		ok_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.5))
		actions_row.add_child(ok_lbl)
	var actions_cell := _shop_boxed_cell(actions_row, 3, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight([item_cell, condition_cell, cost_cell, actions_cell], repair_triggers)

## A Broken armour piece's own row inside the shared Repair grid — no
## Repair button at all (per the request, Broken items can't be
## repaired), just its own salvage value and a note pointing at where
## it CAN still be turned into money. `owner` is whichever party member
## owns this Broken piece — see _add_armour_repair_grid_row above.
func _add_broken_armour_repair_grid_row(grid: GridContainer, owner: Character, piece_name: String, ad: ArmourDefinition, count: int) -> void:
	var name_label := Label.new()
	name_label.text = "• %s%s (%s)" % [piece_name, " x%d" % count if count > 1 else "", owner.character_name]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color(0.75, 0.35, 0.3))
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(item_cell)

	var condition_label := Label.new()
	condition_label.text = "BROKEN"
	condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	condition_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	condition_label.add_theme_color_override("font_color", Color(0.75, 0.35, 0.3))
	var condition_cell := _shop_boxed_cell(condition_label, 1, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(condition_cell)

	var salvage_each := _find_broken_sell_price(piece_name)
	var cost_label := Label.new()
	cost_label.text = _format_price(salvage_each) if salvage_each > 0 else "-"
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	cost_label.tooltip_text = "Salvage value if sold in Party Inventory (10% of list price) — cannot be repaired"
	var cost_cell := _shop_boxed_cell(cost_label, 2, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(cost_cell)

	var note_lbl := Label.new()
	note_lbl.text = "Sell for salvage in Party Inventory"
	note_lbl.add_theme_font_size_override("font_size", 10)
	note_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
	var actions_cell := _shop_boxed_cell(note_lbl, 3, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight([item_cell, condition_cell, cost_cell, actions_cell], [])

## One weapon row inside the shared Repair grid — same damaged/undamaged
## split as _add_armour_repair_grid_row above. `owner` is whichever
## party member actually has this weapon — see _add_armour_repair_grid_row.
func _add_weapon_repair_grid_row(grid: GridContainer, owner: Character, weapon_name: String, wd: WeaponDefinition, w_damage: int) -> void:
	var is_equipped: bool = owner.equipped_weapon == weapon_name or owner.equipped_offhand == weapon_name
	var name_label := Label.new()
	name_label.text = "• %s (%s, %s)" % [weapon_name, owner.character_name, "equipped" if is_equipped else "in pack"]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(item_cell)

	var condition_label := Label.new()
	condition_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	condition_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if w_damage > 0:
		condition_label.text = "%d/%d Damage" % [w_damage, wd.damage_flat]
		condition_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	else:
		condition_label.text = "Undamaged (0/%d Damage)" % wd.damage_flat
	var condition_cell := _shop_boxed_cell(condition_label, 1, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(condition_cell)

	var w_total_cost := 0
	var cost_label := Label.new()
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if w_damage > 0:
		var w_cost_per_point := int(ceil(wd.price_pennies * 0.1))
		w_total_cost = w_cost_per_point * w_damage
		cost_label.text = _format_price(w_total_cost)
	else:
		cost_label.text = "-"
	var cost_cell := _shop_boxed_cell(cost_label, 2, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(cost_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	var repair_triggers: Array = []
	if w_damage > 0:
		var w_repair_btn := Button.new()
		w_repair_btn.text = "Repair Fully"
		_style_compact_button(w_repair_btn)
		w_repair_btn.disabled = owner.get_total_pennies() < w_total_cost
		w_repair_btn.pressed.connect(func(): _on_repair_weapon(owner, weapon_name, w_total_cost))
		actions_row.add_child(w_repair_btn)
		repair_triggers.append(w_repair_btn)
	else:
		var w_ok_lbl := Label.new()
		w_ok_lbl.text = "Nothing to repair"
		w_ok_lbl.add_theme_font_size_override("font_size", 10)
		w_ok_lbl.add_theme_color_override("font_color", Color(0.5, 0.65, 0.5))
		actions_row.add_child(w_ok_lbl)
	var actions_cell := _shop_boxed_cell(actions_row, 3, _SHOP_REPAIR_GRID_COLUMNS)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight([item_cell, condition_cell, cost_cell, actions_cell], repair_triggers)

## Per the request ("light up the Repair tab Red if there is any gear
## that needs repairing"): TabBar/TabContainer has no per-tab font-color
## override in Godot 4, so this uses a small procedural red-dot icon
## next to the tab's own title instead — set when `needs_repair` is
## true, cleared (null) otherwise. Looked up by control rather than a
## hardcoded tab index so this keeps working even if the tab order ever
## changes.
func _update_repair_tab_indicator(needs_repair: bool) -> void:
	if buy_tabs == null or repair_list == null:
		return
	var repair_control := repair_list.get_parent()
	if repair_control == null:
		return
	var idx := buy_tabs.get_tab_idx_from_control(repair_control)
	if idx < 0:
		return
	buy_tabs.set_tab_icon(idx, _repair_alert_texture() if needs_repair else null)

static var _repair_alert_icon: ImageTexture = null

## A tiny solid-red filled circle, generated once and cached — simplest
## way to get a real "this needs attention" red indicator onto a
## specific TabBar tab without a shipped asset file.
func _repair_alert_texture() -> ImageTexture:
	if _repair_alert_icon == null:
		var size := 10
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 0))
		var center := Vector2(float(size - 1) / 2.0, float(size - 1) / 2.0)
		var radius := float(size) / 2.0
		for y in range(size):
			for x in range(size):
				if Vector2(x, y).distance_to(center) <= radius:
					img.set_pixel(x, y, Color(0.85, 0.15, 0.1, 1))
		_repair_alert_icon = ImageTexture.create_from_image(img)
	return _repair_alert_icon

## Per the request ("show only damaged equipment for ALL characters, not
## just the currently selected one"): `target` is whichever party member
## actually owns the repaired piece, which may not be the shop's
## currently selected `character` — coin is a shared party purse either
## way (see Character.gold_crowns), so spend_pennies works the same
## regardless of which member instance it's called on.
func _on_repair(target: Character, piece_name: String, cost: int) -> void:
	if not target.spend_pennies(cost):
		message_label.text = "You can't afford that repair right now."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	target.armour_damage.erase(piece_name)
	message_label.text = "%s's %s repaired to full." % [target.character_name, piece_name]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _on_repair_weapon(target: Character, weapon_name: String, cost: int) -> void:
	if not target.spend_pennies(cost):
		message_label.text = "You can't afford that repair right now."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	target.weapon_damage_taken.erase(weapon_name)
	message_label.text = "%s's %s repaired to full." % [target.character_name, weapon_name]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Per the request ("the selected character equipped gear at the
## top... allow equipping/unequipping"): the currently-selected
## character's own Main Hand/Off-Hand weapon and every worn Armour
## piece, each with a plain Unequip button — mirrors
## character_menu_screen.gd's own Equipment tab (Unequip just clears
## equipped_weapon/equipped_offhand or erases from equipped_armour; the
## item itself stays in the character's inventory either way, same as
## every other Unequip button in this project).
func _rebuild_equipped_list() -> void:
	_clear(equipped_list)
	var any_equipped := false
	if character.equipped_weapon != "":
		any_equipped = true
		equipped_list.add_child(_equipped_row(character.equipped_weapon, "Main Hand", func(): _on_unequip_weapon_slot("main")))
	if character.equipped_offhand != "":
		any_equipped = true
		equipped_list.add_child(_equipped_row(character.equipped_offhand, "Off-Hand", func(): _on_unequip_weapon_slot("off")))
	for piece_name in character.equipped_armour:
		any_equipped = true
		equipped_list.add_child(_equipped_row(piece_name, "Armour", func(): _on_unequip_armour(piece_name)))
	## Per the "packs and containers" request: the three Container equip
	## slots shown here exactly like every other equip slot above.
	for slot in ["Back", "Waist", "Shoulder"]:
		var worn_name: String = character.get_equipped_container(slot)
		if worn_name != "":
			any_equipped = true
			equipped_list.add_child(_equipped_row(worn_name, slot, func(): _on_unequip_container(slot)))
	if not any_equipped:
		var none_lbl := Label.new()
		none_lbl.text = "(nothing currently equipped)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
		equipped_list.add_child(none_lbl)

func _equipped_row(item_name: String, slot_label: String, on_unequip: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "%s — %s" % [slot_label, item_name]
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var btn := Button.new()
	btn.text = "Unequip"
	btn.pressed.connect(on_unequip)
	row.add_child(btn)
	return row

func _on_unequip_weapon_slot(slot: String) -> void:
	## Per the follow-up request: a light source now shares this same
	## hand-slot pair rather than its own — unequipping whichever hand
	## currently holds the active one also turns it off, matching
	## character_menu_screen.gd's own drop/send handlers.
	var unequipped_light := character.get_equipped_light_item()
	if slot == "main":
		character.equipped_weapon = ""
	else:
		character.equipped_offhand = ""
	if unequipped_light != null and character.get_equipped_light_item() != unequipped_light:
		character.light_mode = "off"
	GameState.autosave()
	_rebuild_all()

func _on_unequip_armour(piece_name: String) -> void:
	character.equipped_armour.erase(piece_name)
	GameState.autosave()
	_rebuild_all()

func _on_unequip_container(slot: String) -> void:
	character.set_equipped_container(slot, "")
	GameState.autosave()
	_rebuild_all()

## Per the request: moves one copy of `item_name` from `owner`'s pack
## into the currently-selected character's own inventory — a no-op if
## `owner` already IS the selected character. Mirrors
## character_menu_screen.gd's own _on_send_item(): if that was the
## owner's last copy of something they had equipped, cleanly unequips
## it from them first rather than leaving a dangling equipped_weapon/
## equipped_offhand/equipped_armour entry pointing at an item they no
## longer carry.
func _transfer_item_to_selected(owner: Character, item_name: String) -> void:
	if owner == character:
		return
	owner.inventory.erase(item_name)
	if not owner.inventory.has(item_name):
		var sent_light := owner.get_equipped_light_item()
		if sent_light != null and sent_light.item_name == item_name:
			owner.light_mode = "off"
		if owner.equipped_weapon == item_name:
			owner.equipped_weapon = ""
		if owner.equipped_offhand == item_name:
			owner.equipped_offhand = ""
		owner.equipped_armour.erase(item_name)
		for slot in ["Back", "Waist", "Shoulder"]:
			if owner.get_equipped_container(slot) == item_name:
				owner.set_equipped_container(slot, "")
	character.inventory.append(item_name)

## Per the request ("allow equipping... to and from the selected
## character"): pulls a weapon from ANOTHER party member's pack onto
## the selected character in one step — transfer, then equip into
## whichever hand is open (Main Hand first, then Off-Hand if the main
## weapon isn't two-handed). If both hands are already full, the item
## still gets handed over (now sitting spare in the selected
## character's own pack, equippable manually from the row above) —
## the transfer isn't undone just because there was nowhere to put it.
func _on_give_and_equip_weapon(owner: Character, item_name: String) -> void:
	var w: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
	if w == null:
		return
	_transfer_item_to_selected(owner, item_name)
	var equipped_now := false
	if character.equipped_weapon == "":
		character.equipped_weapon = item_name
		if w.is_two_handed:
			character.equipped_offhand = ""
		equipped_now = true
	elif not character.main_weapon_is_two_handed() and character.equipped_offhand == "":
		character.equipped_offhand = item_name
		equipped_now = true
	if equipped_now:
		message_label.text = "%s given to and equipped by %s." % [item_name, character.character_name]
		message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	else:
		message_label.text = "%s moved to %s's pack — both hands are already full, equip it manually." % [item_name, character.character_name]
		message_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
	GameState.autosave()
	_rebuild_all()

## Armour counterpart to _on_give_and_equip_weapon — same transfer-then-
## equip shortcut, using Character.get_conflicting_equipped_armour() to
## decide whether there's actually room; if not, the piece still gets
## handed over rather than the whole action being blocked.
func _on_give_and_equip_armour(owner: Character, item_name: String) -> void:
	_transfer_item_to_selected(owner, item_name)
	var conflicts := character.get_conflicting_equipped_armour(item_name)
	if conflicts.is_empty():
		character.equipped_armour.append(item_name)
		message_label.text = "%s given to and equipped by %s." % [item_name, character.character_name]
		message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	else:
		message_label.text = "%s moved to %s's pack — conflicts with their equipped %s." % [item_name, character.character_name, ", ".join(conflicts)]
		message_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
	GameState.autosave()
	_rebuild_all()

## Main Hand/Off-Hand Equip-or-Unequip button pair for a weapon already
## in the SELECTED character's own inventory — identical rules to
## character_menu_screen.gd's own _rebuild_weapons(): a single physical
## copy can't be split across both hands (have_two_copies gates the
## "other" hand's button unless there are genuinely 2+ copies to give
## one to each), and equipping a two-handed weapon to Main Hand clears
## whatever was in Off-Hand.
func _weapon_equip_buttons(item_name: String, w: WeaponDefinition, count: int) -> Array[Button]:
	var is_main := character.equipped_weapon == item_name
	var is_off := character.equipped_offhand == item_name
	var have_two_copies: bool = count >= 2
	var main_btn := Button.new()
	main_btn.text = "Unequip" if is_main else "Equip (Main)"
	main_btn.disabled = not is_main and is_off and not have_two_copies
	main_btn.pressed.connect(func():
		if is_main:
			character.equipped_weapon = ""
		else:
			character.equipped_weapon = item_name
			if w.is_two_handed:
				character.equipped_offhand = ""
		GameState.autosave()
		_rebuild_all()
	)
	var off_btn := Button.new()
	off_btn.text = "Unequip" if is_off else "Equip (Off)"
	off_btn.disabled = not is_off and (character.main_weapon_is_two_handed() or (is_main and not have_two_copies))
	off_btn.pressed.connect(func():
		character.equipped_offhand = "" if is_off else item_name
		GameState.autosave()
		_rebuild_all()
	)
	return [main_btn, off_btn]

## Armour Equip/Unequip button for a piece already in the SELECTED
## character's own inventory — identical rule to character_menu_screen
## .gd's own _rebuild_armor(): disabled (with an explanatory tooltip)
## if it covers the same body location as something already worn.
func _armour_equip_button(item_name: String) -> Button:
	var is_current := character.equipped_armour.has(item_name)
	var conflicts: Array[String] = []
	if not is_current:
		conflicts = character.get_conflicting_equipped_armour(item_name)
	var btn := Button.new()
	btn.text = "Unequip" if is_current else "Equip"
	btn.disabled = not is_current and not conflicts.is_empty()
	if not conflicts.is_empty():
		btn.tooltip_text = "Covers the same location as an already-equipped %s — unequip that first." % ", ".join(conflicts)
	btn.pressed.connect(func():
		if is_current:
			character.equipped_armour.erase(item_name)
		else:
			character.equipped_armour.append(item_name)
		GameState.autosave()
		_rebuild_all()
	)
	return btn

## Shared 5-column header content (Item/Price/Availability/Enc/Actions)
## — pulled out as constants (same reasoning as _WEAPON_GRID_TITLES/
## _ARMOUR_GRID_TITLES above) because _rebuild_items_list() now needs to
## add this same header row more than once, once per group, to one
## shared grid. _new_buy_grid() below (still used as-is by the
## Ammunition section, which never needs sub-grouping) keeps building
## its own single header inline from these same constants.
const _ITEMS_GRID_TITLES: Array[String] = ["Item", "Price", "Availability", "Enc", "Actions"]
const _ITEMS_GRID_ALIGNMENTS: Array[int] = [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT]

func _new_buy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _SHOP_BUY_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	_shop_grid_header_row(grid, _ITEMS_GRID_TITLES, _ITEMS_GRID_ALIGNMENTS)
	return grid

## As _new_buy_grid() above, but WITHOUT self-adding a header row — the
## Items tab now needs to add this header more than once (once per
## group) to one shared grid, same reasoning as _new_weapon_buy_grid()/
## _new_armour_buy_grid().
func _new_items_buy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _SHOP_BUY_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	return grid

## Per the request ("separate Containers and Food into their own
## groups, and everything else is the Miscellaneous group"): a simple
## 3-way split of ItemDefinition.category — Container -> "Containers",
## Food -> "Food", everything else (General/Tool/Reagent, and anything
## added later) -> "Miscellaneous". Trophy/Ammunition items never reach
## item_stock at all (see _roll_stock() — Trophies are filtered out
## entirely, Ammunition is filed into ammo_stock for the Weapons tab
## instead), so neither of those categories needs a case here.
const _ITEM_GROUP_ORDER: Array[String] = ["Containers", "Food", "Miscellaneous"]

func _item_group_name(item: ItemDefinition) -> String:
	if item.category == "Container":
		return "Containers"
	if item.category == "Food":
		return "Food"
	return "Miscellaneous"

## As _add_weapon_group_section_row()/_add_armour_tier_section_row()
## above, for the Items tab's own Containers/Food/Miscellaneous
## sections.
func _add_item_group_section_row(grid: GridContainer, group_name: String, first: bool = false) -> void:
	var header_label := Label.new()
	header_label.text = group_name
	header_label.add_theme_font_size_override("font_size", 12)
	header_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	var header_margin := MarginContainer.new()
	if not first:
		header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_margin.add_child(header_label)
	grid.add_child(header_margin)
	for i in range(_SHOP_BUY_GRID_COLUMNS - 1):
		grid.add_child(Control.new())

## Per the request ("separate the shop weapon list by Skill type... add
## Reach, Damage and 'Qualities and Flaws' columns"): the Weapons tab's
## own column set — Item / Reach / Damage / Enc / Qualities and Flaws /
## Availability / Price / Actions, per the follow-up request that moved
## Price and Availability ("move the Price column to between Qualities
## and Actions. then move availability to between Qualities and
## Price"). Pulled out as shared constants (rather than local vars
## inside a single "build one grid" function) because _rebuild_weapons_list()
## now needs to add this SAME header row more than once to one shared
## grid — see that function's own comment for why.
const _WEAPON_GRID_TITLES: Array[String] = ["Item", "Reach", "Damage", "Enc", "Qualities and Flaws", "Availability", "Price", "Actions"]
const _WEAPON_GRID_ALIGNMENTS: Array[int] = [
	HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_CENTER,
	HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER,
	HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT,
]

## Per the follow-up request ("shorten the Item name column by 20% and
## give that space to the Qualities column"): both Item (column 0) and
## Qualities and Flaws (column 4) now expand to fill the grid's own
## spare width, at a 4:1 ratio — Item keeps 80% of the space it used to
## get 100% of, Qualities and Flaws gets the other 20%.
const _SHOP_WEAPON_EXPAND_COLUMNS: Dictionary = {0: 4.0, 4: 1.0}

## Just builds and configures the (currently empty) GridContainer
## itself — callers add their own header/section/data rows to it. See
## _rebuild_weapons_list() for why this is deliberately NOT a
## one-header-row-and-done builder like _new_buy_grid() above.
func _new_weapon_buy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _SHOP_WEAPON_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	return grid

## A skill-group name (e.g. "Basic", "Parry"), as a full "row" inside
## the ONE shared weapons grid — same trick as _add_owner_section_row()
## below (which the Sell list already uses for the same reason): every
## row in a GridContainer must contribute exactly `columns` children, so
## this fills column 0 with a real label and every other column with a
## bare empty spacer, making the row read as a section divider rather
## than a data row while keeping the grid's own column count consistent
## — which is exactly what keeps every section's Damage/Enc/Qualities
## columns lined up with each other. `first` skips the usual top margin
## for the very first section, since the grid itself already has
## breathing room above it from the tab layout.
func _add_weapon_group_section_row(grid: GridContainer, group_name: String, first: bool = false) -> void:
	var header_label := Label.new()
	header_label.text = group_name
	header_label.add_theme_font_size_override("font_size", 12)
	header_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	var header_margin := MarginContainer.new()
	if not first:
		header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_margin.add_child(header_label)
	grid.add_child(header_margin)
	for i in range(_SHOP_WEAPON_GRID_COLUMNS - 1):
		grid.add_child(Control.new())

## Per the follow-up request ("for the shop armor list, do a similar
## treatment... add Locations, APs and 'Qualities and Flaws'") and the
## later column-reorder request ("move price between Qualities and
## Actions. move Availability to between Qualities and Price"): the
## Armour tab's own column set, same reasoning as _WEAPON_GRID_TITLES
## above for why these are shared constants rather than local vars.
## Final order: Item / Locations / APs / Enc / Qualities and Flaws /
## Availability / Price / Actions — same Price/Availability-near-the-end
## shape the Weapons tab's own header already uses.
const _ARMOUR_GRID_TITLES: Array[String] = ["Item", "Locations", "APs", "Enc", "Qualities and Flaws", "Availability", "Price", "Actions"]
const _ARMOUR_GRID_ALIGNMENTS: Array[int] = [
	HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER,
	HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER,
	HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT,
]

## Per the request ("shorten item name field by 15% and add that [to]
## the Locations field"): Item (column 0) keeps 85% of the expand share
## it used to get all of, Locations (column 1) gets the other 15% — same
## "give some of Item's space to another column" trick
## _SHOP_WEAPON_EXPAND_COLUMNS already uses for the Weapons tab's own
## Qualities and Flaws column.
const _SHOP_ARMOUR_EXPAND_COLUMNS: Dictionary = {0: 0.85, 1: 0.15}

## As _new_weapon_buy_grid() above — just builds the empty grid, no
## header row added yet.
func _new_armour_buy_grid() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = _SHOP_ARMOUR_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	return grid

## As _add_weapon_group_section_row() above, for the Armour tab's
## tier sections (Light/Medium/Heavy) — same one-shared-grid fix,
## proactively applied here too since it's the identical root cause
## (independent per-tier GridContainers not sharing column widths),
## even though only the Weapons tab was reported.
func _add_armour_tier_section_row(grid: GridContainer, tier_name: String, first: bool = false) -> void:
	var header_label := Label.new()
	header_label.text = tier_name
	header_label.add_theme_font_size_override("font_size", 12)
	header_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
	var header_margin := MarginContainer.new()
	if not first:
		header_margin.add_theme_constant_override("margin_top", 10)
	header_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_margin.add_child(header_label)
	grid.add_child(header_margin)
	for i in range(_SHOP_ARMOUR_GRID_COLUMNS - 1):
		grid.add_child(Control.new())

## Per the request ("in the shops Items tab, separate Containers and
## Food into their own groups, and everything else is the Miscellaneous
## group"): item_stock (already alphabetical by item_name from
## _roll_stock()) is grouped into Containers/Food/Miscellaneous
## sections, in that fixed order (see _ITEM_GROUP_ORDER) — same
## one-shared-grid-with-section-header-rows pattern the Weapons/Armour
## tabs already use, so every section's columns stay aligned with each
## other (see _add_weapon_group_section_row's own comment on why a
## separate grid per section would drift out of alignment instead).
func _rebuild_items_list() -> void:
	_clear(items_list)
	if item_stock.is_empty():
		items_list.add_child(_none_in_stock_label())
		return

	var groups: Dictionary = {}   ## group name -> Array[ItemDefinition]
	for item in item_stock:
		var group_name := _item_group_name(item)
		if not groups.has(group_name):
			groups[group_name] = []
		groups[group_name].append(item)

	var grid := _new_items_buy_grid()
	var first_section := true
	for group_name in _ITEM_GROUP_ORDER:
		if not groups.has(group_name):
			continue
		_add_item_group_section_row(grid, group_name, first_section)
		first_section = false
		_shop_grid_header_row(grid, _ITEMS_GRID_TITLES, _ITEMS_GRID_ALIGNMENTS)
		for item: ItemDefinition in groups[group_name]:
			## Per the "packs and containers" request: a Container's own
			## Carries value used to sit right in the row itself; moved
			## into the tooltip now that the row only has room for
			## Item/Price/Enc columns (see the grid header above) —
			## still one hover away, just not competing with Price/Enc
			## for the row's own width.
			var tooltip: String = item.summary
			if item.container_slot != "":
				tooltip += "\nCarries %d — %s slot" % [item.container_capacity, item.container_slot]
			_add_buy_grid_row(grid, item.item_name, item.price_pennies, item.availability, item.encumbrance,
				tooltip, func(): _on_buy_item(item), false, [], Callable())
	items_list.add_child(grid)

## Per the request ("separate the shop weapon list by Skill type...
## remove the (Skill) in the item name... add Reach, Damage and
## 'Qualities and Flaws' columns"): weapon_stock (already alphabetical
## by weapon_name from _roll_stock()) is grouped into one section per
## skill_group — each section gets its own header label, rendered into
## a shared 8-column grid (see _new_weapon_buy_grid()), with a visual
## gap between sections exactly like the Ammunition section below
## already used between weapons and ammo. Now that the section header
## itself names the skill group, the item name no longer needs its own
## "(Skill)" suffix.
##
## Per the follow-up request ("separate the shop Weapons tab into 2
## subtabs, Melee and Ranged. Keep all melee weapons in one, and keep
## Ranged + Ammo in the other"): the single weapons_list VBoxContainer
## became two — melee_weapons_list and ranged_weapons_list, each its own
## subtab under the Weapons TabContainer — so this now builds two
## independent grids (one per subtab) instead of one grid holding both
## halves back to back. Each half is still internally alphabetical by
## skill_group, same sort as before; Ammunition stays appended at the
## bottom of the Ranged subtab, unchanged in spirit from when it sat at
## the bottom of the single combined list.
func _rebuild_weapons_list() -> void:
	_clear(melee_weapons_list)
	_clear(ranged_weapons_list)

	var groups: Dictionary = {}   ## skill_group -> Array[WeaponDefinition]
	for w in weapon_stock:
		if not groups.has(w.skill_group):
			groups[w.skill_group] = []
		groups[w.skill_group].append(w)
	## Every weapon in a given skill_group shares the same Melee/Ranged
	## split (it's Ranged iff the group itself is a Ranged specialisation
	## — see _is_weapon_trained's own comment on how Melee/Ranged skill
	## groups work), so the first weapon in each group is a reliable
	## sample to sort that whole group by.
	var melee_group_names: Array = []
	var ranged_group_names: Array = []
	for group_name in groups.keys():
		var sample: WeaponDefinition = groups[group_name][0]
		if sample.is_ranged:
			ranged_group_names.append(group_name)
		else:
			melee_group_names.append(group_name)
	melee_group_names.sort()
	ranged_group_names.sort()

	## --- Melee subtab -----------------------------------------------------
	if melee_group_names.is_empty():
		melee_weapons_list.add_child(_none_in_stock_label())
	else:
		## Per the bug report ("Parry weapons, columns Damage Enc and
		## Qualities are slightly out of line" — and the follow-up "Basic
		## weapons have the same issue... its the Very Short Reach that is
		## causing the miss-alignment"): every skill group used to get its
		## OWN separate GridContainer, and Godot sizes each GridContainer's
		## columns purely from that instance's own content. Fix: ONE
		## shared grid per subtab, with each skill group rendered as a
		## spanning section-header "row" plus a repeated column header
		## instead of a whole separate grid, so every column shares the
		## same width across that subtab.
		var melee_grid := _new_weapon_buy_grid()
		var first_melee_section := true
		for group_name in melee_group_names:
			_add_weapon_group_section_row(melee_grid, group_name, first_melee_section)
			first_melee_section = false
			_shop_grid_header_row(melee_grid, _WEAPON_GRID_TITLES, _WEAPON_GRID_ALIGNMENTS, _SHOP_WEAPON_EXPAND_COLUMNS)
			for w: WeaponDefinition in groups[group_name]:
				var untrained := not _is_weapon_trained(w)
				var tooltip: String = w.summary
				if untrained:
					tooltip += "\nUntrained: you have no advances in %s (%s) — you can still carry and swing it, just without any training bonus." % ["Ranged" if w.is_ranged else "Melee", w.skill_group]
				_add_weapon_buy_grid_row(melee_grid, w, untrained, tooltip)
		melee_weapons_list.add_child(melee_grid)

	## --- Ranged subtab (Ranged weapon groups + Ammunition) -----------------
	if ranged_group_names.is_empty() and ammo_stock.is_empty():
		ranged_weapons_list.add_child(_none_in_stock_label())
		return

	if not ranged_group_names.is_empty():
		var ranged_grid := _new_weapon_buy_grid()
		var first_ranged_section := true
		for group_name in ranged_group_names:
			_add_weapon_group_section_row(ranged_grid, group_name, first_ranged_section)
			first_ranged_section = false
			_shop_grid_header_row(ranged_grid, _WEAPON_GRID_TITLES, _WEAPON_GRID_ALIGNMENTS, _SHOP_WEAPON_EXPAND_COLUMNS)
			for w: WeaponDefinition in groups[group_name]:
				var untrained := not _is_weapon_trained(w)
				var tooltip: String = w.summary
				if untrained:
					tooltip += "\nUntrained: you have no advances in %s (%s) — you can still carry and swing it, just without any training bonus." % ["Ranged" if w.is_ranged else "Melee", w.skill_group]
				_add_weapon_buy_grid_row(ranged_grid, w, untrained, tooltip)
		ranged_weapons_list.add_child(ranged_grid)

	if not ammo_stock.is_empty():
		if not ranged_group_names.is_empty():
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(0, 10)
			ranged_weapons_list.add_child(gap)
		var ammo_header := Label.new()
		ammo_header.text = "Ammunition"
		ammo_header.add_theme_font_size_override("font_size", 12)
		ammo_header.add_theme_color_override("font_color", Color(0.75, 0.68, 0.5))
		ranged_weapons_list.add_child(ammo_header)
		var ammo_grid := _new_buy_grid()
		for item in ammo_stock:
			var tooltip := item.summary
			_add_buy_grid_row(ammo_grid, item.item_name, item.price_pennies, item.availability, item.encumbrance,
				tooltip, func(): _on_buy_item(item), false,
				AMMO_BUY_QUANTITIES, func(qty: int): _on_buy_item_quantity(item, qty))
		ranged_weapons_list.add_child(ammo_grid)

## Per the real book rule (p.116-117): within the grouped "Melee" skill,
## only the "Basic" specialisation is itself a Basic skill (usable
## untrained) — every other Melee group (Brawling, Cavalry, Fencing,
## Flail, Parry, Polearm, Two-Handed) is Advanced and needs real
## training, same as every Ranged group already is (Ranged has no
## "Basic" option at all). Character.has_skill() can't tell those two
## Melee cases apart on its own — it only reads the single "Melee"
## SkillDefinition's own is_advanced flag, which is false so that
## "Melee (Basic)" itself stays usable untrained — so this checks
## skill_advances directly for the Melee-but-not-Basic case instead of
## going through has_skill().
func _is_weapon_trained(w: WeaponDefinition) -> bool:
	if not w.is_ranged and w.skill_group == "Basic":
		return true
	var skill_def: SkillDefinition = GameData.skill_db.find_by_name("Ranged" if w.is_ranged else "Melee")
	if skill_def == null:
		return true
	return character.skill_advances.has(skill_def.display_name(w.skill_group))

## Per the follow-up request ("for the shop armor list, do a similar
## treatment... list them by Armor type (light/Medium/Heavy), and add
## Locations, APs and 'Qualities and Flaws'"): armour_stock (already
## alphabetical by armour_name from _roll_stock()) is grouped into one
## section per armor_tier, sections listed in the fixed Light -> Medium
## -> Heavy order the request itself named (not alphabetically, unlike
## the Weapons tab's skill-group sections — "Heavy" would otherwise
## sort before "Light") — each section gets its own header and its own
## 8-column grid (see _new_armour_buy_grid()), with a gap between
## sections, same convention the Weapons tab's own sections use. Now
## that the section header names the tier and APs has its own column,
## the item name no longer needs its own "(AP N)" suffix.
const _ARMOUR_TIER_ORDER: Array[String] = ["Light", "Medium", "Heavy"]

func _rebuild_armour_list() -> void:
	_clear(armour_list)
	if armour_stock.is_empty():
		armour_list.add_child(_none_in_stock_label())
		return

	var groups: Dictionary = {}   ## armor_tier -> Array[ArmourDefinition]
	for a in armour_stock:
		if not groups.has(a.armor_tier):
			groups[a.armor_tier] = []
		groups[a.armor_tier].append(a)

	## Same one-shared-grid fix as _rebuild_weapons_list() above — see
	## that function's own comment for the root cause.
	var grid := _new_armour_buy_grid()
	var first_section := true
	for tier in _ARMOUR_TIER_ORDER:
		if not groups.has(tier):
			continue
		_add_armour_tier_section_row(grid, tier, first_section)
		first_section = false
		_shop_grid_header_row(grid, _ARMOUR_GRID_TITLES, _ARMOUR_GRID_ALIGNMENTS, _SHOP_ARMOUR_EXPAND_COLUMNS)
		for a: ArmourDefinition in groups[tier]:
			_add_armour_buy_grid_row(grid, a, a.summary)
	armour_list.add_child(grid)

func _none_in_stock_label() -> Label:
	var lbl := Label.new()
	lbl.text = "(nothing Scarce came in this visit — check back another time)"
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
	return lbl

## Appends one boxed grid row (Item / Price / Enc / Actions) to `grid` —
## the shared row builder behind all three Buy tabs (Items/Weapons/
## Armour). Per the request: an item's own Item-column text turns red
## when the currently-selected character can't afford it OR (weapons
## only, via `untrained`) has no training in the weapon's own skill
## group — the exact same dual-cause single-colour "heads up" cue the
## old plain-HBoxContainer rows used, just now living on the Item cell
## specifically rather than one big info Label.
##
## `ammo_quantities`/`on_buy_qty` are only non-empty/valid for
## Ammunition-category items (see AMMO_BUY_QUANTITIES above) — when set,
## the Actions cell gets one button per quantity ("Buy 1"/"Buy 5"/
## "Buy 10") instead of the usual single "Buy" button, each individually
## disabled based on affording THAT quantity's own total cost.
func _add_buy_grid_row(grid: GridContainer, item_text: String, price: int, availability: String, enc: int, tooltip: String,
		on_buy: Callable, untrained: bool, ammo_quantities: Array, on_buy_qty: Callable) -> void:
	var unaffordable := character.get_total_pennies() < price
	var name_label := Label.new()
	name_label.text = "• " + item_text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if unaffordable or untrained:
		name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_BUY_GRID_COLUMNS)
	grid.add_child(item_cell)

	var price_label := Label.new()
	price_label.text = _format_price(price)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var price_cell := _shop_boxed_cell(price_label, 1, _SHOP_BUY_GRID_COLUMNS)
	grid.add_child(price_cell)

	## Per the request ("add a column to the Buy screen between price
	## and Enc to show the Item's Availability"): the settlement-odds
	## Common/Scarce/Rare tier this item rolled as part of _roll_stock()
	## — Common (the overwhelming majority of stock) shows plain, while
	## Scarce/Rare are tinted the same gold used for section headers so
	## the rarer, harder-to-restock finds are easy to spot while
	## scanning a long alphabetical list.
	var availability_label := Label.new()
	availability_label.text = availability
	availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	availability_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if availability != "Common":
		availability_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	var availability_cell := _shop_boxed_cell(availability_label, 2, _SHOP_BUY_GRID_COLUMNS)
	grid.add_child(availability_cell)

	var enc_label := Label.new()
	enc_label.text = str(enc)
	enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enc_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var enc_cell := _shop_boxed_cell(enc_label, 3, _SHOP_BUY_GRID_COLUMNS)
	grid.add_child(enc_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	var buy_triggers: Array = []
	if ammo_quantities.is_empty():
		var buy_btn := Button.new()
		buy_btn.text = "Buy"
		_style_compact_button(buy_btn)
		buy_btn.disabled = unaffordable
		buy_btn.pressed.connect(on_buy)
		actions_row.add_child(buy_btn)
		buy_triggers.append(buy_btn)
	else:
		for qty in ammo_quantities:
			var qty_btn := Button.new()
			qty_btn.text = "Buy %d" % qty
			_style_compact_button(qty_btn)
			qty_btn.disabled = character.get_total_pennies() < price * int(qty)
			qty_btn.pressed.connect(func(): on_buy_qty.call(qty))
			actions_row.add_child(qty_btn)
			buy_triggers.append(qty_btn)
	var actions_cell := _shop_boxed_cell(actions_row, 4, _SHOP_BUY_GRID_COLUMNS)
	grid.add_child(actions_cell)

	## Per the request ("change the outline of the item row... brighter
	## when hovering over a buy/sell button"): every cell in THIS row
	## brightens together while the pointer is over any of this row's
	## own Buy button(s) — a single-Buy row has one trigger, an ammo row
	## has three (Buy 1/5/10), all driving the same shared row highlight.
	_wire_row_hover_highlight([item_cell, price_cell, availability_cell, enc_cell, actions_cell], buy_triggers)

## Per the request ("separate the shop weapon list by Skill type... add
## Reach, Damage and 'Qualities and Flaws' columns too, all weapons
## fill these accordingly"): the Weapons tab's own 8-column row builder
## (Item/Price/Availability/Reach/Damage/Enc/Qualities and Flaws/
## Actions) — a dedicated sibling of _add_buy_grid_row rather than a
## variant of it, since Items/Armour never need Reach/Damage/Qualities
## and forcing those through the same shared signature would mean
## passing meaningless empty values from every non-weapon call site.
## Per the follow-up request ("move the Price column to between
## Qualities and Actions. then move availability to between Qualities
## and Price. Then lets shorten the Item name column by 20% and give
## that space to the Qualities column (also resize the text in the
## Qualities column, 1 size smaller)"): cells are now built in the new
## Item/Reach/Damage/Enc/Qualities and Flaws/Availability/Price/Actions
## order (columns 0-7) to match _new_weapon_buy_grid()'s own header —
## see _SHOP_WEAPON_EXPAND_COLUMNS for the Item/Qualities 4:1 width
## split, and _SHOP_ROW_FONT_SIZE - 1 below for the Qualities column's
## own smaller text.
func _add_weapon_buy_grid_row(grid: GridContainer, w: WeaponDefinition, untrained: bool, tooltip: String) -> void:
	var price := w.price_pennies
	var unaffordable := character.get_total_pennies() < price

	var name_label := Label.new()
	name_label.text = "• " + w.weapon_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if unaffordable or untrained:
		name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(item_cell)

	## Weapon Reach (p.296-297): Personal < Very Short < Short < Average
	## < Long < Very Long < Massive — see WeaponDefinition.reach.
	var reach_label := Label.new()
	reach_label.text = w.reach
	reach_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reach_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var reach_cell := _shop_boxed_cell(reach_label, 1, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(reach_cell)

	## Same "SB+N" / flat-number convention the old tooltip text used —
	## now a real column instead of a hover-only detail.
	var dmg_text := ("SB%+d" % w.damage_flat) if w.damage_mode == "strength_bonus_plus" else str(w.damage_flat)
	var damage_label := Label.new()
	damage_label.text = dmg_text
	damage_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damage_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var damage_cell := _shop_boxed_cell(damage_label, 2, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(damage_cell)

	var enc_label := Label.new()
	enc_label.text = str(w.encumbrance)
	enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enc_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var enc_cell := _shop_boxed_cell(enc_label, 3, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(enc_cell)

	## `qualities` holds both real Qualities (Fast, Precise...) and
	## Flaws (Slow, Undamaging...) in one array — the data doesn't
	## distinguish the two, so both just get listed together under this
	## one column, matching the column's own "Qualities and Flaws" title.
	## One size smaller than every other cell's text, per the request.
	##
	## Per the follow-up request ("Weapons/Armor Qualities, live side by
	## side with these Item Qualities"): the general Trapping
	## item_qualities/item_flaws (Fine, Durable, Lightweight, Practical /
	## Ugly, Shoddy — see ItemQualityRules) are appended after the
	## combat qualities, separated by " | " so the two distinct systems
	## stay visually distinguishable rather than blending into one list.
	var qualities_label := Label.new()
	qualities_label.text = ItemQualityRules.combined_display(w.qualities, w.item_qualities, w.item_flaws)
	qualities_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	qualities_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE - 1)
	var qualities_cell := _shop_boxed_cell(qualities_label, 4, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(qualities_cell)

	var availability_label := Label.new()
	availability_label.text = w.availability
	availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	availability_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if w.availability != "Common":
		availability_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	var availability_cell := _shop_boxed_cell(availability_label, 5, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(availability_cell)

	var price_label := Label.new()
	price_label.text = _format_price(price)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var price_cell := _shop_boxed_cell(price_label, 6, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(price_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	_style_compact_button(buy_btn)
	buy_btn.disabled = unaffordable
	buy_btn.pressed.connect(func(): _on_buy_weapon(w))
	actions_row.add_child(buy_btn)
	var actions_cell := _shop_boxed_cell(actions_row, 7, _SHOP_WEAPON_GRID_COLUMNS, _SHOP_WEAPON_EXPAND_COLUMNS)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight(
		[item_cell, reach_cell, damage_cell, enc_cell, qualities_cell, availability_cell, price_cell, actions_cell],
		[buy_btn])

## Per the follow-up request ("for the shop armor list, do a similar
## treatment... add Locations, APs and 'Qualities and Flaws' too all
## armor fill these accordingly with those values") and the later
## column-reorder request ("move price between Qualities and Actions.
## move Availability to between Qualities and Price. shorten item name
## field by 15% and add that [to] the Locations field"): the Armour
## tab's own 8-column row builder — Item/Locations/APs/Enc/Qualities and
## Flaws/Availability/Price/Actions — a dedicated sibling of
## _add_weapon_buy_grid_row, same reasoning: Items never needs
## Locations/APs/Qualities, so a shared signature would just mean empty
## placeholder values from every non-armour call site.
func _add_armour_buy_grid_row(grid: GridContainer, a: ArmourDefinition, tooltip: String) -> void:
	var price := a.price_pennies
	var unaffordable := character.get_total_pennies() < price

	var name_label := Label.new()
	name_label.text = "• " + a.armour_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = tooltip
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if unaffordable:
		name_label.add_theme_color_override("font_color", Color(0.82, 0.35, 0.32))
	var item_cell := _shop_boxed_cell(name_label, 0, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(item_cell)

	## Hit Locations this piece covers (Head/Body/Arms/Legs — see
	## _format_locations() for how Left/Right Arm and Left/Right Leg
	## collapse into that single shared word).
	var locations_label := Label.new()
	locations_label.text = _format_locations(a.locations)
	locations_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	locations_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var locations_cell := _shop_boxed_cell(locations_label, 1, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(locations_cell)

	var ap_label := Label.new()
	ap_label.text = str(a.armour_points)
	ap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ap_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var ap_cell := _shop_boxed_cell(ap_label, 2, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(ap_cell)

	var enc_label := Label.new()
	enc_label.text = str(a.encumbrance)
	enc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	enc_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var enc_cell := _shop_boxed_cell(enc_label, 3, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(enc_cell)

	## `qualities` holds both real Qualities (Flexible...) and Flaws
	## (Partial, Weakpoints...) in one array, same convention the
	## Weapons tab's own Qualities and Flaws column already uses.
	## item_qualities/item_flaws (Lightweight, Durable, Fine, Practical /
	## Ugly, Shoddy — see ItemQualityRules) are a separate system that
	## "lives side by side" per the request, so appended after a " | "
	## separator rather than merged into the same list.
	var qualities_label := Label.new()
	qualities_label.text = ItemQualityRules.combined_display(a.qualities, a.item_qualities, a.item_flaws)
	qualities_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	qualities_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var qualities_cell := _shop_boxed_cell(qualities_label, 4, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(qualities_cell)

	var availability_label := Label.new()
	availability_label.text = a.availability
	availability_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	availability_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	if a.availability != "Common":
		availability_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35))
	var availability_cell := _shop_boxed_cell(availability_label, 5, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(availability_cell)

	var price_label := Label.new()
	price_label.text = _format_price(price)
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var price_cell := _shop_boxed_cell(price_label, 6, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(price_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	_style_compact_button(buy_btn)
	buy_btn.disabled = unaffordable
	buy_btn.pressed.connect(func(): _on_buy_armour(a))
	actions_row.add_child(buy_btn)
	var actions_cell := _shop_boxed_cell(actions_row, 7, _SHOP_ARMOUR_GRID_COLUMNS, _SHOP_ARMOUR_EXPAND_COLUMNS)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight(
		[item_cell, locations_cell, ap_cell, enc_cell, qualities_cell, availability_cell, price_cell, actions_cell],
		[buy_btn])

## Per the follow-up request ("in the location combine right/left Arm
## into one word, eg, Arms, and do the same for Legs"): only combines
## when a piece covers BOTH sides of a pair — a piece covering just one
## arm/leg (if one ever exists) still reads "Left Arm"/"Right Arm" (or
## Leg) as-is, since collapsing it to the bare "Arms"/"Legs" would
## overstate its real coverage.
func _format_locations(locations: Array[String]) -> String:
	if locations.is_empty():
		return "-"
	var both_arms := locations.has("Left Arm") and locations.has("Right Arm")
	var both_legs := locations.has("Left Leg") and locations.has("Right Leg")
	var display: Array[String] = []
	var arms_added := false
	var legs_added := false
	for loc in locations:
		if both_arms and (loc == "Left Arm" or loc == "Right Arm"):
			if not arms_added:
				display.append("Arms")
				arms_added = true
		elif both_legs and (loc == "Left Leg" or loc == "Right Leg"):
			if not legs_added:
				display.append("Legs")
				legs_added = true
		else:
			display.append(loc)
	return ", ".join(display)

## Per the request ("show all character in the groups inventory on the
## right"): every present party member's own pack, grouped under their
## own name header — not just the character currently being shopped
## for — so gear can be reviewed, equipped, or sold no matter who's
## actually carrying it right now. Each member's items are still
## locked alphabetically for the same reshuffle-avoidance reason the
## single-character version already had.
## Per the follow-up request ("make sure each character's column lines
## up with the one above it, right now Mira Wren's rows are differently
## spaced out to Eric Troller"): ONE single GridContainer for the whole
## Party Inventory section, not one separate GridContainer per member.
## A GridContainer only ever computes uniform column widths from ITS
## OWN children — a separate grid per member meant each one sized its
## own Item/Qty/Price/Actions columns purely from that one member's own
## item names/button counts, so two members' columns had no reason to
## land at the same X position at all. Sharing one grid (and one header
## row, shown once at the top rather than repeated per member) makes
## every column's width computed from the WHOLE party's content at
## once, so they genuinely line up top to bottom regardless of which
## member happens to be shown where.
func _rebuild_sell_list() -> void:
	_clear(sell_list)
	var members_with_items: Array[Character] = []
	var member_orders: Dictionary = {}   ## Character -> Array[String], member_counts: Character -> Dictionary
	var member_counts: Dictionary = {}
	for member: Character in GameState.party:
		var counts: Dictionary = {}
		var order: Array[String] = []
		for item_name in member.inventory:
			## Per the follow-up request ("show favourited items in all
			## shop screens, and allow staring/unstaring from that
			## screen"): favourited items now DO appear in this sell
			## list (with a filled star and no Sell button — see
			## _add_sell_grid_row) rather than being hidden entirely.
			## The separate Equipped list above (_rebuild_equipped_list)
			## still reads equip state directly, not this list, so an
			## equipped-and-favourited item still shows there too.
			if not counts.has(item_name):
				order.append(item_name)
			counts[item_name] = counts.get(item_name, 0) + 1
		## Per the further follow-up request ("dont double show equipped
		## items in the shop, show those only in the Equipped gear
		## section"): the Equipped Gear box above only ever shows the
		## currently-SELECTED character's own gear (_rebuild_equipped_list
		## reads `character`, not `member`) — so it's only a genuine
		## duplicate for `member == character`, and only once every last
		## carried copy is actually equipped/worn (spare count <= 0, via
		## the same _get_spare_sellable_count this row's own Sell button
		## already gates on — nothing left here to Sell or Equip
		## elsewhere, so the row would show zero real actions anyway).
		## A DIFFERENT party member's equipped item still needs to stay
		## here — this list is the only place their gear is visible on
		## this screen at all, and it still offers "Give & Equip" to pull
		## it onto the selected character. A partially-spare item (e.g.
		## one of two Daggers equipped, one still spare) also stays,
		## since that spare copy is real, actionable inventory the
		## Equipped Gear box doesn't show at all.
		if member == character:
			var filtered_order: Array[String] = []
			for item_name in order:
				if _get_spare_sellable_count(member, item_name, counts[item_name]) > 0:
					filtered_order.append(item_name)
			order = filtered_order
		## Per the request ("Broken item[s]... have only 10% their
		## original value"): a member carrying ONLY broken armour (no
		## normal spare inventory) still needs their own section here so
		## that armour can actually be sold off.
		var has_broken := false
		for piece_name in member.broken_armour.keys():
			if int(member.broken_armour[piece_name]) > 0:
				has_broken = true
				break
		if order.is_empty() and not has_broken:
			continue
		order.sort()
		members_with_items.append(member)
		member_orders[member] = order
		member_counts[member] = counts

	if members_with_items.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "(nobody in the party is carrying anything)"
		none_lbl.add_theme_font_size_override("font_size", 11)
		none_lbl.add_theme_color_override("font_color", Color(0.6, 0.55, 0.48))
		sell_list.add_child(none_lbl)
		return

	## Per the original request ("transfer the inventory grid layout to
	## the shop windows... more compact") and the follow-up ("show
	## favourited items in all shop screens, and allow staring/
	## unstaring from that screen"): a real boxed grid — Star / Item /
	## Qty / Price / Actions — matching the Inventory tab's own 5-column
	## layout, so favouriting works the same way in both places.
	var grid := GridContainer.new()
	grid.columns = _SHOP_GRID_COLUMNS
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 1)
	var titles: Array[String] = ["", "Item", "Qty", "Price", "Actions"]
	var alignments: Array[int] = [HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_RIGHT, HORIZONTAL_ALIGNMENT_LEFT]
	_shop_grid_header_row(grid, titles, alignments, {1: 1.0})
	for member in members_with_items:
		_add_owner_section_row(grid, member)
		for item_name in member_orders[member]:
			_add_sell_grid_row(grid, member, item_name, member_counts[member][item_name])
		for piece_name in member.broken_armour.keys():
			var broken_count: int = int(member.broken_armour[piece_name])
			if broken_count > 0:
				_add_broken_sell_grid_row(grid, member, piece_name, broken_count)
	sell_list.add_child(grid)

## A member's own name, as a full "row" inside the shared grid above —
## still `_SHOP_GRID_COLUMNS` children (GridContainer requires every row
## to contribute exactly `columns` children), but only the Item cell
## actually shows anything: an unboxed, larger, coloured Label (not one
## of the boxed item-row cells), with every other column (including the
## new Star column at 0 — a section divider isn't a real item, nothing
## to favourite) left as a bare empty spacer so this row visually reads
## as a section divider, not another data row, while still keeping the
## grid's own column count consistent. The Star spacer at column 0 is
## added separately from the rest so the name Label's own
## SIZE_EXPAND_FILL lands in column 1 (Item) rather than column 0,
## matching the header row's own expand_columns = {1: 1.0}.
func _add_owner_section_row(grid: GridContainer, member: Character) -> void:
	grid.add_child(Control.new())
	var name_label := Label.new()
	name_label.text = "%s%s" % [member.character_name, "  (shopping)" if member == character else ""]
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35) if member == character else Color(0.75, 0.68, 0.5))
	var name_margin := MarginContainer.new()
	name_margin.add_theme_constant_override("margin_top", 4)
	name_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_margin.add_child(name_label)
	grid.add_child(name_margin)
	for i in range(_SHOP_GRID_COLUMNS - 2):
		grid.add_child(Control.new())

## Appends one boxed grid row (Star / Item / Qty / Price / Actions) for
## (owner, item_name) — whatever mix of Equip and Sell controls actually
## apply: a weapon/armour piece already owned by the SELECTED character
## gets the same real Equip/Unequip buttons the Equipment tab has; one
## owned by someone else gets a single "Give & Equip" shortcut (see
## _on_give_and_equip_weapon/_armour); a plain Item gets neither. "Sell
## 1" only shows when there's at least one spare copy AND the item isn't
## favourited, and "Sell All (N)" only appears alongside it once there's
## MORE than one spare — unchanged from the per-row behaviour, just
## re-skinned into a grid cell instead of a bare HBoxContainer. The
## owner's name no longer needs to be repeated inline on every row (the
## old " [Name]" tag) — it's now the grid's own group header above, per
## the earlier "show all characters in the group's inventory" request.
##
## Per the follow-up request ("show favourited items in all shop
## screens, and allow staring/unstaring from that screen"): column 0 is
## now a real Star toggle button, same ★/☆ convention as the Character
## Menu's own Inventory tab (see character_menu_screen.gd's
## _rebuild_inventory) — clicking it toggles `owner.favourite_items` and
## rebuilds this list in place, no need to leave the Shop to do it. A
## favourited item stays fully visible and priced here, it just loses
## its Sell button(s) (see the `not is_favourite` gate below) until
## un-favourited again — matching the Character Menu's own "protects it
## from being dropped/sold" framing, just enforced here instead of by
## hiding the row outright.
func _add_sell_grid_row(grid: GridContainer, owner: Character, item_name: String, count: int) -> void:
	var is_favourite: bool = owner.favourite_items.has(item_name)
	var star_btn := Button.new()
	star_btn.text = "★" if is_favourite else "☆"
	star_btn.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	star_btn.add_theme_color_override("font_color", Color(0.85, 0.7, 0.35) if is_favourite else Color(0.55, 0.5, 0.42))
	star_btn.tooltip_text = "Favourited — protected from being sold (click to un-favourite)" if is_favourite else "Favourite this item (protects it from being sold)"
	_style_compact_button(star_btn)
	star_btn.pressed.connect(func():
		if owner.favourite_items.has(item_name):
			owner.favourite_items.erase(item_name)
		else:
			owner.favourite_items.append(item_name)
		_rebuild_sell_list())
	var star_cell := _shop_boxed_cell(star_btn, 0, _SHOP_GRID_COLUMNS, {})
	grid.add_child(star_cell)

	var name_label := Label.new()
	name_label.text = "• " + item_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var item_cell := _shop_boxed_cell(name_label, 1, _SHOP_GRID_COLUMNS, {1: 1.0})
	grid.add_child(item_cell)

	var qty_label := Label.new()
	qty_label.text = str(count)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var qty_cell := _shop_boxed_cell(qty_label, 2)
	grid.add_child(qty_cell)

	var price := _find_sell_price(item_name)
	var price_label := Label.new()
	price_label.text = _format_price(price) if price > 0 else "—"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var price_cell := _shop_boxed_cell(price_label, 3)
	grid.add_child(price_cell)

	## Per the follow-up request ("move the sell buttons for the far
	## right side of the row, but leave the equip buttons where they
	## are"): Equip/Unequip/Give & Equip stay left, right after the
	## Price column, exactly where they always were — Sell 1/"All (N)"
	## move into their own group pinned to the Actions cell's own far
	## right edge instead of just sitting immediately next to whatever
	## equip buttons happen to be on that particular row. An expanding
	## spacer between the two groups (with actions_row itself stretched
	## to fill the whole cell) is what actually pushes the Sell group
	## right — without it, a row with fewer/no equip buttons would just
	## leave the Sell buttons sitting wherever the equip group left off,
	## not aligned with the Sell buttons on the rows above/below it.
	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var w: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
	var a: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
	if w != null:
		if owner == character:
			for btn in _weapon_equip_buttons(item_name, w, count):
				_style_compact_button(btn)
				actions_row.add_child(btn)
		else:
			var give_btn := Button.new()
			give_btn.text = "Give & Equip"
			_style_compact_button(give_btn)
			give_btn.pressed.connect(func(): _on_give_and_equip_weapon(owner, item_name))
			actions_row.add_child(give_btn)
	elif a != null:
		if owner == character:
			var eq_btn := _armour_equip_button(item_name)
			_style_compact_button(eq_btn)
			actions_row.add_child(eq_btn)
		else:
			var give_btn2 := Button.new()
			give_btn2.text = "Give & Equip"
			_style_compact_button(give_btn2)
			give_btn2.pressed.connect(func(): _on_give_and_equip_armour(owner, item_name))
			actions_row.add_child(give_btn2)

	var sell_spacer := Control.new()
	sell_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(sell_spacer)

	var sell_triggers: Array = []
	## Per the follow-up request: a favourited item stays visible here
	## but is protected from being sold — no Sell button(s) at all while
	## the star is filled, regardless of spare count. Un-favouriting it
	## (via the Star button above) rebuilds this list and the Sell
	## button(s) reappear normally.
	if price > 0 and not is_favourite:
		var spare := _get_spare_sellable_count(owner, item_name, count)
		if spare > 0:
			var sell_btn := Button.new()
			sell_btn.text = "Sell 1"
			_style_compact_button(sell_btn)
			sell_btn.pressed.connect(func(): _on_sell(owner, item_name, price))
			actions_row.add_child(sell_btn)
			sell_triggers.append(sell_btn)
			if spare > 1:
				var sell_all_btn := Button.new()
				sell_all_btn.text = "All (%d)" % spare
				_style_compact_button(sell_all_btn)
				sell_all_btn.pressed.connect(func(): _on_sell_all_item(owner, item_name, price))
				actions_row.add_child(sell_all_btn)
				sell_triggers.append(sell_all_btn)
	var actions_cell := _shop_boxed_cell(actions_row, 4)
	grid.add_child(actions_cell)

	## Per the request ("change the outline of the item row... brighter
	## when hovering over a buy/sell button"): only the Sell button(s)
	## trigger this — not Equip/Unequip/Give & Equip, which already have
	## their own obvious state — Sell is the one action that's easy to
	## misclick on a row that spans nearly the whole panel, so it's the
	## one that gets the extra "this is definitely the row you're about
	## to sell from" cue.
	_wire_row_hover_highlight([star_cell, item_cell, qty_cell, price_cell, actions_cell], sell_triggers)

## A Broken armour piece's own row (per the request: "Broken item[s]...
## have only 10% their original value") — always fully "spare" (a
## Broken piece is never equipped — see Character.damage_armour_piece,
## which unequips it the instant it breaks), so no Equip/Give & Equip
## controls, just a Sell 1 / Sell All at the reduced salvage price.
##
## Broken armour isn't tracked by `favourite_items` at all (that field
## is keyed by names in `inventory`, not `broken_armour` — see
## Character.favourite_items' own doc comment), so there's nothing to
## favourite/star here — column 0 is just a bare empty spacer, matching
## _add_owner_section_row's own convention, so the grid's column count
## still lines up with every other row.
func _add_broken_sell_grid_row(grid: GridContainer, owner: Character, piece_name: String, count: int) -> void:
	var star_cell := _shop_boxed_cell(Control.new(), 0, _SHOP_GRID_COLUMNS, {})
	grid.add_child(star_cell)

	var name_label := Label.new()
	name_label.text = "• %s (Broken)" % piece_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	name_label.add_theme_color_override("font_color", Color(0.75, 0.45, 0.4))
	var item_cell := _shop_boxed_cell(name_label, 1, _SHOP_GRID_COLUMNS, {1: 1.0})
	grid.add_child(item_cell)

	var qty_label := Label.new()
	qty_label.text = str(count)
	qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	qty_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var qty_cell := _shop_boxed_cell(qty_label, 2)
	grid.add_child(qty_cell)

	var price := _find_broken_sell_price(piece_name)
	var price_label := Label.new()
	price_label.text = _format_price(price) if price > 0 else "—"
	price_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price_label.add_theme_font_size_override("font_size", _SHOP_ROW_FONT_SIZE)
	var price_cell := _shop_boxed_cell(price_label, 3)
	grid.add_child(price_cell)

	var actions_row := HBoxContainer.new()
	actions_row.add_theme_constant_override("separation", 4)
	actions_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sell_spacer := Control.new()
	sell_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions_row.add_child(sell_spacer)

	var sell_triggers: Array = []
	if price > 0:
		var sell_btn := Button.new()
		sell_btn.text = "Sell 1"
		_style_compact_button(sell_btn)
		sell_btn.pressed.connect(func(): _on_sell_broken(owner, piece_name, price))
		actions_row.add_child(sell_btn)
		sell_triggers.append(sell_btn)
		if count > 1:
			var sell_all_btn := Button.new()
			sell_all_btn.text = "All (%d)" % count
			_style_compact_button(sell_all_btn)
			sell_all_btn.pressed.connect(func(): _on_sell_all_broken(owner, piece_name, price))
			actions_row.add_child(sell_all_btn)
			sell_triggers.append(sell_all_btn)
	var actions_cell := _shop_boxed_cell(actions_row, 4)
	grid.add_child(actions_cell)

	_wire_row_hover_highlight([star_cell, item_cell, qty_cell, price_cell, actions_cell], sell_triggers)

## Shared with _on_sell/_on_sell_all_item — how many spare (non-
## equipped) copies of this item `owner` can actually sell. Weapon: at
## most 1 equipped in the main hand; off-hand: at most 1; Armour:
## however many equipped pieces share this exact name. Takes `owner`
## explicitly now that this whole list spans the whole party, not just
## the character currently being shopped for.
func _get_spare_sellable_count(owner: Character, item_name: String, carried_count: int) -> int:
	var equipped_count := 0
	if item_name == owner.equipped_weapon:
		equipped_count += 1
	if item_name == owner.equipped_offhand:
		equipped_count += 1
	equipped_count += owner.equipped_armour.count(item_name)
	## Per the "packs and containers" request: same "still needed while
	## worn" protection as every other equip slot above.
	for slot in ["Back", "Waist", "Shoulder"]:
		if item_name == owner.get_equipped_container(slot):
			equipped_count += 1
	## Per the follow-up request: a light source shares the main/off-hand
	## checks above now (it's no longer a separate slot), so an equipped
	## Lantern/Candle/etc is already covered — nothing extra needed here.
	return carried_count - equipped_count

## Checks Items, Weapons, and Armour databases in turn — a sellable
## inventory entry could be any of the three. Weapons and the shop's
## own Light/Medium/Heavy Armour now have real book prices, sold at
## half list like everything else; the older, detailed armour pieces
## (Leather Jack, Mail Coat, etc.) still have no price set, so they
## fall through to a documented Encumbrance-based estimate instead of
## being unsellable outright.
## Per the request: Cooked Meal is explicitly excluded from what a
## shop will buy back, regardless of its own price_pennies — checked
## before any database lookup so it's excluded no matter which
## database it might otherwise resolve through.
const UNSELLABLE_ITEMS := ["Cooked Meal", "Stolen Idol"]

## Per the follow-up request ("item sell review, lets make it so any
## item is sellable, even starting trappings"): a lot of starting kit
## from class_trappings_table.gd — "Cloak", "Clothing", "Pouch", "Hat",
## and bundled display strings like "Backpack containing Tinderbox,
## Blanket, Rations (1 day)" — has no matching ItemDefinition/
## WeaponDefinition/ArmourDefinition at all, so _find_sell_price used
## to fall all the way through to 0 and the Shop would just never offer
## a Sell button for it (see _party_item_row's own `if price > 0:`
## gate). That was never a deliberate exclusion — UNSELLABLE_ITEMS just
## above is where an item is meant to be genuinely unsellable — it was
## just nothing left to price it against. This small flat nominal price
## is the fallback for exactly that case, so every carried item is
## genuinely sellable without writing a full resource for each one.
const FALLBACK_SELL_PRICE_PENNIES := 12

func _find_sell_price(item_name: String) -> int:
	if UNSELLABLE_ITEMS.has(item_name):
		return 0
	var it: ItemDefinition = GameData.item_db.find_by_name(item_name)
	if it != null:
		## Per the request ("note there should be 12/a dozen when
		## buying them"): price_pennies on a bundle item like Candle
		## (dozen) is the price for the WHOLE purchase (all 12 units),
		## not one unit — _on_buy_item() below explodes a purchase into
		## purchase_bundle_quantity separate inventory copies, so each
		## one has to sell for its fair per-unit share of that price,
		## not the whole-bundle price all over again. Without this, 12
		## exploded copies of a 12d dozen would each resell for 6d — 72d
		## total, an easy buy-low/sell-high exploit on a single click.
		if it.purchase_bundle_quantity > 1:
			return int((float(it.price_pennies) / it.purchase_bundle_quantity) * SELL_FRACTION)
		return int(it.price_pennies * SELL_FRACTION)
	var w: WeaponDefinition = GameData.weapon_db.find_by_name(item_name)
	if w != null:
		if w.price_pennies > 0:
			return int(w.price_pennies * SELL_FRACTION)
		return int((100 + w.encumbrance * 40) * SELL_FRACTION)
	var a: ArmourDefinition = GameData.armour_db.find_by_name(item_name)
	if a != null:
		if a.price_pennies > 0:
			return int(a.price_pennies * SELL_FRACTION)
		return int((80 + a.encumbrance * 40) * SELL_FRACTION)
	return int(FALLBACK_SELL_PRICE_PENNIES * SELL_FRACTION)

## Per the request ("Broken item[s]... have only 10% their original
## value"): unlike _find_sell_price above (half list price), a Broken
## piece only ever has its own real list price to go on — no
## Encumbrance-based fallback estimate, since a piece with no list price
## set was never sellable at full condition either.
func _find_broken_sell_price(piece_name: String) -> int:
	var a: ArmourDefinition = GameData.armour_db.find_by_name(piece_name)
	if a == null or a.price_pennies <= 0:
		return 0
	return int(a.price_pennies * BROKEN_SELL_FRACTION)

func _on_buy_item(item: ItemDefinition) -> void:
	if not character.spend_pennies(item.price_pennies):
		message_label.text = "You can't afford that."
		return
	## Per the request ("note there should be 12/a dozen when buying
	## them"): a bundle item like Candle (dozen) grants
	## purchase_bundle_quantity individually-trackable copies for the
	## one price_pennies spend above — every other item's quantity is 1,
	## so this is a no-op for them, same single-copy purchase as before.
	for i in range(item.purchase_bundle_quantity):
		character.inventory.append(item.item_name)
	if item.purchase_bundle_quantity > 1:
		message_label.text = "Bought %d x %s for %s." % [item.purchase_bundle_quantity, item.item_name, _format_price(item.price_pennies)]
	else:
		message_label.text = "Bought %s for %s." % [item.item_name, _format_price(item.price_pennies)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Per the request ("allow any ammo to be bought in 1/5/10 quantities"):
## a single purchase of `qty` copies at once — one spend_pennies() call
## against the combined total (not `qty` separate spends), so this is
## still an all-or-nothing transaction, same as any other purchase.
func _on_buy_item_quantity(item: ItemDefinition, qty: int) -> void:
	var total_cost := item.price_pennies * qty
	if not character.spend_pennies(total_cost):
		message_label.text = "You can't afford that."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	for i in range(qty):
		character.inventory.append(item.item_name)
	message_label.text = "Bought %d x %s for %s." % [qty, item.item_name, _format_price(total_cost)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _on_buy_weapon(w: WeaponDefinition) -> void:
	if not character.spend_pennies(w.price_pennies):
		message_label.text = "You can't afford that."
		return
	character.inventory.append(w.weapon_name)
	message_label.text = "Bought %s for %s." % [w.weapon_name, _format_price(w.price_pennies)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _on_buy_armour(a: ArmourDefinition) -> void:
	if not character.spend_pennies(a.price_pennies):
		message_label.text = "You can't afford that."
		return
	character.inventory.append(a.armour_name)
	message_label.text = "Bought %s for %s." % [a.armour_name, _format_price(a.price_pennies)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## `owner` is whichever party member's row this button sits on — not
## necessarily the character currently being shopped for, now that the
## list spans the whole party. Proceeds always land in the shared
## party purse regardless of which member's stack they came from (see
## Character.gold_crowns/silver_shillings/brass_pennies — every member
## but party[0] just mirrors party[0]'s own totals).
func _on_sell(owner: Character, item_name: String, price: int) -> void:
	if not owner.inventory.has(item_name):
		return
	## Only block the sale if there's nothing SPARE to sell — a
	## character carrying 2 Swords with 1 equipped should be able
	## to sell the other one, not be blocked outright just because the
	## name matches something equipped. This should already be
	## impossible to trigger from the UI now that the sell list hides
	## unsellable rows entirely, but kept as a real safety check rather
	## than assuming the UI is the only caller.
	var carried_count := owner.inventory.count(item_name)
	if _get_spare_sellable_count(owner, item_name, carried_count) <= 0:
		message_label.text = "%s is wearing/wielding all of their %s — nothing spare to sell." % [owner.character_name, item_name]
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	owner.inventory.erase(item_name)
	owner.add_pennies(price)
	message_label.text = "Sold %s for %s." % [item_name, _format_price(price)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Per the follow-up request ("move sell all to being Per item"): sells
## every spare copy of THIS ONE item from THIS ONE owner — the row-
## level replacement for the old single global Sell All button, which
## used to sweep the whole pack at once. Only ever shown (see
## _party_item_row) when there's more than one spare copy to begin
## with, so the plain "Sell 1" button already covers the single-spare
## case.
func _on_sell_all_item(owner: Character, item_name: String, price: int) -> void:
	var carried_count := owner.inventory.count(item_name)
	var spare := _get_spare_sellable_count(owner, item_name, carried_count)
	if spare <= 0:
		return
	for i in range(spare):
		owner.inventory.erase(item_name)
	var total := price * spare
	owner.add_pennies(total)
	message_label.text = "Sold %d x %s for %s." % [spare, item_name, _format_price(total)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## A Broken armour piece's own Sell 1 — always fully spare (a Broken
## piece is never equipped), sold at the reduced salvage price.
func _on_sell_broken(owner: Character, piece_name: String, price: int) -> void:
	var count: int = int(owner.broken_armour.get(piece_name, 0))
	if count <= 0:
		return
	count -= 1
	if count <= 0:
		owner.broken_armour.erase(piece_name)
	else:
		owner.broken_armour[piece_name] = count
	owner.add_pennies(price)
	message_label.text = "Sold Broken %s for %s." % [piece_name, _format_price(price)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## As _on_sell_broken, but every Broken copy of this piece at once —
## the row-level "All (N)" counterpart, same as _on_sell_all_item above.
func _on_sell_all_broken(owner: Character, piece_name: String, price: int) -> void:
	var count: int = int(owner.broken_armour.get(piece_name, 0))
	if count <= 0:
		return
	owner.broken_armour.erase(piece_name)
	var total := price * count
	owner.add_pennies(total)
	message_label.text = "Sold %d x Broken %s for %s." % [count, piece_name, _format_price(total)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

## Per the request ("add back Sell all — sells all sellable items from
## all characters at once"): a single top-level action that sweeps
## every present party member's own pack in one go — the global
## counterpart to the per-row "Sell 1"/"Sell All (N)" buttons above,
## which only ever touch one (owner, item) at a time. Reuses the exact
## same price/spare-count/favourite rules those already use (an earlier
## version of this screen had a single-character-only Sell All that
## this deliberately widens to the whole party, matching the request's
## own "from all characters" wording), so nothing sellable here is ever
## something the per-row buttons wouldn't also have offered.
func _on_sell_all() -> void:
	var total_earned := 0
	var items_sold := 0
	for member: Character in GameState.party:
		var counts: Dictionary = {}
		for item_name in member.inventory:
			if member.favourite_items.has(item_name):
				continue
			counts[item_name] = counts.get(item_name, 0) + 1
		for item_name in counts.keys():
			var price := _find_sell_price(item_name)
			if price <= 0:
				continue
			var spare := _get_spare_sellable_count(member, item_name, counts[item_name])
			if spare <= 0:
				continue
			for i in range(spare):
				member.inventory.erase(item_name)
			total_earned += price * spare
			items_sold += spare
		## Broken armour: always fully spare (never equippable — see
		## Character.damage_armour_piece), sold at the same reduced 10%
		## rate its own dedicated Sell button uses.
		for piece_name in member.broken_armour.keys().duplicate():
			var bcount: int = int(member.broken_armour.get(piece_name, 0))
			if bcount <= 0:
				continue
			var bprice := _find_broken_sell_price(piece_name)
			if bprice <= 0:
				continue
			total_earned += bprice * bcount
			items_sold += bcount
			member.broken_armour.erase(piece_name)

	if items_sold <= 0:
		message_label.text = "Nothing sellable in the party's packs right now."
		message_label.add_theme_color_override("font_color", Color(0.85, 0.6, 0.55))
		return
	character.add_pennies(total_earned)
	message_label.text = "Sold %d item(s) across the party for %s." % [items_sold, _format_price(total_earned)]
	message_label.add_theme_color_override("font_color", Color(0.6, 0.8, 0.55))
	GameState.autosave()
	_rebuild_all()

func _format_price(pennies: int) -> String:
	if pennies >= Character.PENNIES_PER_CROWN:
		var gc := pennies / float(Character.PENNIES_PER_CROWN)
		return "%.1f GC" % gc if pennies % Character.PENNIES_PER_CROWN != 0 else "%d GC" % int(gc)
	elif pennies >= Character.PENNIES_PER_SHILLING:
		var ss := int(pennies / Character.PENNIES_PER_SHILLING)
		var rem := pennies % Character.PENNIES_PER_SHILLING
		return "%d/%d" % [ss, rem] if rem > 0 else "%d/–" % ss
	else:
		return "%dd" % pennies

func _on_close() -> void:
	## City Shop follow-up: a visit that came from a CityScreen radial
	## "Enter" action returns to that same city (not Overworld) — see
	## _return_city_id's own declaration comment above.
	if _return_city_id != "":
		GameState.pending_city_id = _return_city_id
		get_tree().change_scene_to_file("res://scenes/CityScreen.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Overworld.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_on_close()
		## Per the request: Q/E cycle which party member is currently
		## being served, same direction/keys convention and same
		## no-op-below-2-members guard as the Prev/Next buttons
		## _cycle_character() already handles.
		elif event.keycode == KEY_Q:
			get_viewport().set_input_as_handled()
			_cycle_character(-1)
		elif event.keycode == KEY_E:
			get_viewport().set_input_as_handled()
			_cycle_character(1)

func _clear(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
