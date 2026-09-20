--!strict
-- Доход, цены и сохранения принадлежат серверу; клиент передаёт только намерение.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
Players.CharacterAutoLoads = false

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.LocalizationCatalog)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local ProfileStore = require(script.ProfileStore)
local remotes = Remotes.ensure(ReplicatedStorage)
local kitchens
if Config.Kitchen.enabled and Config.Scene3D.enabled then
 kitchens=require(script.KitchenRooms).start(remotes.kitchenMode)
 require(script.KitchenRelay).start(Players,remotes.kitchenAction,require(Shared.WorkstationWire),os.clock)
end
local studio = RunService:IsStudio()
local storage = if studio then nil else ProfileStore.new(DataStoreService:GetDataStore("ChocolateAtelier_v1"), Economy,
	Config.Economy, HttpService:GenerateGUID(false), os.time)
local sessions = {}
local loading = {}
local requests = {}
local closing = false

local function send(player, notice, reward)
	local session = sessions[player]
	if not session then
		remotes.stateSync:FireClient(player, { ready = false })
		return
	end
	local state = Economy.snapshot(session.data)
 if kitchens then kitchens:sync(player,state) end
	state.ready = true
	state.canTestBalance = player.UserId == Config.BalanceTesterUserId
	state.prestigeDisabled = session.data.ignorePrestige == true
	state.offline = session.offline
	state.notice = if type(notice)=="string" then {key=notice} else notice
	state.reward = reward
	state.saveStatus = if studio then "Test session · progress is not saved" else session.saveStatus
	remotes.stateSync:FireClient(player, state)
end

local function accrue(session)
	local now = os.clock()
	Economy.tick(session.data, now - session.tick)
	session.tick = now
end

local function save(player, release)
	local session = sessions[player]
	if not session then return end
	if release then session.closing = true end
	while session.saving do task.wait(0.1) end
	if sessions[player] ~= session then return end
	accrue(session)
	if studio then
		session.nextSave = os.clock() + Config.Economy.saveInterval
		if release then sessions[player] = nil end
		return
	end
	session.saving = true
	local ok, written = pcall(function()
		return storage:save(tostring(player.UserId), session.data, release)
	end)
	session.saving = false
	if ok and written then
		session.lastSave = os.clock()
		session.nextSave = os.clock() + Config.Economy.saveInterval
		session.saveStatus = "Progress saved"
	else
		session.nextSave = os.clock() + 10
		session.saveStatus = "Saving delayed · retrying"
		warn("Chocolate profile save failed", player.UserId)
	end
	if release then
		-- Выход повторяется без снятия блокировки чужого сервера.
		if not ok then
			for _ = 1, 2 do
				task.wait(1)
				local retryOK, retryWritten = pcall(function() return storage:save(tostring(player.UserId), session.data, true) end)
				if retryOK and retryWritten then break end
			end
		end
		sessions[player] = nil
	elseif (ok and not written) or os.clock() - session.lastSave > Config.Economy.leaseSeconds - 30 then
		session.closing = true
		player:Kick(Catalog.format("Could not renew your save session. Rejoin to continue safely.", nil, player.LocaleId))
	elseif player.Parent then
		send(player)
	end
end

local function join(player)
	if loading[player] or sessions[player] or closing then return end
	loading[player] = true
	local data, offline
	if studio then
		data, offline = Economy.load(nil), 0
	else
		for _ = 1, 3 do
			local ok, loaded, away = pcall(function() return storage:claim(tostring(player.UserId)) end)
			if ok and loaded then data, offline = loaded, away; break end
			task.wait(2)
		end
	end
	if not data then
		loading[player] = nil
		if player.Parent then player:Kick(Catalog.format("Could not load your progress. Wait a moment and rejoin. Your save has not been changed.", nil, player.LocaleId)) end
		return
	end
	sessions[player] = { data = data, offline = offline, tick = os.clock(), lastRound = -math.huge,
		lastAction = -math.huge, lastSave = os.clock(), nextSave = os.clock() + Config.Economy.saveInterval, saveStatus = "Progress saved" }
	if not player.Parent or closing then save(player, true); loading[player] = nil; return end
	loading[player] = nil
	send(player)
end

Players.PlayerAdded:Connect(join)
Players.PlayerRemoving:Connect(function(player)
	requests[player] = nil
	save(player, true)
end)
for _, player in Players:GetPlayers() do task.spawn(join, player) end

remotes.requestState.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (requests[player] or -math.huge) < 0.5 then return end
	requests[player] = now
	send(player)
end)

remotes.roundComplete.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.closing then return end
	local now = os.clock()
	if now - session.lastRound < Config.Payout.minInterval then return end
	session.lastRound = now
	accrue(session)
	local amount = Economy.round(session.data)
	send(player, {key="Trick complete! +{amount}",args={amount=amount}}, amount)
end)

remotes.purchase.OnServerEvent:Connect(function(player, id)
	local session = sessions[player]
	if not session or session.closing or type(id) ~= "string" then return end
	local now = os.clock()
	if now - session.lastAction < 0.2 then return end
	session.lastAction = now
	accrue(session)
	-- Режим только текущей сессии: Economy.load исключает флаг из сохранений.
	if id == "admin_toggle_prestige" then
		if player.UserId ~= Config.BalanceTesterUserId then return end
		session.data.ignorePrestige = not session.data.ignorePrestige
		send(player)
		return
	end
	local bought = Economy.buy(session.data, id)
	send(player, if bought then "Upgrade purchased" else "Cannot purchase: check your balance and upgrade level")
end)

remotes.prestige.OnServerEvent:Connect(function(player)
	local session = sessions[player]
	if not session or session.closing then return end
	local now = os.clock()
	if now - session.lastAction < 0.2 then return end
	session.lastAction = now
	accrue(session)
	local gained = Economy.prestigeGain(session.data)
	local success = Economy.prestige(session.data)
	send(player, if success then {key="New workshop! +{stars} cocoa stars",args={stars=gained}} else "Earn more pieces to start a new workshop")
	if success then task.spawn(save, player, false) end
end)

task.spawn(function()
	while not closing do
		task.wait(1)
		for player, session in sessions do
			if not session.closing then
				accrue(session)
				send(player)
				if not session.saving and os.clock() >= session.nextSave then
					task.spawn(save, player, false)
				end
			end
		end
	end
end)

game:BindToClose(function()
	closing = true
	local remaining = 0
	for player in sessions do
		remaining += 1
		task.spawn(function() save(player, true); remaining -= 1 end)
	end
	local deadline = os.clock() + 25
	while (remaining > 0 or next(loading) ~= nil) and os.clock() < deadline do task.wait(0.1) end
end)
