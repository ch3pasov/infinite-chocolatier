--!strict
-- Игровой цикл иллюзии: диагональный рез -> сдвиг верхней области -> долька.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Geom = require(Shared.Geom)
local Recipe = require(Shared.Recipe)
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

local function makeSegment(
	parent: Instance,
	a: Vector2,
	b: Vector2,
	thickness: number,
	color: Color3,
	transparency: number?,
	zIndex: number?
): Frame
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
	return {
		points = points,
		geom = Geom.path(points),
	}
end

local function makeChocolateTile(parent: Instance, name: string, position: Vector2, width: number, height: number)
	local outer = Instance.new("Frame")
	outer.Name = name
	outer.Position = UDim2.fromOffset(position.X, position.Y)
	outer.Size = UDim2.fromOffset(width, height)
	outer.BackgroundColor3 = Theme.chocolateEdge
	outer.BorderSizePixel = 0
	outer.ZIndex = 2
	rounded(outer, math.max(5, math.floor(math.min(width, height) * 0.12)))
	outer.Parent = parent

	local inset = math.max(3, math.floor(math.min(width, height) * 0.08))
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Position = UDim2.fromOffset(inset, inset)
	face.Size = UDim2.fromOffset(width - inset * 2, height - inset * 2)
	face.BackgroundColor3 = Theme.chocolate
	face.BorderSizePixel = 0
	face.ZIndex = 3
	rounded(face, math.max(4, math.floor(math.min(width, height) * 0.09)))
	face.Parent = outer

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.chocolateEdge
	stroke.Transparency = 0.20
	stroke.Thickness = 1
	stroke.Parent = face

	return outer
end

function Game.new(gui: ScreenGui, remotes)
	local self = setmetatable({}, Game)
	self.gui = gui
	self.remotes = remotes
	self.recipe = Recipe.build(Config.Recipe)
	self.trick = Config.Trick
	self.movingLetter = self.trick.movingLetter
	self.active = "cut"
	self.cutProgress = 0
	self.drag = nil
	self.pieces = {}
	self.pendingSlides = {}

	self.root = Instance.new("Frame")
	self.root.Name = "Root"
	self.root.Size = UDim2.fromScale(1, 1)
	self.root.BackgroundColor3 = Theme.background
	self.root.BorderSizePixel = 0
	self.root.Parent = gui

	self.counter = Instance.new("TextLabel")
	self.counter.Name = "Counter"
	self.counter.Position = UDim2.fromOffset(24, 20)
	self.counter.Size = UDim2.fromOffset(240, 48)
	self.counter.BackgroundTransparency = 1
	self.counter.Font = Enum.Font.GothamBold
	self.counter.TextXAlignment = Enum.TextXAlignment.Left
	self.counter.TextColor3 = Theme.accent
	self.counter.TextSize = 28
	self.counter.Text = "ДОЛЬКИ  0"
	-- На экране фокуса важнее показать механику, чем экономический HUD.
	self.counter.Visible = false
	self.counter.Parent = self.root

	self.status = Instance.new("TextLabel")
	self.status.Name = "Status"
	self.status.AnchorPoint = Vector2.new(0.5, 1)
	self.status.Position = UDim2.fromScale(0.5, Config.Board.statusPositionY)
	self.status.Size = UDim2.fromOffset(960, 58)
	self.status.BackgroundTransparency = 1
	self.status.Font = Enum.Font.GothamMedium
	self.status.TextColor3 = Theme.accentSoft
	self.status.TextSize = 30
	self.status.Text = "Проведи по диагонали — рез 1 из 1"
	self.status.Parent = self.root

	self.board = Instance.new("Frame")
	self.board.Name = "ChocolateBoard"
	self.board.AnchorPoint = Vector2.new(0.5, 0.5)
	self.board.BackgroundColor3 = Theme.chocolateDark
	self.board.BackgroundTransparency = 1
	self.board.BorderSizePixel = 0
	self.board.ClipsDescendants = false
	self.board.Parent = self.root

	self.pieceLayer = Instance.new("Frame")
	self.pieceLayer.Name = "Pieces"
	self.pieceLayer.Size = UDim2.fromScale(1, 1)
	self.pieceLayer.BackgroundTransparency = 1
	self.pieceLayer.ClipsDescendants = false
	self.pieceLayer.ZIndex = 2
	self.pieceLayer.Parent = self.board

	-- Верхняя часть не является прямоугольным Roblox-фреймом. Она собирается
	-- из тонких горизонтальных полос, поэтому край действительно диагональный
	-- и может уехать целиком, не превращаясь в сетку квадратов.
	self.wedgeLayer = Instance.new("Frame")
	self.wedgeLayer.Name = "DiagonalMovingRegion"
	self.wedgeLayer.Size = UDim2.fromScale(1, 1)
	self.wedgeLayer.BackgroundTransparency = 1
	self.wedgeLayer.ClipsDescendants = false
	self.wedgeLayer.ZIndex = 5
	self.wedgeLayer.Parent = self.board

	self.seamLayer = Instance.new("Frame")
	self.seamLayer.Name = "Seam"
	self.seamLayer.Size = UDim2.fromScale(1, 1)
	self.seamLayer.BackgroundTransparency = 1
	self.seamLayer.ZIndex = 6
	self.seamLayer.Parent = self.board

	self.lineLayer = Instance.new("Frame")
	self.lineLayer.Name = "Progress"
	self.lineLayer.Size = UDim2.fromScale(1, 1)
	self.lineLayer.BackgroundTransparency = 1
	self.lineLayer.ZIndex = 8
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
	local baseWidth = self.trick.baseTileWidth
	local baseHeight = self.trick.baseTileHeight
	local widthLimit = math.min(self.trick.maxBoardWidth, math.max(self.trick.minBoardWidth, viewport.X - 120))
	local heightLimit = math.min(self.trick.maxBoardHeight, math.max(self.trick.minBoardHeight, viewport.Y - 150))
	local scale = math.min(
		widthLimit / (self.recipe.cols * baseWidth),
		heightLimit / (self.recipe.rows * baseHeight)
	)

	self.tileWidth = round(baseWidth * scale)
	self.tileHeight = round(baseHeight * scale)
	self.tileGap = math.max(3, round(math.min(self.tileWidth, self.tileHeight) * 0.045))
	self.boardWidth = self.tileWidth * self.recipe.cols
	self.boardHeight = self.tileHeight * self.recipe.rows
	self.board.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	self.board.Position = UDim2.fromScale(0.5, Config.Board.positionY)

	clear(self.pieceLayer)
	clear(self.wedgeLayer)
	clear(self.seamLayer)
	clear(self.lineLayer)
	clear(self.hintLayer)
	self.pieces = {}
	for _, letter in self.recipe.order do
		local piece = self.recipe.pieces[letter]
		local frame = Instance.new("Frame")
		frame.Name = "Piece" .. letter
		frame.Position = UDim2.fromOffset(piece.minC * self.tileWidth, piece.minR * self.tileHeight)
		frame.Size = UDim2.fromOffset(
			(piece.maxC - piece.minC + 1) * self.tileWidth,
			(piece.maxR - piece.minR + 1) * self.tileHeight
		)
		frame.BackgroundTransparency = 1
		frame.BorderSizePixel = 0
		frame.ZIndex = 2
		frame.Parent = self.pieceLayer

		local entry = {
			letter = letter,
			piece = piece,
			frame = frame,
			tiles = {},
			home = Vector2.new(piece.minC * self.tileWidth, piece.minR * self.tileHeight),
		}
		self.pieces[letter] = entry

		for _, cellInfo in piece.cells do
			local tileWidth = self.tileWidth - self.tileGap * 2
			local tileHeight = self.tileHeight - self.tileGap * 2
			local localPosition = Vector2.new(
				(cellInfo.c - piece.minC) * self.tileWidth + self.tileGap,
				(cellInfo.r - piece.minR) * self.tileHeight + self.tileGap
			)
			local tile = makeChocolateTile(
				frame,
				`Tile{cellInfo.r + 1}_{cellInfo.c + 1}`,
				localPosition,
				tileWidth,
				tileHeight
			)
			table.insert(entry.tiles, {
				frame = tile,
				center = Vector2.new(
					(cellInfo.c + 0.5) * self.tileWidth,
					(cellInfo.r + 0.5) * self.tileHeight
				),
			})
		end
	end

	self:resetRound()
end

function Game:screenToBoard(position: Vector3 | Vector2): Vector2
	-- ScreenGui игнорирует системный inset после скрытия стандартного HUD Roblox.
	local inset = self.gui.IgnoreGuiInset and Vector2.zero or GuiService:GetGuiInset()
	local screen = Vector2.new(position.X, position.Y) - inset
	return screen - self.board.AbsolutePosition
end

function Game:buildPaths()
	local paths = {}
	for _, cut in self.recipe.cuts do
		local points = {}
		for _, point in cut do
			table.insert(points, Vector2.new(point.x * self.tileWidth, point.y * self.tileHeight))
		end
		table.insert(paths, newPath(points))
	end
	return paths
end

function Game:drawDashed(path, parent: Instance, color: Color3)
	for _, segment in path.geom.segments do
		local direction = (segment.b - segment.a).Unit
		local distance = 0
		local dashLength = math.max(13, math.min(self.tileWidth, self.tileHeight) * 0.23)
		local gap = math.max(9, math.min(self.tileWidth, self.tileHeight) * 0.14)
		local thickness = math.max(4, math.min(self.tileWidth, self.tileHeight) * 0.055)
		while distance < segment.len do
			local startPoint = segment.a + direction * distance
			local endPoint = segment.a + direction * math.min(distance + dashLength, segment.len)
			makeSegment(parent, startPoint, endPoint, thickness, color, 0.04, 7)
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
			makeSegment(self.lineLayer, segment.a, endPoint, math.max(5, self.tileWidth * 0.07), Theme.cut, 0, 9)
		end
	end
end

function Game:drawSeam(path)
	clear(self.seamLayer)
	for _, segment in path.geom.segments do
		-- Тёмная подложка делает диагональ похожей на настоящий разлом, а не
		-- на интерфейсную линию поверх плитки.
		makeSegment(self.seamLayer, segment.a, segment.b, math.max(8, self.tileWidth * 0.11), Theme.background, 0.05, 6)
		makeSegment(self.seamLayer, segment.a, segment.b, math.max(2, self.tileWidth * 0.025), Theme.cut, 0, 7)
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
	local anchor = Geom.pointAt(path.geom, self.cutProgress)
	pip.Position = UDim2.fromOffset(anchor.X, anchor.Y)
	local pipSize = math.max(18, math.min(self.tileWidth, self.tileHeight) * 0.36)
	pip.Size = UDim2.fromOffset(pipSize, pipSize)
	pip.BackgroundColor3 = Theme.accent
	pip.BorderSizePixel = 0
	pip.ZIndex = 10
	pip.Parent = self.hintLayer
	rounded(pip, math.floor(pipSize / 2))
	self.startPip = pip
end

function Game:lineYAtX(x: number): number
	local diagonal = self.diagonal
	if not diagonal then
		return 0
	end
	local width = diagonal.b.X - diagonal.a.X
	if math.abs(width) < 0.001 then
		return diagonal.a.Y
	end
	local t = math.clamp((x - diagonal.a.X) / width, 0, 1)
	return diagonal.a.Y + (diagonal.b.Y - diagonal.a.Y) * t
end

function Game:xBoundaryAtY(y: number): number
	local diagonal = self.diagonal
	if not diagonal then
		return 0
	end
	local topY = math.min(diagonal.a.Y, diagonal.b.Y)
	local bottomY = math.max(diagonal.a.Y, diagonal.b.Y)
	if y <= topY then
		return self.boardWidth
	end
	if y >= bottomY then
		return 0
	end
	local denominator = diagonal.a.Y - diagonal.b.Y
	local t = (diagonal.a.Y - y) / denominator
	return math.clamp(diagonal.a.X + (diagonal.b.X - diagonal.a.X) * t, 0, self.boardWidth)
end

function Game:isAboveDiagonal(point: Vector2): boolean
	if point.X < 0 or point.X > self.boardWidth or point.Y < 0 or point.Y > self.boardHeight then
		return false
	end
	return point.Y <= self:lineYAtX(point.X)
end

function Game:isMovingRegion(point: Vector2): boolean
	return self:isAboveDiagonal(point - self.wedgeOffset)
end

function Game:buildMovingWedge(path)
	self.diagonal = {
		a = path.points[1],
		b = path.points[#path.points],
	}
	self.wedgeOffset = Vector2.zero
	clear(self.wedgeLayer)

	local group = Instance.new("Frame")
	group.Name = "Wedge"
	group.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	group.BackgroundTransparency = 1
	group.BorderSizePixel = 0
	group.ZIndex = 5
	group.Parent = self.wedgeLayer
	self.wedgeGroup = group

	local stripHeight = math.max(2, self.trick.wedgeStripHeight)
	local y = 0
	while y < self.boardHeight do
		local height = math.min(stripHeight, self.boardHeight - y)
		local boundary = self:xBoundaryAtY(y + height / 2)
		if boundary > 0 then
			local strip = Instance.new("Frame")
			strip.Name = "WedgeStrip"
			strip.Position = UDim2.fromOffset(0, y)
			strip.Size = UDim2.fromOffset(boundary, height + 0.5)
			strip.BackgroundColor3 = Theme.chocolate
			strip.BackgroundTransparency = 0
			strip.BorderSizePixel = 0
			strip.ZIndex = 5
			strip.Parent = group
		end
		y += height
	end

	-- Возвращаем рисунок долек только внутри диагональной области. Линии
	-- обрезаются математикой пересечения, а не маской прямоугольного блока.
	for column = 1, self.recipe.cols - 1 do
		local x = column * self.tileWidth
		local top = math.min(self:lineYAtX(x), self.boardHeight)
		if top > 0 then
			makeSegment(group, Vector2.new(x, 0), Vector2.new(x, top), 2, Theme.chocolateEdge, 0.28, 6)
		end
	end
	for row = 1, self.recipe.rows - 1 do
		local yLine = row * self.tileHeight
		local right = self:xBoundaryAtY(yLine)
		if right > 0 then
			makeSegment(group, Vector2.new(0, yLine), Vector2.new(right, yLine), 2, Theme.chocolateEdge, 0.30, 6)
		end
	end

	for _, entry in self.pieces do
		for _, tile in entry.tiles do
			-- Освобождаем место для полос только там, где исходная долька
			-- действительно находится по верхнюю сторону диагонального реза.
			tile.frame.Visible = not self:isAboveDiagonal(tile.center)
		end
	end
end

function Game:updateWedgePosition(offset: Vector2)
	self.wedgeOffset = offset
	if self.wedgeGroup then
		self.wedgeGroup.Position = UDim2.fromOffset(offset.X, offset.Y)
	end
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
				local anchor = Geom.pointAt(path.geom, self.cutProgress)
				local distance = (point - anchor).Magnitude
				local _, arc = Geom.project(path.geom, point)
				if distance <= Config.Cutting.startRadius and math.abs(arc - self.cutProgress) <= Config.Cutting.startRadius then
					self.drag = { kind = "cut", progress = self.cutProgress, last = point }
					if self.startPip then
						self.startPip.Visible = false
					end
				end
			end
		elseif self.active == "slide" then
			if self.pendingSlides[self.movingLetter] and self:isMovingRegion(point) then
				self.drag = { kind = "slide", anchor = point - self.wedgeOffset }
			end
		end
	end)

	self.changed = UserInputService.InputChanged:Connect(function(input, _processed)
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
		if self.drag then
			-- На слабом устройстве короткий жест может не дать отдельный
			-- InputChanged, поэтому проверяем финальную точку при отпускании.
			self:updateDrag(self:screenToBoard(input.Position))
		end
		self:endDrag()
	end)
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
			self.cutProgress = 0
			self:drawProgress(path, 0)
			if self.startPip then
				self.startPip.Position = UDim2.fromOffset(path.points[1].X, path.points[1].Y)
			end
			self.status.Text = "Срыв — начни диагональ заново"
			return
		end
		if arc <= drag.progress + Config.Cutting.maxJump and arc >= drag.progress - Config.Cutting.backtrack then
			drag.progress = math.max(drag.progress, arc)
			self.cutProgress = drag.progress
		end
		self:drawProgress(path, drag.progress)
		if drag.progress >= path.geom.length * Config.Cutting.completeAt then
			self:finishCut()
		end
	elseif drag.kind == "slide" then
		self:updateWedgePosition(point - drag.anchor)
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
			local path = self.paths[self.cutIndex]
			if path then
				local anchor = Geom.pointAt(path.geom, self.cutProgress)
				self.startPip.Position = UDim2.fromOffset(anchor.X, anchor.Y)
			end
			self.startPip.Visible = true
		end
	elseif drag.kind == "slide" then
		local target = self.targets[self.movingLetter]
		if target and (self.wedgeOffset - target).Magnitude <= Config.Sliding.snapRadius then
			self:updateWedgePosition(target)
			self.pendingSlides[self.movingLetter] = nil
			self:updateSlideHints()
		else
			self:updateWedgePosition(Vector2.zero)
		end
	end
end

function Game:finishCut()
	self.drag = nil
	local path = self.paths[self.cutIndex]
	self.cutProgress = 0
	if self.startPip then
		self.startPip:Destroy()
		self.startPip = nil
	end
	self:drawProgress(path, path.geom.length)
	self:drawSeam(path)
	self.cutIndex += 1
	if self.cutIndex <= #self.paths then
		self.status.Text = `Проведи по диагонали — рез {self.cutIndex} из {#self.paths}`
		task.delay(0.12, function()
			if self.active == "cut" then
				self:showCutHint()
			end
		end)
	else
		self:buildMovingWedge(path)
		self:beginSlide()
	end
end

function Game:beginSlide()
	self.active = "slide"
	self.status.Text = "Сдвинь верхнюю часть по диагональной стрелке"
	self.targets = {}
	self.pendingSlides = {}
	local slide = self.recipe.slides[self.movingLetter]
	if slide then
		local target = Vector2.new(
			slide.dx * self.tileWidth,
			slide.dy * self.tileHeight
		)
		self.targets[self.movingLetter] = target
		self.pendingSlides[self.movingLetter] = true
	end
	self:updateSlideHints()
end

function Game:updateSlideHints()
	clear(self.hintLayer)
	for letter in self.pendingSlides do
		local target = self.targets[letter]
		local start = Vector2.new(self.boardWidth * 0.25, self.boardHeight * 0.24) + self.wedgeOffset
		self:drawDashed(newPath({ start, start + target - self.wedgeOffset }), self.hintLayer, Theme.accentSoft)

		if self.wedgeGroup then
			local ghost = self.wedgeGroup:Clone()
			ghost.Name = "GhostWedge"
			ghost.Position = UDim2.fromOffset(target.X, target.Y)
			ghost.ZIndex = 1
			for _, child in ghost:GetDescendants() do
				if child:IsA("GuiObject") then
					child.BackgroundTransparency = math.max(child.BackgroundTransparency, 0.86)
					child.ZIndex = 1
				end
			end
			ghost.Parent = self.hintLayer
		end
	end
	if next(self.pendingSlides) == nil then
		self:finishRound()
	end
end

function Game:showExtraSlice()
	if self.extraSlice then
		self.extraSlice:Destroy()
	end
	local width = self.tileWidth * self.trick.extraSliceWidth
	local height = self.tileHeight * self.trick.extraSliceHeight
	local outer = Instance.new("Frame")
	outer.Name = "ExtraSlice"
	outer.Position = UDim2.fromOffset(self.boardWidth + self.tileWidth * 0.16, self.boardHeight * 0.68)
	outer.Size = UDim2.fromOffset(width, height)
	outer.BackgroundColor3 = Theme.chocolateEdge
	outer.BorderSizePixel = 0
	outer.ZIndex = 12
	rounded(outer, math.max(4, math.floor(width * 0.12)))
	outer.Parent = self.board

	local face = Instance.new("Frame")
	face.Position = UDim2.fromOffset(3, 3)
	face.Size = UDim2.fromOffset(math.max(4, width - 6), math.max(4, height - 6))
	face.BackgroundColor3 = Theme.chocolate
	face.BorderSizePixel = 0
	face.ZIndex = 13
	rounded(face, math.max(4, math.floor(width * 0.10)))
	face.Parent = outer

	local bite = makeSegment(outer, Vector2.new(width * 0.55, 0), Vector2.new(width, height * 0.45), math.max(2, width * 0.07), Theme.background, 0, 14)
	bite.Name = "DiagonalBite"
	self.extraSlice = outer
end

function Game:finishRound()
	if self.active == "done" then
		return
	end
	self.active = "done"
	self.status.Text = "Лишняя долька появилась — фокус сработал"
	self:showExtraSlice()
	self.remotes.roundComplete:FireServer()
	task.delay(1.15, function()
		self:resetRound()
	end)
end

function Game:resetRound()
	self.active = "cut"
	self.cutIndex = 1
	self.cutProgress = 0
	self.drag = nil
	self.targets = {}
	self.pendingSlides = {}
	self.wedgeOffset = Vector2.zero
	self.diagonal = nil
	self.wedgeGroup = nil
	if self.extraSlice then
		self.extraSlice:Destroy()
		self.extraSlice = nil
	end
	clear(self.wedgeLayer)
	clear(self.seamLayer)
	for _, entry in self.pieces do
		for _, tile in entry.tiles do
			tile.frame.Visible = true
		end
		entry.frame.Position = UDim2.fromOffset(entry.home.X, entry.home.Y)
	end
	self.paths = self:buildPaths()
	self.status.Text = `Проведи по диагонали — рез 1 из {#self.paths}`
	self:showCutHint()
end

return Game
