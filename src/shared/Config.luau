--!strict
-- Баланс и рисунок мини-игры собраны в одном месте.

local Config = {}

Config.Board = {
	columns = 5,
	rows = 5,
	-- Высокая плитка и вытянутые дольки повторяют форму настоящей шоколадки,
	-- а не квадратную таблицу из прототипа.
	positionY = 0.50,
	statusPositionY = 0.96,
}

Config.Recipe = {
	map = {
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
	},

	-- Концы лежат точно на боковых гранях. Наклон -1/2 выбран намеренно:
	-- перенос (1, -1/2) идёт вдоль самого шва и не создаёт щель внутри плитки.
	cuts = {
		{ { 0, 3.75 }, { 5, 1.25 } },
	},

	slides = {
		A = { dx = 1, dy = -0.5 },
	},
}

Config.Trick = {
	movingLetter = "A",
	baseTileWidth = 58,
	baseTileHeight = 92,
	maxBoardWidth = 360,
	maxBoardHeight = 520,
	minBoardWidth = 250,
	minBoardHeight = 350,
	tileGapRatio = 0.055,
	bevelRatio = 0.075,
	cornerRatio = 0.12,
	-- Только пересечённые диагональю примитивы раскладываются на колонки.
	-- Один пиксель убирает ступеньку, а готовая область двигается одним Frame.
	clipColumnWidth = 1,
	rewardCell = { row = 1, column = 5 },
	-- Игрок должен успеть увидеть подсвеченную перераспределённую дольку до
	-- автоматического возврата к цельной плитке.
	resetDelay = 3,
}

Config.Cutting = {
	startRadius = 44,
	slipTolerance = 30,
	maxJump = 58,
	backtrack = 22,
	completeAt = 0.94,
}

Config.Sliding = {
	snapRadius = 34,
	separation = 10,
}

Config.Payout = {
	minInterval = 0.45,
	-- Клиент отправляет только RoundComplete; это число читает только серверная
	-- логика начисления и оно не приходит аргументом RemoteEvent.
	amount = 1,
}

return Config
