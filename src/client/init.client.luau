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

-- В первом экране игрок должен видеть шоколадку, а не стандартный HUD Roblox.
-- SetCore иногда становится доступен с задержкой, поэтому повторяем попытку.
task.spawn(function()
	for _ = 1, 8 do
		local ok = pcall(function()
			StarterGui:SetCore("TopbarEnabled", false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, false)
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end)

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
}

local gameView = Game.new(gui, remotes)
local atelier = Atelier.new(gui, gameView, remotes)
if Config.Scene3D.enabled then
	local Scene3D = require(script.Scene3D)
	Scene3D.new(gameView)
end
remotes.stateSync.OnClientEvent:Connect(function(state)
    atelier:update(state)
    if state.reward then gameView:playRewardEffect(state.reward) end
end)
-- PlayerAdded может сработать раньше подписки клиента, поэтому состояние
-- запрашивается явно уже после создания интерфейса и обработчика.
remotes.requestState:FireServer()
