--!strict
-- ClientBootstrap.client.lua
-- The only LocalScript. Controllers are ModuleScripts under Controllers/.

local Controllers = script.Parent:WaitForChild("Controllers")

local UIController = require(Controllers.UIController)
local CombatController = require(Controllers.CombatController)
local FeedbackController = require(Controllers.FeedbackController)

UIController.Init()
CombatController.Init()
FeedbackController.Init()

print("[PRISONER TO KING] Client ready.")
