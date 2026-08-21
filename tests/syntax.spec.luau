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

	harness.test("оптическая кромка растёт геометрией без альфа-проявления", function()
		local source = fs.readFile("src/client/Game.luau")
		-- Регрессия из записи 2026-08-21: прозрачный CanvasGroup выдавал
		-- фокус, потому что шоколад заметно дорисовывался прямо под курсором.
		harness.equals(source:find("GroupTransparency", 1, true), nil)
		harness.equals(source:find("CanvasGroup", 1, true), nil)
		local movement = assert(source:find("function Game:setLargeProgress", 1, true))
		local growth = assert(source:find("self:setOpticalGrowth(self.largeProgress)", movement, true))
		harness.equals(growth > movement, true)
		-- Кромка продолжает пиксель над резом, а не открывает детали снизу.
		harness.equals(source:find("local sourceY = boundary - boundarySampleInset", 1, true) ~= nil, true)
		-- В шве существует один цветовой мост, а не отдельные копии
		-- Bevel/Face/Relief, обрубавшие скругления на диагонали.
		harness.equals(source:find('\"StretchFill\"', 1, true) ~= nil, true)
		harness.equals(source:find('name .. \"Stretch\"', 1, true), nil)
		harness.equals(source:find("ColorSequenceKeypoint.new(1, bottomColor)", 1, true) ~= nil, true)
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
