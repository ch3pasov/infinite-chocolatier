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
	end)

	harness.test("следующий разрез начинается только после отпускания", function()
		local source = fs.readFile("src/client/Game.luau")
		local updateStart = assert(source:find("function Game:updateDrag", 1, true))
		local releaseStart = assert(source:find("function Game:endDrag", updateStart, true))
		local finishDefinition = assert(source:find("function Game:finishCut", releaseStart, true))
		local updateBody = source:sub(updateStart, releaseStart - 1)
		local releaseBody = source:sub(releaseStart, finishDefinition - 1)
		harness.equals(updateBody:find("self:finishCut()", 1, true), nil)
		harness.equals(releaseBody:find("self:finishCut()", 1, true) ~= nil, true)
	end)
end
