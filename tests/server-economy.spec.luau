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
local function fixture(studio, seed, userId)
	local now = 1000
	local sent = {}
	local events = {}
	for _, name in { "stateSync", "requestState", "roundComplete", "purchase", "prestige" } do
		events[name] = { OnServerEvent = signal(), FireClient = function(_, _, state) table.insert(sent, state) end }
	end
	local player = { UserId = userId or 123, Parent = true, Kick = function(self, message) self.kicked = message end }
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
	local record = if seed then { data = seed, savedAt = now } else nil
	local store = { UpdateAsync = function(_, _, callback)
		local nextRecord = callback(record)
		if nextRecord then record = nextRecord end
		return nextRecord
	end }
	local modules = { KitchenRelay = {start=function() end}, KitchenRooms = {start=function() end}, LocalizationCatalog = require("../src/shared/LocalizationCatalog"), Config = Config, Economy = Economy, ProfileStore = ProfileStore, Remotes = { ensure = function() return events end } }
	local services = {
		Players = players, ReplicatedStorage = { WaitForChild = function() return { LocalizationCatalog = "LocalizationCatalog", Config = "Config", Economy = "Economy", Remotes = "Remotes" } end },
		HttpService = { GenerateGUID = function() return "server" end },
		RunService = { IsStudio = function() return studio end },
		DataStoreService = { GetDataStore = function() assert(not studio, "Studio обратился к настоящим сохранениям"); return store end },
	}
	luau.load(fs.readFile("src/server/init.server.luau"), { environment = {
		game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
		script = { ProfileStore = "ProfileStore", KitchenRooms = "KitchenRooms", KitchenRelay = "KitchenRelay" }, require = function(name) return modules[name] end,
		os = { clock = function() return now end, time = function() return now end },
		task = { spawn = function() end, wait = function() end }, warn = function() end,
	}, injectGlobals = true })()
	players.PlayerAdded:Fire(player)
	return { player = player, events = events, players = players, sent = sent,
		advance = function() now += 1 end, latest = function() return sent[#sent] end,
		record = function() return record end }
end
return function(h)
 h.test("сервер покупает десять уровней по своей сумме и сохраняет весь пакет",function()
  local f=fixture(false,{slices=10000})
  local price=Economy.quote(f.latest(),"craft",10)
  f.events.purchase.OnServerEvent:Fire(f.player,"craft",10,-999999)
  h.equals(f.latest().levels.craft,10); h.equals(f.latest().slices,10000-price)
  h.equals(f.latest().notice.key,"Purchased {count} upgrades")
  f.events.purchase.OnServerEvent:Fire(f.player,"craft",10)
  h.equals(f.latest().levels.craft,10)
  f.players.PlayerRemoving:Fire(f.player); h.equals(f.record().data.levels.craft,10)
 end)
 h.test("сервер отвергает поддельное количество и сам считает MAX",function()
  local f=fixture(false,{slices=100})
  for _,n in {-999,0/0,math.huge,{},"10"} do
   f.events.purchase.OnServerEvent:Fire(f.player,"craft",n); f.advance()
   h.equals(f.latest().slices,100); h.equals(f.latest().levels.craft,0)
  end
  local price,count=Economy.quote(f.latest(),"craft","max")
  f.events.purchase.OnServerEvent:Fire(f.player,"craft","max")
  h.equals(f.latest().slices,100-price); h.equals(f.latest().levels.craft,count)
 end)
 h.test("настоящий сервер выдаёт бонус заказа, не принимая повтор и размер награды от клиента",function()
  local f=fixture(false)
  for _=1,4 do f.events.roundComplete.OnServerEvent:Fire(f.player,999999); f.advance() end
  h.equals(f.latest().slices,5); h.equals(f.latest().order.completed,1)
  h.equals(f.latest().reward,2); h.equals(f.latest().notice.key,"Order packed! +{bonus} bonus pieces")
  f.events.roundComplete.OnServerEvent:Fire(f.player); f.events.roundComplete.OnServerEvent:Fire(f.player)
  h.equals(f.latest().slices,6); h.equals(f.latest().order.progress,1)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().version,4); h.equals(f.record().data.ordersCompleted,1)
  h.equals(f.record().data.orderProgress,1)
 end)
 h.test("бонус престижа отключает только админ, звёзды сохраняются",function()
  local seed={stars=20,levels={workers=1}}
  local f=fixture(false,seed,Config.BalanceTesterUserId)
  local boosted=f.latest().manual
  assert(f.latest().canTestBalance)
  f.events.purchase.OnServerEvent:Fire(f.player,'admin_toggle_prestige')
  h.equals(f.latest().prestigeDisabled,true); h.equals(f.latest().stars,20)
  h.near(f.latest().manual*6,boosted)
  f.advance(); f.events.prestige.OnServerEvent:Fire(f.player)
  h.equals(f.latest().prestigeDisabled,true)
  f.advance(); f.events.purchase.OnServerEvent:Fire(f.player,'admin_toggle_prestige')
  h.equals(f.latest().prestigeDisabled,false); h.near(f.latest().manual,boosted)
  local other=fixture(false,seed,456)
  h.equals(other.latest().canTestBalance,false)
  other.events.purchase.OnServerEvent:Fire(other.player,'admin_toggle_prestige')
  other.advance(); other.events.requestState.OnServerEvent:Fire(other.player)
  h.equals(other.latest().prestigeDisabled,false); h.near(other.latest().manual,boosted)
  local loaded=Economy.load({stars=20,ignorePrestige=true})
  h.equals(loaded.ignorePrestige,nil); h.equals(loaded.stars,20)
 end)

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
		f.events.purchase.OnServerEvent:Fire(f.player, "craft", 1, -999)
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
		local f = fixture(false, Economy.load({ slices = 5000, earned = 5000,
			levels = { workers = 73, clock = 5, plant = 1, craft = 4 } }))
		f.events.prestige.OnServerEvent:Fire(f.player, 1000)
		h.equals(f.latest().stars, 1)
		h.equals(f.latest().slices, 0)
		h.equals(f.latest().levels.workers, 0)
		h.equals(f.latest().legacyWorkers, 0)
		h.equals(f.latest().levels.clock, 0)
		h.equals(f.latest().owned.plant, false)
		h.equals(next(f.latest().equipped), nil)
		h.equals(f.latest().rate, 0)
		h.equals(f.latest().prices.kitchen, 25)
		h.equals(f.latest().prices.workers_1, nil)
		f.advance()
		f.events.prestige.OnServerEvent:Fire(f.player)
		h.equals(f.latest().stars, 1)
	end)
end
