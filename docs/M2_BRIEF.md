# M2 Brief — Make the second run exist

**Do this only after `M1_BUGFIX_BRIEF.md` is merged and playtested.**

## The problem this milestone solves

Playtest 2026-08-11, developer self-test: *"First time, yes. Second time, no."*

Run 2 is byte-identical to run 1 — same guard, same chest, same guaranteed Rusty Sword,
same 50 gold, same exit. Nothing escalates, nothing varies, nothing is unfinished.

**This is not a content-volume problem.** Adding kingdoms would not change it. Run 2 needs a
*reason*, a *risk*, and a *variance*. That is what this milestone builds, and nothing else.

## Acceptance test (blueprint §105)

After extracting once, a tester who has been told nothing should be able to say:

> "If I go back in, I can kill the Captain and get better loot."

If a tester can't say that unprompted, this milestone is not done, regardless of how many
systems shipped.

---

## Scope — exactly these six things

### 1. Captain Bronn — the reason to return

The single highest-value item here. A named miniboss in the vault room.

- Spawns in the vault room, visible on run 1 but tuned so a Bent Spoon / Rusty Sword player
  will very likely lose. Losing to him is the intended run-1 experience.
- 3 telegraphed attacks minimum, one heavy swing with a long wind-up. Exaggerate the
  telegraph (§12).
- Calls one reinforcement at 50% HP.
- Guaranteed drop: `guard_sword`. Weighted chance at `captain_greatsword`.
- Health bar visible, name visible. He must read as "a thing you fight", not scenery.

Config goes in `EnemyConfig` per §111. Existing `captain_bronn` shape in the blueprint is the
starting point — do not invent new stat fields.

### 2. Rare drops — the variance

Without randomness every run pays out identically.

- Implement the `LootConfig.Tables` weighted roll for real, server-side (`LootService` already
  has `RollTable`; it is currently underused).
- Add `guard_sword` and `captain_greatsword` to `WeaponConfig` using the blueprint's §11
  baseline damage numbers.
- Add rarity presentation: the existing rarity colour path in `Notify` is enough for now, but
  a Rare+ drop needs a distinct, longer reveal (§81) — not the same toast as +8 gold.

**Keep the §115 first-run guarantees intact.** Run 1 must still be deterministic.

### 3. Wanted system — the voluntary risk

Levels 0–3 only for this milestone. Do not build all six.

- Wanted rises on kills and on opening the chest.
- Each level increases guard spawn rate and a gold multiplier.
- Display it in the HUD top bar (§80: "Am I in danger?").
- The player must be able to *choose* to push it. That choice is the entire point.

### 4. Inventory and equip

- Weapons are collected, not auto-equipped. Auto-equip-if-stronger goes away.
- A minimal equip UI: list owned weapons, tap to equip. Mobile-first, tap targets large
  (§38). No drag, no grid of tiny icons.
- Server validates that the player actually owns a weapon before equipping it.

### 5. Death loss, tuned

`DeathUnsecuredLossPercent` is currently `1.0` — the harshest possible setting, and §94 lists
it as a way to kill the game with young players.

- Drop it to `0.5`.
- Add the death screen's "Recover Loot" hook as a config flag, default off. Do not build the
  run-back loop yet.

### 6. The always-visible near-goal

At every moment the HUD should show one thing the player is close to (§30, §80). Cheapest
version that works:

- A pity meter toward a guaranteed Rare from Captain kills (§13).
- Show it as a bar with a number, e.g. `RARE IN: 2 CAPTAIN KILLS`.

### 7. Co-play hook — the missing signal (added 2026-10-03)

Built after item 1 and before items 2–6. Source: `docs/MARKET_AND_REVENUE.md`. Roblox's June
2026 discovery update ranks on "intentional co-play days per user", and PTK currently
generates none of it. This item is the minimum that produces the signal. It is **not** the
blueprint §22 party system.

- Two players who ESCAPE within a short window of each other both get a bonus. The ESCAPED
  screen shows it, so the cause is obvious.
- A downed player can be revived by another player within a few seconds, instead of dying
  outright.
- Server-authoritative: the server validates a revive by distance and state, and computes
  the escape bonus from the actual escape timestamps.
- Additive only. Playing solo must never become less efficient (§22).
- Analytics: `CoPlayExtraction`, `PlayerRevived`, `PartyBonusAwarded`.

---

## Explicitly out of scope

Not in this milestone, no matter how small it seems: Greenvale, a second kingdom, armor,
parties (item 7's escape bonus and revive are the only co-play), friends, contracts, collection index, PvP, player raids, trading, mounts, crafting,
cosmetics, the store, VIP, or any monetization.

Milestone 3 exists. Let it.

---

## Engineering constraints

- Everything in `CLAUDE.md` still applies. Server-authoritative, config-driven, no magic
  numbers, schema migration if the profile shape changes (it will — inventory and pity meter
  are new fields, so bump `SchemaVersion` and write the migration step).
- New analytics events: `CaptainEngaged`, `CaptainKilled`, `CaptainDefeatedPlayer`,
  `RareObtained`, `WantedLevelReached`, `WeaponEquipped`, plus item 7's `CoPlayExtraction`,
  `PlayerRevived`, `PartyBonusAwarded`.
- One branch per numbered item above. Seven small PRs beat one large one.

## Done means

Run the M1 checklist plus:

- [ ] A first-time player loses to Captain Bronn on run 1 and understands why
- [ ] Two consecutive runs produce visibly different loot
- [ ] A player can choose to raise their wanted level and is paid for it
- [ ] The HUD always shows something the player is close to
- [ ] Death at 50% loss feels tense rather than punishing
- [ ] **A tester, unprompted, says some version of "I want to go back for the Captain"**

The last box is the only one that actually matters.
