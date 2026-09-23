extends RefCounted
class_name ClassTrappingsTable
## The core rulebook's own "Class Trappings" (Character Creation,
## Trappings step): every character gets these on top of — not instead
## of — their Career's own Tier-1 trappings (CareerLevel.trappings),
## granted purely by Class (CareerDefinition.career_class already
## provides the exact matching key: Academic/Burgher/Courtier/Peasant/
## Ranger/Riverfolk/Rogue/Warrior).
##
## Two entries roll a die for a quantity (Academics' Parchment,
## Rogues' Matches) and Rogues make one further choice ("Hood or
## Mask") — all three resolved by grant_to() below rather than left as
## literal unresolved "1d10"/"or" text sitting in the character's
## inventory.

const FIXED := {
	"Academic": ["Clothing", "Dagger", "Pouch", "Sling Bag containing Writing Kit"],
	"Burgher": ["Cloak", "Clothing", "Dagger", "Hat", "Pouch", "Sling Bag containing Lunch"],
	"Courtier": ["Dagger", "Fine Clothing", "Pouch containing Tweezers, Ear Pick, and a Comb"],
	"Peasant": ["Cloak", "Clothing", "Dagger", "Pouch", "Sling Bag containing Rations (1 day)"],
	"Ranger": ["Cloak", "Clothing", "Dagger", "Pouch", "Backpack containing Tinderbox, Blanket, Rations (1 day)"],
	"Riverfolk": ["Cloak", "Clothing", "Dagger", "Pouch", "Sling Bag containing a Flask of Spirits"],
	"Rogue": ["Clothing", "Dagger", "Pouch", "Sling Bag containing 2 Candles"],
	"Warrior": ["Clothing", "Hand Weapon", "Dagger", "Pouch"],
}

## Every Class that needs a further roll/choice beyond FIXED, purely so
## callers (the Trappings step UI) know to ask before granting.
const ROGUE_HOOD_OR_MASK_OPTIONS := ["Hood", "Mask"]

## Appends this Class's Trappings to `inventory` (a plain Array[String],
## e.g. Character.inventory). `rogue_hood_or_mask` is the player's pick
## for Rogues' one choice — ignored for every other Class; defaults to
## "Hood" if omitted/invalid so this is still safe to call unattended.
static func grant_to(character_class: String, inventory: Array, rogue_hood_or_mask: String = "Hood") -> void:
	for item in FIXED.get(character_class, []):
		inventory.append(item)
	match character_class:
		"Academic":
			inventory.append("%d sheets of Parchment" % Dice.roll_dice_string("1d10"))
		"Rogue":
			inventory.append("%d Matches" % Dice.roll_dice_string("1d10"))
			var pick := rogue_hood_or_mask if ROGUE_HOOD_OR_MASK_OPTIONS.has(rogue_hood_or_mask) else "Hood"
			inventory.append(pick)
