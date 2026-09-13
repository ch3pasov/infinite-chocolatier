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
local Layout = require(script.Parent.Layout)

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

local function tileVisualMetrics(tileWidth: number, tileHeight: number, trick)
	local tileMin = math.min(tileWidth, tileHeight)
	local gap = math.max(3, round(tileMin * trick.tileGapRatio))
	local bevel = math.max(3, round(tileMin * trick.bevelRatio))
	local corner = math.max(6, round(tileMin * trick.cornerRatio))
	return gap, bevel, corner
end

local function makeCanonicalTileTemplate(
	parent: Instance,
	tileWidth: number,
	tileHeight: number,
	gap: number,
	bevel: number,
	corner: number
): Frame
	-- Исходная плитка не собирается из отдельно обрезанных фасок. Один
	-- неизменяемый мотив дольки клонируется во все 25 ячеек, поэтому у
	-- диагонали физически нет возможности изменить её рамку или рельеф.
	local template = makeFrame(
		parent,
		"CanonicalTileTemplate",
		Vector2.zero,
		Vector2.new(tileWidth, tileHeight),
		Theme.background,
		1
	)
	template.BackgroundTransparency = 1
	template.Visible = false

	local tileSize = Vector2.new(tileWidth - gap * 2, tileHeight - gap * 2)
	makeFrame(template, "Bevel", Vector2.new(gap, gap), tileSize, Theme.chocolateEdge, 2, corner)
	makeFrame(
		template,
		"Face",
		Vector2.new(gap + bevel, gap + bevel),
		tileSize - Vector2.new(bevel * 2, bevel * 2),
		Theme.chocolate,
		3,
		math.max(4, corner - bevel)
	)

	local panelInsetX = bevel * 2.0
	local panelInsetY = bevel * 2.5
	makeFrame(
		template,
		"Relief",
		Vector2.new(gap + panelInsetX, gap + panelInsetY),
		tileSize - Vector2.new(panelInsetX * 2, panelInsetY * 2),
		Theme.chocolateRaised,
		4,
		math.max(3, corner - bevel)
	)
	return template
end

local function offsetZIndices(root: GuiObject, offset: number)
	root.ZIndex += offset
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex += offset
		end
	end
end

local function cloneCanonicalTile(
	parent: Instance,
	template: Frame,
	name: string,
	position: Vector2,
	zOffset: number
): Frame
	-- Во всех состояниях игры существует ровно один рисунок дольки. Даже
	-- диагональные куски показывают не заново нарисованную фаску, а окно в
	-- неизменённый клон этого шаблона.
	local tile = template:Clone()
	tile.Name = name
	tile.Position = UDim2.fromOffset(position.X, position.Y)
	tile.Visible = true
	offsetZIndices(tile, zOffset)
	tile.Parent = parent
	return tile
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

local function renderUpperExtensionBody(
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
	-- Тёмная подложка не является рисунком дольки: она лишь закрывает щель под
	-- клонами шаблона. Сам мотив ниже обрезается отдельной функцией.
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

local function renderClippedCanonicalTile(
	parent: Instance,
	template: Frame,
	line: Geom.Line,
	mode: string,
	name: string,
	position: Vector2,
	size: Vector2,
	extension: number,
	zOffset: number,
	columnWidth: number
)
	local upperCorners = rectCornerCount(line, position, size)
	if mode == "upper" and upperCorners == 4 then
		cloneCanonicalTile(parent, template, name, position, zOffset)
		return
	elseif mode == "upper" and upperCorners == 0 then
		return
	elseif mode == "lower" and upperCorners == 0 then
		cloneCanonicalTile(parent, template, name, position, zOffset)
		return
	elseif mode == "lower" and upperCorners == 4 then
		return
	end

	-- Roblox UI не имеет polygon clipping. Только дольки, которых касается
	-- диагональ, делятся на узкие окна. В каждом окне находится клон ТОГО ЖЕ
	-- CanonicalTileTemplate со смещением назад в исходную позицию. Поэтому
	-- фаска и рельеф не могут стать другой формы ни на одном этапе.
	local x = position.X
	local right = position.X + size.X
	while x < right - 1e-6 do
		local width = math.min(columnWidth, right - x)
		local sampleX = x + width * 0.5
		local boundary = Geom.lineYAtX(line, sampleX)
		local top = position.Y
		local bottom = position.Y + size.Y
		local bleed = Config.Trick.clipBleed
		-- Соседние окна показывают один и тот же мотив в тех же координатах.
		-- Перекрытие закрывает погрешность округления границ, не растягивая
		-- рисунок. Оно ограничено ячейкой, чтобы не залезать на соседние дольки.
		if mode == "upper" then
			bottom = math.min(bottom, boundary + bleed)
		elseif mode == "lower" then
			top = math.max(top, boundary - bleed)
		else
			top = math.max(top, boundary - bleed)
			bottom = math.min(bottom, boundary + extension + bleed)
		end
		if bottom - top > 0.05 then
			local maskPosition = Vector2.new(x, top)
			local mask = makeFrame(
				parent,
				name .. "Mask",
				maskPosition,
				Vector2.new(math.min(width + bleed, right - x), bottom - top),
				Theme.background,
				1 + zOffset
			)
			mask.BackgroundTransparency = 1
			mask.ClipsDescendants = true
			cloneCanonicalTile(mask, template, name .. "Slice", position - maskPosition, zOffset)
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
	self.cutIndex = 1
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
	self.status.Position = UDim2.new(0.5, 0, 1, -12)
	self.status.Size = UDim2.new(0.94, 0, 0, Config.Board.viewportPadding.bottom - 24)
	self.status.BackgroundTransparency = 1
	self.status.Font = Enum.Font.GothamMedium
	self.status.TextColor3 = Theme.accentSoft
	self.status.TextScaled = true
	self.status.TextWrapped = true
	self.status.ZIndex = 900
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 14
	textConstraint.MaxTextSize = 28
	textConstraint.Parent = self.status
	self.status.Parent = self.root

	self.board = makeFrame(self.root, "ChocolateBoard", Vector2.zero, Vector2.zero, Theme.background, 2)
	self.board.AnchorPoint = Vector2.zero
	self.board.BackgroundTransparency = 1
	self.board.ClipsDescendants = false
	self.boardScale = Instance.new("UIScale")
	self.boardScale.Name = "ViewportScale"
	self.boardScale.Parent = self.board

	-- Готовая Curry-кромка живёт в отдельной подложке. Если держать её внутри
	-- верхних частей, Sibling-ZIndex поднимает её над основанием и она уродует
	-- целые дольки ещё до разреза. Подложка движется вместе с кусками, но видна
	-- только в реально открывшемся зазоре.
	self.extensionLayer = makeLayer(self.board, "OpticalExtensions", 4)
	self.pieceLayer = makeLayer(self.board, "PhysicalPieces", 5)
	-- Пока части не расходятся, игрок видит одну каноническую плитку. Она
	-- скрывает техническую попиксельную маску физических полигонов, но лежит
	-- ниже настоящих линий реза. В момент разделения слой убирается, и его
	-- полностью совпадающее изображение продолжают уже готовые части.
	self.intactLayer = makeLayer(self.board, "CanonicalIntactBoard", 6)
	self.seamLayer = makeLayer(self.board, "PhysicalSeams", 400)
	self.hintLayer = makeLayer(self.board, "Hints", 500)
	self.progressLayer = makeLayer(self.board, "CutProgress", 600)

	self:layout()
	self:bindInput()
	self:bindViewport()
	return self
end

function Game:layout()
	-- Канонические окна клиппинга строятся один раз в максимальном размере.
	-- UIScale вписывает готовую сцену; повторный layout сбросил бы раунд.
	local scale = math.min(
		self.trick.maxBoardWidth / (self.recipe.cols * self.trick.baseTileWidth),
		self.trick.maxBoardHeight / (self.recipe.rows * self.trick.baseTileHeight)
	)

	self.tileWidth = round(self.trick.baseTileWidth * scale)
	self.tileHeight = round(self.trick.baseTileHeight * scale)
	self.boardWidth = self.tileWidth * self.recipe.cols
	self.boardHeight = self.tileHeight * self.recipe.rows
	self.board.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	self.layoutBounds = Layout.bounds(self.recipe, self.trick, self.tileWidth, self.tileHeight, Geom)
	for _, layer in {
		self.extensionLayer,
		self.pieceLayer,
		self.intactLayer,
		self.seamLayer,
		self.hintLayer,
		self.progressLayer,
	} do
		layer.Size = UDim2.fromOffset(self.boardWidth, self.boardHeight)
	end

	self.paths = self:buildPaths()
	local path = self.paths[1]
	self.diagonal = { a = path.points[1], b = path.points[#path.points] }
	self:buildPieces()
	self:renderChocolate()
	self:resetRound()
end

function Game:bindViewport()
	-- Размер Root уже учитывает фактическую область ScreenGui и не зависит
	-- от смены CurrentCamera или времени её появления на клиенте.
	self.viewportChanged = self.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:fitViewport()
	end)
	self:fitViewport()
end

function Game:fitViewport()
	local viewport = self.root.AbsoluteSize
	if viewport == self.viewportSize then
		return
	end
	local presentation = Layout.presentation(viewport.X, viewport.Y, Config.Board.viewportPadding)
	local fit = Layout.fit(viewport.X, viewport.Y, self.layoutBounds, presentation.padding)
	if not fit then
		return
	end
	-- При смене координат отпускаем текущий захват: старые экранные точки
	-- иначе вызвали бы скачок. Уже пройденный разрез и текущий этап сохраняются.
	self:endDrag(true)
	self.viewportSize = viewport
	self.boardScale.Scale = fit.scale
	self.board.Position = UDim2.fromOffset(fit.x, fit.y)
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
	clear(self.extensionLayer)
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

		local extensionMotion: Frame? = nil
		local extensionSurface: Frame? = nil
		if spec.clip == "upper" then
			extensionMotion = makeFrame(self.extensionLayer, name .. "Extension", origin, size, Theme.background, baseZ)
			extensionMotion.BackgroundTransparency = 1
			extensionMotion.ClipsDescendants = false

			local extensionCrop = makeFrame(extensionMotion, "Crop", Vector2.zero, size, Theme.background, baseZ)
			extensionCrop.BackgroundTransparency = 1
			extensionCrop.ClipsDescendants = true

			extensionSurface = makeFrame(
				extensionCrop,
				"Surface",
				-origin,
				Vector2.new(self.boardWidth, self.boardHeight),
				Theme.background,
				baseZ
			)
			extensionSurface.BackgroundTransparency = 1
			extensionSurface.ClipsDescendants = false
		end

		self.pieces[name] = {
			name = name,
			spec = spec,
			motion = motion,
			crop = crop,
			surface = surface,
			origin = origin,
			size = size,
			offset = Vector2.zero,
			baseZ = baseZ,
			extensionMotion = extensionMotion,
			extensionSurface = extensionSurface,
		}
	end
end

function Game:renderBarBody(corner: number)
	local columnWidth = math.max(1, self.trick.clipColumnWidth)
	for _, pieceName in self.trick.pieceOrder do
		local piece = self.pieces[pieceName]
		local zIndex = piece.baseZ + 1
		if piece.spec.clip == "upper" then
			-- Исходный верхний правый угол после перестановки становится
			-- внутренним стыком. Скругление подложки оставляло там выемку.
			-- Рельеф долек сохраняет свои скругления в каноническом шаблоне.
			renderClippedRoundedRect(
				piece.surface,
				self.diagonal,
				true,
				"BarBody",
				Vector2.zero,
				Vector2.new(self.boardWidth, self.boardHeight),
				0,
				Theme.chocolateDark,
				zIndex,
				columnWidth
			)
			renderUpperExtensionBody(
				piece.extensionSurface,
				self.diagonal,
				self.trick.opticalStretchRows * self.tileHeight,
				"BarBody",
				Vector2.zero,
				Vector2.new(self.boardWidth, self.boardHeight),
				0,
				Theme.chocolateDark,
				zIndex,
				columnWidth
			)
		elseif piece.spec.clip == "lower" then
			renderClippedRoundedRect(
				piece.surface,
				self.diagonal,
				false,
				"BarBody",
				Vector2.zero,
				Vector2.new(self.boardWidth, self.boardHeight),
				corner,
				Theme.chocolateDark,
				zIndex,
				columnWidth
			)
		else
			makeFrame(
				piece.surface,
				"BarBody",
				Vector2.zero,
				Vector2.new(self.boardWidth, self.boardHeight),
				Theme.chocolateDark,
				zIndex,
				corner
			)
		end
	end
end

function Game:renderCanonicalTilesForPieces(template: Frame)
	local columnWidth = math.max(1, self.trick.clipColumnWidth)
	local tileSize = Vector2.new(self.tileWidth, self.tileHeight)
	local extension = self.trick.opticalStretchRows * self.tileHeight
	for row = 0, self.recipe.rows - 1 do
		for column = 0, self.recipe.cols - 1 do
			local tilePosition = Vector2.new(column * self.tileWidth, row * self.tileHeight)
			local tileName = `Tile{row + 1}_{column + 1}`
			for _, pieceName in self.trick.pieceOrder do
				local piece = self.pieces[pieceName]
				-- Прямоугольный crop части сам обрежет крайние клоны. Здесь не
				-- создаём клетки, которые с crop вообще не пересекаются.
				if tilePosition.X + tileSize.X <= piece.origin.X
					or tilePosition.X >= piece.origin.X + piece.size.X
					or tilePosition.Y + tileSize.Y <= piece.origin.Y
					or tilePosition.Y >= piece.origin.Y + piece.size.Y
				then
					continue
				end

				if piece.spec.clip == "upper" then
					renderClippedCanonicalTile(
						piece.surface,
						template,
						self.diagonal,
						"upper",
						tileName,
						tilePosition,
						tileSize,
						0,
						piece.baseZ,
						columnWidth
					)
					renderClippedCanonicalTile(
						piece.extensionSurface,
						template,
						self.diagonal,
						"extension",
						tileName .. "Extension",
						tilePosition,
						tileSize,
						extension,
						piece.baseZ,
						columnWidth
					)
				elseif piece.spec.clip == "lower" then
					renderClippedCanonicalTile(
						piece.surface,
						template,
						self.diagonal,
						"lower",
						tileName,
						tilePosition,
						tileSize,
						0,
						piece.baseZ,
						columnWidth
					)
				else
					cloneCanonicalTile(piece.surface, template, tileName, tilePosition, piece.baseZ)
				end
			end
		end
	end
end

function Game:renderIntactChocolate(template: Frame, corner: number)
	makeFrame(
		self.intactLayer,
		"BarBody",
		Vector2.zero,
		Vector2.new(self.boardWidth, self.boardHeight),
		Theme.chocolateDark,
		1,
		corner
	)
	for row = 0, self.recipe.rows - 1 do
		for column = 0, self.recipe.cols - 1 do
			cloneCanonicalTile(
				self.intactLayer,
				template,
				`Tile{row + 1}_{column + 1}`,
				Vector2.new(column * self.tileWidth, row * self.tileHeight),
				0
			)
		end
	end
	self.intactLayer.Visible = true
end

function Game:renderChocolate()
	for _, pieceName in self.trick.pieceOrder do
		local piece = self.pieces[pieceName]
		clear(piece.surface)
		if piece.extensionSurface then
			clear(piece.extensionSurface)
		end
	end
	clear(self.intactLayer)

	local gap, bevel, corner = tileVisualMetrics(self.tileWidth, self.tileHeight, self.trick)
	local template = makeCanonicalTileTemplate(
		self.intactLayer,
		self.tileWidth,
		self.tileHeight,
		gap,
		bevel,
		corner
	)
	self:renderBarBody(corner + gap)
	self:renderCanonicalTilesForPieces(template)
	self:renderIntactChocolate(template, corner + gap)
end

function Game:screenToBoard(position: Vector3 | Vector2): Vector2
	local inset = self.gui.IgnoreGuiInset and Vector2.zero or GuiService:GetGuiInset()
	local screen = Vector2.new(position.X, position.Y) - inset
	return (screen - self.board.AbsolutePosition) / self.boardScale.Scale
end

function Game:definitionOffset(definition): Vector2
	return Vector2.new(definition.dx * self.tileWidth, definition.dy * self.tileHeight)
end

function Game:setPieceOffset(name: string, offset: Vector2)
	local piece = self.pieces[name]
	piece.offset = offset
	piece.motion.Position = UDim2.fromOffset(piece.origin.X + offset.X, piece.origin.Y + offset.Y)
	if piece.extensionMotion then
		piece.extensionMotion.Position = UDim2.fromOffset(piece.origin.X + offset.X, piece.origin.Y + offset.Y)
	end
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
		if piece.extensionMotion then
			local extensionTween = TweenService:Create(
				piece.extensionMotion,
				TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(piece.origin.X + target.X, piece.origin.Y + target.Y) }
			)
			table.insert(self.tweens, extensionTween)
			extensionTween:Play()
		end
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
	for _, segment in path.geom.segments do
		makeSegment(self.seamLayer, segment.a, segment.b, math.max(3, self.tileWidth * 0.045), Theme.chocolateShadow, 0.02, 410)
		makeSegment(self.seamLayer, segment.a, segment.b, 1, Theme.chocolateEdge, 0.12, 411)
	end
end

function Game:drawAssembledSeam()
	clear(self.seamLayer)
	-- Швы нужны во время нарезки, но после соединения даже одна обводка
	-- раскрывает устройство фокуса. Здесь остаётся только непрерывный рисунок
	-- настоящих частей и их заранее подготовленной кромки.
end

function Game:showCutHint()
	clear(self.hintLayer)
	clear(self.progressLayer)
	local path = self.paths[self.cutIndex]
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
	local label = self.trick.cutLabels[self.cutIndex]
	self.status.Text = `Разрез {self.cutIndex} из {#self.paths}: {label}`
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
		if processed or self.drag or self.inputBlocked then
			return
		end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
			return
		end

		local point = self:screenToBoard(input.Position)
		if self.active == "cut" then
			local path = self.paths[self.cutIndex]
			local anchor = Geom.pointAt(path.geom, self.cutProgress)
			local _, arc = Geom.project(path.geom, point)
			local startRadius = Config.Cutting.startRadius / self.boardScale.Scale
			if (point - anchor).Magnitude <= startRadius
				and math.abs(arc - self.cutProgress) <= startRadius
			then
				self.drag = {
					kind = "cut",
					progress = self.cutProgress,
					ready = self.cutProgress >= path.geom.length * Config.Cutting.completeAt,
					input = input,
				}
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
						input = input,
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
				input = input,
				startPoint = point,
				startProgress = self.stripProgress,
				driver = target - from,
			}
		end
	end)

	self.changed = UserInputService.InputChanged:Connect(function(input)
		if not self:ownsDragInput(input, true) then
			return
		end
		self:updateDrag(self:screenToBoard(input.Position))
	end)

	self.ended = UserInputService.InputEnded:Connect(function(input)
		if not self:ownsDragInput(input, false) then
			return
		end
		local cancelled = input.UserInputState == Enum.UserInputState.Cancel
		if not cancelled then
			self:updateDrag(self:screenToBoard(input.Position))
		end
		self:endDrag(cancelled)
	end)

	-- При переключении окна или открытии меню отпускание может не прийти.
	-- Прерывание освобождает захват, но не засчитывает разрез или награду.
	self.focusReleased = UserInputService.WindowFocusReleased:Connect(function()
		self:endDrag(true)
	end)
	self.menuOpened = GuiService.MenuOpened:Connect(function()
		self:endDrag(true)
	end)
end

function Game:ownsDragInput(input: InputObject, movement: boolean): boolean
	local drag = self.drag
	if not drag then
		return false
	end
	-- У каждого пальца свой InputObject; мышь присылает движение отдельно
	-- от нажатой кнопки. Другой палец не должен двигать или отпускать этот жест.
	if drag.input.UserInputType == Enum.UserInputType.Touch then
		return input == drag.input
	end
	return input.UserInputType == (if movement then Enum.UserInputType.MouseMovement else Enum.UserInputType.MouseButton1)
end

function Game:updateDrag(point: Vector2)
	local drag = self.drag
	if not drag then
		return
	end

	if drag.kind == "cut" then
		local path = self.paths[self.cutIndex]
		-- Все четыре игровые линии прямые. Незажатая проекция позволяет одному
		-- быстрому событию ввода оказаться за финишем и всё равно засчитать
		-- реальный взмах вдоль линии, вместо прежнего ограничения maxJump.
		local first = path.geom.segments[1]
		local last = path.geom.segments[#path.geom.segments]
		local distance, arc = Geom.project(path.geom, point)
		if first and last then
			local lineDistance, lineArc = Geom.projectLine(first.a, last.b, point)
			if lineArc >= 0 then
				distance = lineDistance
				arc = math.min(lineArc, path.geom.length)
			end
		end
		-- Допуски заданы в экранных пикселях: уменьшение сцены не должно
		-- требовать от пальца большей точности или более частых событий ввода.
		local scale = self.boardScale.Scale
		if drag.ready then
			-- Конец защёлкнут до отпускания. Последующее движение или координата
			-- InputEnded не могут внезапно отменить уже завершённый взмах.
			return
		end
		if distance > Config.Cutting.slipTolerance / scale then
			-- Нет наказания за дрогнувший палец: сохраняем сделанную часть и ждём,
			-- пока указатель вернётся к подсвеченной точке на линии.
			if self.startPip then
				local anchor = Geom.pointAt(path.geom, drag.progress)
				self.startPip.Position = UDim2.fromOffset(
					anchor.X - self.startPip.Size.X.Offset / 2,
					anchor.Y - self.startPip.Size.Y.Offset / 2
				)
				self.startPip.Visible = true
			end
			self.status.Text = "Вернись к подсвеченной точке — прогресс сохранён"
			return
		end
		if self.startPip then
			self.startPip.Visible = false
		end
		drag.progress = math.max(drag.progress, arc)
		self.cutProgress = drag.progress
		self:drawProgress(path, drag.progress)
		if drag.progress >= path.geom.length * Config.Cutting.completeAt then
			-- Сам жест ещё не завершён: игрок должен почувствовать конечную точку
			-- и явно отпустить мышь или палец. Следующий пунктир до отпускания не
			-- появляется.
			drag.progress = path.geom.length
			self.cutProgress = path.geom.length
			drag.ready = true
			self:drawProgress(path, path.geom.length)
			self.status.Text = "Отпусти, чтобы завершить разрез"
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

function Game:finishCutSmoothly(path)
	local start = self.cutProgress
	local index, token = self.cutIndex, self.animationToken
	self.active = "finishingCut"
	if self.startPip then self.startPip.Visible = false end
	-- Доводка начинается только после отпускания. Пока кнопка удерживается,
	-- отрисованный прогресс ни на пиксель не опережает выполненный жест.
	local steps = Config.Cutting.finishSnapSteps
	for step = 1, steps do
		task.delay(Config.Cutting.finishSnapDuration * step / steps, function()
			if self.active ~= "finishingCut" or self.cutIndex ~= index or self.animationToken ~= token then return end
			local t = step / steps
			self.cutProgress = math.max(self.cutProgress, start + (path.geom.length - start) * (1 - (1 - t) ^ 2))
			self:drawProgress(path, self.cutProgress)
			if step == steps then
				self.active = "cut"
				self:finishCut()
			end
		end)
	end
end

function Game:endDrag(cancelled: boolean?)
	local drag = self.drag
	if not drag then
		return
	end
	self.drag = nil

	if drag.kind == "cut" then
		if self.active == "cut" then
			local path = self.paths[self.cutIndex]
			if not cancelled and (drag.ready or self.cutProgress >= path.geom.length * Config.Cutting.completeAt) then
				self:finishCut()
				return
			end
			local snapDistance = math.min(Config.Cutting.finishSnapRadius / self.boardScale.Scale,
				path.geom.length * (1 - Config.Cutting.finishSnapMinProgress))
			if not cancelled and self.cutProgress >= path.geom.length - snapDistance then
				self:finishCutSmoothly(path)
				return
			end
			if self.startPip then
				local anchor = Geom.pointAt(path.geom, self.cutProgress)
				self.startPip.Position = UDim2.fromOffset(
					anchor.X - self.startPip.Size.X.Offset / 2,
					anchor.Y - self.startPip.Size.Y.Offset / 2
				)
				self.startPip.Visible = true
			end
			self.status.Text = `Разрез {self.cutIndex} из {#self.paths}: продолжи с подсвеченной точки`
		end
	elseif drag.kind == "large" then
		if not cancelled and self.largeProgress >= Config.Sliding.completeAt then
			self:setLargeProgress(1)
			self:finishLargeAssembly()
		else
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
		if not cancelled and self.stripProgress >= Config.Sliding.completeAt then
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
	local path = self.paths[self.cutIndex]
	if self.startPip then
		self.startPip:Destroy()
		self.startPip = nil
	end
	clear(self.hintLayer)
	clear(self.progressLayer)
	self:drawSeam(path)

	if self.cutIndex < #self.paths then
		self.cutIndex += 1
		self.cutProgress = 0
		self:showCutHint()
		return
	end

	self.active = "exploding"
	self.status.Text = "Все четыре разреза готовы — плитка раскрывается на пять частей"

	local targets = {}
	for _, name in self.trick.pieceOrder do
		targets[name] = self:definitionOffset(self.trick.exploded[name])
	end
	task.delay(0.14, function()
		if self.active ~= "exploding" then
			return
		end
		-- До этого кадра все 25 дольки были клонами одного шаблона. Теперь
		-- части действительно расходятся, и становится видна их диагональная
		-- граница вместо технической маски на цельной плитке.
		self.intactLayer.Visible = false
		-- Подложка остаётся видимой и едет вместе с куском весь сдвиг.
		-- Включение только на финише выдаёт фокус мгновенным заполнением щели.
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
	self:drawAssembledSeam()
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

function Game:playRewardEffect(amount: number)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 or amount == math.huge then return end
	local settings = Config.Feedback
	local piece = self.pieces[self.trick.rewardPiece]
	local size = self.root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	local point = self.board.AbsolutePosition - self.root.AbsolutePosition
		+ (piece.origin + piece.offset + piece.size / 2) * self.boardScale.Scale
	-- Число остаётся внутри экрана даже у внешней левой дольки. Эффект
	-- отдельный от полигонов: сброс раунда не обрывает его и не задерживает ввод.
	point = Vector2.new(math.clamp(point.X, 80, math.max(80, size.X - 80)),
		math.clamp(point.Y, 100, math.max(100, size.Y - 60)))
	local effect = makeFrame(self.root, "RewardEffect", Vector2.zero, Vector2.zero, Theme.background, 920)
	effect.BackgroundTransparency = 1
	effect.Position = UDim2.fromScale(point.X / size.X, point.Y / size.Y)
	local label = Instance.new("TextLabel")
	label.Name = "EarnedSlices"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Size = UDim2.fromOffset(160, 44)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Theme.accentSoft
	label.TextStrokeColor3 = Theme.background
	label.TextStrokeTransparency = 0.15
	label.TextScaled = true
	label.Text = "+" .. (string.format("%.2f", amount):gsub("0+$", ""):gsub("%.$", ""))
	label.ZIndex = 923
	label.Parent = effect
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 12
	limit.MaxTextSize = 32
	limit.Parent = label
	TweenService:Create(label, TweenInfo.new(settings.duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.fromOffset(0, -settings.rise), TextTransparency = 1, TextStrokeTransparency = 1,
	}):Play()
	for index = 1, settings.sparkCount do
		local angle = index / settings.sparkCount * math.pi * 2
		local spark = makeFrame(effect, "CocoaSpark", Vector2.zero, Vector2.new(6, 6), Theme.accent, 921, 3)
		spark.AnchorPoint = Vector2.new(0.5, 0.5)
		TweenService:Create(spark, TweenInfo.new(settings.duration * 0.65, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(math.cos(angle) * 38, math.sin(angle) * 28 - 12),
			BackgroundTransparency = 1, Size = UDim2.fromOffset(2, 2),
		}):Play()
	end
	task.delay(settings.duration, function() effect:Destroy() end)
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
	self:cancelTweens()
	self.active = "collecting"
	clear(self.hintLayer)
	clear(self.seamLayer)
	if self.rewardMarker then
		self.rewardMarker:Destroy()
		self.rewardMarker = nil
	end

	-- Никакой обратной перемотки: собранная плитка остаётся на том же месте.
	-- Канонический слой совпадает с ней пиксель в пиксель и скрывает только
	-- техническую подготовку полигонов следующего раунда.
	self.intactLayer.Visible = true
	local rewardName = self.trick.rewardPiece
	for _, name in self.trick.pieceOrder do
		if name ~= rewardName then
			self:setPieceOffset(name, Vector2.zero)
		end
	end

	-- В референсе внешняя долька постепенно исчезает, а не возвращается вместе
	-- с кусками. Непрозрачное окно растёт от правого края (со стороны плитки)
	-- и «съедает» только уже начисленную исходную дольку.
	local piece = self.pieces[rewardName]
	local wipe = makeFrame(
		piece.crop,
		"RewardCollectionWipe",
		Vector2.new(piece.size.X, 0),
		Vector2.new(0, piece.size.Y),
		Theme.background,
		850
	)
	wipe.AnchorPoint = Vector2.new(1, 0)
	self.rewardWipe = wipe
	self.status.Text = "Долька собрана — плитка остаётся целой без обратной перемотки"

	local duration = self.trick.collectionDuration
	local token = self.animationToken
	local tween = TweenService:Create(
		wipe,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut),
		{ Size = UDim2.fromOffset(piece.size.X, piece.size.Y) }
	)
	table.insert(self.tweens, tween)
	tween:Play()
	task.delay(duration + 0.02, function()
		if self.animationToken ~= token or self.active ~= "collecting" then
			return
		end
		self.tweens = {}
		piece.motion.Visible = false
		self:setPieceOffset(rewardName, Vector2.zero)
		if self.rewardWipe then
			self.rewardWipe:Destroy()
			self.rewardWipe = nil
		end
		self:resetRound()
	end)
end

function Game:resetRound()
	self:cancelTweens()
	self.active = "cut"
	self.cutIndex = 1
	self.cutProgress = 0
	self.largeProgress = 0
	self.stripProgress = 0
	self.drag = nil
	for _, name in self.trick.pieceOrder do
		local piece = self.pieces[name]
		piece.motion.Visible = true
		if piece.extensionMotion then
			piece.extensionMotion.Visible = true
		end
		self:setPieceOffset(name, Vector2.zero)
	end
	self.intactLayer.Visible = true
	if self.rewardWipe then
		self.rewardWipe:Destroy()
		self.rewardWipe = nil
	end
	if self.rewardMarker then
		self.rewardMarker:Destroy()
		self.rewardMarker = nil
	end
	clear(self.seamLayer)
	clear(self.progressLayer)
	self:showCutHint()
end

return Game
