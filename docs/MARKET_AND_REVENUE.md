# Market & Revenue Strategy

Research pass, October 2026. Supplements `BLUEPRINT.md` §130, whose source notes predate
the June 2026 discovery change and the RDC 2026 announcements.

---

## 1. The single most important finding: PTK has no co-play

Roblox expanded Recommended For You from a 7-day view to a **28-day view that directly
measures long-term retention**, and published the full signal list. In testing, the updated
algorithm surfaced retaining games better, raising DAU platform-wide.

A **new signal** in the 2026 algorithm is 7-day intentional co-play days per user — how often
players deliberately join with friends, via direct invites, joining a friend's session, or
private servers.

**PTK is currently a 100% solo experience.** No parties, no invites, no shared objectives, no
reason to bring anyone. Against the 2026 algorithm that is not a missing feature, it is a
missing *signal category*. The blueprint flagged this in §22 and §58 Phase D, but parked it
behind M2 and M3.

**Recommendation: promote one small co-play hook into M2.** Not the full party system — the
cheapest thing that generates the signal:

- Two players in the same server both extracting within a short window → both get a bonus
- A downed player can be revived by another player
- A "join friend" prompt on the death screen

Each is a few hours of work and each produces exactly the behaviour the algorithm now counts.

---

## 2. What the genre data says about PTK's position

The 2026 charts are led by cozy/idle sims, roleplay, anime fighters, horror survival, and
**steal-and-defend**. Fighting and combat are described as the fastest-growing genre, and
simulators as the most reliably profitable.

The relevant precedent is Steal a Brainrot: a buy → generate income → steal or be stolen from
loop, merging tycoon/idle income with PvP base defence. It became the only Roblox game to
pass 25 million CCU, and the platform hit a 47.4M CCU record during its event. It spread on
TikTok and YouTube through clips of thefts and of children reacting to losing their Brainrots.

**Why this matters for PTK:** the steal-and-defend loop is proven, and PTK's
`steal → escape → bank → upgrade` is adjacent to it. One analysis notes the loop converts in
30 seconds, and that most successful Roblox games are a known loop with one differentiator.

PTK's differentiator is real: **you can lose the loot on the way out.** Steal a Brainrot's
tension is about defending what you own. PTK's is about the thirty seconds between grabbing
something and getting it home. That is a genuinely different feeling and it is clip-friendly.

**But note the warning in the same research:** brainrot/meme games convert hard on launch and
rarely hold long term. Build them when the trend is current, not as retention plays. PTK
should take the *loop structure*, not the meme aesthetic. The medieval framing is more
durable than the meme and ages better.

---

## 3. What the algorithm actually rewards

Roblox's discovery system is now **age-aware**: younger players engage best with shorter-form
games they discover, enjoy and move on from, while older players are drawn to deeper games
they return to. The system optimises for both, looking beyond the first week to the first 28
days and beyond. Roblox is also testing optimising discovery for **direct growth** — how many
new players a game brings to the platform.

Two practical consequences:

**A 60-minute daily cap.** Recommendation benefit is reportedly limited to the first 60
minutes of daily playtime per user per experience — the platform wants meaningful engagement,
not endless engagement. **Design implication: do not build systems that reward 4-hour
sessions.** Build systems that make someone return tomorrow. PTK's run length (2–4 min) is
well suited to this; long grind walls are not.

**Retention beats everything else.** One analysis puts a D1 target around 12%, and notes that
Dress to Impress holds visibility with sessions often under 15 minutes because players return
constantly. The blueprint's D1 20% ambition is aggressive; 12% is the more realistic
near-term gate.

---

## 4. Revenue: the honest math

Standard DevEx sits around **$0.0035 per Robux** for most developers; a 30% marketplace fee
applies before that, so a 400 Robux gamepass nets the developer 280 Robux, worth roughly 27
US cents of real revenue per sale.

ARPDAU after the full chain:
- Conservative (mid-tier sim, VIP pass): **$0.003–$0.006**
- Well-monetised (cosmetic economy, seasonal passes, cultivated base): **$0.015–$0.025**

At 1,000 CCU with ~4x that in DAU, a conservatively monetised game sees roughly **$12–24 per
day**. The same source makes the point that matters most: the gap between $0.003 and $0.020
at equal player counts is almost entirely a product and design question, not luck.

**Read that number honestly.** Roblox earning is a volume game. The path to meaningful
revenue runs through retention and scale, not through squeezing early players. There is no
monetization design that rescues a game people don't return to.

---

## 5. Monetization structure for PTK

### The split

Roughly **60–70% gamepasses, 30–40% developer products**. Gamepasses are permanent
account-bound entitlements queried with `UserOwnsGamePassAsync`; developer products are
consumables firing `ProcessReceipt` on every purchase, where the server must grant exactly
once and record idempotency so a receipt is never honoured twice.

### Pricing ladder

A tiered structure of 3–5 price points is recommended, with conversion falling as price
rises:

| Tier | Robux | Typical conversion | PTK candidate |
|---|---|---|---|
| Entry | 25–75 | 4–8% | Prisoner's cape, weapon trail |
| Core | 99–249 | 2–5% | Extra loadout slot, 2x extraction gold |
| Premium | 249–499 | 1–3% | VIP: nameplate, banner, daily reroll |
| Ultimate | 999+ | 0.1–0.5% | Royal cosmetic bundle |

Overall conversion of 1–3% is average for Roblox games.

### The highest-value insight

> The best-converting gamepass is not the cheapest or the flashiest — it is **the one that
> removes a frustration.** A pass that solves a specific pain point converts at two to three
> times the rate of a purely cosmetic offering.

**For PTK the obvious candidate is an extra loadout slot or inventory space** — but only once
inventory pressure is a real felt problem. Selling a solution to a frustration players don't
have yet converts at zero, and manufacturing the frustration to sell the fix is the exact
trap `BLUEPRINT.md` §26 warns against.

### Timing

Limited-time and seasonal offers with clear expiration reportedly convert at about **2x**
permanent ones. Use sparingly and never with fake countdowns (§26).

**Do not ship any monetization before M3.** Roblox gives new games a visibility boost in the
first 48–72 hours, and launching before the game is ready wastes that boost on an audience
that returns poor signals, teaching the algorithm the game isn't worth recommending.

---

## 6. Launch sequencing — this matters more than any feature

The new-game boost is a one-shot resource. The practical rule from every source: **polish
before launch, because a premature launch spends the boost on bad signals.**

Suggested order:

1. **M2 + co-play hook complete** — the loop has a reason to repeat and a social signal
2. **Closed alpha, 20–50 testers** — the §56 protocol, funnel gates met
3. **Quiet soft launch** — no marketing; validate the loop and fix bugs on real strangers
4. **Only then the coordinated launch** — all channels firing at once, during a high-traffic
   window

The first players have to come from sources you control — friends, social media, Roblox
communities — since the algorithm cannot recommend a game with no engagement data. Paid ads
don't substitute for this; what ads do is **seed organic signals**, buying players who then
generate real D1/D7 and payer data that improves ranking.

---

## 7. What this changes in the current plan

| Change | Why | When |
|---|---|---|
| **Add a co-play hook** | Co-play is a 2026 algorithm signal and PTK generates zero | M2, now |
| **Target D1 ≈ 12%, not 20%** | More realistic near-term gate | M1 alpha |
| **Don't reward long sessions** | 60-min daily recommendation cap | Ongoing |
| **Keep the loop at 2–4 min** | Matches short-session preference; already true | Ongoing |
| **Hold all monetization until M3** | Protects the new-game boost | M3 |
| **Plan for gamepass-led revenue** | 60–70% of surface, better perceived value | M3 |
| **Keep the medieval frame, not a meme skin** | Meme games spike and fade | Ongoing |

---

## 8. What does not change

The blueprint's core thesis survives this research intact, and most of it is *confirmed* by
it: build the loop first, prove retention, let content follow. The one thing research adds is
that **social is no longer a nice-to-have** — it moved from "Phase D" to "a signal category
you are scoring zero in."

Everything in §26 about monetization ethics also stands, and is reinforced by the platform's
direction: a game optimised for short-term extraction of money from children scores badly on
28-day retention, which is now what discovery measures. Treating players well and ranking
well have converged. That is a genuinely good incentive structure — build for the second one
and you get the first for free.

---

## Sources

- Roblox Newsroom, *Optimizing Discovery* (June 2026) — 28-day window, published signal list
- Roblox Newsroom, *RDC 2026: The World Needs More Play* (Sept 2026) — age-aware ranking,
  direct-growth testing
- Industry analyses of the 2026 charts, discovery mechanics, DevEx math, and gamepass pricing
  (ejaw, studiokrew, rowatcher, rolearn, game-ace, gmmarket)
- Wikipedia, *Steal a Brainrot* — CCU records, loop description, social spread

Platform specifics change fast. Re-verify DevEx rates, fee percentages, and algorithm signals
against Roblox's own Creator documentation before acting on any number here.
