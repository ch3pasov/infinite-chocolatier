--!strict
-- Чистая модель: цены, доход и сброс одинаковы для сервера, UI и тестов.
local Config = require("./Config")
local E = Config.Economy
local Economy = {}

local function number(value, fallback, maximum)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return fallback
	end
	return math.clamp(value, 0, maximum)
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
		productionRemainder = number(raw.productionRemainder, 0, 0.999999999),
		levels = {},
	}
	for _, spec in E.upgrades do
		data.levels[spec.id] = math.floor(number(levels[spec.id], 0, spec.maxLevel))
	end
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
	return (1 + data.levels.recipe * E.recipeBonus) * (1 + data.stars * E.starBonus)
end

function Economy.manual(data)
	return (Config.Payout.amount + data.levels.craft) * Economy.multiplier(data)
end

function Economy.rate(data)
	return data.levels.workers * E.workerRate * Economy.multiplier(data)
end

function Economy.price(data, id)
	for _, spec in E.upgrades do
		if spec.id == id then
			if data.levels[id] >= spec.maxLevel then return nil end
			return math.ceil(spec.baseCost * spec.growth ^ data.levels[id])
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
	-- task.wait не гарантирует ровно секунду. Дробь времени переносим,
	-- а деньги выдаём только за завершённые секундные циклы производства.
	local total = data.productionRemainder + number(elapsed, 0, E.offlineLimit)
	local seconds = math.floor(total + 1e-9)
	data.productionRemainder = math.max(0, total - seconds)
	return Economy.credit(data, rate * seconds)
end

function Economy.buy(data, id)
	if type(id) ~= "string" then return false end
	local price = Economy.price(data, id)
	if not price or data.slices < price then return false end
	data.slices -= price
	data.levels[id] += 1
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
	for id in data.levels do data.levels[id] = 0 end
	return true
end

function Economy.snapshot(data)
	local state = Economy.load(data)
	state.manual = Economy.manual(data)
	state.rate = Economy.rate(data)
	state.prestigeGain = Economy.prestigeGain(data)
	state.prices = {}
	for _, spec in E.upgrades do state.prices[spec.id] = Economy.price(data, spec.id) end
	return state
end

return Economy
