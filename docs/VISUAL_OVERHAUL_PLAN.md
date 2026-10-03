# Visual Overhaul Plan

Written after the third playtest, October 2026. Supersedes the "Tier 0 only" guidance in
`ART_AND_UI_DIRECTION.md` §8 — not the palette, typography or layout rules, which still hold.

---

## 0. The finding

Three playtests, three times "I don't want to go back in." The first two were diagnosed as a
structural problem (run 2 identical to run 1). Captain Bronn fixed that structurally — and
run 2 still failed.

The third playtest produced a different and more credible diagnosis:

> It's unpleasant to look at. Things are invisible. There are no animations. It's boring to
> the eye. The map is very small.

**This has been contaminating every playtest.** A loop cannot be evaluated through an
interface that's unpleasant to use. "I don't want to go back in" may have been reporting
*feel*, not structure, the entire time.

Roblox's own UI/UX guidance states it directly: UI is often the primary way a game
communicates with the player, and poorly designed UI leaves players confused and frustrated
and leads to **poor retention**, while well-designed UI contributes to engagement and
monetization.

**Decision: do the visual pass BEFORE more content.** Then re-test the loop. If run 2 still
fails with a game that looks and feels good, the problem is structural after all and we pull
the key-locked shortcut forward. Until then we are testing through a broken lens.

---

## 1. What Claude Code can and cannot do

This is the question that decides everything below, so state it plainly.

### CAN do, to a genuinely high standard: all UI

**Roblox UI is code.** There is no asset to import. The gap between "looks default" and
"looks designed" is six modifier objects, and they are all built into the engine:

| Modifier | What it does |
|---|---|
| `UICorner` | Rounds edges |
| `UIGradient` | Fills a frame with a gradient |
| `UIStroke` | Clean outline on text or frames |
| `UIListLayout` / `UIGridLayout` | Positions children automatically |
| `UIPadding` | Breathing room inside a panel |
| `UIAspectRatioConstraint` | Stops a square going oblong on a wide screen |

Together those six are described as the difference between "looks designed" and "looks
default". **The current HUD uses none of them.** It is raw `TextLabel`s on a transparent
background — which is exactly why it reads as unfinished.

Two more things Claude Code can do that cost nothing:

- **Tweens.** Described as what elevates a GUI to the next level, and one of the few places
  where UI gets personality. The unsecured bar in `ART_AND_UI_DIRECTION.md` §6 is entirely a
  tween exercise.
- **Procedural animation.** No imported animation needed for weapon swing arcs, chest lids
  opening, torch flicker, Bronn's wind-up, loot bobbing, camera kick. All `TweenService` on
  parts.

### CAN do: much better geometry

The current dungeon is boxes because I wrote boxes, not because Roblox can't do better.
Cell bars, arched doorways, a chest with a hinged lid, torch sconces, banners, pillars,
window slits with light shafts — all achievable with primitives, `WedgePart`s, `CylinderPart`s
and negated unions.

### CANNOT do: meshes, textures, rigged characters, imported animations

No `.rbxm` models, no custom meshes, no texture maps, no FBX animations. Those need either a
marketplace, a tool, or a human. Section 2 covers where to get them.

**The practical consequence: the UI and feel problem is 100% solvable by Claude Code right
now, for free. The "characters look like blocks" problem is not.** And of those two, the UI
is the one players see every single second.

---

## 2. Free asset sources, researched

### Roblox Creator Store — first stop

Millions of assets from Roblox and independent creators: 3D model packs, materials, plugins,
UI elements, audio. Roblox has added paid models, but free assets continue to exist alongside
them, existing free models stay free, and Roblox continues publishing its own free assets.
Accessible directly inside Studio's Toolbox.

**Two warnings that matter:**

1. **Inspect every model before inserting it.** Free models are a known vector for malicious
   scripts. Check for `Script`/`LocalScript` children and `require()` calls before using
   anything. This is not paranoia; it's standard practice.
2. **Licensing is murky at the edges.** Assets uploaded before the Asset Privacy beta
   defaulted to "Open Use", meaning anyone with the asset ID can use them. Community consensus
   is that publicly distributed free models are fine to use in monetized games, but this is
   community consensus rather than a clean license grant. For anything load-bearing — your
   icon, your boss, your signature weapon — own the asset outright.

**Use it for:** environment props, materials, audio. **Not for:** anything that defines the
game's identity.

### Animations — three options

**Roblox's own free animation packs** are the safest route: built for R15, no retargeting, no
licensing question.

**Mixamo (Adobe)** — free with an Adobe account, several hundred animations covering combat,
locomotion and expressions, plus auto-rigging. Widely used by indie devs. Three caveats:
animations are tied to the Mixamo skeleton so retargeting to R15 takes work; quality is
inconsistent; and **Adobe's licensing terms have changed over time, so check current terms
before shipping commercially.** The Roblox import path is real but fiddly — community
tutorials exist, and a plugin called RoMixamo automates it.

**MoCap Online's free pack** — professional mocap quality, engine-ready FBX, and
**licensed for commercial use without attribution.** The cleanest licensing of the three.
Still needs retargeting to R15.

**Community free animation kits** on the DevForum include ready-made R15 melee sets — sword
idle, sword attack, knife attack — which is close to exactly what PTK needs.

**Recommendation:** start with Roblox's own packs for locomotion, and a free community melee
set for the sword. Don't touch Mixamo until something specific is missing — the retargeting
cost is real and the licensing needs checking.

### Paid, if you ever want it

Animation packs and UI kits sell in the roughly $10–20 range from several vendors. Worth it
later for boss movesets. Not now — free covers the current gap.

### CC0 / public domain 3D

Poly Haven releases assets under CC0, effectively public domain, usable commercially with no
credit required. Textures and materials transfer to Roblox well; full models usually need
poly-count reduction first.

---

## 3. What to build, in order

### Phase 1 — UI overhaul (Claude Code, free, highest impact)

Everything here is pure code. This is the single biggest visual win available.

1. **Rebuild the HUD with the six modifiers.** Panels with `UICorner` + `UIStroke` +
   `UIGradient` instead of floating text. Use the palette tokens already specified in
   `ART_AND_UI_DIRECTION.md` §3.
2. **Build the unsecured bar** (§6 of the art doc). Still unbuilt, still the signature
   element.
3. **Everything tweens.** Prompts fade in, toasts slide, the gold counter rolls up rather
   than snapping, the objective banner animates on change.
4. **Scale, not offset.** Size with `Scale` for anything that grows with the screen, `Offset`
   only for things that should stay a fixed physical size — a 2px divider, a border. Getting
   this wrong is why UIs look fine in Studio and break on a phone.
5. **Touch targets.** More than half of Roblox play is mobile; tiny targets are listed among
   the mistakes that make a UI look amateur.
6. **One descriptive style line, reused verbatim** — palette, corner radius, outline weight,
   type — on every panel, so nothing drifts.

**Style direction for PTK:** chunky cartoon reads fastest for younger players and small
screens. Three colours: a dark neutral for panels, a light neutral for text, one saturated
accent reserved for the primary action. For PTK that accent is `bleed` — reserved for danger
and unsecured loot, nothing else.

### Phase 2 — procedural animation and feel (Claude Code, free)

7. Weapon swing arcs with real wind-up and follow-through, not a single rotation
8. Chest lid that hinges open
9. Torch flicker, banner sway, dust motes in light shafts
10. Bronn's attacks given weight — anticipation, impact pause, recovery
11. Loot bobbing and rotating on the floor so it's visible
12. Hit-stop on heavy impacts

### Phase 3 — geometry and map size (Claude Code, free)

13. **Enlarge the map.** The corridor is 60 studs; the vault room 40×30. Make the dungeon
    read as a castle: more rooms, vertical variation, sightlines that let you see where you're
    going and what's dangerous.
14. Cell bars, arched doorways, pillars, window slits with light shafts
15. Real silhouettes: Bronn taller and wider, archers lean, shield guards bulky

### Phase 4 — imported assets (needs you, not Claude Code)

16. Free animation pack for the sword swing, from Roblox's own packs or a community kit
17. Creator Store environment props — inspected first
18. Only after all of the above: consider paying for a boss model

---

## 4. Guard respawn — the open design question

You flagged this and it deserves a real decision rather than a tweak.

**Current behaviour:** a guard dies, 25 seconds pass, an identical guard appears in the same
place. That is a simulator convention, and it is wrong for an extraction game.

**The case against respawning at all:** in an extraction game the castle should get *emptier*
as you clear it, and the tension should come from the alarm bringing *new* guards to *your*
position. A guard popping back into the same spot tells the player their actions don't matter.

**The case for respawning:** without it, a cleared castle has nothing left to fight on the way
out, which removes the extraction tension entirely.

**Recommendation: replace respawning with alarm-driven spawning.** Guards you kill stay dead
for the run. The wanted system (already scheduled in M2) spawns new guards dynamically based
on wanted level, arriving from entrances rather than materialising where you killed someone.
That makes clearing a room feel permanent, makes the alarm the actual threat, and ties
directly into the system being built anyway.

---

## 5. Revised order of work

| # | Work | Who | Cost |
|---|---|---|---|
| 1 | Fix the three playtest bugs: **P0** loot falls through the floor; **P1** "UPGRADE ARMORY" reads as armour/defence but grants damage; **P2** Bronn's 50% reinforcement survives his reset and keeps chasing | Claude Code | — |
| 2 | **Phase 1 — UI overhaul** | Claude Code | free |
| 3 | **Phase 2 — procedural animation** | Claude Code | free |
| 4 | **Phase 3 — map size and geometry** | Claude Code | free |
| 5 | **Re-playtest. Does run 2 work now?** | You | — |
| 6 | Wanted system with alarm-driven spawning, replacing respawn | Claude Code | free |
| 7 | Remaining M2 items | Claude Code | free |
| 8 | Imported animations and props | You + Claude Code | free |

Steps 2–4 move ahead of the remaining M2 content. **Step 5 is the real decision point.**

---

## 6. The honest caveat

A visual overhaul will not, by itself, make a boring loop fun. If run 2 still fails after
Phases 1–3, the structural diagnosis was right and content is genuinely the gap.

But the reverse is also true, and currently more likely: **a good loop cannot be evaluated
through an interface that's unpleasant to look at.** Three playtests have now been run through
that interface. Fixing it costs nothing but Claude Code's time and removes the confound.

Do it, then ask the question again.
