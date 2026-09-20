--!strict
-- Чистая модель: цены, доход и сброс одинаковы для сервера, UI и тестов.
local Config = require("./Config")
local Catalog = require("./KitchenCatalog")
local E = Config.Economy
local Economy = {}

local function number(value, fallback, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, 0, maximum)
end

local function recount(data)
 for _,group in {'workers','temper','library','clock','plant','rug','art'} do
  local n=if group=='workers' then data.legacyWorkers else 0
  for _,item in Catalog.items do if item.group==group and data.owned[item.id] then n+=1 end end
  data.levels[group]=n
 end
 for _,id in {'plant','rug','art'} do data.decor[id]=data.equipped[id]==id end
end
function Economy.load(raw)
	raw = if type(raw) == "table" then raw else {}
	local levels = if type(raw.levels) == "table" then raw.levels else {}
	local data = {
		slices = number(raw.slices, 0, E.maxValue),
		earned = number(raw.earned, 0, E.maxValue),
		lifetime = number(raw.lifetime, 0, E.maxValue),
		stars = math.floor(number(raw.stars, 0, 1000000)),
		rounds = math.floor(number(raw.rounds, 0, E.maxValue)),
		-- Старые workers сохраняются; остаток старого секундного цикла
		-- становится той же долей нового полного фокуса. Деньги не списываются.
		productionRemainder = number(raw.productionRemainder, 0, 0.999999999),
		levels = {},
		decor = {},
        collectionVersion=1, owned={}, equipped={}, legacyWorkers=0,
	}
	for _, spec in E.upgrades do
		data.levels[spec.id] = math.floor(number(levels[spec.id], 0, math.min(spec.maxLevel,1e9)))
        if spec.cosmetic then
            data.decor[spec.id] = data.levels[spec.id] > 0 and not (type(raw.decor) == "table" and raw.decor[spec.id] == false)
        end
	end
    -- Старый уровень N означает владение первыми N предметами. Избыточных
    -- стажёров сохраняем отдельно: новая конечная коллекция не отнимает доход.
    local modern=raw.collectionVersion==1
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
    recount(data)
	-- Старый таймер оставлял случайные сотые даже без множителей. Один раз
	-- доводим такой баланс вверх до десятой, не отнимая уже заработанное.
	-- При рецептуре или звёздах сотые могут быть настоящей частью дохода.
	if raw.productionRemainder == nil and data.stars == 0 and data.levels.recipe == 0 then
		local corrected = math.ceil(data.slices * 10 - 1e-9) / 10
		local bonus = math.max(0, corrected - data.slices)
		data.slices = math.min(E.maxValue, data.slices + bonus)
		data.earned = math.min(E.maxValue, data.earned + bonus)
		data.lifetime = math.min(E.maxValue, data.lifetime + bonus)
	end
	return data
end

function Economy.multiplier(data)
	return (1 + data.levels.recipe * E.recipeBonus) * (1 + data.stars * E.starBonus) * (1 + data.levels.temper * E.temperBonus)
end

function Economy.manual(data)
	return math.min(E.maxValue,(Config.Payout.amount + data.levels.craft + data.levels.library * E.libraryBonus) * Economy.multiplier(data))
end

function Economy.cycleSeconds(data)
	return E.apprenticeCycleSeconds / (1 + data.levels.speed * E.apprenticeSpeedBonus + data.levels.clock * E.clockBonus)
end

function Economy.rate(data)
	return math.min(E.maxValue,data.levels.workers * Economy.manual(data) / Economy.cycleSeconds(data))
end

function Economy.price(data, id)
 local item=Catalog.byId[id]
 if item then
  if data.levels.kitchen<1 or data.owned[id] then return nil end
  return item.price
 end
 if id=='speed' and data.levels.workers<1 then return nil end
 for _,spec in E.upgrades do
  if spec.id==id and (spec.id=='kitchen' or spec.maxLevel==math.huge) then
   if data.levels[id]>=spec.maxLevel then return nil end
   -- Ограничена цена, а не число покупок. Не допускаем переполнения степени.
   return math.min(E.maxValue,math.ceil(spec.baseCost*spec.growth^math.min(data.levels[id],200)))
  end
 end
 return nil
end

function Economy.credit(data, amount)
	amount = number(amount, 0, E.maxValue)
	data.slices = math.min(E.maxValue, data.slices + amount)
	data.earned = math.min(E.maxValue, data.earned + amount)
	data.lifetime = math.min(E.maxValue, data.lifetime + amount)
	return amount
end

function Economy.round(data)
	data.rounds = math.min(E.maxValue, data.rounds + 1)
	return Economy.credit(data, Economy.manual(data))
end

function Economy.tick(data, elapsed)
	local rate = Economy.rate(data)
	if rate <= 0 then
		data.productionRemainder = 0
		return 0
	end
	-- Храним долю готового фокуса: ускорение не стирает прогресс и не
	-- начисляет задним числом ускоренные циклы. Оплата только за целые циклы.
	local total = data.productionRemainder + number(elapsed, 0, E.offlineLimit) / Economy.cycleSeconds(data)
	local cycles = math.floor(total + 1e-9)
	data.productionRemainder = math.max(0, total - cycles)
	return Economy.credit(data, data.levels.workers * Economy.manual(data) * cycles)
end

function Economy.buy(data, id)
 if type(id)~='string' then return false end
 local item=Catalog.byId[id]
 if item and data.levels.kitchen>0 and data.owned[id] then
  data.equipped[item.group]=if data.equipped[item.group]==id then nil else id
  recount(data); return true
 end
 local price=Economy.price(data,id)
 if not price or data.slices<price then return false end
 data.slices-=price
 if item then
  data.owned[id]=true; data.equipped[item.group]=id; recount(data)
 else data.levels[id]+=1 end
 return true
end

function Economy.prestigeGain(data)
	return math.floor(math.sqrt(data.earned / E.prestigeTarget))
end

function Economy.prestige(data)
	local gain = Economy.prestigeGain(data)
	if gain < 1 or data.stars + gain > 1000000 then return false end
	data.stars += gain
	data.slices = 0
	data.earned = 0
	data.productionRemainder = 0
	for _, spec in E.upgrades do if spec.maxLevel==math.huge then data.levels[spec.id] = 0 end end
	return true
end

function Economy.snapshot(data)
	local state = Economy.load(data)
	state.manual = Economy.manual(data)
	state.rate = Economy.rate(data)
	state.cycleSeconds = Economy.cycleSeconds(data)
	state.cycleReward = Economy.manual(data)
	state.prestigeGain = Economy.prestigeGain(data)
	state.prices = {}
	for _, spec in E.upgrades do state.prices[spec.id] = Economy.price(data, spec.id) end
    for _,item in Catalog.items do state.prices[item.id]=Economy.price(data,item.id) end
	return state
end

return Economy
