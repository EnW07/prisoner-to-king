# PRISONER TO KING
## Roblox Breakout Blueprint — Product, Game Design, Growth, Monetization, Tech & Claude Build Brief
**Version:** 1.0  
**Prepared:** August 2026  
**Working title:** `PRISONER TO KING`  
**One-line fantasy:** Start in chains. Steal your first weapon. Escape the dungeon. Build power. Raid castles. Become king.

---

# 0. HOW TO USE THIS DOCUMENT

This is not meant to be a traditional 100-page AAA game design document that gets written once and ignored.

It is a **hit-oriented operating document**. It answers five questions:

1. What exactly is the game?
2. Why should someone click it?
3. Why should they keep playing after 30 seconds?
4. Why should they return tomorrow and bring friends?
5. How should the game be built so it can be tested, changed, and scaled quickly?

If this document is given to Claude or another coding agent, the agent should **not try to build everything at once**. Build the `P0 MVP` first, instrument it, test it with real players, and only build deeper systems after the basic loop proves itself.

The game must always prioritize:

`CLICK -> UNDERSTAND -> ACTION -> REWARD -> UPGRADE -> NEW GOAL -> RETURN -> SOCIAL`

over lore, realism, map size, visual complexity, or feature count.

---

# 1. EXECUTIVE THESIS

## 1.1 The original concept

The initial concept was:

> You start as the weakest medieval prisoner. Fight NPCs, steal weapons, escape increasingly secure castles, collect rare armor, and eventually raid other players' castles.

That concept has good ingredients but is too close to a broad RPG if implemented literally.

A broad medieval RPG is dangerous for a first Roblox project because it can easily become:

- a large empty map;
- slow travel;
- weak first five minutes;
- too many menus;
- expensive content production;
- combat without a strong meta loop;
- quests players do once;
- progression that feels generic;
- a game that is "good" but not clickable.

The stronger version is a **social progression / extraction / raiding game** with RPG flavor.

## 1.2 Recommended final concept

### PRISONER TO KING

Every player begins as a chained prisoner with no equipment and almost no status.

They must:

1. escape a dungeon;
2. steal or earn equipment;
3. defeat guards and minibosses;
4. carry loot to safety before dying;
5. upgrade a personal hideout;
6. unlock stronger kingdoms;
7. display trophies and rare gear;
8. raid dangerous public castles;
9. optionally attack rival player strongholds;
10. ascend from Prisoner -> Outlaw -> Warlord -> Lord -> King.

The game should feel like a combination of:

- immediate simulator-style progression;
- simple action combat;
- short extraction tension;
- collection;
- visible status;
- base building;
- social competition;
- live events.

But it should have its own identity and **must not become a clone of any existing Roblox experience**.

---

# 2. THE HIT TEST

No design can guarantee a hit.

The correct question is:

> Does the experience generate the behavioral signals that allow Roblox to keep testing it with increasingly larger audiences?

As of 2026, Roblox's own Discovery documentation emphasizes signals including:

- play-through rate after a recommendation impression;
- first-play bounce rate;
- play days per user over D1, D2–7, and D8–28;
- playtime per user;
- intentional co-play days;
- qualified play sessions;
- spend days;
- Robux spent.

Roblox describes recommendation distribution as an `explore -> expand` process: the system tests an experience with users, observes behavior, and can expand distribution if the cohort performs well.

**Implication:** this game should not be designed around "maximum monetization per player on day one." It should first create:

- strong click appeal;
- an instantly understandable fantasy;
- an interesting first minute;
- a meaningful reward in under 60 seconds;
- a clear next objective;
- reasons to play with friends;
- reasons to come back.

Sources used for the Roblox-specific discovery principles are listed at the end of this document.

---

# 3. THE ONE-SENTENCE PITCH

> **Escape prison with nothing, steal legendary gear, build your fortress, raid kingdoms, and rise from Prisoner to King.**

It communicates:

- starting weakness;
- progression;
- action;
- stealing/loot tension;
- building;
- social conflict;
- final status fantasy.

If the pitch cannot be understood by a young player in a few seconds, simplify it.

---

# 4. DESIGN PILLARS

Every major feature must support at least one of these pillars.

## Pillar A — Zero to King

The transformation must be visually dramatic.

At the beginning:

- torn prisoner clothes;
- wooden spoon / fists;
- no castle;
- no title;
- weak stats.

Later:

- ornate armor;
- legendary weapon;
- horse/mount;
- glowing aura;
- followers/guards;
- fortress;
- royal banner;
- King title.

Players should be able to see another player and instantly understand:

> "That person is much further than me. I want that."

## Pillar B — Steal, Escape, Bank

Loot should not simply appear in an inventory with no risk.

The key emotional sequence:

`SEE VALUABLE LOOT -> GET IT -> BECOME VULNERABLE -> ESCAPE -> BANK -> RELIEF`

The game becomes more exciting because obtaining the item is not the end. Getting it home matters.

## Pillar C — One More Upgrade

At almost all times, the player should be close to something.

Examples:

- 80/100 coins for a better sword;
- 4/5 keys for the vault;
- 2/3 armor fragments;
- 90% of the way to unlocking the next kingdom;
- one boss kill away from a guaranteed rare drop.

Never let progression feel infinitely distant.

## Pillar D — Public Flex

Important possessions should be visible.

Examples:

- equipped armor;
- weapon effects;
- titles;
- fortress cosmetics;
- throne;
- banners;
- rare captured trophies;
- leaderboard crown;
- boss trophies;
- mount;
- kill streak / bounty.

Players should create goals for one another just by existing in the same server.

## Pillar E — Friends Make It Better

Friends should be useful without being mandatory.

Examples:

- duo escape bonus;
- shared raid;
- revive;
- party chest;
- friend-only emotes;
- castle defense;
- group boss;
- coordinated extraction;
- bonuses for joining the same server.

## Pillar F — Short Sessions Work, Long Sessions Reward

A player should be able to get something meaningful in five minutes.

A long session should naturally turn into:

> "I'll do one more run."

---

# 5. TARGET PLAYER

## Primary design target

- Roblox-native players who understand upgrading, rarity, collecting, simple combat, and social flex.
- Approximate design age: 10–17.
- Mobile must be first-class, not a reduced PC version.

## Secondary target

- Older Roblox players who enjoy:
  - PvE grinding;
  - boss hunting;
  - action RPG progression;
  - collection;
  - leaderboards;
  - social raiding.

## The game should NOT require

- reading long dialogue;
- understanding medieval history;
- complex builds;
- precision Souls-like combat;
- long travel;
- voice chat;
- joining a clan;
- watching a tutorial video.

---

# 6. POSITIONING

## Do not market it as

> "A medieval open-world RPG."

That is generic.

## Market it as

> "Start as a prisoner. Become the king."

The transformation is the product.

### Better discovery language

- PRISONER TO KING
- Escape Prison, Become King
- Steal Weapons, Build a Castle
- Escape the King's Dungeon
- From Prisoner to Warlord

### Recommended title

# `PRISONER TO KING 👑`

Possible update suffixes:

- `[CASTLE RAIDS]`
- `[NEW KINGDOM]`
- `[DRAGON]`
- `[BOSS UPDATE]`

Do not overload the title with emojis.

---

# 7. THE CORE LOOPS

# 7.1 Five-second loop

Player sees:

- guard;
- loot;
- enemy;
- chest;
- breakable object;
- interactable door.

Player immediately knows what action is possible.

# 7.2 Thirty-second loop

`FIGHT / STEAL -> GET LOOT -> MOVE TOWARD SAFETY`

Example:

1. Hit guard.
2. Guard drops 14 coins and a key.
3. Key opens cellblock chest.
4. Chest contains uncommon sword.
5. Alarm begins.
6. Player runs to tunnel.
7. Loot is banked.

# 7.3 Two-minute loop

`ENTER DANGER -> COMPLETE OBJECTIVE -> EXTRACT -> UPGRADE`

Example:

- raid kitchen;
- defeat captain;
- take silver;
- escape;
- upgrade sword;
- see next objective.

# 7.4 Ten-minute loop

`RUN -> UPGRADE -> HARDER RUN -> BOSS / VAULT -> MAJOR UNLOCK`

# 7.5 20–40 minute session loop

`PROGRESS KINGDOM -> COMPLETE MILESTONE -> CUSTOMIZE HIDEOUT -> RAID / PLAY WITH FRIEND -> START NEXT GOAL`

# 7.6 Multi-day loop

`RETURN -> CLAIM / CHECK NEW OBJECTIVE -> DAILY CONTRACT -> NEW DROP / EVENT -> PROGRESS TITLE -> PREPARE FOR NEXT KINGDOM`

---

# 8. THE FIRST SESSION — MINUTE BY MINUTE

This is one of the most important parts of the entire game.

## 0:00–0:05

Spawn directly inside a dungeon cell.

Camera briefly frames:

- barred door;
- sleeping guard;
- key attached to guard;
- huge distant castle visible through window.

Text:

> **ESCAPE.**

No title screen.

No character creator.

No long cutscene.

## 0:05–0:20

Player receives an obvious interactive prompt:

> `Break Chain`

One input.

Large satisfying animation.

Chain snaps.

Sound effect.

Tiny XP/coin effect.

The player has already done something.

## 0:20–0:45

Tutorial points at a loose brick / spoon / wooden plank.

> `Grab a weapon.`

Player gets `Bent Spoon` or `Wooden Club`.

A weak guard is nearby.

## 0:45–1:15

First combat.

Guard has low HP.

Three to five hits maximum.

Big hit feedback.

Guard drops:

- coins;
- dungeon key;
- small random item.

The loot physically bursts out and is visible.

## 1:15–1:45

Player opens first locked door.

A chest is visible.

Chest contains a guaranteed visually better weapon.

Example:

`Rusty Shortsword — COMMON`

Equip animation.

Compare panel:

`+7 DAMAGE`

Do not make players study stat sheets.

## 1:45–2:30

Alarm.

Two weak guards appear.

Exit marker activates.

Player runs through short path.

The player learns:

> Loot is not safe until I escape.

## 2:30–3:00

Player reaches sewer tunnel.

Screen:

> `ESCAPED!`
>
> Loot secured.
>
> +120 Coins
>
> First Escape Bonus

Strong music sting.

## 3:00–4:00

Player enters hideout.

Three visually large upgrade choices:

- Weapon Rack
- Armor Stand
- Hideout Gate

The first upgrade is nearly free.

Player spends first money.

Something visibly changes in the world.

## 4:00–5:00

New objective:

> `BREAK INTO THE CASTLE AGAIN`
>
> Defeat the Captain.
>
> Reward: **RARE CHEST**

Player should already want to re-enter.

## 5:00–10:00

Second run introduces:

- optional path;
- stronger guard;
- one vault;
- first miniboss;
- first rare chance;
- another player nearby if possible.

## End-of-first-session objective

Before the average player leaves, they should have experienced at least:

- escape;
- combat;
- rarity;
- upgrade;
- visible progression;
- one locked future goal;
- one moment where another player appears richer/stronger.

---

# 9. WORLD STRUCTURE

Do **not** launch with a giant seamless world.

Use dense, readable kingdoms.

Each kingdom contains:

1. Safe hub / hideout.
2. Main castle or dangerous objective.
3. 2–4 side areas.
4. Boss.
5. Vault.
6. Unique loot family.
7. Extraction routes.
8. Unlock requirement.

## Launch kingdoms

### Kingdom 0 — The Dungeon

Purpose:

- onboarding only;
- first escape;
- first gear.

Visual identity:

- stone;
- chains;
- torches;
- sewage;
- rain outside.

### Kingdom 1 — Greenvale

The first actual loop.

Includes:

- village;
- castle;
- barracks;
- treasury;
- sewer;
- forest path.

Boss:

`Captain Bronn`

Rare drop:

`Captain's Greatsword`

### Kingdom 2 — Blackstone

Theme:

- dark fortress;
- lava forge;
- armored knights;
- siege weapons.

Boss:

`The Iron Warden`

Signature set:

`Blackstone Armor`

### Kingdom 3 — Frosthold

Theme:

- snow;
- icy castle;
- frozen prison;
- wolves;
- frost knights.

Boss:

`The White Knight`

Signature item:

`Frostbrand`

### Later kingdoms

- Desert Sultanate / Sun Citadel
- Haunted Kingdom
- Pirate Fortress
- Dragon Kingdom
- Sky Castle
- Imperial Capital

The game can become fantastical over time. "Medieval" should be a visual foundation, not a creativity prison.

---

# 10. PLAYER PROGRESSION

Use multiple progression axes so a player almost always has something advancing.

## 10.1 Power

Main combat effectiveness.

Derived from:

- weapon;
- armor;
- permanent training;
- skill mastery;
- optional companions later.

## 10.2 Rank

Suggested hierarchy:

1. Prisoner
2. Escapee
3. Thief
4. Outlaw
5. Raider
6. Mercenary
7. Knight
8. Warlord
9. Lord
10. King

Rank should unlock:

- areas;
- cosmetics;
- castle parts;
- badges;
- quests;
- increasingly impressive nameplate.

## 10.3 Kingdom progress

Each kingdom has a completion bar.

Example:

`GREENVALE CONTROL: 63%`

Progress comes from:

- guards defeated;
- vaults robbed;
- boss defeats;
- contracts;
- secret finds.

At 100%:

- major reward;
- access to next kingdom;
- visual conquest moment.

## 10.4 Collection

`ARMORY INDEX`

Every weapon has:

- silhouette before discovery;
- rarity;
- source;
- best roll;
- lore sentence;
- optional mastery level.

Collection is powerful because a player can keep playing even when raw power progression slows.

## 10.5 Castle progress

Persistent visual progression.

Level:

- camp;
- hideout;
- wooden fort;
- stone keep;
- castle;
- royal fortress.

---

# 11. COMBAT

The combat system must be satisfying but easy enough for mobile.

## P0 controls

### Primary attack

- tap/click;
- short combo;
- slight forward magnetism;
- no precision aim required for melee.

### Heavy attack

- hold or secondary button;
- slower;
- guard break;
- cooldown.

### Dash / dodge

- short movement burst;
- cooldown;
- readable button.

### Block

Optional for MVP.

Could be introduced later if the first build already feels good without it.

## Recommended MVP combat

Start with only:

- light attack combo;
- dash;
- one weapon special.

Depth should initially come from:

- enemy patterns;
- weapon identity;
- positioning;
- extraction risk.

Not from six combat buttons.

## Combat feel requirements

Every hit needs some combination of:

- hit sound;
- micro camera response;
- damage number;
- animation reaction;
- spark / slash VFX;
- knockback on finisher;
- enemy health response.

Combat cannot feel like two Roblox mannequins touching each other while numbers fall.

## Example baseline weapon math

These are starting balance values only.

### Fists

Damage: 5  
Attack interval: 0.65s

### Bent Spoon

Damage: 7  
Attack interval: 0.60s

### Rusty Sword

Damage: 12  
Attack interval: 0.70s

### Guard Sword

Damage: 18  
Attack interval: 0.72s

### Captain Greatsword

Damage: 32  
Attack interval: 0.95s  
Special: cone knockback

Damage progression should be easy to understand.

Do not create decimal-heavy stats like `13.74% armor penetration` in the early game.

---

# 12. ENEMIES

Each enemy needs one readable gameplay identity.

## Basic Guard

- walks toward player;
- normal sword combo;
- slow;
- tutorial enemy.

## Archer

- ranged pressure;
- weak up close.

## Shield Guard

- blocks frontal attacks;
- heavy attack or rear attack breaks defense.

## Hound

- fast;
- low HP;
- pressures escaping players.

## Captain

- miniboss;
- telegraphed heavy swing;
- calls one reinforcement.

## Warden

- boss;
- three attack patterns;
- phase at 50% HP;
- guaranteed chest.

Keep attack telegraphs exaggerated.

---

# 13. LOOT SYSTEM

Loot is one of the main dopamine systems.

## Rarities

Recommended:

- Common
- Uncommon
- Rare
- Epic
- Legendary
- Mythic

Do not launch with fifteen rarity tiers.

## Visual language

Common = plain shape.  
Uncommon = improved materials.  
Rare = distinct silhouette.  
Epic = VFX detail.  
Legendary = dramatic silhouette / effect.  
Mythic = immediately recognizable server-status item.

Do not rely only on UI colors.

## Loot sources

- guard drops;
- minibosses;
- vaults;
- secret rooms;
- kingdom completion;
- world events;
- bosses;
- raid rewards;
- achievement rewards.

## Pity / bad-luck protection

Long rare-drop grinds can destroy satisfaction.

Possible design:

Every boss kill adds `Luck Charge`.

At 100 charge:

> Next boss chest guarantees Rare+.

Never hide every progression system behind pure randomness.

---

# 14. EXTRACTION SYSTEM

This is the main differentiator from a normal simulator.

## Carried loot

When inside a danger zone, certain loot is `UNSECURED`.

UI:

`UNSECURED LOOT: 342`

If player escapes:

`342 -> BANKED`

If player dies:

Recommended MVP rule:

- player keeps equipped permanent gear;
- loses a percentage of unsecured currency;
- drops one temporary loot bag;
- does **not** lose months of progression.

The tension must be real without generating rage-quits.

## Extraction points

Different routes:

- sewer;
- broken wall;
- drawbridge;
- rooftop rope;
- hidden tunnel.

Some routes unlock through progression.

## Extraction decision

At a key moment the player should think:

> Do I leave now with what I have, or risk the vault?

This creates stories naturally.

---

# 15. ALARM / WANTED SYSTEM

The castle reacts to player behavior.

## Wanted levels

### 0 — Hidden
Few guards react.

### 1 — Suspected
Nearby guards investigate.

### 2 — Wanted
More guards spawn.

### 3 — Hunted
Captain / hounds.

### 4 — LOCKDOWN
Exits become harder.

### 5 — ROYAL BOUNTY
Big reward multiplier, elite enemies, server announcement.

The system turns ordinary grinding into dynamic difficulty.

## Risk multiplier

Higher wanted level can increase:

- coin drops;
- loot quality;
- XP;
- bounty points.

That makes danger voluntary.

---

# 16. THE HIDEOUT / CASTLE

The base is not a separate decorating game.

It has four jobs:

1. visualize progress;
2. protect/store loot;
3. provide useful upgrades;
4. create social flex.

## Early hideout modules

### Armory
Displays best weapons.

### Vault
Stores valuables.

### Training Yard
Permanent combat upgrades.

### Gate
Improves defense.

### Trophy Hall
Boss trophies.

### Throne Room
Late-game prestige.

## Design principle

Every upgrade should visibly change the 3D space.

Bad:

> `Vault Level 4 -> +15% capacity`

Better:

The tiny wooden chest becomes:

- reinforced chest;
- iron vault;
- stone treasury;
- royal gold room.

---

# 17. PLAYER CASTLE RAIDING

This is high-potential but **should not be P0**.

It adds enormous social value but also:

- griefing risk;
- balance problems;
- exploit incentives;
- offline protection design;
- matchmaking complexity.

Build it only after PvE extraction is fun.

## Recommended raid rules

- raids use a snapshot / instanced copy, not destructive real-time offline griefing;
- defender's core progression cannot be permanently deleted;
- attacker steals `raid tokens / exposed treasury`, not the owner's entire wealth;
- shield after being raided;
- optional defense layout;
- leaderboard season.

## Raid flow

1. Scout target.
2. Choose loadout.
3. Attack fortress.
4. Destroy gate / avoid defenses.
5. Reach treasury.
6. Escape before timer.
7. Receive raid chest.

## Why this is strong

Player-generated bases become content.

A developer can create 20 castle pieces and players generate thousands of configurations.

---

# 18. BOSSES

Bosses create:

- content milestones;
- rare drop motivation;
- YouTube/TikTok moments;
- group play;
- update hooks.

## Boss design template

Each boss should have:

- unique silhouette;
- 3 core attacks;
- one phase transition;
- one iconic drop;
- one trophy;
- one achievement;
- difficulty readable in under 30 seconds.

## Example: The Iron Warden

Attacks:

1. Hammer Slam
2. Chain Pull
3. Shockwave

50% phase:

- furnace ignites;
- arena hazards activate;
- Warden armor glows.

Drop:

`WARDEN HAMMER — LEGENDARY`

Trophy:

`Warden Helmet`

---

# 19. QUESTS / CONTRACTS

Avoid NPC walls of text.

Use contracts.

Examples:

> Steal 3 Guard Keys  
> Reward: 240 Coins

> Escape at Wanted Level 3  
> Reward: Rare Chest

> Defeat Captain Bronn  
> Reward: Captain Token

> Extract with 500+ unsecured gold  
> Reward: +1 Luck Chest

Contracts should push players toward interesting behavior, not chores.

---

# 20. DAILY AND WEEKLY SYSTEMS

Do not begin the game with seven different claim buttons.

## Daily contract

Three choices:

- Combat
- Extraction
- Social

Complete any one.

## Weekly kingdom bounty

Longer objective.

Example:

> Defeat 15 Captains  
> Complete 7 extractions  
> Open 3 vaults

Reward:

`Royal Chest`

## Login rewards

Use lightly.

The best reason to return should be gameplay, not a calendar.

---

# 21. EVENTS

Roblox provides an experience event/update system and can notify users about event starts. Roblox documentation currently notes that strong events typically highlight new/time-limited content and that selected events can receive extra platform exposure.

Use events to create spikes without making the base game dependent on FOMO.

Examples:

### DOUBLE BOUNTY WEEKEND

Wanted rewards x2.

### DRAGON ATTACK

Every 20 minutes a dragon attacks a kingdom.

Server must cooperate.

### KING'S TREASURY OPEN

Special vault accessible for 10 minutes.

### BANDIT INVASION

Players defend their hideouts.

### BLACK KNIGHT EVENT

Limited boss.

Events should generate a sentence players can message to friends:

> "Dragon is spawning — join."

---

# 22. SOCIAL SYSTEM

Roblox's current discovery signals include intentional co-play, so social design should not be an afterthought.

## Party

2–4 players.

Benefits:

- party markers;
- revive;
- shared objective credit;
- small party extraction bonus;
- boss queue.

Do not make solo progression inefficient.

## Friend bonus

First time playing with a friend each day:

`Friend Chest`

Avoid endlessly stacking multipliers for giant groups.

## Rescue mechanic

Downed party member has a few seconds to be revived.

This creates moments of cooperation.

## Spectacle

When someone pulls a Mythic:

> `ULVI FOUND THE CROWN OF ASH!`

Only announce genuinely rare events.

Too many global announcements become invisible.

---

# 23. PvP

PvP is not required for the first version.

If implemented:

- use specific PvP areas;
- keep onboarding safe;
- prevent high-level players from farming beginners;
- avoid full-loot PvP;
- create clear opt-in risk.

Possible PvP zone:

`THE OUTLAW ROAD`

Entering warns:

> `Other players can attack you here. Loot reward +50%.`

---

# 24. ECONOMY

The economy must have both faucets and sinks.

## Currencies

Launch with only two.

### Gold
Normal earnable currency.

Used for:

- basic upgrades;
- crafting;
- hideout;
- consumables.

### Crowns
Premium / rare event currency.

Used carefully.

Do not create five currencies at launch.

## Gold sources

- guards;
- contracts;
- extraction;
- bosses;
- vaults;
- events.

## Gold sinks

- permanent upgrades;
- hideout construction;
- crafting;
- rerolls;
- repairs only if repairs are not annoying;
- cosmetic prestige.

## Inflation control

Do not solve inflation by making new prices absurdly high.

Use:

- prestige sinks;
- collection;
- rotating cosmetics;
- crafting;
- high-end base upgrades.

---

# 25. EXAMPLE EARLY ECONOMY

These are tuning placeholders, not final numbers.

| Action | Gold |
|---|---:|
| Basic guard | 8–15 |
| First chest | 50 |
| First escape bonus | 100 |
| Captain | 80 |
| Small vault | 150 |
| First sword upgrade | 120 |
| Armor upgrade | 250 |
| Hideout Level 2 | 500 |
| Greenvale completion | 1,500 |

Early players should upgrade quickly.

The game can slow later.

Do not make the first meaningful upgrade require 20 minutes.

---

# 26. MONETIZATION PRINCIPLES

The correct monetization philosophy:

> Sell excitement, identity, convenience, customization, and optional acceleration — not relief from intentionally bad game design.

Roblox currently supports monetization mechanisms including passes, developer products, subscriptions, private servers, and regional/managed pricing. Regional prices can vary by economic location, so any in-game store should retrieve prices dynamically rather than hard-code Robux values.

## Never do

- ten purchase popups in the first minute;
- fake "limited" countdowns;
- make free combat miserable;
- direct purchase prompt immediately after death every time;
- paywall the second kingdom;
- sell an unbeatable PvP weapon;
- force players to buy inventory space before the game is proven fun.

---

# 27. MONETIZATION STACK

## P0 launch monetization

Keep it small.

### Starter Bundle — Developer Product

Triggered after first successful extraction, not at spawn.

Possible contents:

- cosmetic prisoner cape;
- small Gold amount;
- one Rare chest;
- temporary 2x extraction Gold for 10 minutes.

Suggested default price test:
`49–99 Robux`

Use price testing and managed pricing rather than assuming one universal optimum.

### Gold Packs — Developer Products

Repeated purchase.

Examples:

- Small
- Medium
- Large

But Gold should not be the store's hero product.

### Lucky Chest — Developer Product

Can be purchased repeatedly.

However:

- publish odds clearly in accordance with Roblox policies;
- keep earnable equivalents;
- do not make paid chests required for competitive viability.

## P1 monetization

### VIP Pass

Benefits:

- VIP name tag;
- exclusive castle banner;
- extra daily contract reroll;
- cosmetic aura;
- small non-PvP quality-of-life bonus.

### Extra Loadout Slot

Convenience.

### Mount Skins

Cosmetic.

### Execution / Finisher Animations

Cosmetic.

### Emote Pack

Social flex.

## P2 monetization

### Royal Club Subscription

Only after a meaningful engaged audience exists.

Possible recurring benefits:

- monthly Royal cosmetic;
- extra contract slot;
- rotating castle décor;
- premium cosmetic track;
- small daily currency grant.

Subscription should make fans feel rewarded, not make non-subscribers feel second-class.

---

# 28. REWARDED VIDEO ADS

Roblox supports rewarded video ads for eligible experiences/users.

If used:

Good placements:

- optional bonus chest;
- reroll contract;
- revive in PvE;
- bonus gold after extraction.

Bad placement:

> Watch ad or lose everything.

The user should initiate the ad voluntarily and understand the reward.

Roblox recommends using experiments to observe engagement/retention impact before full rollout.

---

# 29. STORE UX

Do not open the store on spawn.

Store discovery moments:

- after first win;
- near cosmetic armory;
- after seeing another player's interesting appearance;
- from normal menu.

Tabs:

1. Featured
2. Cosmetics
3. Boosts
4. Gold
5. VIP

The first screen should not look like a casino wall.

---

# 30. RETENTION ARCHITECTURE

Retention should come from stacked horizons.

## Next 30 seconds
Kill guard / open chest.

## Next 3 minutes
Escape.

## Next 10 minutes
Defeat Captain.

## Next session
Finish Greenvale.

## Next few days
Get Legendary set.

## Next week
Upgrade fortress / complete event.

## Long-term
Reach King / collect Mythics / seasonal prestige.

A player should always see:

- one near goal;
- one medium goal;
- one aspirational goal.

---

# 31. RETURN TRIGGERS

Good reasons to return:

- unfinished kingdom;
- boss pity bar almost full;
- new daily contract;
- castle upgrade ready;
- friend activity;
- limited event;
- new content update;
- leaderboard season;
- collection gap.

For opted-in eligible players, Roblox provides experience notification functionality. Use it for meaningful triggers, not spam.

Examples:

> `Your Royal Vault upgrade is ready.`

> `The Dragon Event starts now.`

> `A new kingdom is open.`

---

# 32. VIRALITY

Do not rely on "please share the game."

Create moments people naturally want to show.

## Viral moment types

### 1. Huge luck
Player pulls Mythic.

### 2. Close escape
1 HP extraction.

### 3. Betrayal / theft
Player takes vault before another group.

### 4. Power transformation
Prisoner -> full legendary king.

### 5. Physics comedy
Guard flies off bridge.

### 6. Giant world event
Dragon attacks castle.

### 7. Rare server event
Golden carriage enters castle.

### 8. Social flex
Ridiculous throne room.

## Content creator requirement

Every update should include at least one mechanic that can produce a 10–20 second vertical clip without explanation.

---

# 33. THUMBNAIL STRATEGY

Roblox recommends 16:9 thumbnails, ideally 1920×1080.

Do not make thumbnails that look like generic AI fantasy art with 25 characters.

The image must communicate a simple before/after story at small size.

## Thumbnail A — Transformation

Left:

- weak chained prisoner;
- terrified face;
- dungeon.

Right:

- same avatar as huge armored king;
- glowing sword;
- castle.

Center:

`PRISONER -> KING`

## Thumbnail B — Theft

Player runs from guards carrying glowing Legendary sword.

Huge castle behind.

## Thumbnail C — Raid

Tiny player attacking giant castle treasury.

Gold flying out.

## Thumbnail D — Rare loot

Huge Mythic weapon in foreground.

Player reaching for it.

## Thumbnail rule

At phone size the player should still identify:

- character;
- object;
- action.

---

# 34. ICON STRATEGY

The icon should be identifiable in less than one second.

Recommended:

- half prisoner face / half king helmet;
- crown silhouette;
- dark dungeon vs gold palace contrast.

Do not use small text.

---

# 35. DESCRIPTION

Short version:

> **Start with nothing. Escape the dungeon. Steal weapons. Raid castles. Become KING. 👑**
>
> ⚔️ Fight guards & bosses  
> 💰 Escape with stolen loot  
> 🏰 Build your fortress  
> 👑 Collect legendary gear  
> 🤝 Raid with friends  
>
> New kingdoms and events regularly.

Do not write three paragraphs of lore above the gameplay explanation.

---

# 36. ART DIRECTION

## Style

Stylized medieval fantasy.

Not realistic.

Goals:

- strong silhouettes;
- chunky readable weapons;
- exaggerated architecture;
- good performance;
- visually understandable enemies.

## Palette philosophy

Each kingdom has a unique palette.

Examples:

- Greenvale: green / stone / warm torchlight
- Blackstone: charcoal / orange furnace
- Frosthold: white / blue
- Sun Citadel: sand / red / gold

Color should help navigation.

## Scale

Slightly oversized:

- doors;
- weapons;
- treasure;
- bosses;
- interactables.

Roblox players often view on smaller screens. Important objects need visual presence.

---

# 37. AUDIO

Sound creates perceived quality cheaply.

Need:

- satisfying hit sound;
- weapon equip;
- loot rarity reveal;
- chest open;
- alarm bell;
- footsteps;
- successful extraction;
- rank-up fanfare;
- boss music;
- rare drop sound.

The Mythic drop sound must be recognizable.

---

# 38. MOBILE-FIRST UI

Every mechanic should be designed for thumbs.

## HUD

Keep to:

Top:

- objective;
- wanted level.

Bottom:

- attack;
- dash;
- special.

Side:

- bag/loot;
- menu.

Avoid 14 permanent buttons.

## Rules

- buttons large enough for mobile;
- critical text readable at phone size;
- no tiny inventory grids;
- minimize dragging;
- use tap equip;
- tooltips only when needed;
- controller navigation later tested explicitly.

---

# 39. ONBOARDING RULES

Do not explain before action.

Bad:

> "Welcome to the Kingdom of Atheria. For centuries..."

Good:

> `BREAK YOUR CHAINS`

Then:

> `STEAL THE KEY`

Then:

> `ESCAPE`

Learning sequence:

`DO -> REWARD -> NEXT`

Not:

`READ -> READ -> READ -> MAYBE DO`

---

# 40. ACCESSIBILITY / USABILITY

At minimum:

- readable text;
- icon + text for important states;
- avoid critical information encoded only by color;
- adjustable camera sensitivity if appropriate;
- reduced screen shake setting;
- music/SFX controls;
- avoid excessive flashing;
- clear touch targets.

---

# 41. PERFORMANCE

Performance is a growth feature.

A beautiful game that loads slowly or runs poorly on mobile loses users before its systems matter.

Roblox's current performance documentation recommends instance streaming for larger worlds because it can improve join time, memory footprint, and frame rate.

## Technical performance rules

- enable `StreamingEnabled` for larger maps after compatibility testing;
- keep collision geometry simple;
- reuse meshes;
- avoid thousands of unnecessary moving parts;
- pool frequently created effects;
- server does not simulate decorative physics unnecessarily;
- use LOD where practical;
- measure memory and frame time on actual low/mid mobile hardware;
- avoid loading every kingdom's assets at spawn;
- keep onboarding area especially light.

## Target mindset

First 60 seconds should never be delayed because the game wants to load a dragon from Kingdom 8.

---

# 42. ROBLOX TECH ARCHITECTURE

Recommended principle:

> Client asks. Server decides.

Anything involving:

- damage;
- currency;
- loot;
- purchase grants;
- inventory;
- extraction;
- boss rewards;
- rank progression;

must be authoritative on the server.

## Proposed folder structure

```text
ReplicatedStorage/
  Shared/
    Config/
      WeaponConfig.lua
      EnemyConfig.lua
      EconomyConfig.lua
      KingdomConfig.lua
      LootConfig.lua
      ProductConfig.lua
    Types/
    Utils/
    Remotes/

ServerScriptService/
  Services/
    PlayerDataService.lua
    CombatService.lua
    EnemyService.lua
    LootService.lua
    ExtractionService.lua
    EconomyService.lua
    ProgressionService.lua
    QuestService.lua
    CastleService.lua
    AnalyticsService.lua
    PurchaseService.lua
    AntiExploitService.lua
  Bootstrap.server.lua

StarterPlayer/
  StarterPlayerScripts/
    Controllers/
      CombatController.lua
      InteractionController.lua
      CameraController.lua
      UIController.lua
      AudioController.lua

StarterGui/
  HUD/
  Inventory/
  Store/
  Results/
  Menus/

Workspace/
  Zones/
  NPCSpawns/
  ExtractionPoints/
  Interactables/
```

Do not make one 5,000-line `MainScript`.

---

# 43. PLAYER DATA MODEL

Example conceptual schema:

```lua
PlayerProfile = {
    Version = 1,

    Currencies = {
        Gold = 0,
        Crowns = 0,
    },

    Progression = {
        Rank = 1,
        XP = 0,
        CurrentKingdom = "Greenvale",
        KingdomProgress = {},
    },

    Inventory = {
        Weapons = {},
        Armor = {},
        Consumables = {},
    },

    Equipped = {
        WeaponId = nil,
        ArmorIds = {},
    },

    Collection = {
        DiscoveredWeapons = {},
        DiscoveredArmor = {},
        BossesDefeated = {},
    },

    Castle = {
        Level = 1,
        Upgrades = {},
        Cosmetics = {},
    },

    Quests = {
        Daily = {},
        Weekly = {},
    },

    Meta = {
        FirstJoinUnix = 0,
        LastJoinUnix = 0,
        TutorialComplete = false,
        TotalEscapes = 0,
        TotalDeaths = 0,
    },
}
```

Use schema versioning and migrations.

Never assume stored player data will remain in the first schema forever.

---

# 44. REMOTE SECURITY

Exploiters must not be able to tell the server:

> "I dealt 999999 damage."

Client sends an intent:

> "I attacked with weapon X."

Server verifies:

- weapon is equipped;
- cooldown valid;
- player alive;
- target plausible;
- distance valid;
- state valid;
- damage calculated by server.

Same for loot:

Bad:

`ClaimLoot(player, 1000000)`

Good:

`PickupLoot(lootInstanceId)`

Server verifies the loot exists and belongs to that run.

## Rate limits

Every remote should have reasonable server-side rate limiting.

Repeated invalid requests should:

- be ignored;
- be logged;
- potentially increase exploit suspicion.

Do not immediately kick on one false positive.

---

# 45. COMBAT SERVER FLOW

Conceptual:

1. Client receives input.
2. Client immediately plays local animation for responsiveness.
3. Client sends attack intent.
4. Server validates combat state.
5. Server performs authoritative hit detection / validates target.
6. Server calculates damage.
7. Server applies damage.
8. Server replicates result.
9. Clients play hit VFX.

This balances:

- responsiveness;
- security.

---

# 46. NPC ARCHITECTURE

Do not run expensive AI logic every frame for every NPC.

Suggested state machine:

```text
Idle
Patrol
Investigate
Chase
Attack
Stunned
Return
Dead
```

Update rates can vary by relevance/distance.

Use spawn managers.

Do not keep 300 active guards simulating across an empty map.

---

# 47. LOOT INSTANCE MODEL

Every dropped loot object should have a server-generated identifier.

Example:

```lua
LootDrop = {
    Id = "server_generated_id",
    ItemId = "guard_sword",
    Rarity = "Uncommon",
    OwnerRule = "Public",
    SpawnTime = os.time(),
    Secured = false,
}
```

When picked up:

- validate distance;
- mark claimed atomically;
- add to run inventory;
- destroy world object.

Prevent duplicate pickup exploits.

---

# 48. EXTRACTION STATE

Run loot should be separated from permanent inventory.

Example:

```lua
SessionRun = {
    UnsecuredGold = 0,
    UnsecuredItems = {},
    WantedLevel = 0,
    RunStart = 0,
}
```

On extraction:

- validate extraction zone;
- transfer allowed rewards to profile;
- log economy events;
- reset run.

On death:

- apply configured loss rule;
- reset.

---

# 49. PURCHASE PROCESSING

For Roblox Developer Products, purchase grants must be handled through proper server receipt processing and made idempotent.

Principle:

> A receipt should never grant twice because of retries.

Store a processed purchase record or otherwise implement reliable receipt handling according to Roblox's current MarketplaceService/ProcessReceipt guidance.

Do not put entitlement logic purely on the client.

---

# 50. DYNAMIC PRICES

Roblox supports managed/regional pricing.

Therefore:

Bad:

```lua
PriceLabel.Text = "99 R$"
```

Good:

Retrieve current user-specific product information and display the price returned by Roblox.

This prevents UI showing a price that differs from the purchase prompt.

---

# 51. ANALYTICS — NON-NEGOTIABLE

The game should not be launched without events.

Roblox supports custom analytics events for adoption, user behavior, and core loops.

Track the funnel.

## Core funnel events

1. `FirstSpawn`
2. `ChainsBroken`
3. `FirstWeaponPicked`
4. `FirstGuardHit`
5. `FirstGuardKilled`
6. `FirstLootPicked`
7. `FirstChestOpened`
8. `FirstEscapeStarted`
9. `FirstEscapeCompleted`
10. `FirstUpgradePurchased`
11. `SecondRunStarted`
12. `FirstCaptainKilled`
13. `FirstRareObtained`
14. `FirstFriendParty`
15. `StoreOpened`
16. `PurchasePromptShown`
17. `PurchaseCompleted`
18. `SessionEnd`

## Core-loop events

- RunStarted
- RunEnded
- ExtractionSuccess
- ExtractionFailed
- LootValueExtracted
- WantedLevelReached
- BossStarted
- BossCompleted
- VaultOpened
- Death
- UpgradeBought

## Custom fields

Useful dimensions:

- kingdom;
- player rank;
- device category if available in platform analytics;
- weapon;
- run duration bucket;
- acquisition source where available;
- new vs returning;
- party vs solo.

Do not put personal information into analytics payloads.

---

# 52. ANALYTICS QUESTIONS

Every event should answer a question.

### Question
Where do new players quit?

Need:
onboarding funnel.

### Question
Does extraction create tension or frustration?

Need:
success rate, run duration, death point, repeat-run rate.

### Question
Which kingdom causes retention loss?

Need:
kingdom entry and completion.

### Question
Are players social?

Need:
party starts, intentional friend play, co-op boss runs.

### Question
Does the store hurt engagement?

Need:
store opens, prompts, purchases, session behavior.

### Question
Which weapons are fun?

Need:
equip frequency, kills, run usage, retention correlations.

---

# 53. INTERNAL MVP SUCCESS TARGETS

These are **product testing targets**, not claimed official Roblox-wide benchmarks.

Use Creator Analytics' similar-experience benchmarks as the real comparison once enough data exists.

Suggested early gates:

## Funnel

- Chains broken: >90% of spawned users
- First weapon: >85%
- First guard kill: >75%
- First successful extraction: >60%
- First upgrade: >50%
- Second run started: >45%

## Experience

Aim for:

- low first-play bounce;
- median first meaningful reward under 60 seconds;
- first extraction around 2–4 minutes;
- average first session long enough to experience two loops.

## Retention working targets

Initial ambition:

- D1: 20%+;
- D7: 7%+;
- improve toward the benchmark for comparable successful experiences.

Again: **do not optimize blindly to these numbers. Compare against Roblox's live similar-experience benchmarks and cohort trends.**

---

# 54. DIAGNOSIS MATRIX

## High click, high bounce

Problem:

Packaging works; game opening fails.

Check:

- load time;
- confusing spawn;
- weak first action;
- misleading thumbnail.

## Low click, good retention

Problem:

Game is good; packaging is bad.

Change:

- title;
- icon;
- thumbnail;
- one-line promise.

Do not redesign the game first.

## Good D1, weak D7

Problem:

Initial loop works; depth is weak.

Add/improve:

- collection;
- kingdoms;
- weekly goals;
- social system;
- progression variety.

## Strong playtime, weak return days

Problem:

Players binge once but have no reason to return.

Add:

- unfinished progression;
- meaningful daily content;
- events;
- social obligations;
- collection horizon.

## Good engagement, weak monetization

Do not immediately add paywalls.

Test:

- store visibility;
- starter bundle timing;
- cosmetic desirability;
- value communication;
- price optimization.

---

# 55. A/B TEST ROADMAP

Change one important variable at a time when possible.

## Test 1 — Thumbnail

A: Prisoner -> King  
B: Running with stolen sword  
C: Giant boss

Measure:

play-through.

## Test 2 — First reward

A: sword at 45 sec  
B: sword at 90 sec

Measure:

bounce, tutorial completion.

## Test 3 — Extraction loss

A: lose 25% unsecured Gold  
B: lose 50% unsecured Gold

Measure:

repeat runs, session length, rage quit proxy.

## Test 4 — Starter offer

A: after first extraction  
B: after first boss

Measure:

purchase rate plus retention.

## Test 5 — Party incentive

A: +10% Gold  
B: party chest after extraction

Measure:

co-play and retention.

---

# 56. CLOSED ALPHA

Do not send the first ugly build to thousands of players.

First test with roughly 20–50 people.

Observe them without teaching.

Critical rule:

If you need to stand next to a player and explain what to do, the onboarding failed.

Ask after play:

1. What were you trying to do?
2. What part was fun?
3. What was confusing?
4. What did you want next?
5. Would you play again tomorrow? Why?

Do not ask:

> "Did you like my game?"

That produces useless politeness.

---

# 57. PAID TRAFFIC TEST

Once the first five minutes are polished:

Use a modest Roblox acquisition test.

The purpose is **not profit**.

The purpose is to buy information.

Test multiple creatives.

Observe separately:

- impression -> play;
- first-play bounce;
- first-session funnel;
- session duration;
- next-day return.

Do not scale ad spend because one thumbnail has a good CTR if users immediately leave.

---

# 58. LAUNCH PHASES

## Phase A — Graybox

Only:

- cell;
- guard;
- combat;
- loot;
- exit.

Question:

> Is hitting, stealing, and escaping fun?

## Phase B — Vertical Slice

Add:

- polished dungeon;
- 5 weapons;
- one miniboss;
- hideout;
- first progression.

Question:

> Do players voluntarily start a second run?

## Phase C — MVP

Add:

- Greenvale;
- collection;
- basic contracts;
- analytics;
- monetization;
- mobile polish.

Question:

> Do strangers retain?

## Phase D — Social expansion

Add:

- parties;
- friend systems;
- boss co-op;
- social rewards.

Question:

> Do players bring and join friends?

## Phase E — Castle meta

Add:

- fortress;
- raid system;
- seasonal leaderboard.

Question:

> Does player-generated competition create long-term retention?

---

# 59. EXACT P0 MVP

Do not let Claude expand scope beyond this without instruction.

## World

- 1 dungeon;
- 1 castle zone;
- 1 hideout;
- 1 extraction route plus 1 unlockable shortcut.

## Enemies

- Basic Guard
- Archer
- Shield Guard
- Captain boss

## Weapons

- Fists
- Bent Spoon
- Rusty Sword
- Guard Sword
- Axe
- Captain Greatsword

## Systems

- basic combat;
- enemy AI;
- health/death;
- loot;
- rarity;
- unsecured run inventory;
- extraction;
- Gold;
- weapon inventory;
- equip;
- one upgrade shop;
- basic rank;
- tutorial;
- analytics events;
- save/load;
- one Developer Product;
- mobile controls.

## NOT P0

- player trading;
- guilds;
- full castle builder;
- pets;
- mounts;
- crafting tree;
- PvP;
- player raids;
- 10 kingdoms;
- procedural dungeons;
- clans;
- global marketplace.

---

# 60. P1 BACKLOG

After MVP loop proves itself:

- 2nd kingdom;
- armor;
- more bosses;
- daily contracts;
- parties;
- friend rewards;
- collection index;
- more extraction routes;
- wanted system depth;
- castle visual progression;
- VIP;
- cosmetics;
- improved thumbnails;
- events.

---

# 61. P2 BACKLOG

Only after retention justifies complexity:

- player castle raids;
- seasons;
- clans;
- leaderboard;
- mounts;
- crafting;
- trading;
- world bosses;
- subscriptions;
- prestige / ascension;
- advanced PvP.

---

# 62. ASCENSION / PRESTIGE

Potential long-term system:

Once player becomes King:

> `ABDICATE & BEGIN A NEW DYNASTY`

Reset some power progression in return for:

- Crown level;
- permanent cosmetic;
- new banner;
- new starting perk;
- special kingdom access.

Do not introduce prestige before players have meaningful content to prestige through.

---

# 63. COLLECTION DESIGN

The collection screen should create desire.

Example:

```text
GREENVALE ARMORY
12 / 20 FOUND

[✓] Rusty Sword
[✓] Guard Sword
[?] ???
[✓] Captain Axe
[🔒] GOLDEN ROYAL BLADE
    Source: Royal Vault
```

Mystery is useful.

But once the player has tried enough, provide hints.

---

# 64. WEAPON IDENTITY

Do not create 50 swords with only different damage numbers.

Families:

### Sword
Balanced.

### Axe
Slow, strong, guard break.

### Spear
Range.

### Dagger
Fast.

### Hammer
Knockback.

### Bow
Ranged.

### Legendary weapons
One signature mechanic each.

Example:

`Frostbrand`
Every fifth hit releases ice wave.

Simple enough to understand immediately.

---

# 65. POWER CREEP

New kingdom equipment should not make old Mythics instantly worthless.

Possible solutions:

- weapon mastery;
- upgrade tiers;
- transmog;
- set collection bonuses;
- unique effects;
- horizontal utility.

A beloved weapon can remain cosmetically or mechanically interesting.

---

# 66. DEATH

Death must create:

- tension;
- lesson;
- quick retry.

Not:

- 30-second respawn;
- huge punishment;
- lost permanent legendary;
- walk two minutes back.

Target:

Player should be making a new decision within a few seconds after death.

Death screen:

> `CAPTURED!`
>
> Unsecured Gold lost: 84
>
> Best Loot Saved: Rusty Sword
>
> `TRY AGAIN`

Optional:

`Recover Loot` objective can create a run-back loop later.

---

# 67. FAIL-SOFT DESIGN

Whenever possible, failure still progresses something.

On failed extraction:

- small XP;
- quest progress;
- boss knowledge;
- pity meter;
- discovered map shortcut.

This reduces rage without removing tension.

---

# 68. PLAYER MOTIVATION TYPES

The game should satisfy several motivations.

## Achiever
Ranks, bosses, completion.

## Collector
Weapons, armor, trophies.

## Competitor
Bounty, raids, leaderboard.

## Socializer
Parties, castle visits, emotes.

## Explorer
Secrets, hidden routes.

## Creator/customizer
Castle appearance later.

Do not rely only on grinding damage.

---

# 69. SECRETS

Secrets improve content creation and exploration cheaply.

Examples:

- loose dungeon brick;
- hidden sewer;
- fake castle wall;
- ghost knight;
- secret weapon room;
- rare wandering merchant.

Some secrets can rotate by server.

---

# 70. SERVER EVENTS

Use server-wide moments.

Examples:

> `THE ROYAL VAULT OPENS IN 60s`

> `A GOLDEN CARRIAGE HAS ENTERED GREENVALE`

> `THE DRAGON HAS AWAKENED`

This temporarily aligns player goals and makes servers feel alive.

---

# 71. LIVE OPS CALENDAR — EXAMPLE FIRST MONTH

Do not promise all this before MVP quality is proven.

## Week 1
Launch.
Fix onboarding and critical balance only.

## Week 2
Mini update:
- 2 weapons;
- secret vault;
- balance fixes.

## Week 3
Event:
`Double Bounty Weekend`

## Week 4
Content update:
`Blackstone`
- new fortress;
- boss;
- armor;
- 6 weapons.

Content cadence should be sustainable.

A game that needs 20 new weapons every week is badly designed.

---

# 72. UPDATE DESIGN RULE

Every major update should ideally contain:

1. something for new players;
2. something for returning midgame players;
3. one aspirational item;
4. one social/viral moment;
5. one reason to return during the update period.

---

# 73. LOCALIZATION

Roblox currently supports automatic translation tools that can capture and translate game strings.

Design for localization from day one:

- centralize UI text;
- no text baked into critical images;
- short phrases;
- avoid slang-heavy tutorial text;
- test layout expansion;
- localize experience metadata where useful.

Initial priority languages can be decided from analytics rather than guesses.

---

# 74. SAFETY / PLATFORM FIT

Because Roblox has many young users:

- use platform chat and moderation systems;
- do not encourage off-platform contact inside gameplay;
- do not create gambling-like presentation around paid randomized items without checking current Roblox rules;
- keep violence stylized;
- avoid gore;
- review age/content maturity settings;
- review current Community Standards before release and major updates.

---

# 75. ANTI-EXPLOIT PRIORITY LIST

Protect in this order:

1. currency;
2. inventory;
3. purchases;
4. damage;
5. loot duplication;
6. teleport/speed abuse affecting extraction;
7. boss reward duplication;
8. raid results.

## Detection examples

- impossible movement delta;
- attack faster than configured cooldown;
- pickup from impossible distance;
- item ID not existing;
- duplicate claim;
- boss reward without boss participation.

Server validation is more important than flashy detection.

---

# 76. DATA SAFETY

Need:

- autosaves;
- save on major milestones;
- save on graceful leave where possible;
- retry with backoff;
- session-lock strategy;
- version migrations;
- backup/migration awareness.

Never trust a single save call at PlayerRemoving as the entire persistence strategy.

---

# 77. MATCHMAKING / PLACE STRUCTURE

MVP can live in one Roblox place.

Later, consider separate places only if necessary.

Possible future universe:

- Main Kingdoms
- Raid Instance
- Event Arena

Separate places add complexity:

- teleport failures;
- state transfer;
- player fragmentation.

Do not split the MVP prematurely.

---

# 78. CAMERA

Default third person.

Combat camera should:

- preserve situational awareness;
- not zoom too close;
- avoid excessive lock-on complexity.

Optional soft target assist:

- prioritize enemy near crosshair/character;
- short range;
- mobile friendly.

---

# 79. INTERACTION LANGUAGE

Use the same verbs repeatedly.

Preferred:

- STEAL
- BREAK
- OPEN
- ESCAPE
- UPGRADE
- RAID
- CLAIM

Do not call the same action:

- "Acquire"
- "Loot"
- "Collect"
- "Redeem"
- "Take"

in five different menus unless the meanings differ.

Consistency improves onboarding.

---

# 80. UI INFORMATION HIERARCHY

At any moment answer:

1. What should I do?
2. What will I get?
3. Am I in danger?
4. What am I close to unlocking?

Example HUD:

```text
[ WANTED: III ]

STEAL THE CAPTAIN'S KEY
Reward: RARE CHEST

Unsecured: 482 Gold
```

Clear.

---

# 81. REWARD PRESENTATION

The same 100 Gold can feel weak or satisfying depending on presentation.

Small reward:

- quick popup.

Medium reward:

- sound + burst.

Rare reward:

- short slow reveal;
- item rotates;
- rarity sound.

Mythic reward:

- dramatic but not 10 seconds unskippable every time.

Players should never feel trapped inside reward animations.

---

# 82. TUTORIAL COPY — PROPOSED

Use minimal copy.

### Spawn
`BREAK YOUR CHAINS`

### Weapon
`GRAB A WEAPON`

### Guard
`STEAL THE KEY`

### Door
`UNLOCK THE CELLBLOCK`

### Loot
`TAKE THE SWORD`

### Alarm
`RUN!`

### Extraction
`ESCAPE WITH YOUR LOOT`

### Hideout
`UPGRADE YOUR ARMORY`

### Next objective
`THE CAPTAIN HAS BETTER GEAR`

That is almost the entire tutorial.

---

# 83. NARRATIVE

Lore is optional flavor.

Core narrative:

The player was imprisoned by a corrupt crown.

Escaping begins a rise from nobody to ruler.

Do not force story.

Lore can live in:

- item descriptions;
- boss intros;
- environment;
- secret rooms;
- optional dialogue.

---

# 84. NPC PERSONALITY

Memorable NPCs make clips and fan culture.

Examples:

### Weak Guard
Overconfident.

### Merchant
Always appears in questionable places.

### Prison Cook
Secretly helps escapees.

### Captain Bronn
Recurring rival who upgrades after each defeat.

A recurring rival could become more memorable than five disposable bosses.

---

# 85. THE RIVAL SYSTEM — OPTIONAL HIGH-POTENTIAL FEATURE

A named NPC rival can remember progression conceptually.

Example:

`Captain Bronn`

First encounter:
Guard captain.

Later:
Elite knight.

Later:
Royal general.

Later:
Corrupted king.

This creates continuity and gives updates a recognizable face.

---

# 86. BOUNTIES

High-performing players can voluntarily become marked.

Example:

After reaching Wanted V:

`ROYAL BOUNTY: 2,400`

Other players in PvP-enabled contexts may pursue them later.

MVP can keep bounty as PvE only.

---

# 87. LEADERBOARDS

Do not make only one lifetime leaderboard where old whales permanently dominate.

Better:

- weekly extractions;
- weekly bounty;
- fastest boss;
- seasonal raids.

Lifetime stats can exist but should not be the main competitive surface.

---

# 88. BADGES / ACHIEVEMENTS

Examples:

- First Escape
- Wanted V
- No Damage Captain
- 100 Extractions
- First Legendary
- King
- Escape with 10,000 Gold
- Defeat boss with friend

Achievements should occasionally unlock cosmetics.

---

# 89. COSMETICS

Cosmetics can become a major monetization and status layer.

Categories:

- capes;
- crown;
- weapon skins;
- trails;
- kill effects;
- extraction effects;
- banners;
- castle themes;
- emotes;
- throne;
- armor transmog.

Players should be able to look powerful without paid cosmetics being stronger.

---

# 90. USER-GENERATED STORIES

The best Roblox systems create sentences.

Examples:

> "I got a Legendary but died one meter before the sewer."

> "We hit Wanted V and the whole castle chased us."

> "My friend distracted the Warden while I stole the vault."

> "A Mythic dropped on my first boss."

> "We raided a max-level fortress."

If a system cannot generate stories, it may still be useful — but story-generating systems are unusually valuable.

---

# 91. THE "ONE SCREENSHOT" TEST

Take a random gameplay screenshot.

Can someone identify:

- medieval fantasy;
- who the player is;
- what is dangerous;
- what is valuable?

If every wall/floor/enemy has equal visual weight, redesign the scene.

---

# 92. THE "NO SOUND" TEST

Turn sound off.

Can the player understand:

- hit landed;
- damage occurred;
- enemy is attacking;
- loot is rare;
- extraction succeeded?

If not, visual feedback is insufficient.

Then do the reverse:

Close your eyes during rewards and test whether audio communicates importance.

---

# 93. THE "MOM WATCHING" TEST

Show ten seconds to someone who does not play Roblox.

Can they explain the basic fantasy?

Good:

> "You're escaping a castle and stealing stuff."

Bad:

> "I don't know, some medieval person is walking around."

---

# 94. WHAT WILL KILL THIS GAME

## 1. Building too much before testing

Ten kingdoms with a weak first minute = failure at scale.

## 2. Generic simulator grind

If combat is only "click NPC with bigger number," players have seen it.

## 3. Generic RPG complexity

Stats, crafting, skill trees, classes, quests, professions at spawn.

## 4. Slow onboarding

Lobby -> menu -> dialogue -> character creator -> tutorial.

No.

## 5. Empty map

Travel is not content.

## 6. Harsh full-loot loss

Young casual players can quit after one painful loss.

## 7. Pay-to-win PvP

Destroys trust.

## 8. No social reason

Single-player grind inside a multiplayer platform wastes a major advantage.

## 9. Weak visual identity

"Medieval Roblox game #583."

## 10. No analytics

Then every update becomes opinion.

---

# 95. WHAT COULD MAKE IT BREAK OUT

The strongest version has five memorable truths:

### 1.
You literally start in chains.

### 2.
You steal gear rather than just buying everything.

### 3.
You must escape to secure valuable loot.

### 4.
Your hideout visibly becomes a castle.

### 5.
Eventually you raid kingdoms/players and become King.

That is the game's identity.

---

# 96. POTENTIAL TAGLINE SYSTEM

Marketing can repeatedly use transformation language.

- Nothing -> King
- Prisoner -> Warlord
- Spoon -> Legendary Sword
- Cell -> Castle
- 0 Gold -> Royal Treasury
- Escape -> Conquer

This is strong short-form content structure.

---

# 97. SHORT-FORM CONTENT IDEAS

## Video 1
"Can I become King using only a spoon?"

## Video 2
"I stole the rarest sword in the castle."

## Video 3
"Escaping at 1 HP with 10,000 gold."

## Video 4
"0 Robux Prisoner vs 10,000 Robux King"  
Only if monetization does not misrepresent power.

## Video 5
"Every time I escape, my castle gets bigger."

## Video 6
"I reached MAX WANTED."

## Video 7
"100 guards vs one Mythic weapon."

The game should make these possible without staging fake mechanics.

---

# 98. CREATOR / INFLUENCER SEEDING

Do not message creators with:

> "Please play my Roblox game."

Give them a challenge.

Examples:

- First creator to escape Wanted V.
- Beat the Warden with a Spoon.
- Find the hidden Mythic.
- Raid developer castle.
- Speedrun first kingdom.

Content creators need a video idea, not a product brochure.

---

# 99. COMMUNITY LOOP

After the game has enough users:

- Discord for older eligible community members, within Roblox/platform policy;
- Roblox group;
- polls on next weapon/kingdom;
- update teasers;
- fan castle showcases.

Do not outsource game design to polls.

Use community feedback to identify pain and excitement.

---

# 100. TEAM FOR A LEAN BUILD

A serious MVP can be created by a small strong team.

Ideal roles:

## Roblox gameplay engineer
Luau, networking, datastore, combat.

## Builder / environment artist
Castle/dungeon/world.

## 3D/character/VFX generalist
Weapons, enemies, effects.

## UI/UX
Can initially be combined with another role if strong.

## Product/game designer
Owns loop, balance, analytics, tests.

One person can cover multiple roles.

More people do not automatically make the game better.

---

# 101. PRODUCTION PROCESS

Work in playable slices.

Bad sprint:

- make 40 weapon models;
- make 12 UI screens;
- write 20 quests.

Good sprint:

> One full player journey from cell -> guard -> loot -> escape -> upgrade.

Then improve it until it works.

---

# 102. PRIORITY FRAMEWORK

For every feature, score:

- First-session impact
- Retention impact
- Social impact
- Revenue impact
- Development cost
- Risk

Build high-impact, low-cost systems first.

Example:

### Alarm System
First session: High  
Retention: Medium  
Social: Medium  
Cost: Medium  
Build early.

### Player Trading
First session: Low  
Retention: Medium/High  
Risk: Very High  
Cost: High  
Build late.

---

# 103. CLAUDE: MASTER IMPLEMENTATION INSTRUCTION

Copy the following along with this document when asking Claude to build.

---

## CLAUDE ROLE

You are the lead Roblox gameplay engineer and technical game designer for `PRISONER TO KING`.

Your job is not to blindly implement every idea in the design document.

Your priorities are:

1. Build a playable vertical slice.
2. Keep all economy/combat/progression logic server-authoritative.
3. Use modular Luau.
4. Make systems configurable through shared configuration modules.
5. Instrument the onboarding and core loop with analytics.
6. Keep the game mobile-first.
7. Avoid premature complexity.
8. Clearly state any Roblox Studio objects/assets/animations that must be created manually.
9. Never invent an API if uncertain; flag it for verification against current Roblox Creator documentation.
10. Do not add systems outside the defined milestone unless explicitly asked.

### Engineering rules

- No giant monolithic scripts.
- Use typed Luau where useful.
- Separate services, controllers, config, and UI.
- Validate every client request.
- Never trust client-reported money, damage, loot, or entitlements.
- Add comments around security-sensitive code.
- Make every module independently understandable.
- Use clean naming.
- Provide setup instructions with every batch of scripts.
- If an object hierarchy is required in Studio, specify the exact hierarchy.
- Prefer simple native Roblox architecture before adding third-party dependencies.
- Design persistence with schema versioning.
- Design receipt processing to be retry-safe.
- Do not hard-code regional Robux prices into store UI.
- Make interaction prompts usable on keyboard, controller, and touch.

---

# 104. CLAUDE MILESTONE 1 — GRAYBOX

Build only:

1. player spawn in cell;
2. break chain interaction;
3. pick up Bent Spoon;
4. attack Basic Guard;
5. Guard health and death;
6. Guard drops key + Gold;
7. key opens dungeon door;
8. player reaches extraction zone;
9. extraction secures Gold;
10. player receives a simple upgrade;
11. basic analytics events.

No store.

No base building.

No second kingdom.

No advanced inventory.

### Acceptance criteria

A completely new tester can:

- spawn;
- understand they must escape;
- break chains;
- acquire weapon;
- kill guard;
- collect key;
- open door;
- reach extraction;
- see Gold secured;

without a developer explaining anything.

The full sequence should be completable in roughly 2–4 minutes.

---

# 105. CLAUDE MILESTONE 2 — VERTICAL SLICE

Add:

- Rusty Sword;
- Guard Sword;
- inventory/equip;
- chest;
- Captain;
- rare drop;
- unsecured loot UI;
- death loss;
- second run;
- simple hideout armory upgrade;
- persistent save.

### Acceptance criteria

After escaping once, a tester voluntarily understands:

> "If I go back in, I can kill the Captain and get better loot."

---

# 106. CLAUDE MILESTONE 3 — MVP SYSTEMS

Add:

- Greenvale castle;
- three enemy archetypes;
- 6 weapons;
- simple rank progression;
- 10 contracts;
- collection index;
- mobile polished HUD;
- analytics funnel;
- purchase handling;
- starter bundle;
- settings;
- performance pass.

---

# 107. CLAUDE OUTPUT FORMAT FOR CODE TASKS

For each implementation request, Claude should output:

## A. What is being built
One paragraph.

## B. Studio hierarchy
Exact folders/objects/remotes required.

## C. Files
Each script with full path and complete code.

## D. Configuration
Anything the developer may tune.

## E. Manual setup
Animations, tags, collision groups, GUI references, etc.

## F. Security notes
What is validated server-side.

## G. Test checklist
Steps to verify functionality in Studio.

## H. Known limitations
Anything intentionally deferred.

---

# 108. CLAUDE FIRST TASK

Recommended first instruction after giving Claude this file:

> Implement Milestone 1 only. Start by defining the exact Roblox Studio hierarchy and module architecture. Then give me the scripts in dependency order. Do not implement Milestone 2 or any later system. Use placeholder Parts and Roblox primitives so the entire gameplay loop can be tested before custom art exists. The server must be authoritative for combat rewards, the key, Gold, and extraction. Add analytics wrapper functions even if analytics cannot be observed in unpublished Studio tests. After the code, give an exact Studio setup checklist and a playtest checklist.

---

# 109. FUTURE CODE MODULES

Potential final services:

```text
PlayerDataService
CombatService
WeaponService
EnemyService
LootService
RunService
ExtractionService
WantedService
EconomyService
ProgressionService
KingdomService
ContractService
CollectionService
CastleService
PartyService
RaidService
LiveOpsService
PurchaseService
AnalyticsService
AntiExploitService
```

Do not create all of them on Day 1 just because they are listed.

Architecture should grow with proven needs.

---

# 110. CONFIG-DRIVEN CONTENT

Weapons should be data, not separate logic scripts whenever possible.

Example conceptual config:

```lua
return {
    rusty_sword = {
        Name = "Rusty Sword",
        Rarity = "Common",
        Damage = 12,
        AttackCooldown = 0.70,
        WeaponClass = "Sword",
        SellValue = 30,
        Special = nil,
    },

    captain_greatsword = {
        Name = "Captain's Greatsword",
        Rarity = "Rare",
        Damage = 32,
        AttackCooldown = 0.95,
        WeaponClass = "Greatsword",
        SellValue = 240,
        Special = "KnockbackCone",
    },
}
```

This lets designers rebalance without rewriting combat logic.

---

# 111. ENEMY CONFIG

```lua
return {
    basic_guard = {
        MaxHealth = 35,
        Damage = 6,
        MoveSpeed = 10,
        AggroRange = 35,
        AttackRange = 5,
        GoldMin = 8,
        GoldMax = 15,
        LootTable = "basic_guard",
    },

    captain_bronn = {
        MaxHealth = 300,
        Damage = 18,
        MoveSpeed = 11,
        AggroRange = 60,
        AttackRange = 7,
        Boss = true,
        LootTable = "captain_bronn",
    },
}
```

---

# 112. LOOT TABLE CONFIG

Conceptual:

```lua
captain_bronn = {
    Rolls = 1,
    Entries = {
        { Item = "guard_sword", Weight = 60 },
        { Item = "captain_helmet", Weight = 25 },
        { Item = "captain_greatsword", Weight = 10 },
        { Item = "royal_key", Weight = 5 },
    }
}
```

The actual randomization must occur server-side.

---

# 113. STATE MACHINES

Explicit states reduce bugs.

## Player run state

```text
Safe
EnteringDanger
InDanger
Extracting
Extracted
Dead
```

## Enemy

```text
Idle
Patrol
Investigate
Chase
Attack
Stunned
Dead
```

## Extraction

```text
Inactive
Available
Channeling
Completed
Cancelled
```

Make transitions explicit.

---

# 114. BALANCE VARIABLES TO CENTRALIZE

Do not scatter magic numbers.

Central config should include:

- base player HP;
- respawn delay;
- extraction channel time;
- death Gold loss;
- wanted thresholds;
- gold multiplier;
- party bonus;
- enemy scaling;
- boss HP scaling;
- rarity weights;
- first-run guarantees;
- tutorial reward;
- rank XP;
- kingdom unlocks.

---

# 115. FIRST-RUN GUARANTEES

Random systems can ruin onboarding.

On first run:

- guard always drops required key;
- first chest always contains Rusty Sword;
- extraction cannot be blocked by a random impossible encounter;
- player receives enough Gold for first upgrade;
- no PvP;
- no confusing rare branch.

The game can become variable after the player understands it.

---

# 116. DIFFICULTY CURVE

First run:
Almost impossible to fail unless inactive.

Second run:
Some risk.

Captain:
Player may fail once.

Boss:
Requires understanding.

Never use "difficulty" as justification for a weak first experience.

---

# 117. RECOMMENDED FIRST 10-MINUTE CONTENT

0–3:
Escape tutorial.

3–4:
Upgrade.

4–7:
Second castle run.

7–10:
Captain attempt / chest.

At minute 10, the player should know:

- what the loop is;
- why better gear matters;
- what the next boss/reward is;
- what becoming King means.

---

# 118. PLAYER FEEDBACK PANEL

After sessions in alpha, optionally ask one small question.

Examples:

> `What felt worst?`
> - Combat
> - Getting lost
> - Too slow
> - Dying
> - Nothing

Or:

> `What do you want more of?`
> - Bosses
> - Weapons
> - Castles
> - PvP
> - Secrets

Do not interrupt every session.

---

# 119. BUG PRIORITY

P0:
- data loss;
- purchase failure;
- duplication;
- stuck tutorial;
- impossible extraction;
- server crash.

P1:
- combat exploit;
- broken boss;
- severe mobile UI issue;
- performance regression.

P2:
- cosmetic issue;
- minor animation;
- text typo.

Never ship a new sword while data loss is unresolved.

---

# 120. QA MATRIX

Test each major system on:

- desktop keyboard/mouse;
- touch/mobile;
- controller where supported;
- low graphics;
- high latency simulation;
- server with multiple players;
- leave/rejoin;
- death during interaction;
- death during extraction;
- disconnect during purchase;
- double-click purchase;
- two players picking same loot;
- boss death with multiple players;
- full inventory;
- old save schema.

---

# 121. PERFORMANCE QA

Measure:

- first join load;
- client memory;
- frame rate;
- server frame health;
- network traffic;
- NPC counts;
- VFX spam;
- map streaming.

Roblox provides performance analytics and MicroProfiler tooling; use them before and after major content updates.

---

# 122. DISCOVERY OPERATING LOOP

After launch:

```text
1. Check impressions.
2. Check play-through.
3. Check first-play bounce.
4. Check onboarding funnel.
5. Check playtime / play days.
6. Check social co-play.
7. Compare cohorts.
8. Identify one bottleneck.
9. Ship one focused improvement.
10. Measure again.
```

Do not react to one day of noisy data by rebuilding everything.

---

# 123. THE PRODUCT DASHBOARD

Maintain a simple internal dashboard.

## Acquisition
- impressions;
- plays;
- play-through;
- source.

## Activation
- tutorial completion;
- first extraction;
- first upgrade;
- second run.

## Engagement
- session length;
- runs/session;
- extractions/session;
- bosses/session.

## Retention
- D1;
- D7;
- D30;
- play days/user.

## Social
- party usage;
- friend joins;
- co-op boss participation.

## Economy
- Gold earned;
- Gold spent;
- wealth distribution;
- most purchased upgrades.

## Monetization
- payer conversion;
- ARPDAU;
- product conversion;
- spend days;
- prompt -> purchase.

---

# 124. DATA-DRIVEN EXAMPLE

Suppose:

- 80% kill first guard;
- 72% take sword;
- 31% complete extraction.

Then do **not** add a new kingdom.

Find why 41 points are lost before extraction.

Potential causes:

- cannot find exit;
- enemies too hard;
- objective unclear;
- death penalty;
- extraction point unclear.

Fix the leak.

---

# 125. ANTI-FEATURE LIST

Unless data strongly supports them, avoid:

- energy system;
- forced ads;
- weapon durability;
- hunger;
- thirst;
- inventory weight simulation;
- long crafting timers;
- random walking quests;
- 20-minute unskippable story;
- mandatory clan;
- player-to-player permanent item theft;
- manual stat allocation at level 1.

These can add friction without adding fun.

---

# 126. WHY THIS CONCEPT HAS POTENTIAL

The concept has a good Roblox-compatible fantasy because it can be understood visually:

`weak -> strong`

It also has:

- loot;
- progression;
- visible status;
- risk;
- action;
- social potential;
- update scalability.

More importantly, the core verbs can be made very simple:

`BREAK -> STEAL -> FIGHT -> ESCAPE -> UPGRADE -> RAID`

That is stronger than a generic RPG quest structure.

---

# 127. MAIN CONCEPT RISK

The biggest risk is trying to combine:

- Blox Fruits-scale progression;
- extraction shooter risk;
- base building;
- PvP raiding;
- medieval RPG combat;

in version one.

That would almost certainly create too much scope.

The game should earn complexity.

First prove:

> `steal -> escape -> upgrade`

Then build the kingdom around it.

---

# 128. FINAL PRODUCT PRINCIPLE

If the game only has:

- one dungeon;
- one boss;
- six weapons;

but players repeatedly escape because the loop feels great, you have something.

If the game has:

- nine kingdoms;
- 200 weapons;
- pets;
- guilds;
- raids;
- crafting;

and players quit before the first escape, you have nothing.

---

# 129. RECOMMENDED DECISION

**Build this concept.**

But build **PRISONER TO KING as an extraction-progression social game**, not as a traditional medieval RPG.

The first prototype should answer one question:

> Is it satisfying enough to steal loot and escape that players immediately want to go back inside for better loot?

If yes, expand.

If no, fix that before adding anything else.

---

# 130. SOURCE NOTES — CURRENT ROBLOX PLATFORM GUIDANCE

The product strategy above was informed by current Roblox documentation/public guidance available in August 2026.

## Roblox Discovery
Roblox Creator Hub — `Discovery`

Key current concepts:
- play-through rate;
- first-play bounce;
- D1 / D2–7 / D8–28 play behavior;
- playtime;
- intentional co-play;
- qualified play sessions;
- spend signals;
- explore -> expand recommendation behavior.

Source:
https://create.roblox.com/docs/discovery

## 2026 discovery update
Roblox Newsroom — `Optimizing Discovery: How Great Games Reach Millions of Players on Roblox`

Roblox stated in June 2026 that recommendation signals were being made more granular and that long-term player behavior across D1, D2–7, and D8–28 would be represented more directly.

Source:
https://about.roblox.com/newsroom/2026/06/optimizing-discovery-great-games-reach-millions-players-roblox

## Analytics / custom events
Roblox Creator Hub — `Custom events`

Source:
https://create.roblox.com/docs/production/analytics/custom-events

## Monetization
Roblox Creator Hub — `Monetization`, `Developer Products`, `Passes`, `Subscriptions`

Source family:
https://create.roblox.com/docs/production/monetization

## Regional / managed pricing
Roblox Creator Hub — `Regional pricing`

Current Roblox documentation says managed pricing can adjust item prices based on economic location, and custom in-game price displays should use dynamic product data rather than hard-coded values.

Source:
https://create.roblox.com/docs/production/monetization/regional-pricing

## Thumbnails
Roblox Creator Hub — `Thumbnails`

Current guidance recommends 16:9 and ideally 1920×1080 for image thumbnails.

Source:
https://create.roblox.com/docs/production/publishing/thumbnails

## Experience events
Roblox Creator Hub — `Experience events and updates`

Source:
https://create.roblox.com/docs/production/promotion/experience-events

## Localization
Roblox Creator Hub — `Localization`

Source:
https://create.roblox.com/docs/production/localization

## Performance / streaming
Roblox Creator Hub — `Design for performance`, `Instance streaming`

Sources:
https://create.roblox.com/docs/performance-optimization/design
https://create.roblox.com/docs/workspace/streaming

## Rewarded video
Roblox Creator Hub — `Rewarded video ads`

Source:
https://create.roblox.com/docs/production/promotion/rewarded-video-ads

---

# 131. FINAL CLAUDE COPY-PASTE PROMPT

If you want one prompt to place above this file, use:

> You are my Lead Roblox Engineer, Game Designer, and Product Partner. The attached `PRISONER TO KING` document is the source of truth for the game's product direction. Read it completely before writing code. We are intentionally NOT building the whole document at once. Your first objective is to create the smallest fully playable Roblox Studio vertical slice that proves the core loop: BREAK CHAINS -> GET WEAPON -> KILL GUARD -> STEAL KEY/LOOT -> ESCAPE -> SECURE GOLD -> UPGRADE -> WANT TO RE-ENTER. Keep the server authoritative for combat, loot, currency, extraction, inventory, and purchases. Use modular Luau with config-driven content. Design for mobile first. Instrument the funnel. Do not add PvP, trading, clans, multiple kingdoms, pets, mounts, crafting, player raids, or other P1/P2 systems until I explicitly request them. Whenever you provide code, include the exact Roblox Studio hierarchy, full file paths, complete code, setup instructions, test procedure, security notes, and known limitations. If any Roblox API detail may have changed, do not guess—identify it and verify it against current Roblox Creator documentation.

---

# END

**Core mantra:**

> **Start in chains. Get something valuable. Risk losing it. Escape. Grow visibly stronger. Go back for more. Become King.**
