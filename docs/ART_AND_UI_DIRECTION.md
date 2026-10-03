# Art & UI Direction

Binding spec for all visual work. Any new UI element in Milestone 2 gets built against this
rather than invented at the keyboard.

---

## 1. Thesis

**The screen should read as "I am carrying something I could lose."**

Every other visual decision is subordinate. This is not a medieval RPG that happens to have
loot — it is a game about walking out of a building with something in your hands. If a
design choice doesn't serve that feeling, cut it.

---

## 2. The two tests everything must pass

Blueprint §91 and §92, restated as gates. Run both before merging any visual change.

**Screenshot test.** Freeze a random frame. A stranger must identify, in under three
seconds: who they are, what's dangerous, what's valuable. If walls, floor, enemies and loot
have equal visual weight, the scene has failed and needs contrast, not detail.

**No-sound test.** Mute. Can you tell a hit landed, damage was taken, an enemy is winding up,
loot is rare, extraction succeeded? Sound may *reinforce* these. It may never be the only
carrier. This matters more than usual on Roblox, where a large share of players are muted.

---

## 3. Palette

Named values. Use these, not approximations.

| Token | Hex | Use |
|---|---|---|
| `stone` | `#5A5A63` | Dungeon walls, neutral architecture |
| `pitch` | `#2E2E36` | Floors, shadow, the base the whole scene sits on |
| `ember` | `#FF9B3D` | Torchlight, warmth, safety-adjacent |
| `gold` | `#FFCD50` | Currency, banked value, weapon upgrades |
| `bleed` | `#FF6B4A` | **Unsecured loot, danger, wanted level** |
| `escape` | `#5CE08C` | Extraction, safety achieved |

The critical pair is `gold` vs `bleed`. Banked gold is warm and calm. Unsecured gold is hot
and unstable. A player must be able to tell at a glance which state they're in — that single
distinction carries the game's whole tension.

**Per-kingdom identity** (blueprint §36) — each kingdom shifts the neutrals, never the
functional colours. `bleed` means "at risk" in Frosthold exactly as it does in the dungeon.

- Dungeon: `stone` / `pitch` / `ember`
- Greenvale: mossy stone, warm torch, green canopy
- Blackstone: charcoal with furnace orange
- Frosthold: white-blue with cold shadow

Colour aids navigation. It never carries information alone (§40) — always pair with icon,
shape, or text.

---

## 4. Rarity language

Blueprint §13 is explicit that colour alone is insufficient. Rarity reads in this order:

1. **Silhouette** — a Rare has a different outline than a Common. Recognisable as a black
   shape at 40px.
2. **Material** — plain plastic → forged metal → glow → emissive
3. **Motion** — Epic+ has idle motion; Mythic has a trail
4. **Colour** — last, as confirmation, never as the sole signal

Practical floor for the graybox: a Rare must differ from a Common in **size or proportion**,
not just tint. A longer blade, a heavier head, a wider guard.

---

## 5. Typography

Verify each name against `Enum.Font` in Studio before committing — availability changes.

- **Display** (objectives, ESCAPED, rarity reveals): a medieval-leaning serif — `Grenze` is
  the first candidate. Used with restraint: objective banner, screen moments, rank-ups.
  Nowhere else.
- **Body / HUD** (gold, weapon, prompts): `Gotham` family. Chosen for legibility on a phone
  at arm's length, not for character.
- **Numerals** (damage, currency): `GothamBlack`. Numbers must punch.

Two faces total. A third is scope creep.

**Mobile floor:** no text below 18px effective. Objective text at 30px+. If it isn't readable
on a 5-inch screen in daylight, it isn't shipped.

---

## 6. HUD layout — Milestone 2 target

```
┌──────────────────────────────────────────────────────┐
│              STEAL THE CAPTAIN'S KEY                 │  ← objective, display face
│                                                       │
│  Gold 1,240                            [ WANTED III ] │  ← gold calm, wanted in `bleed`
│  ▓▓▓▓▓ UNSECURED 482                                  │  ← the signature element
│                                                       │
│                                                       │
│                                                       │
│  RARE IN: 2 CAPTAIN KILLS                             │  ← always-visible near goal
│                                                       │
│  Rusty Sword · 17 DMG                        (ATTACK) │
└──────────────────────────────────────────────────────┘
```

Answers the four §80 questions in reading order: what to do, what I have, am I in danger,
what am I close to.

### The signature element: the unsecured bar

This is the one place to spend boldness. Unsecured gold is not a number — it is a **bar that
fills as you loot and empties the instant you die.**

- Fills left-to-right in `bleed` as you collect
- Pulses faster as the total climbs — the pulse *is* the tension
- On extraction: sweeps left-to-right and recolours to `gold`, then merges into the Gold
  counter. The player watches risk become safety.
- On death: drains in one hard frame. No animation, no easing. Gone.

That single element communicates the entire game. Everything around it stays quiet.

### Rules

- Maximum six persistent HUD elements. Blueprint §38: avoid fourteen permanent buttons.
- Touch targets ≥ 44px.
- Reward presentation scales with value (§81): small = popup, rare = short reveal, Mythic =
  dramatic but skippable. Never trap the player inside an animation.

---

## 7. Interface vocabulary

Blueprint §79 — one verb per action, everywhere. A control says what happens, and the
resulting message uses the same word.

| Use | Never |
|---|---|
| STEAL | Acquire, Obtain |
| BREAK | Destroy, Smash |
| OPEN | Unlock (unless a key is genuinely required) |
| ESCAPE | Extract, Exfil, Leave |
| UPGRADE | Enhance, Improve |
| RAID | Attack, Assault |
| CLAIM | Redeem, Collect |

Failure states give direction, not mood. `NEED 46 MORE GOLD` — not `Insufficient funds`.
`YOU NEED THE CELLBLOCK KEY` — not `Access denied`.

---

## 8. Asset pipeline — who makes what

Ordered by cost. Exhaust each tier before the next.

**Tier 0 — Procedural Luau (free, immediate).**
Everything in `WorldBuilder` today. Can go much further: cell bars, a hinged chest, torch
sconces, banners, a Captain with a distinct silhouette. **This is the correct tier for all of
Milestone 2.** Blocky is not a problem; unreadable is.

**Tier 1 — Roblox Creator Store.**
Free and paid models. Fastest route to non-blocky props. Check licence terms, and check
poly count against the mobile budget — a beautiful asset that tanks frame rate on a low-end
Android is a net loss (§41).

**Tier 2 — Studio's built-in generation tools.**
Roblox ships AI material and asset tooling. Verify current capability and terms in Studio
directly; it moves fast. Useful for materials and props, not for hero assets.

**Tier 3 — A human artist.**
Required for: the Captain, each boss, signature weapons, the icon, and thumbnails. These are
the assets that carry the game's identity, and they're the ones worth paying for. Brief them
with sections 1–5 of this document.

### Priority order when art budget appears

1. **Enemy readability** — a player must know what's attacking and when to dodge
2. **Weapon silhouettes** — the whole progression fantasy is visible in your hands
3. **The extraction pad** — the most emotionally loaded object in the game
4. **The hideout and weapon rack** — where progress is displayed
5. Environment detail — last, and it is genuinely last

### Scale

Slightly oversized doors, weapons, treasure, bosses, interactables (§36). Most players are on
small screens; important objects need presence.

---

## 9. Deferred

Not now, and saying so explicitly so it doesn't creep in:

- Thumbnails and icon — Milestone 3, and they get their own A/B plan (§55)
- Cosmetics, transmog, trails — Milestone 3+
- Per-kingdom palettes beyond the dungeon — when those kingdoms exist
- Custom animations — after M2 systems are proven

---

## 10. Before merging any visual change

- [ ] Screenshot test passes
- [ ] No-sound test passes
- [ ] Readable on a 5-inch screen
- [ ] No information carried by colour alone
- [ ] Uses the palette tokens, no new hex values
- [ ] Uses the existing verb vocabulary
- [ ] Frame rate unchanged on a low-end device
