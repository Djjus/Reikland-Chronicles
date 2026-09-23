extends RefCounted
class_name NPCNameGenerator
## Per the request: randomizes a social encounter's NPC name and
## gender each time, rather than a fixed name baked into the data.
## Names are Empire/Reikland-flavoured, original combinations, not
## drawn from any published sourcebook's own NPC list.

const MALE_NAMES := [
	"Otto", "Gerhardt", "Klaus", "Dieter", "Wilhelm", "Ludwig", "Reinhardt", "Fritz", "Manfred", "Heinrich",
]
const FEMALE_NAMES := [
	"Greta", "Ilsa", "Hedwig", "Ursula", "Brunhilde", "Katarin", "Adelheid", "Roswitha", "Meta", "Frieda",
]
const SURNAMES := [
	"Krantz", "Voss", "Steiner", "Hoffmann", "Baumann", "Faust", "Richter", "Wagner", "Brandt", "Zimmer",
]

class NameInfo:
	var full_name: String
	var gender: String   ## "male" or "female"
	var pronoun_subj: String   ## he / she
	var pronoun_obj: String    ## him / her
	var pronoun_poss: String   ## his / her

static func random_name() -> NameInfo:
	var info := NameInfo.new()
	if randi() % 2 == 0:
		info.gender = "male"
		info.pronoun_subj = "he"
		info.pronoun_obj = "him"
		info.pronoun_poss = "his"
		info.full_name = "%s %s" % [MALE_NAMES[randi() % MALE_NAMES.size()], SURNAMES[randi() % SURNAMES.size()]]
	else:
		info.gender = "female"
		info.pronoun_subj = "she"
		info.pronoun_obj = "her"
		info.pronoun_poss = "her"
		info.full_name = "%s %s" % [FEMALE_NAMES[randi() % FEMALE_NAMES.size()], SURNAMES[randi() % SURNAMES.size()]]
	return info
