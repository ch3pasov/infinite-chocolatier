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
	manualStep = remotesFolder:WaitForChild(Remotes.Names.ManualStep) :: RemoteEvent,
	requestState = remotesFolder:WaitForChild(Remotes.Names.RequestState) :: RemoteEvent,
	purchase = remotesFolder:WaitForChild(Remotes.Names.Purchase) :: RemoteEvent,
	prestige = remotesFolder:WaitForChild(Remotes.Names.Prestige) :: RemoteEvent,
	kitchenMode = remotesFolder:WaitForChild(Remotes.Names.KitchenMode) :: RemoteEvent,
	kitchenAction = remotesFolder:WaitForChild(Remotes.Names.KitchenAction) :: RemoteEvent,
	cafeVisit = remotesFolder:WaitForChild(Remotes.Names.CafeVisit) :: RemoteEvent,
}

local gameView = Game.new(gui, remotes)
gameView.audio = require(script.Audio).new(gui, gameView)
local atelier = Atelier.new(gui, gameView, remotes)
-- Сбой вспомогательного отчёта не должен останавливать загрузку самой игры.
local diagnosticOk, diagnostics = pcall(function()
	return require(script.Diagnostics).new(gui.Parent, gameView)
end)
if not diagnosticOk then
	warn("Developer diagnostics unavailable: " .. tostring(diagnostics))
	local partial = gui.Parent:FindFirstChild("DeveloperDiagnostics")
	if partial then partial:Destroy() end
	diagnostics = nil
end
local kitchen
if Config.Scene3D.enabled then
	local Scene3D = require(script.Scene3D)
	Scene3D.new(gameView)
	if Config.Kitchen.enabled then kitchen = require(script.Kitchen).new(gameView, atelier) end
end
local rankings=if kitchen then require(script.Rankings).new(gui,gameView,kitchen) else nil
local stateConnection = remotes.stateSync.OnClientEvent:Connect(function(state)
	if gameView.destroyed then return end
    gameView.audio:update(state)
    atelier:update(state)
	if kitchen then kitchen:update(state) end
    if state.reward then gameView:playRewardEffect(state.reward) end
	if diagnostics then diagnostics:update(state) end
end)
-- RemoteEvent живёт дольше GUI и иначе удерживает всю старую сцену.
gui.Destroying:Connect(function() stateConnection:Disconnect() end)
-- PlayerAdded может сработать раньше подписки клиента, поэтому состояние
-- запрашивается явно уже после создания интерфейса и обработчика.
remotes.requestState:FireServer()
