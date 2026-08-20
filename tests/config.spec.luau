return function(harness)
	local Config = require("../src/shared/Config")
	local Geom = require("../src/shared/Geom")
	local V = Vector2

	harness.test("рецепт использует один диагональный рез", function()
		harness.equals(#Config.Recipe.cuts, 1)
		harness.equals(#Config.Recipe.cuts[1], 2)
		harness.equals(Config.Recipe.cuts[1][1][1], 0)
		harness.equals(Config.Recipe.cuts[1][2][1], Config.Board.columns)
		harness.equals(Config.Recipe.cuts[1][2][2], 1.5)
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

	harness.test("сервер выдаёт ровно одну дольку", function()
		harness.equals(Config.Payout.amount, 1)
	end)

	harness.test("результат остаётся видимым до автоматического сброса", function()
		harness.equals(Config.Trick.resetDelay >= 2, true)
	end)
end
