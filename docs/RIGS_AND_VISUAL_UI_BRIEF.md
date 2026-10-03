# Rigs & Visual UI Brief

Written after the fourth playtest. The visual overhaul improved the castle and HUD layout,
but three problems remain:

> Still lacks animations (only Bronn has any, and they aren't good). No real models for the
> spoon, sword, Bronn or the guards. The UI is just blatant text — it needs shown items.

All three trace to two root causes. One is a mistake in M1 that is cheap to fix. The other is
a genuine capability limit.

---

## 1. Root cause: the enemies are not characters

`EnemyService.buildRig` builds every enemy from three parts: a `HumanoidRootPart`, a `Head`,
and a welded `Blade`. A `Humanoid` is parented to that, with `RequiresNeck = false` so it
doesn't kill itself.

**There are no arms, no legs, no torso. There is nothing to animate.**

This is why:
- Guards slide instead of walking
- Nothing idles, breathes, or reacts
- Bronn's attacks move his entire body, because he has no arm to swing
- Every enemy reads as a box

It was the right call for a graybox — it made the loop testable in a day. It is the wrong
thing to still be shipping, and it blocks every animation improvement downstream.

### The fix: real R15 rigs

Roblox Studio has a **Rig Builder** (Avatar tab) that generates standard R15 and R6 rigs with
full limb hierarchies. A proper `Humanoid` on a proper rig gets Roblox's **default animation
set automatically** — walk, run, idle, jump, fall — with no code and no imported assets.

That single change gets guards walking instead of sliding, for free.

It also unlocks everything else: once limbs exist, any R15 animation from Roblox's own free
packs or a community kit can be played with `Animator:LoadAnimation`. Right now none of them
can be used at all.

**This is the highest-impact change available and it costs nothing.**

#### Implementation notes

- Keep `EnemyConfig` exactly as it is. Rig construction is an implementation detail;
  `MaxHealth`, `Damage`, `MoveSpeed` and the rest don't change.
- Replace `buildRig` with a function that clones a stored R15 rig template and applies the
  config's colour and scale. Store the template in `ServerStorage`.
- **Silhouette still matters** (`ART_AND_UI_DIRECTION.md` §2). Use `Humanoid` body-scale
  properties — `BodyDepthScale`, `BodyHeightScale`, `BodyWidthScale`, `HeadScale` — so Bronn
  is genuinely bigger and bulkier than a guard rather than a recoloured copy.
- The player character is already a real R15 rig, so weapon welds continue to work unchanged.
- Verify `EnemyService.ApplyDamage` and the `CombatService` hit box still resolve correctly:
  hit detection currently finds a model via `EnemyId`, which still works, but a multi-part rig
  has more parts in the overlap query, so check `MaxTargetsPerSwing` still behaves.
- Watch performance. A full R15 rig is many more parts than three. Test with the usual guard
  count on a low-end device before merging.

---

## 2. The UI needs ViewportFrames, not text

"Blatant text" is accurate: the HUD shows weapon *names*. Items are never seen.

The Roblox answer is **`ViewportFrame`** — a UI element that renders a real 3D model inside a
frame, with its own camera. It is how most Roblox games draw item icons, inventory slots and
character previews. It needs **no image assets and no uploads**: it displays a model that
already exists in the game.

### What to build with it

1. **Weapon slot in the HUD** — the equipped weapon rendered as a slowly rotating 3D model in
   a styled panel, with the name and damage beneath it. Replaces the current text line.
2. **Inventory grid** (for `m2/inventory-equip`) — one `ViewportFrame` per owned weapon, in a
   grid, each tappable to equip. Rarity shown by the panel's `UIStroke` colour and a
   background `UIGradient`, per `ART_AND_UI_DIRECTION.md` §4.
3. **Loot reveal** — when a weapon drops, show it rotating in a `ViewportFrame` for a beat
   before it goes into the inventory. This is the §81 "rare reward" moment, and it is the
   difference between a toast and a feeling.
4. **Bronn's health bar** — a small `ViewportFrame` of his head beside the bar, so the boss
   has a face in the UI.

### Notes

- A `ViewportFrame` needs its own `Camera` and the model parented inside it. Clone the weapon
  model rather than reparenting the live one.
- They are not free to render. Keep the count low, don't animate more than a couple at once,
  and test on a low-end device.
- Icons must still read at phone size. A rotating model at 60px is mush; size the frames
  generously and keep the camera close.

---

## 3. What this does NOT fix

Being straight about the ceiling: **neither of the above produces actual 3D art.**

After R15 rigs and ViewportFrames, the game will have guards that walk properly, weapons you
can see and rotate, and inventory slots showing real items. The weapons will still be
**boxes**, because `WeaponConfig` defines them as `Vector3` sizes with a colour.

A spoon that looks like a spoon, a sword with a crossguard and a fuller, a Bronn with armour
plating — those are **meshes**. They cannot be written in Luau. They have to come from:

| Source | Cost | Notes |
|---|---|---|
| Roblox Creator Store | Free | Inspect every model for malicious scripts before inserting |
| Roblox free animation packs | Free | R15-ready, no retargeting, safest animation source |
| Community free melee animation kits (DevForum) | Free | Sword idle/attack sets exist that match PTK's needs |
| MoCap Online free pack | Free | Commercially licensed, no attribution; needs R15 retargeting |
| Paid asset packs | ~$10–20 | Worth it for boss movesets later |
| A human artist | Real money | For the icon, Bronn, and signature weapons only |

**This is the point where the project needs you, not the agent.** Claude Code can write the
code that loads and plays an animation; it cannot create the animation. It can write the
`ViewportFrame` that displays a sword model; it cannot model the sword.

### Suggested split

- **Claude Code, now, free:** R15 rig conversion, ViewportFrame UI, animation *playback*
  system wired up and ready for assets.
- **You, next:** acquire a free R15 melee animation pack and a handful of Creator Store
  weapon meshes. Drop the asset IDs into `WeaponConfig` and an animation config.
- **Claude Code, after:** wire the acquired IDs in. Trivial once they exist.

Building the playback system *before* the assets arrive is deliberate: it means the moment
you have an animation ID, it's a one-line config change rather than a new system.

---

## 4. Order of work

1. **R15 rig conversion** — biggest single visual win, free, unblocks everything else
2. **Animation playback system** — `Animator` wiring, config-driven animation IDs, with
   Roblox's default animation set working out of the box
3. **ViewportFrame weapon slot in the HUD** — replaces the text line
4. **ViewportFrame inventory grid** — lands with `m2/inventory-equip`
5. **ViewportFrame loot reveal** — the rare-drop moment
6. *(You)* acquire free animation packs and weapon meshes
7. Wire the acquired asset IDs into config

Steps 1–5 are free and are Claude Code's work. Step 6 is yours. Step 7 is trivial.

---

## 5. Honest expectation

After steps 1–5 the game will look substantially better: enemies that walk and idle, a HUD
showing real items, loot you see before you own it.

It will still be a game made of **boxes**, because that is what the assets are. The step
change to "looks like a real game" needs meshes, and meshes need either the Creator Store or
money. There is no code path to it.

That is not a reason to delay 1–5. Those steps are what make imported assets *land* when they
arrive — without real rigs, an animation pack is unusable; without ViewportFrames, a weapon
mesh is invisible outside the player's hand.
