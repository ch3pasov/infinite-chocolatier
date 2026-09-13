--!nostrict
-- Исполняем точку входа сервера: чистая модель не ловит ошибки подключения.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Economy = require("../src/shared/Economy")
local Config = require("../src/shared/Config")
local ProfileStore = require("../src/server/ProfileStore")

local function signal()
	local callbacks = {}
	return { Connect = function(_, fn) table.insert(callbacks, fn) end,
		Fire = function(_, ...) for _, fn in callbacks do fn(...) end end }
end
local function fixture(studio, seed)
	local now = 1000
	local sent = {}
	local events = {}
	for _, name in { "stateSync", "requestState", "roundComplete", "purchase", "prestige" } do
		events[name] = { OnServerEvent = signal(), FireClient = function(_, _, state) table.insert(sent, state) end }
	end
	local player = { UserId = 123, Parent = true, Kick = function(self, message) self.kicked = message end }
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
	local record = if seed then { data = seed, savedAt = now } else nil
	local store = { UpdateAsync = function(_, _, callback)
		local nextRecord = callback(record)
		if nextRecord then record = nextRecord end
		return nextRecord
	end }
	local modules = { LocalizationCatalog = require("../src/shared/LocalizationCatalog"), Config = Config, Economy = Economy, ProfileStore = ProfileStore, Remotes = { ensure = function() return events end } }
	local services = {
		Players = players, ReplicatedStorage = { WaitForChild = function() return { LocalizationCatalog = "LocalizationCatalog", Config = "Config", Economy = "Economy", Remotes = "Remotes" } end },
		HttpService = { GenerateGUID = function() return "server" end },
		RunService = { IsStudio = function() return studio end },
		DataStoreService = { GetDataStore = function() assert(not studio, "Studio обратился к настоящим сохранениям"); return store end },
	}
	luau.load(fs.readFile("src/server/init.server.luau"), { environment = {
		game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
		script = { ProfileStore = "ProfileStore" }, require = function(name) return modules[name] end,
		os = { clock = function() return now end, time = function() return now end },
		task = { spawn = function() end, wait = function() end }, warn = function() end,
	}, injectGlobals = true })()
	players.PlayerAdded:Fire(player)
	return { player = player, events = events, players = players, sent = sent,
		advance = function() now += 1 end, latest = function() return sent[#sent] end,
		record = function() return record end }
end
return function(h)
	h.test("локальный Studio запускается без доступа к DataStore", function()
		local f = fixture(true)
		h.equals(f.latest().ready, true)
		h.equals(f.latest().slices, 0)
	end)
	h.test("сервер игнорирует присланный доход и повтор завершения раунда", function()
		local f = fixture(false)
		f.events.roundComplete.OnServerEvent:Fire(f.player, 999999)
		h.equals(f.latest().slices, 1)
		h.equals(f.latest().reward, 1)
		f.events.roundComplete.OnServerEvent:Fire(f.player, 999999)
		h.equals(f.latest().slices, 1)
		f.advance()
		f.events.roundComplete.OnServerEvent:Fire(f.player)
		h.equals(f.latest().slices, 2)
	end)
	h.test("настоящий сервер покупает только по своей цене и сохраняет при выходе", function()
		local f = fixture(false, Economy.load({ slices = 3 }))
		f.events.purchase.OnServerEvent:Fire(f.player, "craft", -999)
		h.equals(f.latest().slices, 0)
		h.equals(f.latest().levels.craft, 1)
		f.events.roundComplete.OnServerEvent:Fire(f.player)
		h.equals(f.latest().slices, 2)
		f.players.PlayerRemoving:Fire(f.player)
		h.equals(f.record().data.levels.craft, 1)
		h.equals(f.record().data.slices, 2)
		h.equals(f.record().owner, nil)
	end)
	h.test("повторный запрос состояния решает гонку подключения клиента", function()
		local f = fixture(false, Economy.load({ slices = 33 }))
		f.events.requestState.OnServerEvent:Fire(f.player)
		h.equals(f.latest().slices, 33)
		h.equals(f.latest().reward, nil)
		h.equals(f.latest().ready, true)
	end)
	h.test("серверный перезапуск ателье нельзя повторить с тем же доходом", function()
		local f = fixture(false, Economy.load({ slices = 5000, earned = 5000 }))
		f.events.prestige.OnServerEvent:Fire(f.player, 1000)
		h.equals(f.latest().stars, 1)
		h.equals(f.latest().slices, 0)
		f.advance()
		f.events.prestige.OnServerEvent:Fire(f.player)
		h.equals(f.latest().stars, 1)
	end)
end
