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
end
