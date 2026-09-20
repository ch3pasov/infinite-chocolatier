--!strict
-- Только завершённый ручной фокус продвигает заказ. Цикл детерминирован,
-- поэтому после входа нужен лишь счётчик заказов и прогресс текущего.
local Config = require("./Config")
local Orders = {}
function Orders.spec(completed)
	return Config.Orders[completed % #Config.Orders + 1]
end
function Orders.snapshot(data, manual)
	local spec = Orders.spec(data.ordersCompleted)
	return {name = spec.name, required = spec.rounds, progress = data.orderProgress,
		bonus = math.min(Config.Economy.maxValue, manual * spec.bonusRounds), completed = data.ordersCompleted}
end
function Orders.advance(data, manual)
	local spec = Orders.spec(data.ordersCompleted)
	data.orderProgress += 1
	if data.orderProgress < spec.rounds then return nil end
	data.orderProgress = 0
	data.ordersCompleted = math.min(1e9, data.ordersCompleted + 1)
	return {name = spec.name, bonus = math.min(Config.Economy.maxValue, manual * spec.bonusRounds)}
end
function Orders.rank(rounds)
	local rank = Config.JournalRanks[1]
	for index, candidate in Config.JournalRanks do
		if rounds < candidate.rounds then return rank, candidate end
		rank = candidate
	end
	return rank, nil
end
return Orders
