# CLAUDE.md

Project instructions for agentic work in this repo. Read `docs/BLUEPRINT.md` before any
non-trivial change — it is the product source of truth.

## What this is

`PRISONER TO KING` — a Roblox extraction-progression game. **Milestone 1 (graybox) is built
and playable.** See `docs/MILESTONE_1.md` for exactly what exists.

## Environment

- Roblox Studio: **Windows/macOS only.** Not supported on Linux.
- Sync: `rojo serve`, then Connect in the Rojo Studio plugin.
- Keep the repo, Rojo, and Studio on the **same** working tree. Do not run Rojo against one
  copy while Studio has another open.
- Build a place file with `rojo build -o PrisonerToKing.rbxlx`. Never commit it.

## Non-negotiable engineering rules

These come from blueprint §103/§44 and are not up for renegotiation without a discussion.

1. **Server decides, client asks.** Damage, currency, loot, extraction, inventory and
   progression are server-authoritative.
2. **No remote may accept a value the server could compute itself.** Currently no remote in
   this codebase takes a number from the client. Keep it that way. `AttackRequest` is fired
   with zero arguments on purpose.
3. **Every client-callable remote is rate limited** via `RateLimiter`. Violations are logged
   and ignored — never auto-kick. Lag is indistinguishable from abuse.
4. **Content is data.** New weapons and enemies go in `src/shared/Config/`, never in new
   logic scripts.
5. **No magic numbers.** Tunable values live in `GameConfig.luau`.
6. **No monolithic scripts.** One service, one responsibility, one file.
7. **Persistence changes require a schema migration.** `PlayerDataService.migrate` is the
   only place profile shape changes. Bump `GameConfig.Data.SchemaVersion` and add a step;
   never silently reshape a saved profile.
8. **Never invent a Roblox API.** If uncertain about a signature, flag it in a comment and
   verify against current Creator docs. `AnalyticsService` is the existing example — every
   call is `pcall`-wrapped so an API change degrades to a log line, not a crash.

## Scope discipline

The blueprint's central thesis (§94, §127) is that scope kills this genre of project.

**Do not build past the current milestone without being asked.** Not PvP, not trading, not
clans, not pets, not mounts, not crafting, not a second kingdom, not player raids.

Milestone 2 starts only after the closed-alpha funnel gates in `docs/MILESTONE_1.md` are
met — in particular **second-run rate above 45%**. If testers don't voluntarily go back into
the dungeon, adding content does not fix it.

## Before committing

```bash
# every file must parse
for f in $(find src -name "*.luau"); do luau-compile --binary "$f" >/dev/null || echo "FAIL $f"; done

stylua src
```

CI runs both on push. The parse check is deliberately not a full type analysis — Roblox
globals aren't in scope on a CI runner, so it would be all false positives.

## Commit and PR conventions

- Branch per change: `m1/extraction-tuning`, `m2/inventory`, `fix/loot-duplication`.
- Commit messages state **what changed and why**, referencing the blueprint section when the
  change is a design decision rather than a bug fix.
- Balance changes should be a one-line diff in `GameConfig.luau`. If a balance change touches
  gameplay logic, the number was in the wrong place.

## Things that must never be committed

- `.rbxl` / `.rbxlx` place files. `src/` is the source of truth; binary places can't be
  diffed, reviewed, or merged.
- Open Cloud API keys, DataStore dumps, `.env`. Gitignored as a backstop, but the real
  defence is keeping them out of the working tree.

## Bug priority (§119)

- **P0:** data loss, purchase failure, duplication, stuck tutorial, impossible extraction,
  server crash.
- **P1:** combat exploit, broken boss, severe mobile UI issue, performance regression.
- **P2:** cosmetic, minor animation, typo.

Never ship a new weapon while a P0 is open.
