return function(harness)
	local Recipe = require("../src/shared/Recipe")
	local result = Recipe.build({
		map = { "AAB", "ACB" },
		cuts = { { { 0, 1 }, { 3, 1 } } },
		slides = { B = { dx = 1, dy = 0 } },
		payout = { piece = "B", amount = 1 },
	})

	harness.test("размеры карты считаются", function()
		harness.equals(result.rows, 2)
		harness.equals(result.cols, 3)
	end)

	harness.test("кусочки группируются по буквам", function()
		harness.equals(#result.pieces.A.cells, 3)
		harness.equals(result.pieces.C.cells[1].r, 1)
	end)

	harness.test("рваная карта отвергается", function()
		local ok = pcall(function()
			Recipe.build({ map = { "AA", "A" } })
		end)
		harness.equals(ok, false)
	end)
end
