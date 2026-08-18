--!strict
-- Единственная точка входа клиента.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Theme = require(script.Theme)
local Game = require(script.Game)

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
}

local gameView = Game.new(gui, remotes)
local counter = gameView.counter

remotes.stateSync.OnClientEvent:Connect(function(state)
	local slices = tonumber(state.slices) or 0
	counter.Text = `ДОЛЬКИ  {slices}`
end)
