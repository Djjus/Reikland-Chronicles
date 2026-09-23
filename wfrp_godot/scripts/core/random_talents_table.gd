extends RefCounted
class_name RandomTalentsTable
## The core rulebook's own "Random Talents" table (Character Creation,
## Species Skills and Talents): rolled once per "N Random Talents" a
## Species grants (e.g. Humans roll 3, Halflings roll 2). A 1d100 table,
## bands keyed here by each entry's inclusive upper bound — 98-00 wraps
## to 100 the same way every other d100 table in this project treats "00".
## "If you roll a Talent you already have, you may reroll" (the book's own
## note) is the CALLER's responsibility (see
## CharacterCreator.roll_racial_random_talents), not this table.

const ENTRIES := [
	{"max": 3, "name": "Acute Sense"},
	{"max": 6, "name": "Ambidextrous"},
	{"max": 9, "name": "Animal Affinity"},
	{"max": 12, "name": "Artistic"},
	{"max": 15, "name": "Attractive"},
	{"max": 18, "name": "Coolheaded"},
	{"max": 21, "name": "Craftsman"},
	{"max": 24, "name": "Flee!"},
	{"max": 28, "name": "Hardy"},
	{"max": 31, "name": "Lightning Reflexes"},
	{"max": 34, "name": "Linguistics"},
	{"max": 38, "name": "Luck"},
	{"max": 41, "name": "Marksman"},
	{"max": 44, "name": "Mimic"},
	{"max": 47, "name": "Night Vision"},
	{"max": 50, "name": "Nimble Fingered"},
	{"max": 52, "name": "Noble Blood"},
	{"max": 55, "name": "Orientation"},
	{"max": 58, "name": "Perfect Pitch"},
	{"max": 62, "name": "Pure Soul"},
	{"max": 65, "name": "Read/Write"},
	{"max": 68, "name": "Resistance"},
	{"max": 71, "name": "Savvy"},
	{"max": 74, "name": "Sharp"},
	{"max": 78, "name": "Sixth Sense"},
	{"max": 81, "name": "Strong Legs"},
	{"max": 84, "name": "Sturdy"},
	{"max": 87, "name": "Suave"},
	{"max": 91, "name": "Super Numerate"},
	{"max": 94, "name": "Very Resilient"},
	{"max": 97, "name": "Very Strong"},
	{"max": 100, "name": "Warrior Born"},
]

## Three entries ("Acute Sense", "Craftsman", "Resistance") are printed in
## the book as "(any one)" — a further choice the roller makes once they
## land on that result. Resolved against the matching TalentDefinition's
## own situation_options where this project's talent database actually
## has one populated; left unresolved (base name only) where it doesn't,
## rather than inventing an option list the data doesn't back.
const NEEDS_SUB_CHOICE := ["Acute Sense", "Craftsman", "Resistance"]

static func roll_name(forced_roll: int = -1) -> String:
	var roll: int = forced_roll if forced_roll >= 1 else Dice.d100()
	for entry in ENTRIES:
		if roll <= entry["max"]:
			return entry["name"]
	return ENTRIES[-1]["name"]

static func needs_sub_choice(base_name: String) -> bool:
	return NEEDS_SUB_CHOICE.has(base_name)
