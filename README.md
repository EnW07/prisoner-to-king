# PRISONER TO KING

> Start in chains. Steal your first weapon. Escape the dungeon. Build power. Raid castles. Become king.

A Roblox extraction-progression game. **Milestone 1 (graybox) is implemented and playable.**

- Product direction and full design doc: [`docs/BLUEPRINT.md`](docs/BLUEPRINT.md)
- What's built right now, plus test checklists: [`docs/MILESTONE_1.md`](docs/MILESTONE_1.md)

---

## Requirements

| Tool | Why | Notes |
|---|---|---|
| **Roblox Studio** | Run and test the game | **Windows or macOS only.** See below. |
| **Rojo 7+** | Syncs this repo into Studio | Install via [Rokit](https://github.com/rojo-rbx/rokit), Aftman, or `cargo install rojo` |
| **Rojo Studio plugin** | The Studio side of the sync | Install from the Roblox plugin marketplace |
| **StyLua** *(optional)* | Formatting, enforced in CI | `rokit install` picks it up |

### Roblox Studio is not supported on Linux

There is no official Linux build of Roblox Studio — Roblox ships Windows and macOS only. Community workarounds exist (Vinegar/Wine), but they're unofficial, break on Roblox updates, and are widely reported to be unstable for Studio specifically: flickering viewports, login failures, crashes.

**Recommendation: use Windows or macOS for Studio.** You can keep everything else — this repo, the editor, git, Rojo's CLI — on Linux if you prefer, since Rojo syncs over the network. But the Studio session itself should live on a supported OS. A dual boot or a Windows VM both work.

---

## Setup

```bash
git clone <your-repo-url> prisoner-to-king
cd prisoner-to-king

rokit install          # or: aftman install / cargo install rojo
rojo serve
```

Then in Studio:

1. Open a **new, empty Baseplate place**.
2. Plugins → Rojo → **Connect** (default address `localhost:34872`).
3. Press **Play**.

That's the whole setup. The map, the remotes, and the HUD all generate at runtime — there is nothing to build by hand.

### One-time Studio settings

- **Game Settings → Security → Enable Studio Access to API Services.** Required for DataStores. Without it the game still runs; `PlayerDataService` falls back to an in-memory profile and refuses to write, so real save data can never be corrupted by a Studio session.

### Building a place file instead of syncing

```bash
rojo build -o PrisonerToKing.rbxlx
```

Place files are gitignored on purpose. **`src/` is the source of truth**, never a `.rbxl`. Binary place files can't be diffed, reviewed, or merged, and two people editing one is a guaranteed lost afternoon.

---

## Layout

```
src/
  shared/          → ReplicatedStorage.Shared      (config + remote definitions)
    Config/                                        all tunable numbers live here
  server/          → ServerScriptService           (authoritative game logic)
    Services/
  client/          → StarterPlayer.StarterPlayerScripts
    Controllers/                                   HUD, input, feedback
docs/
```

The mapping is defined in [`default.project.json`](default.project.json).

---

## Working rules

These come from §103 of the blueprint and are worth keeping:

1. **Server decides, client asks.** Damage, currency, loot, extraction, and progression are server-authoritative. No remote in this codebase accepts a number from the client.
2. **Content is data.** New weapons and enemies go in `src/shared/Config`, not in new logic scripts.
3. **No magic numbers.** If you're tuning balance, the number belongs in `GameConfig`.
4. **Don't build past the current milestone.** The blueprint's whole thesis is that scope kills this genre of project. Milestone 2 starts only after the Milestone 1 funnel gates are met.
5. **Small modules.** No 5,000-line `MainScript`.

---

## Roadmap

| Milestone | Contents | Status |
|---|---|---|
| **M1 — Graybox** | Chains → weapon → guard → key → chest → alarm → extract → upgrade → re-enter | ✅ Built |
| **M2 — Vertical slice** | Inventory + equip, Captain Bronn, rare drops, death loss tuning, persistent save polish | Not started |
| **M3 — MVP** | Greenvale, 3 enemy archetypes, 6 weapons, ranks, contracts, collection index, purchase handling, mobile polish | Not started |

**Gate before M2:** second-run rate above 45% in closed alpha. Full funnel targets in [`docs/MILESTONE_1.md`](docs/MILESTONE_1.md).

---

## CI

Every push runs a Luau parse check across `src/` and a StyLua format check. The parse check is deliberately not a full type analysis — Roblox globals aren't in scope on a CI runner, so it would be nothing but false positives.
