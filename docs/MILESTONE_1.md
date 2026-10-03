# PRISONER TO KING — Milestone 1 (Graybox)

Implements §104 of the blueprint and nothing beyond it.

**The loop:** spawn in chains → break chains → grab a weapon → kill a guard → the guard drops the key + gold → unlock the cellblock → open the chest (guaranteed Rusty Sword) → alarm → run the sewer → extract → gold banks → upgrade your weapons → re-enter.

Target completion time for a first-time tester: **2–4 minutes.**

---

## A. What is being built

A fully playable vertical slice using only Roblox primitives. The entire map is generated at runtime by `WorldBuilder`, so there is no manual building step — paste the scripts in, press Play, and the loop works. Combat, loot, currency, the key, and extraction are all server-authoritative. Every funnel event from §51 that applies to Milestone 1 is instrumented.

No store, no base building, no second kingdom, no PvP, no inventory UI.

---

## B. Studio hierarchy

Create exactly this. Folder names matter; script names matter.

```
ReplicatedStorage/
  Shared/                          (Folder)
    Net                            (ModuleScript)
    Config/                        (Folder)
      GameConfig                   (ModuleScript)
      WeaponConfig                 (ModuleScript)
      EnemyConfig                  (ModuleScript)
      LootConfig                   (ModuleScript)

ServerScriptService/
  Bootstrap                        (Script — server)
  Services/                        (Folder)
    AnalyticsService               (ModuleScript)
    PlayerDataService              (ModuleScript)
    EconomyService                 (ModuleScript)
    RunStateService                (ModuleScript)
    LootService                    (ModuleScript)
    EnemyService                   (ModuleScript)
    CombatService                  (ModuleScript)
    ExtractionService              (ModuleScript)
    UpgradeService                 (ModuleScript)
    InteractionService             (ModuleScript)
    WorldBuilder                   (ModuleScript)
    RateLimiter                    (ModuleScript)

StarterPlayer/
  StarterPlayerScripts/
    ClientBootstrap                (LocalScript)
    Controllers/                   (Folder)
      UIController                 (ModuleScript)
      CombatController             (ModuleScript)
      FeedbackController           (ModuleScript)
```

Files ending `.server.lua` are **Scripts**. Files ending `.client.lua` are **LocalScripts**. Everything else is a **ModuleScript**. Drop the `.lua` / `.server.lua` / `.client.lua` suffix when naming the object in Studio.

`ReplicatedStorage/Remotes` is created automatically at runtime — do not make it by hand.

Nothing needs to be placed in `Workspace` or `StarterGui`.

---

## C. Files

Generated in dependency order. Read them in this order too:

1. `Config/*` — all tunable data
2. `Shared/Net` — remote definitions
3. `Services/RateLimiter` — remote throttling
4. `Services/AnalyticsService` → `PlayerDataService` → `EconomyService` → `RunStateService`
5. `Services/WorldBuilder` — the map
6. `Services/LootService` → `EnemyService` → `CombatService`
7. `Services/ExtractionService` → `UpgradeService` → `InteractionService`
8. `Bootstrap` — wires it all together
9. `Controllers/*` — client HUD, input, feedback

---

## D. Configuration

Everything tunable lives in `ReplicatedStorage/Shared/Config`. The values most worth moving during testing:

| Where | Knob | Default | Why you'd change it |
|---|---|---:|---|
| `GameConfig.Run` | `ExtractionChannelTime` | 3 | Longer = more tension, more rage. A/B this (§55 Test 3). |
| `GameConfig.Run` | `DeathUnsecuredLossPercent` | 1.0 | The single most retention-sensitive number in the game. |
| `GameConfig.Economy` | `WeaponUpgradeCost` | 120 | First upgrade must be affordable off one run (§25). |
| `GameConfig.Economy` | `FirstEscapeBonus` | 100 | Makes the first extraction feel like a payoff. |
| `EnemyConfig.sleepy_guard` | `MaxHealth` | 30 | Tuned for 4–5 Bent Spoon hits (§8). |
| `GameConfig.Combat` | `Range` / `Width` | 8 / 6 | Widen if mobile players report whiffing. |
| `GameConfig.Enemy` | `ThinkInterval` | 0.2 | Raise if server frame time suffers at scale. |

---

## E. Manual setup

Only three things are not automated:

1. **Enable Studio Access to API Services** — Game Settings → Security. Required for DataStores. Without it the game still runs, but nothing saves (`PlayerDataService` falls back to an in-memory profile and refuses to write, so no real data is ever corrupted).
2. **Sound asset IDs** — `FeedbackController.SOUND_IDS` is intentionally empty. No placeholder IDs are invented. Fill in your own audio and the hit/loot/escape feedback turns on. Everything is readable with sound off by design (§92).
3. **Publish before trusting analytics** — `AnalyticsService:LogCustomEvent` only reports from a published experience. In Studio, events print to Output instead, which is enough to verify the funnel fires in the right order.

No animations, tags, collision groups, or GUI objects are required for Milestone 1.

---

## F. Security notes

What the server validates, per §44:

| Surface | Client sends | Server decides |
|---|---|---|
| Attack | An empty intent — literally no arguments | Rate limit, alive check, weapon cooldown from config, hit volume from the server's own character position, damage from config + saved upgrades |
| Loot pickup | Nothing — driven by a server-side `Touched` | Distance re-check, atomic claim flag flipped before any grant, owner rule for the guaranteed key |
| Key / door | Nothing — `ProximityPrompt.Triggered` | Distance re-check, run state check (`HasKey`) |
| Extraction | Nothing — prompt hold | Distance from pad re-checked, amount read from the server's run record, never from the client |
| Gold | Nothing | `TrySpendGold` is the only debit path and returns `false` rather than going negative |

There is deliberately **no remote that accepts a number**. An exploiter has no field in which to claim damage, gold, or loot.

Rate-limit violations are logged and ignored, never auto-punished — lag looks identical to abuse.

---

## G. Test checklist

Run in Studio (Play, then Play with 2 players for the multiplayer rows).

**Core path**
- [ ] Spawn is inside the cell, facing the doorway; walk speed is visibly slow
- [ ] "BREAK YOUR CHAINS" objective is legible at the top of the screen
- [ ] Chain prompt works on keyboard (E), and on touch after toggling device emulation
- [ ] After breaking chains, walk speed returns to normal
- [ ] Spoon pickup shows the weapon toast with rarity colour and `+7 DAMAGE`
- [ ] Attacking with no target still animates and does not spam errors
- [ ] Guard takes 4–5 hits, shows floating damage numbers, camera nudges on hit
- [ ] Guard death drops gold **and** the key, both physically visible on the floor
- [ ] Walking over gold increments `UNSECURED`, not `Gold`
- [ ] Door refuses to open without the key, with a clear warning toast
- [ ] Chest gives the Rusty Sword every time, plus 50 gold
- [ ] Alarm fires, two guards spawn, extraction pad turns bright green
- [ ] Extraction requires a 3-second hold and cannot be triggered from across the room
- [ ] "ESCAPED!" overlay shows banked gold + first escape bonus, then clears within ~3s
- [ ] Player lands in the hideout, `UNSECURED` is 0, `Gold` went up
- [ ] Weapon upgrade is affordable after one run and the rack visibly grows
- [ ] Weapon damage on the HUD increases by 5 after the upgrade
- [ ] Re-enter pad returns the player to the cell with chains already off

**Failure paths**
- [ ] Dying with unsecured gold shows "CAPTURED!", lists gold lost and gear kept
- [ ] The equipped weapon survives death
- [ ] Respawn puts the player back in the cell within a couple of seconds
- [ ] Leaving and rejoining preserves Gold, weapons, and weapon upgrade level (API services on)
- [ ] With API services **off**, the game still plays and prints the fallback warning

**Multiplayer**
- [ ] Two players cannot both collect the same gold pile
- [ ] Each player sees damage numbers only for their own hits
- [ ] The guaranteed key can only be picked up by the player who earned it

**Analytics**
- [ ] Output shows, in order: `FirstSpawn`, `ChainsBroken`, `FirstWeaponPicked`, `FirstGuardHit`, `FirstGuardKilled`, `FirstLootPicked`, `FirstChestOpened`, `FirstEscapeStarted`, `FirstEscapeCompleted`, `FirstUpgradePurchased`, `SecondRunStarted`
- [ ] Each `First*` event fires exactly once per session

---

## H. Known limitations (deferred on purpose)

- **Enemy rigs are part-built.** `HumanoidRootPart` + `Head` + `RequiresNeck = false`. Movement uses `Humanoid:MoveTo` with no pathfinding, which is fine in a straight corridor and will not be fine in Greenvale. If a rig ever misbehaves, swap `buildRig` for a cloned Rig Builder R6 model — nothing outside that function depends on its internals.
- **World interactables are shared, not per-player.** One player opening the chest disables it for everyone for 30 seconds. Correct fix is per-player instancing; not worth building before the loop is proven.
- **No inventory or manual equip.** Anything stronger auto-equips. That is Milestone 2.
- **Death always restarts from the cell.** No loot-recovery run-back (§66 optional).
- **No wanted system, no pity meter, no contracts, no store.** All Milestone 2/3.
- **Analytics custom-field keys need verification.** `Enum.AnalyticsCustomFieldKeys` usage is `pcall`-wrapped and should be re-checked against current Creator docs before launch. A signature change degrades to a log line rather than breaking gameplay.
- **No streaming.** The map is tiny enough not to need it; `StreamingEnabled` becomes relevant at Greenvale scale (§41).

---

## Alpha test protocol (§56)

Do this **before** building Milestone 2. 20–50 testers, no explanation.

**The rule:** if you have to stand next to someone and tell them what to do, onboarding failed. Write down where you wanted to intervene — that timestamp is the bug.

Watch for and record:
1. Seconds from spawn to chains broken
2. Seconds to first guard kill
3. Whether they find the sewer without being told
4. Whether they extract or die
5. Whether they voluntarily start a second run

Ask afterwards, in this order:
1. What were you trying to do?
2. What part was fun?
3. What was confusing?
4. What did you want next?
5. Would you play again tomorrow? Why?

Never ask "did you like my game?"

**Gates before Milestone 2** (from §53, these are internal product targets, not Roblox benchmarks):

| Step | Target |
|---|---:|
| Chains broken | >90% |
| First weapon | >85% |
| First guard kill | >75% |
| First extraction | >60% |
| First upgrade | >50% |
| Second run started | >45% |

If second-run rate is below 45%, the loop is not fun yet. Fix that before adding a single new weapon, kingdom, or feature.
