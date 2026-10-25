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
local function makePlayer(userId)
	return { UserId = userId or 123, Parent = true, Kick = function(self, message) self.kicked = message end }
end
local function fixture(studio, seed, userId, savedAt, options)
	local now = 1000
	local sent = {}
	local events = {}
	for _, name in { "stateSync", "requestState", "roundComplete", "manualStep", "purchase", "prestige", "staffChoice" } do
		events[name] = { OnServerEvent = signal(), FireClient = function(_, _, state) table.insert(sent, state) end }
	end
	local player = makePlayer(userId)
	local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
	local record = if seed then { data = seed, savedAt = savedAt or now } else nil
	local beforeUpdate
	local store = { UpdateAsync = function(_, _, callback)
		if options and options.beforeUpdate then options.beforeUpdate(function(seconds) now += seconds end) end
		-- Однократная задержка запроса позволяет воспроизвести другой вход
		-- до выполнения callback старого сохранения без настоящего DataStore.
		local hook = beforeUpdate; beforeUpdate = nil
		if hook then hook() end
		local nextRecord = callback(record)
		if nextRecord then record = nextRecord end
		if options and options.afterUpdate then options.afterUpdate(nextRecord,function(seconds) now += seconds end) end
		return nextRecord
	end }
	local rankingRecords={}
	local modules = { RankingsService={start=function() return {record=function(_,id,data) table.insert(rankingRecords,{id=id,lifetime=data.lifetime,rounds=data.rounds,guests=data.socialCounts and data.socialCounts.guests}) end} end}, SocialService=require("../src/server/SocialService"), KitchenRelay = {start=function() end}, KitchenRooms = {start=function() return options and options.rooms end}, LocalizationCatalog = require("../src/shared/LocalizationCatalog"), Config = Config, Economy = Economy, ProfileStore = ProfileStore, Remotes = { ensure = function() return events end } }
	local nextToken = 0
	local services = {
		Players = players, ReplicatedStorage = { WaitForChild = function() return { LocalizationCatalog = "LocalizationCatalog", Config = "Config", Economy = "Economy", Remotes = "Remotes" } end },
		HttpService = { GenerateGUID = function() nextToken += 1; return "session-" .. nextToken end },
		RunService = { IsStudio = function() return studio end },
		DataStoreService = { GetDataStore = function() assert(not studio, "Studio обратился к настоящим сохранениям"); return store end },
	}
	luau.load(fs.readFile("src/server/init.server.luau"), { environment = {
		game = { GetService = function(_, name) return services[name] end, BindToClose = function() end },
		script = { RankingsService="RankingsService", SocialService = "SocialService", ProfileStore = "ProfileStore", KitchenRooms = "KitchenRooms", KitchenRelay = "KitchenRelay" }, require = function(name) return modules[name] end,
		os = { clock = function() return now end, time = function() return now end },
		task = { spawn = function(fn, ...)
			if options and options.runSaves and select("#",...)>0 then fn(...) end
		end, wait = function() end }, warn = function() end,
	}, injectGlobals = true })()
	players.PlayerAdded:Fire(player)
	return { rankingRecords=rankingRecords, player = player, events = events, players = players, sent = sent,
  complete=function(who,...)
   events.manualStep.OnServerEvent:Fire(who,'cancel')
   events.manualStep.OnServerEvent:Fire(who,'begin')
   for i=1,5 do events.manualStep.OnServerEvent:Fire(who,i) end
   now+=.5
   events.roundComplete.OnServerEvent:Fire(who,...)
  end,
		advance = function(seconds) now += seconds or 1 end, latest = function() return sent[#sent] end,
		beforeUpdate = function(hook) beforeUpdate = hook end,
		record = function() return record end }
end
return function(h)
 h.test('сервер выбора стажёра проверяет друга, присутствие, найм и форму запроса до записи',function()
  local current,allowed=0,true
  local rooms={sync=function(_,_,state) current=state.apprenticeUserId end,visiblePlayers=function() return {} end,
   onSocialChange=function() end,manualContext=function() return 1 end,hasOnlineFriend=function() return false end,visits=function() return {} end,
   canChooseStaff=function(_,_,id) return id==0 or (allowed and id==456) end,
   staffPage=function() return {items={},page=1,pages=1,selected=current} end}
  local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1},slices=100},123,nil,{rooms=rooms})
  local function choose(id)
   f.advance(1);f.events.staffChoice.OnServerEvent:Fire(f.player,{action='select',id=id,query='',page=1,request=1})
  end
  choose(456);h.equals(f.latest().apprenticeUserId,nil,'последний ответ — страница, без копии кошелька')
  h.equals(current,456)
  for _,bad in {999,123,-1,1.5,0/0,math.huge,'456',{}} do choose(bad);h.equals(current,456) end
  allowed=false;choose(456);h.equals(current,456)
  choose(0);h.equals(current,0)
  for _,request in {{action='select',id=456,query='',page=0/0,request=1},{action='select',id=456,query=string.rep('x',81),page=1,request=1}} do
   f.advance(1);f.events.staffChoice.OnServerEvent:Fire(f.player,request);h.equals(current,0)
  end
  f.players.PlayerRemoving:Fire(f.player);h.equals(f.record().data.apprenticeUserId,0)
  local noHire=fixture(false,{collectionVersion=2,levels={kitchen=1}},123,nil,{rooms=rooms})
  noHire.events.staffChoice.OnServerEvent:Fire(noHire.player,{action='select',id=456,query='',page=1,request=1})
  noHire.players.PlayerRemoving:Fire(noHire.player);h.equals(noHire.record().data.apprenticeUserId,0)
 end)
 h.test('рейтинг получает подтверждённый профиль, а не покупку или сырой раунд клиента',function()
  local f=fixture(false,{lifetime=100,rounds=4})
  h.equals(#f.rankingRecords,1);h.equals(f.rankingRecords[1].lifetime,100)
  f.complete(f.player);h.equals(#f.rankingRecords,1)
  f.events.purchase.OnServerEvent:Fire(f.player,'invalid');h.equals(#f.rankingRecords,1)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(#f.rankingRecords,2);h.equals(f.rankingRecords[2].rounds,5)
  h.equals(f.rankingRecords[2].lifetime,f.record().data.lifetime)
 end)
 h.test('повтор сохранения при выходе отправляет рекорд только после успешной записи',function()
  local f=fixture(false,{lifetime=100,rounds=4});f.complete(f.player)
  f.beforeUpdate(function() error('temporary failure') end)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(#f.rankingRecords,2);h.equals(f.rankingRecords[2].rounds,5)
  h.equals(f.record().data.rounds,5)
 end)
 h.test('Studio-профиль не отправляется в глобальный рейтинг',function()
  local f=fixture(true);f.complete(f.player);f.players.PlayerRemoving:Fire(f.player)
  h.equals(#f.rankingRecords,0)
 end)
 h.test('профиль не открывает ручной ввод до персонажа и сообщает о восстановлении сразу',function()
  local context; local changed
  local rooms={sync=function() end,visiblePlayers=function() return {} end}
  function rooms:onSocialChange(fn) changed=fn end
  function rooms:hasOnlineFriend() return false end
  function rooms:visits() return {} end
  function rooms:manualContext() return context end
  local f=fixture(false,nil,nil,nil,{rooms=rooms})
  h.equals(f.latest().ready,true); h.equals(f.latest().manualReady,false)
  f.complete(f.player); h.equals(f.latest().rounds,0)
  context=1; changed(); h.equals(f.latest().manualReady,true)
  f.complete(f.player); h.equals(f.latest().rounds,1)
  context=nil; changed(); h.equals(f.latest().manualReady,false)
  context=2; changed(); h.equals(f.latest().manualReady,true)
  f.complete(f.player); h.equals(f.latest().rounds,2)
 end)
 h.test('сервер отвергает голый RoundComplete и сохраняет проверенный бонус зрителя',function()
  local owner; local friend={UserId=456}; local present=true; local visit=false; local watch=1; local changed
  local rooms={sync=function() end,visiblePlayers=function() return {} end}
  function rooms:onSocialChange(fn) changed=fn end
  function rooms:hasOnlineFriend(p) owner=p; return present end
  function rooms:isFriend(_,guest) return guest==friend and present end
  function rooms:visits() return if visit then {{owner=owner,guest=friend}} else {} end
  function rooms:manualContext() return 1 end
  function rooms:watching() return if present then watch else nil end
  local f=fixture(false,nil,nil,nil,{rooms=rooms})
  h.equals(f.latest().manual,2)
  f.events.roundComplete.OnServerEvent:Fire(f.player,1e12)
  h.equals(f.latest().slices,0)
  visit=true; changed(); h.near(f.latest().manual,2.2)
  f.complete(f.player,1e12)
  h.near(f.latest().reward,2.2,'новый зритель не усиливает уже завершённый фокус')
  h.near(f.latest().manual,3.3); h.equals(f.latest().socialCounts.spectators,1)
  h.equals(f.latest().social,nil)
  f.complete(f.player); h.near(f.latest().reward,3.3)
  h.equals(f.latest().socialCounts.spectators,1)
  present=false; changed(); h.near(f.latest().manual,1.65)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().data.social.guests['456'],true)
  h.equals(f.record().data.social.spectators['456'],true)
  h.equals(f.record().data.onlineFriend,nil)
 end)
 h.test('ожидание успешной загрузки сохраняет целые циклы и дробный прогресс стажёра',function()
  local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1},productionRemainder=.2},123,900,{
   afterUpdate=function(_,advance) advance(15.5) end,
  })
  h.equals(f.latest().slices,11,'время ответа не вошло в производство')
  h.near(f.latest().productionRemainder,.75)
  h.equals(f.latest().offline,10); h.equals(f.latest().offlineReport.seconds,100)
  h.equals(f.latest().rounds,0); h.equals(f.latest().ordersCompleted,0)
  f.advance(2.5); f.events.purchase.OnServerEvent:Fire(f.player,'invalid')
  h.equals(f.latest().slices,12); h.near(f.latest().productionRemainder,0)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().data.slices,12); h.near(f.record().data.productionRemainder,0)
 end)
 h.test('потерянный ответ загрузки не удваивает производство за ожидание',function()
  for _,committed in {false,true} do
   local replies=0
   local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1}},123,900,{
    beforeUpdate=function(advance)
     replies+=1
     if replies==1 and not committed then advance(7); error('Запрос не дошёл до хранилища') end
    end,
    afterUpdate=function(_,advance)
     if replies==1 then advance(7); error('Ответ потерян после записи') end
     if replies==2 then advance(8) end
    end,
   })
   h.equals(replies,2); h.equals(f.player.kicked,nil)
   h.equals(f.latest().slices,11); h.near(f.latest().productionRemainder,.5)
   h.equals(f.latest().offline,10); h.equals(f.latest().offlineReport.seconds,if committed then 100 else 107)
   f.players.PlayerRemoving:Fire(f.player)
   h.equals(f.record().data.slices,11); h.near(f.record().data.productionRemainder,.5)
  end
 end)
 h.test('офлайн-предел не отнимает производство за ожидание успешного ответа',function()
  local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1}},123,1000-9*3600,{
   afterUpdate=function(_,advance) advance(10) end,
  })
  h.equals(f.latest().offline,1440); h.equals(f.latest().offlineReport.seconds,14400)
  h.equals(f.latest().offlineReport.capped,true)
  h.equals(f.latest().slices,1441)
 end)
 h.test('сервер не обещает неполученную награду при полном кошельке',function()
  local unit=2^20
  local f=fixture(false,{slices=Config.Economy.maxSlices-4*unit,orderProgress=3,productionRemainder=0,levels={craft=3*unit-1}})
  f.complete(f.player)
  h.equals(f.latest().reward,4*unit); h.equals(f.latest().lastOrder.bonus,unit)
  h.equals(f.latest().notice.args.bonus,unit)
  f.advance(); f.complete(f.player)
  h.equals(f.latest().reward,0); h.equals(f.latest().notice.key,'Trick complete · wallet full')
  for _=1,5 do f.advance(); f.complete(f.player) end
  h.equals(f.latest().notice.key,'Order packed · wallet full'); h.equals(f.latest().lastOrder.bonus,0)
  h.equals(f.latest().ordersCompleted,2)
 end)
 h.test('квитанция заказа переживает снимки, покупку и престиж без повторного начисления',function()
  local f=fixture(false,{slices=100,earned=5000})
  h.equals(f.latest().lastOrder,nil)
  for _=1,4 do f.complete(f.player); f.advance() end
  local receipt=f.latest().lastOrder
  h.equals(receipt.name,Config.Orders[1].name); h.equals(receipt.bonus,1); h.equals(receipt.number,1)
  local balance=f.latest().slices
  f.events.requestState.OnServerEvent:Fire(f.player)
  h.equals(f.latest().lastOrder.bonus,1); h.equals(f.latest().slices,balance); h.equals(f.latest().reward,nil)
  f.advance(); f.events.purchase.OnServerEvent:Fire(f.player,'craft',1)
  h.equals(f.latest().manual,2); h.equals(f.latest().lastOrder.bonus,1)
  f.advance(); f.events.prestige.OnServerEvent:Fire(f.player)
  h.equals(f.latest().slices,0); h.equals(f.latest().lastOrder.bonus,1)
  -- Престиж начинает текущий заказ заново, сохраняя число выполненных.
  local remaining=f.latest().order.required-f.latest().order.progress
  for _=1,remaining do f.advance(); f.complete(f.player) end
  h.equals(f.latest().lastOrder.number,2)
  h.equals(f.latest().lastOrder.name,Config.Orders[2].name)
  h.equals(f.latest().lastOrder.bonus,f.latest().manual*Config.Orders[2].bonusRounds)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().data.lastOrder,nil)
 end)
 h.test('сервер начисляет остаток звёзд и объясняет отказ на общем пределе',function()
  local f=fixture(false,{stars=Config.Economy.maxStars-1,earned=20000})
  f.events.prestige.OnServerEvent:Fire(f.player)
  h.equals(f.latest().stars,Config.Economy.maxStars); h.equals(f.latest().notice.args.stars,1)
  f.advance(1); f.events.prestige.OnServerEvent:Fire(f.player)
  h.equals(f.latest().notice.key,'Cocoa star limit reached'); h.equals(f.latest().stars,Config.Economy.maxStars)
 end)
 h.test('запоздалое подтверждение записи не продлевает истёкшую аренду в памяти',function()
  local f=fixture(false,{earned=5000},123,nil,{runSaves=true})
  f.beforeUpdate(function() f.advance(Config.Economy.leaseSeconds+1) end)
  f.events.prestige.OnServerEvent:Fire(f.player)
  assert(f.player.kicked,'Истёкшая аренда была принята как свежая после долгого ответа')
  local sent=#f.sent
  f.advance(1); f.complete(f.player)
  h.equals(#f.sent,sent,'Закрытая сессия продолжает выдавать награды')
 end)
 h.test('сессия не выдаёт награды во время зависшего продления аренды',function()
  local f=fixture(false,{earned=5000},123,nil,{runSaves=true})
  local sent
  f.beforeUpdate(function()
   f.advance(Config.Economy.leaseSeconds-29); sent=#f.sent
   f.complete(f.player)
   h.equals(#f.sent,sent,'Награда выдана по старой истёкшей аренде во время запроса')
  end)
  f.events.prestige.OnServerEvent:Fire(f.player)
  assert(f.player.kicked)
  f.advance(1); f.events.purchase.OnServerEvent:Fire(f.player,'craft')
  f.events.requestState.OnServerEvent:Fire(f.player)
  h.equals(#f.sent,sent,'Закрытая сессия снова стала готовой')
 end)
 h.test('истёкший ответ начальной загрузки не открывает профиль и не записывается при выходе',function()
  local calls=0
  local f=fixture(false,{slices=40},123,nil,{afterUpdate=function(_,advance)
   calls+=1; advance(Config.Economy.leaseSeconds+1)
  end})
  assert(f.player.kicked); h.equals(#f.sent,0,'Просроченный профиль показан как ready')
  local record=f.record(); f.players.PlayerRemoving:Fire(f.player)
  h.equals(calls,1,'Выход перезаписал отклонённый профиль')
  h.equals(f.record(),record); h.equals(record.data.slices,40)
 end)
 h.test("время сохранения отсчитывается от подтверждения и не скрывает задержку",function()
  local fail=false
  local f=fixture(false,{slices=100,earned=5000},123,nil,{
   runSaves=true, afterUpdate=function() if fail then error('Temporary save error') end end,
  })
  h.equals(f.latest().saveStatus,'Progress saved'); h.equals(f.latest().saveAge,0)
  f.advance(20); f.events.purchase.OnServerEvent:Fire(f.player,'craft')
  h.equals(f.latest().saveAge,20,'покупка не означает запись прогресса')
  f.events.requestState.OnServerEvent:Fire(f.player); h.equals(f.latest().saveAge,20)
  f.advance(1); f.events.prestige.OnServerEvent:Fire(f.player)
  h.equals(f.latest().saveAge,0); h.equals(f.latest().saveStatus,'Progress saved')
  f.advance(7); f.events.requestState.OnServerEvent:Fire(f.player); h.equals(f.latest().saveAge,7)
  local delayed=fixture(false,{earned=5000},123,nil,{runSaves=true,afterUpdate=function() if fail then error('Temporary save error') end end})
  fail=true; delayed.advance(5); delayed.events.prestige.OnServerEvent:Fire(delayed.player)
  h.equals(delayed.latest().saveStatus,'Saving delayed · retrying'); h.equals(delayed.latest().saveAge,5)
  local localTest=fixture(true,nil); localTest.advance(10); localTest.events.requestState.OnServerEvent:Fire(localTest.player)
  h.equals(localTest.latest().saveAge,nil); h.equals(localTest.latest().saveStatus,'Test session · progress is not saved')
 end)
 h.test("потерянный ответ загрузки повторяется с той же арендой и не удваивает доход",function()
  local replies=0
  local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1}},123,900,{
   afterUpdate=function(record)
    replies+=1
    if replies==1 then assert(record.owner); error("Ответ потерян после успешной записи") end
   end,
  })
  h.equals(replies,2); h.equals(f.player.kicked,nil)
  h.equals(f.latest().ready,true); h.equals(f.latest().slices,10)
  h.equals(f.latest().offline,10,'потерянный ответ не должен обнулять отчёт')
  h.equals(f.latest().offlineReport.seconds,100)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().data.slices,10); h.equals(f.record().owner,nil)
 end)
 h.test("повторный вход на тот же сервер не забирает ещё занятую запись",function()
  local f=fixture(false,{slices=100})
  local owner=f.record().owner
  local newcomer=makePlayer(f.player.UserId)
  f.players.PlayerAdded:Fire(newcomer)
  assert(newcomer.kicked,"Второй вход принял ещё занятую запись")
  h.equals(f.record().owner,owner)
  f.events.purchase.OnServerEvent:Fire(f.player,"craft")
  f.players.PlayerRemoving:Fire(f.player)
  local nextPlayer=makePlayer(f.player.UserId)
  f.players.PlayerAdded:Fire(nextPlayer)
  h.equals(nextPlayer.kicked,nil); h.equals(f.latest().levels.craft,1)
  assert(f.record().owner~=owner,"Новый вход должен получить собственную аренду")
 end)
 h.test("задержавшееся сохранение вышедшего игрока не перезаписывает новую сессию",function()
  local f=fixture(false,{slices=100})
  local oldOwner=f.record().owner
  f.events.purchase.OnServerEvent:Fire(f.player,"craft")
  local newcomer=makePlayer(f.player.UserId)
  local newOwner
  f.beforeUpdate(function()
   f.advance(Config.Economy.leaseSeconds+1)
   f.players.PlayerAdded:Fire(newcomer)
   h.equals(newcomer.kicked,nil)
   newOwner=f.record().owner
   f.complete(newcomer)
  end)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().owner,newOwner)
  assert(newOwner~=oldOwner,"Аренда ошибочно общая на весь сервер")
  h.equals(f.record().data.levels.craft,0)
  f.players.PlayerRemoving:Fire(newcomer)
  h.equals(f.record().owner,nil)
  h.equals(f.record().data.slices,101)
  h.equals(f.record().data.levels.craft,0)
 end)
 h.test("сервер сохраняет офлайн-отчёт на весь вход без повторного начисления при запросах",function()
  local f=fixture(false,{collectionVersion=2,owned={workers_1=true},levels={kitchen=1}},123,900)
  h.equals(f.latest().offline,10); h.equals(f.latest().offlineReport.seconds,100)
  h.equals(f.latest().slices,10)
  f.advance(); f.events.requestState.OnServerEvent:Fire(f.player)
  h.equals(f.latest().offline,10); h.equals(f.latest().offlineReport.seconds,100)
  h.equals(f.latest().slices,10)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().data.offlineReport,nil)
 end)
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
  for _=1,4 do f.complete(f.player,999999); f.advance() end
  h.equals(f.latest().slices,5); h.equals(f.latest().order.completed,1)
  h.equals(f.latest().reward,2); h.equals(f.latest().notice.key,"Order packed! +{bonus} bonus pieces")
  f.complete(f.player); f.events.roundComplete.OnServerEvent:Fire(f.player)
  h.equals(f.latest().slices,6); h.equals(f.latest().order.progress,1)
  f.players.PlayerRemoving:Fire(f.player)
  h.equals(f.record().version,6); h.equals(f.record().data.ordersCompleted,1)
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
		f.complete(f.player, 999999)
		h.equals(f.latest().slices, 1)
		h.equals(f.latest().reward, 1)
		f.events.roundComplete.OnServerEvent:Fire(f.player, 999999)
		h.equals(f.latest().slices, 1)
		f.advance()
		f.complete(f.player)
		h.equals(f.latest().slices, 2)
	end)
	h.test("настоящий сервер покупает только по своей цене и сохраняет при выходе", function()
		local f = fixture(false, Economy.load({ slices = 3 }))
		f.events.purchase.OnServerEvent:Fire(f.player, "craft", 1, -999)
		h.equals(f.latest().slices, 0)
		h.equals(f.latest().levels.craft, 1)
		f.complete(f.player)
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
