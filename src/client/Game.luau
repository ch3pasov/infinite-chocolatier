--!strict
-- Игровой цикл иллюзии: один диагональный рез -> перенос верхнего полигона.

local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Geom = require(Shared.Geom)
local Recipe = require(Shared.Recipe)
local Theme = require(script.Parent.Theme)

local Game = {}
Game.__index = Game

type CutPath = {
	points: { Vector2 },
	geom: Geom.Path,
}

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function clear(parent: Instance)
	for _, child in parent:GetChildren() do
		child:Destroy()
	end
end

local function rounded(guiObject: GuiObject, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = guiObject
end

local function makeFrame(
	parent: Instance,
	name: string,
	position: Vector2,
	size: Vector2,
	color: Color3,
	zIndex: number,
	radius: number?
): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Position = UDim2.fromOffset(position.X, position.Y)
	frame.Size = UDim2.fromOffset(math.max(size.X, 0), math.max(size.Y, 0))
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = zIndex
	if radius and radius > 0 then
		rounded(frame, radius)
	end
	frame.Parent = parent
	return frame
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
	frame.ZIndex = zIndex or 10
	rounded(frame, math.floor(thickness / 2))
	frame.Parent = parent
	return frame
end

local function newPath(points: { Vector2 }): CutPath
	return {
		points = points,
		geom = Geom.path(points),
	}
end

local function roundedVerticalBounds(
	position: Vector2,
	size: Vector2,
	radius: number,
	x: number
): (number, number)
	if radius <= 0 then
		return position.Y, position.Y + size.Y
	end

	local localX = math.clamp(x - position.X, 0, size.X)
	local edgeDistance = math.min(localX, size.X - localX)
	if edgeDistance >= radius then
		return position.Y, position.Y + size.Y
	end

	local circleX = radius - edgeDistance
	local inset = radius - math.sqrt(math.max(0, radius * radius - circleX * circleX))
	return position.Y + inset, position.Y + size.Y - inset
end

local function rectCornerCount(line: Geom.Line, position: Vector2, size: Vector2): number
	local count = 0
	for _, point in {
		position,
		position + Vector2.new(size.X, 0),
		position + size,
		position + Vector2.new(0, size.Y),
	} do
		if Geom.isUpper(line, point, 1e-6) then
			count += 1
		end
	end
	return count
end

local function renderClippedRoundedRect(
	parent: Instance,
	line: Geom.Line,
	keepUpper: boolean,
	name: string,
	position: Vector2,
	size: Vector2,
	radius: number,
	color: Color3,
	zIndex: number,
	columnWidth: number
)
	local upperCorners = rectCornerCount(line, position, size)
	local fullyInside = if keepUpper then upperCorners == 4 else upperCorners == 0
	local fullyOutside = if keepUpper then upperCorners == 0 else upperCorners == 4
	if fullyOutside then
		return
	end
	if fullyInside then
		makeFrame(parent, name, position, size, color, zIndex, radius)
		return
	end

	-- Roblox UI не имеет надёжной произвольной маски. Мы растрируем только те
	-- шоколадные примитивы, которые реально пересекает рез: аналитическая
	-- граница вычисляется для каждой узкой колонки. Это сохраняет рельеф и
	-- рамки, не создаёт общего прямоугольного wedge и не требует EditableImage.
	local x = position.X
	local right = position.X + size.X
	while x < right - 1e-6 do
		local width = math.min(columnWidth, right - x)
		local sampleX = x + width * 0.5
		local top, bottom = roundedVerticalBounds(position, size, radius, sampleX)
		local boundary = Geom.lineYAtX(line, sampleX)
		if keepUpper then
			bottom = math.min(bottom, boundary)
		else
			top = math.max(top, boundary)
		end
		if bottom - top > 0.05 then
			makeFrame(
				parent,
				name .. "Clip",
				Vector2.new(x, top),
				Vector2.new(width + 0.08, bottom - top + 0.08),
				color,
				zIndex
			)
		end
		x += width
	end
end

function Game.new(gui: ScreenGui, remotes)
	local self = setmetatable({}, Game)
	self.gui = gui
	self.remotes = remotes
	self.recipe = Recipe.build(Config.Recipe)
	self.trick = Config.Trick
	self.active = "cut"
	self.cutProgress = 0
	self.drag = nil
	self.wedgeOffset = Vector2.zero

	self.root = makeFrame(gui, "Root", Vector2.zero, Vector2.zero, Theme.background, 1)
	self.root.Size = UDim2.fromScale(1, 1)

	self.counter = Instance.new("TextLabel")
	self.counter.Name = "Counter"
	-- Левый верхний угол занят системными кнопками Roblox даже при скрытом
	-- Topbar. Центр оставляет счётчик читаемым в Studio и на узком экране.
	self.counter.AnchorPoint = Vector2.new(0.5, 0)
	self.counter.Position = UDim2.new(0.5, 0, 0, 12)
	self.counter.Size = UDim2.fromOffset(260, 48)
	self.counter.BackgroundTransparency = 1
	self.counter.Font = Enum.Font.GothamBold
	self.counter.TextXAlignment = Enum.TextXAlignment.Center
	self.counter.TextColor3 = Theme.accent
	self.counter.TextSize = 25
	self.counter.Text = "ДОЛЬКИ  0"
	self.counter.Parent = self.root

	self.status = Instance.new("TextLabel")
	self.status.Name = "Status"
	self.status.AnchorPoint = Vector2.new(0.5, 1)
	self.status.Position = UDim2.fromScale(0.5, Config.Board.statusPositionY)
	self.status.Size = UDim2.fromScale(0.92, 0.08)
	self.status.BackgroundTransparency = 1
	self.status.Font = Enum.Font.GothamMedium
	self.status.TextColor3 = Theme.accentSoft
	self.status.TextScaled = true
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 17
	textConstraint.MaxTextSize = 28
	textConstraint.Parent = self.status
	self.status.Parent = self.root

	self.board = makeFrame(self.root, "ChocolateBoard", Vector2.zero, Vector2.zero, Theme.background, 2)
	self.board.AnchorPoint = Vector2.new(0.5, 0.5)
	self.board.BackgroundTransparency = 1
	self.board.ClipsDescendants = false

	self.lowerLayer = makeFrame(self.board, "LowerPolygon", Vector2.zero, Vector2.zero, Theme.background, 2)
	self.lowerLayer.BackgroundTransparency = 1
	self.lowerLayer.ClipsDescendants = false

	self.upperGroup = makeFrame(self.board, "UpperPolygon", Vector2.zero, Vector2.zero, Theme.background, 5)
	self.upperGroup.BackgroundTransparency = 1
	self.upperGroup.ClipsDescendants = false

	self.seamLayer = makeFrame(self.board, "PhysicalSeam", Vector2.zero, Vector2.zero, Theme.background, 8)
	self.seamLayer.BackgroundTransparency = 1

	self.hintLayer = makeFrame(self.board, "Hints", Vector2.zero, Vector2.zero, Theme.background, 10)
	self.hintLayer.BackgroundTransparency = 1
	self.hintLayer.ClipsDescendants = false

	self.progressLayer = makeFrame(self.board, "CutProgress", Vector2.zero, Vector2.zero, Theme.background, 12)
	self.progressLayer.BackgroundTransparency = 1

	self:layout()
	self:bindInput()
	return self
end

function Game:layout()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local availableWidth = math.max(220, viewport.X - 110)
	local availableHeight = math.max(300, viewport.Y - 170)
	local widthLimit = math.min(self.trick.maxBoardWidth, math.max(self.trick.minBoardWidth, availableWidth))
	local heightLimit = math.min(self.trick.maxBoardHeight, math.max(self.trick.minBoardHeight, availableHeight))
	local scale = math.min(
		widthLimit / (self.recipe.cols * self.trick.baseTileWidth),
		heightLimit / (self.recipe.rows * self.trick.baseTileHeight)
	)

	self.tileWidth = round(self.trick.baseTileWidth * scale)
	self.tileHeight = round(self.trick.baseTileHeight * scale)
	self.boardWidth = self.tileWidth * self.recipe.cols
	self.boardHeight = self.tileHeight * self.recipe.rows
	self.board.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	self.board.Position = UDim2.fromScale(0.5, Config.Board.positionY)
	for _, layer in { self.lowerLayer, self.upperGroup, self.seamLayer, self.hintLayer, self.progressLayer } do
		layer.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	end

	self.paths = self:buildPaths()
	local path = self.paths[1]
	self.diagonal = { a = path.points[1], b = path.points[#path.points] }
	self:renderChocolate()
	self:resetRound()
end

function Game:buildPaths(): { CutPath }
	local paths: { CutPath } = {}
	for _, cut in self.recipe.cuts do
		local points: { Vector2 } = {}
		for _, point in cut do
			table.insert(points, Vector2.new(point.x * self.tileWidth, point.y * self.tileHeight))
		end
		table.insert(paths, newPath(points))
	end
	return paths
end

function Game:renderPrimitive(
	name: string,
	position: Vector2,
	size: Vector2,
	radius: number,
	color: Color3,
	zIndex: number
)
	local columnWidth = math.max(1, self.trick.clipColumnWidth)
	renderClippedRoundedRect(
		self.lowerLayer,
		self.diagonal,
		false,
		name,
		position,
		size,
		radius,
		color,
		zIndex,
		columnWidth
	)
	renderClippedRoundedRect(
		self.upperGroup,
		self.diagonal,
		true,
		name,
		position,
		size,
		radius,
		color,
		zIndex,
		columnWidth
	)
end

function Game:renderChocolate()
	clear(self.lowerLayer)
	clear(self.upperGroup)
	local tileMin = math.min(self.tileWidth, self.tileHeight)
	local gap = math.max(3, round(tileMin * self.trick.tileGapRatio))
	local bevel = math.max(3, round(tileMin * self.trick.bevelRatio))
	local corner = math.max(6, round(tileMin * self.trick.cornerRatio))

	self:renderPrimitive(
		"BarBody",
		Vector2.zero,
		Vector2.new(self.boardWidth, self.boardHeight),
		corner + gap,
		Theme.chocolateDark,
		2
	)

	for row = 0, self.recipe.rows - 1 do
		for column = 0, self.recipe.cols - 1 do
			local tilePosition = Vector2.new(column * self.tileWidth + gap, row * self.tileHeight + gap)
			local tileSize = Vector2.new(self.tileWidth - gap * 2, self.tileHeight - gap * 2)
			self:renderPrimitive(
				`Tile{row + 1}_{column + 1}Bevel`,
				tilePosition,
				tileSize,
				corner,
				Theme.chocolateEdge,
				3
			)
			self:renderPrimitive(
				`Tile{row + 1}_{column + 1}Face`,
				tilePosition + Vector2.new(bevel, bevel),
				tileSize - Vector2.new(bevel * 2, bevel * 2),
				math.max(4, corner - bevel),
				Theme.chocolate,
				4
			)

			local panelInsetX = bevel * 2.0
			local panelInsetY = bevel * 2.5
			self:renderPrimitive(
				`Tile{row + 1}_{column + 1}Relief`,
				tilePosition + Vector2.new(panelInsetX, panelInsetY),
				tileSize - Vector2.new(panelInsetX * 2, panelInsetY * 2),
				math.max(3, corner - bevel),
				Theme.chocolateRaised,
				5
			)
		end
	end
end

function Game:screenToBoard(position: Vector3 | Vector2): Vector2
	local inset = self.gui.IgnoreGuiInset and Vector2.zero or GuiService:GetGuiInset()
	local screen = Vector2.new(position.X, position.Y) - inset
	return screen - self.board.AbsolutePosition
end

function Game:isMovingRegion(point: Vector2): boolean
	local source = point - self.wedgeOffset
	return source.X >= 0
		and source.X <= self.boardWidth
		and source.Y >= 0
		and source.Y <= self.boardHeight
		and Geom.isUpper(self.diagonal, source, 0.5)
end

function Game:updateUpperPosition(offset: Vector2)
	self.wedgeOffset = offset
	self.upperGroup.Position = UDim2.fromOffset(offset.X, offset.Y)
end

function Game:drawDashed(path: CutPath, parent: Instance, color: Color3)
	for _, segment in path.geom.segments do
		local direction = (segment.b - segment.a).Unit
		local distance = 0
		local unit = math.min(self.tileWidth, self.tileHeight)
		local dashLength = math.max(12, unit * 0.22)
		local gap = math.max(8, unit * 0.13)
		local thickness = math.max(3, unit * 0.05)
		while distance < segment.len do
			local startPoint = segment.a + direction * distance
			local endPoint = segment.a + direction * math.min(distance + dashLength, segment.len)
			makeSegment(parent, startPoint, endPoint, thickness, color, 0.04, 11)
			distance += dashLength + gap
		end
	end
end

function Game:drawProgress(path: CutPath, progress: number)
	clear(self.progressLayer)
	for _, segment in path.geom.segments do
		local covered = math.clamp(progress - segment.start, 0, segment.len)
		if covered > 0 then
			local endPoint = segment.a + (segment.b - segment.a) * (covered / segment.len)
			makeSegment(self.progressLayer, segment.a, endPoint, math.max(4, self.tileWidth * 0.065), Theme.cut, 0, 12)
		end
	end
end

function Game:drawSeam(path: CutPath)
	clear(self.seamLayer)
	for _, segment in path.geom.segments do
		-- Этот шов совпадает с математической границей двух слоёв. Он проявляет
		-- реальный разрез и остаётся на месте, когда верх скользит вдоль него.
		makeSegment(self.seamLayer, segment.a, segment.b, math.max(3, self.tileWidth * 0.045), Theme.chocolateShadow, 0.02, 8)
		makeSegment(self.seamLayer, segment.a, segment.b, 1, Theme.chocolateEdge, 0.12, 9)
	end
end

function Game:showCutHint()
	clear(self.hintLayer)
	clear(self.progressLayer)
	local path = self.paths[self.cutIndex]
	if not path then
		return
	end
	self:drawDashed(path, self.hintLayer, Theme.accentSoft)
	local anchor = Geom.pointAt(path.geom, self.cutProgress)
	local pipSize = math.max(18, math.min(self.tileWidth, self.tileHeight) * 0.32)
	self.startPip = makeFrame(
		self.hintLayer,
		"Start",
		anchor - Vector2.new(pipSize, pipSize) * 0.5,
		Vector2.new(pipSize, pipSize),
		Theme.accent,
		13,
		math.floor(pipSize / 2)
	)
end

function Game:showSlideHint()
	clear(self.hintLayer)
	local start = Vector2.new(self.boardWidth * 0.42, self.boardHeight * 0.18)
	local target = self.slideTarget
	local finish = start + target
	self:drawDashed(newPath({ start, finish }), self.hintLayer, Theme.accentSoft)
	local direction = target.Unit
	local normal = Vector2.new(-direction.Y, direction.X)
	local arrowSize = math.max(13, self.tileWidth * 0.22)
	makeSegment(self.hintLayer, finish, finish - direction * arrowSize + normal * arrowSize * 0.62, 4, Theme.accent, 0, 12)
	makeSegment(self.hintLayer, finish, finish - direction * arrowSize - normal * arrowSize * 0.62, 4, Theme.accent, 0, 12)
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
				local _, arc = Geom.project(path.geom, point)
				if (point - anchor).Magnitude <= Config.Cutting.startRadius
					and math.abs(arc - self.cutProgress) <= Config.Cutting.startRadius
				then
					self.drag = { kind = "cut", progress = self.cutProgress }
					if self.startPip then
						self.startPip.Visible = false
					end
				end
			end
		elseif self.active == "slide" and self:isMovingRegion(point) then
			self.drag = { kind = "slide", anchor = point - self.wedgeOffset }
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
		if self.drag then
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
		self:updateUpperPosition(point - drag.anchor)
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
			local anchor = Geom.pointAt(path.geom, self.cutProgress)
			self.startPip.Position = UDim2.fromOffset(anchor.X - self.startPip.AbsoluteSize.X / 2, anchor.Y - self.startPip.AbsoluteSize.Y / 2)
			self.startPip.Visible = true
		end
	elseif drag.kind == "slide" then
		if (self.wedgeOffset - self.slideTarget).Magnitude <= Config.Sliding.snapRadius then
			self:updateUpperPosition(self.slideTarget)
			self:finishRound()
		else
			self:updateUpperPosition(Vector2.zero)
		end
	end
end

function Game:finishCut()
	self.drag = nil
	local path = self.paths[self.cutIndex]
	if self.startPip then
		self.startPip:Destroy()
		self.startPip = nil
	end
	clear(self.hintLayer)
	self:drawProgress(path, path.geom.length)
	self:drawSeam(path)
	self.active = "slide"

	local slide = self.recipe.slides[self.trick.movingLetter]
	self.slideTarget = Vector2.new(slide.dx * self.tileWidth, slide.dy * self.tileHeight)
	self.status.Text = "Схвати верхнюю область в любом месте и сдвинь по стрелке"
	task.delay(0.12, function()
		if self.active == "slide" then
			clear(self.progressLayer)
			self:showSlideHint()
		end
	end)
end

function Game:showRewardMarker()
	if self.rewardMarker then
		self.rewardMarker:Destroy()
	end
	local reward = self.trick.rewardCell
	local gap = math.max(3, round(math.min(self.tileWidth, self.tileHeight) * self.trick.tileGapRatio))
	local marker = makeFrame(
		self.upperGroup,
		"RedistributedSliceMarker",
		Vector2.new((reward.column - 1) * self.tileWidth + gap, (reward.row - 1) * self.tileHeight + gap),
		Vector2.new(self.tileWidth - gap * 2, self.tileHeight - gap * 2),
		Theme.accent,
		20,
		math.max(6, round(math.min(self.tileWidth, self.tileHeight) * self.trick.cornerRatio))
	)
	marker.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.accent
	stroke.Thickness = 4
	stroke.Transparency = 0.05
	stroke.Parent = marker
	self.rewardMarker = marker
end

function Game:finishRound()
	if self.active == "done" then
		return
	end
	self.active = "done"
	clear(self.hintLayer)
	clear(self.seamLayer)
	self:showRewardMarker()
	self.status.Text = "Готово: перераспределение площади дало +1 дольку"
	-- В RemoteEvent нет количества: клиент сообщает только завершение жеста.
	self.remotes.roundComplete:FireServer()
	task.delay(self.trick.resetDelay, function()
		self:resetRound()
	end)
end

function Game:resetRound()
	self.active = "cut"
	self.cutIndex = 1
	self.cutProgress = 0
	self.drag = nil
	self.slideTarget = Vector2.zero
	self:updateUpperPosition(Vector2.zero)
	if self.rewardMarker then
		self.rewardMarker:Destroy()
		self.rewardMarker = nil
	end
	clear(self.seamLayer)
	clear(self.progressLayer)
	self.status.Text = "Проведи снизу слева вверх направо по единственной линии"
	self:showCutHint()
end

return Game
