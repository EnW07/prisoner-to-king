# Playtest 5 — Bug Brief & Combat AI Redesign

Fifth playtest, on `main` after the R15 and ViewportFrame work. Five issues. Ordered by
impact, not by discovery order.

**Item 4 is the important one.** It is not a polish bug — it is the core combat loop being
absent. Take whatever time it needs.

---

## 1. Enemy AI has no attack behaviour (P0 — the real problem)

**Observed:** the guard runs at the player and keeps running into them forever, colliding
endlessly. He never stops, never winds up, never strikes as a discrete act.

**Cause:** `EnemyService.Think` calls `humanoid:MoveTo(pRoot.Position)` in the `Attack` branch
as well as the `Chase` branch. The enemy is always walking into the player's collision box.
`AttackPlayer` then applies damage invisibly on a cooldown timer. There is no spacing, no
telegraph, no commitment, no recovery — the attack is a number subtraction, not an event.

This is why combat has felt flat since M1. The guard is not fighting; he is a damage-over-time
field with legs.

### Required behaviour

Replace the `Attack` state with a real attack cycle:

```
Chase  → close to AttackRange, then STOP moving
Windup → telegraph plays, enemy committed, cannot turn to track
Strike → hit detection fires once, at a specific moment
Recover→ vulnerable pause before the next cycle
```

Specifics:

- **Stop at a stand-off distance.** Add `StandoffDistance` to `EnemyConfig` — the distance the
  enemy holds while attacking. It must be slightly *less* than `AttackRange` so the strike
  connects, and large enough that the enemy never pushes into the player's capsule. If the
  player moves away, return to `Chase`.
- **Windup is committed.** Once windup starts the enemy stops turning to track the player.
  This is what makes dodging possible — if the enemy tracks through the windup, there is no
  dodge, only a dice roll. Add `WindupTime` to config.
- **Damage applies at the strike moment**, not on a cooldown tick, and only if the player is
  still inside the hit area. Dodging must actually work.
- **Recovery is a punish window.** Add `RecoveryTime`. This is where the player is supposed to
  land their own hits. Without it, combat has no rhythm.
- **Enemies should not push the player around.** Whatever the implementation (collision
  groups, or simply never moving during the attack cycle), walking into the player must stop
  being a thing that happens.

This changes how the whole game feels. Tune `WindupTime` generously at first — a readable,
slightly-too-slow enemy is far better than a fast unreadable one.

---

## 2. Attack animations missing (P0, same system as #1)

**Observed:** running, walking and dying animate. Attacks do not. The weapon rotates in place;
the arm never swings.

**Cause:** `AnimationConfig` attack slots are empty, so they fall back to the procedural path,
which tweens the weapon part rather than the rig's arm. The enemies are now real R15 rigs with
real shoulder joints, so this is now fixable.

### Required

- Drive the attack from the **rig's arm**, through the shoulder joint, not by rotating the
  welded weapon part. Bronn already does this — apply the same approach to every enemy and to
  the player.
- Each phase of the cycle in #1 needs a visible pose: a readable draw-back during windup, a
  fast arc through the strike, a slow return during recovery.
- Keep it procedural for now, but build it so an imported `rbxassetid://` clip in
  `AnimationConfig` replaces it with no code change — that contract already exists, keep it.
- The player's swing needs the same treatment. Currently the weapon moves and the arm doesn't.

---

## 3. Bronn is broken (P0)

**Observed:** run 1 — Bronn present but motionless, **no health bar**, could be killed by
spamming. Later runs — **the model isn't there at all.**

**Cause:** unknown, needs investigation. Candidates:

- The R15 conversion may have broken his `Humanoid` health display settings
  (`HealthDisplayType`, `DisplayDistanceType`) or the nameplate/portrait rebuild may have
  replaced them.
- Motionless suggests his AI tick isn't running — check that his record is in the `active`
  table after the rig change, and that his state isn't stuck.
- Missing on later runs points at the ~60s respawn path failing — likely `SpawnCFrame` or the
  stored options not surviving the rig refactor.

Investigate properly rather than patching symptoms. A boss that doesn't move and has no health
bar is worse than no boss.

---

## 4. Damage number disagrees between HUD and inventory (P1)

**Observed:** HUD weapon slot reads `28 DMG`, inventory reads `18 DMG` for the same Guard
Sword. Inventory also appears to show every weapon as upgraded.

**Cause:** `EconomyService.GetPlayerDamage` returns the weapon's base damage **plus** the
weapon-rack bonus (`WeaponRackLevel × WeaponRackDamageBonus`). The HUD shows that total. The
inventory grid shows `WeaponConfig`'s raw value. Both are internally correct; together they
contradict each other. 18 base + 2 rack levels × 5 = 28.

**Fix:** show the same thing in both places, and make the bonus legible rather than hidden.
Suggested: display base and bonus separately — `18 +10` — so the player can see what their
upgrades are doing. Whatever form is chosen, the HUD slot, the inventory grid and the loot
reveal card must all agree.

Also verify the unequipped entries: the rack bonus applies to whatever is equipped, so every
weapon's displayed total should reflect what it *would* do if equipped.

---

## 5. The chest gives a duplicate sword every run (P1)

**Observed:** re-entering the dungeon and opening the chest "gives" the Rusty Sword again,
with the same damage, despite already owning it.

**Cause:** `LootConfig.Guarantees.FirstChestWeapon` is applied unconditionally in
`InteractionService`. The §115 first-run guarantee was only ever meant to cover run 1.

**Fix:** the guarantee applies on the **first run only**. After that, the chest rolls its loot
table — gold, a chance at something better, nothing guaranteed. If the player somehow doesn't
own the Rusty Sword yet, keep the guarantee until they do.

This also removes a small exploit and gives repeat runs a reason to feel different, which is
the whole point of the milestone.

---

## Order of work

1. **Bronn investigation** — he's broken, and everything else is tested around him
2. **Enemy attack cycle** (#1) — the core combat loop
3. **Attack animations** (#2) — the visible half of #1; build them together
4. **Chest guarantee** (#5) — small
5. **Damage display** (#4) — small

Items 1–3 are one piece of work in practice. Do them together.

## Constraints

- Everything in `CLAUDE.md` still applies. Server-authoritative; the attack cycle's damage
  decision happens on the server, with the client only playing what it's told.
- New config values (`StandoffDistance`, `WindupTime`, `RecoveryTime`) go in `EnemyConfig` or
  `GameConfig`, not inline.
- No new content. No archers, no shield guards, no new weapons.
- Parse sweep and stylua before every push.

## Done means

- A guard approaches, **stops**, winds up visibly, strikes once, and is briefly vulnerable
- The player can dodge an incoming attack by moving during the windup
- Enemies never push the player around
- Arms swing — on enemies and on the player
- Bronn moves, has a health bar, and is present on every run
- HUD and inventory agree on damage
- The chest doesn't hand out a duplicate sword on repeat runs
