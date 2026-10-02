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
local Motion = require("../src/client/Motion3D")
local Action = require("../src/client/WorkstationAction")
local Wire = require("../src/shared/WorkstationWire")
local source = fs.readFile("src/client/Game.luau")
local V = Roblox.Vector2
local E = Roblox.Enum

local function signal()
	local handlers = {}
	return {
		Connect = function(_, callback)
			local connection = { Connected = true }
			function connection:Disconnect() self.Connected = false end
			table.insert(handlers, { connection = connection, callback = callback })
			return connection
		end,
		Fire = function(_, ...)
			for _, handler in handlers do
				if handler.connection.Connected then handler.callback(...) end
			end
		end,
	}
end

local function input(kind, x, y)
	return { UserInputType = E.UserInputType[kind], Position = V.new(x or 0, y or 0), UserInputState = E.UserInputState.Begin }
end

local function fixture(phase)
	local pending = {}
	local events = {
		InputBegan = signal(), InputChanged = signal(), InputEnded = signal(),
		WindowFocusReleased = signal(), MenuOpened = signal(), TextBoxFocused = signal(),
		GetFocusedTextBox = function(self) return self.focused end,
	}
	local modules = { Localization = {set=function(label,source) label.Text=source end, token=function(source) return source end}, Config = Config, Geom = Geom, Recipe = Recipe, Theme = {}, Layout = Layout, Motion3D = Motion }
	local tweenService = { Create = function(_, value, _, goal)
		local tween = { Play = function() end, Cancel = function() end }
		function tween:advance(progress) value.Value = progress; value.Changed:Fire(progress) end
		tween.goal = goal.Value; events.tween = tween
		return tween
	end }
	local services = {
		UserInputService = events, GuiService = events, TweenService = tweenService,
		ReplicatedStorage = { WaitForChild = function() return { Config = "Config", Geom = "Geom", Recipe = "Recipe" } end },
	}
	local Game = luau.load(source, {
		environment = {
			game = { GetService = function(_, name) return assert(services[name]) end },
			script = { Parent = { Localization = "Localization", Theme = "Theme", Motion3D = "Motion3D", Layout = "Layout" } },
			require = function(name) return assert(modules[name]) end,
			Enum = E, Vector2 = V, UDim2 = Roblox.UDim2,
			Instance = { new = function(class)
				assert(class == "NumberValue")
				return { Changed = signal(), Destroy = function() end }
			end },
			TweenInfo = { new = function() return {} end },
			task = { delay = function(_, callback) table.insert(pending, callback) end },
		},
		injectGlobals = true,
	})()
	local view = setmetatable({
		active = phase or "cut", cutIndex = 1, cutProgress = 0,
		tweens = {}, animationToken = 0,
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
	function events:stepAnimation() if #pending > 0 then table.remove(pending, 1)() end end
	function events:finishAnimation() while #pending > 0 do self:stepAnimation() end end
	return view, events
end

local function planarFixture(layout)
	local view, events = fixture("assembleStrip")
	view.planarLayout = layout; view.trick = table.clone(Config.Trick)
	view.trick.exploded = Config.Scene3D.layouts[layout]
	view.intactLayer = { Visible = false }; view.pieces = {}
	for index, name in view.trick.pieceOrder do
		view.pieces[name] = { origin = V.new(index * 7, index * 11), motion = { Visible = true } }
	end
	-- Реальный обработчик обновляет экранные координаты; снимок станции
	-- должен отличаться от них только выбранной раскладкой, а не прогрессом.
	view.setPieceOffset = nil
	return view, events
end

local function move(events, pointer, x, y)
	pointer.Position = V.new(x, y or 0)
	events.InputChanged:Fire(pointer)
end

return function(harness)
	harness.test("телефон и широкий экран показывают зрителю ту же перестановку, что ученик", function()
		for _, layout in { "portrait", "landscape" } do
			local view = planarFixture(layout)
			for _, stage in { {"explode", .45, .13}, {"large", .58, .16}, {"join", .74, .1}, {"strip", .84, .12} } do
				for _, progress in { 0, .2, .5, .8, 1 } do
					view:setPlanarProgress(stage[1], progress)
					local manual = Action.player(view, Config)
					local received = assert(Wire.clean(manual))
					local npc = Action.cycle(stage[2] + stage[3] * progress, Config, view.recipe.slides)
					for _, name in view.trick.pieceOrder do
						harness.near((received.offsets[name] - npc.offsets[name]).Magnitude, 0)
						local screen = view.pieces[name].offset
						local actual = Motion.pose(name, stage[1], progress, view.trick.exploded, view.recipe.slides, Config.Scene3D.passageY)
						harness.near((screen - V.new(actual.X * view.tileWidth, actual.Y * view.tileHeight)).Magnitude, 0)
					end
					harness.near((received.rightHand - npc.rightHand).Magnitude, 0)
					harness.near((received.leftHand - npc.leftHand).Magnitude, 0)
				end
			end
			view:setPlanarProgress("explode", 1)
			local single = view.pieces.stripSingle.offset
			harness.near(single.Y / view.tileHeight, Config.Scene3D.layouts[layout].stripSingle.dy)
			local station = Action.player(view, Config).offsets.stripSingle
			harness.near(station.Y, Config.Scene3D.layouts.landscape.stripSingle.dy)
		end
	end)
	harness.test("начало анимации и отмена двух долек сразу обновляют снимок станции", function()
		local view, events = planarFixture("portrait")
		view:setPlanarProgress("large", 1)
		view:tweenPlanar("join", 0, 1, .24, function() end)
		harness.equals(view.planarPhase, "join"); harness.equals(view.planarProgress, 0)
		events:finishAnimation()
		view:setStripProgress(.6); view.drag = { kind = "strip" }
		view:endDrag(true)
		harness.equals(view.active, "snappingStrip"); harness.equals(view.planarPhase, "strip")
		harness.near(view.planarProgress, .6); harness.equals(events.tween.goal, 0)
		events.tween:advance(.3)
		local received = assert(Wire.clean(Action.player(view, Config)))
		local npc = Action.cycle(.84 + .12 * .3, Config, view.recipe.slides)
		harness.near((received.offsets.stripSingle - npc.offsets.stripSingle).Magnitude, 0)
		events:finishAnimation()
		harness.equals(view.active, "assembleStrip"); harness.equals(view.stripProgress, 0)
		harness.equals(view.planarProgress, 0); harness.equals(view.completed, 0)
		-- Новый разрез не должен отправлять зрителям смещения старого раунда.
		view.choosePieceLayout = function() return false end
		view.fitViewport = function() end; view.showCutHint = function() end
		view.seamLayer = { GetChildren = function() return {} end }; view.progressLayer = view.seamLayer
		view:resetRound()
		harness.equals(view.planarPhase, nil); harness.equals(view.planarProgress, nil)
		for _, piece in view.pieces do harness.equals(piece.offset, V.zero) end
	end)
	harness.test("удалённая игра отпускает все подписки и не завершает старый жест", function()
		local view, events = fixture(); local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false); move(events, pointer, 50)
		local connections = { view.began, view.changed, view.ended, view.focusReleased, view.menuOpened, view.textFocused }
		view.viewportChanged = signal():Connect(function() end); table.insert(connections, view.viewportChanged)
		local cancelled = 0
		view.tweens = { { Cancel = function() cancelled += 1 end } }
		view:destroy(); local token = view.animationToken; view:destroy()
		harness.equals(cancelled, 1); harness.equals(view.animationToken, token)
		for _, connection in connections do harness.equals(connection.Connected, false) end
		harness.equals(view.drag, nil)
		move(events, pointer, 100); events.InputEnded:Fire(pointer)
		events.InputBegan:Fire(input("Touch"), false)
		events.MenuOpened:Fire(); events.TextBoxFocused:Fire({}); events.WindowFocusReleased:Fire()
		events:finishAnimation()
		harness.equals(view.completed, 0); harness.equals(view.cutProgress, 50)
	end)
	harness.test("доводка разреза отменяется при удалении интерфейса", function()
		local view, events = fixture(); local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false); move(events, pointer, 95); events.InputEnded:Fire(pointer)
		harness.equals(view.active, "finishingCut")
		view:destroy(); events:finishAnimation()
		harness.equals(view.completed, 0); harness.equals(view.cutProgress, 95)
		-- Поздняя награда не пытается создать объекты на уже удалённом Root.
		view:playRewardEffect(10)
	end)
	harness.test("меню Roblox и текстовое поле блокируют новый разрез даже без processed",function()
		for _,mode in {'menu','text'} do
			local view,events=fixture()
			if mode=='menu' then events.MenuIsOpen=true else events.focused={} end
			local pointer=input('Touch')
			events.InputBegan:Fire(pointer,false)
			harness.equals(view.drag,nil); harness.equals(view.cutProgress,0)
			events.MenuIsOpen=false; events.focused=nil
			events.InputBegan:Fire(pointer,false); move(events,pointer,50)
			harness.equals(view.cutProgress,50)
		end
	end)
	harness.test("переход в текстовое поле отменяет захват и сохраняет часть разреза",function()
		local view,events=fixture(); local pointer=input('Touch')
		events.InputBegan:Fire(pointer,false); move(events,pointer,55)
		events.focused={}; events.TextBoxFocused:Fire(events.focused)
		harness.equals(view.drag,nil); harness.equals(view.cutProgress,55)
		move(events,pointer,100); events.InputEnded:Fire(pointer)
		harness.equals(view.completed,0); harness.equals(view.cutProgress,55)
		events.focused=nil; local resumed=input('Touch',55)
		events.InputBegan:Fire(resumed,false); move(events,resumed,100); events.InputEnded:Fire(resumed)
		harness.equals(view.completed,1)
	end)
	harness.test("отмена почти готового разреза не запускает доводку", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 95)
		events.WindowFocusReleased:Fire()
		events:finishAnimation()
		harness.equals(view.cutProgress, 95)
		harness.equals(view.completed, 0)
		harness.equals(view.active, "cut")
	end)

	harness.test("автодоводка начинается только после отпускания и дорисовывает плавно", function()
		for _, scale in { 0.5, 1, 2 } do
			local view, events = fixture()
			view.boardScale.Scale = scale
			view.paths = { { geom = Geom.path({ V.zero, V.new(1000, 0) }) } }
			local pointer = input("Touch")
			events.InputBegan:Fire(pointer, false)
			move(events, pointer, 1000 - 29 / scale)
			harness.equals(view.drag.ready, false)
			move(events, pointer, 1000 - 27 / scale)
			local before = 1000 - 27 / scale
			harness.near(view.cutProgress, before)
			harness.near(view.drawnProgress, before)
			events.InputEnded:Fire(pointer)
			harness.equals(view.completed, 0)
			harness.equals(view.active, "finishingCut")
			events:stepAnimation()
			assert(view.cutProgress > before and view.cutProgress < 1000)
			events:finishAnimation()
			harness.equals(view.cutProgress, 1000)
			harness.equals(view.completed, 1)
		end
	end)

	harness.test("короткий разрез доводится только после 90 процентов", function()
		local view, events = fixture()
		view.paths = { { geom = Geom.path({ V.zero, V.new(10, 0) }) } }
		local pointer = input("MouseButton1")
		events.InputBegan:Fire(pointer, false)
		view:updateDrag(V.new(8, 0))
		harness.equals(view.cutProgress, 8)
		view:updateDrag(V.new(9, 0))
		harness.equals(view.cutProgress, 9)
		harness.equals(view.completed, 0)
		events.InputEnded:Fire(pointer)
		events:finishAnimation()
		harness.equals(view.completed, 1)
	end)

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

	harness.test("отчёт блокирует разрез даже после обновления ателье и сохраняет его прогресс", function()
		local view, events = fixture()
		local pointer = input("Touch")
		events.InputBegan:Fire(pointer, false)
		move(events, pointer, 40)
		view:endDrag(true)
		view.diagnosticsOpen = true
		view.inputBlocked = false -- Так приходит обычное обновление открытой боковой панели.
		local nextPointer = input("Touch", 40)
		events.InputBegan:Fire(nextPointer, false)
		harness.equals(view.drag, nil)
		harness.equals(view.cutProgress, 40)
		view.diagnosticsOpen = false
		events.InputBegan:Fire(nextPointer, false)
		move(events, nextPointer, 60)
		harness.equals(view.cutProgress, 60)
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
		for _, event in { "WindowFocusReleased", "MenuOpened", "TextBoxFocused" } do
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
		harness.equals(view.status.Text, "Return to the highlighted point — your cut progress is saved")
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
