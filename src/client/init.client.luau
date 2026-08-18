--!strict
-- Единственная точка входа клиента.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Theme = require(script.Theme)
local Game = require(script.Game)

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "InfiniteChocolate"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
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
