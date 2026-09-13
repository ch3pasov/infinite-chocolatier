--!nostrict
-- Проверяем настоящие окна рендера и координаты их клонов. Числовые проверки
-- не заменяют Studio, но ловят возврат щелей или сдвиг рисунка в перекрытии.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local R = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Geom = require("../src/shared/Geom")
local Recipe = require("../src/shared/Recipe")
local pending = {}
local tweenService = {
	Create = function(_, target, _, properties)
		return {
			Play = function() for key, value in properties do target[key] = value end end,
			Cancel = function() end,
		}
	end,
}
local modules = { Config = Config, Geom = Geom, Recipe = {}, Layout = {}, Motion3D = {}, Theme = { background = R.Color3.new(), chocolateDark = R.Color3.new(), accent = R.Color3.new(), accentSoft = R.Color3.new() } }
local shared = { Config = "Config", Geom = "Geom", Recipe = "Recipe" }
local source = fs.readFile("src/client/Game.luau"):gsub("return Game%s*$", "return { render = renderClippedCanonicalTile, Game = Game }")
local exports = luau.load(source, {
	environment = {
		game = { GetService = function(_, name)
			return if name == "TweenService" then tweenService else { WaitForChild = function() return shared end }
		end },
		script = { Parent = { Theme = "Theme", Motion3D = "Motion3D", Layout = "Layout" } },
		require = function(name) return assert(modules[name]) end,
		Instance = R.Instance, Vector2 = R.Vector2, UDim2 = R.UDim2, UDim = R.UDim,
		Enum = R.Enum, TweenInfo = { new = function() return {} end },
		task = { delay = function(_, callback) table.insert(pending, callback) end },
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
	harness.test("эффект показывает точное начисление и удаляет свои объекты", function()
		local root = R.Instance.new("Frame")
		root.AbsoluteSize = V.new(400, 800)
		root.AbsolutePosition = V.zero
		local view = setmetatable({ root = root, board = { AbsolutePosition = V.new(150, 200) },
			boardScale = { Scale = 0.5 }, trick = Config.Trick,
			pieces = { stripSingle = { origin = V.zero, offset = V.new(-100, 0), size = V.new(60, 90) } },
		}, exports.Game)
		view:playRewardEffect(1.25)
		local effect = root:FindFirstChild("RewardEffect")
		assert(effect)
		harness.equals(effect.EarnedSlices.Text, "+1.25")
		harness.equals(#effect:GetChildren(), Config.Feedback.sparkCount + 1)
		while #pending > 0 do table.remove(pending, 1)() end
		harness.equals(#root:GetChildren(), 0)
		root:Destroy()
	end)

	harness.test("бывший внешний угол верхней части заполняет внутренний стык", function()
		local surface = R.Instance.new("Frame")
		local extension = R.Instance.new("Frame")
		local view = setmetatable({
			trick = { clipColumnWidth = 1, opticalStretchRows = 0.2, pieceOrder = { "upperRight" } },
			boardWidth = 290, boardHeight = 460, tileHeight = 92,
			diagonal = { a = V.new(0, 322), b = V.new(290, 138) },
			pieces = { upperRight = { spec = { clip = "upper" }, surface = surface,
				extensionSurface = extension, baseZ = 20 } },
		}, exports.Game)
		view:renderBarBody(10)
		-- После сдвига (-3, +1) правый верхний угол оказывается между
		-- дольками: даже последние полпикселя подложки должны быть заполнены.
		local covered = false
		for _, column in surface:GetChildren() do
			local p, size = column.Position, column.Size
			if p.X.Offset <= 289.5 and p.X.Offset + size.X.Offset >= 289.5
				and p.Y.Offset <= 0.5 and p.Y.Offset + size.Y.Offset >= 0.5 then
				covered = true
			end
		end
		harness.equals(covered, true)
		surface:Destroy(); extension:Destroy()
	end)

	harness.test("кромка непрерывна от разлёта до отпускания и отмены сдвига", function()
		local root = R.Instance.new("Frame")
		local function frame()
			local result = R.Instance.new("Frame")
			result.Parent = root
			return result
		end
		local view = setmetatable({
			active = "cut", cutIndex = 1, paths = { {} }, status = {},
			trick = Config.Trick, recipe = Recipe.build(Config.Recipe),
			tileWidth = 50, tileHeight = 80, pieces = {}, tweens = {}, animationToken = 0,
			hintLayer = frame(), progressLayer = frame(), seamLayer = frame(), intactLayer = frame(),
			drawSeam = function() end, showLargeHint = function() end, showStripHint = function() end,
		}, exports.Game)
		for _, name in Config.Trick.pieceOrder do
			view.pieces[name] = { origin = V.new(7, 11), motion = frame() }
		end
		for _, name in { "upperLeft", "upperRight" } do
			view.pieces[name].extensionMotion = frame()
		end
		local function check()
			for _, name in { "upperLeft", "upperRight" } do
				local piece = view.pieces[name]
				harness.equals(piece.extensionMotion.Visible, true)
				harness.equals(piece.extensionMotion.Position, piece.motion.Position)
			end
		end
		local function flush()
			while #pending > 0 do
				table.remove(pending, 1)()
				check()
			end
		end
		view:finishCut()
		flush()
		harness.equals(view.active, "assembleLarge")
		-- Прямой ход, отмена с возвратом и повторный ход: ни на одном
		-- переходе нельзя выключать подложку и возвращать её на финише.
		for _, cancelled in { true, false } do
			for step = 0, 100 do
				view:setLargeProgress(step / 100)
				check()
			end
			view.drag = { kind = "large" }
			view:endDrag(cancelled)
			check()
			flush()
		end
		harness.equals(view.active, "assembleStrip")
		root:Destroy()
	end)

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
