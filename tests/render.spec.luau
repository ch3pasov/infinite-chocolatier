--!nostrict
-- Проверяем настоящие окна рендера и координаты их клонов. Числовые проверки
-- не заменяют Studio, но ловят возврат щелей или сдвиг рисунка в перекрытии.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local R = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Geom = require("../src/shared/Geom")
local modules = { Config = Config, Geom = Geom, Recipe = {}, Layout = {}, Theme = { background = R.Color3.new() } }
local shared = { Config = "Config", Geom = "Geom", Recipe = "Recipe" }
local source = fs.readFile("src/client/Game.luau"):gsub("return Game%s*$", "return { render = renderClippedCanonicalTile, Game = Game }")
local exports = luau.load(source, {
	environment = {
		game = { GetService = function() return { WaitForChild = function() return shared end } end },
		script = { Parent = { Theme = "Theme", Layout = "Layout" } },
		require = function(name) return assert(modules[name]) end,
		Instance = R.Instance, Vector2 = R.Vector2, UDim2 = R.UDim2,
	}, injectGlobals = true,
})()
local V = R.Vector2
local line = { a = V.new(0, 70), b = V.new(100, 30) }

local function render(mode)
	local root = R.Instance.new("Frame")
	local template = R.Instance.new("Frame")
	template.Size = R.UDim2.fromOffset(100, 100)
	exports.render(root, template, line, mode, "TestTile", V.zero, V.new(100, 100), 20, 0, 1)
	template:Destroy()
	local columns = root:GetChildren()
	table.sort(columns, function(a, b) return a.Position.X.Offset < b.Position.X.Offset end)
	return root, columns
end

return function(harness)
	harness.test("стыки рисунка имеют перекрытие по обе стороны диагонали", function()
		local upperRoot, upper = render("upper")
		local lowerRoot, lower = render("lower")
		local extensionRoot, extension = render("extension")
		for index, mask in upper do
			local topOfExtension = extension[index].Position.Y.Offset
			local bottomOfUpper = mask.Position.Y.Offset + mask.Size.Y.Offset
			local bottomOfExtension = topOfExtension + extension[index].Size.Y.Offset
			local topOfLower = lower[index].Position.Y.Offset
			-- После Curry-сдвига на 20 единиц продолжение должно заходить
			-- на основание, а не только касаться его дробной границы.
			assert(bottomOfUpper > topOfExtension)
			assert(bottomOfExtension - 20 > topOfLower)
		end
		upperRoot:Destroy(); lowerRoot:Destroy(); extensionRoot:Destroy()
	end)

	harness.test("перекрытие не сдвигает мотив и не выходит за границы дольки", function()
		for _, mode in { "upper", "lower", "extension" } do
			local root, masks = render(mode)
			for index, mask in masks do
				local tile = mask:GetChildren()[1]
				harness.near(mask.Position.X.Offset + tile.Position.X.Offset, 0)
				harness.near(mask.Position.Y.Offset + tile.Position.Y.Offset, 0)
				harness.equals(tile.Size, R.UDim2.fromOffset(100, 100))
				assert(mask.Position.X.Offset + mask.Size.X.Offset <= 100)
				assert(mask.Position.Y.Offset >= 0)
				assert(mask.Position.Y.Offset + mask.Size.Y.Offset <= 100)
				if index < #masks then
					assert(mask.Position.X.Offset + mask.Size.X.Offset > masks[index + 1].Position.X.Offset)
				end
			end
			root:Destroy()
		end
	end)

	harness.test("соединение частей удаляет линии нарезки без новой обводки", function()
		local layer = R.Instance.new("Frame")
		local seam = R.Instance.new("Frame")
		seam.Parent = layer
		exports.Game.drawAssembledSeam({ seamLayer = layer, drawSeam = function() error("Стык снова обведён") end })
		harness.equals(#layer:GetChildren(), 0)
		layer:Destroy()
	end)
end
