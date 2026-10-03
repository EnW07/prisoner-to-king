# PRISONER TO KING — Master Build Spec

**This document is the work order for a long autonomous session.** It supersedes the
remaining items in `M2_BRIEF.md` and absorbs them. Everything in `CLAUDE.md` still applies
without exception.

Read in this order before writing code: `CLAUDE.md`, this document,
`ART_AND_UI_DIRECTION.md`, `PLAYTEST_5_BRIEF.md`, `BLUEPRINT.md` (§8, §11, §12, §13, §14,
§15, §30, §38, §80, §81).

---

# PART 0 — VERIFY BEFORE BUILDING (do this first, do not skip)

The previous session ended with a stack of unmerged branches and **one unconfirmed
diagnosis**. Everything below depends on it. Resolve it first.

## 0.1 The unconfirmed diagnosis

The previous session concluded that Roblox's newer avatar rigs use `AnimationConstraint`
instead of `Motor6D` for joints, and that this single fact caused three symptoms: Bronn's
setup threw and left him motionless with no health bar, enemy arm swings did nothing, and the
player's swing only rotated the weapon at the wrist. It added a `[ArmPose]` log line that
names the joint type actually present, and made the code handle both forms.

**That log line has never been read.** It is the keystone of the current combat
implementation.

**Action:**
1. Check out `fix/damage-display` (the top of the stack — it contains everything).
2. Verify the branch builds and every file parses.
3. Report to the user: "Play `fix/damage-display` and send me the `[ArmPose]` line from
   Output, plus any `[Captain]` or `[Enemy]` warnings." Then **wait**.
4. When the user reports back, confirm or correct the diagnosis before continuing.

If the user tells you to proceed without this, proceed — but note in your report that the
combat foundation is unverified.

## 0.2 Merge and clean

Once verified: merge the stack into `main` in dependency order, each with `--no-ff`, no
squashing. Delete merged branches. Confirm `stylua --check src` and the parse sweep are green
on `main`. Every subsequent phase branches from a clean `main`.

## 0.3 Working method for the rest of this document

- **One branch per numbered section.** Small, reviewable commits.
- **Parse sweep and stylua before every push.** Never push red.
- **Report after each PART**, not each section, to `C:\dev\reports\agent-report.md`,
  overwriting, including full diffs.
- **Hard stops** (wait for the user): the schema migration in §5.6, and any point where you
  genuinely cannot decide. Everything else runs continuously.
- **Never** `git commit --amend`, never squash.
- If a section turns out to be a bad idea once you're inside the code, say so in the report
  and skip it rather than building something you believe is wrong.

---

# PART 1 — COMBAT DEPTH

The core loop has been flat since M1 because enemies had no attack cycle. The previous
session built one. This part makes it a *fight* rather than a timing puzzle with one input.

## 1.1 Player combat — the missing verbs

Currently the player has exactly one input: swing. `BLUEPRINT.md` §11 scoped light attack,
heavy attack, dash and block, and deliberately deferred most of it. The loop is now mature
enough to need more.

**Build, in this priority order:**

### Dash / dodge (highest value)
- Short directional burst, generous i-frames at the start, meaningful cooldown.
- This is what makes the enemy windup *mean* something. Without a dodge, a telegraph is just
  a delay.
- Mobile: its own large button, bottom right cluster.
- Config: `DashDistance`, `DashDuration`, `IFrameWindow`, `DashCooldown`.
- Feedback: a motion-blur streak or afterimage, a sharp whoosh, and a brief camera pull. The
  dash must feel *good* on its own, because players will spam it.

### Heavy attack
- Hold the attack input, or a second button on mobile.
- Slower windup, more damage, breaks a blocking enemy's guard, knockback on hit.
- This is the answer to the Shield Guard in §2.3 — a specific solution to a specific problem,
  which is what makes an enemy roster meaningful.
- Config per weapon: `HeavyDamageMultiplier`, `HeavyWindup`, `HeavyCooldown`.

### Block (build last, cut if time is short)
- Hold to reduce incoming damage; perfect-timed block staggers the attacker.
- Only worth building if dash and heavy already feel good. A third defensive option on top of
  a weak foundation adds confusion, not depth.

### Light attack combo
- Two or three chained swings with escalating animation and a finisher that knocks back.
- The third hit should feel conclusive — bigger arc, heavier impact, more hit-stop.
- Combo window resets if the player pauses.

**Design constraint from §11:** depth comes from enemy patterns, weapon identity, positioning
and extraction risk — not from six buttons. Four inputs total (swing, heavy, dash, and
interact) is the ceiling for mobile.

## 1.2 Weapon identity

`BLUEPRINT.md` §64 is explicit: do not create fifty swords that differ only in a damage
number. Each weapon *class* needs one mechanical identity:

| Class | Identity |
|---|---|
| Sword | Balanced. Fastest combo. The baseline everything is measured against. |
| Axe | Slow, heavy, breaks guard on light attacks. |
| Spear | Longer reach. Can hit from outside a guard's standoff distance. |
| Dagger | Very fast, low damage, longest i-frame dash. |
| Hammer | Slowest, massive knockback, stuns. |

Implement this as data in `WeaponConfig`: `Reach`, `ComboLength`, `GuardBreak`,
`KnockbackForce`, `StaggerDuration`. Combat code reads the fields; it never special-cases a
weapon id.

Add the weapons the blueprint's P0 list already names but that don't exist yet: `Axe`,
`Spear`. Keep the roster small — six to eight weapons total.

## 1.3 Hit feedback (§11, §92)

Every hit needs the full stack, and it must all read with sound off:

- Hit-stop scaled to damage (already exists — verify it's tuned)
- Camera kick scaled to damage, with a reduced-shake setting honoured (§40)
- Damage number with size scaled to the hit's significance
- Impact VFX at the contact point, not at the enemy's centre
- Enemy flinch — a real stagger animation on light hits, a longer one on heavy
- Knockback on finishers and hammer hits
- A distinct, unmistakable effect on a killing blow

## 1.4 Enemy stagger and poise

Enemies currently absorb hits without reacting, which makes the player's attacks feel weightless.

- Every enemy has a `Poise` value. Damage reduces it; it regenerates over time.
- At zero poise the enemy staggers — a visible stumble, interrupted attack, vulnerable window.
- Bosses have high poise and stagger rarely, but it must be *possible*, or heavy attacks have
  no purpose against them.

---

# PART 2 — ENEMY ROSTER

`BLUEPRINT.md` §59 lists Basic Guard, Archer, Shield Guard and Captain as **P0 MVP content**.
Only the guards and Captain exist. The roster is the single cheapest source of combat variety
— each enemy is a few dozen lines of config plus a behaviour, and each one changes how a room
plays.

**§12 rule: each enemy needs exactly one readable gameplay identity.** If you can't state it
in one sentence, redesign it.

## 2.1 Basic Guard (exists — refine)
*Identity: the baseline. Teaches the attack cycle.*
Walks toward the player, stops at standoff, telegraphed swing. Nothing special. This is the
enemy every other enemy is a variation of, so its timing must be the clearest.

## 2.2 Archer
*Identity: punishes standing still. Weak up close.*
- Holds distance and retreats if the player closes.
- Fires a visible, dodgeable projectile with a clear draw-back telegraph.
- Very low health; dies in one or two hits.
- Creates the first real positioning problem: fight the melee guard while an archer is
  shooting you, or break off and kill the archer first.
- Projectile must be server-validated. The client renders it; the server decides the hit.

## 2.3 Shield Guard
*Identity: a lock with a specific key.*
- Blocks all frontal light attacks entirely.
- Heavy attack breaks the guard. So does attacking from behind.
- Slow, high health, low damage.
- This is the enemy that makes the heavy attack from §1.1 exist for a reason.

## 2.4 Hound
*Identity: pressure. Punishes extraction.*
- Fast, erratic, very low health, leaps to attack.
- Spawns in packs of two or three.
- Appears at higher wanted levels and during extraction runs — this is the enemy that makes
  running for the sewer with loot genuinely dangerous.

## 2.5 Crossbow Sentry (static)
*Identity: area denial.*
- Doesn't move. Fires on a fixed interval along a fixed line.
- Turns a corridor into a timing problem.
- Cheap to build, adds spatial variety, creates a route the player learns.

## 2.6 Enemy variety within a type

Even the basic guard should not feel identical every time:
- Small randomised variation in scale, colour and weapon within config-defined ranges
- Randomised idle behaviour — some patrol, some stand, some lean on a wall
- Slight randomisation of attack timing within a band, so the player reads the *animation*
  rather than memorising a stopwatch

---

# PART 3 — BOSSES

## 3.1 Captain Bronn — finish him

Bronn exists but is thin. `BLUEPRINT.md` §18 gives the template: unique silhouette, three
core attacks, one phase transition, one iconic drop, one trophy, difficulty readable in under
30 seconds.

**Three distinct attacks, each demanding a different response:**
1. **Cleave** — wide horizontal arc. Dodge *backward* or out of range.
2. **Crushing Blow** — slow overhead, huge damage, small area. Dodge *sideways*. Long
   recovery — this is the player's main damage window.
3. **Charge** — he rushes a distance. Dodge *perpendicular*. Ends with him briefly stuck.

Each needs a wind-up pose so distinct the player recognises it from the first frame, with no
sound.

**Phase transition at 50%:**
- Visual change: armour glows, weapon ignites, he roars
- One reinforcement called (already built — verify it despawns on reset)
- Attack speed increases modestly, and he gains one new move
- The transition must be a *moment* — screen flash, audio sting, camera push

**Arena:** his hall should have something to use — pillars that block the charge, a dais that
changes elevation. A flat empty box is a worse fight than the same boss in an interesting room.

## 3.2 The Warden — second boss

`BLUEPRINT.md` §18 specifies this one in detail. Build it only after Bronn is genuinely good.
Hammer Slam, Chain Pull, Shockwave; furnace ignites at 50%; drops `WARDEN HAMMER — LEGENDARY`
and a `Warden Helmet` trophy.

If time runs short, skip this entirely and note it. One excellent boss beats two mediocre ones.

## 3.3 Boss presentation

- Health bar with segment markers showing phase thresholds
- Name and title card on first encounter — a brief, skippable, one-time moment
- Distinct music cue if audio IDs exist; if not, leave the hook in place
- Death: slow-motion final blow, a held beat, then the reward sequence

---

# PART 4 — WORLD AND ROOMS

The map is "very very very small" per playtest feedback. The castle must feel like a place.

## 4.1 Scale and structure

Target: a full run of **3–5 minutes** including a boss attempt. Currently closer to 2.

**Required spaces**, each visually distinct and each posing a different problem:

1. **The Cells** — where you start. Barred cells, other prisoners (static props), dripping
   water. Cramped, oppressive, dark.
2. **Guard Room** — the first real fight. Tables, weapon racks, a fireplace. Two or three
   enemies with sightlines that let the player plan.
3. **The Long Hall** — vertical space, banners, pillars, light shafts from high windows.
   Patrolling guards and a crossbow sentry. The room that makes the castle feel big.
4. **Kitchen / Stores** — a cluttered, horizontal, chaotic space. Breakable crates and
   barrels, some containing loot. Visual relief from stone.
5. **The Barracks** — optional side room, higher risk, better loot. Sleeping guards who wake.
   Rewards exploration.
6. **The Vault** — the main chest, on a raised dais, lit dramatically. Treasure piles.
7. **Bronn's Hall** — the boss arena, with the pillars and elevation from §3.1.
8. **The Sewers** — the escape route. Narrow, flooded, claustrophobic. Hounds. This is the
   tension corridor; it must feel different from everywhere else.
9. **A second, locked route** — see §4.3.

## 4.2 Making rooms readable (§91, §36)

- **Light tells you where to go.** Torches cluster along the critical path; dead ends are
  darker. This is the cheapest navigation aid in existence.
- **Each room has one dominant colour note** within the dungeon palette, so the player always
  knows which room they're in.
- **Vertical variation.** Stairs, raised platforms, balconies, drops. A flat map reads as a
  corridor no matter how big it is.
- **Sightlines.** From each room the player should glimpse the next, which pulls them forward.
- **Scale things up** (§36) — doors, chests, weapons, bosses. Most players are on phones.

## 4.3 The locked shortcut (§59, held in reserve, now build it)

The blueprint's MVP scope specified "1 extraction route plus 1 unlockable shortcut" and only
the sewer was ever built. ARC Raiders uses exactly this pattern — safer exits requiring a key.

- A second extraction route, locked, opened with a key found deep in the castle
- Shorter and safer than the sewer, but the key is in a dangerous place
- **This directly addresses "run 2 has no reason to exist"**: the player who knows about the
  shortcut plays the castle differently from the player who doesn't

## 4.4 Environmental interaction

- Breakable crates and barrels containing gold or small loot
- Torches that can be knocked down
- Chandeliers or stacked crates that can be dropped on enemies
- Doors that can be barred behind you to delay pursuit

These generate the §90 stories: *"I dropped a chandelier on three guards."*

## 4.5 Performance (§41)

A larger map makes this real rather than theoretical.
- Evaluate `StreamingEnabled` once the map grows past the current size
- Pool VFX and loot parts rather than creating and destroying constantly
- Keep the onboarding area especially light — the first 60 seconds must never wait on a
  distant room's assets
- Cap active NPCs; despawn far-away enemies rather than ticking them
- Test on low graphics settings and report the frame rate

---

# PART 5 — SYSTEMS

## 5.1 Wanted system (M2 item 3, now with the respawn decision folded in)

Levels 0–3.

- Rises on kills, on opening the chest, on being seen
- Decays slowly if the player breaks line of sight and stays hidden
- Each level: more guards, better gold multiplier, and at level 3, hounds
- **Guards you kill stay dead for the run.** New guards arrive via the wanted system, entering
  from doors and stairwells rather than materialising where you killed someone. Clearing a room
  must feel permanent. Remove the old `RespawnDelay` behaviour entirely.
- HUD element per §6 of the art doc, in `bleed`
- The player must be able to *choose* to raise it. That choice is the whole point.

## 5.2 Rare drops (M2 item 2)

- Implement the weighted `LootConfig.Tables` roll properly, server-side
- Guard Sword as a low-weight drop from ordinary guards (already decided)
- Rarity presentation scales with value (§81): common is a toast, rare is the ViewportFrame
  reveal card, legendary is a held moment
- Keep §115 first-run guarantees intact — run 1 stays deterministic

## 5.3 Pity meter (M2 item 6)

- Boss kills add charge; at full charge the next boss chest guarantees Rare or better
- Always visible in the HUD as a bar with a number
- §13: never hide all progression behind pure randomness

## 5.4 Co-play hook (M2 item 7)

Roblox's 2026 discovery algorithm counts intentional co-play days. PTK currently generates
zero. Build the minimum that produces the signal — **not** the full party system:

- Two players extracting within a short window both get a bonus, shown on the extraction
  screen so the cause is obvious
- A downed player can be revived by another within a few seconds instead of dying
- Server-authoritative: revive validated by distance and state, bonus computed from actual
  server-side extraction timestamps
- Analytics: `CoPlayExtraction`, `PlayerRevived`, `PartyBonusAwarded`
- **Solo progression must never become inefficient.** The bonus is additive, never a penalty
  for playing alone (§22).
- Also fix: the player's swing is currently client-only, so other players can't see it.
  Replicate the swing animation.

## 5.5 Death loss tuning (M2 item 5)

`DeathUnsecuredLossPercent` from 1.0 to 0.5. §94 lists harsh full loss as a way to kill the
game with young players.

## 5.6 Schema migration — **HARD STOP**

Inventory, pity meter and any new persistent state change the profile shape. Bump
`GameConfig.Data.SchemaVersion` and write the migration step in `PlayerDataService.migrate`.

**Show the user the migration before it lands.** Do not merge it unreviewed. Never silently
reshape a saved profile.

---

# PART 6 — UI

`ART_AND_UI_DIRECTION.md` is binding. The HUD was rebuilt with proper panels and
ViewportFrames; this part finishes the job.

## 6.1 Principles (§80, §38)

The HUD answers four questions, in reading order: what should I do, what will I get, am I in
danger, what am I close to. Six persistent elements maximum. Touch targets ≥44px. Readable at
phone size. Nothing carried by colour alone.

## 6.2 What still needs building

- **Wanted level indicator** — prominent, in `bleed`, impossible to miss at level 3
- **Pity meter** — a bar with a number, always visible
- **Health** — currently the default Roblox bar. Replace with a styled one matching everything
  else, with damage flash and low-health pulse
- **Dash and heavy cooldown indicators** — radial fills on the mobile buttons
- **Minimap or compass** — optional, but a larger map may need one. Prefer a directional
  objective arrow over a full minimap; it's cheaper and reads better on a phone.
- **Enemy health bars** — small, above the enemy, fading in on first hit and out when
  disengaged. Not permanently on screen.
- **Boss bar** — exists; verify against §3.3
- **Settings panel** — music/SFX volume, reduced screen shake, camera sensitivity (§40)

## 6.3 Screens

- **Extraction success** — the §81 moment. The unsecured bar sweeping into Gold is already
  built; make the surrounding screen match its quality.
- **Death screen** — `CAPTURED!`, gold lost, gear kept, what killed you, and a fast retry. §66:
  the player should be making a new decision within seconds.
- **Inventory** — exists with ViewportFrames; add sorting and a comparison against equipped
- **Upgrade / hideout panel** — currently a ProximityPrompt. Give it a real panel showing what
  each upgrade does and what's next.

## 6.4 Polish rules

- Everything tweens — nothing snaps into existence
- Numbers roll rather than jumping
- Buttons respond on press: scale, colour, sound
- One style definition reused verbatim everywhere (already built — keep using it)
- Consistent verb vocabulary (§7 of the art doc): STEAL, BREAK, OPEN, ESCAPE, UPGRADE, RAID,
  CLAIM

---

# PART 7 — ANIMATION AND VISUAL POLISH

## 7.1 Animation system

The `AnimationConfig` contract exists: a slot takes `"default"`, an `rbxassetid://` override,
or falls back to procedural. Keep it. Extend coverage:

**Player:** idle, walk, run, jump, fall, light combo (3 stages), heavy, dash, block, hit
reaction, death, interact, extract.

**Enemies:** idle, patrol walk, chase run, each attack's windup/strike/recovery, stagger, death.

Every procedural pose must be replaceable by an imported clip with no code change.

## 7.2 VFX

All of this is achievable with `ParticleEmitter`, `Beam`, `Trail` and `Highlight` — no
imported assets:

- Weapon trails during swings, coloured by rarity
- Impact sparks at the contact point
- Blood or dust puffs on hit (stylised, not gore — §74)
- Dust motes in light shafts
- Torch flame and smoke
- A rarity-coloured beam on dropped loot, so it's visible across a room
- Chest-opening light burst
- Dash afterimage
- Boss phase-transition burst
- Extraction portal shimmer

## 7.3 Lighting and atmosphere

- Dynamic torch flicker affecting nearby surfaces
- Coloured lighting per room to reinforce identity
- Light shafts from high windows in the Long Hall
- Darkness as a design tool: the lit path is the way forward
- Verify it still runs on low-end mobile; cut shadow-casting lights if not

## 7.4 Camera

- Subtle FOV increase while sprinting
- Camera pull on dash
- Slight shake during boss attacks, honouring the reduced-shake setting
- Smooth follow with light lag rather than rigid attachment
- Death camera: slow drift, not an instant cut

## 7.5 Audio hooks

`SOUND_IDS` in `FeedbackController` is intentionally empty — no invented IDs. Expand the hook
list so the user can fill it in one place: hit (light/heavy), take damage, kill, enemy windup,
block, dash, loot pickup, rarity reveal, chest open, door, alarm, footsteps (varying by
surface), extraction success, death, boss roar, phase transition, rank up, UI click, purchase.

Leave every ID blank. Never invent an asset ID.

---

# PART 8 — WHAT NOT TO BUILD

Explicitly out of scope, no matter how natural it feels once you're in the code:

PvP. Player castle raiding. Trading. Guilds or clans. Pets or mounts. A crafting tree.
Kingdoms beyond the dungeon and Greenvale. Monetization of any kind — no store, no
gamepasses, no developer products, no VIP. Procedural dungeon generation. A global
marketplace. Seasons or battle passes. Prestige or ascension.

**On monetization specifically:** a new experience gets a 48–72 hour discovery boost, and
shipping monetization before the loop retains wastes it on signals that teach the algorithm
not to recommend the game. Monetization is an M3 decision, after the retention gate.

---

# PART 9 — DEFINITION OF DONE

Not "the code compiles." These are the human-observable outcomes:

**Combat**
- A guard approaches, stops, visibly winds up, strikes once, and is briefly vulnerable
- The player can dodge by moving during the windup, and it works reliably
- Hits feel like they land — stagger, hit-stop, impact VFX, damage numbers
- The heavy attack has a reason to exist (the Shield Guard)
- Weapon classes feel mechanically different, not statistically different

**Enemies**
- At least four enemy types with distinct, one-sentence identities
- Fighting two archers is a different problem from fighting two guards
- Enemies never push the player around

**Boss**
- Bronn has three attacks a player can learn to read
- The 50% phase transition is a moment, not a stat change
- He's present on every run, moves, and has a health bar

**World**
- A run takes 3–5 minutes including a boss attempt
- Each room is identifiable from one screenshot
- The locked shortcut gives a returning player a different plan
- Frame rate holds on low graphics settings

**UI**
- The HUD answers all four §80 questions at a glance
- Nothing snaps; everything tweens
- Readable on a phone

**The real test**
- After extracting once, a player wants to go back in

The last one is the only one that decides anything, and only a human playtest answers it.

---

# PART 10 — REPORTING

Write to `C:\dev\reports\agent-report.md`, overwriting, after each PART. Include:

1. What was built, by section number
2. **Full diffs** of everything added, changed or deleted
3. Anything you chose not to build, and why
4. Anything you're uncertain about that a playtest would settle
5. Specific things for the user to check in Studio that you cannot verify yourself —
   particularly performance on low-end settings, and anything depending on the `[ArmPose]`
   diagnosis
6. A single consolidated playtest checklist at the end

Do not mark any part complete yourself. Completion is a human playtest.

---

# APPENDIX — PRIORITY IF TIME RUNS SHORT

If you cannot finish everything, this is the order of value. Stop cleanly at a branch
boundary rather than leaving something half-built.

1. Part 0 (verification and merge) — non-negotiable
2. §1.1 dash, §1.3 hit feedback, §1.4 stagger — makes combat *feel* like combat
3. §2.2–2.4 the enemy roster — cheapest variety available
4. §3.1 Bronn finished properly
5. §4.1–4.2 the rooms
6. §5.1 wanted system with the respawn change
7. §6 UI completion
8. §7 animation and VFX
9. §5.4 co-play
10. Everything else

A smaller amount of work, finished and polished, is worth more than every section half-done.
