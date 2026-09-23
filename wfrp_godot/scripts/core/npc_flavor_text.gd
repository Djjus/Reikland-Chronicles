extends RefCounted
class_name NPCFlavorText
## Per the request: content for the Overworld's NPC radial menu —
## Perception (a description of the NPC) and Gossip (a random piece
## of local rumour, not tied to any specific NPC). This project's
## NPCs don't currently have individual names or backstories (just
## dialogue text keyed by role — shopkeeper, priest, trainer, or a
## plain traveller), so descriptions are written per role instead,
## with a few variants each for some real variety rather than the
## same line every time. Original writing, in the same dark, cynical,
## grimdark-comedic voice as the rest of this project's narrative
## content — not from any published sourcebook.

const DESCRIPTIONS := {
	"shopkeeper": [
		"A merchant with the calculating eyes of someone who's already worked out your net worth down to the last Brass Penny, and is deciding how much of it they can talk you out of.",
		"Behind the counter stands someone who's clearly seen every excuse for why a customer can't quite pay full price, and has heard none of them twice.",
		"This one smiles with their whole face and none of their eyes — the universal expression of a trader who knows exactly what their stock is actually worth.",
	],
	"priest": [
		"A Sister of Shallya, hands stained with herbs and worse, radiating the specific patient calm of someone who's stitched together far too many people who really should have listened the first time.",
		"There's genuine kindness in this one's face, and the particular exhaustion of someone who heals the same fools' same wounds on a fairly regular schedule.",
		"A quiet, watchful presence — the kind of person who's seen enough of what people do to each other that nothing much startles them anymore.",
	],
	"trainer": [
		"An old hermit with the unmistakable look of someone who's spent far too long alone with books that were never meant to be read that closely.",
		"Robes that were probably fine clothes decades ago, a stare that's seen things that don't bear repeating, and the calm of someone who's made peace with most of it.",
		"There's an unsettling amount of confidence in how casually this one discusses things that should, by rights, be setting off every alarm bell you own.",
	],
	"traveller": [
		"Just another soul on the road, road-worn and keeping half an eye on you the way anyone sensible does with a stranger out here.",
		"Travel-stained clothes, a wary posture, and the particular look of someone who's clearly had at least one bad encounter already this week.",
		"Nothing remarkable at a glance — which, out here, is either reassuring or exactly what someone dangerous would want you to think.",
	],
}

## Not tied to any specific NPC — a general pool of local rumour and
## colour, per the request ("a random piece of Gossip about the local
## area"). A future Quest system could reasonably draw from (or
## replace) entries in this same pool once it exists.
const GOSSIP := [
	"\"Bandits took a whole cart off the north road last week. Driver made it back, minus his boots and most of his dignity.\"",
	"\"There's talk the old goblin fort's stirring again. Nobody's gone to check. Nobody's volunteering, either.\"",
	"\"Heard the miller's been watering down the flour again. Man could water down a stone if there was coin in it.\"",
	"\"Something's been getting into the northern cave that isn't the bears. The bears, for what it's worth, don't seem thrilled either.\"",
	"\"They say a Sigmarite preacher passed through last month raving about the end times. Usual nonsense — though he did leave before anyone could ask him to prove it.\"",
	"\"Local watch caught someone selling 'blessed' water from the village well. Same well the pigs drink from, mind.\"",
	"\"Heard tell a peddler's been through here more than once, always looking over his shoulder. Draw your own conclusions.\"",
	"\"Someone swears they saw lights out past the treeline at night. Everyone else swears that someone drinks too much.\"",
]

## Short, in-character small talk shown when the player actually Talks
## to an NPC (not Perception/Gossip) — a few lines per role, since
## real conversation should read a little differently from a passing
## Gossip rumour or a Perception once-over.
const SMALL_TALK := {
	"shopkeeper": [
		"\"Business is business, friend — but I'll admit, it's nice to talk to someone who isn't haggling for once.\"",
		"\"You'd be amazed what people try to sell me. Or maybe you wouldn't, out here.\"",
		"\"Keep your coin close and your blade closer. That's free advice, that is.\"",
	],
	"priest": [
		"\"Shallya's mercy finds everyone eventually — some of us just take the scenic route.\"",
		"\"You look like someone who's seen a fight recently. Sit a moment, if you need to.\"",
		"\"There's always more suffering than there are hands to ease it. Still, one does what one can.\"",
	],
	"trainer": [
		"\"Careful what you go poking at out there. Some things poke back.\"",
		"\"I didn't choose this life so much as fail to avoid it convincingly enough.\"",
		"\"Magic's a lot less glamorous once you've actually had to clean up after it.\"",
	],
	"traveller": [
		"\"Long road, this one. Good to see a face that isn't trying to rob me.\"",
		"\"You hear anything strange out this way? No? Give it time.\"",
		"\"I've learned to travel light and trust slowly. Seems to be working so far.\"",
	],
}

static func get_small_talk(role: String) -> String:
	var options: Array = SMALL_TALK.get(role, SMALL_TALK["traveller"])
	return options[randi() % options.size()]

static func get_description(role: String) -> String:
	var options: Array = DESCRIPTIONS.get(role, DESCRIPTIONS["traveller"])
	return options[randi() % options.size()]

static func get_gossip() -> String:
	if GOSSIP.is_empty():
		return "Nobody around here seems to have anything worth repeating today."
	return GOSSIP[randi() % GOSSIP.size()]
