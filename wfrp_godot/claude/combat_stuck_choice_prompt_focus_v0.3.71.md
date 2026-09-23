# v0.3.71 — "combat getting stuck sometimes on creature's turn"

## The report

Two screenshots of a dungeon combat: Turn Order highlighted a monster
(Wight) as the current combatant, Round 4, but the bottom prompt panel
looked empty with nothing to click, and the Combat Log's newest entries
were a duplicated "Wight is too far away to strike in melee" line. From
the player's side this reads as a genuine freeze — nothing to click,
nothing happening, no way to advance the turn.

## What I found

Reading every button-menu builder in `field_encounter_screen.gd` and
checking every call site of `_auto_focus_default_button()` (the helper
that gives a menu's default button real keyboard focus the instant it
appears) turned up three, and only three, player-facing choice prompts
that never call it:

- `_handle_critical_wound_on_player()` — the Accept/Deflect prompt shown
  when a monster's hit lands a Critical Wound on the player-controlled
  character.
- `_handle_fatal_moment()` — the "spend a Fate Point or accept your
  fate" prompt, offered when a Critical Wound (or accumulated wounds)
  would otherwise kill the character.
- `_on_spend_resolve()` — the "spend Resolve" menu (ignore Critical
  Wound penalties, or shed a Condition).

Every other choice menu in this ~16,000-line file — Attack, Charge,
Parry/Dodge, Overcast, Bonus Action, Continue prompts, and more — calls
`_auto_focus_default_button()` right after building its buttons. These
three didn't, for a real historical reason: they used to share the
`awaiting_player_target` flag with ordinary attack-target selection, and
an earlier fix (see `awaiting_critical_wound_choice`/
`awaiting_fatal_moment_choice`'s own code comments) gave them dedicated
flags and made `Enter` deliberately do nothing while they're open, to
stop a stale target selection from launching a second attack mid-prompt.
That fix never restored a working keyboard default — Enter still does
nothing (intentionally), and `Space` (this project's own documented way
to accept a choice menu) only handles two unrelated flags in
`_unhandled_input`, so with no button focused, **neither key did
anything at all** while one of these three prompts was open.

A monster landing a Critical Wound on whoever the player is controlling
is exactly a "creature's turn" event, and it's a common one — armour
piercing hits, high Success Levels, and Undead like the Wight in the
screenshot are all reasons this can come up in an ordinary fight. A
player who presses Space (as the game itself tells them to) and sees
nothing happen has every reason to think the game has locked up, even
though clicking the right button on screen would have worked the whole
time.

I can't be 100% certain this exact bug produced the exact frame in the
screenshot — the visible log lines are consistent with an ordinary
earlier melee-range miss, not directly with one of these three prompts —
but this is a real, confirmed gap in the same "turn looks stuck" family,
worth fixing regardless of whether it's the exact frame caught on
camera.

## The fix

All three prompts now call `_auto_focus_default_button()` after building
their buttons, via the same `_active_primary_hotkey_button` convention
every other menu in the file already uses. Each one's default is
deliberately the safe, no-resource-spent option rather than whichever
button happened to be built first:

- Critical Wound: defaults to **Accept the wound as dealt** (not
  Deflect, which spends a point of armour AP).
- Fatal Moment: defaults to **Accept your fate** (not either
  Fate-Point-spending option) when Fate Points are available, or its
  only button when they aren't.
- Spend Resolve: defaults to **Cancel** (not whichever real option — e.g.
  "Ignore Critical Wound modifiers" — was built first).

This means Space now works immediately on all three, through Godot's own
built-in `ui_accept` binding — no changes needed to `_unhandled_input`
at all. `Enter` stays exactly as deliberately unbound as before (it's
been stripped from `ui_accept` project-wide, see `_setup_wasd_navigation`),
so this can't reopen the old crash these flags were split out to fix in
the first place; it only adds a focused default that Space's existing,
untouched binding can now actually reach. Because each default is the
safe/no-op choice, an accidental Space press can never burn a Fate
Point, spend Resolve, or lose the chance to Deflect — worst case, it
just confirms "yes, I accept this" a little faster than clicking would
have.

## Regression sweep

New test: `scripts/core/choice_prompt_keyboard_focus_test.gd` — 29
checks across all three prompts (and the two real branches of Fatal
Moment: with and without Fate Points), confirming the expected default
button is genuinely focused, carries the `[Space]` hint, and that the
safe option (never the resource-spending one) is what's focused.

Full sweep run in a clean, freshly-imported copy of the project: 286
checks across `ChoicePromptKeyboardFocusTest`, `CriticalWoundDeflectInputTest`,
`CriticalWoundDeflectReproTest`, `EndTurnWasdFocusNoTargetTest`,
`DungeonLootEquipableTest`, `CraftingTest`, and `ShopGridTest` (the
suites most likely to interact with this area of the file) — all passed,
0 failures.

## Known limitation

This does not conclusively prove the exact screenshot's freeze was
caused by one of these three prompts specifically — the visible Combat
Log content in the screenshot is also consistent with an ordinary,
non-buggy melee-range miss from earlier in the round. If "combat gets
stuck on a creature's turn" still happens after this build, the next
most useful thing to send is what's actually showing in the bottom
prompt panel at the moment it looks stuck (even "nothing" vs "a button
that doesn't respond" narrows it a lot), plus whether Wounds recently
dropped for the character shown as DEFENDER right before it happened.
