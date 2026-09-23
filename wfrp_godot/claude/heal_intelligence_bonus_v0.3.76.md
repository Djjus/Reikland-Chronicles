# v0.3.76 — Heal now adds Intelligence Bonus, not just SL

## The report

The user's own attached roll card showed the bug directly: "Fredi Heal
Elrohir", "Roll vs Target: 31 vs 70", "SL: +4", "Healed 4 Wound(s) (now
9/13)". SL +4 producing exactly 4 healed Wounds meant the Intelligence
Bonus half of Heal's own formula was missing entirely.

## The fix

Heal (p.138): "the patient recovers a number of Wounds equal to your
Intelligence Bonus plus the SL." `_apply_heal_outcome()` in
`field_encounter_screen.gd` previously computed healed Wounds as
`max(1, test.success_levels)` alone. Now it also adds the healer's own
`get_characteristic_bonus("intelligence")` on top — "your" in the book's
own wording is the person making the Heal Test (the player doing the
healing), not the patient receiving it, so this reads from `player`
regardless of whether the target is an ally or the player healing
themselves.

The pre-existing `max(1, ...)` floor on the SL half is untouched — a
bare SL-0 success still recovers at least 1 Wound from that term alone,
exactly as before; the Intelligence Bonus is purely additive on top. The
roll card's own "Healed N Wound(s)" line is unchanged in shape, with a
new second line breaking the total down as "(SL X + Intelligence Bonus
Y)" whenever the Bonus is actually nonzero, so the math stays visible
rather than folded into one opaque number.

Bleeding/Poisoned side-effect clearing (a Heal Test doing double duty per
their own p.167/169 rules) still reduces by `max(1, SL)` alone, unrelated
to Wounds healed — that wasn't part of the report and wasn't touched.

## Verification

New `heal_intelligence_bonus_test.gd` (6 checks) drives
`_apply_heal_outcome()` directly against a real FieldEncounter fixture:
a healer with Int 44 (Bonus 4) treating an ally with a deliberately
different Int 20 (Bonus 2) confirms the HEALER's own Bonus is what's
used, not the patient's; a case near `wounds_max` confirms the added
Bonus still respects the healing cap; a failed Test still heals nothing;
Heal Self also gets the Bonus; and a 0-Bonus healer still floors at the
pre-existing minimum of 1 Wound on a bare SL-0 success.

Also verified visually — a real rendered roll card, screenshotted
headless via the same Xvfb + software-GL technique established for the
condition markers — reproducing the user's own exact reported numbers
(SL +4, same Roll-vs-Target shape) with a healer's Intelligence Bonus of
3: the card now reads "Healed 7 Wound(s)" with "(SL 4 + Intelligence
Bonus 3)" underneath, instead of the old flat 4.

Full regression sweep: 443 checks across 18 suites — all passed, 0
failures.
