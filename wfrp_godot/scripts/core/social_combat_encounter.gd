extends RefCounted
class_name SocialCombatEncounter
## Turn order and round progression for one Social Combat exchange, per
## the design doc ("Social Combat — Design Doc v1", Section 2) — mirrors
## CombatEncounter's own shape (combatants/turn_order/round_number/
## current_turn_index, advance_turn(), is_defeated(), get_living())
## deliberately closely, so anyone who already knows how a real fight's
## turn order works recognizes this immediately. The one real
## difference is what determines turn order: real combat rolls 1d10 +
## Agility Bonus + Initiative Bonus each round; Social Combat sorts by
## a fixed Wit score (Intelligence + Initiative, no die roll) computed
## once at encounter start — a war of wits doesn't re-roll who's
## quickest to speak every round the way a physical scuffle's footing
## might.
##
## Both party members and NPCs are plain Characters here (an NPC is
## built via SocialCombatNPCDefinition.to_character(), same "build a
## real Character on demand" pattern MonsterDefinition.to_character()
## already uses for monsters) — allegiance ("ally"/"adversary") is what
## tells the two apart, exactly as it already does in real combat.
## composure_current/composure_max (Character, Design Doc Section 1)
## stands in for wounds_current/wounds_max as this encounter's health
## pool.

var combatants: Array[Character] = []
var turn_order: Array[Character] = []
var round_number: int = 0
var current_turn_index: int = -1

## Per the request ("we need to limit the attempts somehow"): Social
## Combat previously had no round budget at all — advance_turn() would
## happily run forever until one side's Composure hit 0. A real
## conversation doesn't go on indefinitely either way; once neither side
## has broken the other by this many rounds, the exchange is treated as
## a stalemate (SocialEncounterScreen resolves it as a non-reward
## failure, same shape as any other lost encounter). Six rounds gives a
## typical 2-4 person party real room to work with, now that Attack
## Types actually come back on cooldown instead of being spent forever
## — see used_attack_types below.
const MAX_ROUNDS := 6

## True once round_number has gone past the cap with neither side
## broken — SocialEncounterScreen checks this right after advance_turn()
## and, if true, ends the encounter as a stalemate instead of handing
## out another turn.
func round_limit_reached() -> bool:
	return round_number > MAX_ROUNDS

## Per the original request ("stop the same character repeating the same
## action (one he's best at) each round") — a character who's just used a
## given Attack Type against a given NPC can't reuse it again right away.
##
## CORRECTED per a real, confirmed balance bug reported after playing
## this: the original version made a used Attack Type off the table for
## that character against that NPC for the REST of the encounter, with
## no way back — win, lose, or true tie, the attempt itself was what got
## spent. Since only 3 of the 4 Attack Types actually deal Composure
## damage (Reason only heals), that gave each character a hard, one-time
## damage ceiling of exactly 3 hits against any single NPC, forever. Once
## that ran dry (which happens fast — most of the 12 core encounters have
## only one NPC), the ONLY other damage action (Bring in the Muscle) costs
## 3 Rapport, which a Brass-tier party's own 2-point cap makes literally
## impossible to ever afford — so a character in that situation was left
## with nothing but Pass/Distract/Overwhelm (none of which deal Composure
## damage) while the NPC's own Momentum kept climbing and eventually wore
## the whole party down. "Momentum snowballs and... they can only pass
## until the NPC slowly beats them all" was the exact, accurate bug
## report.
##
## Fixed as a genuine COOLDOWN instead of a one-time spend: using an
## Attack Type against an NPC puts it on cooldown for ATTACK_TYPE_
## REFRESH_ROUNDS rounds (blocked the round it's used AND the very next
## one, available again 2 rounds after use), rather than being gone for
## good. That still satisfies the original ask — a character can't just
## spam their best move every single round — while removing the hard
## damage ceiling: a full 6-round encounter now gives real room to rotate
## back through Intimidate/Charm/Needle more than once each, rather than
## hitting a wall after 3 total attempts ever. Storage changed from
## Character -> {Character(npc): Array[int] (types ever used)} to
## Character -> {Character(npc): {AttackType: round it was last used}},
## so "used" can now expire rather than only ever accumulate.
var used_attack_types: Dictionary = {}

## How many rounds an Attack Type stays on cooldown after use, per
## (character, npc) — see used_attack_types' own comment for the full
## reasoning. 2 means: blocked the round it's used and the next one,
## available again starting 2 rounds later (e.g. used round 1 -> blocked
## rounds 1-2 -> free again round 3).
const ATTACK_TYPE_REFRESH_ROUNDS := 2

func has_used_attack_type(character: Character, npc: Character, attack_type: int) -> bool:
	var per_npc: Dictionary = used_attack_types.get(character, {})
	var used: Dictionary = per_npc.get(npc, {})
	if not used.has(attack_type):
		return false
	var used_round: int = used[attack_type]
	return round_number - used_round < ATTACK_TYPE_REFRESH_ROUNDS

## How many more rounds until this specific (character, npc, attack_type)
## comes off cooldown — 0 if it's already available (never used, or its
## cooldown has already elapsed). Used by the screen to show a real "back
## in N rounds" countdown instead of a flat, misleading "already tried"
## that used to imply "gone forever."
func rounds_until_attack_type_available(character: Character, npc: Character, attack_type: int) -> int:
	var per_npc: Dictionary = used_attack_types.get(character, {})
	var used: Dictionary = per_npc.get(npc, {})
	if not used.has(attack_type):
		return 0
	var used_round: int = used[attack_type]
	return maxi(0, ATTACK_TYPE_REFRESH_ROUNDS - (round_number - used_round))

func mark_attack_type_used(character: Character, npc: Character, attack_type: int) -> void:
	if not used_attack_types.has(character):
		used_attack_types[character] = {}
	var per_npc: Dictionary = used_attack_types[character]
	if not per_npc.has(npc):
		per_npc[npc] = {}
	var used: Dictionary = per_npc[npc]
	## Overwrites any prior round on a re-use (e.g. reused the moment its
	## old cooldown lapsed) — correct either way, since the cooldown
	## should always count from the MOST RECENT use.
	used[attack_type] = round_number

## True if `character` still has at least one trained Attack Type left
## to use against `npc` — checked by the screen so it can offer a
## fallback (a Maneuver, or Pass) when all four are spent for this
## matchup, rather than leaving every Attack Type button disabled with
## nothing else to do.
func has_any_attack_type_available(character: Character, npc: Character) -> bool:
	for attack_type in [SocialCombatResolver.AttackType.INTIMIDATE, SocialCombatResolver.AttackType.CHARM,
			SocialCombatResolver.AttackType.NEEDLE, SocialCombatResolver.AttackType.REASON]:
		if SocialCombatResolver.can_use(attack_type, character) and not has_used_attack_type(character, npc, attack_type):
			return true
	return false

## The party's own Rapport Pool (Design Doc Section 3) — owned here,
## same as real combat's own advantage_pool lives on CombatEncounter,
## so a unit test can exercise it without needing a screen at all.
## rapport_max is (re)computed in roll_initiative(), once every present
## party member is already seated as a combatant.
var rapport_pool: SocialRapportPool = SocialRapportPool.new()
var rapport_max: int = 2

func add_combatant(character: Character) -> void:
	if not combatants.has(character):
		combatants.append(character)

func remove_combatant(character: Character) -> void:
	combatants.erase(character)
	turn_order.erase(character)

## Builds (or rebuilds) the turn order, sorted by Wit (Intelligence +
## Initiative) — highest first. Ties are broken by a fresh 1d10 roll-
## off, pre-rolled up front for the same "deterministic comparator"
## reason CombatEncounter.roll_initiative()'s own comment explains (a
## comparator that rolls fresh dice on every comparison during the sort
## violates sort_custom's ordering contract).
func roll_initiative() -> void:
	turn_order = combatants.duplicate()
	_wit_scores.clear()
	_tiebreak_rolls.clear()
	for c in turn_order:
		var wit: int = c.get_effective_characteristic_value("intelligence") + c.get_effective_characteristic_value("initiative")
		_wit_scores[c] = wit
		_tiebreak_rolls[c] = Dice.d10()
	turn_order.sort_custom(_compare_wit)
	round_number = 1
	current_turn_index = -1
	rapport_max = SocialRapportPool.max_for_party(get_living("ally"))

var _wit_scores: Dictionary = {}   ## Character -> int, set by roll_initiative()
var _tiebreak_rolls: Dictionary = {}   ## Character -> int (1d10), set by roll_initiative()

func _compare_wit(a: Character, b: Character) -> bool:
	var wit_a: int = _wit_scores.get(a, 0)
	var wit_b: int = _wit_scores.get(b, 0)
	if wit_a != wit_b:
		return wit_a > wit_b
	var roll_a: int = _tiebreak_rolls.get(a, 0)
	var roll_b: int = _tiebreak_rolls.get(b, 0)
	return roll_a >= roll_b

## Advances to the next combatant's Turn, starting a new Round when the
## order wraps, and silently skipping anyone currently defeated —
## exactly CombatEncounter.advance_turn()'s own shape, minus the
## Advantage-pool round-end hook (Social Combat's own Rapport Pool,
## Design Doc Section 3, isn't a per-round-end mechanic the way Group
## Advantage's "Losing Advantage" rule is). Returns null only if every
## combatant is defeated (the encounter should already have ended by
## then — see SocialEncounterScreen's own win/lose check).
func advance_turn() -> Character:
	if turn_order.is_empty():
		return null
	var attempts := 0
	while attempts <= turn_order.size():
		current_turn_index += 1
		if current_turn_index >= turn_order.size():
			current_turn_index = 0
			round_number += 1
		var candidate: Character = turn_order[current_turn_index]
		if not is_defeated(candidate):
			return candidate
		attempts += 1
	return null   ## everyone is defeated

## A party member "knocked out of the conversation" (Design Doc Section
## 8) can no longer act, but — unlike a defeated NPC — stays a legal
## target and stays visible; only Composure <= 0 is checked here, same
## single condition for both sides, matching how Wounds <= 0 alone
## already gates a lot of real-combat logic.
func is_defeated(character: Character) -> bool:
	return character.composure_current <= 0

## Living combatants on a given side ("ally"/"adversary"), in turn
## order — directly mirrors CombatEncounter.get_living().
func get_living(side: String) -> Array[Character]:
	var result: Array[Character] = []
	for c in turn_order:
		if c.allegiance == side and not is_defeated(c):
			result.append(c)
	return result

## True once every NPC ("adversary") on the roster is defeated — the
## party's win condition (Design Doc Section 8).
func all_npcs_defeated() -> bool:
	return get_living("adversary").is_empty()

## True once every present party member ("ally") is defeated — the
## whole-encounter failure condition (Design Doc Section 8).
func all_party_defeated() -> bool:
	return get_living("ally").is_empty()
