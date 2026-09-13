return function(harness)
	local Config = require("../src/shared/Config")
	local Geom = require("../src/shared/Geom")
	local V = Vector2

	harness.test("place разрешает поворот телефона в портретный режим", function()
		-- Одного адаптивного UI недостаточно: без настройки самого place
		-- Roblox блокирует портретную ориентацию ещё до изменения размера Root.
		local fs = require("@lune/fs")
		local serde = require("@lune/serde")
		local project = serde.decode("json", fs.readFile("default.project.json"))
		harness.equals(project.tree.StarterGui["$properties"].ScreenOrientation, "Sensor")
	end)

	harness.test("рецепт требует все четыре разреза пяти частей", function()
		harness.equals(#Config.Recipe.cuts, 4)
		harness.equals(#Config.Recipe.cuts[1], 2)
		harness.equals(Config.Recipe.cuts[1][1][1], 0)
		harness.equals(Config.Recipe.cuts[1][2][1], Config.Board.columns)
		harness.equals(Config.Recipe.cuts[1][2][2], 1.5)

		local rightSplit = Config.Recipe.cuts[2]
		harness.equals(rightSplit[1][1], 3)
		harness.equals(rightSplit[2][1], 3)
		harness.near(rightSplit[2][2], 2.3)

		local topSplit = Config.Recipe.cuts[3]
		harness.equals(topSplit[1][2], 1)
		harness.equals(topSplit[2][2], 1)

		local sliceSplit = Config.Recipe.cuts[4]
		harness.equals(sliceSplit[1][1], 1)
		harness.equals(sliceSplit[2][1], 1)
		harness.equals(#Config.Trick.cutLabels, #Config.Recipe.cuts)
	end)

	harness.test("две крупные части образуют общую новую диагональ", function()
		local cut = Config.Recipe.cuts[1]
		local line = { a = V.new(cut[1][1], cut[1][2]), b = V.new(cut[2][1], cut[2][2]) }
		local left = Config.Recipe.slides.upperLeft
		local right = Config.Recipe.slides.upperRight
		local leftLine = {
			a = line.a + V.new(left.dx, left.dy),
			b = line.b + V.new(left.dx, left.dy),
		}
		local rightLine = {
			a = line.a + V.new(right.dx, right.dy),
			b = line.b + V.new(right.dx, right.dy),
		}
		harness.near(Geom.lineYAtX(leftLine, 2), Geom.lineYAtX(rightLine, 2))
		harness.near((Geom.lineYAtX(line, 0) - Geom.lineYAtX(leftLine, 0)) * Config.Board.columns, 1)
	end)

	harness.test("наградой служит исходная одиночная часть", function()
		harness.equals(Config.Trick.rewardPiece, "stripSingle")
		local bounds = Config.Trick.pieces.stripSingle.bounds
		harness.near((bounds[3] - bounds[1]) * (bounds[4] - bounds[2]), 1)
	end)

	harness.test("двухдольный блок закрывает ровно верхнюю нишу", function()
		local bounds = Config.Trick.pieces.stripDouble.bounds
		local slide = Config.Recipe.slides.stripDouble
		harness.near(bounds[1] + slide.dx, 0)
		harness.near(bounds[2] + slide.dy, 0)
		harness.near(bounds[3] + slide.dx, 2)
		harness.near(bounds[4] + slide.dy, 1)

		local single = Config.Trick.pieces.stripSingle.bounds
		local rewardSlide = Config.Recipe.slides.stripSingle
		harness.equals(single[3] + rewardSlide.dx < 0, true)
	end)

	harness.test("заранее подготовленная кромка полностью скрывает Curry-полосу", function()
		harness.near(Config.Trick.opticalStretchRows, Config.Trick.gapRows)
		harness.equals(Config.Trick.assembledSeamRatio < Config.Trick.gapRows, true)
		-- Динамический коэффициент проявления означал бы, что шоколад снова
		-- дорисовывается во время жеста вместо скрытого начального перекрытия.
		harness.equals(Config.Trick.opticalStretchRevealPower, nil)
	end)

	harness.test("базовый фокус без улучшений даёт одну дольку", function()
		harness.equals(Config.Payout.amount, 1)
	end)

	harness.test("разрез требуется довести почти до физического конца", function()
		harness.equals(Config.Cutting.completeAt >= 0.99, true)
		harness.equals(Config.Cutting.completeAt <= 1, true)
		harness.equals(Config.Cutting.slipTolerance >= Config.Cutting.startRadius * 0.9, true)
		harness.equals(Config.Cutting.maxJump, nil)
		harness.equals(Config.Cutting.backtrack, nil)
	end)

	harness.test("результат остаётся видимым до сбора внешней дольки", function()
		harness.equals(Config.Trick.resetDelay >= 2, true)
		harness.equals(Config.Trick.collectionDuration > 0, true)
		harness.equals(Config.Trick.resetDuration, nil)
	end)
end
