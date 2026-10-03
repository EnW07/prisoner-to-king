--!strict
-- ClientBootstrap.client.lua
-- The only LocalScript. Controllers are ModuleScripts under Controllers/.

local Controllers = script.Parent:WaitForChild("Controllers")

local UIController = require(Controllers.UIController)
local CombatController = require(Controllers.CombatController)
local FeedbackController = require(Controllers.FeedbackController)
local PromptController = require(Controllers.PromptController)
local PromptUIController = require(Controllers.PromptUIController)
local WorldFXController = require(Controllers.WorldFXController)
local InventoryController = require(Controllers.InventoryController)

UIController.Init()
CombatController.Init()
FeedbackController.Init()
PromptController.Init()
PromptUIController.Init()
WorldFXController.Init()
InventoryController.Init()

print("[PRISONER TO KING] Client ready.")
