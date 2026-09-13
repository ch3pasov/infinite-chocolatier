--!nostrict
-- UI не запускается вне Studio, но синтаксис всех файлов проверяется здесь.

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function collect(dir, result)
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			collect(path, result)
		elseif entry:match("%.luau$") then
			table.insert(result, path)
		end
	end
	return result
end

return function(harness)
	local files = collect("src", {})
	table.sort(files)
	for _, path in ipairs(files) do
		harness.test("синтаксис " .. path, function()
			luau.compile(fs.readFile(path))
		end)
	end

	harness.test("оптическая кромка не проявляется во время движения", function()
		local source = fs.readFile("src/client/Game.luau")
		-- Регрессия из записи 2026-08-21: прозрачный CanvasGroup выдавал
		-- фокус, потому что шоколад заметно дорисовывался прямо под курсором.
		harness.equals(source:find("GroupTransparency", 1, true), nil)
		harness.equals(source:find("setOpticalStretch", 1, true), nil)
		-- Подложка обязана быть отдельным младшим sibling: иначе заранее
		-- подготовленные рамки перекрывают обычные дольки до первого разреза.
		local extensionLayer = assert(source:find('makeLayer(self.board, "OpticalExtensions", 4)', 1, true))
		local pieceLayer = assert(source:find('makeLayer(self.board, "PhysicalPieces", 5)', extensionLayer, true))
		harness.equals(extensionLayer < pieceLayer, true)
		harness.equals(source:find("renderUpperExtensionBody(\n\t\t\t\tpiece.extensionSurface", 1, true) ~= nil, true)
		harness.equals(source:find('"extension",\n\t\t\t\t\t\ttileName .. "Extension"', 1, true) ~= nil, true)
		harness.equals(source:find("piece.extensionMotion.Position", 1, true) ~= nil, true)
		harness.equals(source:find("local extensionTween = TweenService:Create", 1, true) ~= nil, true)
	end)

	harness.test("каждый этап клонирует один канонический мотив дольки", function()
		local source = fs.readFile("src/client/Game.luau")
		local pieceLayer = assert(source:find('makeLayer(self.board, "PhysicalPieces", 5)', 1, true))
		local intactLayer = assert(source:find('makeLayer(self.board, "CanonicalIntactBoard", 6)', pieceLayer, true))
		harness.equals(pieceLayer < intactLayer, true)
		harness.equals(source:find('"CanonicalTileTemplate"', 1, true) ~= nil, true)
		harness.equals(source:find("local tile = template:Clone()", 1, true) ~= nil, true)
		harness.equals(source:find("function Game:renderPrimitive", 1, true), nil)
		harness.equals(source:find("renderUpperExtensionRect", 1, true), nil)
		harness.equals(source:find("function Game:renderCanonicalTilesForPieces", 1, true) ~= nil, true)
		harness.equals(
			source:find("cloneCanonicalTile(piece.surface, template, tileName, tilePosition, piece.baseZ)", 1, true)
				~= nil,
			true
		)
		harness.equals(source:find("cloneCanonicalTile(mask, template", 1, true) ~= nil, true)
		harness.equals(source:find("self.intactLayer.Visible = false", 1, true) ~= nil, true)
		harness.equals(source:find("self.intactLayer.Visible = true", 1, true) ~= nil, true)
	end)

	harness.test("следующий разрез начинается только после отпускания", function()
		local source = fs.readFile("src/client/Game.luau")
		local updateStart = assert(source:find("function Game:updateDrag", 1, true))
		local releaseStart = assert(source:find("function Game:endDrag", updateStart, true))
		local finishDefinition = assert(source:find("function Game:finishCut", releaseStart, true))
		local smoothStart = assert(source:find("function Game:finishCutSmoothly", updateStart, true))
		local updateBody = source:sub(updateStart, smoothStart - 1)
		local releaseBody = source:sub(releaseStart, finishDefinition - 1)
		harness.equals(updateBody:find("self:finishCut()", 1, true), nil)
		harness.equals(releaseBody:find("self:finishCut()", 1, true) ~= nil, true)
	end)

	harness.test("собранная плитка не обводит скрытую Curry-полосу", function()
		local source = fs.readFile("src/client/Game.luau")
		local seamStart = assert(source:find("function Game:drawAssembledSeam", 1, true))
		local nextFunction = assert(source:find("function Game:showCutHint", seamStart, true))
		local seamBody = source:sub(seamStart, nextFunction - 1)
		harness.equals(seamBody:find("self:drawSeam", 1, true), nil)
		harness.equals(seamBody:find("middleA", 1, true), nil)
		harness.equals(seamBody:find("middleB", 1, true), nil)
		harness.equals(source:find("drawCurryGap", 1, true), nil)
	end)

	harness.test("следующий цикл начинается без видимого возврата частей", function()
		local source = fs.readFile("src/client/Game.luau")
		local resetStart = assert(source:find("function Game:beginReset", 1, true))
		local nextFunction = assert(source:find("function Game:resetRound", resetStart, true))
		local resetBody = source:sub(resetStart, nextFunction - 1)
		harness.equals(resetBody:find("self:tweenOffsets", 1, true), nil)
		harness.equals(resetBody:find('"RewardCollectionWipe"', 1, true) ~= nil, true)
		harness.equals(resetBody:find("self.intactLayer.Visible = true", 1, true) ~= nil, true)
		harness.equals(resetBody:find("Возвращаем исходные части", 1, true), nil)
	end)
end
