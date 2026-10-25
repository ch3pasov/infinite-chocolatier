--!strict
-- Чистая модель: цены, доход и сброс одинаковы для сервера, UI и тестов.
local Config = require("./Config")
local Catalog = require("./KitchenCatalog")
local Orders = require("./Orders")
local Social = require("./SocialProgress")
local E = Config.Economy
local Economy = {}
local upgradeById = {}
for _, spec in E.upgrades do upgradeById[spec.id] = spec end

local function levelPrice(spec, level)
	return math.min(E.maxValue, math.ceil(spec.baseCost * spec.growth ^ math.min(level, 200)))
end

local function number(value, fallback, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, 0, maximum)
end

local function recount(data)
 for _,group in {'workers','temper','library','clock','plant','rug','art'} do
  local n=if group=='workers' then 2*data.levels.cafes else 0
  for _,item in Catalog.items do if item.group==group and data.owned[item.id] then n+=1 end end
  data.levels[group]=n
 end
 -- Нанятый стажёр всегда виден; восстанавливаем и ранее скрытые сохранения.
 if not data.equipped.workers then
  for _,item in Catalog.items do
   if item.group=='workers' and data.owned[item.id] then data.equipped.workers=item.id; break end
  end
 end
 for _,id in {'plant','rug','art'} do data.decor[id]=data.equipped[id]==id end
end
function Economy.load(raw)
	raw = if type(raw) == "table" then raw else {}
	local levels = if type(raw.levels) == "table" then raw.levels else {}
	local data = {
		slices = number(raw.slices, 0, E.maxSlices),
		earned = number(raw.earned, 0, E.maxValue),
		lifetime = number(raw.lifetime, 0, E.maxValue),
		stars = math.floor(number(raw.stars, 0, E.maxStars)),
		rounds = math.floor(number(raw.rounds, 0, E.maxValue)),
		ordersCompleted = math.floor(number(raw.ordersCompleted, 0, 1e9)),
		orderProgress = 0,
		-- Старые workers сохраняются; остаток старого секундного цикла
		-- становится той же долей нового полного фокуса. Деньги не списываются.
		productionRemainder = number(raw.productionRemainder, 0, 0.999999999),
		levels = {},
		decor = {},
        collectionVersion=2, owned={}, equipped={}, legacyWorkers=0,
		-- Это предпочтение внешности, поэтому престиж его не стирает.
		apprenticeUserId = math.floor(number(raw.apprenticeUserId, 0, 9007199254740991)),
	}
	data.social, data.socialCounts = Social.load(raw.social)
	data.orderProgress = math.floor(number(raw.orderProgress, 0, Orders.spec(data.ordersCompleted).rounds - 1))
	for _, spec in E.upgrades do
		data.levels[spec.id] = math.floor(number(levels[spec.id], 0, math.min(spec.maxLevel,1e9)))
        if spec.cosmetic then
            data.decor[spec.id] = data.levels[spec.id] > 0 and not (type(raw.decor) == "table" and raw.decor[spec.id] == false)
        end
	end
    -- Старый уровень N означает владение первыми N предметами. Избыточных
    -- стажёров сохраняем отдельно: новая конечная коллекция не отнимает доход.
    local modern=raw.collectionVersion==1 or raw.collectionVersion==2
    data.legacyWorkers=if modern then math.floor(number(raw.legacyWorkers,0,100)) else math.max(0,data.levels.workers-5)
    local oldOwned=if type(raw.owned)=='table' then raw.owned else {}
    local oldEquipped=if type(raw.equipped)=='table' then raw.equipped else {}
    for _,item in Catalog.items do
        local owned=if modern then oldOwned[item.id]==true else data.levels[item.group]>=item.variant
        data.owned[item.id]=owned
        if owned and not modern then
            data.levels.kitchen=1
            if not (type(raw.decor)=='table' and raw.decor[item.group]==false) then data.equipped[item.group]=item.id end
        end
    end
    if modern then
        for group,id in oldEquipped do
            local item=Catalog.byId[id]
            if item and item.group==group and data.owned[id] then data.equipped[group]=id end
        end
    end
    -- Пять старых обликов и прежние стажёры превращаются в полноценные кафе.
    -- Нечётный остаток округляем в пользу игрока, миграция выполняется один раз.
    if raw.collectionVersion~=2 then
        local workers=data.levels.workers
        if modern then
            workers=data.legacyWorkers
            for i=1,5 do if oldOwned['workers_'..i]==true then workers+=1 end end
        end
        if workers>0 then
            data.owned.workers_1=true; data.equipped.workers='workers_1'; data.levels.kitchen=1
            data.levels.cafes=math.max(data.levels.cafes,math.ceil((workers-1)/2))
        end
    end
    data.legacyWorkers=0
    recount(data)
	-- Старый таймер оставлял случайные сотые даже без множителей. Один раз
	-- доводим такой баланс вверх до десятой, не отнимая уже заработанное.
	-- При рецептуре или звёздах сотые могут быть настоящей частью дохода.
	if raw.productionRemainder == nil and data.stars == 0 and data.levels.recipe == 0 then
		local corrected = math.ceil(data.slices * 10 - 1e-9) / 10
		local bonus = math.max(0, corrected - data.slices)
		data.slices = math.min(E.maxSlices, data.slices + bonus)
		data.earned = math.min(E.maxValue, data.earned + bonus)
		data.lifetime = math.min(E.maxValue, data.lifetime + bonus)
	end
	return data
end

-- Единственный расчёт используется выплатами, предпросмотром и страницей бонусов.
function Economy.breakdown(data)
 local l=data.levels
 local counts=data.socialCounts or {guests=0,spectators=0}
 local b={base=Config.Payout.amount, craft=l.craft, library=l.library*E.libraryBonus,
  stars=data.stars, starsEnabled=not data.ignorePrestige,
  recipe=1+l.recipe*E.recipeBonus,
  star=1+(if data.ignorePrestige then 0 else data.stars)*E.starBonus,
  temper=1+l.temper*E.temperBonus,
  online=if data.onlineFriend==true then E.friendOnlineMultiplier else 1,
  guests=1+counts.guests*E.guestBonus, spectators=1+counts.spectators*E.spectatorBonus,
  guestCount=counts.guests, spectatorCount=counts.spectators,
  friendStatus=data.friendStatus or 'ready',
  guestPercent=E.guestBonus*100, spectatorPercent=E.spectatorBonus*100,
  starPercent=E.starBonus*100, workers=l.workers,
  baseSeconds=E.apprenticeCycleSeconds,
  skillSpeed=l.speed*E.apprenticeSpeedBonus, clockSpeed=l.clock*E.clockBonus,
  maxValue=E.maxValue, offlineLimit=E.offlineLimit,
 }
 b.baseReward=b.base+b.craft+b.library
 b.multiplier=b.recipe*b.star*b.temper*b.online*b.guests*b.spectators
 b.uncappedManual=b.baseReward*b.multiplier
 b.manual=math.min(E.maxValue,b.uncappedManual)
 b.speed=1+b.skillSpeed+b.clockSpeed
 b.cycleSeconds=b.baseSeconds/b.speed
 b.cycleTotal=math.min(E.maxValue,b.workers*b.manual)
 b.rate=math.min(E.maxValue,b.workers*b.manual/b.cycleSeconds)
 b.orderFactor=Orders.spec(data.ordersCompleted).bonusRounds
 b.orderBonus=Orders.snapshot(data,b.manual).bonus
 return b
end
function Economy.multiplier(data) return Economy.breakdown(data).multiplier end
function Economy.manual(data) return Economy.breakdown(data).manual end
function Economy.cycleSeconds(data) return Economy.breakdown(data).cycleSeconds end
function Economy.rate(data) return Economy.breakdown(data).rate end
Economy.addSocial = Social.add

function Economy.price(data, id)
 local item=Catalog.byId[id]
 if item then
  if data.levels.kitchen<1 or data.owned[id] then return nil end
  return item.price
 end
 if (id=='speed' or id=='cafes') and not data.owned.workers_1 then return nil end
 for _,spec in E.upgrades do
  if spec.id==id and (spec.id=='kitchen' or spec.maxLevel==math.huge) then
   if data.levels[id]>=spec.maxLevel then return nil end
   -- Ограничена цена, а не число покупок. Не допускаем переполнения степени.
   return levelPrice(spec, data.levels[id])
  end
 end
 return nil
end

-- Суммируем округлённую цену каждого уровня: пакет стоит ровно столько,
-- сколько последовательные одиночные покупки. MAX ограничен работой цикла,
-- а не присланным клиентом количеством или стоимостью.
function Economy.quote(data, id, quantity)
	quantity = if quantity == nil then 1 else quantity
	if quantity ~= 1 and quantity ~= 10 and quantity ~= "max" then return nil, 0 end
	local first = Economy.price(data, id)
	if not first then return nil, 0 end
	if quantity == 1 then return first, 1 end
	local spec = upgradeById[id]
	if not spec or spec.maxLevel ~= math.huge then return nil, 0 end
	local total, count = 0, 0
	for offset = 0, (if quantity == "max" then 99 else 9) do
		local price = levelPrice(spec, data.levels[id] + offset)
		if quantity == "max" and total + price > data.slices then break end
		total += price; count += 1
	end
	return if count > 0 then total else first, count
end

-- Предпросмотр использует те же формулы и число уровней, что покупка.
-- Он не списывает деньги; при пустом MAX показывает ближайший один уровень.
function Economy.preview(data, id, quantity)
	local spec = upgradeById[id]
	local item = Catalog.byId[id]
	if not item and (not spec or spec.maxLevel ~= math.huge) then return nil end
	local price, count = Economy.quote(data, id, quantity)
	if not price then return nil end
	local after = Economy.load(data)
	-- В сетевом снимке флаг называется иначе, чем в серверной сессии.
	after.ignorePrestige = data.ignorePrestige == true or data.prestigeDisabled == true
	after.onlineFriend = data.onlineFriend == true
	after.socialCounts = table.clone(data.socialCounts or after.socialCounts)
	local before = Economy.breakdown(after)
	local manual, rate = before.manual, before.rate
	local cycle, workers = before.cycleSeconds, before.workers
	local missing = math.max(0, price - data.slices)
	local waitSeconds = nil
	if missing > 0 and rate > 0 and price <= E.maxValue then
		-- Доход приходит целыми циклами: средняя скорость занижает ожидание
		-- перед первой выплатой. Учитываем уже отработанную часть цикла.
		local cycles = math.ceil(missing / (workers * manual))
		waitSeconds = math.max(0, cycles - after.productionRemainder) * cycle
	end
	if item then
		-- Бонус конечного предмета даёт владение, а не выбранный облик.
		-- price/quote выше исключают уже купленный предмет и пакетный найм.
		after.owned[id] = true
	else after.levels[id] += math.max(1, count) end
	recount(after)
	local result = Economy.breakdown(after)
	return {
		manualGain = math.max(0, result.manual - manual),
		rateGain = math.max(0, result.rate - rate),
		cycleBefore = cycle, cycleAfter = result.cycleSeconds,
		workersGain = after.levels.workers - workers,
		waitSeconds = waitSeconds,
	}
end

function Economy.credit(data, amount)
	amount = number(amount, 0, E.maxValue)
	local before = data.slices
	data.slices = math.min(E.maxSlices, data.slices + amount)
	data.earned = math.min(E.maxValue, data.earned + amount)
	data.lifetime = math.min(E.maxValue, data.lifetime + amount)
	-- Статистика труда растёт как прежде, но всплывающая награда должна
	-- совпадать с пополнением кошелька, включая его верхний предел.
	return math.max(0, data.slices - before)
end

function Economy.round(data)
	data.rounds = math.min(E.maxValue, data.rounds + 1)
	local manual = Economy.manual(data)
	local completed = Orders.advance(data, manual)
	local credited = Economy.credit(data, manual + (if completed then completed.bonus else 0))
	-- Сначала оплачивается сам фокус, затем премия. Квитанция показывает
	-- только часть премии, которая поместилась; заказ всё равно выполнен.
	if completed then completed.bonus = math.max(0, credited - manual) end
	return credited, completed
end

function Economy.tick(data, elapsed)
	local production = Economy.breakdown(data)
	if production.rate <= 0 then
		data.productionRemainder = 0
		return 0
	end
	-- Храним долю готового фокуса: ускорение не стирает прогресс и не
	-- начисляет задним числом ускоренные циклы. Оплата только за целые циклы.
	local total = data.productionRemainder + number(elapsed, 0, E.offlineLimit) / production.cycleSeconds
	local cycles = math.floor(total + 1e-9)
	data.productionRemainder = math.max(0, total - cycles)
	return Economy.credit(data, production.workers * production.manual * cycles)
end

function Economy.buy(data, id, quantity)
 if type(id)~='string' then return false end
 quantity = if quantity == nil then 1 else quantity
 if quantity ~= 1 and quantity ~= 10 and quantity ~= 'max' then return false end
 local item=Catalog.byId[id]
 if item and data.levels.kitchen>0 and data.owned[id] then
  if quantity ~= 1 then return false end
  data.equipped[item.group]=if item.group~='workers' and data.equipped[item.group]==id then nil else id
  recount(data); return true
 end
 local price,count=Economy.quote(data,id,quantity)
 if not price or count == 0 or data.slices<price then return false end
 data.slices-=price
 if item then
  data.owned[id]=true; data.equipped[item.group]=id; recount(data)
 else data.levels[id]+=count; recount(data) end
 return true, count
end

function Economy.prestigeGain(data)
	return math.min(math.floor(math.sqrt(data.earned / E.prestigeTarget)), math.max(0, E.maxStars - data.stars))
end

-- Шкала идёт от текущей звезды к следующей; после первой награды она
-- не остаётся навсегда полной. Возле лимита не обещаем недостижимую звезду.
function Economy.prestigeProgress(data)
 local gain = Economy.prestigeGain(data)
 local target = (gain + 1)^2 * E.prestigeTarget
 if data.stars + gain >= E.maxStars or target > E.maxValue then
  return { gain = gain, progress = 1 }
 end
 local previous = gain^2 * E.prestigeTarget
 return { gain = gain, target = target, remaining = math.max(0, target - data.earned),
  progress = math.clamp((data.earned - previous) / (target - previous), 0, 1) }
end

function Economy.prestige(data)
	local gain = Economy.prestigeGain(data)
	if gain < 1 or data.stars + gain > E.maxStars then return false end
	data.stars += gain
	data.slices = 0
	data.earned = 0
	data.productionRemainder = 0
	-- Престиж начинает заказ заново; число уже выполненных остаётся статистикой.
	data.orderProgress = 0
	-- Новый цикл начинается с пустой кухни, включая перенесённых старых стажёров.
	for _, spec in E.upgrades do data.levels[spec.id] = 0 end
	data.legacyWorkers = 0
	data.owned = {}
	data.equipped = {}
	for _, item in Catalog.items do data.owned[item.id] = false end
	recount(data)
	return true
end

function Economy.snapshot(data)
	-- Не копируем и не отправляем полные пожизненные списки каждый тик.
 local public=table.clone(data); public.social=nil
 local state = Economy.load(public)
 state.social=nil; state.socialCounts=table.clone(data.socialCounts)
 state.onlineFriend=data.onlineFriend==true
 -- Все поля одного снимка используют один расчёт, без повторного создания
 -- таблиц множителей и премии на каждом серверном тике.
 local bonuses=Economy.breakdown(data)
 state.bonuses=bonuses
	state.manual = bonuses.manual
	state.rate = bonuses.rate
	state.cycleSeconds = bonuses.cycleSeconds
	state.cycleReward = bonuses.manual
	state.order = Orders.snapshot(data, state.manual)
	state.prestigeGain = Economy.prestigeGain(data)
	state.prices = {}
	for _, spec in E.upgrades do state.prices[spec.id] = Economy.price(data, spec.id) end
    for _,item in Catalog.items do state.prices[item.id]=Economy.price(data,item.id) end
	return state
end

return Economy
