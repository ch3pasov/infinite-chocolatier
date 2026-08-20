--!nostrict
-- За полноэкранной UI-игрой не должен бесконечно падать обычный персонаж Roblox.

local fs = require("@lune/fs")

return function(harness)
	local source = fs.readFile("src/server/init.server.luau")

	harness.test("сервер отключает автоспавн ненужного персонажа", function()
		assert(source:find("Players.CharacterAutoLoads = false", 1, true))
	end)
end
