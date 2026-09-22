--!nonstrict
-- Локальный эксперимент над настоящей экономикой. Политика покупок —
-- эвристика, а не оптимальный игрок; время прогулки/чтения меню не моделируется.
local Economy=require('../../src/shared/Economy')
local Config=require('../../src/shared/Config')
local Catalog=require('../../src/shared/KitchenCatalog')
local Simulator={}
local offers={}
for _,spec in Config.Economy.upgrades do
 if spec.id=='kitchen' or spec.maxLevel==math.huge then table.insert(offers,spec.id) end
end
for _,item in Catalog.items do table.insert(offers,item.id) end
table.sort(offers)
local rounds,bonus=0,0
for _,order in Config.Orders do rounds+=order.rounds; bonus+=order.bonusRounds end
local orderMultiplier=1+bonus/rounds

local function income(data,roundSeconds,manual)
 return Economy.rate(data)+(if manual then Economy.manual(data)*orderMultiplier/roundSeconds else 0)
end
function Simulator.choose(data,strategy,roundSeconds,manual)
 if strategy=='none' then return nil end
 if data.levels.kitchen>0 and not data.owned.workers_1 then return 'workers_1' end
 if strategy=='cafe' then return if data.levels.kitchen==0 then 'kitchen' else 'cafes' end
 assert(strategy=='invest' or strategy=='idle','неизвестная стратегия')
 local before=income(data,roundSeconds,manual); local chosen,best=nil,math.huge
 for _,id in offers do
  local price=Economy.price(data,id)
  if price then
   local after=Economy.load(data); after.slices=price
   assert(Economy.buy(after,id),'кандидат не покупается: '..id)
   -- Доступ к книге включает бесплатный первый найм. Сама симуляция
   -- всё равно выполняет две отдельные покупки с серверной паузой.
   if id=='kitchen' then assert(Economy.buy(after,'workers_1')) end
   local gain=income(after,roundSeconds,manual)-before
   if gain>0 then
    local payback=price/gain
    if payback<best then chosen,best=id,payback end
   end
  end
 end
 return chosen
end

function Simulator.run(options)
 options=options or {}
 local duration=options.seconds or 3600; local roundSeconds=options.roundSeconds or 8
 assert(type(duration)=='number' and duration>0 and duration<=4*3600,'длительность должна быть в пределах 4 часов')
 assert(type(roundSeconds)=='number' and roundSeconds>=Config.Payout.minInterval and roundSeconds<=3600,'неверный интервал ручных фокусов')
 local strategy=options.strategy or 'invest'
 local data=Economy.load(options.initial)
 local result={strategy=strategy,seconds=duration,roundSeconds=roundSeconds,milestones={},purchases={},manualRounds=0}
 local time,last,nextRound,nextTick,nextBuy=0,0,roundSeconds,1,0
 local function manualActive() return strategy~='idle' or not data.owned.workers_1 end
 local function choose()
  if options.choose then return options.choose(data) end
  return Simulator.choose(data,strategy,roundSeconds,manualActive())
 end
 local function mark()
  for name,reached in {craft=data.levels.craft>0,kitchen=data.levels.kitchen>0,
   apprentice=data.owned.workers_1,cafe=data.levels.cafes>0,prestige=Economy.prestigeGain(data)>0} do
   if reached and result.milestones[name]==nil then result.milestones[name]=time end
  end
 end
 local choice=choose()
 while true do
  Economy.tick(data,time-last); last=time
  if manualActive() and time+1e-8>=nextRound then
   Economy.round(data); result.manualRounds+=1; nextRound+=roundSeconds
  end
  mark()
  local price=if choice then Economy.price(data,choice) else nil
  if price and data.slices>=price and time+1e-8>=nextBuy then
   local before=data.slices
   assert(Economy.buy(data,choice),'покупка не выполнена: '..choice)
   table.insert(result.purchases,{seconds=time,id=choice,price=before-data.slices})
   nextBuy=time+.2
   mark(); choice=choose()
  end
  if time>=duration then break end
  if nextTick<=time+1e-8 then nextTick=math.floor(time+1e-8)+1 end
  -- Секундный серверный тик и события ручной резки/покупки вызывают
  -- один accrue. Цена и выплата не интерполируются по средней скорости.
  local nextTime=math.min(duration,nextTick,if manualActive() then nextRound else math.huge)
  price=if choice then Economy.price(data,choice) else nil
  if price and data.slices>=price then nextTime=math.min(nextTime,nextBuy) end
  assert(nextTime>time,'симуляция перестала продвигать время')
  time=nextTime
 end
 result.final=Economy.snapshot(data)
 return result
end
return Simulator
