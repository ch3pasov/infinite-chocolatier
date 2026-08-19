--!strict
-- Сервер хранит число долек и принимает только факт завершения раунда.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Remotes = require(Shared.Remotes)
local remotes = Remotes.ensure(ReplicatedStorage)

local slices: { [Player]: number } = {}
local lastPayout: { [Player]: number } = {}

local function sendState(player: Player)
	remotes.stateSync:FireClient(player, {
		slices = slices[player] or 0,
	})
end

Players.PlayerAdded:Connect(function(player)
	slices[player] = 0
	lastPayout[player] = 0
	sendState(player)
end)

Players.PlayerRemoving:Connect(function(player)
	slices[player] = nil
	lastPayout[player] = nil
end)

remotes.roundComplete.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastPayout[player] or 0) < Config.Payout.minInterval then
		return
	end

	lastPayout[player] = now
	slices[player] = (slices[player] or 0) + Config.Payout.amount
	sendState(player)
end)
