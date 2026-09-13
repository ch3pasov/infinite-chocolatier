--!nostrict
-- Исполняем настоящие обработчики Game с сигналами вместо Roblox-сервисов.
-- Это позволяет проверить порядок событий нескольких пальцев без эмулятора.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local Roblox = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Geom = require("../src/shared/Geom")
local Recipe = require("../src/shared/Recipe")
local Layout = require("../src/client/Layout")
local source = fs.readFile("src/client/Game.luau")
local V = Roblox.Vector2
local E = Roblox.Enum

local function signal()
	local handlers = {}
	return {
		Connect = function(_, callback)
			table.insert(handlers, callback)
			return {}
		end,
		Fire = function(_, ...)
			for _, callback in handlers do
				callback(...)
			end
		end,
	}
end

local function input(kind, x, y)
	return { UserInputType = E.UserInputType[kind], Position = V.new(x or 0, y or 0), UserInputState = E.UserInputState.Begin }
end

local function fixture(phase)
	local events = {
		InputBegan = signal(), InputChanged = signal(), InputEnded = signal(),
		WindowFocusReleased = signal(), MenuOpened = signal(),
	}
	local modules = { Config = Config, Geom = Geom, Recipe = Recipe, Theme = {}, Layout = Layout }
	local services = {
		UserInputService = events, GuiService = events, TweenService = {},
		ReplicatedStorage = { WaitForChild = function() return { Config = "Config", Geom = "Geom", Recipe = "Recipe" } end },
	}
	local Game = luau.load(source, {
		environment = {
			game = { GetService = function(_, name) return assert(services[name]) end },
			script = { Parent = { Theme = "Theme", Layout = "Layout" } },
			require = function(name) return assert(modules[name]) end,
			Enum = E, Vector2 = V, UDim2 = Roblox.UDim2,
		},
		injectGlobals = true,
	})()
	local view = setmetatable({
		active = phase or "cut", cutIndex = 1, cutProgress = 0,
		largeProgress = 0, stripProgress = 0, completed = 0,
		paths = { { geom = Geom.path({ V.zero, V.new(100, 0) }) } },
		status = {}, startPip = { Visible = true, Size = Roblox.UDim2.fromOffset(20, 20) },
		trick = Config.Trick, recipe = Recipe.build(Config.Recipe),
		tileWidth = 50, tileHeight = 80,
		boardScale = { Scale = 1 }, board = { AbsolutePosition = V.zero },
		gui = { IgnoreGuiInset = true },
	}, Game)
	function view:screenToBoard(point) return point end
	function view:drawProgress(_, progress) self.drawnProgress = progress end
	function view:isInsidePiece() return true end
	function view:setPieceOffset() end
	function view:tweenOffsets(_, _, callback) callback() end
	function view:finishCut() self.completed += 1 end
	function view:finishLargeAssembly() self.completed += 1 end
	function view:finishRound() self.completed += 1 end
	view:bindInput()
	return view, events
end

local function move(events, pointer, x, y)
	pointer.Position = V.new(x, y or 0)
	events.InputChanged:Fire(pointer)
end

return function(harness)
	harness.test("открытое ателье блокирует новые жесты, закрытие позволяет продолжить", function()
		local view, events = fixture()
		view.inputBlocked = true
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		harness.equals(view.drag, nil)
		view.inputBlocked = false
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 50)
		harness.equals(view.cutProgress, 50)
	end)

	harness.test("второй палец не перехватывает и не отпускает разрез", function()
		local view, events = fixture()
		local first, second = input("Touch"), input("Touch", 10)
		events.InputBegan:Fire(first, false)
		local drag = view.drag
		events.InputBegan:Fire(second, false)
		harness.equals(view.drag, drag)
		move(events, first, 50)
		move(events, second, 100, 100)
		harness.equals(view.cutProgress, 50)
		events.InputEnded:Fire(second)
		harness.equals(view.drag, drag)
		move(events, first, 100)
		harness.equals(view.completed, 0)
		events.InputEnded:Fire(first)
		harness.equals(view.completed, 1)
		harness.equals(view.drag, nil)
	end)

	harness.test("мышь и касание не вмешиваются в жест друг друга", function()
		for _, kind in { "MouseButton1", "Touch" } do
			local view, events = fixture()
			local pointer = input(kind)
			events.InputBegan:Fire(pointer, false)
			local alien = input(if kind == "Touch" then "MouseMovement" else "Touch", 50)
			events.InputChanged:Fire(alien)
			harness.equals(view.cutProgress, 0)
			events.InputEnded:Fire(input(if kind == "Touch" then "MouseButton1" else "Touch"))
			harness.equals(view.drag ~= nil, true)
			if kind == "MouseButton1" then
				events.InputChanged:Fire(input("MouseMovement", 50))
				events.InputChanged:Fire(input("MouseMovement", 100))
				pointer.Position = V.new(100, 0)
			else
				move(events, pointer, 50)
				move(events, pointer, 100)
			end
			events.InputEnded:Fire(pointer)
			harness.equals(view.completed, 1)
		end
	end)

	harness.test("потеря фокуса и меню сохраняют разрез без завершения", function()
		for _, event in { "WindowFocusReleased", "MenuOpened" } do
			for _, progress in { 50, 100 } do
				local view, events = fixture()
				local pointer = input("Touch")
				events.InputBegan:Fire(pointer, false)
				move(events, pointer, 50)
				move(events, pointer, progress)
				events[event]:Fire()
				harness.equals(view.drag, nil)
				harness.equals(view.cutProgress, progress)
				harness.equals(view.completed, 0)
				harness.equals(view.startPip.Visible, true)
				-- Запоздалое отпускание после возвращения в окно ничего не начисляет.
				events.InputEnded:Fire(pointer)
				harness.equals(view.completed, 0)
				local resumed = input("Touch", progress)
				events.InputBegan:Fire(resumed, false)
				move(events, resumed, 100)
				events.InputEnded:Fire(resumed)
				harness.equals(view.completed, 1)
			end
		end
	end)

	harness.test("системная отмена касания не завершает готовый разрез", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 50)
		move(events, pointer, 100)
		pointer.UserInputState = E.UserInputState.Cancel
		pointer.Position = V.new(1000, 1000)
		events.InputEnded:Fire(pointer)
		harness.equals(view.completed, 0)
		harness.equals(view.cutProgress, 100)
		harness.equals(view.drag, nil)
	end)

	harness.test("перестановки принадлежат первому пальцу и отменяются без награды", function()
		for _, phase in { "assembleLarge", "assembleStrip" } do
			for _, cancelled in { false, true } do
				local view, events = fixture(phase)
				local first, second = input("Touch"), input("Touch")
				events.InputBegan:Fire(first, false)
				local drag = view.drag
				events.InputBegan:Fire(second, false)
				harness.equals(view.drag, drag)
				first.Position = drag.driver
				events.InputChanged:Fire(first)
				events.InputEnded:Fire(second)
				harness.equals(view.completed, 0)
				harness.equals(view.drag, drag)
				if cancelled then
					events.WindowFocusReleased:Fire()
					harness.equals(view.active, phase)
					harness.equals(view.largeProgress, 0)
					harness.equals(view.stripProgress, 0)
				else
					events.InputEnded:Fire(first)
				end
				harness.equals(view.completed, if cancelled then 0 else 1)
				harness.equals(view.drag, nil)
			end
		end
	end)

	harness.test("обработанное интерфейсом нажатие не начинает разрез", function()
		local view, events = fixture()
		events.InputBegan:Fire(input("Touch"), true)
		harness.equals(view.drag, nil)
	end)

	harness.test("отклонение не стирает разрез и позволяет продолжить без отпускания", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 50)
		move(events, pointer, 50, 100)
		harness.equals(view.cutProgress, 50)
		harness.equals(view.status.Text, "Вернись к подсвеченной точке — прогресс сохранён")
		harness.equals(view.startPip.Visible, true)
		move(events, pointer, 100, 0)
		harness.equals(view.cutProgress, 100)
		harness.equals(view.startPip.Visible, false)
		events.InputEnded:Fire(pointer)
		harness.equals(view.completed, 1)
	end)

	harness.test("быстрый взмах одним событием может закончиться за линией", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 260, 0)
		harness.equals(view.cutProgress, 100)
		events.InputEnded:Fire(pointer)
		harness.equals(view.completed, 1)
	end)

	harness.test("раннее отпускание сохраняет место продолжения", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 55, 0)
		events.InputEnded:Fire(pointer)
		harness.equals(view.completed, 0)
		harness.equals(view.cutProgress, 55)
		harness.equals(view.startPip.Visible, true)

		local resumed = input("Touch", 55, 0)
		events.InputBegan:Fire(resumed, false)
		move(events, resumed, 100, 0)
		events.InputEnded:Fire(resumed)
		harness.equals(view.completed, 1)
	end)

	harness.test("достигнутый конец защёлкивается до отпускания", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 100, 0)
		harness.equals(view.cutProgress, 100)
		move(events, pointer, 1000, 1000)
		harness.equals(view.cutProgress, 100)
		events.InputEnded:Fire(pointer)
		harness.equals(view.completed, 1)
	end)

	harness.test("изменение окна сохраняет этап и пройденную часть разреза", function()
		local view, events = fixture()
		local resized = signal()
		view.root = { AbsoluteSize = V.new(1280, 720), GetPropertyChangedSignal = function() return resized end }
		view.layoutBounds = Layout.bounds(view.recipe, view.trick, view.tileWidth, view.tileHeight, Geom)
		view:bindViewport()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 50)
		view.root.AbsoluteSize = V.new(320, 568)
		resized:Fire()
		harness.equals(view.active, "cut")
		harness.equals(view.cutIndex, 1)
		harness.equals(view.cutProgress, 50)
		harness.equals(view.completed, 0)
		harness.equals(view.drag, nil)
		harness.equals(view.boardScale.Scale < 1, true)
		harness.equals(view.startPip.Position, Roblox.UDim2.fromOffset(40, -10))
	end)

	harness.test("смена размера не сбрасывает анимации и ожидание награды", function()
		for _, phase in { "exploding", "snappingLarge", "assembleStrip", "done", "collecting" } do
			local view = fixture(phase)
			view.root = { AbsoluteSize = V.new(568, 320) }
			view.layoutBounds = Layout.bounds(view.recipe, view.trick, view.tileWidth, view.tileHeight, Geom)
			view.animationToken = 42
			view.cutIndex = 4
			view:fitViewport()
			harness.equals(view.active, phase)
			harness.equals(view.animationToken, 42)
			harness.equals(view.cutIndex, 4)
			harness.equals(view.completed, 0)
		end
	end)

	harness.test("нулевой и повторный размер окна не прерывают захват", function()
		local view, events = fixture()
		view.root = { AbsoluteSize = V.new(320, 568) }
		view.layoutBounds = Layout.bounds(view.recipe, view.trick, view.tileWidth, view.tileHeight, Geom)
		view:fitViewport()
		events.InputBegan:Fire(input("Touch"), false)
		local drag = view.drag
		view:fitViewport()
		harness.equals(view.drag, drag)
		view.root.AbsoluteSize = V.zero
		view:fitViewport()
		harness.equals(view.drag, drag)
	end)

	harness.test("экранные координаты учитывают масштаб и положение плитки", function()
		local view = fixture()
		view.screenToBoard = nil
		view.boardScale.Scale = 0.5
		view.board.AbsolutePosition = V.new(80, 120)
		harness.equals(view:screenToBoard(V.new(130, 145)), V.new(100, 50))
	end)

	harness.test("точность пальца остаётся в экранных пикселях при уменьшении", function()
		local view, events = fixture()
		view.boardScale.Scale = 0.5
		local pointer = input("Touch", 0, 60)
		-- 60 локальных единиц — 30 экранных пикселей, внутри радиуса захвата.
		events.InputBegan:Fire(pointer, false)
		harness.equals(view.drag ~= nil, true)
		move(events, pointer, 80, 50)
		harness.equals(view.cutProgress, 80)
		move(events, pointer, 80, 62)
		harness.equals(view.cutProgress, 80)
	end)
end
