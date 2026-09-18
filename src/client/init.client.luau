--!strict
-- Единственная точка входа клиента.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Atelier = require(script.Atelier)
local Game = require(script.Game)
local Config = require(Shared.Config)

local player = Players.LocalPlayer

-- Стандартный HUD и PlayerModule нужны для прогулки, чата и управления камерой.
local gui = Instance.new("ScreenGui")
gui.Name = "InfiniteChocolate"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local remotesFolder = ReplicatedStorage:WaitForChild(Remotes.Names.Folder)
local remotes = {
	stateSync = remotesFolder:WaitForChild(Remotes.Names.StateSync) :: RemoteEvent,
	roundComplete = remotesFolder:WaitForChild(Remotes.Names.RoundComplete) :: RemoteEvent,
	requestState = remotesFolder:WaitForChild(Remotes.Names.RequestState) :: RemoteEvent,
	purchase = remotesFolder:WaitForChild(Remotes.Names.Purchase) :: RemoteEvent,
	prestige = remotesFolder:WaitForChild(Remotes.Names.Prestige) :: RemoteEvent,
	kitchenMode = remotesFolder:WaitForChild(Remotes.Names.KitchenMode) :: RemoteEvent,
}

local gameView = Game.new(gui, remotes)
local atelier = Atelier.new(gui, gameView, remotes)
local kitchen
if Config.Scene3D.enabled then
	local Scene3D = require(script.Scene3D)
	Scene3D.new(gameView)
	if Config.Kitchen.enabled then kitchen = require(script.Kitchen).new(gameView, atelier) end
end
remotes.stateSync.OnClientEvent:Connect(function(state)
    atelier:update(state)
	if kitchen then kitchen:update(state) end
    if state.reward then gameView:playRewardEffect(state.reward) end
end)
-- PlayerAdded может сработать раньше подписки клиента, поэтому состояние
-- запрашивается явно уже после создания интерфейса и обработчика.
remotes.requestState:FireServer()
