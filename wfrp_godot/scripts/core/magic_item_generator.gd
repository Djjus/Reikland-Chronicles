extends RefCounted
class_name MagicItemGenerator
## Magic Weapon / Ammunition / Armour / Shield generator, per the
## request ("add Magic Item Gen rules from WFRP_Archives_of_the_Empire_
## Vol_II_231213.pdf... a Magic Weapons/Armor/Shields/Ammunition
## generator"). Every table below is transcribed directly from that
## sourcebook's "A Touch of Magic: Magical Items and Artifice" chapter
## (p.51-64) — the Magical Weapons/Weapon Qualities/Weapon History
## tables (p.57-60), the Magical Ammunition table (p.61), the Magical
## Armour/Armour Size/Armour Qualities tables (p.62-63, including the
## Gromril/Ithilmar rules), the Magical Shield/Shield Quality tables
## (p.64), the Random Creature table (p.55, used by "Of Bane"), and the
## Quirks and Curses table (p.56-57) — checked against the book rather
## than reconstructed, matching this project's existing convention for
## every other rules system.
##
## Per the request's own follow-up scoping ("standalone tool only for
## now"): this is a real, callable generator — it resolves each rolled
## base item against this project's actual weapon_db/armour_db (never
## the shared originals; every result clones its own copy via
## duplicate(true)) and wires in every ability whose effect maps onto a
## mechanic this project ALREADY implements for real (the Fast,
## Precise, Damaging, Unbreakable, Hack, Impale, Penetrating, and
## Pummel Qualities; the Impenetrable Quality and Weakpoints Flaw; a
## Shield's own rated "Shield N" Quality) — but it is NOT wired into
## loot generation, quest rewards, or the shop; that integration is an
## explicit, separate follow-up.
##
## Deliberately out of scope, per the request's own named categories:
## Scrolls, Wands, Staffs, Rings, Talismans, and Oddities are all real
## rows on the book's own Magical Artefact Generation Table (p.51), but
## weren't asked for — only its Weapon/Ammunition/Armour/Shield branch
## is implemented here.
##
## Several rolled abilities describe mechanics this project has no
## general hook for at all yet — a once-per-day "ignore the first hit
## that would damage this armour," an automatic "bypasses the Ethereal
## Creature Trait's non-magical-attack immunity" (this project doesn't
## track "is this weapon magical" as a combat-relevant flag, nor
## implement Ethereal's immunity in the first place), a suit granting a
## permanent +Toughness, "on a d10 roll of X, ignore the hit entirely,"
## Arrow of Potency's Armour-and-Toughness-ignoring bonus Damage, a
## weapon-granted Talent (Strike Mighty Blow, Fast Shot, ...) while
## wielded, and so on. These are always included in full in the
## result's own `ability_text` for a GM to read and adjudicate, and
## additionally listed in `unimplemented_mechanics` so nothing is
## silently dropped or half-faked into a field that doesn't really
## match — same honesty convention this project already uses elsewhere
## (see MagicResolver's own Miscast table, or Character's Corruption
## Threshold comment).

## --- Shared plumbing --------------------------------------------------

## Looks up the D100 (1-100) or extended-range roll in a `{min,max,...}`
## entry table, returning the first matching entry. First-match-wins is
## deliberate: the book's own Magical Weapon Qualities table (p.58) has
## a genuine printed overlap between "25–28: Alight with Flame" and
## "28–31: Dolorous" (confirmed against the source text, not an OCR
## slip on this project's part) — resolved here by always awarding the
## earlier-listed result on that single ambiguous roll (28), which
## keeps the table gapless and crash-free without silently "fixing" a
## real, if minor, book typo.
static func _lookup(table: Array, roll: int) -> Dictionary:
	for entry in table:
		if roll >= int(entry["min"]) and roll <= int(entry["max"]):
			return entry
	return {}

## Picks one entry from `choices` using Dice (this project's shared,
## centralised RNG — see dice.gd) rather than Godot's global randi(),
## so every roll a caller might want to control/observe in a test goes
## through the same, single source of randomness the rest of the
## project already uses.
static func _pick_one(choices: Array) -> Variant:
	if choices.size() == 1:
		return choices[0]
	return choices[(Dice.d100() - 1) % choices.size()]

## --- Random Creature Table (p.55) --------------------------------------
## Used by the Magical Weapon Qualities table's own "Of Bane" result.
const RANDOM_CREATURE_TABLE := [
	{"min": 1, "max": 19, "name": "Goblins and Snotlings"},
	{"min": 20, "max": 29, "name": "Orcs"},
	{"min": 30, "max": 32, "name": "Daemons of Tzeentch"},
	{"min": 33, "max": 35, "name": "Daemons of Nurgle"},
	{"min": 36, "max": 38, "name": "Daemons of Khorne"},
	{"min": 39, "max": 40, "name": "Daemons of Slaanesh"},
	{"min": 41, "max": 55, "name": "Daemons (All)"},
	{"min": 56, "max": 58, "name": "Beastmen"},
	{"min": 59, "max": 62, "name": "Skeletons and Zombies"},
	{"min": 63, "max": 65, "name": "Ethereal Undead"},
	{"min": 66, "max": 69, "name": "Skaven and their vile kin"},
	{"min": 70, "max": 73, "name": "Vampires"},
	{"min": 74, "max": 75, "name": "Lizardmen"},
	{"min": 76, "max": 78, "name": "Trolls"},
	{"min": 79, "max": 81, "name": "Humans"},
	{"min": 82, "max": 82, "name": "Halflings"},
	{"min": 83, "max": 83, "name": "Ogres"},
	{"min": 84, "max": 84, "name": "Dwarfs"},
	{"min": 85, "max": 85, "name": "Elves"},
	{"min": 86, "max": 86, "name": "Giants"},
	{"min": 87, "max": 88, "name": "Spites, Dryads, Tree Kin, Treemen"},
	{"min": 89, "max": 90, "name": "Beasts"},
	{"min": 91, "max": 91, "name": "Spiders"},
	{"min": 92, "max": 92, "name": "Mutants"},
	{"min": 93, "max": 93, "name": "The Truly Faithful"},
	{"min": 94, "max": 94, "name": "Spellcasters"},
	{"min": 95, "max": 95, "name": "Giant Spiders"},
	{"min": 96, "max": 96, "name": "Manticores, Chimera"},
	{"min": 97, "max": 97, "name": "Pegasi"},
	{"min": 98, "max": 98, "name": "Griffons, Hippogriffs, Demigryphs"},
	{"min": 99, "max": 99, "name": "Dragons"},
	{"min": 100, "max": 100, "name": "Jabberslythes"},
]

static func roll_random_creature() -> String:
	return String(_lookup(RANDOM_CREATURE_TABLE, Dice.d100()).get("name", ""))

## --- Quirks and Curses (p.56-57) ----------------------------------------
## Ranges 101-140 are only ever reached via another table's own "+40 and
## reroll" instruction (e.g. the Weapon History table's Bewitched
## result) — see roll_quirk_or_curse()'s `plus_forty` parameter. A plain
## "found item" roll (this generator's own default use) only ever
## produces 1-100, per the book's own "make a secret roll" instruction
## on p.56 (no reroll-on-no-effect mechanic there — that specific
## reroll instruction belongs to the separate player-crafting Extended
## Test flow on p.54, which this generator doesn't implement at all,
## being out of scope for "found"/randomly-generated items).
const QUIRKS_AND_CURSES_TABLE := [
	{"min": 1, "max": 20, "name": "No Quirk or Curse",
		"text": "The artefact does not carry any sort of Quirk or Curse."},
	{"min": 21, "max": 35, "name": "Blessed Glow",
		"text": "Whenever the artefact is used it gives off an eerie blue-green glow. This item was forged with the help of miraculous rites performed by a priest of one of the Empire's gods (the GM decides which — Shallya, for instance, never assists in the construction of a weapon). The magical effects only work if the wielder first abides by that god's strictures for at least 32 consecutive days."},
	{"min": 36, "max": 40, "name": "Dwarf Runes",
		"text": "The effect is achieved through runes inscribed by a Dwarf Runesmith. There is no negative effect on the item, and it has the Durable and Fine Item Qualities. However, it is likely the Dwarfs who produced this artefact desire its return and regard the bearer as a thief. The artefact gives off a faint, constant humming noise, increasing the Difficulty of any Stealth Tests the bearer makes by one step, and is rather annoying."},
	{"min": 41, "max": 45, "name": "Command Word",
		"text": "The artefact will only work after the wielder speaks a particular word. What this word might be is left up to the GM, and learning it may take the Character some time and effort."},
	{"min": 46, "max": 50, "name": "Tenuously Bound",
		"text": "The Winds of Magic are tenuously bound to this artefact. Every time it is used the bearer must make a Very Easy (+60) Channelling Test. If they fail the Test, the bearer must roll on the Minor Miscast Table as the Winds escape the artefact. Characters without the Channelling Skill automatically fail this Test."},
	{"min": 51, "max": 63, "name": "Temporary Enchantment",
		"text": "The effect was produced through a temporary enchantment on the item, the magic used was unstable, or the item is otherwise close to the end of its useful life. After 1d100 days, any magical abilities the item possesses vanish."},
	{"min": 64, "max": 69, "name": "Draws on the Bearer",
		"text": "The artefact draws on the bearer for some of its strength. Anyone who carries it feels unusually hungry, and must eat twice the normal amount of food or suffer from a permanent Fatigued Condition for as long as they carry the item."},
	{"min": 70, "max": 75, "name": "Sinister Carvings",
		"text": "The effect relies on sinister carvings, crude fetishes, or grotesque scrimshaw. The nightmarish item may frighten superstitious folk and draw the unwelcome suspicion of Witch Hunters. The artefact has the Ugly Flaw."},
	{"min": 76, "max": 78, "name": "Warpstone Dust",
		"text": "A pinch of Warpstone dust was used in the creation of this artefact. It is a minor source of Corruption."},
	{"min": 79, "max": 80, "name": "Sun or Moon Bound",
		"text": "The item relies on power drawn from either sunlight or moonlight. It only works during the day or night, and does not work indoors or underground. (Roll 1d10 to determine the body: 1-6 The Sun, 7-9 Mannslieb, 10 Morrslieb.)"},
	{"min": 81, "max": 84, "name": "Hermit-Made",
		"text": "The artefact was created by a hermit who shunned the contact of others, and a little of their solitary nature has infected the item. Tests involving the item while others are present suffer -1 SL, while Tests made involving it while alone benefit from +1 SL."},
	{"min": 85, "max": 89, "name": "Leeches Life",
		"text": "The item derives its power by leeching the life from its wielder. Every time the item is used the wielder must make a Challenging (+0) Endurance Test. If they fail, they gain a Fatigued Condition."},
	{"min": 90, "max": 93, "name": "Unreliable Craft",
		"text": "Whilst the person who made this item was a mighty worker of magic, they were a poor craftsman. The artefact has the Unreliable Flaw."},
	{"min": 94, "max": 97, "name": "Wild Energies",
		"text": "Wild energies course around the item. Any creature or Character with the Second Sight Talent is able to see the item as if it was a beacon fire, even if it is kept in a scabbard or backpack. The bearer has no hope of hiding the item from those with Second Sight."},
	{"min": 98, "max": 99, "name": "Vampiric",
		"text": "The item is vampiric. Each dawn it must be daubed with a Wound's worth of the wielder's blood or its magical effects cease to function until the item is bathed. If the item is allowed to go inactive in this way, three Wounds' worth of the wielder's blood is required to reactivate it."},
	{"min": 100, "max": 100, "name": "Captured Spite",
		"text": "The source of power for this item is a captured Spite, trapped inside a prominent adornment or pommel. It is magically bound, but once a day the creature gains a Hard (-20) Pick Lock Test (with a Dex of 58) to gain temporary control. It is still physically restrained within the artefact, but there is a perceptible rattle as it strains against its bonds. During the subsequent 24 hours it may attempt to cast three spells from the Lore of Life using WP 47 of the bearer (it chooses whichever most inconveniences or humiliates the bearer, such as healing an opponent in combat). Spites are capricious and cruel; if the creature is released, it may decide to torment its liberators."},
	{"min": 101, "max": 111, "name": "Weakly Bound (Average)",
		"text": "Magical energy is weakly bound to the item. Every time it is used the bearer must make an Average (+20) Channelling Test. If they fail the Test, the bearer must roll on the Minor Miscast Table as wild magic is vented off. Characters without the Channelling Skill automatically fail this Test."},
	{"min": 112, "max": 129, "name": "Swirling Winds Nearby",
		"text": "Magical energy swirls about the item. Anyone casting spells within 10 yards of the bearer is subject to the Swirling Winds effect."},
	{"min": 130, "max": 137, "name": "Poorly Bound (Challenging)",
		"text": "Magical energy is poorly bound to the artefact. Every time it is used the bearer must make a Challenging (+0) Channelling Test. If they fail the Test, the bearer must roll on the Minor Miscast table as wild magic is vented off. Characters without the Channelling Skill automatically fail this Test."},
	{"min": 138, "max": 140, "name": "Warpstone Core",
		"text": "A chunk of Warpstone was used in the creation of this artefact. It is a source of Moderate Corruption."},
]

## `plus_forty`: true reproduces the Weapon History table's own
## "generate an additional Quirk or Curse by rolling on the Quirks and
## Curses Table and adding +40 to the result" instruction — otherwise a
## plain 1-100 roll, per the book's own "found item" instruction (p.56).
static func roll_quirk_or_curse(plus_forty: bool = false) -> Dictionary:
	var roll := Dice.d100() + (40 if plus_forty else 0)
	return _lookup(QUIRKS_AND_CURSES_TABLE, roll)

## --- Cost/time formula (Magical Artefact Generation Table, p.51) ---------
## "(Cost of weapon/armour/shield) x 50 (per ability)" / "(Cost of
## arrows) x 30" (flat — ammunition never has more than one ability).
const COST_MULTIPLIER_PER_ABILITY := 50
const AMMO_COST_MULTIPLIER := 30
const WEAPON_TIME_TO_CREATE := "2 months"
const ARMOUR_TIME_TO_CREATE := "4 months"
const SHIELD_TIME_TO_CREATE := "4 months"
const AMMO_TIME_TO_CREATE := "2 weeks for 6 arrows"

## --- Magical Weapons (p.57-60) -------------------------------------------

## Each `names` array is a set of this project's own real weapon_db
## entries standing in for the book's more generic type name — "Hand
## Weapon" has no single matching item in this project's data (its own
## Sword/Axe/Mace/Club already cover that role between them), and
## "Warhammer"/"Bow"/"Crossbow" each cover more than one real weapon
## here, so one is chosen at random from the set per _pick_one() above
## rather than picking a single fixed representative.
const WEAPON_TYPE_TABLE := [
	{"min": 1, "max": 50, "names": ["Sword", "Axe", "Mace", "Club"], "is_ranged": false},
	{"min": 51, "max": 60, "names": ["Dagger"], "is_ranged": false},
	{"min": 61, "max": 65, "names": ["Rapier"], "is_ranged": false},
	{"min": 66, "max": 68, "names": ["Halberd"], "is_ranged": false},
	{"min": 69, "max": 72, "names": ["Spear"], "is_ranged": false},
	{"min": 73, "max": 75, "names": ["Bastard Sword"], "is_ranged": false},
	{"min": 76, "max": 78, "names": ["Great Axe"], "is_ranged": false},
	{"min": 79, "max": 83, "names": ["Warhammer (1H)", "Warhammer (2H)"], "is_ranged": false},
	{"min": 84, "max": 85, "names": ["Zweihänder"], "is_ranged": false},
	{"min": 86, "max": 90, "names": ["Throwing Axe"], "is_ranged": false},
	{"min": 91, "max": 98, "names": ["Bow", "Longbow", "Shortbow"], "is_ranged": true},
	{"min": 99, "max": 100, "names": ["Crossbow", "Heavy Crossbow"], "is_ranged": true},
]

## Magical Weapon Qualities (p.58-59). `qualities` lists real, already-
## implemented WeaponDefinition.qualities strings this ability genuinely
## grants (appended to the generated weapon's own qualities array, not
## merely described); `gap` is a short note for `unimplemented_mechanics`
## when part (or all) of the ability has no real mechanical hook yet.
## Ranges 25-28/28-31 deliberately overlap on 28 — see _lookup()'s own
## comment; that is the book's own text, not a transcription error here.
const WEAPON_QUALITY_TABLE := [
	{"min": 1, "max": 20, "name": "Touched by the Winds",
		"text": "The weapon has petty enchantments cast upon it. Beyond damaging creatures that are immune to non-magical attacks it has no particular ability. If the weapon is a ranged item, this ability is conferred to its ammunition.",
		"qualities": [], "gap": "bypasses non-magical-attack immunity (e.g. the Ethereal Creature Trait) — not implemented, no such immunity exists in this project yet"},
	{"min": 21, "max": 24, "name": "Wreathed in Shadow",
		"text": "These weapons are often made by Grey Wizard artificers. The blade of a melee weapon seems insubstantial and ghostly, while the same effect lingers on the string of a bow or crossbow, and is conferred to any ammunition the weapon fires. Any target hit by the weapon receives no benefit from non-magical armour.",
		"qualities": [], "gap": "target's non-magical armour is ignored — this project has no 'is this armour magical' flag to check against"},
	{"min": 25, "max": 28, "name": "Alight with Flame",
		"text": "Many of these weapons are produced in the forges of the Bright College. Once drawn the weapon bursts into searing flame, but does not harm the wielder or any possessions they carry. If the wielder hits a flammable target with the weapon, the target suffers one Ablaze Condition.",
		"qualities": [], "gap": "should inflict the real Ablaze Condition (already implemented) on a hit against a flammable target — no per-weapon on-hit-condition hook exists yet to apply it automatically"},
	{"min": 28, "max": 31, "name": "Dolorous",
		"text": "Death magic permeates the weapon, filling foes with fright. The wielder counts as causing Fear (1).",
		"qualities": [], "gap": "should apply the real Fear (1) mechanic (already implemented for monsters) to the wielder — no per-weapon Fear-grant hook exists yet"},
	{"min": 32, "max": 35, "name": "Of Leaping Silver Wroth",
		"text": "Alloys used in constructing this weapon lend it expert balance and surprising lightness. A melee weapon of Leaping Silver has the Fast Quality. A ranged weapon with this enchantment bears the silver alloy in fine filigree about it, granting a wielder +10 Initiative in combat.",
		"qualities_melee": ["Fast"], "qualities_ranged": [], "gap_ranged": "+10 Initiative in combat — no per-weapon Initiative bonus hook exists yet"},
	{"min": 36, "max": 39, "name": "Carved of Rage",
		"text": "Often created by the shamans of the Amber Order, animalistic fury and instinct fill the mind of the wielder whenever this weapon is drawn in anger. Once drawn, the wielder of this weapon becomes subject to Frenzy.",
		"qualities": [], "gap": "should apply the real Frenzy Condition (already implemented) once drawn — no per-weapon on-draw-Condition hook exists yet"},
	{"min": 40, "max": 43, "name": "Envigoured",
		"text": "The life-giving wind of Ghyran courses through the weapon. The wielder ignores Fatigue Conditions whilst fighting with the weapon. The blade also has the Unbreakable Quality.",
		"qualities": ["Unbreakable"], "gap": "wielder ignoring Fatigued Conditions while fighting with this weapon — no per-weapon Condition-suppression hook exists yet"},
	{"min": 44, "max": 47, "name": "Entwined with Fate",
		"text": "Celestial magics have imbued the weapon with subtle prognosticative abilities. At the start of each round of combat, the weapon imbues the wielder with one Advantage.",
		"qualities": [], "gap": "should grant 1 Advantage at the start of each Round (the real Advantage Pool already exists) — no per-weapon start-of-Round hook exists yet"},
	{"min": 48, "max": 51, "name": "Of Rigor Wroth",
		"text": "Light magic makes a paragon of this weapon's wielder. The wielder of such a melee weapon benefits from the following Talents: Strike Mighty Blow, Strike to Injure, and Strike to Stun. The wielder of a ranged weapon gains the benefit of the following Talents: Fast Shot, Sharpshooter, and Sniper.",
		"qualities": [], "gap": "grants the wielder several real Talents while wielded — no 'weapon grants a Talent while equipped' hook exists yet"},
	{"min": 52, "max": 54, "name": "Of Stalwart Sorcery",
		"text": "These weapons strike true as Verena (though the Verenan cult is at pains to point out they don't endorse magical weapons as instruments of justice). The weapon has the Precise Quality.",
		"qualities": ["Precise"]},
	{"min": 55, "max": 57, "name": "Bewildering",
		"text": "Powerful enchantments of bemusement and misdirection are woven into the weapon. Anyone wounded by the weapon gains the Surprised Condition.",
		"qualities": [], "gap": "should apply the real Surprised Condition (already implemented) on a Wound — no per-weapon on-wound-Condition hook exists yet"},
	{"min": 58, "max": 60, "name": "Of Bold Brass",
		"text": "This weapon's bearer is filled with a sense of vim, is immune to the effects of Fear, and enjoys a +2 SL bonus to resist Terror.",
		"qualities": [], "gap": "Fear immunity and a +2 SL Terror-resistance bonus for the bearer — no per-weapon Fear/Terror-interaction hook exists yet"},
	{"min": 61, "max": 63, "name": "Of the Wolf's Wide Jaws",
		"text": "The most favoured Ulrican warriors wield these weapons with wolf's head pommels and other lupine motifs. The weapon has the Damaging Quality.",
		"qualities": ["Damaging"]},
	{"min": 64, "max": 66, "name": "Of Deft and Cunning",
		"text": "Often created with the aid of Myrmidian experts, these deft weapons handle with exquisite precision. The wielder benefits from +20 WS or BS, as appropriate.",
		"qualities": [], "gap": "+20 WS/BS while wielded — no per-weapon characteristic bonus hook exists yet"},
	{"min": 67, "max": 69, "name": "Of Salt and Brine",
		"text": "The priests of Manann lend their knowledge to artificers seeking to create weapons that guard against unexpected raiders. The bearer of this weapon may make a free Action in the first Round of any combat. The weapon also has the Fast Quality.",
		"qualities": ["Fast"], "gap": "a free Action in the first Round of combat — no per-weapon start-of-combat free-Action hook exists yet"},
	{"min": 70, "max": 72, "name": "Of Grisly Wounds",
		"text": "Deathly enchantments ensure that wounds caused by this weapon are severe. The weapon has the Damaging Quality.",
		"qualities": ["Damaging"]},
	{"min": 73, "max": 75, "name": "Of Tooth and Claw",
		"text": "Creatures with the Bestial Creature Trait recognise something of themselves in this weapon. They must pass a Difficult (-10) Willpower Test before attacking the wielder.",
		"qualities": [], "gap": "forces a Willpower Test on a Bestial attacker before they can attack the wielder — no such pre-attack Test hook exists yet"},
	{"min": 76, "max": 78, "name": "Of Deepest Banishing",
		"text": "The energies given off by this weapon are anathema to Daemons and Ethereal Undead. The wielder always counts as having three additional points of Advantage when determining effects of the Unstable Trait.",
		"qualities": [], "gap": "+3 Advantage specifically for Unstable Trait purposes — the Unstable Creature Trait isn't implemented in this project yet"},
	{"min": 79, "max": 81, "name": "Of Undue Substance",
		"text": "A master of Chamon has imbued this weapon with strange properties of density and mass. The weapon has the Pummel and Hack Qualities.",
		"qualities": ["Pummel", "Hack"]},
	{"min": 82, "max": 84, "name": "Of Languishing Death",
		"text": "Morr calls earnestly to those wounded by this weapon. All Wounds the weapon inflicts are Festering Wounds.",
		"qualities": [], "gap": "every Wound inflicted becomes a Festering Wound (the real Festering Wounds rule already exists) — no per-weapon on-Wound hook exists yet"},
	{"min": 85, "max": 87, "name": "Of Keenest Edge",
		"text": "The tip and edges of this weapon are kept magically keen, or any ammunition it fires becomes so. The weapon has the following Qualities: Hack, Impale, and Penetrating.",
		"qualities": ["Hack", "Impale", "Penetrating"]},
	{"min": 88, "max": 90, "name": "Of Bane",
		"text": "The weapon was made with enchantments that increase its deadliness to a given enemy. If it deals damage to a particular type of creature, it inflicts twice the number of Wounds. Roll on the Random Creature Table to determine the affected creature.",
		"qualities": [], "special": "of_bane", "gap": "double Wounds against the rolled creature type — no per-weapon creature-type damage-multiplier hook exists yet"},
	{"min": 91, "max": 92, "name": "Of Ceaseless Cleaving",
		"text": "Powerful enchantments guide the weapon easily through flesh and bone. If a hit from the weapon deals Damage, it inflicts an additional two Wounds.",
		"qualities": [], "gap": "+2 Wounds on any damaging hit — no per-weapon flat bonus-Wounds hook exists yet"},
	{"min": 93, "max": 94, "name": "Of Leaping Gold",
		"text": "This stunning weapon handles like a feather, but lands like a block of lead. The weapon has the following Qualities: Fast, Penetrating, and Precise.",
		"qualities": ["Fast", "Penetrating", "Precise"]},
	{"min": 95, "max": 96, "name": "Of Grievous Injury",
		"text": "The injuries inflicted by this weapon are cruel and severe. Whenever the wielder rolls on the Critical Injuries Chart they can reverse the numbers of the roll and apply whichever is the most damaging result.",
		"qualities": [], "gap": "reverse the Critical Injury roll's digits and take the worse of the two — no such Critical Injury reroll hook exists yet"},
	{"min": 97, "max": 98, "name": "Of Form Mercurial",
		"text": "A master of Chamon has created this weapon, allowing it to morph according to the wielder's movements. When used to thrust, it becomes long and thin. When used to slash or strike, it becomes broad and razor-edged. Each Round the wielder may choose from the following Qualities: Fast, Hack, Impale, Penetrating, and Precise.",
		"qualities": [], "special": "form_mercurial", "gap": "the wielder picks one of Fast/Hack/Impale/Penetrating/Precise fresh each Round — no per-Round Quality-choice hook exists yet, so no single Quality is pre-applied here"},
	{"min": 99, "max": 99, "name": "Hoarfrost Blade",
		"text": "These rare and powerful weapons are sometimes created through painstaking rites undergone by the Ice Witches of Kislev. So much as a nick from one of these blades can prove fatal. If a hit from the weapon deals Damage, it inflicts double the number of Wounds, plus four additional Wounds. There is no way to create ranged weapons that imbue their ammunition with this quality — for a ranged weapon this instead represents 1d10 pieces of ammunition imbued with the above ability.",
		"qualities": [], "special": "hoarfrost", "gap": "double Wounds plus four additional Wounds on any damaging hit — no per-weapon Wounds-multiplier hook exists yet"},
	{"min": 100, "max": 100, "name": "Legendary Weapon",
		"text": "Roll twice more on this table. If you roll this result multiple times, a magical weapon has a maximum of five abilities. Duplicate abilities are not cumulative.",
		"qualities": [], "special": "legendary"},
]

## Magical Weapon History (p.60). `quality` names one of the four
## Trapping Item Qualities already implemented (ItemQualityRules) for
## Battered/Expertly Forged results, applied to the generated weapon's
## own item_qualities/item_flaws array for real. Battle Tested/Bitterly
## Remembered/Tyrant Borne/Sacrilegious/Heirloom/Sought describe
## reputation/NPC-reaction effects this project has no generic "social
## reputation" system to hook into yet, so they stay narrative-only
## (full text always included; not narrated as a mechanical gap, since
## nothing here claims to be a live mechanic already — same as the
## book's own psychological-effects caveat that these only matter when
## an NPC actually recognises the weapon).
const WEAPON_HISTORY_TABLE := [
	{"min": 1, "max": 17, "name": "No Particular Significance",
		"text": "The weapon is of no particular historical significance."},
	{"min": 18, "max": 29, "name": "Battered",
		"text": "The weapon has been worn and damaged after long years of use and abuse. Choose an Item Flaw and apply it to the weapon: Ugly, Shoddy, or Unreliable.",
		"flaw_choices": ["Ugly", "Shoddy", "Unreliable"]},
	{"min": 30, "max": 37, "name": "Expertly Forged",
		"text": "The weapon was made by a renowned magician artificer, such as Volans or the great Hagmar Wyrmschlager. Choose an Item Quality and apply it to the weapon: Fine, Durable, Lightweight, or Practical.",
		"quality_choices": ["Fine", "Durable", "Lightweight", "Practical"]},
	{"min": 38, "max": 44, "name": "Tyrant Borne",
		"text": "This weapon was once wielded by a cruel and petty Old World ruler. Agitators, Verenans, and other champions of the common folk who recognise it are subject to Prejudice towards the bearer."},
	{"min": 45, "max": 51, "name": "Sacrilegious",
		"text": "This weapon became associated with a particular side during the Age of Wars and is seen as a sign of division between Sigmarites and Ulricans (choose which). Those people are subject to Animosity towards the bearer."},
	{"min": 52, "max": 56, "name": "Bewitched",
		"text": "Once an unholy necromancer, witch, or sorcerer of Chaos bore this weapon. Even if the weapon itself is not actually a corrupt artefact, people may perceive it as such. (Roll 1d10: 1 - the weapon counts as a minor source of Corruption; 2-5 - generate an additional Quirk or Curse, rolling on the Quirks and Curses Table and adding +40 to the result; 6-10 - people who recognise the weapon are subject to Animosity towards the bearer.)",
		"special": "bewitched"},
	{"min": 57, "max": 73, "name": "Battle Tested",
		"text": "This weapon was once wielded with noted effect at a famous battle against one of the Empire's many enemies. Folk who recognise and respect its provenance treat the bearer as having a Status tier one higher than they actually do (to a maximum of Gold) for Intimidate, Leadership, and Charm Tests."},
	{"min": 74, "max": 80, "name": "Bitterly Remembered",
		"text": "This weapon once slew a mighty champion of a hostile Species given to holding lasting grudges. Members of that Species who recognise the weapon become subject to Hatred toward the bearer.",
		"special": "bitterly_remembered"},
	{"min": 81, "max": 89, "name": "Heirloom",
		"text": "This weapon once belonged to a rich and powerful family. They would most certainly pay handsomely for its return, but they may well resent those who refused to sell it back to them."},
	{"min": 90, "max": 96, "name": "Sought",
		"text": "The former owner of this weapon is part of an adventuring band of mercenaries. Having recently finished their last commission, they are now on the trail of the lost weapon."},
	{"min": 97, "max": 100, "name": "Storied",
		"text": "Roll twice more on this table.", "special": "storied"},
]

const HATED_SPECIES_TABLE := [
	{"min": 1, "max": 1, "name": "Fimir"}, {"min": 2, "max": 2, "name": "Dark Elves"},
	{"min": 3, "max": 3, "name": "Dragons"}, {"min": 4, "max": 4, "name": "Daemons"},
	{"min": 5, "max": 6, "name": "The mortal followers of a particular Chaos God"},
	{"min": 7, "max": 8, "name": "Vampires and Necromancers"}, {"min": 9, "max": 10, "name": "Dwarfs"},
]

## Generates one Magical Weapon: rolls its base type (p.57), its
## ability/abilities (p.58-59, handling Legendary's own reroll-twice-
## more-max-five-no-duplicates rule and Hoarfrost Blade's ranged-weapon
## special case), then optionally its History (p.60, `include_history`)
## and a secret Quirk/Curse roll (p.56, `include_quirk_curse`) — both
## true by default, matching "found a magical weapon" play, but left
## togglable since History/Quirks explicitly don't apply to every
## artefact category this class might grow into later.
static func generate_weapon(include_history: bool = true, include_quirk_curse: bool = true) -> Dictionary:
	var type_entry := _lookup(WEAPON_TYPE_TABLE, Dice.d100())
	var base_name: String = String(_pick_one(type_entry.get("names", ["Sword"])))
	var is_ranged: bool = bool(type_entry.get("is_ranged", false))
	var base_weapon: WeaponDefinition = GameData.weapon_db.find_by_name(base_name)

	var abilities: Array[Dictionary] = []
	var notes: Array[String] = []
	_roll_weapon_abilities(is_ranged, abilities, notes, 5)

	var granted_qualities: Array[String] = []
	var unimplemented: Array[String] = []
	for ab in abilities:
		var qs: Array = ab.get("qualities", ab.get("qualities_ranged" if is_ranged else "qualities_melee", []))
		for q in qs:
			if not granted_qualities.has(q):
				granted_qualities.append(q)
		var gap: String = String(ab.get("gap_ranged" if is_ranged else "gap", ab.get("gap", "")))
		if gap != "":
			unimplemented.append("%s: %s" % [ab["name"], gap])

	var weapon_copy: WeaponDefinition = base_weapon.duplicate(true) if base_weapon != null else null
	if weapon_copy != null:
		for q in granted_qualities:
			if not weapon_copy.qualities.has(q):
				weapon_copy.qualities.append(q)
		weapon_copy.weapon_name = "%s \"%s\"" % [base_weapon.weapon_name, abilities[0]["name"]] if abilities.size() > 0 else base_weapon.weapon_name
		weapon_copy.summary = "%s Magical ability — %s: %s" % [weapon_copy.summary, abilities[0].get("name", ""), abilities[0].get("text", "")] if abilities.size() > 0 else weapon_copy.summary

	var history: Dictionary = {}
	if include_history:
		history = _roll_weapon_history(0)

	var quirk: Dictionary = {}
	if include_quirk_curse:
		quirk = roll_quirk_or_curse()

	var base_price: int = base_weapon.price_pennies if base_weapon != null else 0
	var estimated_cost: int = base_price * COST_MULTIPLIER_PER_ABILITY * int(max(1, abilities.size()))

	return {
		"category": "Weapon",
		"base_name": base_name,
		"is_ranged": is_ranged,
		"definition": weapon_copy,
		"abilities": abilities,
		"granted_qualities": granted_qualities,
		"unimplemented_mechanics": unimplemented,
		"history": history,
		"quirk_or_curse": quirk,
		"estimated_cost_pennies": estimated_cost,
		"time_to_create": WEAPON_TIME_TO_CREATE,
		"notes": notes,
	}

## Rolls the weapon's ability (or abilities, for a Legendary/Hoarfrost
## chain), appending each resolved entry to `abilities` and any flavour/
## bookkeeping notes to `notes`. `budget` guards against a pathological
## chain (Legendary rolling Legendary rolling Legendary...) — the book
## itself caps a weapon at five abilities total, enforced here by simply
## stopping once that many have been collected.
static func _roll_weapon_abilities(is_ranged: bool, abilities: Array[Dictionary], notes: Array[String], budget: int) -> void:
	if budget <= 0 or abilities.size() >= 5:
		return
	var entry := _lookup(WEAPON_QUALITY_TABLE, Dice.d100())
	var special: String = String(entry.get("special", ""))
	if special == "legendary":
		notes.append("Legendary Weapon rolled — rolling twice more (max five abilities total, duplicates not cumulative).")
		_roll_weapon_abilities(is_ranged, abilities, notes, budget - 1)
		_roll_weapon_abilities(is_ranged, abilities, notes, budget - 1)
		return
	if special == "hoarfrost" and is_ranged:
		notes.append("Hoarfrost Blade rolled for a ranged weapon — per the book, this represents 1d10 pieces of ammunition imbued with the ability instead of the weapon itself.")
		entry = entry.duplicate(true)
		entry["ammo_count"] = Dice.roll_dice_string("1d10")
	if special == "of_bane":
		entry = entry.duplicate(true)
		var creature := roll_random_creature()
		entry["creature"] = creature
		entry["text"] = "%s (Random Creature Table result: %s.)" % [entry["text"], creature]
	var already_have := false
	for existing in abilities:
		if existing["name"] == entry.get("name", ""):
			already_have = true
			break
	if already_have:
		notes.append("Duplicate ability rolled (%s) — not cumulative, no second copy added." % entry.get("name", ""))
		return
	abilities.append(entry)

static func _roll_weapon_history(depth: int) -> Dictionary:
	if depth > 4:
		return {}
	var entry := _lookup(WEAPON_HISTORY_TABLE, Dice.d100())
	var special: String = String(entry.get("special", ""))
	entry = entry.duplicate(true)
	if special == "storied":
		entry["rerolls"] = [_roll_weapon_history(depth + 1), _roll_weapon_history(depth + 1)]
	elif special == "bewitched":
		var sub := Dice.d10()
		if sub == 1:
			entry["sub_result"] = "The weapon counts as a minor source of Corruption."
		elif sub <= 5:
			entry["sub_result"] = "Additional Quirk/Curse: %s" % roll_quirk_or_curse(true).get("text", "")
		else:
			entry["sub_result"] = "People who recognise the weapon are subject to Animosity towards the bearer."
	elif special == "bitterly_remembered":
		entry["hated_species"] = String(_lookup(HATED_SPECIES_TABLE, Dice.d10()).get("name", ""))
	elif entry.has("flaw_choices"):
		entry["chosen"] = String(_pick_one(entry["flaw_choices"]))
	elif entry.has("quality_choices"):
		entry["chosen"] = String(_pick_one(entry["quality_choices"]))
	return entry

## --- Magical Ammunition (p.61) --------------------------------------------

const AMMO_TABLE := [
	{"min": 1, "max": 54, "name": "Magical Arrow",
		"text": "The arrow is capable of damaging creatures that are immune to non-magical attacks and inflicts +1 Damage, but has no particular ability.",
		"ammo_damage_bonus": 1, "gap": "bypasses non-magical-attack immunity (e.g. the Ethereal Creature Trait) — not implemented, no such immunity exists in this project yet"},
	{"min": 55, "max": 74, "name": "Arrow of Potency",
		"text": "If a hit from an Arrow of Potency deals Damage, it inflicts an additional 1d10 Damage which ignores Armour and Toughness.",
		"ammo_damage_bonus": 0, "gap": "+1d10 Damage ignoring Armour and Toughness on a hit — the existing ammo_damage_bonus field adds ordinary (soakable) Damage, so this bonus doesn't fit it; would need a dedicated armour/Toughness-bypassing on-hit hook"},
	{"min": 75, "max": 91, "name": "Arrow of True Flight",
		"text": "These arrows grant +30 Ballistic Skill when fired.",
		"ammo_damage_bonus": 0, "gap": "+30 BS when fired — no per-ammunition to-hit bonus hook exists yet (ammo_added_qualities only unions Qualities, not a flat characteristic/Test bonus)"},
	{"min": 92, "max": 100, "name": "Hail of Doom Arrow",
		"text": "After firing a Hail of Doom Arrow, it splits into 1d10 arrows in flight. Roll to hit and damage with each arrow. These arrows can all hit the same target, or may hit secondary targets provided they are within 5 feet of the primary target and that the shooter has a clear line of sight to them.",
		"ammo_damage_bonus": 0, "gap": "splits into 1d10 separate to-hit/damage rolls, optionally against secondary targets — no such multi-projectile-on-fire mechanic exists yet"},
]

static func generate_ammunition(include_quirk_curse: bool = true) -> Dictionary:
	var entry := _lookup(AMMO_TABLE, Dice.d100())
	var base_name: String = "Bolt" if Dice.d10() <= 3 else "Arrow"   ## arrows are the more common base per the chapter's own "Magical Arrows and Bolts" framing; bolts are the minority case
	var base_item: ItemDefinition = GameData.item_db.find_by_name(base_name)
	var item_copy: ItemDefinition = base_item.duplicate(true) if base_item != null else null
	if item_copy != null:
		item_copy.item_name = "%s \"%s\"" % [base_item.item_name, entry.get("name", "")]
		item_copy.ammo_damage_bonus += int(entry.get("ammo_damage_bonus", 0))
		item_copy.summary = "%s Magical ability — %s: %s" % [item_copy.summary, entry.get("name", ""), entry.get("text", "")]

	var quirk: Dictionary = {}
	if include_quirk_curse:
		quirk = roll_quirk_or_curse()

	var base_price: int = base_item.price_pennies if base_item != null else 0
	var estimated_cost := base_price * AMMO_COST_MULTIPLIER

	return {
		"category": "Ammunition",
		"base_name": base_name,
		"definition": item_copy,
		"abilities": [entry],
		"unimplemented_mechanics": ([("%s: %s" % [entry["name"], entry["gap"]])] if entry.get("gap", "") != "" else []),
		"quirk_or_curse": quirk,
		"estimated_cost_pennies": estimated_cost,
		"time_to_create": AMMO_TIME_TO_CREATE,
		"notes": [],
	}

## --- Magical Armour (p.62-63) ----------------------------------------------

## Each entry's `armour_names` lists the real armour_db piece(s) this
## project has that best match the book's own piece name — some book
## rows (a full mail hauberk, a full plate suit) describe a SET of
## pieces this project sells/tracks individually, represented here as
## a multi-entry array sharing one magical ability, per the book's own
## "certain effects require a full suit... others can be applied to a
## single piece" framing.
const ARMOUR_PIECE_TABLE := [
	{"min": 1, "max": 3, "armour_names": ["Mail Chausses"], "is_leather": false},
	{"min": 4, "max": 10, "armour_names": ["Mail Coat"], "is_leather": false},
	{"min": 11, "max": 15, "armour_names": ["Mail Coif"], "is_leather": false},
	{"min": 16, "max": 20, "armour_names": ["Mail Shirt"], "is_leather": false},
	{"min": 21, "max": 25, "armour_names": ["Mail Coat", "Mail Chausses"], "is_leather": false},
	{"min": 26, "max": 35, "armour_names": ["Mail Coat", "Mail Chausses", "Mail Coif"], "is_leather": false},
	{"min": 36, "max": 38, "armour_names": ["Leather Jack"], "is_leather": true},
	{"min": 39, "max": 41, "armour_names": ["Leather Jerkin"], "is_leather": true},
	{"min": 42, "max": 45, "armour_names": ["Leather Leggings"], "is_leather": true},
	{"min": 46, "max": 48, "armour_names": ["Leather Skullcap"], "is_leather": true},
	{"min": 49, "max": 51, "armour_names": ["Boiled Leather Breastplate"], "is_leather": true},
	{"min": 52, "max": 54, "armour_names": ["Leather Jack", "Leather Leggings", "Leather Skullcap", "Boiled Leather Breastplate"], "is_leather": true},
	{"min": 55, "max": 70, "armour_names": ["Plate Breastplate"], "is_leather": false},
	{"min": 71, "max": 75, "armour_names": ["Open Helm"], "is_leather": false},
	{"min": 76, "max": 80, "armour_names": ["Bracers"], "is_leather": false},
	{"min": 81, "max": 85, "armour_names": ["Plate Leggings"], "is_leather": false},
	{"min": 86, "max": 90, "armour_names": ["Helm"], "is_leather": false},
	{"min": 91, "max": 100, "armour_names": ["Plate Breastplate", "Plate Leggings", "Bracers", "Helm"], "is_leather": false},
]

const ARMOUR_SIZE_TABLE := [
	{"min": 1, "max": 1, "species": "Human", "height": "Exceedingly Short"},
	{"min": 2, "max": 2, "species": "Human", "height": "Short"},
	{"min": 3, "max": 3, "species": "Human", "height": "Short"},
	{"min": 4, "max": 4, "species": "Human", "height": "Average"},
	{"min": 5, "max": 5, "species": "Human", "height": "Average"},
	{"min": 6, "max": 6, "species": "Elf", "height": "Average"},
	{"min": 7, "max": 7, "species": "Elf", "height": "Average"},
	{"min": 8, "max": 8, "species": "Dwarf", "height": "Tall"},
	{"min": 9, "max": 9, "species": "Dwarf", "height": "Tall"},
	{"min": 10, "max": 10, "species": "Halfling", "height": "Exceedingly Tall"},
]

## Magical Armour Qualities (p.63). `full_suit_required` mirrors the
## book's own note (mechanically unenforced here — this project already
## tracks armour per-piece, and per the book "a piece's magical effect
## only applies if it is worn on the location struck" for the rest).
const ARMOUR_QUALITY_TABLE := [
	{"min": 1, "max": 32, "name": "Magical Armour",
		"text": "The armour is enchanted, but has no unusual ability."},
	{"min": 33, "max": 38, "name": "Gromril Armour",
		"text": "The armour is made of Gromril, and enjoys all the benefits described above (3 AP instead of 2, and immunity to Critical Wounds unless the Character has already been reduced to 0 Wounds). It bears Runes identifying the Dwarf Hold to which the suit belongs by right.",
		"special": "gromril", "dwarf_or_gift_only": true},
	{"min": 39, "max": 42, "name": "Ithilmar Armour",
		"text": "The armour is made of Ithilmar, and enjoys all the benefits described above (Encumbrance of any piece reduced by 2, to a minimum of 0). Eltharin inscription identifies its original owner in a series of rhyming couplets.",
		"special": "ithilmar", "elf_or_gift_only": true},
	{"min": 43, "max": 44, "name": "Gifted Armour",
		"text": "The armour is one of the very rare suits of Gromril or Ithilmar armour that was made as a gift — sized for whoever it was intended (typically a Human, though there are records of Halflings and even one Ogre). It bears runes in Khazalid stating the Gromril was a gift and the terms of its eventual return.",
		"special": "gifted"},
	{"min": 45, "max": 51, "name": "Alleviating Armour",
		"text": "Suits such as this are often made in consultation with Jade Wizards or Shallyan priests. This armour is suffused with healing energies. Whenever the wearer suffers a Critical Wound, the attacker must roll twice on the appropriate Critical Wounds table and apply the lower result.",
		"gap": "roll twice on the Critical Wounds table and take the lower result — no such reroll-and-take-lower hook exists yet"},
	{"min": 52, "max": 58, "name": "Seamless Armour",
		"text": "Such is the skill of this armour's forging that even slender blades cannot find a weakpoint. If the armour is mail, it gains the Impenetrable Quality. If it is plate, it loses the Weakpoints Flaw. Full suit required.",
		"special": "seamless", "full_suit_required": true},
	{"min": 59, "max": 65, "name": "Dragon Scale Armour",
		"text": "This armour was made in part from the scales of dragons, and it is remarkable in its ability to withstand heat. If an attack that deals Damage through flames or heat hits an area protected by this armour, reduce the Damage of that attack by 2. If an attack that would inflict the Ablaze Condition hits an area protected by this armour, the wearer ignores the Condition.",
		"gap": "reduces fire/heat Damage by 2 and ignores Ablaze on a protected hit location — no such source-typed Damage-reduction hook exists yet"},
	{"min": 66, "max": 76, "name": "Armour of Glittering Silver",
		"text": "Such is the bright lustre of this armour that it can dazzle enemies. If fighting in sunlight (or near another source of strong light), opponents in melee with the wearer must pass an Average (+20) Agility Test at the start of each Round or suffer one Blinded Condition. Full suit required.",
		"full_suit_required": true, "gap": "forces an Agility Test on nearby melee opponents each Round or Blinded — no such aura-effect hook exists yet"},
	{"min": 77, "max": 88, "name": "Trickster's Armour",
		"text": "It is said that the artificers of this armour consulted with followers of Ranald to imbue the armour with protective wards. If an attack hits an area protected by this armour, roll 1d10. On a roll of a 10, the wearer ignores the hit.",
		"gap": "10% chance to ignore any hit to a protected location — no such per-hit reroll hook exists yet"},
	{"min": 89, "max": 96, "name": "Armour of Resilience",
		"text": "Powerful enchantments known to practitioners of Chamon ensure that the living flesh of the wearer is as strong as steel. The wearer benefits from +5 Toughness. Full suit required.",
		"full_suit_required": true, "gap": "a permanent +5 Toughness while worn — no per-armour-piece characteristic bonus hook exists yet"},
	{"min": 97, "max": 99, "name": "Armour of Fortune",
		"text": "The Armour of Fortune does not so much protect the wearer directly but misdirects blows that would otherwise land. If an attack hits an area protected by this armour, roll 1d10. On a roll of a 9 or 10, the wearer ignores the hit.",
		"gap": "20% chance to ignore any hit to a protected location — no such per-hit reroll hook exists yet"},
	{"min": 100, "max": 100, "name": "Legendary Armour",
		"text": "Roll twice more on this table. If you roll this result multiple times, a piece of magical armour has a maximum of five abilities and duplicate abilities are not cumulative. A suit of armour may never be made of both Gromril and Ithilmar.",
		"special": "legendary"},
]

## Generates one Magical Armour piece (or matched set — see
## ARMOUR_PIECE_TABLE's own comment). Leather results can never roll
## Gromril/Ithilmar (p.62: "Leather armour cannot be either Gromril or
## Ithilmar. Reroll these results if rolling for a piece of leather
## armor.") — enforced by rerolling the ability table exactly as
## instructed, rather than silently reassigning a different ability.
static func generate_armour(include_quirk_curse: bool = true) -> Dictionary:
	var piece_entry := _lookup(ARMOUR_PIECE_TABLE, Dice.d100())
	var armour_names: Array = piece_entry.get("armour_names", [])
	var is_leather: bool = bool(piece_entry.get("is_leather", false))
	var size_entry := _lookup(ARMOUR_SIZE_TABLE, Dice.d10())

	var abilities: Array[Dictionary] = []
	var notes: Array[String] = []
	_roll_armour_abilities(is_leather, abilities, notes, 5)

	var granted_qualities: Array[String] = []
	var lost_flaws: Array[String] = []
	var unimplemented: Array[String] = []
	var is_mail := false
	for n in armour_names:
		if String(n).begins_with("Mail"):
			is_mail = true
	var is_plate := false
	for n in armour_names:
		var nm := String(n)
		if nm.begins_with("Plate") or nm == "Helm" or nm == "Open Helm" or nm == "Bracers":
			is_plate = true
	for ab in abilities:
		var special: String = String(ab.get("special", ""))
		if special == "seamless":
			if is_mail:
				granted_qualities.append("Impenetrable")
			elif is_plate:
				lost_flaws.append("Weakpoints")
		var gap: String = String(ab.get("gap", ""))
		if gap != "":
			unimplemented.append("%s: %s" % [ab["name"], gap])

	var definitions: Array[ArmourDefinition] = []
	for n in armour_names:
		var base_armour: ArmourDefinition = GameData.armour_db.find_by_name(String(n))
		if base_armour == null:
			continue
		var copy: ArmourDefinition = base_armour.duplicate(true)
		if abilities.size() > 0:
			copy.armour_name = "%s \"%s\"" % [base_armour.armour_name, abilities[0]["name"]]
			copy.summary = "%s Magical ability — %s: %s" % [copy.summary, abilities[0].get("name", ""), abilities[0].get("text", "")]
		if String(_ability_special(abilities, "gromril")) != "":
			copy.armour_points += 1
		for q in granted_qualities:
			if not copy.qualities.has(q):
				copy.qualities.append(q)
		for f in lost_flaws:
			copy.qualities.erase(f)
		definitions.append(copy)

	var quirk: Dictionary = {}
	if include_quirk_curse:
		quirk = roll_quirk_or_curse()

	var base_price := 0
	for n in armour_names:
		var base_armour2: ArmourDefinition = GameData.armour_db.find_by_name(String(n))
		if base_armour2 != null:
			base_price += base_armour2.price_pennies
	var estimated_cost: int = base_price * COST_MULTIPLIER_PER_ABILITY * int(max(1, abilities.size()))

	return {
		"category": "Armour",
		"base_names": armour_names,
		"is_leather": is_leather,
		"size": {"species": size_entry.get("species", ""), "height": size_entry.get("height", "")},
		"definitions": definitions,
		"abilities": abilities,
		"granted_qualities": granted_qualities,
		"lost_flaws": lost_flaws,
		"unimplemented_mechanics": unimplemented,
		"quirk_or_curse": quirk,
		"estimated_cost_pennies": estimated_cost,
		"time_to_create": ARMOUR_TIME_TO_CREATE,
		"notes": notes,
	}

static func _ability_special(abilities: Array[Dictionary], key: String) -> String:
	for ab in abilities:
		if String(ab.get("special", "")) == key:
			return key
	return ""

static func _roll_armour_abilities(is_leather: bool, abilities: Array[Dictionary], notes: Array[String], budget: int) -> void:
	if budget <= 0 or abilities.size() >= 5:
		return
	var entry := _lookup(ARMOUR_QUALITY_TABLE, Dice.d100())
	var special: String = String(entry.get("special", ""))
	if is_leather and (special == "gromril" or special == "ithilmar"):
		notes.append("%s rolled for a piece of leather armour — leather can never be Gromril or Ithilmar, rerolling per the book." % entry.get("name", ""))
		_roll_armour_abilities(is_leather, abilities, notes, budget - 1)
		return
	if special == "legendary":
		notes.append("Legendary Armour rolled — rolling twice more (max five abilities total, duplicates not cumulative; never both Gromril and Ithilmar on the same suit).")
		var before_size := abilities.size()
		_roll_armour_abilities(is_leather, abilities, notes, budget - 1)
		## "A suit of armour may never be made of both Gromril and
		## Ithilmar" — if the first extra roll landed one of them,
		## forbid the other on the second extra roll by treating this
		## suit as if it were leather for that one purpose (reusing the
		## exact same reroll branch above, since the rule is identical:
		## "can't have this specific pairing").
		var got_gromril := _ability_special(abilities, "gromril") != ""
		var got_ithilmar := _ability_special(abilities, "ithilmar") != ""
		if got_gromril or got_ithilmar:
			_roll_armour_abilities_excluding(abilities, notes, budget - 1, "ithilmar" if got_gromril else "gromril")
		else:
			_roll_armour_abilities(is_leather, abilities, notes, budget - 1)
		return
	var already_have := false
	for existing in abilities:
		if existing["name"] == entry.get("name", ""):
			already_have = true
			break
	if already_have:
		notes.append("Duplicate ability rolled (%s) — not cumulative, no second copy added." % entry.get("name", ""))
		return
	abilities.append(entry)

## Same as _roll_armour_abilities, but additionally rerolls a specific
## `exclude_special` result (used only to enforce "never both Gromril
## and Ithilmar on the same suit" after a Legendary Armour roll already
## landed one of the two).
static func _roll_armour_abilities_excluding(abilities: Array[Dictionary], notes: Array[String], budget: int, exclude_special: String) -> void:
	if budget <= 0 or abilities.size() >= 5:
		return
	var entry := _lookup(ARMOUR_QUALITY_TABLE, Dice.d100())
	var special: String = String(entry.get("special", ""))
	if special == exclude_special:
		notes.append("%s rerolled — a suit may never be made of both Gromril and Ithilmar." % entry.get("name", ""))
		_roll_armour_abilities_excluding(abilities, notes, budget - 1, exclude_special)
		return
	if special == "legendary":
		_roll_armour_abilities_excluding(abilities, notes, budget - 1, exclude_special)
		_roll_armour_abilities_excluding(abilities, notes, budget - 1, exclude_special)
		return
	var already_have := false
	for existing in abilities:
		if existing["name"] == entry.get("name", ""):
			already_have = true
			break
	if not already_have:
		abilities.append(entry)

## --- Magical Shields (p.64) ------------------------------------------------
## Shields are WeaponDefinition entries in this project (off-hand items
## carrying the rated "Shield N" Quality — see weapon_definition.gd's
## own comment) — the book's three shield sizes already exist here
## under these exact names, so the Shield Quality table's own
## "Gromril Shield: +1 to the Shield Quality" (and Shield of Ptolos'
## missile-only +2) are wired in as real "Shield N"/"Shield N vs
## missile" adjustments below.
const SHIELD_PIECE_TABLE := [
	{"min": 1, "max": 64, "name": "Shield"},
	{"min": 65, "max": 89, "name": "Shield (Large)"},
	{"min": 90, "max": 100, "name": "Shield (Buckler)"},
]

const SHIELD_QUALITY_TABLE := [
	{"min": 1, "max": 45, "name": "Magical Shield",
		"text": "The shield is magical, but has no further ability."},
	{"min": 46, "max": 56, "name": "Ithilmar Shield",
		"text": "These shields are very light. Reduce Encumbrance by 1 to a minimum of 0.",
		"special": "ithilmar_shield"},
	{"min": 57, "max": 68, "name": "Gromril Shield",
		"text": "Gromril shields provide +1 to the Shield Quality. So, a large Gromril shield counts as having the Shield 4 Quality.",
		"special": "gromril_shield"},
	{"min": 69, "max": 75, "name": "Shield of Ptolos",
		"text": "These shields are based on a design discovered in tombs to the far south of the Old World. Enchantments on the shield misdirect projectiles. Shields of Ptolos provide +2 to the Shield Quality when defending against a missile weapon. So, a large Shield of Ptolos has the Shield 3 Quality against melee attacks but Shield 5 against missile attacks.",
		"special": "ptolos", "gap": "the +2 only applies specifically when defending against a missile weapon — this project's Shield Quality is a single flat rating with no melee/missile split, so the bonus is applied to the shield's normal Shield rating as a conservative stand-in (see notes)"},
	{"min": 76, "max": 88, "name": "Spell Shield",
		"text": "These shields are enchanted to deflect magic missiles. If such a spell targets the bearer, roll a d100 — if the result is 30 or below, the spell fails. An attempt made by a spellcaster to dispel a magic missile while bearing this shield gains +3 SL.",
		"gap": "a 30% chance to automatically fail an incoming magic missile spell, and +3 SL to dispel one — no such hooks exist yet"},
	{"min": 89, "max": 100, "name": "Charmed Shield",
		"text": "Enchantments imbue this shield with an enhanced ability to deflect incoming attacks. The Defensive Quality of a Charmed Shield is enhanced so that the bearer benefits from +3 SL to Melee Tests they make when opposing incoming attacks.",
		"gap": "+3 SL specifically to opposed Melee Tests made while Defensive — no such Quality-specific SL bonus hook exists yet"},
]

static func generate_shield(include_quirk_curse: bool = true) -> Dictionary:
	var piece_entry := _lookup(SHIELD_PIECE_TABLE, Dice.d100())
	var piece_name: String = String(piece_entry.get("name", "Shield"))
	var base_shield: WeaponDefinition = GameData.weapon_db.find_by_name(piece_name)

	var ability := _lookup(SHIELD_QUALITY_TABLE, Dice.d100())
	var notes: Array[String] = []
	var unimplemented: Array[String] = []
	var gap: String = String(ability.get("gap", ""))
	if gap != "":
		unimplemented.append("%s: %s" % [ability.get("name", ""), gap])

	var shield_copy: WeaponDefinition = base_shield.duplicate(true) if base_shield != null else null
	if shield_copy != null:
		shield_copy.weapon_name = "%s \"%s\"" % [base_shield.weapon_name, ability.get("name", "")]
		shield_copy.summary = "%s Magical ability — %s: %s" % [shield_copy.summary, ability.get("name", ""), ability.get("text", "")]
		var special: String = String(ability.get("special", ""))
		if special == "ithilmar_shield":
			shield_copy.encumbrance = max(0, shield_copy.encumbrance - 1)
		elif special == "gromril_shield" or special == "ptolos":
			## Bump the shield's own rated "Shield N" Quality by +1
			## (Gromril) — Shield of Ptolos' book text is +2 but only
			## against missile attacks specifically, which this
			## project's flat Shield rating can't represent; applying
			## +1 here is a deliberately conservative stand-in (noted
			## above and in `notes`) rather than over-granting the full
			## missile-only +2 as an always-on bonus.
			for i in shield_copy.qualities.size():
				if String(shield_copy.qualities[i]).begins_with("Shield "):
					var rating := int(String(shield_copy.qualities[i]).trim_prefix("Shield "))
					shield_copy.qualities[i] = "Shield %d" % (rating + 1)
					break
			if special == "ptolos":
				notes.append("Shield of Ptolos: RAW is +2 Shield Quality specifically against missile attacks (melee unaffected) — applied here as a flat +1 to the shield's own Shield rating instead, since this project's Shield Quality doesn't distinguish melee from missile defence.")

	var quirk: Dictionary = {}
	if include_quirk_curse:
		quirk = roll_quirk_or_curse()

	var base_price: int = base_shield.price_pennies if base_shield != null else 0
	var estimated_cost := base_price * COST_MULTIPLIER_PER_ABILITY

	return {
		"category": "Shield",
		"base_name": piece_name,
		"definition": shield_copy,
		"abilities": [ability],
		"unimplemented_mechanics": unimplemented,
		"quirk_or_curse": quirk,
		"estimated_cost_pennies": estimated_cost,
		"time_to_create": SHIELD_TIME_TO_CREATE,
		"notes": notes,
	}

## --- Display formatting -----------------------------------------------

## Formats any of the four generate_*() results into a readable,
## multi-section report — used by the debug generator screen, and handy
## for a GM reading the roll straight from the log/console too.
static func format_result(result: Dictionary) -> String:
	var lines: Array[String] = []
	var category: String = String(result.get("category", ""))
	lines.append("=== Magical %s ===" % category)
	if result.has("base_names"):
		lines.append("Base piece(s): %s" % ", ".join(result["base_names"]))
		var size: Dictionary = result.get("size", {})
		lines.append("Sized for: %s (%s)" % [size.get("species", "?"), size.get("height", "?")])
	else:
		lines.append("Base item: %s" % String(result.get("base_name", "")))
	for ab in result.get("abilities", []):
		lines.append("\nAbility — %s:" % ab.get("name", ""))
		lines.append(String(ab.get("text", "")))
		if ab.has("creature"):
			lines.append("  (Bane creature: %s)" % ab["creature"])
		if ab.has("ammo_count"):
			lines.append("  (Represents %d pieces of magical ammunition instead of the weapon itself.)" % ab["ammo_count"])
	if result.get("granted_qualities", []).size() > 0:
		lines.append("\nQualities granted: %s" % ", ".join(result["granted_qualities"]))
	if result.get("lost_flaws", []).size() > 0:
		lines.append("Flaws removed: %s" % ", ".join(result["lost_flaws"]))
	var history: Dictionary = result.get("history", {})
	if not history.is_empty():
		lines.append("\nHistory — %s: %s" % [history.get("name", ""), history.get("text", "")])
		if history.has("chosen"):
			lines.append("  Chosen: %s" % history["chosen"])
		if history.has("sub_result"):
			lines.append("  %s" % history["sub_result"])
		if history.has("hated_species"):
			lines.append("  Hated by: %s" % history["hated_species"])
	var quirk: Dictionary = result.get("quirk_or_curse", {})
	if not quirk.is_empty():
		lines.append("\nQuirk/Curse — %s: %s" % [quirk.get("name", ""), quirk.get("text", "")])
	if result.get("notes", []).size() > 0:
		lines.append("\nNotes:")
		for n in result["notes"]:
			lines.append("  - %s" % n)
	if result.get("unimplemented_mechanics", []).size() > 0:
		lines.append("\nNot yet mechanically wired up (described above for a GM to adjudicate):")
		for u in result["unimplemented_mechanics"]:
			lines.append("  - %s" % u)
	lines.append("\nEstimated cost to commission: %d Brass Pennies (%s to create)" % [result.get("estimated_cost_pennies", 0), result.get("time_to_create", "?")])
	return "\n".join(lines)
