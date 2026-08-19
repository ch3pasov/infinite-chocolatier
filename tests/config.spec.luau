return function(harness)
	local Config = require("../src/shared/Config")

	harness.test("рецепт использует один диагональный рез", function()
		harness.equals(#Config.Recipe.cuts, 1)
		harness.equals(#Config.Recipe.cuts[1], 2)
		harness.equals(Config.Recipe.cuts[1][1][1], 0.08)
		harness.equals(Config.Recipe.cuts[1][2][2], 1.28)
	end)

	harness.test("область сдвига существует в карте", function()
		local letter = Config.Trick.movingLetter
		harness.equals(letter, "A")
		harness.equals(Config.Recipe.slides[letter].dx, 0.86)
		harness.equals(Config.Recipe.slides[letter].dy, -0.24)
	end)
end
