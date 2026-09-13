--!strict
-- Магазин живёт отдельным слоем: открытие не перестраивает шоколадку.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local Atelier = {}
Atelier.__index = Atelier

local function format(value)
	value = value or 0
	for _, unit in { { 1e12, " трлн" }, { 1e9, " млрд" }, { 1e6, " млн" }, { 1e3, " тыс." } } do
		if value >= unit[1] then return string.format("%.1f%s", value / unit[1], unit[2]) end
	end
	return if math.abs(value - math.floor(value)) < 0.01 then tostring(math.floor(value)) else (string.format("%.2f", value):gsub("0+$", ""):gsub("%.$", ""))
end

local function box(parent, name, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame
	return frame
end

local function text(parent, name, size, color)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = size
	label.TextColor3 = color or Theme.text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function button(parent, name, caption)
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = caption
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextScaled = true
	b.TextWrapped = true
	b.TextColor3 = Theme.background
	b.BackgroundColor3 = Theme.accent
	b.BorderSizePixel = 0
	b.Parent = parent
	local limit = Instance.new("UITextSizeConstraint")
	limit.MinTextSize = 11
	limit.MaxTextSize = 16
	limit.Parent = b
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = b
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = b
	return b
end

function Atelier.new(gui, gameView, remotes)
	local self = setmetatable({ view = gameView, remotes = remotes, cards = {}, confirmed = false }, Atelier)
	gameView.inputBlocked = true
	-- Системные кнопки Roblox могут оставаться видимыми на телефоне.
	-- Счётчик занимает оставшуюся ширину, включая длинные суммы поздней игры.
	gameView.counter.AnchorPoint = Vector2.zero
	gameView.counter.Position = UDim2.fromOffset(128, 12)
	gameView.counter.Size = UDim2.new(1, -144, 0, 48)
	gameView.counter.TextScaled = true
	local counterLimit = Instance.new("UITextSizeConstraint")
	counterLimit.MinTextSize = 12
	counterLimit.MaxTextSize = 25
	counterLimit.Parent = gameView.counter
	gameView.counter.Text = "ЗАГРУЗКА АТЕЛЬЕ…"
	self.metrics = text(gameView.root, "Production", 14, Theme.muted)
	self.metrics.Position = UDim2.new(0.04, 0, 0, 57)
	self.metrics.Size = UDim2.new(0.92, 0, 0, 26)
	self.metrics.TextXAlignment = Enum.TextXAlignment.Center
	self.metrics.ZIndex = 910
	self.metrics.Text = "Загружаем твой прогресс"
	self.open = button(gameView.root, "OpenAtelier", "АТЕЛЬЕ")
	self.open.AnchorPoint = Vector2.new(0.5, 0)
	self.open.Position = UDim2.new(0.5, 0, 0, 90)
	self.open.Size = UDim2.fromOffset(260, 38)
	self.open.ZIndex = 910

	self.overlay = Instance.new("Frame")
	self.overlay.Name = "AtelierOverlay"
	self.overlay.Size = UDim2.fromScale(1, 1)
	self.overlay.BackgroundColor3 = Theme.background
	self.overlay.BackgroundTransparency = 0.08
	self.overlay.BorderSizePixel = 0
	self.overlay.Active = true
	self.overlay.Visible = false
	self.overlay.ZIndex = 1000
	self.overlay.Parent = gui
	local panel = box(self.overlay, "Shop", Theme.panel)
	self.panel = panel
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(1, -24, 1, -32)
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize = Vector2.new(520, 690)
	bounds.Parent = panel
	self.panelBounds = bounds
	local title = text(panel, "Title", 23, Theme.accent)
	title.Text = "Шоколадное ателье"
	title.Position = UDim2.fromOffset(16, 12)
	title.Size = UDim2.new(1, -80, 0, 56)
	local close = button(panel, "Close", "×")
	close.Position = UDim2.new(1, -54, 0, 16)
	close.Size = UDim2.fromOffset(38, 38)
	self.close = close
	self.title = title
	self.balance = text(panel, "Balance", 15, Theme.text)
	self.balance.Position = UDim2.fromOffset(16, 70)
	self.balance.Size = UDim2.new(1, -32, 0, 36)
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "Upgrades"
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.Position = UDim2.fromOffset(12, 116)
	scroll.Size = UDim2.new(1, -24, 1, -158)
	scroll.CanvasSize = UDim2.fromOffset(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.accent
	scroll.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = scroll
	for index, spec in Config.Economy.upgrades do
		local card = box(scroll, spec.id, Theme.chocolate)
		card.Size = UDim2.new(1, -8, 0, 138)
		card.LayoutOrder = index
		local heading = text(card, "Name", 19, Theme.accentSoft)
		heading.Position = UDim2.fromOffset(12, 8)
		heading.Size = UDim2.new(1, -24, 0, 28)
		local description = text(card, "Effect", 14, Theme.muted)
		description.Position = UDim2.fromOffset(12, 40)
		description.Size = UDim2.new(1, -24, 0, 40)
		description.Text = spec.description
		local buy = button(card, "Buy", "Купить")
		buy.Position = UDim2.new(0, 12, 1, -48)
		buy.Size = UDim2.new(1, -24, 0, 36)
		buy.Activated:Connect(function()
			if self.state and self.state.ready and self.state.prices[spec.id]
				and self.state.slices >= self.state.prices[spec.id] then
				remotes.purchase:FireServer(spec.id)
			end
		end)
		self.cards[spec.id] = { heading = heading, buy = buy, spec = spec }
	end
	local prestige = box(scroll, "NextAtelier", Theme.chocolateDark)
	prestige.Size = UDim2.new(1, -8, 0, 242)
	prestige.LayoutOrder = 10
	local heading = text(prestige, "Title", 19, Theme.accent)
	heading.Text = "Новое ателье"
	heading.Position = UDim2.fromOffset(12, 8)
	heading.Size = UDim2.new(1, -24, 0, 28)
	self.prestigeInfo = text(prestige, "Progress", 14, Theme.muted)
	self.prestigeInfo.Position = UDim2.fromOffset(12, 40)
	self.prestigeInfo.Size = UDim2.new(1, -24, 0, 80)
	local track = box(prestige, "ProgressTrack", Theme.background)
	track.Position = UDim2.fromOffset(12, 126)
	track.Size = UDim2.new(1, -24, 0, 8)
	self.fill = box(track, "Fill", Theme.accent)
	self.fill.Size = UDim2.fromScale(0, 1)
	self.ascend = button(prestige, "Ascend", "Нужно 5 тыс. заработанных долек")
	self.ascend.Position = UDim2.new(0, 12, 1, -92)
	self.ascend.Size = UDim2.new(1, -24, 0, 40)
	self.cancel = button(prestige, "CancelReset", "Отмена")
	self.cancel.Position = UDim2.new(0, 12, 1, -44)
	self.cancel.Size = UDim2.new(1, -24, 0, 32)
	self.cancel.Visible = false
	self.cancel.Activated:Connect(function() self.confirmed = false; self:update(self.state) end)
	self.ascend.Activated:Connect(function()
		if not self.state or (self.state.prestigeGain or 0) < 1 then return end
		if self.confirmed then
			self.confirmed = false
			remotes.prestige:FireServer()
		else
			self.confirmed = true
			self:update(self.state)
		end
	end)
	self.saved = text(panel, "SaveStatus", 12, Theme.muted)
	self.saved.Position = UDim2.new(0, 16, 1, -34)
	self.saved.Size = UDim2.new(1, -32, 0, 24)
	self.open.Activated:Connect(function() self:setOpen(true) end)
	close.Activated:Connect(function() self:setOpen(false) end)
	UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and self.overlay.Visible then self:setOpen(false) end
	end)
	self.sidebar = box(gameView.root, "Sidebar", Theme.panel)
	self.sidebar.ZIndex = 900
	self.sidebar.Visible = false
	gameView.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:fit() end)
	self:fit()
	return self
end

function Atelier:fit()
	local size = self.view.root.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return end
	local mode = Layout.presentation(size.X, size.Y, Config.Board.viewportPadding)
	local changed = self.docked ~= mode.docked or self.landscape ~= mode.landscape
	self.docked, self.landscape = mode.docked, mode.landscape
	self.sidebar.Visible = mode.landscape
	local counter, status = self.view.counter, self.view.status
	if mode.landscape then
		local top = if size.Y < 500 then 60 else 80
		local height = size.Y - top - 16
		self.sidebar.Position = UDim2.fromOffset(12, top)
		self.sidebar.Size = UDim2.fromOffset(mode.left - 12, height)
		counter.Parent = self.sidebar
		counter.Position = UDim2.fromOffset(12, 12)
		counter.Size = UDim2.new(1, -24, 0, 48)
		self.metrics.Parent = self.sidebar
		self.metrics.Position = UDim2.fromOffset(12, 64)
		self.metrics.Size = UDim2.new(1, -24, 0, 54)
		status.Parent = self.sidebar
		status.AnchorPoint = Vector2.zero
		status.Position = UDim2.fromOffset(12, 126)
		status.Size = UDim2.new(1, -24, 0, math.max(40, height - (if mode.docked then 142 else 184)))
		status:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = if size.Y < 500 then 18 else 22
		self.open.Parent = self.sidebar
		self.open.AnchorPoint = Vector2.new(0, 1)
		self.open.Position = UDim2.new(0, 12, 1, -12)
		self.open.Size = UDim2.new(1, -24, 0, 36)
	else
		counter.Parent = self.view.root
		counter.Position = UDim2.fromOffset(128, 12)
		counter.Size = UDim2.new(1, -144, 0, 48)
		self.metrics.Parent = self.view.root
		self.metrics.Position = UDim2.new(0.04, 0, 0, 57)
		self.metrics.Size = UDim2.new(0.92, 0, 0, 26)
		status.Parent = self.view.root
		status.AnchorPoint = Vector2.new(0.5, 1)
		status.Position = UDim2.new(0.5, 0, 1, -12)
		status.Size = UDim2.new(0.94, 0, 0, Config.Board.viewportPadding.bottom - 24)
		status:FindFirstChildOfClass("UITextSizeConstraint").MaxTextSize = 28
		self.open.Parent = self.view.root
		self.open.AnchorPoint = Vector2.new(0.5, 0)
		self.open.Position = UDim2.new(0.5, 0, 0, 90)
		self.open.Size = UDim2.fromOffset(260, 38)
	end
	-- На широком экране тот же магазин закреплён справа. Он не становится
	-- модальным и не перехватывает жесты над шоколадкой в центре.
	self.open.Visible = not mode.docked
	self.close.Visible = not mode.docked
	self.overlay.Position = if mode.docked then UDim2.fromOffset(size.X - mode.right, 16) else UDim2.fromOffset(0, 0)
	self.overlay.Size = if mode.docked then UDim2.fromOffset(mode.right - 16, size.Y - 32) else UDim2.fromScale(1, 1)
	self.overlay.BackgroundTransparency = if mode.docked then 1 else 0.08
	self.panel.AnchorPoint = if mode.docked then Vector2.zero else Vector2.new(0.5, 0.5)
	self.panel.Position = if mode.docked then UDim2.fromScale(0, 0) else UDim2.fromScale(0.5, 0.5)
	self.panel.Size = if mode.docked then UDim2.fromScale(1, 1) else UDim2.new(1, -24, 1, -32)
	self.panelBounds.MaxSize = if mode.docked then Vector2.new(10000, 10000) else Vector2.new(520, 690)
	self.title.Size = UDim2.new(1, if mode.docked then -32 else -80, 0, 56)
	if changed then self.confirmed = false; self.overlay.Visible = mode.docked end
	self.view.inputBlocked = (self.overlay.Visible and not self.docked) or not (self.state and self.state.ready)
	if self.state then self:update(self.state) end
end

function Atelier:setOpen(open)
	if self.docked then return end
	self.view:endDrag(true)
	self.overlay.Visible = open
	self.confirmed = false
	self.view.inputBlocked = open or not (self.state and self.state.ready)
	if self.state then self:update(self.state) end
end

function Atelier:update(state)
	if not state then return end
	self.state = state
	if not state.ready then return end
	self.view.inputBlocked = self.overlay.Visible and not self.docked
	self.view.counter.Text = `ДОЛЬКИ  {format(state.slices)}`
	if state.notice then
		self.notice = state.notice
		self.noticeUntil = os.clock() + 3
	end
	self.metrics.Text = if self.noticeUntil and self.noticeUntil > os.clock() then self.notice
		else `+{format(state.manual)} за фокус  ·  {format(state.rate)}/с  ·  ★ {format(state.stars)}`
	self.balance.Text = `{format(state.slices)} долек  ·  {format(state.rate)} в секунду`
	self.saved.Text = state.saveStatus or ""
	local affordable = 0
	for id, card in self.cards do
		local level = state.levels[id]
		card.heading.Text = `{card.spec.name} · {level}`
		local price = state.prices[id]
		local canBuy = price and state.slices >= price
		if canBuy then affordable += 1 end
		card.buy.BackgroundColor3 = if canBuy then Theme.accent else Theme.chocolateEdge
		card.buy.TextColor3 = if canBuy then Theme.background else Theme.text
		card.buy.AutoButtonColor = canBuy == true
		card.buy.Text = if not price then "Максимальный уровень" elseif canBuy then `Купить · {format(price)} долек`
			else `Цена {format(price)} · не хватает {format(price - state.slices)}`
	end
	self.open.Text = if affordable > 0 then `АТЕЛЬЕ · доступно {affordable}` else "АТЕЛЬЕ · улучшения"
	local gain = state.prestigeGain
	if gain < 1 then self.confirmed = false end
	self.prestigeInfo.Text = if self.confirmed then
		`Сбросить дольки и все улучшения? Звёзды сохранятся. Получишь ещё {gain}; каждая навсегда даёт +25% к доходу.`
		else `Заработано в этом ателье: {format(state.earned)}. Первая звезда за 5 тыс., две — за 20 тыс. Каждая даёт +25% навсегда. Дольки и улучшения сбросятся.`
	self.fill.Size = UDim2.fromScale(math.clamp(state.earned / Config.Economy.prestigeTarget, 0, 1), 1)
	self.ascend.Text = if self.confirmed then `Подтвердить сброс · +{gain} ★` elseif gain > 0 then `Открыть новое ателье · +{gain} ★` else "Цель · 5 тыс. заработанных долек"
	self.ascend.BackgroundColor3 = if gain > 0 then Theme.accent else Theme.chocolateEdge
	self.cancel.Visible = self.confirmed
	if not self.welcomed then
		self.welcomed = true
		if (state.offline or 0) >= 0.1 then
			self.notice = `Пока тебя не было: +{format(state.offline)} долек`
			self.noticeUntil = os.clock() + 8
			self.metrics.Text = self.notice
		end
	end
end

return Atelier
