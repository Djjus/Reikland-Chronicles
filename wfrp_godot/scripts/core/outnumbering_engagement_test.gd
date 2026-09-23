extends RefCounted
class_name OutnumberingEngagementTest
## Regression test for the real bug reported by the user: "make sure that
## engaging in combat is only triggered when combatants hit each other,
## just standing next to a combatant does not mean your engaged. Right now
## it assumes that and it leads to incorrect outnumbering modifiers... if a
## 2nd defender join another defending who is currently outnumbered 2vs1,
## from the moment the 2nd defender hit one of the attackers these 4
## combatants all now count as 1vs1, until one side looses a member after
## which the other side will outnumber them 2v1 — scales up to 3vs1 too,"
## plus the related follow-up: "it also leads to moving away from enemies
## that you have not hit (nor they hit you) leads to a fleeing free hit
## which is not correct."
##
## Exercises CombatEncounter's Engagement/Outnumbering primitives directly
## (mark_melee_engaged / get_outnumbering_bonus / is_engaged_with /
## is_currently_engaged), with hand-built `physical_cluster` arrays
## standing in for field_encounter_screen.gd's live _local_melee_cluster()
## battle-grid BFS (that adjacency walk itself is plain geometry with no
## rules logic in it — this test focuses on the actual rules math it
## feeds, which is where the real bug lived).

static func _make_character(name: String, side: String) -> Character:
	var human := GameData.find_race("Human")
	var soldier := GameData.find_career("Soldier")
	var c := Character.new()
	c.character_name = name
	c.race = human
	c.career = soldier
	c.current_tier = 1
	c.characteristics = CharacteristicSet.new()
	c.recompute_max_wounds()
	c.allegiance = side
	return c

static func run_test() -> bool:
	var checks: Array = []

	var encounter := CombatEncounter.new()
	var a1 := _make_character("Attacker1", "adversary")
	var a2 := _make_character("Attacker2", "adversary")
	var d1 := _make_character("Defender1", "ally")
	var d2 := _make_character("Defender2", "ally")
	encounter.turn_order = [a1, a2, d1, d2]

	## --- Case 1: nobody has fought anyone yet. Mere existence/adjacency
	## (a physical_cluster containing all four, as if they were standing
	## right next to each other) grants NO bonus to anyone, and no pair
	## reads as Engaged — the actual bug being fixed.
	var full_cluster: Array = [a1, a2, d1, d2]
	checks.append(["Case 1: nobody has attacked yet -> a1 gets no Outnumbering bonus from mere adjacency", encounter.get_outnumbering_bonus(a1, full_cluster) == 0])
	checks.append(["Case 1: ...nor does d1", encounter.get_outnumbering_bonus(d1, full_cluster) == 0])
	checks.append(["Case 1: a1/d1 do NOT read as Engaged with each other despite being adjacent", not encounter.is_engaged_with(a1, d1)])
	checks.append(["Case 1: is_currently_engaged is false for everyone before any real hit", not encounter.is_currently_engaged(a1) and not encounter.is_currently_engaged(d1)])

	## --- Case 2: a1 lands the first real hit on d1. A lone attacker with
	## only one qualifying ally on their side still gets nothing (mine < 2)
	## even though they personally started the fight.
	encounter.mark_melee_engaged(a1, d1)
	checks.append(["Case 2: a1 alone (mine=1) still gets no bonus after its own first hit", encounter.get_outnumbering_bonus(a1, full_cluster) == 0])
	checks.append(["Case 2: a1/d1 now correctly read as genuinely Engaged with each other", encounter.is_engaged_with(a1, d1)])
	checks.append(["Case 2: is_currently_engaged is now true for both a1 and d1", encounter.is_currently_engaged(a1) and encounter.is_currently_engaged(d1)])
	checks.append(["Case 2: a2/d2, who haven't swung at anyone, still read as not engaged with anyone", not encounter.is_currently_engaged(a2) and not encounter.is_currently_engaged(d2)])

	## --- Case 3: a2 joins in, landing a hit on the SAME defender d1 —
	## the adversary side is now 2-strong in this cluster: 2 vs 1,
	## +20 to hit for both a1 and a2.
	encounter.mark_melee_engaged(a2, d1)
	checks.append(["Case 3: a1 now gets +20 (2 attackers vs 1 defender, 2:1)", encounter.get_outnumbering_bonus(a1, full_cluster) == 20])
	checks.append(["Case 3: a2 also gets +20 (the bonus applies to every qualifying attacker on the outnumbering side, not just whoever tipped the count)", encounter.get_outnumbering_bonus(a2, full_cluster) == 20])
	checks.append(["Case 3: d1, being outnumbered, gets nothing", encounter.get_outnumbering_bonus(d1, full_cluster) == 0])

	## --- Case 4: d2 is standing right there in the same physical cluster
	## but has NOT yet landed or received a hit — per the actual bug
	## report, mere adjacency must NOT fold them in. Still 2:1.
	checks.append(["Case 4: d2 merely standing adjacent (no hit yet) does NOT even the odds — still 2:1, a1 keeps +20", encounter.get_outnumbering_bonus(a1, full_cluster) == 20])
	checks.append(["Case 4: d2 itself is not yet Engaged with anyone", not encounter.is_currently_engaged(d2)])

	## --- Case 5: d2 lands its own real hit (on a2, say) — the exact
	## "2nd defender join another defender who is currently outnumbered
	## 2vs1... from the moment the 2nd defender hit one of the attackers
	## these 4 combatants all now count as 1vs1" scenario from the
	## request. The cluster is now a genuine 2v2 -> nobody gets a bonus.
	encounter.mark_melee_engaged(d2, a2)
	checks.append(["Case 5: once d2 lands its own hit, the fight evens to 2v2 -> a1 loses its +20", encounter.get_outnumbering_bonus(a1, full_cluster) == 0])
	checks.append(["Case 5: ...a2 also loses its +20", encounter.get_outnumbering_bonus(a2, full_cluster) == 0])
	checks.append(["Case 5: ...and neither defender gets a bonus either (still even, 2v2)", encounter.get_outnumbering_bonus(d1, full_cluster) == 0 and encounter.get_outnumbering_bonus(d2, full_cluster) == 0])
	checks.append(["Case 5: d2/a2 now read as genuinely Engaged with each other", encounter.is_engaged_with(d2, a2)])
	checks.append(["Case 5: but d2/a1 do NOT read as engaged with each other (they've never traded blows) -- the Flee-free-attack precision case", not encounter.is_engaged_with(d2, a1)])

	## --- Case 6: one side loses a member. Per the request, this must
	## correctly re-outnumber the survivors 2:1 REGARDLESS of which
	## specific individual died -- this is exactly the asymmetry bug
	## caught and fixed during design (a pairwise-only graph would give
	## different answers depending on which node died). Test BOTH
	## sub-cases against fresh, independently-built encounters so neither
	## death order can leak state between them.

	## 6a: d1 (a1's original opponent, NOT d2's) dies. The physical
	## cluster the screen recomputes fresh would now only contain the 3
	## survivors -- a1, a2, d2.
	var enc_a := CombatEncounter.new()
	var a1a := _make_character("A1", "adversary")
	var a2a := _make_character("A2", "adversary")
	var d1a := _make_character("D1", "ally")
	var d2a := _make_character("D2", "ally")
	enc_a.turn_order = [a1a, a2a, d1a, d2a]
	enc_a.mark_melee_engaged(a1a, d1a)
	enc_a.mark_melee_engaged(a2a, d1a)
	enc_a.mark_melee_engaged(d2a, a2a)
	d1a.wounds_current = 0
	var cluster_a: Array = [a1a, a2a, d2a]   ## d1a is dead, dropped from the live cluster
	checks.append(["Case 6a: d1 (a1's own original opponent) dies -> survivors are correctly 2:1 (a1/a2 vs d2), a1 gets +20", enc_a.get_outnumbering_bonus(a1a, cluster_a) == 20])
	checks.append(["Case 6a: ...a2 also gets +20", enc_a.get_outnumbering_bonus(a2a, cluster_a) == 20])
	checks.append(["Case 6a: ...the lone surviving defender d2 gets nothing, being outnumbered", enc_a.get_outnumbering_bonus(d2a, cluster_a) == 0])

	## 6b: the SAME scenario, but d2 (a2's original opponent, NOT a1's)
	## dies instead -- must give the identical shape of result (2:1 to
	## the adversaries), not an asymmetric outcome depending on which
	## specific pairing the casualty belonged to.
	var enc_b := CombatEncounter.new()
	var a1b := _make_character("A1", "adversary")
	var a2b := _make_character("A2", "adversary")
	var d1b := _make_character("D1", "ally")
	var d2b := _make_character("D2", "ally")
	enc_b.turn_order = [a1b, a2b, d1b, d2b]
	enc_b.mark_melee_engaged(a1b, d1b)
	enc_b.mark_melee_engaged(a2b, d1b)
	enc_b.mark_melee_engaged(d2b, a2b)
	d2b.wounds_current = 0
	var cluster_b: Array = [a1b, a2b, d1b]   ## d2b is dead, dropped from the live cluster
	checks.append(["Case 6b: d2 (a2's own original opponent) dies instead -> survivors are STILL correctly 2:1 (a1/a2 vs d1), a1 gets +20 (symmetry check -- the actual asymmetry bug caught during design)", enc_b.get_outnumbering_bonus(a1b, cluster_b) == 20])
	checks.append(["Case 6b: ...a2 also gets +20, even though a2's OWN specific opponent (d2) is the one who died, not a1's", enc_b.get_outnumbering_bonus(a2b, cluster_b) == 20])
	checks.append(["Case 6b: ...the lone surviving defender d1 gets nothing", enc_b.get_outnumbering_bonus(d1b, cluster_b) == 0])

	## --- Case 7: scaling to 3:1. Three adversaries who've each landed a
	## real hit vs one lone surviving defender -> +40.
	var enc_c := CombatEncounter.new()
	var x1 := _make_character("X1", "adversary")
	var x2 := _make_character("X2", "adversary")
	var x3 := _make_character("X3", "adversary")
	var y1 := _make_character("Y1", "ally")
	enc_c.turn_order = [x1, x2, x3, y1]
	enc_c.mark_melee_engaged(x1, y1)
	enc_c.mark_melee_engaged(x2, y1)
	enc_c.mark_melee_engaged(x3, y1)
	var cluster_c: Array = [x1, x2, x3, y1]
	checks.append(["Case 7: three attackers who've all genuinely landed a hit vs one defender -> +40 (3:1)", enc_c.get_outnumbering_bonus(x1, cluster_c) == 40])
	checks.append(["Case 7: applies to every qualifying attacker in the cluster", enc_c.get_outnumbering_bonus(x2, cluster_c) == 40 and enc_c.get_outnumbering_bonus(x3, cluster_c) == 40])

	## --- Case 8: pretend_engaged preview mode (used by the Attack
	## button's own target-number preview) -- a not-yet-engaged attacker
	## previewing their first swing against an already-2-strong opposing
	## cluster sees the SAME bonus they'd get the instant the real attack
	## lands, without actually mutating any state.
	var enc_d := CombatEncounter.new()
	var p1 := _make_character("P1", "ally")
	var e1 := _make_character("E1", "adversary")
	var e2 := _make_character("E2", "adversary")
	enc_d.turn_order = [p1, e1, e2]
	enc_d.mark_melee_engaged(e1, e2)   ## irrelevant same-side no-op state, just to prove pretend math isn't fooled by it
	var cluster_d: Array = [p1, e1, e2]
	checks.append(["Case 8: a genuinely not-yet-engaged previewer sees 0 with pretend_engaged=false", enc_d.get_outnumbering_bonus(p1, cluster_d, false) == 0])
	checks.append(["Case 8: is_currently_engaged is still false for p1 before any real attack lands", not enc_d.is_currently_engaged(p1)])

	var all_pass := true
	for chk in checks:
		var label: String = chk[0]
		var passed: bool = chk[1]
		print(("PASS  " if passed else "FAIL  ") + label)
		if not passed:
			all_pass = false
	print("RESULT (Outnumbering/Engagement): ", "ALL PASS" if all_pass else "SOME FAILED")
	return all_pass
