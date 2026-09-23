extends RefCounted
class_name CombatEncounter
## Tracks turn order and round progression for one fight, following the
## rulebook's Combat Summary (p.156):
##   1. Determine Surprise (not automated here — apply Conditions before
##      starting the encounter if needed)
##   2. Round Begins
##   3. Characters Take Turns in Initiative order (highest first) —
##      this project uses a house rule for determining that order (see
##      roll_initiative below) rather than the book's own
##      characteristic-comparison method
##   4. Round Ends
##   5. Repeat until the fight is over
##
## Each combatant gets one Move and one Action per Turn, in either order
## (p.157) — this class only manages ordering/rounds; Move/Action choices
## are up to whatever's driving the encounter (UI, AI, etc).

var combatants: Array[Character] = []
var turn_order: Array[Character] = []
var round_number: int = 0
var current_turn_index: int = -1

## The shared Advantage Pool for this encounter (Up in Arms, p.133-135) —
## this project uses Group Advantage exclusively, so this always exists
## rather than being optional. Replace with a fresh one per encounter if
## you don't want pools carrying over between fights.
var advantage_pool: GroupAdvantagePool = GroupAdvantagePool.new()

func add_combatant(character: Character) -> void:
	if not combatants.has(character):
		combatants.append(character)

func remove_combatant(character: Character) -> void:
	combatants.erase(character)
	turn_order.erase(character)

## Exploration mode (Dungeon Encounter Screen rework): monsters that
## spawn onto an already-live turn order — a room's door opening, a
## hallway patrol — need to join THIS ROUND, not wait for a fresh
## roll_initiative() pass, which would reshuffle the whole order
## (including everyone who's already acted) and reset round_number/
## current_turn_index back to Round 1. This instead rolls just the one
## new arrival's own initiative (same formula/tiebreak roll_initiative()
## itself uses) and inserts them into the REMAINING slice of turn_order
## (current_turn_index+1 onward) at the position _compare_initiative
## would rank them — so anyone who's already had their Turn this Round is
## left completely untouched, and the new arrival still lands at a fair
## initiative slot for whatever's left of the Round instead of always
## going last (or first).
func add_combatant_mid_round(character: Character) -> void:
	add_combatant(character)
	if turn_order.has(character):
		return   ## already seated (e.g. re-added defensively) — never duplicate
	var agi_bonus := character.get_characteristic_bonus("agility")
	var init_bonus := character.get_characteristic_bonus("initiative")
	var roll := Dice.d10()
	_initiative_scores[character] = roll + agi_bonus + init_bonus
	_tiebreak_rolls[character] = Dice.d10()
	var insert_at := turn_order.size()
	for i in range(current_turn_index + 1, turn_order.size()):
		if _compare_initiative(character, turn_order[i]):
			insert_at = i
			break
	turn_order.insert(insert_at, character)

## Builds (or rebuilds) the turn order per this project's house rule:
## each combatant rolls 1d10 and adds it to their Agility Bonus +
## Initiative Bonus — highest total goes first. Ties are broken by
## the higher raw Initiative Bonus, then Agility Bonus, then (if still
## tied) a fresh 1d10-only roll-off.
##
## The roll is made ONCE per combatant up front, then reused for every
## comparison during the sort. Rolling fresh dice inside the comparator
## itself (as an earlier version of this did) makes the comparator
## non-deterministic across repeated calls on the same pair, which
## violates the ordering contract sort_custom relies on and can
## trigger Godot's "bad comparison function" warning intermittently.
func roll_initiative() -> void:
	turn_order = combatants.duplicate()
	_initiative_scores.clear()
	_tiebreak_rolls.clear()
	for c in turn_order:
		var agi_bonus := c.get_characteristic_bonus("agility")
		var init_bonus := c.get_characteristic_bonus("initiative")
		var roll := Dice.d10()
		_initiative_scores[c] = roll + agi_bonus + init_bonus
		_tiebreak_rolls[c] = Dice.d10()
	turn_order.sort_custom(_compare_initiative)
	round_number = 1
	current_turn_index = -1

var _initiative_scores: Dictionary = {}   ## Character -> int, set by roll_initiative()
var _tiebreak_rolls: Dictionary = {}   ## Character -> int (1d10), set by roll_initiative()

func _compare_initiative(a: Character, b: Character) -> bool:
	var score_a: int = _initiative_scores.get(a, 0)
	var score_b: int = _initiative_scores.get(b, 0)
	if score_a != score_b:
		return score_a > score_b
	var init_bonus_a := a.get_characteristic_bonus("initiative")
	var init_bonus_b := b.get_characteristic_bonus("initiative")
	if init_bonus_a != init_bonus_b:
		return init_bonus_a > init_bonus_b
	var agi_bonus_a := a.get_characteristic_bonus("agility")
	var agi_bonus_b := b.get_characteristic_bonus("agility")
	if agi_bonus_a != agi_bonus_b:
		return agi_bonus_a > agi_bonus_b
	## Still tied: a fresh 1d10-only roll-off, pre-rolled up front.
	var roll_a: int = _tiebreak_rolls.get(a, 0)
	var roll_b: int = _tiebreak_rolls.get(b, 0)
	return roll_a >= roll_b

## Advances to the next combatant's Turn, starting a new Round (and
## resetting per-round Advantage bookkeeping) when the order wraps.
## Returns the combatant whose Turn it now is, or null if turn_order is empty.
func advance_turn() -> Character:
	if turn_order.is_empty():
		return null
	current_turn_index += 1
	if current_turn_index >= turn_order.size():
		_on_round_end()
		current_turn_index = 0
		round_number += 1
	return turn_order[current_turn_index]

## Applies the Group Advantage "Losing Advantage" rule (p.134) at the end
## of each Round: the side with more still-standing combatants is
## dominant and takes 1 Advantage from the suppressed side (or gains 1 if
## the suppressed pool is empty). Equal headcounts default to "ally" as
## dominant — call `advantage_pool.resolve_round_end()` directly with
## your own GM ruling if you need different tie-breaking.
## Results of the most recent _on_round_end() condition ticks —
## {Character: summary_dict} — populated fresh each round for the UI
## layer to read right after advance_turn() and log appropriately
## (this class has no UI access of its own).
var last_round_end_condition_results: Dictionary = {}
## Advantage Pool before/after the Losing Advantage rule resolved this
## Round (p.134), plus which side was judged dominant — the UI layer
## reads this to report the actual shift, rather than the change
## happening silently with nothing shown for it.
var last_round_end_advantage_summary: Dictionary = {}

func _on_round_end() -> void:
	last_round_end_condition_results.clear()
	var ally_count := 0
	var adversary_count := 0
	## Per the request: Group Advantage is a combat-only mechanic (p.134)
	## — it must not tick during pure exploration (walking the dungeon
	## with no monsters encountered yet), where every Round would
	## otherwise silently hand the party 1 free Advantage since
	## ally_count > adversary_count(0) is trivially always true. Tracked
	## separately from adversary_count itself (which only counts
	## still-standing adversaries) so a Round that ends with the last
	## adversary already defeated still resolves its own final shift —
	## this only ever suppresses the rule for a Round that had no
	## adversary combatant in it at all.
	var has_adversary := false
	for c in turn_order:
		if c.allegiance == "adversary":
			has_adversary = true
		c.tick_active_buffs()
		c.riposte_uses_this_round = 0
		c.furious_assault_used_this_round = false
		## p.171 Resolve spend: "ignore all modifiers from all Critical
		## Wounds until the beginning of the next round" — this IS the
		## beginning of the next round, so the flag's effect ends here.
		c.critical_wound_penalties_ignored_this_round = false
		## Distract (p.142): see Character.advantage_denied_rounds_remaining's
		## own comment for the exact 2-decrements-to-clear timing that
		## covers "until the end of the next Round."
		if c.advantage_denied_rounds_remaining > 0:
			c.advantage_denied_rounds_remaining -= 1
		if is_defeated(c):
			continue
		## Master Condition List (p.167-169) round-end effects —
		## Bleeding/Ablaze/Poisoned Wound loss, and Bleeding's death
		## check while Unconscious. Applied to every still-standing
		## combatant, not just the player, so monster Bleeding/Ablaze
		## genuinely matters too.
		var result: Dictionary = c.tick_end_of_round_conditions(is_currently_engaged(c), broken_recovery_modifier.get(c, 0), hidden_from_enemies.get(c, false))
		## A real bug fix: this used to only store a result when Wounds
		## were actually lost or the character fell — a character who
		## ONLY recovered from a Condition (Stunned/Poisoned's Endurance
		## Test, Blinded/Deafened's chance, Broken's Cool Test — all of
		## which land in "notes") got silently dropped and never shown
		## to the player at all.
		if result["wounds_lost"] > 0 or result["fell_unconscious"] or result["died_from_bleeding"] or not result.get("notes", []).is_empty():
			last_round_end_condition_results[c] = result
		## Drilled (Up in Arms p.141): "Characters with the Drilled Talent
		## count as two combatants when determining Losing Advantage" — a
		## flat headcount bonus (not per-rank; the book states no "per
		## level" scaling for this specific effect, unlike its own Bonus
		## Tests line, which is the separate, ordinary +1 SL/rank Melee
		## bonus for testing "when beside an ally with Drilled"). Applies
		## to either side alike — a monster with Drilled would count
		## double too, though no monster data grants it today.
		var headcount: int = 2 if c.has_talent("Drilled") else 1
		if c.allegiance == "ally":
			ally_count += headcount
		else:
			adversary_count += headcount

	var ally_before := advantage_pool.get_pool("ally")
	var adversary_before := advantage_pool.get_pool("adversary")
	var dominant := "ally" if ally_count > adversary_count else ("adversary" if adversary_count > ally_count else "ally")
	if has_adversary:
		advantage_pool.resolve_round_end_by_headcount(ally_count, adversary_count)
	last_round_end_advantage_summary = {
		"ally_before": ally_before, "ally_after": advantage_pool.get_pool("ally"),
		"adversary_before": adversary_before, "adversary_after": advantage_pool.get_pool("adversary"),
		"dominant_side": dominant,
	}

func get_current_combatant() -> Character:
	if current_turn_index < 0 or current_turn_index >= turn_order.size():
		return null
	return turn_order[current_turn_index]

## Ends the encounter. The book doesn't specify pools resetting when
## combat ends, so `advantage_pool` is left as-is — assign a fresh
## GroupAdvantagePool yourself before the next encounter if you want to
## start clean.
func end_encounter() -> void:
	turn_order.clear()
	current_turn_index = -1
	round_number = 0

## Per the request: a strict rulebook reading (p.172-173) keeps
## Unconsciousness and 0 Wounds as separate states — some Critical
## Wound results (e.g. Body's "Painful Cut", Head's "Broken Jaw") can
## knock a character Unconscious on a failed Endurance Test while they
## still have Wounds left. This project simplifies that specifically
## for adversaries: an Unconscious enemy is now treated as defeated
## outright — skipped in turn order, excluded from get_living(),
## counted toward Victory, eligible for loot/XP — rather than either
## continuing to fight while nominally "helpless" or sitting inert in
## turn order forever doing nothing. Deliberately NOT extended to the
## player/allies — their own Unconscious handling (Fate spends,
## Bleeding's separate 10%-per-stack death check, a possible rescue)
## stays exactly as it already works; only an adversary's own presence
## in the fight is being fast-forwarded here.
func is_defeated(character: Character) -> bool:
	if character.wounds_current <= 0:
		return true
	return character.allegiance == "adversary" and character.conditions.has("Unconscious")

## Living combatants on a given side ("ally"/"adversary"), in turn order.
func get_living(side: String) -> Array[Character]:
	var result: Array[Character] = []
	for c in turn_order:
		if c.allegiance == side and not is_defeated(c):
			result.append(c)
	return result

## --- Outnumbering (p.162) -------------------------------------------------
## "If you out-number an opponent 2 to 1, you gain a bonus of +20 to hit
## your opponent in melee combat. If you outnumber an enemy by 3 to 1,
## you get an even larger bonus of +40 to hit... Outnumbering is
## generally determined by how many Characters are Engaged with each
## other" — a group-vs-group headcount, not an individual one. (The
## book's separate "outnumbered opponents lose 1 Advantage at the end of
## every Round" clause is deliberately NOT duplicated here — this
## project's Group Advantage round-end rule already reduces the weaker
## side's pool by headcount every Round, and applying both would
## double-penalise the same underlying idea.)
##
## Real bug fix (per the request: "make sure that engaging in combat is
## only triggered when combatants hit each other, just standing next to
## a combatant does not mean your engaged... if a 2nd defender join
## another defending who is currently outnumbered 2vs1, from the moment
## the 2nd defender hit one of the attackers these 4 combatants all now
## count as 1vs1, until one side looses a member after which the other
## side will outnumber them 2v1 — scales up to 3vs1 too"): two separate
## things are tracked now, deliberately kept apart —
##
## 1) `melee_engaged_pairs[a][b]` — a genuine undirected graph, true once
##    `a` and `b` SPECIFICALLY have made or received a melee attack
##    against EACH OTHER (see mark_melee_engaged). This is exactly "has
##    this specific pair actually fought," used where that precision
##    matters — e.g. deciding whether moving away from one particular
##    adversary should trigger a Flee free attack (Up in Arms p.140);
##    mere adjacency, or having fought some OTHER enemy, isn't enough.
## 2) `has_fought_anyone[c]` — a simple durable flag, true once `c` has
##    made or received ANY real melee attack against anyone, at any
##    point this encounter — deliberately NOT un-set if their original
##    opponent later dies or they reposition; once you've swung a blade
##    in this fight you're a genuine combat participant for the rest of
##    it, not reset to "innocent bystander."
##
## Outnumbering itself needs a THIRD thing neither of the above alone
## provides: which combatants are physically part of the SAME local
## scrum RIGHT NOW. That's live battlefield-position data this class
## deliberately doesn't own (see broken_recovery_modifier's own comment
## on the same division of responsibility) — field_encounter_screen.gd
## computes it fresh on every attack via its own _local_melee_cluster()
## (a live adjacency walk over battle_grid positions, not cached state)
## and passes the result in as `physical_cluster` below. Only cluster
## members with has_fought_anyone true actually count toward either
## side's headcount there — someone merely standing in the scrum without
## ever having swung doesn't inflate anyone's Outnumbering, but a
## bystander who HASN'T fought doesn't sever the cluster just by
## standing between two people who have, either.
##
## Together this correctly handles every case from the request: a lone
## first attacker gets nothing (mine < 2); a 2nd ally landing a hit
## brings the local headcount to 2, earning +20 for both; a 2nd
## defender's OWN landed hit (not mere arrival) folds them into the same
## live cluster, evening it back to 1v1; and whichever side loses a
## member goes back to being outnumbered 2:1 by the survivors —
## regardless of which specific pairing the casualty happened to be
## fighting, since the cluster is recomputed fresh from CURRENT
## adjacency every time, not frozen at the moment any one edge formed.
var melee_engaged_pairs: Dictionary = {}   ## Character -> {Character: true} — undirected; both directions always kept in sync
var has_fought_anyone: Dictionary = {}     ## Character -> true, durable for the rest of the encounter once set

## Broken Condition (p.168) round-end recovery inputs, set fresh by
## field_encounter_screen.gd right before each advance_turn() call (same
## division of responsibility as melee_engaged_pairs/has_fought_anyone
## above — battlefield distance/line-of-sight lives on the battle grid,
## not here) and consumed by _on_round_end() below.
## `broken_recovery_modifier`: Character -> int, the circumstance-scaled
## Cool Test bonus/penalty (Average +20 safe / Very Hard -30 danger).
## `hidden_from_enemies`: Character -> true, a full Round genuinely out
## of every living enemy's line of sight — an automatic recovery, no
## roll needed.
var broken_recovery_modifier: Dictionary = {}
var hidden_from_enemies: Dictionary = {}

## Marks TWO Characters as Engaged with EACH OTHER in melee — call once
## a real melee attack actually happens between exactly these two
## combatants (either direction) — not for ranged/Charge-that-hasn't-
## landed-yet/adjacency alone/etc. Records both the specific pairwise
## edge (melee_engaged_pairs, undirected) and each participant's own
## durable "has fought at all" flag (has_fought_anyone) — see the big
## comment above for why both exist.
func mark_melee_engaged(a: Character, b: Character) -> void:
	if not melee_engaged_pairs.has(a):
		melee_engaged_pairs[a] = {}
	if not melee_engaged_pairs.has(b):
		melee_engaged_pairs[b] = {}
	melee_engaged_pairs[a][b] = true
	melee_engaged_pairs[b][a] = true
	has_fought_anyone[a] = true
	has_fought_anyone[b] = true

## Whether `c` has personally made or received at least one real melee
## attack, against anyone, at any point this encounter, and is still
## alive — used wherever "is this combatant a genuine, established
## participant in melee" is what matters (not specifically WHO they
## fought): Broken's own recovery gate below, Outnumbering's own
## headcount, and a couple of monster-AI heuristics in
## field_encounter_screen.gd.
func is_currently_engaged(c: Character) -> bool:
	if is_defeated(c):
		return false
	return has_fought_anyone.get(c, false)

## Whether `a` and `b` have specifically traded blows with each other at
## some point this encounter (and both are still alive). Used where that
## precision matters and mere "each has fought SOMEONE" isn't enough —
## e.g. deciding whether moving away from one particular adversary
## should trigger a Flee free attack (Up in Arms p.140); mere adjacency
## is deliberately NOT enough on its own either.
func is_engaged_with(a: Character, b: Character) -> bool:
	if is_defeated(a) or is_defeated(b):
		return false
	return melee_engaged_pairs.get(a, {}).has(b)

## Headcount for Outnumbering purposes within a specific PHYSICAL
## cluster (see field_encounter_screen.gd's _local_melee_cluster — a
## live battle-grid adjacency walk, not stored here), with Combat
## Master's effect applied: "For each level in this Talent, you count
## as one more person for the purposes of determining if one side
## out-numbers the other" — so each counted character contributes
## 1 + their Combat Master rank, not just a flat 1. Only members with
## has_fought_anyone true actually count (see the big comment above) —
## `pretend_member`, if given, is force-counted regardless (preview use
## only, see get_outnumbering_bonus's own `pretend_engaged`).
func _cluster_headcount(cluster: Array, side: String, pretend_member: Character = null) -> int:
	var total := 0
	for c in cluster:
		if c.allegiance != side or is_defeated(c):
			continue
		if has_fought_anyone.get(c, false) or c == pretend_member:
			total += 1 + c.get_talent_rank("Combat Master")
	return total

## The to-hit bonus `attacker` gets from their side outnumbering the
## opposing side within `physical_cluster` (their CURRENT local scrum —
## see field_encounter_screen.gd's _local_melee_cluster, which computes
## this fresh from live battle-grid adjacency on every single attack, so
## it correctly shrinks the instant a member dies and grows the instant
## a new combatant's hit joins it), per the table above (extrapolated
## linearly beyond 3:1, since the book doesn't give a further table but
## the pattern is clear: +20 per whole multiple past 1:1). Requires the
## outnumbering side to have at least 2 qualifying (has_fought_anyone)
## members — a lone attacker doesn't benefit just because they
## personally attacked first; the bonus only kicks in once enough allies
## have actually joined THIS fight to outnumber the other side there,
## which then applies to every qualifying attacker in that cluster, not
## just whoever tipped the count.
##
## `pretend_engaged`, if true, treats `attacker` as already
## has_fought_anyone for this computation only, without mutating any
## state — used ONLY by the Attack button's own preview
## (_preview_attack_target_number), so the displayed roll number matches
## what mark_melee_engaged()+get_outnumbering_bonus() will actually
## produce once the attack is really thrown, without prematurely
## recording an engagement the player might still cancel out of. Real
## attack call sites always call mark_melee_engaged() first and pass
## false (the default) here.
func get_outnumbering_bonus(attacker: Character, physical_cluster: Array, pretend_engaged: bool = false) -> int:
	if is_defeated(attacker):
		return 0
	if not pretend_engaged and not has_fought_anyone.get(attacker, false):
		return 0
	var my_side := attacker.allegiance
	var their_side := "adversary" if my_side == "ally" else "ally"
	var pretend_member: Character = attacker if pretend_engaged else null
	var mine := _cluster_headcount(physical_cluster, my_side, pretend_member)
	var theirs := _cluster_headcount(physical_cluster, their_side, pretend_member)
	if mine < 2 or theirs < 1:
		return 0
	var ratio := int(mine / float(theirs))
	if ratio < 2:
		return 0
	return (ratio - 1) * 20

