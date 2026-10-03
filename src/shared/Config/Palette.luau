--!strict
-- Palette.lua  (docs/ART_AND_UI_DIRECTION.md §3)
-- The ONLY place colour values for new visual work are defined. Use a token, never a new
-- Color3 literal. `bleed` vs `gold` is the game's core read: at risk vs banked.

local Palette = {
	stone = Color3.fromHex("#5A5A63"), -- dungeon walls, neutral architecture
	pitch = Color3.fromHex("#2E2E36"), -- floors, shadow, the base the scene sits on
	ember = Color3.fromHex("#FF9B3D"), -- torchlight, warmth, safety-adjacent
	gold = Color3.fromHex("#FFCD50"), -- currency, banked value, the armory
	bleed = Color3.fromHex("#FF6B4A"), -- unsecured loot, danger, wanted level
	escape = Color3.fromHex("#5CE08C"), -- extraction, safety achieved
}

return Palette
