--!strict
-- Баланс и рисунок мини-игры собраны в одном месте.

local Config = {}
Config.BalanceTesterUserId = 2630291964
-- Отдельный флаг позволяет убрать эксперимент без изменения ручного фокуса.
Config.Kitchen = { enabled = true }

-- Экспериментальный рендер отделён от правил игры; false возвращает 2D.
Config.Scene3D = {
	enabled = true,
	unitsPerPixel = 0.02,
	-- Единый масштаб всей сцены и камеры сохраняет проекцию, но сокращает
	-- расстояние рендера тонких граней. Во время игры масштаб не меняется.
	renderScale = 0.25,
	knifeScale = 2.2,
	fieldOfView = 5,
	cameraTilt = 34,
	surfaceHeight = 0.48,
	baseHeight = 0.23,
	-- Запасной проход над плиткой позволяет менять части местами на столе.
	layouts = {
		portrait = {
			base={dx=0,dy=0}, upperLeft={dx=-0.35,dy=-0.65},
			upperRight={dx=0.35,dy=-3.1}, stripDouble={dx=-1.7,dy=-4.5},
			stripSingle={dx=-2.3,dy=-4.5},
		},
		landscape = {
			base={dx=0,dy=0}, upperLeft={dx=-0.35,dy=-0.65},
			upperRight={dx=3.5,dy=-1}, stripDouble={dx=-4,dy=-1.2},
			stripSingle={dx=-4.4,dy=-1.2},
		},
	},
	passageY = -3.1,
	colors = {
		body = {65, 30, 20}, bevel = {112, 58, 34}, face = {86, 40, 24},
		relief = {104, 51, 29}, table = {80, 106, 99}, wood = {194, 151, 103},
		woodEdge = {115, 73, 44}, grain = {178, 130, 85}, knife = {199, 215, 216}, handle = {39, 72, 70},
	},
}

Config.Board = {
	columns = 5,
	rows = 5,
	-- Высокая плитка и вытянутые дольки повторяют форму настоящей шоколадки,
	-- а не квадратную таблицу из прототипа.
	-- Поля оставляют место счётчику и многострочной подсказке даже на телефоне.
	viewportPadding = { side = 18, top = 140, bottom = 100 },
}

Config.Recipe = {
	map = {
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
		"AAAAA",
	},

	-- Референс использует Curry-перестановку. Наклон -2/5 выбран не для
	-- красоты: после смещений двух верхних частей их нижние границы совпадают,
	-- но оказываются на 0,2 ряда выше исходной диагонали. Полоса 5 × 0,2
	-- имеет площадь ровно одной дольки.
	cuts = {
		-- Главная диагональ отделяет неподвижное основание.
		{ { 0, 3.5 }, { 5, 1.5 } },
		-- Остальные резы проходят по шоколадным бороздкам и физически
		-- отделяют все четыре верхние части, видимые в референсе.
		{ { 3, 0 }, { 3, 2.3 } },
		{ { 0, 1 }, { 3, 1 } },
		{ { 1, 0 }, { 1, 1 } },
	},

	slides = {
		upperLeft = { dx = 2, dy = -1 },
		upperRight = { dx = -3, dy = 1 },
		stripDouble = { dx = -1, dy = 0 },
		-- Одиночная исходная клетка остаётся слева от собранной плитки.
		stripSingle = { dx = -1.85, dy = 0 },
	},
}

Config.Trick = {
	baseTileWidth = 58,
	baseTileHeight = 92,
	maxBoardWidth = 360,
	maxBoardHeight = 520,
	tileGapRatio = 0.055,
	bevelRatio = 0.075,
	cornerRatio = 0.12,
	-- Только пересечённые диагональю примитивы раскладываются на колонки.
	-- Один пиксель убирает ступеньку, а готовая область двигается одним Frame.
	clipColumnWidth = 1,
	-- Окна одного рисунка слегка перекрываются: округление ClipsDescendants
	-- при UIScale иначе оставляет тёмные пиксели вдоль диагонального контакта.
	clipBleed = 2,
	rewardPiece = "stripSingle",
	cutLabels = {
		"make the main diagonal cut",
		"separate the upper-right piece",
		"cut off the top strip",
		"separate the single piece from the two-piece strip",
	},
	-- Пять частей точно покрывают исходные 5×5. Прямоугольные границы идут
	-- по уже существующим бороздкам, но теперь игрок действительно проводит
	-- по каждой из них до начала перестановки.
	pieces = {
		base = { clip = "lower", bounds = { 0, 0, 5, 5 }, z = 4 },
		upperLeft = { clip = "upper", bounds = { 0, 1, 3, 5 }, z = 7 },
		upperRight = { clip = "upper", bounds = { 3, 0, 5, 5 }, z = 8 },
		stripDouble = { clip = "rect", bounds = { 1, 0, 3, 1 }, z = 10 },
		stripSingle = { clip = "rect", bounds = { 0, 0, 1, 1 }, z = 11 },
	},
	pieceOrder = { "base", "upperLeft", "upperRight", "stripDouble", "stripSingle" },
	exploded = {
		base = { dx = 0, dy = 0 },
		upperLeft = { dx = 1, dy = -0.55 },
		-- Верхний правый кусок уходит вверх, не перекрывая центральный.
		-- Адаптивная сцена резервирует место и для этой крайней позиции.
		upperRight = { dx = -1.5, dy = -1.8 },
		stripDouble = { dx = -1.8, dy = -0.65 },
		stripSingle = { dx = -1.95, dy = -0.65 },
	},
	-- Стрелка крупного сдвига начинается не из центра ограничивающего
	-- прямоугольника, а из точки, гарантированно лежащей внутри диагонального
	-- полигона. Поэтому за неё одинаково удобно браться мышью и пальцем.
	largeHintAnchor = { x = 1.5, y = 1.65 },
	gapRows = 0.2,
	-- Curry-полоса остаётся частью математической модели, но не должна быть
	-- видна игроку как пустая чёрная лента. Нижний край спрайтов двух верхних
	-- полигонов оптически продолжается на ту же высоту. Это и есть незаметное
	-- искажение размеров, которым референс скрывает цену лишней дольки.
	-- Продолжение отрисовано заранее: в цельной плитке оно совпадает с теми же
	-- пикселями основания, а после разделения уже не возникает на глазах.
	opticalStretchRows = 0.2,
	assembledSeamRatio = 0.045,
	explodeDuration = 0.62,
	snapDuration = 0.18,
	-- Полученная долька не возвращается в плитку вместе с остальными частями.
	-- Фон постепенно «съедает» её со стороны собранной шоколадки, как в
	-- оригинальной анимации, пока следующий цикл готовится под цельным слоем.
	collectionDuration = 0.25,
	-- Короткая пауза даёт увидеть результат, не тормозя ручное производство.
	-- Всплывающая награда доживает отдельно и не блокирует следующий фокус.
	resetDelay = 0.35,
}

Config.Cutting = {
	startRadius = 44,
	-- Коридор намеренно чуть шире линии: палец закрывает подсказку и не обязан
	-- двигаться с пиксельной точностью. Выход из коридора больше не стирает
	-- уже сделанный рез, а лишь приостанавливает продвижение.
	slipTolerance = 42,
	-- До готовности остаётся лишь несколько экранных пикселей. Сам переход к
	-- следующему разрезу выполняется только после отпускания мыши или пальца.
	completeAt = 1,
	-- После отпускания последние пиксели доводятся сами, но короткий разрез нельзя пройти
	-- одним нажатием: сначала нужно провести хотя бы 90% его длины.
	finishSnapRadius = 28,
	finishSnapDuration = 0.14,
	finishSnapSteps = 8,
	finishSnapMinProgress = 0.9,
}

Config.Sliding = {
	completeAt = 0.9,
}

Config.Feedback = { duration = 0.85, rise = 52, sparkCount = 8 }

Config.Payout = {
	minInterval = 0.45,
	-- Клиент отправляет только RoundComplete; это число читает только серверная
	-- логика начисления и оно не приходит аргументом RemoteEvent.
	amount = 1,
}

-- Первое улучшение доступно после трёх фокусов; автоматизация появляется
-- вскоре после него, но ручное действие продолжает ускорять развитие.
Config.Economy = {
    upgrades = {
        { id = "kitchen", name = "Open My Kitchen", description = "Unlock the kitchen catalog · first apprentice included", baseCost = 25, growth = 1, maxLevel = 1 },
        { id = "craft", name = "Craftsmanship", description = "+1 piece per manual trick and apprentice cycle", baseCost = 3, growth = 1.55, maxLevel = math.huge },
        { id = "workers", name = "Apprentice Chocolatiers", description = "+1 apprentice · same reward as your manual trick", baseCost = 25, growth = 1.4, maxLevel = 100 },
        { id = "cafes", name = "New Cafe", description = "+2 apprentices · a new cafe in your endless factory", baseCost = 1000, growth = 2, maxLevel = math.huge },
        { id = "speed", name = "Practiced Hands", description = "+20% apprentice cycle speed", baseCost = 40, growth = 1.55, maxLevel = math.huge },
        { id = "recipe", name = "Recipe", description = "+25% manual and automatic income", baseCost = 40, growth = 1.7, maxLevel = math.huge },
        { id = "temper", name = "Tempering Machine", description = "+20% trick reward · adds a tempering machine", baseCost = 80, growth = 2, maxLevel = 5 },
        { id = "library", name = "Recipe Library", description = "+2 pieces per trick · fills your recipe shelf", baseCost = 60, growth = 1.8, maxLevel = 5 },
        { id = "clock", name = "Confectioner’s Clock", description = "+10% apprentice speed · adds a kitchen clock", baseCost = 100, growth = 2, maxLevel = 5 },
        { id = "plant", name = "Cocoa Plant", description = "Decoration · a leafy cocoa plant", baseCost = 45, growth = 1, maxLevel = 1, cosmetic = true },
        { id = "rug", name = "Caramel Rug", description = "Decoration · a warm patterned rug", baseCost = 75, growth = 1, maxLevel = 1, cosmetic = true },
        { id = "art", name = "Golden Cocoa", description = "Decoration · a framed cocoa artwork", baseCost = 120, growth = 1, maxLevel = 1, cosmetic = true },
    },
    -- Один ученик выполняет полный фокус; мастерство усиливает его награду.
    apprenticeCycleSeconds = 10,
    apprenticeSpeedBonus = 0.2,
    recipeBonus = 0.25,
    temperBonus = 0.2,
    libraryBonus = 2,
    clockBonus = 0.1,
    starBonus = 0.25,
    prestigeTarget = 5000,
    offlineLimit = 4 * 60 * 60,
    maxValue = 1e15,
    saveInterval = 30,
    leaseSeconds = 180,
}

return Config
