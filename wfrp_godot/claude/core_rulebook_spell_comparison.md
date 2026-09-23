# Core Rulebook vs. In-Game Spell List Comparison

Source: `Warhammer_Fantasy_Roleplay_PDF_version4.pdf` (your own copy, WFRP 4e folder), Magic chapter, pages 239–256. Compared against `data/spells/core_spells.tres`.

## Petty Spells

Book has **25**, game has **23**. Missing 2:

- **Dazzle** (CN0, Touch, Blinded stacking each round)
- **Sounds** (CN0, controllable illusory noises)

Every other Petty spell in the book is already in the game, name-for-name.

## Arcane Spells (generic list — usable by every Lore)

The book treats this as one shared list of options available to *any* Arcane caster regardless of which Lore they know. The game's flat "Arcane" list (all with `lore=""`) is actually this same generic list, not a Lore.

Book has **23**, game has **10**. Missing 13:

- Bridge (CN4)
- Chain Attack (CN6)
- Drop (CN1)
- Entangle (CN3)
- Fearsome (CN3)
- Flight (CN8)
- Magic Shield (CN4)
- Move Object (CN4)
- Mundane Aura (CN4)
- Push (CN6)
- Teleport (CN5)
- Terrifying (CN7)
- Ward (CN5)

## The 8 Lores of Colour Magic — not implemented at all

This is the big gap. The core rulebook builds Arcane magic around 8 Lores (Beasts, Death, Fire, Heavens, Metal, Life, Light, Shadows), each with its own 8 unique signature spells (64 total) plus a Lore-specific passive bonus (e.g. Fire spells add a Bleeding-adjacent Ablaze condition; Shadows spells ignore non-magical armour). The game's `SpellDefinition.lore` field exists but is empty on every single entry — there's no Lore structure at all right now, just the one flat "Arcane" bucket above.

Book spell counts per Lore (all currently absent from the game):

- **Lore of Beasts**: Amber Talons, Beast Form, Beast Master, Beast Tongue, Flock of Doom, Hunter's Hide, The Amber Spear, Wyssan's Wildform
- **Lore of Death**: Caress of Laniph, Dying Words, Purple Pall of Shyish, Sanctify, Scythe of Shyish, Soul Vortex, Steal Life, Swift Passing
- **Lore of Fire**: Aqshy's Aegis, Cauterise, Crown of Flame, Firewall, Flaming Hearts, Flaming Sword of Rhuin, Great Fires of U'Zhul, Purge
- **Lore of Heavens**: Cerulean Shield, Comet of Casandora, Fate's Fickle Fingers, First/Second/Third Portent of Amul, Starcrossed, T'Essla's Arc
- **Lore of Metal**: Crucible of Chamon, Enchant Weapon, Feather of Lead, Fool's Gold, Forge of Chamon, Glittering Robe, Mutable Metal, Transmutation of Chamon
- **Lore of Life**: Barkskin, Earthblood, Earthpool, Fat of the Land, Forest of Thorns, Lie of the Land, Lifebloom, Regenerate
- **Lore of Light**: Banishment, Blinding Light, Clarity of Thought, Daemonbane, Healing Light, Net of Amyntok, Phâ's Protection, Speed of Thought
- **Lore of Shadows**: Choking Shadows, Doppelganger, Mindslip, Miasma, Mystifying Illusion, Shadowsteed, Shadowstep, Shroud of Invisibility

## Witch Magic — also not implemented

Two shorter lists of 6 (all CN0 for Hedgecraft, higher CN for Witchcraft):

- **Lore of Hedgecraft**: Goodwill, Mirkride, Nepenthe, Nostrum, Part the Branches, Protective Charm
- **Lore of Witchcraft**: Blight, Creeping Menace, Curse of Crippling Pain, Curse of Ill-Fortune, Haunting Horror, The Evil Eye

## Dark Magic / Chaos Magic

Also present in the book (Daemonology, Necromancy, and the three Chaos god-lores of Nurgle/Slaanesh/Tzeentch) but these are GM/NPC villain spell lists, not normally player-facing, and lower priority for the game.

## Bottom line

- Petty list: 92% complete (23/25), just missing Dazzle and Sounds.
- Generic Arcane list: 43% complete (10/23).
- Lore-specific magic (the actual "point" of Arcane casters in 4e — 64 spells across 8 Lores) and Witch Magic (12 spells): 0% implemented. Every in-game Arcane spell is currently just a generic option, with no Lore identity or Lore passive bonuses attached.
