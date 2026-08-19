--!strict
-- Баланс и рисунок мини-игры собраны в одном месте.

local Config = {}

Config.Board = {
	columns = 5,
	rows = 5,
	-- Вертикальная плитка лучше сохраняет иллюзию: узкая и высокая долька
	-- не выдаёт небольшое перераспределение ширины после диагонального сдвига.
	maxSize = 520,
	minSize = 300,
	cellInset = 4,
	cornerRadius = 9,
	positionY = 0.40,
	statusPositionY = 0.91,
}

Config.Recipe = {
	map = {
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
	},

	-- Это один непрерывный диагональный рез, а не набор резов по клеточным
	-- границам. Доли остаются прямоугольными, поэтому сдвиг не выглядит как
	-- простое удаление одной квадратной клетки.
	cuts = {
		{ { 0.08, 3.72 }, { 4.92, 1.28 } },
	},

	slides = {
		-- Сдвигаем верхнюю диагональную область вправо и немного вверх. Так
		-- появляется тонкая зона перераспределения, а не пропадает клетка.
		A = { dx = 0.86, dy = -0.24 },
	},

	payout = {
		piece = "A",
		amount = 1,
	},
}

Config.Trick = {
	-- Верхняя область отделяется одной диагональю и после реза двигается
	-- целиком. Это и есть источник иллюзии, а не удаление клетки карты.
	movingLetter = "A",
	baseTileWidth = 66,
	baseTileHeight = 88,
	maxBoardWidth = 450,
	maxBoardHeight = 390,
	minBoardWidth = 300,
	minBoardHeight = 280,
	wedgeStripHeight = 4,
	extraSliceWidth = 0.42,
	extraSliceHeight = 0.70,
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
}

return Config
