--!nostrict
-- Автоспавн отключён: KitchenRooms сначала готовит пол и только затем аватар.

local fs = require("@lune/fs")

return function(harness)
	local source = fs.readFile("src/server/init.server.luau")

	harness.test("сервер передаёт спавн персонажа безопасной кухне", function()
		assert(source:find("Players.CharacterAutoLoads = false", 1, true))
	end)
end
