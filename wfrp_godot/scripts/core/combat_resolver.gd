extends RefCounted
class_name CombatResolver
## Implements the core rulebook's melee/ranged attack sequence (p.158-160):
##   1. Roll to Hit (Opposed Melee Test, or unopposed Ranged Test)
##   2. Determine Hit Location (reverse the digits of the roll to hit)
##   3. Determine Damage (Weapon Damage + SL)
##   4. Apply Damage (subtract Toughness Bonus + Armour Points, min 1 Wound)
## plus Criticals/Fumbles and the Oops! Table (p.159-160).
##
## Not yet implemented (flagged rather than guessed at): grappling,
## two-weapon fighting, mounted combat, outnumbering bonuses, called shots,
## size modifiers, shooting into a group/melee, scatter. These are all
## real rules but layering all of them in at once risked getting more of
## them subtly wrong — the core loop below is verified against the book.

## Shooting's own Size modifier table — a flat bonus/penalty purely
## from the TARGET's Size category, independent of the attacker's own
## size (unlike melee's relative Size rule below). Indexed the same as
## Character.SIZE_STEPS (0=Tiny .. 6=Monstrous): Tiny -30, Little -20,
## Small -10, Average 0, Large +20, Enormous +40, Monstrous +60. See
## resolve_ranged_attack's own comment for why this replaced the old
## (wrong) reuse of melee's Size rule for ranged Tests.
const RANGED_SIZE_MODIFIERS: Array[int] = [-30, -20, -10, 0, 20, 40, 60]

## Hit Locations table (p.159). Roll is the *reversed* digits of the roll
## to hit (e.g. a to-hit roll of 23 becomes 32 for this lookup). "00" is
## represented as 100 throughout this project's dice code.
const HIT_LOCATIONS := [
	{"min": 1, "max": 9, "location": "Head"},
	{"min": 10, "max": 24, "location": "Left Arm"},
	{"min": 25, "max": 44, "location": "Right Arm"},
	{"min": 45, "max": 79, "location": "Body"},
	{"min": 80, "max": 89, "location": "Left Leg"},
	{"min": 90, "max": 100, "location": "Right Leg"},
]

## Oops! Table (p.160) — rolled on any failed combat Test that's also a
## double. Wording below is original, not copied from the book; the
## roll ranges and mechanical effects match it.
const OOPS_TABLE := [
	{"min": 1, "max": 20, "tag": "self_inflicted_wound",
		"text": "You catch yourself awkwardly — lose 1 Wound, ignoring Toughness Bonus and Armour Points."},
	{"min": 21, "max": 40, "tag": "weapon_damaged_act_last",
		"text": "Your weapon jars or fumbles in your grip; it takes 1 point of damage, and you act last next round regardless of Initiative."},
	{"min": 41, "max": 60, "tag": "next_action_penalty",
		"text": "You're left badly out of position; your next Action suffers a -10 penalty."},
	{"min": 61, "max": 70, "tag": "lose_next_move",
		"text": "You stumble and struggle to right yourself; you lose your next Move."},
	{"min": 71, "max": 80, "tag": "miss_next_action",
		"text": "You mishandle your weapon or drop your ammunition; you miss your next Action entirely."},
	{"min": 81, "max": 90, "tag": "critical_wound_minor",
		"text": "You overextend and wrench something; you suffer a minor Critical Wound."},
	{"min": 91, "max": 100, "tag": "hit_random_ally_or_self",
		"text": "You badly mishandle the attack — it lands on a random ally in range (using your roll's units digit as SL), or if none are in range, on yourself, leaving you Stunned."},
]

class AttackResult:
	var hit: bool = false
	var attacker_test: TestResolver.TestResult
	var defender_test: TestResolver.TestResult   ## null for unopposed ranged attacks
	var hit_location: String = ""
	var damage: int = 0
	var weapon_damage: int = 0    ## the flat/SB-based component, before Opposed SL is added
	var soak: int = 0
	var wounds_dealt: int = 0
	var was_critical: bool = false
	var caused_critical_wound: bool = false
	## Set only when caused_critical_wound is true — the actual rolled
	## result from Up in Arms' Critical Wound tables (p.83-86).
	var critical_wound_location: String = ""
	var critical_wound_entry: Dictionary = {}
	var critical_wound_roll: int = 0
	var critical_wound_overkill_bonus: int = 0   ## the +10-per-excess-Wound portion baked into critical_wound_roll, tracked separately so the UI can show it explicitly rather than guessing
	var critical_wound_extra_wounds: int = 0   ## already applied to the defender by the time this is set
	var critical_wound_causes_death: bool = false
	## Per the follow-up request ("if the critical is against a 0 wounds
	## target, then the wounds from the critical dont matter anyway only
	## that they go unconscious or death... dont display critical wounds
	## at all in that case"): true when the defender had already been
	## reduced to 0 Wounds (or was already there) BEFORE this hit was
	## even applied — i.e. this Critical Wound roll is the "already
	## downed, what actually happens to them" case (p.81's own worked
	## example), not a critical landed on someone still standing. Set
	## from the same `wounds_before_hit` _roll_critical_wound() itself
	## already branches on — see _apply_hit below.
	var critical_wound_target_already_down: bool = false
	var fumble: Dictionary = {}   ## Oops! Table result, if any
	## Per the request: melee Parry doubles cause real Critical/Fumble
	## consequences of their own, same as an attack roll does. A
	## fumbled Parry (defender_fumble) is a separate Oops! Table roll —
	## the defender fumbling their own attempted Parry, regardless of
	## who won the opposed test. A critical Parry is a riposte: rather
	## than grant Advantage, per the follow-up request, it lands a real
	## counter-hit — a flat 1 Wound plus a full Critical Wound roll —
	## directly on the ATTACKER, tracked in the riposte_* fields below.
	var defender_fumble: Dictionary = {}
	## Per the request: a genuine tie (same Success Level AND same Target
	## Number — see TestResolver.resolve_opposed()'s own comment) means
	## the exchange cancels out completely: no hit, and none of the
	## defender's own "successfully defended" consequences either.
	var is_true_tie: bool = false
	var critical_parry_counter_triggered: bool = false
	var critical_parry_counter_wounds_dealt: int = 0   ## the flat 1-Wound counter-hit itself -- NOT the critical table's own Wounds column, see critical_parry_counter_extra_wounds below
	var critical_parry_counter_wound_location: String = ""
	var critical_parry_counter_wound_entry: Dictionary = {}
	var critical_parry_counter_wound_roll: int = 0
	var critical_parry_counter_extra_wounds: int = 0   ## the counter-strike's OWN Critical Wound table "Wounds" column, already applied to the attacker by the time this is set -- mirrors critical_wound_extra_wounds above
	var critical_parry_counter_causes_death: bool = false
	var critical_parry_counter_target_already_down: bool = false   ## mirrors critical_wound_target_already_down above, for the counter-strike's own roll
	## True when the real Riposte Talent actually triggered (a genuine
	## Talent-gated effect, distinct from the doubles-based counter-
	## strike above — see the "else" branch of the opposed test below).
	var riposte_talent_triggered: bool = false
	var riposte_talent_wounds_dealt: int = 0
	var riposte_talent_hit_location: String = ""
	var reversal_used: bool = false   ## true if the defender's Reversal Talent fired
	var talent_damage_bonus: int = 0
	var talent_damage_source: String = ""
	var damage_sl_used: int = 0   ## the Success Levels actually added into damage — exposed directly rather than derived later by subtraction
	var impact_bonus: int = 0   ## from the Impact weapon Quality or Size (p.298/341) — flat bonus damage on a hit
	var ammo_damage_bonus: int = 0   ## from the attacker's currently-loaded Ammunition item's ammo_damage_bonus (e.g. Elf Arrow, Lead Bullet, Bullet and Powder) — 0 for melee/Throwing or when no ammo bonus applies
	var ammo_name: String = ""   ## the Ammunition item name that produced ammo_damage_bonus above (e.g. "Elf Arrow") — "" whenever ammo_damage_bonus is 0, used only for the damage-breakdown UI label
	var active_buff_bonus: int = 0   ## from a timed Spell/Blessing/Miracle buff (e.g. Sigmar's Fiery Hammer)
	var size_damage_multiplier: int = 1   ## from Size (p.341) — applied to the additive sum above, not folded into it
	## Shield (Rating), p.298: "If you use this weapon to oppose an
	## incoming attack, you count as having (Rating) Armour Points on
	## all locations of your body" — set by the caller when the defender
	## chose to Parry with a shield, applied to soak in _apply_hit.
	var defender_shield_ap_bonus: int = 0
	## Blackpowder (p.297): "Any character... targeted by an attack from
	## a Blackpowder weapon must succeed on an Average (+20) Cool Test or
	## gain the Broken Condition" — fires whether or not the shot itself
	## hits, so tracked here rather than folded into the hit-only fields
	## below. Null when the firing weapon isn't Blackpowder at all.
	var blackpowder_cool_test: TestResolver.TestResult = null
	var blackpowder_broken_applied: bool = false
	## Entangle (p.298): true when this hit applied the Entangled
	## Condition to the defender.
	var entangle_applied: bool = false
	## Distract (p.298): true when this hit's Damage/Wounds were
	## suppressed to zero by the Distract Quality.
	var distract_applied: bool = false
	## Blast (Rating) (p.297): every OTHER living character on the
	## target's side also caught in the blast, each entry
	## {"character": Character, "wounds_dealt": int, "hit_location": String}
	## — set by the caller (field_encounter_screen.gd) from its own
	## roster, since this resolver has no concept of "sides" beyond the
	## two combatants passed in.
	var blast_hits: Array[Dictionary] = []
	## Trap Blade (p.298): a Critical Parry against a bladed weapon with
	## a Trap Blade weapon runs an Opposed Strength Test instead of the
	## normal doubles counter-hit — these fields describe that exchange
	## in place of the critical_parry_counter_* fields above, which are
	## left at their defaults when Trap Blade fires.
	var trap_blade_triggered: bool = false
	var trap_blade_test: TestResolver.TestResult = null   ## the defender's (Trap Blade wielder's) Strength Test
	var trap_blade_opposing_test: TestResolver.TestResult = null   ## the attacker's Strength Test
	var trap_blade_disarmed: bool = false   ## true if the defender won and disarmed the attacker
	var trap_blade_weapon_destroyed: bool = false   ## true if the defender won with 6+ SL (Astounding Success) and the attacker's weapon wasn't Unbreakable/indestructible
	## Shoddy (p.302, general Item Flaw — see ItemQualityRules): true if
	## the attacker's own weapon just broke because this attack Test
	## failed on a rolled double. False both when Shoddy didn't fire AND
	## when it fired but a Durable saving throw spared the weapon.
	var attacker_weapon_broke_shoddy: bool = false
	## Shoddy (p.302, general Item Flaw): the name(s) of any equipped
	## Shoddy armour piece(s) covering this hit's own Hit Location that
	## broke outright because it took a genuine Critical Hit — see
	## _apply_hit. Empty when Shoddy didn't fire, when nothing Shoddy
	## covers that location, or when a Durable saving throw spared it.
	var shoddy_armour_broken: Array[String] = []

## Reverses the two digits of a d100 roll (1-100, where 100 represents
## "00"), per the book's hit-location method: a roll of 23 becomes 32.
## Computes what defending with a specific weapon actually grants:
## - Defensive Quality (p.298): "+1 SL to any Melee Test when you
##   oppose an incoming attack" if wielding a Defensive weapon — note
##   this is "wielding," not "parrying with": a shield with Defensive
##   held in the off-hand grants its +1 SL even while parrying with
##   the main weapon, and vice versa. Checked across both of the
##   defender's equipped hands here, not just whichever one is
##   actually making the Parry roll — a real bug fix, since this only
##   ever checked the single weapon passed in before.
## - The off-hand penalty (-20, matching the same penalty Dual Wielder
##   already applies to an off-hand attack): normally applies to
##   defending with an off-hand item too, UNLESS it's a one-handed
##   Defensive weapon — "Any one-handed weapon with the Defensive
##   Quality can be used with Melee (Parry)... without the normal -20
##   off-hand penalty" (p.296) — or rank-scaled down/removed entirely by
##   Ambidextrous (see Character.get_offhand_penalty(): 0/-10/-20 by
##   rank, matching every other off-hand-penalty call site).
##   This part stays tied to the specific weapon actually parrying,
##   since the penalty is about which hand is making the attempt, and
##   requires the weapon to genuinely be one-handed — a two-handed
##   Defensive weapon (there are none in the current data, but nothing
##   stops one being added) still owes the full off-hand penalty.
## - Shield (Rating) (p.298): "(Rating) Armour Points on all locations
##   of your body" while using it to oppose an incoming attack.
##
## Weapon Groups (p.296): Defensive/Shield are Qualities, so both are
## read off `defender.get_effective_weapon_qualities()` rather than the
## weapon's own raw `qualities` — an untrained defender loses them
## entirely, same as every other Quality.
static func get_defense_modifiers(defender: Character, weapon: WeaponDefinition, is_offhand: bool) -> Dictionary:
	var sl_breakdown: Array = []
	var target_breakdown: Array = []
	var shield_ap := 0
	if weapon == null:
		return {"sl_breakdown": sl_breakdown, "target_breakdown": target_breakdown, "shield_ap": shield_ap}

	var effective_qualities := defender.get_effective_weapon_qualities(weapon)
	var is_defensive := effective_qualities.has("Defensive")
	## Also check the OTHER hand — a Defensive item you're wielding
	## grants its bonus regardless of which weapon actually makes the
	## Parry roll.
	var other_hand_weapon: WeaponDefinition = defender.get_offhand_weapon() if not is_offhand else defender.get_equipped_weapon()
	var other_hand_defensive := other_hand_weapon != null and other_hand_weapon != weapon and defender.get_effective_weapon_qualities(other_hand_weapon).has("Defensive")
	if is_defensive:
		sl_breakdown.append({"name": "Defensive (%s)" % weapon.weapon_name, "amount": 1})
	if other_hand_defensive:
		sl_breakdown.append({"name": "Defensive (%s, other hand)" % other_hand_weapon.weapon_name, "amount": 1})

	var one_handed_defensive := is_defensive and not weapon.is_two_handed
	if is_offhand and not one_handed_defensive:
		var offhand_defense_penalty := defender.get_offhand_penalty()
		if offhand_defense_penalty < 0:
			target_breakdown.append({"name": "Off-hand penalty", "amount": offhand_defense_penalty})

	for q in effective_qualities:
		if q.begins_with("Shield "):
			var rating_str := q.trim_prefix("Shield ")
			if rating_str.is_valid_int():
				shield_ap = int(rating_str)

	return {"sl_breakdown": sl_breakdown, "target_breakdown": target_breakdown, "shield_ap": shield_ap}

## Reverses the two digits of a d100 roll (1-100, where 100 represents
## "00"), per the book's hit-location method: a roll of 23 becomes 32.
static func reverse_roll(roll: int) -> int:
	var r := roll % 100   ## 100 ("00") -> 0
	var tens := int(r / 10)
	var units := r % 10
	var reversed := units * 10 + tens
	if reversed == 0:
		reversed = 100   ## "00" stays "00"
	return reversed

## Impale (p.298): "causes a Critical Hit on any roll that is divisible
## by 10, or any roll that is doubles" — a real bug fix: only the
## divisible-by-10 half was ever checked before; the doubles clause
## (11/22/.../99) was missing entirely.
static func _is_impale_trigger(roll: int) -> bool:
	if roll % 10 == 0:
		return true
	return (roll / 10) % 10 == roll % 10

static func get_hit_location(reversed_roll: int) -> String:
	for entry in HIT_LOCATIONS:
		if reversed_roll >= entry["min"] and reversed_roll <= entry["max"]:
			return entry["location"]
	return "Body"

## Careful Strike (p.134): "You may modify your Hit Location result by
## up to +/-10 per time you have this Talent. So, if you had this Talent
## twice and hit location 34, the Right Arm, you could modify this down
## to 14, the Left Arm, or up to 54, the Body." Per the request, this is
## now a genuine player choice offered in the combat log right after a
## hit lands (see field_encounter_screen.gd's _offer_careful_strike_
## choice), rather than an automatic shift — this helper just computes
## which OTHER Hit Locations are actually reachable from the natural
## roll, for that picker to offer. A location is reachable if any point
## in [reversed_roll - 10*rank, reversed_roll + 10*rank] (clamped to the
## valid 1-100 roll range) falls inside that location's own band.
static func careful_strike_reachable_locations(reversed_roll: int, rank: int) -> Array:
	var options: Array = []
	if rank <= 0:
		return options
	var max_shift := 10 * rank
	var lo: int = max(1, reversed_roll - max_shift)
	var hi: int = min(100, reversed_roll + max_shift)
	var natural := get_hit_location(reversed_roll)
	for entry in HIT_LOCATIONS:
		if entry["location"] == natural:
			continue
		if entry["max"] >= lo and entry["min"] <= hi:
			options.append(entry["location"])
	return options

static func roll_oops() -> Dictionary:
	var roll := Dice.d100()
	for entry in OOPS_TABLE:
		if roll >= entry["min"] and roll <= entry["max"]:
			return {"roll": roll, "tag": entry["tag"], "text": entry["text"]}
	return {}

## Resolves one melee attack. Default defence is an Opposed Melee Test
## (both combatants test the "Melee" skill using the attacker's weapon
## group) — pass a different `defense_skill`/`defense_specialisation`
## (e.g. Dodge) if the defender chooses to react differently (p.159).
##
## `pool`: the shared GroupAdvantagePool (Up in Arms, p.133-135) — this
## project uses Group Advantage exclusively, so this is required, not
## optional. Advantage bonuses/gains route through the pool by each
## combatant's `allegiance`.
##
## `defender_uses_reversal`: if the defender has the Reversal Talent
## (Up in Arms, p.140) and chooses to use it, pass true — on a defensive
## win they take 1 Advantage from the attacker's pool instead of the
## normal +1 Winning gain, and deal no Damage even if it's their Turn.
static func resolve_melee_attack(attacker: Character, defender: Character,
		weapon: WeaponDefinition, pool: GroupAdvantagePool, defense_skill: SkillDefinition = null,
		defense_specialisation: String = "", defender_uses_reversal: bool = false,
		attacker_extra_modifier: int = 0, defender_extra_modifier: int = 0,
		attacker_forced_roll: int = -1, defender_extra_sl_breakdown: Array = [],
		defender_shield_ap_bonus: int = 0, attacker_extra_scopes: Array = [],
		defender_forced_roll: int = -1, is_charge: bool = false,
		attacker_extra_sl_breakdown: Array = [], blast_candidates: Array[Character] = [],
		forced_hit_location: String = "") -> AttackResult:
	var result := AttackResult.new()
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")

	## Close the Distance / In-Fighting (p.297): "During in-fighting,
	## any weapon longer than Short counts as an Improvised weapon."
	## Substituted here, before anything below reads the weapon's own
	## stats/qualities/reach, so every downstream calculation (damage,
	## qualities, everything in this function) genuinely uses the
	## Improvised Weapon's numbers rather than the real weapon's.
	if attacker.conditions.has("In-Fighting"):
		var reach_rank := {"Personal": 0, "Very Short": 1, "Short": 2, "Average": 3, "Long": 4, "Very Long": 5, "Massive": 6}
		if int(reach_rank.get(weapon.reach, 3)) > 2:
			var improvised: WeaponDefinition = GameData.weapon_db.find_by_name("Improvised Weapon")
			if improvised != null:
				weapon = improvised

	## Surprise (Up in Arms p.133): attacking a Surprised target grants
	## the attacker's side +1 Advantage regardless of whether the attack
	## itself lands. Distract (p.142) gates every Advantage gain
	## attributable to the DISTRACTED character's own actions — see
	## Character.is_advantage_denied()'s own comment.
	if defender.conditions.has("Surprised") and not attacker.is_advantage_denied():
		pool.gain_surprise(attacker.allegiance)
	## Stunned (p.168): "If you have any Stunned Conditions, any
	## opponent trying to strike you in Melee Combat gains +1 Advantage
	## before rolling the attack." Only once per attack, regardless of
	## how many Stunned Conditions are stacked — the book says "any,"
	## not "per."
	if defender.conditions.has("Stunned") and not attacker.is_advantage_denied():
		pool.add(attacker.allegiance, 1)

	## Advantage does NOT automatically add to any roll under Up in Arms
	## — the only way it modifies a Test is a deliberate spend via
	## Additional Effort (p.134), which is exactly what
	## `attacker_extra_modifier`/`defender_extra_modifier` represent —
	## either side can independently spend their own Effort on their own
	## half of this Opposed Test (e.g. the defender boosting their Dodge).
	var attacker_mod := attacker_extra_modifier
	var attacker_mod_breakdown: Array = []
	if attacker_extra_modifier != 0:
		attacker_mod_breakdown.append({"name": "Additional Effort", "amount": attacker_extra_modifier})
	## Weapon Length (house rule, per the request): "if your weapon is
	## longer than your opponent's, they suffer a penalty of -10 to hit
	## (attacks only) you as you find it easier to keep them at bay."
	## Compares the DEFENDER's weapon reach against the ATTACKER's own —
	## the attacker is the one being kept at bay here, so the penalty
	## lands on their attack roll, not the defender's.
	## In-fighter (p.138): "you suffer no penalty for fighting an
	## opponent with a longer weapon" — waives exactly this house-rule
	## penalty for the attacker holding the Talent. (The book's other
	## clause, "+10 to hit when using the optional In-Fighting rules,"
	## has no live trigger to hook into: the only code that ever set the
	## "In-Fighting" Condition — a Close the Distance action — was
	## removed in v0.2.405, so that Condition is never actually applied
	## to anyone in this project any more. Not fabricating a new trigger
	## for it here; this Talent's real, reachable effect is the
	## reach-penalty waiver below.)
	var reach_rank := {"Personal": 0, "Very Short": 1, "Short": 2, "Average": 3, "Long": 4, "Very Long": 5, "Massive": 6}
	var defender_weapon_for_length := defender.get_equipped_weapon()
	if defender_weapon_for_length != null and not defender_weapon_for_length.is_ranged and not attacker.has_talent("In-fighter"):
		var attacker_reach_rank: int = reach_rank.get(weapon.reach, 3)
		var defender_reach_rank: int = reach_rank.get(defender_weapon_for_length.reach, 3)
		if defender_reach_rank > attacker_reach_rank:
			attacker_mod -= 10
			attacker_mod_breakdown.append({"name": "Kept at bay (shorter weapon)", "amount": -10})
	## Imprecise (Flaw, p.297): "-1 SL when using the weapon to attack."
	## Applied as an extra_sl_breakdown entry (like a Talent bonus) so it
	## only actually reduces the total on a genuine success, matching
	## how every other SL modifier in this project already behaves.
	##
	## Per the request: Furious Assault (and any future caller with its
	## own SL bonus that isn't a weapon quality) is folded in here via
	## `attacker_extra_sl_breakdown` rather than a flat roll-target
	## modifier — this is the same mechanism Imprecise/Precise already
	## use, so it correctly propagates into hit/Damage/Critical Wound
	## triggers instead of just shifting the number needed to hit.
	## Weapon Groups (p.296): "you cannot use any of [the weapon's]
	## Qualities" when attacking with a weapon Group you have no
	## Advances in — Flaws (Imprecise included) are always suffered
	## regardless, so only Precise/Wrap/Dangerous/Impale/Fast/Damaging/
	## Impact below read off this effective, training-filtered list.
	var attacker_effective_qualities := attacker.get_effective_weapon_qualities(weapon)
	var attacker_extra_sl: Array = attacker_extra_sl_breakdown.duplicate()
	if weapon.qualities.has("Imprecise"):
		attacker_extra_sl.append({"name": "Imprecise", "amount": -1})
	## Precise (p.297): "+1 SL to any successful Test when attacking
	## with this weapon."
	if attacker_effective_qualities.has("Precise"):
		attacker_extra_sl.append({"name": "Precise", "amount": 1})

	var defender_mod := defender_extra_modifier
	var defender_mod_breakdown: Array = []
	if defender_extra_modifier != 0:
		defender_mod_breakdown.append({"name": "Additional Effort", "amount": defender_extra_modifier})
	## Distracting (p.339): "-20 to all Tests for all Characters within
	## 5 yards of it." This project doesn't track yardage — melee
	## combat is the one place two combatants are unambiguously within
	## that range of each other, so the penalty applies to whichever
	## side is NOT the one with the Trait (a creature isn't distracted
	## by its own presence). Implemented once, centrally, here — every
	## current and future monster with this Trait gets the real effect
	## automatically, on both their own attacks and their defense.
	if defender.has_creature_trait("Distracting") and not attacker.has_creature_trait("Distracting"):
		attacker_mod -= 20
		attacker_mod_breakdown.append({"name": "Distracting (%s)" % defender.character_name, "amount": -20})
	if attacker.has_creature_trait("Distracting") and not defender.has_creature_trait("Distracting"):
		defender_mod -= 20
		defender_mod_breakdown.append({"name": "Distracting (%s)" % attacker.character_name, "amount": -20})
	## Size (p.341): "If smaller: it gains a bonus of +10 to hit."
	## Applied whenever the attacker is smaller than the defender by
	## any number of steps — the book's own wording isn't "per step"
	## here (unlike the Damage multiplier below, which explicitly is).
	if attacker.get_size_step() < defender.get_size_step():
		attacker_mod += 10
		attacker_mod_breakdown.append({"name": "Smaller than target (Size)", "amount": 10})
	## Master Condition List (p.167-169): several Conditions grant "any
	## opponent trying to strike you in Melee Combat gains a bonus of
	## +X to hit you" — implemented as an equivalent penalty to the
	## defender's own roll, since a bonus to the attacker's side of an
	## Opposed Test and an equal penalty to the defender's side produce
	## the same net result here.
	## Real bug fix: this used to apply a flat -10 regardless of how many
	## Blinded stacks the defender had. Unlike Deafened (which explicitly
	## says its to-hit bonus "does not increase with multiple Deafened
	## Conditions," p.168), Blinded's own entry has no such carve-out, so
	## it follows the general Multiple Conditions stacking rule (p.167)
	## like the Condition's own Test penalty already does.
	var blinded_stacks: int = int(defender.conditions.get("Blinded", 0))
	if blinded_stacks > 0:
		defender_mod -= 10 * blinded_stacks
		defender_mod_breakdown.append({"name": "Blinded (opponent easier to hit)", "amount": -10 * blinded_stacks})
	if defender.conditions.has("Prone"):
		defender_mod -= 20
		defender_mod_breakdown.append({"name": "Prone (opponent easier to hit)", "amount": -20})
	## Surprised (p.169): "cannot defend yourself in opposed Tests" — a
	## full block, not merely a penalty (unlike Blinded/Prone above). The
	## -20 breakdown line is kept for the roll card's own readability, but
	## defender_forced_roll is also pinned to a guaranteed failure (100)
	## below so the defender genuinely cannot succeed, matching the
	## book's wording rather than just making it unlikely. Only overrides
	## the roll when the caller hasn't already forced a specific one
	## (defender_forced_roll == -1, the normal case) — a caller-forced
	## roll (used by this project's own smoke tests) is left alone.
	if defender.conditions.has("Surprised"):
		defender_mod -= 20
		defender_mod_breakdown.append({"name": "Surprised (cannot defend)", "amount": -20})
		if defender_forced_roll == -1:
			defender_forced_roll = 100
	## Deafened's real bonus only applies "from the flank or rear" —
	## this project doesn't track facing/positioning, so applying it
	## unconditionally would overstate the effect; left un-applied here
	## as a documented simplification rather than guessed at.
	## Wrap (p.298): "Melee Tests opposing an attack from a Wrap weapon
	## suffer a penalty of -1 SL."
	var defender_extra_sl: Array = defender_extra_sl_breakdown.duplicate()
	if attacker_effective_qualities.has("Wrap"):
		defender_extra_sl.append({"name": "Wrap", "amount": -1})

	result.attacker_test = TestResolver.resolve_skill_test(attacker, melee_skill, weapon.skill_group, attacker_mod, attacker_mod_breakdown, attacker_forced_roll, attacker_extra_sl, attacker_extra_scopes)
	## Dangerous (p.298): "Any failed test including a 9 on either 10s
	## or units die results in a Fumble" — broader than the normal
	## "failed + double" fumble trigger, so re-checked here after the
	## roll if the weapon has this Flaw. A Flaw, so always suffered —
	## but read off the effective list anyway (not the weapon's raw
	## `qualities`) since Flail (p.296) dynamically adds it there for
	## an unskilled wielder even when the weapon's own data doesn't.
	if attacker_effective_qualities.has("Dangerous") and not result.attacker_test.success:
		var roll := result.attacker_test.roll
		if (roll / 10) % 10 == 9 or roll % 10 == 9:
			result.attacker_test.is_fumble = true
	## Impale (p.298): "Impale weapons cause a Critical Hit on any
	## number divisible by 10... as well as on doubles" — broader than
	## the normal doubles-only Critical trigger.
	if attacker_effective_qualities.has("Impale") and result.attacker_test.success and _is_impale_trigger(result.attacker_test.roll):
		result.attacker_test.is_critical = true

	## Practical (p.301, general Item Quality — see ItemQualityRules):
	## "A failed Test using this item receives +1 SL" — softens (never
	## erases) a failure, so this only ever moves success_levels toward
	## 0, never up to or past it.
	if ItemQualityRules.has(weapon.item_qualities, "Practical") and not result.attacker_test.success:
		result.attacker_test.success_levels = mini(-1, result.attacker_test.success_levels + 1)
	## Shoddy (p.302, general Item Flaw): "breaks when used in any failed
	## Test rolling a double." Checked against the raw roll's own digits
	## directly (not is_fumble, which Dangerous above can already have
	## widened to cover non-double failed-on-a-9 rolls) — Shoddy is
	## specifically about doubles. Routed through destroy_weapon() so a
	## Durable+Shoddy combination (unusual, but the Crafting order screen
	## doesn't forbid mixing them) still gets its saving throw, and
	## Unbreakable/indestructible weapons stay exempt the same way Trap
	## Blade's own outright-destroy already respects them.
	if not result.attacker_test.success and result.attacker_test.roll % 11 == 0 and ItemQualityRules.has(weapon.item_flaws, "Shoddy") and not weapon.qualities.has("Unbreakable") and not weapon.is_indestructible:
		result.attacker_weapon_broke_shoddy = attacker.destroy_weapon(weapon.weapon_name)

	var def_skill := defense_skill if defense_skill != null else melee_skill
	var def_spec := defense_specialisation
	if defense_skill == null and defense_specialisation == "":
		var defender_weapon := defender.get_equipped_weapon()
		def_spec = defender_weapon.skill_group if defender_weapon != null else "Basic"
	## Fast (p.297): "all Melee Tests to defend against Fast weapons
	## suffer a penalty of -10 if your opponent is using a weapon
	## without the Fast Quality." Slow (p.296): opponents gain "+1 SL
	## to any Test to defend against your attacks." Both Qualities, so
	## both read off each side's own effective (training-filtered) list.
	if attacker_effective_qualities.has("Fast"):
		var defender_weapon_for_fast := defender.get_equipped_weapon()
		if defender_weapon_for_fast == null or not defender.get_effective_weapon_qualities(defender_weapon_for_fast).has("Fast"):
			defender_mod -= 10
			defender_mod_breakdown.append({"name": "vs Fast weapon", "amount": -10})
	if attacker_effective_qualities.has("Slow"):
		defender_extra_sl.append({"name": "vs Slow weapon", "amount": 1})
	## Defending Against Big Creatures (p.341): "You suffer a penalty
	## of –2 SL for each step larger your opponent is when using Melee
	## to defend an Opposed Test." Specifically Melee (Parry) — the
	## book's own example is "dodge a Giant swinging a tree, not parry
	## it" — so this is checked only when def_skill is genuinely Melee,
	## not Dodge.
	if def_skill != null and def_skill.skill_name == "Melee":
		var defender_size_diff := attacker.get_size_step() - defender.get_size_step()
		if defender_size_diff >= 1:
			defender_extra_sl.append({"name": "Parrying a larger opponent (Size)", "amount": -2 * defender_size_diff})
	result.defender_test = TestResolver.resolve_skill_test(defender, def_skill, def_spec, defender_mod, defender_mod_breakdown, defender_forced_roll, defender_extra_sl)
	result.defender_shield_ap_bonus = defender_shield_ap_bonus

	## Per the request: the defender's own doubles matter now too, same
	## as an attacker's. A fumbled Parry/Dodge attempt is its own real
	## mishap (checked here, unconditionally — the defender genuinely
	## botched the attempt regardless of how the opposed comparison
	## below happens to shake out).
	if result.defender_test.is_fumble:
		result.defender_fumble = roll_oops()

	## Opposed Test: highest SL wins; on an SL tie, the higher tested
	## target number wins; only when SL AND target number are BOTH tied
	## is it a genuine tie where nothing happens for either side (p.153/
	## 158 — corrected per an explicit follow-up request: a plain `>=`
	## tiebreak used to default every double-tie to the attacker, which
	## was wrong. TestResolver.resolve_opposed() is now the single source
	## of truth for this comparison, shared with Social Combat).
	var opposed := TestResolver.resolve_opposed(result.attacker_test, result.defender_test)
	var attacker_wins: bool = opposed.attacker_wins
	result.is_true_tie = opposed.is_true_tie

	## An exceptionally good Parry — doubles, and the parry genuinely
	## held (the attacker did not win this exchange, and it wasn't a dead
	## -even tie either — that's nothing happening, not a held Parry) —
	## triggers the riposte below, applied once the win/lose branch has
	## resolved.
	var critical_parry_counter_earned: bool = result.defender_test.is_critical and not attacker_wins and not result.is_true_tie

	if result.is_true_tie:
		## A genuine tie: the exchange cancels out completely. No hit, no
		## Winning Advantage for the attacker, and none of the defender's
		## own "successfully defended" consequences (Reversal, Riposte,
		## Critical Parry counter) fire either — this is a dead-even
		## bounce, not a successful Parry/Dodge.
		pass
	elif attacker_wins:
		## Winning (Up in Arms p.133): "If you win an Opposed Test you
		## initiated" — the attacker initiated this one, so they gain it.
		## Beneath Notice (p.133): "characters with a higher Status Tier
		## than you gain no Advantage for striking or wounding you in
		## combat" — checked here rather than skipped further down, since
		## Winning is granted for winning the Opposed Test itself, before
		## Damage is even calculated. Distract (p.142): also skipped while
		## the attacker themselves can generate no Advantage.
		if not attacker.is_advantage_denied() and not (defender.has_talent("Beneath Notice") and attacker.get_status_ordinal() > defender.get_status_ordinal()):
			pool.gain_winning(attacker.allegiance)
		result.hit = true
		## Damage uses the NET SL of the opposed test (p.159), not the
		## attacker's raw SL alone — see _apply_hit's doc comment.
		var net_sl := result.attacker_test.success_levels - result.defender_test.success_levels
		var units_die := result.attacker_test.roll % 10
		## Size (p.341): "its weapons gain the Damaging Quality if the
		## creature is one step larger, and Impact if two steps or
		## more larger." Combined with the weapon's own real Damaging/
		## Impact qualities via local flags, rather than mutating the
		## shared WeaponDefinition resource itself (which would wrongly
		## persist the bonus onto every future attack with that same
		## weapon, including against differently-sized targets).
		var size_diff := attacker.get_size_step() - defender.get_size_step()
		var weapon_has_damaging := attacker_effective_qualities.has("Damaging")
		var weapon_has_impact := attacker_effective_qualities.has("Impact")
		var size_grants_damaging: bool = size_diff >= 1
		var size_grants_impact: bool = size_diff >= 2
		## Tiring (p.297, a Flaw paired with Impact/Damaging on some
		## weapons): "you only gain the benefit of the Impact and
		## Damaging Weapon Traits on a Turn you Charge" — only ever
		## gates the WEAPON's own qualities, not a grant from Size,
		## since Tiring is a flaw of the weapon's own design, not the
		## wielder's build.
		var weapon_qualities_active: bool = not weapon.qualities.has("Tiring") or is_charge
		var has_damaging: bool = (weapon_has_damaging and weapon_qualities_active) or size_grants_damaging
		var has_impact: bool = (weapon_has_impact and weapon_qualities_active) or size_grants_impact
		## Damaging (p.297): "can use the higher score from either the
		## units die or the SL to determine the Damage caused."
		if has_damaging:
			net_sl = max(net_sl, units_die)
		## Impact (p.298): "add the result of the units die of the
		## attack roll to any Damage caused."
		var impact_bonus := 0
		if has_impact:
			impact_bonus = units_die
		_apply_hit(result, attacker, defender, weapon, result.attacker_test, net_sl, impact_bonus, blast_candidates, forced_hit_location)
	else:
		if defender_uses_reversal and defender.has_talent("Reversal"):
			## Reversal (p.140): take 1 Advantage from the opposing pool
			## instead of the normal +1 Winning gain; no Damage is dealt.
			## Distract (p.142): a Distracted defender still gets to
			## Reverse (it isn't an Advantage-GENERATING roll, it's a
			## steal from the opponent's pool), but the actual +1 credit
			## to their own side is still an Advantage gain, so it's
			## skipped the same as every other self-attributed gain while
			## denied.
			if pool.get_pool(attacker.allegiance) > 0:
				pool.spend(attacker.allegiance, 1)
				if not defender.is_advantage_denied():
					pool.add(defender.allegiance, 1)
			result.reversal_used = true
		## Reversal (p.140): "If you do this, you do not cause any
		## Damage, even if it is your Turn in the Round" — an explicit,
		## unconditional ban on this exchange also dealing damage some
		## other way. Both the Talent-based Riposte counter and the
		## doubles-triggered Critical Parry counter below deal damage on
		## the exact same "defender won the Opposed Melee Test" branch
		## this Reversal check just ran in, so both are skipped entirely
		## once Reversal has actually fired (a real double-dip bug this
		## project used to have — a defender with both Reversal AND
		## Riposte/a Critical Parry, using Reversal, still got the
		## damage on top of the Advantage steal).
		if not result.reversal_used:
			## Riposte (Talent, distinct from the doubles-triggered counter-
			## strike below, per the follow-up request's own clarification):
			## on a successful Parry, deal your own weapon's normal damage
			## to the attacker — usable up to your own Riposte rank times
			## per Round (defender.riposte_uses_this_round, reset each
			## Round by CombatEncounter._on_round_end). Triggers on any
			## successful Parry (specifically Melee, not Dodge, matching
			## the Talent's own wording — "parrying" isn't dodging), only
			## for characters who actually have the Talent and haven't
			## already used up their own rank's worth this Round. Per this
			## second follow-up request: only works when defending with a
			## Fast weapon — a quick enough weapon to land the counter
			## before the attacker recovers, not any weapon at all.
			if def_skill != null and def_skill.skill_name == "Melee" and defender.has_talent("Riposte"):
				var riposte_rank := defender.get_talent_rank("Riposte")
				if defender.riposte_uses_this_round < riposte_rank:
					var defender_weapon := defender.get_equipped_weapon()
					if defender_weapon != null and defender.get_effective_weapon_qualities(defender_weapon).has("Fast"):
						defender.riposte_uses_this_round += 1
						result.riposte_talent_triggered = true
						## Per the request ("dont apply this to riposte"): Riposte's
						## counter-strike always uses the plain reversed roll — no
						## Careful Strike involvement, even if the defender has it.
						var riposte_loc_roll := reverse_roll(result.defender_test.roll)
						result.riposte_talent_hit_location = get_hit_location(riposte_loc_roll)
						var riposte_weapon_damage := defender_weapon.get_weapon_damage(defender)
						var riposte_total_damage := riposte_weapon_damage + result.defender_test.success_levels
						## Robust (see its own comment further down, at the main
						## hit's soak calculation): the attacker being riposted
						## against is the one taking this Damage, so it's their
						## own Robust rank that reduces it here, same as any
						## other incoming hit.
						var riposte_soak := attacker.get_characteristic_bonus("toughness") + attacker.get_armour_points(result.riposte_talent_hit_location) + attacker.get_talent_rank("Robust")
						result.riposte_talent_wounds_dealt = max(1, riposte_total_damage - riposte_soak)
						attacker.take_wounds(result.riposte_talent_wounds_dealt)
			## A successful defence does NOT grant the defender Winning
			## Advantage — they didn't initiate this Opposed Test, and the
			## book's Winning trigger explicitly requires that. Simply
			## avoiding a hit isn't one of the five listed ways to gain
			## Advantage under Up in Arms.
			##
			## Per the follow-up request: an exceptionally good (critical)
			## Parry deals no Advantage at all — instead, it's a real
			## riposte, landing a genuine counter-hit (a flat 1 Wound, since
			## this represents a fast, precise counter-thrust rather than a
			## full weapon swing) plus a full Critical Wound roll directly
			## on the attacker who just tried to land the original blow.
			if critical_parry_counter_earned:
				## Trap Blade (p.298): "When Parrying an attack from a Bladed
				## weapon with a Trap Blade weapon, on a Critical, instead of
				## the normal effects of a Critical Parry, you may make an
				## Opposed Strength Test... if you win, your opponent's weapon
				## is disarmed; if you win with an Astounding success (6+ SL),
				## it is broken instead" — replaces the normal doubles counter-
				## hit below entirely for this specific matchup, rather than
				## stacking with it.
				var defender_parry_weapon := defender.get_equipped_weapon()
				var defender_has_trap_blade := defender_parry_weapon != null and defender.get_effective_weapon_qualities(defender_parry_weapon).has("Trap Blade")
				if defender_has_trap_blade and weapon.is_bladed:
					result.trap_blade_triggered = true
					result.trap_blade_test = TestResolver.resolve_characteristic_test(defender, "strength")
					result.trap_blade_opposing_test = TestResolver.resolve_characteristic_test(attacker, "strength")
					## Same corrected tie-break as the main Opposed Test above: a
					## true tie (same SL AND same target) here means the Trap
					## Blade Strength contest is a wash — no disarm.
					var trap_opposed := TestResolver.resolve_opposed(result.trap_blade_test, result.trap_blade_opposing_test)
					var defender_wins := trap_opposed.attacker_wins
					var defender_sl := result.trap_blade_test.success_levels
					if defender_wins:
						result.trap_blade_disarmed = true
						if attacker.equipped_weapon == weapon.weapon_name:
							attacker.equipped_weapon = ""
						elif attacker.equipped_offhand == weapon.weapon_name:
							attacker.equipped_offhand = ""
						## Unbreakable (p.298): "This weapon cannot be broken by
						## abilities that would normally destroy a weapon" —
						## exempts it from the Astounding Success outright-
						## destruction below, same as an is_indestructible item.
						if defender_sl >= 6 and not weapon.qualities.has("Unbreakable") and not weapon.is_indestructible:
							## destroy_weapon() now also rolls a Durable saving
							## throw (p.301) when the weapon has that Quality —
							## use its real return value rather than assuming
							## success, so a Durable weapon can survive here too.
							result.trap_blade_weapon_destroyed = attacker.destroy_weapon(weapon.weapon_name)
				else:
					result.critical_parry_counter_triggered = true
					result.critical_parry_counter_wounds_dealt = 1
					var attacker_wounds_before := attacker.wounds_current
					attacker.take_wounds(1)
					var cw := _roll_critical_wound(attacker_wounds_before, 1)
					result.critical_parry_counter_wound_location = cw["location"]
					result.critical_parry_counter_wound_entry = cw["entry"]
					result.critical_parry_counter_wound_roll = cw["roll"]
					result.critical_parry_counter_target_already_down = attacker_wounds_before <= 0
					if cw["entry"].get("wounds") is int:
						var counter_extra: int = int(cw["entry"]["wounds"])
						result.critical_parry_counter_extra_wounds = counter_extra
						attacker.take_wounds(counter_extra)
					elif cw["entry"].get("wounds") == "Death":
						result.critical_parry_counter_causes_death = true
		if result.attacker_test.is_fumble:
			result.fumble = roll_oops()

	return result

## Resolves one ranged attack. Unopposed by default — success alone
## determines a hit (p.158). If the target is Engaged and you want them
## to be able to Oppose with a Melee Skill instead, resolve that
## separately before calling this (not automated here).
##
## `pool`: see `resolve_melee_attack` above (required). A ranged hit is
## unopposed, so under the group system it counts as "Outmaneuver"
## (p.133) rather than "Winning" — still +1, capped at 1 per attack.
static func resolve_ranged_attack(attacker: Character, defender: Character,
		weapon: WeaponDefinition, pool: GroupAdvantagePool, modifier: int = 0, forced_roll: int = -1,
		blast_candidates: Array[Character] = [], forced_hit_location: String = "",
		attacker_extra_scopes: Array = [], round_number: int = -1) -> AttackResult:
	var result := AttackResult.new()
	var ranged_skill: SkillDefinition = GameData.skill_db.find_by_name("Ranged")

	if defender.conditions.has("Surprised"):
		pool.gain_surprise(attacker.allegiance)

	## See resolve_melee_attack's comment: Advantage never automatically
	## adds to a roll under Up in Arms. `modifier` here is purely
	## whatever the caller passes explicitly (Additional Effort).
	var attacker_mod := modifier
	var attacker_mod_breakdown: Array = []
	if modifier != 0:
		attacker_mod_breakdown.append({"name": "Additional Effort", "amount": modifier})
	## Weapon Groups (p.296): Qualities are lost when firing a weapon
	## Group the attacker has no Advances in (Crossbow/Throwing via
	## Ballistic Skill, Engineering via Ranged (Blackpowder), etc. —
	## see Character.get_effective_weapon_qualities()). Whether the
	## attack can even be ATTEMPTED at all is the caller's own
	## responsibility (Character.can_use_ranged_weapon()) — this
	## resolver assumes it's already been allowed, same as it's never
	## checked ammo/range either.
	var attacker_effective_qualities := attacker.get_effective_weapon_qualities(weapon, round_number)
	## Accurate (p.296): "Gain a bonus of +10 to any Test when firing
	## this weapon."
	if attacker_effective_qualities.has("Accurate"):
		attacker_mod += 10
		attacker_mod_breakdown.append({"name": "Accurate", "amount": 10})
	## Size (Shooting): real bug fix — this used to reuse melee's own
	## relative "+10 if you're smaller than the target" rule, which is
	## the wrong Size rule for a ranged Test. Shooting's own Size
	## modifier isn't relative to the attacker at all: "it is far
	## easier to hit a barn door than an apple," a flat bonus/penalty
	## from the TARGET's Size category alone, Tiny -30 through
	## Monstrous +60 (see RANGED_SIZE_MODIFIERS below). Only added to
	## the breakdown when non-zero, so the overwhelmingly common
	## Average-vs-Average case doesn't clutter the roll card with a
	## "+0" line.
	var target_size_mod: int = RANGED_SIZE_MODIFIERS[defender.get_size_step()]
	if target_size_mod != 0:
		attacker_mod += target_size_mod
		attacker_mod_breakdown.append({"name": "Target Size (%s)" % Character.SIZE_STEPS[defender.get_size_step()], "amount": target_size_mod})

	result.attacker_test = TestResolver.resolve_skill_test(attacker, ranged_skill, weapon.skill_group, attacker_mod, attacker_mod_breakdown, forced_roll, [], attacker_extra_scopes)
	if attacker_effective_qualities.has("Dangerous") and not result.attacker_test.success:
		var roll := result.attacker_test.roll
		if (roll / 10) % 10 == 9 or roll % 10 == 9:
			result.attacker_test.is_fumble = true
	if attacker_effective_qualities.has("Impale") and result.attacker_test.success and _is_impale_trigger(result.attacker_test.roll):
		result.attacker_test.is_critical = true

	## Practical / Shoddy (p.301-302, general Item Qualities/Flaws — see
	## ItemQualityRules and the matching comment in resolve_melee_attack
	## above, which this mirrors exactly for a ranged weapon).
	if ItemQualityRules.has(weapon.item_qualities, "Practical") and not result.attacker_test.success:
		result.attacker_test.success_levels = mini(-1, result.attacker_test.success_levels + 1)
	if not result.attacker_test.success and result.attacker_test.roll % 11 == 0 and ItemQualityRules.has(weapon.item_flaws, "Shoddy") and not weapon.qualities.has("Unbreakable") and not weapon.is_indestructible:
		result.attacker_weapon_broke_shoddy = attacker.destroy_weapon(weapon.weapon_name)

	## Blackpowder (p.297): fires whether or not the shot itself hits —
	## the report of a gun going off is what rattles the target, not the
	## ball actually connecting. A Quality, so gated by training the same
	## as everything else read off attacker_effective_qualities.
	if attacker_effective_qualities.has("Blackpowder"):
		var cool_skill: SkillDefinition = GameData.skill_db.find_by_name("Cool")
		result.blackpowder_cool_test = TestResolver.resolve_skill_test(defender, cool_skill, "", 20, [{"name": "Blackpowder weapon fired at you", "amount": 20}])
		if not result.blackpowder_cool_test.success:
			defender.add_condition("Broken", 1)
			result.blackpowder_broken_applied = true

	if result.attacker_test.success:
		## Beneath Notice (p.133) / Distract (p.142) — see the matching
		## comments on the melee Winning gain above.
		if not attacker.is_advantage_denied() and not (defender.has_talent("Beneath Notice") and attacker.get_status_ordinal() > defender.get_status_ordinal()):
			pool.gain_outmaneuver(attacker.allegiance)
		result.hit = true
		_apply_hit(result, attacker, defender, weapon, result.attacker_test, -999999, 0, blast_candidates, forced_hit_location)
	else:
		if result.attacker_test.is_fumble:
			result.fumble = roll_oops()

	return result

## Flee (Up in Arms, p.140) — the free attack you provoke by moving away
## from an engaged opponent without successfully Disengaging first (core
## rulebook Disengaging, p.165, replaced under the Group Advantage
## system by Disengage/spend_flee_from_harm): "your opponent immediately
## gains 1 Advantage and may attempt 1 free attack. The free attack is
## an unopposed Melee Test using whatever weapon is currently held...
## As you are throwing caution to the wind, your opponent gains +20 to
## hit you. If you are hit, your opponent gains +1 Advantage." (The
## fleeing character's own Cool Test against gaining Broken on a hit is
## the caller's responsibility — see _resolve_free_attack — since that's
## a Condition/UI concern, not something this resolver owns.)
static func resolve_free_melee_attack(attacker: Character, defender: Character,
		weapon: WeaponDefinition, pool: GroupAdvantagePool, modifier: int = 0, forced_roll: int = -1,
		blast_candidates: Array[Character] = []) -> AttackResult:
	var result := AttackResult.new()
	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")

	## Distract (p.142) gates every Advantage gain attributable to the
	## DISTRACTED character's own actions -- here that's `attacker` (the
	## one PUNISHING the flee with a free attack, despite the confusing
	## parameter name; `defender` is the character actually fleeing).
	if defender.conditions.has("Surprised") and not attacker.is_advantage_denied():
		pool.gain_surprise(attacker.allegiance)

	## "Your opponent immediately gains 1 Advantage" — unconditional,
	## before the free attack is even rolled.
	if not attacker.is_advantage_denied():
		pool.add(attacker.allegiance, 1)

	var attacker_mod := modifier + 20
	var attacker_mod_breakdown: Array = [{"name": "Undefended (Fleeing)", "amount": 20}]
	if modifier != 0:
		attacker_mod_breakdown.append({"name": "Additional Effort", "amount": modifier})
	## Size (p.341): same "+10 to hit a larger target" rule as a normal
	## Opposed melee attack.
	if attacker.get_size_step() < defender.get_size_step():
		attacker_mod += 10
		attacker_mod_breakdown.append({"name": "Smaller than target (Size)", "amount": 10})

	## Weapon Groups (p.296): same effective-quality/Flaw treatment as
	## every other attack path — a Flee free attack is still just a
	## Melee Test with this weapon.
	var attacker_effective_qualities := attacker.get_effective_weapon_qualities(weapon)
	result.attacker_test = TestResolver.resolve_skill_test(attacker, melee_skill, weapon.skill_group, attacker_mod, attacker_mod_breakdown, forced_roll)
	if attacker_effective_qualities.has("Dangerous") and not result.attacker_test.success:
		var roll := result.attacker_test.roll
		if (roll / 10) % 10 == 9 or roll % 10 == 9:
			result.attacker_test.is_fumble = true
	if attacker_effective_qualities.has("Impale") and result.attacker_test.success and _is_impale_trigger(result.attacker_test.roll):
		result.attacker_test.is_critical = true

	if result.attacker_test.success:
		## "If you are hit, your opponent gains +1 Advantage" — on top
		## of the flat 1 Advantage already granted above just for
		## fleeing while engaged.
		if not attacker.is_advantage_denied():
			pool.add(attacker.allegiance, 1)
		result.hit = true
		_apply_hit(result, attacker, defender, weapon, result.attacker_test, -999999, 0, blast_candidates)
	else:
		if result.attacker_test.is_fumble:
			result.fumble = roll_oops()

	return result

## Beat Blade (Up in Arms, p.140): for your Action, before making an
## attack, you may Beat Blade instead — an unopposed Melee Test against
## the target. On success, the OPPOSING side's Advantage Pool loses 1,
## and a further 1 if you scored 6+ SL. Has no effect if the target is
## unarmed or larger than you (checked by the caller — Size isn't
## modelled yet, so only the unarmed case is checked here).
static func resolve_beat_blade(actor: Character, opponent: Character,
		weapon: WeaponDefinition, pool: GroupAdvantagePool) -> AttackResult:
	var result := AttackResult.new()
	if opponent.get_equipped_weapon() == null:
		result.fumble = {"text": "Beat Blade has no effect — the opponent is unarmed."}
		return result

	var melee_skill: SkillDefinition = GameData.skill_db.find_by_name("Melee")
	var mod := pool.get_pool(actor.allegiance) * 10
	result.attacker_test = TestResolver.resolve_skill_test(actor, melee_skill, weapon.skill_group, mod)

	if result.attacker_test.success:
		result.hit = true
		var loss := 2 if result.attacker_test.success_levels >= 6 else 1
		pool.spend(opponent.allegiance, min(loss, pool.get_pool(opponent.allegiance)))
	elif result.attacker_test.is_fumble:
		result.fumble = roll_oops()

	return result

## Shared "determine location / damage / apply" steps for a confirmed hit.
## `damage_sl` is the Success Level actually used for Damage. For an
## unopposed attack (ranged) this is just the attacker's own rolled SL
## (the default). For an OPPOSED attack (melee), the book is explicit
## (p.159, "Summary: Damage = Weapon Damage + SL" under "Success Levels
## in Combat" / "3: Determine Damage" — "Take the SL of your Opposed
## Test"): this must be the NET SL of the opposed test (winner's SL
## minus loser's SL), not the attacker's own raw SL from their side of
## it alone. A real bug used the attacker's raw SL for melee too, which
## overstated Damage whenever the defender also scored some SL on their
## losing Test.
## Up in Arms "An Alternative Approach to Injury" (p.81-86): a fresh
## d100 for location (NOT the reversed-digit method used for a normal
## hit's own location), then a fresh d100 looked up on that location's
## own table. If the victim was already at 0 Wounds *before* this hit,
## add +10 to the effect roll for every Wound this hit dealt beyond
## what was needed to bring them to 0 (p.81's own worked example) —
## pushes the roll into the table's higher, nastier bands. Extracted
## out of _apply_hit so the same real rolling logic can also drive the
## Critical Parry riposte below, rather than a second, drifting copy.
static func _roll_critical_wound(wounds_before_hit: int, wounds_dealt: int) -> Dictionary:
	var loc_roll := Dice.d100()
	var location := get_hit_location(loc_roll)
	var effect_roll := Dice.d100()
	var overkill_bonus := 0
	if wounds_before_hit <= 0:
		overkill_bonus = wounds_dealt * 10
	elif wounds_dealt > wounds_before_hit:
		overkill_bonus = (wounds_dealt - wounds_before_hit) * 10
	effect_roll += overkill_bonus
	var entry: Dictionary = GameData.critical_wound_db.lookup(location, effect_roll)
	return {"location": location, "entry": entry, "roll": effect_roll, "overkill_bonus": overkill_bonus}

## `blast_candidates` (Blast (Rating), p.297): every OTHER living
## character on the target's side, passed in by the caller (this
## resolver has no concept of "sides" beyond the two combatants already
## involved) — splashed for SL+Weapon Damage with no soak if `weapon`
## has the Blast Quality. `defender` itself is skipped automatically if
## it's ever accidentally included.
## `forced_hit_location`, when non-empty, skips the reversed-dice
## determination entirely and uses this location instead — used both by
## Deadeye Shot (p.136, "instead of reversing the dice... you may pick a
## location," chosen up front via the UI before the shot is even fired)
## and by a redo of this same hit after the player accepts a Careful
## Strike relocation offered in the combat log (see
## field_encounter_screen.gd's _offer_careful_strike_choice and its
## call site in _on_player_attack).
static func _apply_hit(result: AttackResult, attacker: Character, defender: Character,
		weapon: WeaponDefinition, hitting_test: TestResolver.TestResult, damage_sl: int = -999999, impact_bonus: int = 0,
		blast_candidates: Array[Character] = [], forced_hit_location: String = "") -> void:
	if damage_sl == -999999:
		damage_sl = hitting_test.success_levels
	if forced_hit_location != "":
		result.hit_location = forced_hit_location
	else:
		result.hit_location = get_hit_location(reverse_roll(hitting_test.roll))

	## Weapon Groups (p.296): computed once here and reused below for
	## every Quality this shared "apply a confirmed hit" step cares
	## about (Penetrating, Entangle, Distract, Blast) — an untrained
	## attacker loses all of them, same as everywhere else in this file.
	var effective_qualities := attacker.get_effective_weapon_qualities(weapon)

	var weapon_damage := weapon.get_weapon_damage(attacker)
	result.weapon_damage = weapon_damage

	## Ammunition (p.294): the attacker's currently-loaded ammo (see
	## Character.get_active_ammo_item) can add its own flat Damage bonus
	## on top of the weapon's own (e.g. Elf Arrow, Lead Bullet, Bullet
	## and Powder's "+1" entries) — null (and so 0 here) for melee/
	## Throwing weapons, which have no ammo concept at all.
	var ammo_item := attacker.get_active_ammo_item(weapon)
	if ammo_item != null:
		result.ammo_damage_bonus = ammo_item.ammo_damage_bonus
		result.ammo_name = ammo_item.item_name

	## Strike Mighty Blow (melee) / Accurate Shot (ranged), p.145/136:
	## "You deal your level of Strike Mighty Blow in extra Damage with
	## melee weapons" / "You deal your Accurate Shot level in extra
	## Damage with all ranged weapons" — a flat per-rank Damage bonus,
	## not a Success Level bonus, which is why these are handled here
	## rather than through the generic Talent SL system.
	var talent_name := "Accurate Shot" if weapon.is_ranged else "Strike Mighty Blow"
	var talent_rank := attacker.get_talent_rank(talent_name)
	var talent_sources: Array[String] = []
	if talent_rank > 0:
		result.talent_damage_bonus += talent_rank
		talent_sources.append(talent_name)

	## Dirty Fighting, p.? ("You have been taught all the dirty tricks of
	## unarmed combat. You may choose to cause an extra +1 Damage for each
	## level in Dirty Fighting with any successful Melee (Brawling) hit"):
	## same flat per-rank Damage bonus as Strike Mighty Blow above, but
	## gated on the weapon actually being a Brawling one (Fists,
	## Knuckledusters — see WeaponDefinition.skill_group) rather than on
	## melee-vs-ranged. The book frames it as an optional choice ("you may
	## choose to") rather than an automatic bonus like Strike Mighty
	## Blow's own wording — but this project has no mechanical downside
	## for using it (the Talent's own "Note: using this Talent will be
	## seen as cheating in any formal bout" is flavour text; there's no
	## formal-bout/duel-judging system here to react to it), so there's
	## never a real reason to decline extra free Damage. Applied
	## automatically here, same as Strike Mighty Blow, rather than adding
	## a UI toggle whose "no" branch would never be a rational click.
	## Stacks additively with Strike Mighty Blow if the attacker somehow
	## has both and is using a Brawling weapon — both are genuinely
	## separate Talents per the book, not alternate ranks of the same one.
	if not weapon.is_ranged and weapon.skill_group == "Brawling":
		var dirty_fighting_rank := attacker.get_talent_rank("Dirty Fighting")
		if dirty_fighting_rank > 0:
			result.talent_damage_bonus += dirty_fighting_rank
			talent_sources.append("Dirty Fighting")
	result.talent_damage_source = " + ".join(talent_sources)

	## Active timed buffs (e.g. Sigmar's Fiery Hammer's "+Fellowship
	## Bonus Damage") — real, time-limited effects the attacker gained
	## from a Blessing/Miracle/Spell, not a permanent Talent bonus.
	var active_buff_bonus := attacker.get_active_damage_bonus(weapon)
	result.impact_bonus = impact_bonus
	result.active_buff_bonus = active_buff_bonus
	result.damage_sl_used = damage_sl
	result.damage = weapon_damage + damage_sl + impact_bonus + result.talent_damage_bonus + active_buff_bonus + result.ammo_damage_bonus
	## Size (p.341): "It multiplies any Damage caused by the number of
	## steps larger it is (so, 2 steps=×2, 3 steps=×3, and so on); this
	## multiplication is calculated after all modifiers are applied."
	## 1 step larger stays ×1 (no change) — the book's own example
	## table starts the multiplier at 2 steps.
	var attacker_size_diff := attacker.get_size_step() - defender.get_size_step()
	if attacker_size_diff >= 2:
		result.damage *= attacker_size_diff
		result.size_damage_multiplier = attacker_size_diff
	## Penetrating (p.297): "Non-metal APs are ignored, and the first
	## point of all other armour is ignored" — a real, separate AP
	## calculation, not just a flat reduction to the summed total. A
	## Quality, so lost when the attacker isn't trained in this
	## weapon's Group (p.296) — Undamaging just below stays a Flaw,
	## always suffered, so it's still read off the weapon's raw list.
	##
	## Partial (p.300) and Weakpoints (p.300) are per-piece Armour Flaws
	## (an even to-hit roll or any Critical ignores a Partial piece's AP
	## entirely; an Impale weapon scoring a Critical ignores a Weakpoints
	## piece's AP) — folded into the same attack-aware calculation here
	## via get_armour_points_for_attack(), rather than the plain
	## get_armour_points()/get_armour_points_penetrating() every other
	## caller (AI target-weighting, riposte soak, etc.) still uses.
	var armour_ap := defender.get_armour_points_for_attack(result.hit_location, hitting_test.roll, hitting_test.is_critical, effective_qualities.has("Penetrating"), effective_qualities.has("Impale"))
	## Robust (p.109, Max: Toughness Bonus): "You reduce all incoming
	## Damage by an extra +1 per time you have taken the Robust Talent,
	## even if the Damage cannot normally be reduced, but still suffer a
	## minimum of 1 Wound from any Damage source." A flat extra point of
	## soak per rank, folded into the same `soak` both branches below
	## already build from Toughness Bonus + Armour Points + shield.
	var robust_rank := defender.get_talent_rank("Robust")
	result.soak = defender.get_characteristic_bonus("toughness") + armour_ap + result.defender_shield_ap_bonus + robust_rank
	## Undamaging (p.297): "All APs are doubled against Undamaging
	## weapons. Further, you do not automatically inflict a minimum of
	## 1 Wound on a successful hit." Per an explicit follow-up ("no
	## Undamaging should override Robust"): Undamaging's OWN removal of
	## the minimum-1-Wound floor wins here — Robust still adds its flat
	## soak same as always (so it can still fully absorb an Undamaging
	## hit down to 0), it just doesn't force a Wound through the way it
	## does against a normal weapon's own always-on floor below.
	if weapon.qualities.has("Undamaging"):
		result.soak = defender.get_characteristic_bonus("toughness") + armour_ap * 2 + result.defender_shield_ap_bonus + robust_rank
		result.wounds_dealt = max(0, result.damage - result.soak)
	else:
		result.wounds_dealt = max(1, result.damage - result.soak)

	## Distract (p.298): "Rather than dealing Damage, a hit from this
	## weapon knocks the target back" — this project has no positional
	## model to move the target with, so the whole effect is represented
	## as dealing zero Damage/Wounds, overriding the normal (minimum-1)
	## Wound calculation above entirely.
	if effective_qualities.has("Distract"):
		result.wounds_dealt = 0
		result.distract_applied = true

	## Entangle (p.298): "If you hit with this weapon, the target gains
	## the Entangled Condition" — applied regardless of how much Damage
	## the hit itself did (even a Distract+Entangle combination, however
	## unlikely in the current data, should still entangle).
	if effective_qualities.has("Entangle"):
		defender.add_condition("Entangled")
		result.entangle_applied = true

	result.was_critical = hitting_test.is_critical
	var wounds_before_hit := defender.wounds_current
	## Wound loss is ALWAYS the normally-computed amount, clamped at 0 by
	## take_wounds() itself — a Critical Hit does not mean "wipe all
	## remaining Wounds regardless of how small the actual hit was". A
	## real bug used to do exactly that (any Critical, even a 1-point
	## graze, instantly zeroed the defender's Wounds), which is not what
	## the book says (p.159/172): scoring a Critical, or dealing more
	## Wounds than the defender has left ("overkill"), triggers an
	## ADDITIONAL Critical Wound roll on top of the normal Wound loss —
	## it doesn't replace or inflate that Wound loss.
	defender.take_wounds(result.wounds_dealt)

	## Blast (Rating) (p.297): "Everyone within Rating yards of the
	## target... suffers the same Damage" — this project doesn't track
	## yards, so simplified to "every other living character on the
	## target's side" (the caller's own roster, passed in as
	## `blast_candidates`). Each splash hit uses the same SL+Weapon
	## Damage as the primary hit but no soak at all (no Toughness Bonus,
	## no Armour Points) — a blast doesn't care what you're wearing.
	var weapon_has_blast := effective_qualities.has("Blast")
	if not weapon_has_blast:
		for q in effective_qualities:
			if q.begins_with("Blast "):
				weapon_has_blast = true
				break
	if weapon_has_blast:
		for other in blast_candidates:
			if other == null or other == defender or other.wounds_current <= 0:
				continue
			var splash_wounds: int = max(0, result.damage)
			other.take_wounds(splash_wounds)
			result.blast_hits.append({"character": other, "wounds_dealt": splash_wounds, "hit_location": result.hit_location})

	## Critical Wound triggers (p.172): scoring a Critical Hit, or this
	## hit dealing more Wounds than the defender had left ("overkill").
	## A Distracted hit deals no Wounds at all, so it can never trigger
	## a Critical Wound via overkill — but a Critical roll that also
	## happened to be Distract still counts as a Critical Hit per RAW.
	var overkill := result.wounds_dealt > wounds_before_hit
	result.caused_critical_wound = result.was_critical or overkill

	## Shoddy (p.302, general Item Flaw — see ItemQualityRules): "Shoddy
	## armour breaks if any Critical Hit is sustained to a Hit Location
	## it protects." Specifically a genuine Critical Hit
	## (result.was_critical — the roll itself triggered a Critical, via
	## doubles or Impale), not the broader caused_critical_wound just
	## above (which also fires on plain overkill against a nearly-dead
	## target — that's not "a Critical Hit" in the book's own sense).
	## Routed through destroy_armour_piece() so Durable+Shoddy armour
	## still gets its saving throw, same as the weapon side.
	if result.was_critical:
		for piece in defender.get_equipped_armour_at_location(result.hit_location):
			if ItemQualityRules.has(piece.item_flaws, "Shoddy") and defender.destroy_armour_piece(piece.armour_name):
				result.shoddy_armour_broken.append(piece.armour_name)

	## Impenetrable (p.300): "This location cannot suffer a Critical
	## Wound from an odd double (11/33/55/77/99)" — a precision-hit
	## defense, not overkill protection, so only suppresses a Critical
	## Wound that was specifically triggered by rolling one of those five
	## odd doubles; a Critical Wound triggered by overkill (dealing more
	## Wounds than the defender had left) still goes through untouched.
	var roll_tens := (hitting_test.roll / 10) % 10
	var roll_units := hitting_test.roll % 10
	var critical_from_odd_double := hitting_test.is_critical and roll_tens == roll_units and roll_tens % 2 == 1
	if result.caused_critical_wound and critical_from_odd_double and defender.has_impenetrable_armour_at(result.hit_location):
		result.caused_critical_wound = false

	if result.caused_critical_wound:
		var cw := _roll_critical_wound(wounds_before_hit, result.wounds_dealt)
		result.critical_wound_location = cw["location"]
		result.critical_wound_entry = cw["entry"]
		result.critical_wound_roll = cw["roll"]
		result.critical_wound_overkill_bonus = cw["overkill_bonus"]
		result.critical_wound_target_already_down = wounds_before_hit <= 0
		var entry: Dictionary = result.critical_wound_entry
		## The table's own "Wounds" column is extra, unavoidable Wound
		## loss on top of the normal hit — Critical Deflection (p.299)
		## only lets you avoid the Condition/text effects, never this.
		if entry.get("wounds") is int:
			var extra: int = entry["wounds"]
			result.critical_wound_extra_wounds = extra
			defender.take_wounds(extra)
		elif entry.get("wounds") == "Death":
			result.critical_wound_causes_death = true

	## Prone specifically follows from reaching 0 Wounds (p.172: "if you
	## lose all of your Wounds... you gain the Prone Condition"), not
	## from a Critical Wound occurring on its own — different Critical
	## Table results have different effects, and this project doesn't
	## model that table yet, so it shouldn't assume Prone every time.
	if defender.wounds_current <= 0:
		defender.add_condition("Prone")
