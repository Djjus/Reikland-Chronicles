extends Resource
class_name SocialEncounterDefinition
## A non-combat field encounter, per the request: a narrative exchange
## resolved with social Skills (Charm, Gossip, Leadership, Intimidate)
## instead of combat rolls — presented on its own screen with the same
## overall feel as a real battle (a log of what happened, roll cards,
## a Return button) but no initiative or turn order at all.
##
## Structure: two "rounds" of dialogue, each giving the player up to
## two attempts (the request's own "more than one chance to succeed")
## — a failed first attempt at a round offers a retry with a
## DIFFERENT skill (representing trying a different approach), and
## only a second failure at the same round actually ends the
## encounter. Succeeding at Round 1 leads into Round 2; succeeding at
## Round 2 is the real win. Failing a round for good branches to
## either a harmless "funny ending" (no reward) or a fight — the exact
## same monster(s) the story should have already made clear were
## present, never introduced as a surprise at the point of failure.
##
## Per the follow-up request: the NPC's name and gender are no longer
## fixed data — generated fresh each time via NPCNameGenerator and
## substituted into every text field via {name}/{subj}/{obj}/{poss}
## placeholders. Two independent parts of the story are ALSO
## randomized from pools of at least 6 each: `opening_flavors` (a
## short mood-setting detail folded into the intro) and `situations`
## (the actual secret/twist behind the NPC's behaviour, which
## determines both the win reveal and — since a situation can be
## either kind — the specific failure outcome for THIS playthrough of
## the encounter). Every text field may contain the placeholder tokens
## {name}/{subj}/{obj}/{poss} — substituted once, at encounter start,
## by SocialEncounterScreen.

@export var encounter_name: String = ""
## Per the request ("NPC portraits... social encounters are a bit
## boring/too flat"): a CareerPortraits key (see career_portraits.gd)
## giving this NPC a real face on the encounter screen — set once per
## encounter resource (the archetype's face, e.g. "always looks like a
## peddler"), not per-situation, since the randomized `situations` array
## below supplies the twist behind the NPC's behaviour while the NPC's
## visual archetype stays fixed. Empty or a key with no matching art
## falls back to CareerPortraits.FALLBACK_PATH, same as every other
## portrait in the game.
@export var portrait_career_key: String = ""
## Used to build this NPC's opposed target for each Skill roll —
## Fellowship covers Charm/Gossip/Leadership resistance, Willpower
## covers holding firm against Intimidate specifically (Cool's own
## linked characteristic), matching how each real Skill's own opposed
## Test would actually be resisted.
@export var npc_fellowship: int = 40
@export var npc_willpower: int = 40

## Social Combat's own opponent roster (Design Doc "Social Combat —
## Design Doc v1", Section 1/2, and the follow-up "make sure it
## supports multiple NPCs in the same social combat"). Most encounters
## leave this empty and rely on get_npcs() below to synthesize a
## single opponent from the legacy npc_fellowship/npc_willpower/
## portrait_career_key fields above — a genuine multi-opponent
## encounter (two thugs, a trio of guards) populates this directly
## instead, each entry with its own Composure/Wit/portrait.
@export var npcs: Array[SocialCombatNPCDefinition] = []

## Always returns at least one entry. If `npcs` was left empty (true
## for every one of the 12 core encounters today), synthesizes a
## single SocialCombatNPCDefinition from the legacy flat fields above
## so old data keeps working with Social Combat unchanged — no .tres
## migration required. The synthesized stats are reasonable defaults,
## not lore-accurate: intelligence/initiative have no real single-NPC
## equivalent in the old data model, so they're derived from
## Fellowship/Willpower rather than invented from nothing.
func get_npcs() -> Array[SocialCombatNPCDefinition]:
	if not npcs.is_empty():
		return npcs
	var synthesized := SocialCombatNPCDefinition.new()
	synthesized.fellowship = npc_fellowship
	synthesized.willpower = npc_willpower
	synthesized.intelligence = int(round((npc_fellowship + npc_willpower) / 2.0))
	synthesized.initiative = npc_willpower
	## Per the request ("social encounters have too much health (composure)
	## let half the current values for everyone"): halved from the
	## original 20 — see DifficultyTiers' own comment for the matching
	## party-side halving and its own halved Tier bonus table.
	synthesized.composure_max = 10
	synthesized.portrait_career_key = portrait_career_key
	return [synthesized]

## {situation_hook} in intro_text is replaced with the chosen
## situation's own hook text — see `situations` below.
@export_multiline var intro_text: String = ""
## At least 6 short, independent mood-setting details — a genuinely
## separate "part of the story" from the situation itself, so the
## SAME situation still reads differently run to run. One is chosen
## and appended to intro_text via {opening_flavor}.
@export var opening_flavors: Array[String] = []

@export var round1_skills: Array[String] = ["Charm", "Gossip", "Leadership", "Intimidate"]
@export_multiline var round1_prompt_text: String = ""
@export_multiline var round1_success_text: String = ""
@export_multiline var round1_retry_text: String = ""   ## shown after the FIRST failed attempt, inviting a different approach
@export_multiline var round1_final_fail_text: String = ""   ## shown after BOTH attempts fail

@export var round2_skills: Array[String] = ["Charm", "Gossip", "Leadership", "Intimidate"]
@export_multiline var round2_prompt_text: String = ""
@export_multiline var round2_retry_text: String = ""

@export var reward_xp: int = 5
@export var reward_item: String = ""   ## a name into GameData.item_db, granted on a genuine win

## Per the request ("it would be nice the conversation would evolve with
## each roll rather than only take place at the start and after all
## rolls are done"): short in-character reaction lines for THIS NPC,
## shown mid-Social-Combat as their Composure actually drops, instead of
## the conversation going silent between intro_text and success_reveal/
## funny_loss_text. Written at the encounter level (this NPC's fixed
## persona — the peddler, the watchman, and so on) rather than per
## `situations` entry, since these fire regardless of which situation
## was rolled for this playthrough and shouldn't spoil or contradict
## any of them.
##
## Two entries is the norm (not enforced): the first shows the first
## time this NPC's Composure drops to 66% or below, the second the
## first time it drops to 33% or below — see
## SocialEncounterScreen._maybe_show_npc_reaction() for the exact
## threshold math, which divides evenly however many lines are given.
## May contain the same {name}/{subj}/{obj}/{poss} placeholder tokens
## every other text field on this resource uses.
@export var npc_reaction_lines: Array[String] = []

## At least 6 entries, per the request. Each is a Dictionary:
## {"hook": String, "success_reveal": String, "is_combat": bool,
##  "combat_monster_names": Array[String], "funny_loss_text": String}
## One is chosen per playthrough of this encounter. "hook" fills
## {situation_hook} in intro_text. "success_reveal" is shown as the
## Round 2 win text. On a total failure, either combat_monster_names
## (if is_combat) or funny_loss_text is used — mirroring the old
## single-outcome fields, but now one of several possible twists
## instead of the encounter's only possible twist.
@export var situations: Array[Dictionary] = []
