--!strict
-- Описывает плитку данными, не создавая Roblox-инстансы.

local Recipe = {}

type Cell = { r: number, c: number }
type Piece = {
	letter: string,
	cells: { Cell },
	minR: number,
	maxR: number,
	minC: number,
	maxC: number,
}

local function fail(message: string): never
	error("Recipe: " .. message, 2)
end

function Recipe.build(def)
	if type(def) ~= "table" or type(def.map) ~= "table" or #def.map == 0 then
		fail("map must be a non-empty array")
	end

	local rows = #def.map
	local cols = #def.map[1]
	if cols == 0 then
		fail("map rows must not be empty")
	end

	local pieces: { [string]: Piece } = {}
	local order: { string } = {}
	for r, row in ipairs(def.map) do
		if type(row) ~= "string" or #row ~= cols then
			fail("map must be rectangular")
		end
		for c = 1, cols do
			local letter = string.sub(row, c, c)
			if letter ~= " " then
				if not pieces[letter] then
					pieces[letter] = {
						letter = letter,
						cells = {},
						minR = r - 1,
						maxR = r - 1,
						minC = c - 1,
						maxC = c - 1,
					}
					table.insert(order, letter)
				end
				local piece = pieces[letter]
				table.insert(piece.cells, { r = r - 1, c = c - 1 })
				piece.minR = math.min(piece.minR, r - 1)
				piece.maxR = math.max(piece.maxR, r - 1)
				piece.minC = math.min(piece.minC, c - 1)
				piece.maxC = math.max(piece.maxC, c - 1)
			end
		end
	end

	local cuts = {}
	for cutIndex, cut in ipairs(def.cuts or {}) do
		if type(cut) ~= "table" or #cut < 2 then
			fail(`cut {cutIndex} must contain at least two points`)
		end
		local points = {}
		for pointIndex, point in ipairs(cut) do
			if type(point) ~= "table" or type(point[1]) ~= "number" or type(point[2]) ~= "number" then
				fail(`cut {cutIndex}, point {pointIndex} is invalid`)
			end
			if point[1] < 0 or point[1] > cols or point[2] < 0 or point[2] > rows then
				fail(`cut {cutIndex}, point {pointIndex} is outside the board`)
			end
			table.insert(points, { x = point[1], y = point[2] })
		end
		table.insert(cuts, points)
	end

	return {
		rows = rows,
		cols = cols,
		map = def.map,
		pieces = pieces,
		order = order,
		cuts = cuts,
		slides = def.slides or {},
		payout = def.payout,
	}
end

return Recipe
