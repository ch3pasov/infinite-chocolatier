--!strict
-- Игровой цикл повторяет пятичастную Curry-перестановку из видео-референса.

local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
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

local function makeLayer(parent: Instance, name: string, zIndex: number): Frame
	local frame = makeFrame(parent, name, Vector2.zero, Vector2.zero, Theme.background, zIndex)
	frame.BackgroundTransparency = 1
	frame.ClipsDescendants = false
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
	rounded(frame, math.max(1, math.floor(thickness / 2)))
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

	-- Roblox UI не умеет произвольные маски. Только примитивы, пересечённые
	-- диагональю, раскладываются на однопиксельные колонки; прямоугольные
	-- границы остальных частей обрезаются дешёвым ClipsDescendants.
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

local function renderUpperExtensionRect(
	parent: Instance,
	line: Geom.Line,
	extension: number,
	name: string,
	position: Vector2,
	size: Vector2,
	radius: number,
	color: Color3,
	zIndex: number,
	columnWidth: number
)
	-- Это продолжение уже существующего спрайта, а не новая шоколадная часть.
	-- Для каждой колонки берём только узкую область между настоящей нижней
	-- границей верхнего полигона и её оптически растянутым положением.
	local x = position.X
	local right = position.X + size.X
	while x < right - 1e-6 do
		local width = math.min(columnWidth, right - x)
		local sampleX = x + width * 0.5
		local top, bottom = roundedVerticalBounds(position, size, radius, sampleX)
		local boundary = Geom.lineYAtX(line, sampleX)
		local extensionTop = math.max(top, math.min(bottom, boundary))
		local extensionBottom = math.min(bottom, boundary + extension)
		if extensionBottom - extensionTop > 0.05 then
			makeFrame(
				parent,
				name .. "Stretch",
				Vector2.new(x, extensionTop),
				Vector2.new(width + 0.08, extensionBottom - extensionTop + 0.08),
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
	self.pieces = {}
	self.animationToken = 0
	self.tweens = {}

	self.root = makeFrame(gui, "Root", Vector2.zero, Vector2.zero, Theme.background, 1)
	self.root.Size = UDim2.fromScale(1, 1)

	self.counter = Instance.new("TextLabel")
	self.counter.Name = "Counter"
	self.counter.AnchorPoint = Vector2.new(0.5, 0)
	self.counter.Position = UDim2.new(0.5, 0, 0, 12)
	self.counter.Size = UDim2.fromOffset(260, 48)
	self.counter.BackgroundTransparency = 1
	self.counter.Font = Enum.Font.GothamBold
	self.counter.TextXAlignment = Enum.TextXAlignment.Center
	self.counter.TextColor3 = Theme.accent
	self.counter.TextSize = 25
	self.counter.Text = "ДОЛЬКИ  0"
	self.counter.ZIndex = 900
	self.counter.Parent = self.root

	self.status = Instance.new("TextLabel")
	self.status.Name = "Status"
	self.status.AnchorPoint = Vector2.new(0.5, 1)
	self.status.Position = UDim2.fromScale(0.5, Config.Board.statusPositionY)
	self.status.Size = UDim2.fromScale(0.94, 0.08)
	self.status.BackgroundTransparency = 1
	self.status.Font = Enum.Font.GothamMedium
	self.status.TextColor3 = Theme.accentSoft
	self.status.TextScaled = true
	self.status.ZIndex = 900
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 17
	textConstraint.MaxTextSize = 28
	textConstraint.Parent = self.status
	self.status.Parent = self.root

	self.board = makeFrame(self.root, "ChocolateBoard", Vector2.zero, Vector2.zero, Theme.background, 2)
	self.board.AnchorPoint = Vector2.new(0.5, 0.5)
	self.board.BackgroundTransparency = 1
	self.board.ClipsDescendants = false

	self.pieceLayer = makeLayer(self.board, "PhysicalPieces", 5)
	self.seamLayer = makeLayer(self.board, "PhysicalSeams", 400)
	self.hintLayer = makeLayer(self.board, "Hints", 500)
	self.progressLayer = makeLayer(self.board, "CutProgress", 600)

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
	for _, layer in { self.pieceLayer, self.seamLayer, self.hintLayer, self.progressLayer } do
		layer.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	end

	self.paths = self:buildPaths()
	local path = self.paths[1]
	self.diagonal = { a = path.points[1], b = path.points[#path.points] }
	self:buildPieces()
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

function Game:buildPieces()
	clear(self.pieceLayer)
	self.pieces = {}

	for _, name in self.trick.pieceOrder do
		local spec = self.trick.pieces[name]
		local bounds = spec.bounds
		local origin = Vector2.new(bounds[1] * self.tileWidth, bounds[2] * self.tileHeight)
		local size = Vector2.new((bounds[3] - bounds[1]) * self.tileWidth, (bounds[4] - bounds[2]) * self.tileHeight)
		local baseZ = 20 + spec.z * 20
		local motion = makeFrame(self.pieceLayer, name, origin, size, Theme.background, baseZ)
		motion.BackgroundTransparency = 1
		motion.ClipsDescendants = false

		local crop = makeFrame(motion, "Crop", Vector2.zero, size, Theme.background, baseZ)
		crop.BackgroundTransparency = 1
		crop.ClipsDescendants = true

		local surface = makeFrame(crop, "Surface", -origin, Vector2.new(self.boardWidth, self.boardHeight), Theme.background, baseZ)
		surface.BackgroundTransparency = 1
		surface.ClipsDescendants = false

		local opticalSurface = nil
		if spec.clip == "upper" then
			local group = Instance.new("CanvasGroup")
			group.Name = "OpticalStretch"
			group.Position = UDim2.fromOffset(-origin.X, -origin.Y)
			group.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
			group.BackgroundTransparency = 1
			group.GroupTransparency = 1
			group.ClipsDescendants = false
			group.ZIndex = baseZ
			group.Parent = crop
			opticalSurface = group
		end

		self.pieces[name] = {
			name = name,
			spec = spec,
			motion = motion,
			crop = crop,
			surface = surface,
			opticalSurface = opticalSurface,
			origin = origin,
			size = size,
			offset = Vector2.zero,
			baseZ = baseZ,
		}
	end
end

function Game:renderPrimitive(
	name: string,
	position: Vector2,
	size: Vector2,
	radius: number,
	color: Color3,
	zOffset: number
)
	local columnWidth = math.max(1, self.trick.clipColumnWidth)
	for _, pieceName in self.trick.pieceOrder do
		local piece = self.pieces[pieceName]
		-- Не создаём невидимые копии долек за пределами прямоугольного crop.
		-- Это особенно важно для двух верхних частей на слабом ноутбуке.
		if position.X + size.X <= piece.origin.X
			or position.X >= piece.origin.X + piece.size.X
			or position.Y + size.Y <= piece.origin.Y
			or position.Y >= piece.origin.Y + piece.size.Y
		then
			continue
		end
		local zIndex = piece.baseZ + zOffset
		if piece.spec.clip == "upper" then
			renderClippedRoundedRect(
				piece.surface,
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
			if piece.opticalSurface then
				renderUpperExtensionRect(
					piece.opticalSurface,
					self.diagonal,
					self.trick.opticalStretchRows * self.tileHeight,
					name,
					position,
					size,
					radius,
					color,
					zIndex,
					columnWidth
				)
			end
		elseif piece.spec.clip == "lower" then
			renderClippedRoundedRect(
				piece.surface,
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
		else
			makeFrame(piece.surface, name, position, size, color, zIndex, radius)
		end
	end
end

function Game:renderChocolate()
	for _, pieceName in self.trick.pieceOrder do
		local piece = self.pieces[pieceName]
		clear(piece.surface)
		if piece.opticalSurface then
			clear(piece.opticalSurface)
		end
	end

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

function Game:setOpticalStretch(progress: number)
	local visible = math.pow(math.clamp(progress, 0, 1), self.trick.opticalStretchRevealPower)
	for _, name in { "upperLeft", "upperRight" } do
		local surface = self.pieces[name].opticalSurface
		if surface then
			surface.GroupTransparency = 1 - visible
		end
	end
end

function Game:screenToBoard(position: Vector3 | Vector2): Vector2
	local inset = self.gui.IgnoreGuiInset and Vector2.zero or GuiService:GetGuiInset()
	local screen = Vector2.new(position.X, position.Y) - inset
	return screen - self.board.AbsolutePosition
end

function Game:definitionOffset(definition): Vector2
	return Vector2.new(definition.dx * self.tileWidth, definition.dy * self.tileHeight)
end

function Game:setPieceOffset(name: string, offset: Vector2)
	local piece = self.pieces[name]
	piece.offset = offset
	piece.motion.Position = UDim2.fromOffset(piece.origin.X + offset.X, piece.origin.Y + offset.Y)
end

function Game:cancelTweens()
	for _, tween in self.tweens do
		tween:Cancel()
	end
	self.tweens = {}
	self.animationToken += 1
end

function Game:tweenOffsets(targets, duration: number, callback)
	self:cancelTweens()
	local token = self.animationToken
	for name, target in targets do
		local piece = self.pieces[name]
		piece.offset = target
		local tween = TweenService:Create(
			piece.motion,
			TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.fromOffset(piece.origin.X + target.X, piece.origin.Y + target.Y) }
		)
		table.insert(self.tweens, tween)
		tween:Play()
	end
	task.delay(duration + 0.02, function()
		if self.animationToken == token then
			self.tweens = {}
			callback()
		end
	end)
end

function Game:sourcePoint(name: string, point: Vector2): Vector2
	return point - self.pieces[name].offset
end

function Game:isInsidePiece(name: string, point: Vector2): boolean
	local piece = self.pieces[name]
	local source = self:sourcePoint(name, point)
	if source.X < piece.origin.X
		or source.X > piece.origin.X + piece.size.X
		or source.Y < piece.origin.Y
		or source.Y > piece.origin.Y + piece.size.Y
	then
		return false
	end
	if piece.spec.clip == "upper" then
		return Geom.isUpper(self.diagonal, source, 0.5)
	elseif piece.spec.clip == "lower" then
		return not Geom.isUpper(self.diagonal, source, -0.5)
	end
	return true
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
			makeSegment(parent, startPoint, endPoint, thickness, color, 0.04, 510)
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
			makeSegment(self.progressLayer, segment.a, endPoint, math.max(4, self.tileWidth * 0.065), Theme.cut, 0, 610)
		end
	end
end

function Game:drawSeam(path: CutPath)
	clear(self.seamLayer)
	for _, segment in path.geom.segments do
		makeSegment(self.seamLayer, segment.a, segment.b, math.max(3, self.tileWidth * 0.045), Theme.chocolateShadow, 0.02, 410)
		makeSegment(self.seamLayer, segment.a, segment.b, 1, Theme.chocolateEdge, 0.12, 411)
	end
end

function Game:drawCurryGap()
	clear(self.seamLayer)
	local leftSlide = self:definitionOffset(self.recipe.slides.upperLeft)
	local translated = {
		a = self.diagonal.a + leftSlide,
		b = self.diagonal.b + leftSlide,
	}
	-- После переноса левая часть занимает x=2..5, а правая x=0..2.
	-- Обе дают одну и ту же бесконечную прямую; для шва восстанавливаем её
	-- точки на настоящих боковых гранях собранной плитки.
	local upperA = Vector2.new(0, Geom.lineYAtX(translated, 0))
	local upperB = Vector2.new(self.boardWidth, Geom.lineYAtX(translated, self.boardWidth))
	local middleA = (self.diagonal.a + upperA) * 0.5
	local middleB = (self.diagonal.b + upperB) * 0.5
	-- Площадь Curry-полосы скрыта оптическим растяжением спрайтов. Здесь
	-- остаётся лишь обычный тонкий шов: он объясняет игроку границу частей,
	-- но больше не выдаёт секрет широкой чёрной лентой.
	local thickness = math.max(2, self.tileWidth * self.trick.assembledSeamRatio)
	makeSegment(self.seamLayer, middleA, middleB, thickness, Theme.chocolateShadow, 0.08, 405)
	makeSegment(self.seamLayer, middleA, middleB, 1, Theme.chocolateEdge, 0.22, 406)
end

function Game:showCutHint()
	clear(self.hintLayer)
	clear(self.progressLayer)
	local path = self.paths[1]
	self:drawDashed(path, self.hintLayer, Theme.accentSoft)
	local anchor = Geom.pointAt(path.geom, self.cutProgress)
	local pipSize = math.max(18, math.min(self.tileWidth, self.tileHeight) * 0.32)
	self.startPip = makeFrame(
		self.hintLayer,
		"Start",
		anchor - Vector2.new(pipSize, pipSize) * 0.5,
		Vector2.new(pipSize, pipSize),
		Theme.accent,
		620,
		math.floor(pipSize / 2)
	)
end

function Game:drawArrow(startPoint: Vector2, finish: Vector2)
	clear(self.hintLayer)
	local path = newPath({ startPoint, finish })
	self:drawDashed(path, self.hintLayer, Theme.accentSoft)
	local target = finish - startPoint
	if target.Magnitude < 1 then
		return
	end
	local direction = target.Unit
	local normal = Vector2.new(-direction.Y, direction.X)
	local arrowSize = math.max(13, self.tileWidth * 0.22)
	makeSegment(self.hintLayer, finish, finish - direction * arrowSize + normal * arrowSize * 0.62, 4, Theme.accent, 0, 520)
	makeSegment(self.hintLayer, finish, finish - direction * arrowSize - normal * arrowSize * 0.62, 4, Theme.accent, 0, 520)
end

function Game:pieceCenter(name: string): Vector2
	local piece = self.pieces[name]
	return piece.origin + piece.size * 0.5
end

function Game:showLargeHint()
	local name = "upperLeft"
	local exploded = self:definitionOffset(self.trick.exploded[name])
	local target = self:definitionOffset(self.recipe.slides[name])
	local anchor = Vector2.new(
		self.trick.largeHintAnchor.x * self.tileWidth,
		self.trick.largeHintAnchor.y * self.tileHeight
	)
	self:drawArrow(anchor + exploded, anchor + target)
	self.status.Text = "Сдвинь крупную часть по стрелке — вторая повторит перестановку"
end

function Game:showStripHint()
	local name = "stripDouble"
	local exploded = self:definitionOffset(self.trick.exploded[name])
	local target = self:definitionOffset(self.recipe.slides[name])
	local center = self:pieceCenter(name)
	self:drawArrow(center + exploded, center + target)
	self.status.Text = "Вставь блок из двух долек в верхнюю нишу"
end

function Game:setLargeProgress(progress: number)
	self.largeProgress = math.clamp(progress, 0, 1)
	self:setOpticalStretch(self.largeProgress)
	for _, name in { "upperLeft", "upperRight" } do
		local from = self:definitionOffset(self.trick.exploded[name])
		local target = self:definitionOffset(self.recipe.slides[name])
		self:setPieceOffset(name, from:Lerp(target, self.largeProgress))
	end
end

function Game:setStripProgress(progress: number)
	self.stripProgress = math.clamp(progress, 0, 1)
	for _, name in { "stripDouble", "stripSingle" } do
		local from = self:definitionOffset(self.trick.exploded[name])
		local target = self:definitionOffset(self.recipe.slides[name])
		self:setPieceOffset(name, from:Lerp(target, self.stripProgress))
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
			local path = self.paths[1]
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
		elseif self.active == "assembleLarge" then
			for _, name in { "upperLeft", "upperRight" } do
				if self:isInsidePiece(name, point) then
					local from = self:definitionOffset(self.trick.exploded[name])
					local target = self:definitionOffset(self.recipe.slides[name])
					self.drag = {
						kind = "large",
						startPoint = point,
						startProgress = self.largeProgress,
						driver = target - from,
					}
					break
				end
			end
		elseif self.active == "assembleStrip" and self:isInsidePiece("stripDouble", point) then
			local from = self:definitionOffset(self.trick.exploded.stripDouble)
			local target = self:definitionOffset(self.recipe.slides.stripDouble)
			self.drag = {
				kind = "strip",
				startPoint = point,
				startProgress = self.stripProgress,
				driver = target - from,
			}
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
		local path = self.paths[1]
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
	elseif drag.kind == "large" or drag.kind == "strip" then
		local driver = drag.driver
		local denominator = driver:Dot(driver)
		if denominator <= 1e-6 then
			return
		end
		local progress = drag.startProgress + (point - drag.startPoint):Dot(driver) / denominator
		if drag.kind == "large" then
			self:setLargeProgress(progress)
		else
			self:setStripProgress(progress)
		end
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
			local path = self.paths[1]
			local anchor = Geom.pointAt(path.geom, self.cutProgress)
			self.startPip.Position = UDim2.fromOffset(
				anchor.X - self.startPip.AbsoluteSize.X / 2,
				anchor.Y - self.startPip.AbsoluteSize.Y / 2
			)
			self.startPip.Visible = true
		end
	elseif drag.kind == "large" then
		if self.largeProgress >= Config.Sliding.completeAt then
			self:setLargeProgress(1)
			self:finishLargeAssembly()
		else
			self:setOpticalStretch(0)
			self.active = "snappingLarge"
			local targets = {}
			for _, name in { "upperLeft", "upperRight" } do
				targets[name] = self:definitionOffset(self.trick.exploded[name])
			end
			self:tweenOffsets(targets, self.trick.snapDuration, function()
				self.largeProgress = 0
				self.active = "assembleLarge"
			end)
		end
	elseif drag.kind == "strip" then
		if self.stripProgress >= Config.Sliding.completeAt then
			self:setStripProgress(1)
			self:finishRound()
		else
			self.active = "snappingStrip"
			local targets = {}
			for _, name in { "stripDouble", "stripSingle" } do
				targets[name] = self:definitionOffset(self.trick.exploded[name])
			end
			self:tweenOffsets(targets, self.trick.snapDuration, function()
				self.stripProgress = 0
				self.active = "assembleStrip"
			end)
		end
	end
end

function Game:finishCut()
	if self.active ~= "cut" then
		return
	end
	self.drag = nil
	local path = self.paths[1]
	if self.startPip then
		self.startPip:Destroy()
		self.startPip = nil
	end
	clear(self.hintLayer)
	self:drawProgress(path, path.geom.length)
	self:drawSeam(path)
	self.active = "exploding"
	self.status.Text = "Разрез готов — плитка раскрывается на пять исходных частей"

	local targets = {}
	for _, name in self.trick.pieceOrder do
		targets[name] = self:definitionOffset(self.trick.exploded[name])
	end
	task.delay(0.14, function()
		if self.active ~= "exploding" then
			return
		end
		clear(self.progressLayer)
		clear(self.seamLayer)
		self:tweenOffsets(targets, self.trick.explodeDuration, function()
			self.active = "assembleLarge"
			self.largeProgress = 0
			self:showLargeHint()
		end)
	end)
end

function Game:finishLargeAssembly()
	if self.active ~= "assembleLarge" then
		return
	end
	self.active = "assembleStrip"
	self.stripProgress = 0
	self:drawCurryGap()
	self:showStripHint()
end

function Game:showRewardMarker()
	if self.rewardMarker then
		self.rewardMarker:Destroy()
	end
	local piece = self.pieces[self.trick.rewardPiece]
	local marker = makeFrame(
		piece.crop,
		"OriginalExtraSliceMarker",
		Vector2.zero,
		piece.size,
		Theme.accent,
		720,
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
	if self.active ~= "assembleStrip" then
		return
	end
	self.active = "done"
	clear(self.hintLayer)
	self:showRewardMarker()
	self.status.Text = "Готово: плитка снова целая, а исходная долька осталась снаружи"
	-- В RemoteEvent нет количества: клиент сообщает только завершение жеста.
	self.remotes.roundComplete:FireServer()
	task.delay(self.trick.resetDelay, function()
		if self.active == "done" then
			self:beginReset()
		end
	end)
end

function Game:beginReset()
	self.active = "resetting"
	self:setOpticalStretch(0)
	clear(self.hintLayer)
	clear(self.seamLayer)
	if self.rewardMarker then
		self.rewardMarker:Destroy()
		self.rewardMarker = nil
	end
	self.status.Text = "Возвращаем исходные части для нового раунда"
	local targets = {}
	for _, name in self.trick.pieceOrder do
		targets[name] = Vector2.zero
	end
	self:tweenOffsets(targets, self.trick.resetDuration, function()
		self:resetRound()
	end)
end

function Game:resetRound()
	self:cancelTweens()
	self.active = "cut"
	self.cutProgress = 0
	self.largeProgress = 0
	self.stripProgress = 0
	self.drag = nil
	self:setOpticalStretch(0)
	for _, name in self.trick.pieceOrder do
		self:setPieceOffset(name, Vector2.zero)
	end
	if self.rewardMarker then
		self.rewardMarker:Destroy()
		self.rewardMarker = nil
	end
	clear(self.seamLayer)
	clear(self.progressLayer)
	self.status.Text = "Проведи по диагонали: остальные разъёмы уже лежат в бороздках"
	self:showCutHint()
end

return Game
