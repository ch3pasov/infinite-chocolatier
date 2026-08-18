--!strict
-- Баланс и рисунок мини-игры собраны в одном месте.

local Config = {}

Config.Board = {
	columns = 6,
	rows = 4,
	-- Плитка должна быть главным объектом кадра, поэтому минимальный размер
	-- рассчитан и на окно Studio, а не только на маленький viewport.
	maxSize = 640,
	minSize = 420,
	cellInset = 5,
	cornerRadius = 17,
	positionY = 0.42,
	statusPositionY = 0.91,
}

Config.Recipe = {
	map = {
		"AAAABB",
		"AAABBB",
		"AABBBB",
		"CCCCCD",
	},

	-- Координаты вершин идут по клеточной решётке, от верхнего левого угла.
	cuts = {
		{ { 4, 0 }, { 4, 1 }, { 3, 1 }, { 3, 2 }, { 2, 2 }, { 2, 3 } },
		{ { 0, 3 }, { 6, 3 } },
		{ { 5, 3 }, { 5, 4 } },
	},

	slides = {
		B = { dx = -1, dy = 1 },
		D = { dx = 1, dy = 0 },
	},

	payout = {
		piece = "D",
		amount = 1,
	},
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
