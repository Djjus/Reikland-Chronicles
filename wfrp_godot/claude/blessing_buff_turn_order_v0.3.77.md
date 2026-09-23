# v0.3.77 — Blessing/buff counter moved into the Turn Order panel

## The request

"move blessing buff count to same place as the Light spell counter and
show it all the time its active." The user's own screenshots showed
"Active: Blessing of Battle (3)" sitting up near Round/Advantage, in a
different spot from "💡 Aes's Light — 32" pinned in the Turn Order panel
below.

## The fix

That "Active: X (Y)" line (built in `_render_status()`) is gone. Every
active timed buff (`add_timed_buff()` — Blessing prayers, Cordelia's
Apothecary draughts, even a fumble's own Off-Balance penalty; see
`Character.active_buffs`'s own comment for the full shape) now gets
exactly the same pinned-row treatment the Light spell already had, in
`_render_turn_order_panel()`, right next to it: one row per buff, reading
"✨ CharacterName's BuffName — N", counting down and disappearing on
expiry the same way a Light row does.

This was also a genuine bug fix, not just a cosmetic move. The old
"Active:" line only ever read `player.active_buffs` — and `player` gets
reassigned all over `field_encounter_screen.gd` to whoever's turn or kill
is currently being attributed (loot/XP attribution, free attacks, and so
on). A Blessing cast on a different party member than whoever `player`
last happened to point to simply never showed at all. The new version
loops every combatant in `encounter.turn_order` — same as the Light
loop it now sits beside — so a buff on ANY combatant, ally or adversary,
shows for as long as it's genuinely active, regardless of whose turn it
is or who `player` currently points to. That's the literal "show it all
the time it's active" half of the request.

## Verification

New `blessing_buff_turn_order_test.gd` (10 checks) drives a real
FieldEncounter exploration fixture with two party members, casts
Blessing of Battle on the SECOND member (deliberately not `player`) to
reproduce the old bug's exact condition, and confirms: the pinned row
shows up anyway; the old "Active:" text is gone from the status label;
a buff on `player` themselves still shows too (not a regression on the
one case the old code did handle); two simultaneous buffs on two
different characters each get their own row; and the row disappears once
the buff's own Round-tick countdown reaches 0, same as Light's own
expiry.

Also verified visually — a real rendered screenshot (same headless
Xvfb + software-GL technique used for every other visual feature this
project has shipped) reproducing the user's own reported scene: Aes with
both an active Light and an active Blessing of Battle, both now showing
side by side in the Turn Order panel as "💡 Aes's Light — 32" and
"✨ Aes's Blessing of Battle — 3".

Full regression sweep: 453 checks across 19 suites — all passed, 0
failures.
