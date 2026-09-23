extends RefCounted
class_name CorruptionResolver
## Implements Corruption (p.182-186): Corruption Points, the Corruption
## Threshold (Willpower Bonus + Toughness Bonus — see
## Character.get_corruption_threshold()), and Mutations gained when
## Corruption Points exceed that Threshold. Table wording below is
## original, not copied text — a good-faith, thematically-matched
## reconstruction of the book's Physical/Beast Head/Mental Mutation and
## Fixations tables, not a transcription. Re-share the actual table
## scans if exact book wording/ranges are wanted here instead.
##
## Scope for this pass (per the request): only the "Any Power" Physical
## Mutation table is actually rolled against automatically. The four
## Chaos god tables (Khorne/Nurgle/Slaanesh/Tzeentch) are kept as real
## data below for later use — e.g. a specific Chaos-aligned source
## explicitly calling for one — but nothing in this project rolls
## against them yet. The Mental Mutation and Fixations tables are also
## data-only stubs for now (documented as incomplete/starter sets) —
## crossing the Threshold currently always rolls Physical/Any Power.

## 1d100. Each entry: min/max (inclusive), a short mutation name, and a
## one-line description. "roll_again" entries (96-99) are handled by
## roll_physical_mutation() itself, same pattern as MagicResolver's
## "roll_again" Miscast tag.
const PHYSICAL_MUTATIONS_ANY_POWER := [
	{"min": 1, "max": 5, "name": "Extra Arm", "text": "A fully functional extra arm grows in, awkward to hide but impossible to ignore."},
	{"min": 6, "max": 10, "name": "Cloven Hooves", "text": "The feet reshape into cloven hooves — ordinary footwear no longer fits."},
	{"min": 11, "max": 15, "name": "Beast Head", "text": "The head reshapes into that of a beast (roll on the Beast Head table)."},
	{"min": 16, "max": 20, "name": "Extra Eye", "text": "A third eye opens somewhere on the body, blinking independently of the other two."},
	{"min": 21, "max": 25, "name": "Forked Tongue", "text": "The tongue splits in two; every word now comes with a faint hiss."},
	{"min": 26, "max": 30, "name": "Tentacle", "text": "One limb reshapes into a boneless, prehensile tentacle."},
	{"min": 31, "max": 35, "name": "Chitinous Hide", "text": "Patches of hard, insect-like plating spread slowly across the skin."},
	{"min": 36, "max": 40, "name": "Discoloured Skin", "text": "The skin shifts to an unnatural hue — scaled, mottled, or ashen."},
	{"min": 41, "max": 45, "name": "Cloud of Flies", "text": "A permanent, buzzing swarm of flies now follows everywhere."},
	{"min": 46, "max": 50, "name": "Vestigial Wing", "text": "A small, useless wing sprouts from the back."},
	{"min": 51, "max": 55, "name": "Fangs", "text": "The teeth lengthen into predatory fangs."},
	{"min": 56, "max": 60, "name": "Prehensile Tail", "text": "A long, fully functional tail grows in."},
	{"min": 61, "max": 65, "name": "Withered Limb", "text": "One limb shrivels — weakened, but still attached and usable."},
	{"min": 66, "max": 70, "name": "Overgrown Feature", "text": "One feature — nose, ears, or jaw — grows to a grotesque size."},
	{"min": 71, "max": 75, "name": "Talons", "text": "The fingers lengthen and harden into hooked talons."},
	{"min": 76, "max": 80, "name": "Warped Voice", "text": "The voice twists into something unnervingly inhuman."},
	{"min": 81, "max": 85, "name": "Weeping Sores", "text": "The body erupts in weeping sores that never fully heal."},
	{"min": 86, "max": 90, "name": "Horns", "text": "A pair of horns erupts from the skull."},
	{"min": 91, "max": 95, "name": "Extra Digit", "text": "Additional, unnatural fingers or toes appear."},
	{"min": 96, "max": 99, "name": "", "text": "Two mutations take hold at once — roll twice more on this table.", "roll_again": 2},
	{"min": 0, "max": 0, "name": "Wings", "text": "Full, functional wings erupt from the back."},
]

## 1d10 (or 1d100 collapsed to tens, per the book's own sub-table
## convention) — rolled when Physical Mutations returns "Beast Head".
const BEAST_HEAD_TABLE := [
	{"min": 1, "max": 1, "name": "Wolf", "text": "The head reshapes into a wolf's — keen senses, a lupine snout."},
	{"min": 2, "max": 2, "name": "Boar", "text": "The head reshapes into a boar's — tusks and a porcine snout."},
	{"min": 3, "max": 3, "name": "Serpent", "text": "The head reshapes into a serpent's — scaled, fanged, unblinking."},
	{"min": 4, "max": 4, "name": "Bird of Prey", "text": "The head reshapes into a raptor's — a hooked beak, piercing eyes."},
	{"min": 5, "max": 5, "name": "Bull", "text": "The head reshapes into a bull's — heavy horns, a broad muzzle."},
	{"min": 6, "max": 6, "name": "Rat", "text": "The head reshapes into a rat's — twitching whiskers, a narrow snout."},
	{"min": 7, "max": 7, "name": "Goat", "text": "The head reshapes into a goat's — curling horns, slitted eyes."},
	{"min": 8, "max": 8, "name": "Bat", "text": "The head reshapes into a bat's — oversized ears, a leathery snout."},
	{"min": 9, "max": 9, "name": "Lizard", "text": "The head reshapes into a lizard's — a reptilian, unblinking gaze."},
	{"min": 10, "max": 0, "name": "Hound", "text": "The head reshapes into a hound's — a canine muzzle, a lolling tongue."},
]

## 1d100 — STARTER SET ONLY. The book's Mental Mutation table runs the
## full range; only the first block is modelled here for now (the
## scans this was built from cut off partway through). Not currently
## rolled against by check_and_apply_threshold() (see the note at the
## top of this file) — kept here so it's ready to wire in once the
## rest of the table is available.
const MENTAL_MUTATIONS_ANY_POWER_PARTIAL := [
	{"min": 1, "max": 10, "name": "Aethyric Leak", "text": "Reality flickers faintly nearby whenever the character is distressed."},
	{"min": 11, "max": 20, "name": "Fitful Hatred", "text": "An intense, irrational hatred fixates on something specific (roll on the Fixations table)."},
	{"min": 21, "max": 30, "name": "Creeping Paranoia", "text": "A conviction that everyone nearby is watching, judging, or plotting."},
	{"min": 31, "max": 40, "name": "Split Attention", "text": "A second, whispering train of thought runs constantly underneath the first."},
	{"min": 41, "max": 52, "name": "Night Terrors", "text": "Sleep brings vivid, exhausting nightmares almost every night."},
	{"min": 53, "max": 55, "name": "Lingering Foulness", "text": "A faint, unplaceable wrongness clings to every thought — nothing feels quite clean anymore."},
	## 56-100 not yet modelled — see the file-level note above.
]

## 2d10 — STARTER SET ONLY, referenced by Mental's "Fitful Hatred"
## result. Not currently wired to anything (Mental table isn't rolled
## against yet either).
const FIXATIONS_TABLE_PARTIAL := [
	{"min": 2, "max": 3, "name": "Fire"},
	{"min": 4, "max": 5, "name": "A specific animal"},
	{"min": 6, "max": 7, "name": "A colour"},
	{"min": 8, "max": 9, "name": "A number"},
	{"min": 10, "max": 11, "name": "A particular phrase"},
	{"min": 12, "max": 13, "name": "A specific person"},
	{"min": 14, "max": 15, "name": "A smell"},
	{"min": 16, "max": 17, "name": "A sound"},
	{"min": 18, "max": 20, "name": "A direction"},
	## Remainder not yet modelled — see the file-level note above.
]

## Data-only for now (see the file-level note): NOT rolled against
## automatically anywhere in this project yet. A smaller, coarser
## table than Any Power's — enough to be real data for later, not a
## full 1-100 breakdown per entry.
const KHORNE_PHYSICAL_MUTATIONS := [
	{"min": 1, "max": 15, "name": "Bloodlust Boils", "text": "Veins bulge and pulse with feverish rage before every fight."},
	{"min": 16, "max": 30, "name": "Iron Jaw", "text": "The teeth fuse into a jagged, metal-hard bite."},
	{"min": 31, "max": 45, "name": "Blood Tears", "text": "The eyes weep thin trails of blood whenever anger flares."},
	{"min": 46, "max": 60, "name": "Skull Ridge", "text": "A bony crest rises across the brow, like a helm grown from bone."},
	{"min": 61, "max": 75, "name": "Rending Claws", "text": "The fingers harden into blade-like claws."},
	{"min": 76, "max": 90, "name": "Furnace Blood", "text": "The body runs hot enough to steam in cold air."},
	{"min": 91, "max": 99, "name": "Berserker's Mark", "text": "A brand-like scar burns itself into the skin after every kill."},
	{"min": 0, "max": 0, "name": "Brass Skin", "text": "Patches of skin harden into brass-like plates."},
]
const NURGLE_PHYSICAL_MUTATIONS := [
	{"min": 1, "max": 15, "name": "Weeping Rot", "text": "Patches of skin ooze a foul-smelling ichor."},
	{"min": 16, "max": 30, "name": "Fly-Blown", "text": "A permanent, thick halo of flies never leaves."},
	{"min": 31, "max": 45, "name": "Bloated Frame", "text": "The body swells, soft and waterlogged."},
	{"min": 46, "max": 60, "name": "Rancid Breath", "text": "The breath alone is enough to wilt nearby plants."},
	{"min": 61, "max": 75, "name": "Weeping Sores", "text": "Open sores that never close, oozing gently."},
	{"min": 76, "max": 90, "name": "Grub-Ridden", "text": "Something moves faintly beneath the skin."},
	{"min": 91, "max": 99, "name": "Plague Aura", "text": "A sickly-sweet stench of rot clings permanently to the body."},
	{"min": 0, "max": 0, "name": "Nurgling Companion", "text": "A small, cheerful daemon of decay follows at a distance."},
]
const SLAANESH_PHYSICAL_MUTATIONS := [
	{"min": 1, "max": 15, "name": "Flawless Skin", "text": "Unnervingly perfect, poreless skin."},
	{"min": 16, "max": 30, "name": "Extra Sensitivity", "text": "The senses sharpen to an almost painful degree."},
	{"min": 31, "max": 45, "name": "Shifting Beauty", "text": "Features subtly rearrange over time — always striking, never quite right."},
	{"min": 46, "max": 60, "name": "Silken Voice", "text": "A hypnotic, melodic voice."},
	{"min": 61, "max": 75, "name": "Elongated Limbs", "text": "The limbs stretch, elegant and unnervingly long."},
	{"min": 76, "max": 90, "name": "Iridescent Eyes", "text": "The eyes shift colour with mood, faintly luminous."},
	{"min": 91, "max": 99, "name": "Second Mouth", "text": "A small, whispering second mouth appears somewhere unexpected."},
	{"min": 0, "max": 0, "name": "Androgynous Perfection", "text": "The features soften into something beyond ordinary symmetry."},
]
const TZEENTCH_PHYSICAL_MUTATIONS := [
	{"min": 1, "max": 15, "name": "Shifting Eyes", "text": "The eye colour never settles, shifting with the light."},
	{"min": 16, "max": 30, "name": "Third Eye", "text": "A faintly glowing eye opens on the brow, usually kept hidden."},
	{"min": 31, "max": 45, "name": "Feathered Patch", "text": "A patch of iridescent feathers grows somewhere on the body."},
	{"min": 46, "max": 60, "name": "Ever-Changing Mark", "text": "A birthmark slowly rearranges itself over the course of weeks."},
	{"min": 61, "max": 75, "name": "Warpfire Fingertips", "text": "The fingertips spark faintly with chilling blue fire."},
	{"min": 76, "max": 90, "name": "Split Reflection", "text": "Mirrors and still water show a face a half-second out of sync."},
	{"min": 91, "max": 99, "name": "Fated Scarring", "text": "Faint runic scars appear, shifting meaning depending on who reads them."},
	{"min": 0, "max": 0, "name": "Twin-Faced", "text": "A second, faint face is visible on the back of the skull in the right light."},
]

const GOD_TABLES := {
	"khorne": KHORNE_PHYSICAL_MUTATIONS,
	"nurgle": NURGLE_PHYSICAL_MUTATIONS,
	"slaanesh": SLAANESH_PHYSICAL_MUTATIONS,
	"tzeentch": TZEENTCH_PHYSICAL_MUTATIONS,
}

## Rolls d100 against the requested table ("any" by default — the only
## one actually used automatically anywhere in this project right now,
## per the request: "only use the any power table unless a chaos god
## is specifically stated"). Resolves "roll_again" and "Beast Head"
## sub-rolls internally so the caller always gets one final, concrete
## result. Returns {"name": String, "text": String}.
static func roll_physical_mutation(power: String = "any") -> Dictionary:
	var table: Array = GOD_TABLES.get(power, PHYSICAL_MUTATIONS_ANY_POWER)
	var roll := Dice.d100()
	var entry: Dictionary = {}
	for row in table:
		var lo: int = row["min"]
		var hi: int = row["max"] if row["max"] != 0 else 100
		if roll >= lo and roll <= hi:
			entry = row
			break
	if entry.is_empty():
		entry = table[table.size() - 1]
	if entry.get("roll_again", 0) > 0:
		var names: Array[String] = []
		var texts: Array[String] = []
		for i in range(entry["roll_again"]):
			var sub := roll_physical_mutation(power)
			names.append(sub["name"])
			texts.append(sub["text"])
		return {"name": ", ".join(names), "text": entry["text"] + " (" + " / ".join(texts) + ")"}
	if entry.get("name", "") == "Beast Head":
		var beast_roll := Dice.d10()
		var beast: Dictionary = {}
		for row in BEAST_HEAD_TABLE:
			var lo: int = row["min"]
			var hi: int = row["max"] if row["max"] != 0 else 10
			if beast_roll >= lo and beast_roll <= hi:
				beast = row
				break
		if not beast.is_empty():
			return {"name": "Beast Head (%s)" % beast["name"], "text": beast["text"]}
	return {"name": entry.get("name", ""), "text": entry.get("text", "")}

## Applies a rolled mutation to `character` — recorded in
## mutations_gained (narrative/tracking only, same treatment as
## creature_traits: no automatic characteristic/skill change is
## derived from a mutation's name) — and resets Corruption Points to 0,
## matching the book's own "gain a Mutation, then reduce Corruption
## Points to 0" resolution. Returns a log-ready description line.
static func apply_mutation_to_character(character: Character, mutation: Dictionary) -> String:
	character.mutations_gained.append(mutation.get("name", "Mutation"))
	character.corruption_points = 0
	return "[color=#a05a9c]%s is warped by Chaos: %s — %s. (Corruption reset to 0/%d)[/color]" % [
		character.character_name, mutation.get("name", "Mutation"), mutation.get("text", ""),
		character.get_corruption_threshold(),
	]

## Checks whether `character`'s Corruption Points now exceed their
## Corruption Threshold (Willpower Bonus + Toughness Bonus) and, if so,
## rolls and applies an Any Power Physical Mutation. Returns the log
## line to show, or "" if nothing triggered. Safe to call after any
## Corruption-Point gain, from any source.
static func check_and_apply_threshold(character: Character) -> String:
	if character == null:
		return ""
	if character.corruption_points <= character.get_corruption_threshold():
		return ""
	var mutation := roll_physical_mutation("any")
	return apply_mutation_to_character(character, mutation)
