return function(harness)
	local Config = require("../src/shared/Config")
	local Geom = require("../src/shared/Geom")
	local V = Vector2

	harness.test("рецепт использует один диагональный рез", function()
		harness.equals(#Config.Recipe.cuts, 1)
		harness.equals(#Config.Recipe.cuts[1], 2)
		harness.equals(Config.Recipe.cuts[1][1][1], 0)
		harness.equals(Config.Recipe.cuts[1][2][1], Config.Board.columns)
		harness.equals(Config.Recipe.cuts[1][2][2], 1.25)
	end)

	harness.test("сдвиг верхней области идёт точно вдоль разреза", function()
		local letter = Config.Trick.movingLetter
		harness.equals(letter, "A")
		local cut = Config.Recipe.cuts[1]
		local line = { a = V.new(cut[1][1], cut[1][2]), b = V.new(cut[2][1], cut[2][2]) }
		local slide = Config.Recipe.slides[letter]
		harness.near(Geom.tangentError(line, V.new(slide.dx, slide.dy)), 0)
	end)

	harness.test("выделяемая долька существовала в исходной плитке", function()
		local reward = Config.Trick.rewardCell
		harness.equals(reward.row >= 1 and reward.row <= Config.Board.rows, true)
		harness.equals(reward.column >= 1 and reward.column <= Config.Board.columns, true)
	end)

	harness.test("сервер выдаёт ровно одну дольку", function()
		harness.equals(Config.Payout.amount, 1)
	end)

	harness.test("результат остаётся видимым до автоматического сброса", function()
		harness.equals(Config.Trick.resetDelay >= 2, true)
	end)
end
