--!strict
-- Локальный игровой цикл: резка -> сдвиг -> награда.

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Geom = require(Shared.Geom)
local Recipe = require(Shared.Recipe)
local Remotes = require(Shared.Remotes)
local Theme = require(script.Parent.Theme)

local Game = {}
Game.__index = Game

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		child:Destroy()
	end
end

local function rounded(frame: Frame, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = frame
end

local function makeSegment(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, transparency: number?, zIndex: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	frame.Size = UDim2.fromOffset(math.max((b - a).Magnitude, thickness), thickness)
	frame.Rotation = math.deg(math.atan2(b.Y - a.Y, b.X - a.X))
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex or 5
	rounded(frame, math.floor(thickness / 2))
	frame.Parent = parent
	return frame
end

local function newPath(points: { Vector2 })
	local path = Geom.path(points)
	return {
		points = points,
		geom = path,
		progressFrames = {},
	}
end

function Game.new(gui: ScreenGui, remotes)
	local self = setmetatable({}, Game)
	self.gui = gui
	self.remotes = remotes
	self.recipe = Recipe.build(Config.Recipe)
	self.active = "cut"
	self.cutIndex = 1
	self.drag = nil
	self.pieces = {}
	self.pendingSlides = {}

	self.root = Instance.new("Frame")
	self.root.Name = "Root"
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.BackgroundColor3 = Theme.background
	self.root.BorderSizePixel = 0
	self.root.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.fromScale(0.5, 0.035)
	title.Size = UDim2.fromOffset(600, 42)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "INFINITE CHOCOLATE"
	title.TextColor3 = Theme.text
	title.TextSize = 26
	title.Parent = self.root

	self.counter = Instance.new("TextLabel")
	self.counter.Name = "Counter"
	self.counter.Position = UDim2.fromOffset(28, 24)
	self.counter.Size = UDim2.fromOffset(220, 64)
	self.counter.BackgroundTransparency = 1
	self.counter.Font = Enum.Font.GothamBold
	self.counter.TextXAlignment = Enum.TextXAlignment.Left
	self.counter.TextColor3 = Theme.accent
	self.counter.TextSize = 34
	self.counter.Text = "ДОЛЬКИ  0"
	self.counter.Parent = self.root

	self.status = Instance.new("TextLabel")
	self.status.Name = "Status"
	self.status.AnchorPoint = Vector2.new(0.5, 1)
	self.status.Position = UDim2.fromScale(0.5, 0.965)
	self.status.Size = UDim2.fromOffset(760, 44)
	self.status.BackgroundTransparency = 1
	self.status.Font = Enum.Font.GothamMedium
	self.status.TextColor3 = Theme.accentSoft
	self.status.TextSize = 20
	self.status.Text = "Обведи пунктир — рез 1 из 3"
	self.status.Parent = self.root

	self.board = Instance.new("Frame")
	self.board.Name = "ChocolateBoard"
	self.board.AnchorPoint = Vector2.new(0.5, 0.5)
	self.board.BackgroundColor3 = Theme.chocolateDark
	self.board.BorderSizePixel = 0
	self.board.ClipsDescendants = false
	self.board.Parent = self.root
	rounded(self.board, 14)

	self.pieceLayer = Instance.new("Frame")
	self.pieceLayer.Name = "Pieces"
	self.pieceLayer.Size = UDim2.fromScale(1, 1)
	self.pieceLayer.BackgroundTransparency = 1
	self.pieceLayer.ClipsDescendants = false
	self.pieceLayer.ZIndex = 2
	self.pieceLayer.Parent = self.board

	self.lineLayer = Instance.new("Frame")
	self.lineLayer.Name = "Lines"
	self.lineLayer.Size = UDim2.fromScale(1, 1)
	self.lineLayer.BackgroundTransparency = 1
	self.lineLayer.ZIndex = 6
	self.lineLayer.Parent = self.board

	self.hintLayer = Instance.new("Frame")
	self.hintLayer.Name = "Hints"
	self.hintLayer.Size = UDim2.fromScale(1, 1)
	self.hintLayer.BackgroundTransparency = 1
	self.hintLayer.ZIndex = 7
	self.hintLayer.Parent = self.board

	self:layout()
	self:bindInput()
	return self
end

function Game:layout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local size = math.min(Config.Board.maxSize, math.max(Config.Board.minSize, viewport.X - 90))
	local cell = round(size / self.recipe.cols)
	self.cell = cell
	self.board.Size = UDim2.fromOffset(cell * self.recipe.cols, cell * self.recipe.rows)
	self.board.Position = UDim2.fromScale(0.5, 0.53)

	clear(self.pieceLayer)
	self.pieces = {}
	for _, letter in self.recipe.order do
		local piece = self.recipe.pieces[letter]
		local frame = Instance.new("Frame")
		frame.Name = "Piece" .. letter
		frame.Position = UDim2.fromOffset(piece.minC * cell, piece.minR * cell)
		frame.Size = UDim2.fromOffset((piece.maxC - piece.minC + 1) * cell, (piece.maxR - piece.minR + 1) * cell)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = 2
		frame.Parent = self.pieceLayer

		local entry = {
			letter = letter,
			piece = piece,
			frame = frame,
			offset = Vector2.zero,
			locked = false,
			home = Vector2.new(piece.minC * cell, piece.minR * cell),
		}
		self.pieces[letter] = entry

		for _, cellInfo in piece.cells do
			local tile = Instance.new("Frame")
			tile.Position = UDim2.fromOffset((cellInfo.c - piece.minC) * cell + 3, (cellInfo.r - piece.minR) * cell + 3)
			tile.Size = UDim2.fromOffset(cell - 6, cell - 6)
			tile.BackgroundColor3 = Theme.chocolate
			tile.BorderSizePixel = 0
			tile.ZIndex = 2
			tile.Parent = frame
			rounded(tile, 9)
			local stroke = Instance.new("UIStroke")
			stroke.Color = Theme.chocolateEdge
			stroke.Transparency = 0.38
			stroke.Thickness = 1
			stroke.Parent = tile
		end
	end

	self:resetRound()
end

function Game:screenToBoard(position: Vector3 | Vector2): Vector2
	local inset = GuiService:GetGuiInset()
	local screen = Vector2.new(position.X, position.Y) - inset
	return screen - self.board.AbsolutePosition
end

function Game:boardToScreen(point: Vector2): Vector2
	return self.board.AbsolutePosition + point
end

function Game:buildPaths()
	local paths = {}
	for _, cut in self.recipe.cuts do
		local points = {}
		for _, point in cut do
			table.insert(points, Vector2.new(point.x * self.cell, point.y * self.cell))
		end
		table.insert(paths, newPath(points))
	end
	return paths
end

function Game:drawDashed(path, parent: Instance, color: Color3)
	local dashLength = 12
	local gap = 9
	for _, segment in path.geom.segments do
		local direction = (segment.b - segment.a).Unit
		local distance = 0
		while distance < segment.len do
			local startPoint = segment.a + direction * distance
			local endPoint = segment.a + direction * math.min(distance + dashLength, segment.len)
			makeSegment(parent, startPoint, endPoint, 4, color, 0.05, 7)
			distance += dashLength + gap
		end
	end
end

function Game:drawProgress(path, progress: number)
	clear(self.lineLayer)
	for _, segment in path.geom.segments do
		local covered = math.clamp(progress - segment.start, 0, segment.len)
		if covered > 0 then
			local endPoint = segment.a + (segment.b - segment.a) * (covered / segment.len)
			makeSegment(self.lineLayer, segment.a, endPoint, 6, Theme.cut, 0, 8)
		end
	end
end

function Game:showCutHint()
	clear(self.hintLayer)
	clear(self.lineLayer)
	local path = self.paths[self.cutIndex]
	if not path then
		return
	end
	self:drawDashed(path, self.hintLayer, Theme.accentSoft)
	local pip = Instance.new("Frame")
	pip.Name = "Start"
	pip.AnchorPoint = Vector2.new(0.5, 0.5)
	pip.Position = UDim2.fromOffset(path.points[1].X, path.points[1].Y)
	pip.Size = UDim2.fromOffset(18, 18)
	pip.BackgroundColor3 = Theme.accent
	pip.BorderSizePixel = 0
	pip.ZIndex = 9
	pip.Parent = self.hintLayer
	rounded(pip, 9)
	self.startPip = pip
end

function Game:bindInput()
	self.began = UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local point = self:screenToBoard(input.Position)
		if self.active == "cut" then
			local path = self.paths[self.cutIndex]
			if path then
				local distance = (point - path.points[1]).Magnitude
				if distance <= Config.Cutting.startRadius then
					self.drag = { kind = "cut", progress = 0, last = point }
					if self.startPip then
						self.startPip.Visible = false
					end
				end
			end
		elseif self.active == "slide" then
			local letter = self:pieceAt(point)
			if letter and self.pendingSlides[letter] then
				local entry = self.pieces[letter]
				self.drag = { kind = "slide", letter = letter, anchor = point - entry.offset }
				entry.frame.ZIndex = 10
			end
		end
	end)

	self.changed = UserInputService.InputChanged:Connect(function(input)
		if not self.drag then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		self:updateDrag(self:screenToBoard(input.Position))
	end)

	self.ended = UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end
		self:endDrag()
	end)
end

function Game:pieceAt(point: Vector2): string?
	local screen = self:boardToScreen(point)
	for letter, entry in self.pieces do
		if self.pendingSlides[letter] and not entry.locked then
			local minPoint = entry.frame.AbsolutePosition
			local maxPoint = minPoint + entry.frame.AbsoluteSize
			if screen.X >= minPoint.X and screen.X <= maxPoint.X and screen.Y >= minPoint.Y and screen.Y <= maxPoint.Y then
				return letter
			end
		end
	end
	return nil
end

function Game:updateDrag(point: Vector2)
	local drag = self.drag
	if not drag then
		return
	end

	if drag.kind == "cut" then
		local path = self.paths[self.cutIndex]
		local distance, arc = Geom.project(path.geom, point)
		if distance > Config.Cutting.slipTolerance then
			drag.progress = 0
			self:drawProgress(path, 0)
			if self.status then
				self.status.Text = "Срыв — начни линию заново"
			end
			return
		end
		if arc <= drag.progress + Config.Cutting.maxJump and arc >= drag.progress - Config.Cutting.backtrack then
			drag.progress = math.max(drag.progress, arc)
		end
		self:drawProgress(path, drag.progress)
		if drag.progress >= path.geom.length * Config.Cutting.completeAt then
			self:finishCut()
		end
	elseif drag.kind == "slide" then
		local entry = self.pieces[drag.letter]
		entry.offset = point - drag.anchor
		entry.frame.Position = UDim2.fromOffset(entry.home.X + entry.offset.X, entry.home.Y + entry.offset.Y)
	end
end

function Game:endDrag()
	local drag = self.drag
	if not drag then
		return
	end
	self.drag = nil

	if drag.kind == "cut" then
		if self.active == "cut" and self.startPip then
			self.startPip.Visible = true
		end
	elseif drag.kind == "slide" then
		local entry = self.pieces[drag.letter]
		entry.frame.ZIndex = 2
		local target = self.targets[drag.letter]
		if target and (entry.offset - target).Magnitude <= Config.Sliding.snapRadius then
			entry.offset = target
			entry.locked = true
			entry.frame.Position = UDim2.fromOffset(entry.home.X + target.X, entry.home.Y + target.Y)
			self.pendingSlides[drag.letter] = nil
			self:updateSlideHints()
		else
			entry.offset = Vector2.zero
			entry.frame.Position = UDim2.fromOffset(entry.home.X, entry.home.Y)
		end
	end
end

function Game:finishCut()
	self.drag = nil
	local path = self.paths[self.cutIndex]
	self:drawProgress(path, path.geom.length)
	if self.startPip then
		self.startPip:Destroy()
		self.startPip = nil
	end
	self.cutIndex += 1
	if self.cutIndex <= #self.paths then
		self.status.Text = `Обведи пунктир — рез {self.cutIndex} из {#self.paths}`
		task.delay(0.12, function()
			if self.active == "cut" then
				self:showCutHint()
			end
		end)
	else
		self:beginSlide()
	end
end

function Game:beginSlide()
	self.active = "slide"
	self.status.Text = "Растащи куски по подсказкам"
	self.targets = {}
	self.pendingSlides = {}
	for letter, slide in self.recipe.slides do
		local target = Vector2.new(slide.dx * self.cell, slide.dy * self.cell)
		self.targets[letter] = target
		self.pendingSlides[letter] = true
		local entry = self.pieces[letter]
		entry.locked = false
		local separation = letter == "B" and Vector2.new(-Config.Sliding.separation, Config.Sliding.separation) or Vector2.new(Config.Sliding.separation, 0)
		entry.offset = separation
		entry.frame.Position = UDim2.fromOffset(entry.home.X + separation.X, entry.home.Y + separation.Y)
	end
	self:updateSlideHints()
end

function Game:updateSlideHints()
	clear(self.hintLayer)
	for letter in self.pendingSlides do
		local entry = self.pieces[letter]
		local target = self.targets[letter]
		local start = Vector2.new((entry.piece.minC + entry.piece.maxC + 1) * self.cell / 2, (entry.piece.minR + entry.piece.maxR + 1) * self.cell / 2)
		self:drawDashed(newPath({ start, start + target }), self.hintLayer, Theme.accentSoft)
		local ghost = Instance.new("Frame")
		ghost.Name = "Ghost" .. letter
		ghost.Position = UDim2.fromOffset(entry.home.X + target.X, entry.home.Y + target.Y)
		ghost.Size = entry.frame.Size
		ghost.BackgroundColor3 = Theme.ghost
		ghost.BackgroundTransparency = 0.88
		ghost.BorderSizePixel = 0
		ghost.ZIndex = 1
		ghost.Parent = self.hintLayer
		rounded(ghost, 8)
	end
	if next(self.pendingSlides) == nil then
		self:finishRound()
	end
end

function Game:finishRound()
	if self.active == "done" then
		return
	end
	self.active = "done"
	self.status.Text = "Лишняя долька — твоя"
	self.remotes.roundComplete:FireServer()
	task.delay(0.5, function()
		self:resetRound()
	end)
end

function Game:resetRound()
	self.active = "cut"
	self.cutIndex = 1
	self.drag = nil
	self.targets = {}
	self.pendingSlides = {}
	for _, entry in self.pieces do
		entry.offset = Vector2.zero
		entry.locked = false
		entry.frame.Position = UDim2.fromOffset(entry.home.X, entry.home.Y)
		entry.frame.ZIndex = 2
	end
	self.paths = self:buildPaths()
	self.status.Text = `Обведи пунктир — рез 1 из {#self.paths}`
	self:showCutHint()
end

return Game
