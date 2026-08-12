# M1 Bugfix Brief — playtest 2026-08-11

Five defects found in the first real playtest. All are in Milestone 1 code. **Do not add
features while fixing these.** Scope is exactly what's listed here.

Root cause for 1, 2 and 5 is the same: **ProximityPrompt state is global to the server, but
the game's objectives are per-player.** Fixing that one thing fixes three bugs.

---

## Bug 1 — Chain prompt never goes away (P1)

**Repro:** Break chains. The "BREAK YOUR CHAINS / Break" prompt stays active forever.

**Cause:** `InteractionService` sets `run.ChainsBroken = true` but never touches
`chainPrompt.Enabled`.

## Bug 2 — Weapon plank and chest prompts never go away (P1)

**Repro:** Take the Bent Spoon. "GRAB A WEAPON / Take" is still there. Open the chest, it
re-arms 30 seconds later and gives loot again.

**Cause:** Same as Bug 1. The chest's 30-second re-arm in `InteractionService` was written
for repeat runs; it reads as broken and lets a player farm the guaranteed chest.

## Bug 5 — Prompts are shared across players (P1)

**Repro:** Two players. One opens the chest; it disables for both.

---

### Fix for 1, 2 and 5 — per-player prompt visibility

`ProximityPrompt.Enabled` is replicated, so it cannot be per-player from the server. But a
**client** can disable a prompt locally, and the server still validates every `Triggered`
call. That gives correct per-player behaviour with no security loss.

**Do this:**

1. **Server: stop toggling `Enabled` entirely.** Remove every
   `chestPrompt.Enabled = false` / `task.delay(30, ...)` re-arm block in
   `InteractionService`. Delete the `run.ChestOpened = false` reset. Once a run's chest is
   opened, it stays opened for that run; `StartRun` already creates a fresh run record.

2. **Server: tag each prompt** so the client can identify it without name-matching:
   ```lua
   chainPrompt:SetAttribute("PTKGate", "chains")
   weaponPrompt:SetAttribute("PTKGate", "weapon")
   doorPrompt:SetAttribute("PTKGate", "door")
   chestPrompt:SetAttribute("PTKGate", "chest")
   ```
   Do the same in `UpgradeService` with `"upgrade"` and `"reenter"`, and in
   `ExtractionService` with `"extract"`.

3. **Server: add the fields the client needs** to the `StateUpdate` payload in
   `EconomyService.PushState`:
   ```lua
   ChainsBroken   = run and run.ChainsBroken or false,
   HasWeapon      = profile.Equipped.WeaponId ~= "fists",
   ChestOpened    = run and run.ChestOpened or false,
   UpgradeCost    = <see Bug 4>,
   ```

4. **Client: new `Controllers/PromptController.luau`.** On each `StateUpdate`, walk
   `CollectionService` or `workspace.World.Interactables` for parts with a `PTKGate`
   attribute and set `prompt.Enabled` from the current state:

   | Gate | Enabled when |
   |---|---|
   | `chains` | `not state.ChainsBroken` |
   | `weapon` | `state.ChainsBroken and not state.HasWeapon` |
   | `door` | `state.HasKey` |
   | `chest` | `not state.ChestOpened` |
   | `extract` | `state.RunState ~= "Safe"` |
   | `upgrade` / `reenter` | `state.RunState == "Safe"` |

   Register it in `ClientBootstrap`.

5. **Server: also destroy the chain visually.** In `InteractionService.ReleaseChains`,
   replace the transparency flicker with actually removing `world.Chain` from view for that
   run, or leave the part and rely on the prompt gate — but the current 3-second
   transparency blip is meaningless. Prefer: drop the chain to the floor
   (`Anchored = false`) once, purely as feedback.

**Acceptance:** after breaking chains the prompt is gone for you and still present for a
second player who hasn't broken theirs. Chest gives loot exactly once per run.

---

## Bug 3 — Objective points at content that doesn't exist (P1)

**Repro:** Buy the armory upgrade. Objective becomes "THE CAPTAIN HAS BETTER GEAR". There is
no Captain in Milestone 1. Dead end.

**Fix:** In `UpgradeService.BuyWeaponRack`, change the post-upgrade objective to point at the
thing that actually exists:

```lua
ctx.RunState.SetObjective(player, "BREAK INTO THE CASTLE AGAIN")
```

Also audit `docs/MILESTONE_1.md` — it documents the old string.

**Note for later:** the blueprint's §82 tutorial copy ends on "THE CAPTAIN HAS BETTER GEAR"
deliberately, as the hook into the next goal. Restore that string in Milestone 2, when
Captain Bronn exists.

---

## Bug 4 — Upgrade prompt shows a stale price (P2)

**Repro:** Own armory level 1, have 194 gold. Prompt reads "UPGRADE ARMORY — 120 Gold".
Toast reads "NEED 46 GOLD". The toast is correct (level 2 costs 240); the prompt is not.

**Cause:** `UpgradeService.Init` sets `ObjectText` once with the base cost. It is never
recomputed, and being replicated it could not show a per-player price anyway.

**Fix:**

1. Make the server-side label generic and price-free:
   ```lua
   upgradePrompt = makePrompt(world.UpgradePad, "Upgrade", "UPGRADE ARMORY", 0.4)
   ```
2. Add a helper and send the real per-player cost in `StateUpdate`:
   ```lua
   function UpgradeService.GetCost(player: Player): number
       local profile = ctx.Data.Get(player)
       local level = profile and profile.Castle.WeaponRackLevel or 0
       return GameConfig.Economy.WeaponRackCost * (level + 1)
   end
   ```
3. Let `PromptController` write the per-player price into `ObjectText` **locally** on each
   `StateUpdate`: `"UPGRADE ARMORY — " .. state.UpgradeCost .. " Gold"`.
4. Fix the wording of the failure toast — it currently reads as a total, not a shortfall:
   ```lua
   Text = ("NEED %d MORE GOLD"):format(cost - ctx.Economy.GetGold(player))
   ```
5. When `WeaponRackLevel` is maxed, the client should show `"ARMORY FULLY UPGRADED"` and the
   gate should disable the prompt.

**Acceptance:** the prompt price always matches what is actually charged, at every level.

---

## Constraints

- Server stays authoritative. The client may only change what a prompt *displays* and
  whether it is locally interactable. Every `Triggered` handler keeps its existing
  server-side validation — do not remove a single distance or state check.
- No new features. No Captain, no inventory UI, no second kingdom.
- `luau-compile` must pass on every file before commit; CI enforces it.
- One branch, one PR: `fix/m1-prompt-lifecycle`.

## Test before calling it done

Run through `docs/MILESTONE_1.md`'s test checklist, plus:

- [ ] Each prompt disappears the moment its step is complete, and stays gone
- [ ] Chest yields loot exactly once per run, and again on a fresh run
- [ ] Two-player: prompt states are independent
- [ ] Upgrade prompt price matches the charge at levels 0, 1 and 2
- [ ] At max level the prompt is gone, not silently failing
- [ ] Post-upgrade objective sends you somewhere that exists
