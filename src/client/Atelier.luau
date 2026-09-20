--!strict
-- Магазин живёт отдельным слоем: открытие не перестраивает шоколадку.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Config = require(ReplicatedStorage:WaitForChild("Shared").Config)
local Catalog = require(ReplicatedStorage:WaitForChild("Shared").KitchenCatalog)
local L = require(script.Parent.Localization)
local Theme = require(script.Parent.Theme)
local Layout = require(script.Parent.Layout)
local Thumbnails = require(script.Parent.DecorThumbnails)
local Atelier = {}
Atelier.__index = Atelier

local function format(value)
	return L.number(value or 0)
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
	L.set(b, caption)
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
	L.set(gameView.counter, "LOADING CHOCOLATE…")
	self.metrics = text(gameView.root, "Production", 14, Theme.muted)
	self.metrics.Position = UDim2.new(0.04, 0, 0, 57)
	self.metrics.Size = UDim2.new(0.92, 0, 0, 26)
	self.metrics.TextXAlignment = Enum.TextXAlignment.Center
	self.metrics.ZIndex = 910
	L.set(self.metrics, "Loading your progress")
	self.open = button(gameView.root, "OpenAtelier", "WORKSHOP")
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
	L.set(title, "Upgrades")
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
	local specs={}
	for _,spec in Config.Economy.upgrades do if spec.id=="kitchen" or spec.maxLevel==math.huge then table.insert(specs,spec) end end
	for _,spec in Catalog.items do table.insert(specs,spec) end
	self.scroll=scroll
	self.placeMap=Instance.new('ScrollingFrame')
	self.placeMap.Name='ChoosePlace'; self.placeMap.BackgroundColor3=Theme.chocolateDark; self.placeMap.BorderSizePixel=0
	self.placeMap.CanvasSize=UDim2.fromOffset(0,420); self.placeMap.ScrollBarThickness=4; self.placeMap.Parent=panel
	self.placeMap.Position=UDim2.fromOffset(12,116)
	self.placeMap.Size=UDim2.new(1,-24,1,-158)
	self.placeMap.Visible=false
	local hint=text(self.placeMap,"Hint",17,Theme.accentSoft)
	L.set(hint,"Choose a spot in your kitchen")
	hint.Position=UDim2.fromOffset(12,4); hint.Size=UDim2.new(1,-24,0,44)
	local floor=box(self.placeMap,"KitchenPlan",Color3.fromRGB(181,160,130))
	floor.Position=UDim2.new(.05,0,0,54); floor.Size=UDim2.new(.9,0,0,350)
	self.placeMap:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
	 local height=math.max(240,self.placeMap.AbsoluteSize.Y-68)
	 floor.Size=UDim2.new(.9,0,0,height); self.placeMap.CanvasSize=UDim2.fromOffset(0,height+68)
	end)
	local wall=box(floor,"BackWall",Color3.fromRGB(83,112,97)); wall.Size=UDim2.new(1,0,.25,0)
	for _,x in {0,.97} do
	 local side=box(floor,"SideWall",Color3.fromRGB(83,112,97)); side.Position=UDim2.fromScale(x,0); side.Size=UDim2.fromScale(.03,1)
	end
	for _,x in {.14,.55} do
	 local tableTop=box(floor,"Worktable",Color3.fromRGB(207,161,101)); tableTop.Position=UDim2.fromScale(x,.36); tableTop.Size=UDim2.fromScale(.31,.23)
	end
	self.placeButtons={}
	local spots={{'temper',.17,.27},{'library',.25,.08},{'clock',.77,.08},{'workers',.71,.46},{'art',.1,.67},{'rug',.5,.81},{'plant',.89,.81}}
	for _,spot in spots do
	 local spec
	 for _,item in Catalog.items do if item.group==spot[1] then spec=item; break end end
	 local choice=button(floor,spot[1],"")
	 choice.AnchorPoint=Vector2.new(.5,.5); choice.Position=UDim2.fromScale(spot[2],spot[3]); choice.Size=UDim2.fromOffset(52,52)
	 Thumbnails.new(choice,if spot[1]=="library" then Catalog.byId.library_5 else spec)
	 self.placeButtons[spot[1]]=choice
	 choice.Activated:Connect(function()
	  self.selectedPlace=spot[1]; self.scroll.CanvasPosition=Vector2.zero; self:update(self.state)
	 end)
	end
	self.placesBack=button(panel,"ChooseAnotherSpot","‹ Choose another spot")
	self.placesBack.Position=UDim2.fromOffset(12,112); self.placesBack.Size=UDim2.new(1,-24,0,38); self.placesBack.Visible=false
	self.placesBack.Activated:Connect(function() self.selectedPlace=nil; self:update(self.state) end)
	for index, spec in specs do
		local card = box(scroll, spec.id, Theme.chocolate)
		card.Size = UDim2.new(1, -8, 0, 138)
		card.LayoutOrder = index
		card.Visible = spec.id ~= "speed"
		local heading = text(card, "Name", 19, Theme.accentSoft)
		heading.Position = UDim2.fromOffset(12, 8)
		heading.Size = UDim2.new(1, -24, 0, 28)
		local description = text(card, "Effect", 14, Theme.muted)
		description.Position = UDim2.fromOffset(12, 40)
		description.Size = UDim2.new(1, -24, 0, 40)
		L.set(description, spec.description)
		if spec.group then
		 local visual=Instance.new('Frame'); visual.Name='Visual'; visual.BackgroundTransparency=1; visual.Position=UDim2.fromOffset(6,8); visual.Size=UDim2.fromOffset(96,80); visual.Parent=card
		 Thumbnails.new(visual,spec)
		 heading.Position=UDim2.fromOffset(108,8); heading.Size=UDim2.new(1,-120,0,32); heading.TextSize=17
		 description.Position=UDim2.fromOffset(108,42); description.Size=UDim2.new(1,-120,0,42); description.TextSize=12
		end
		local buy = button(card, "Buy", "Buy")
		buy.Position = UDim2.new(0, 12, 1, -48)
		buy.Size = UDim2.new(1, -24, 0, 36)
		local function activate()
            if spec.group and self.onPreview and self.state and self.state.ready then self.returningFromPreview=true; self.onPreview(spec.id); return end
			if self.state and self.state.ready and ((spec.cosmetic and self.state.levels[spec.id] > 0) or (self.state.prices[spec.id]
				and self.state.slices >= self.state.prices[spec.id])) then
				remotes.purchase:FireServer(spec.id)
			end
		end
		buy.Activated:Connect(activate)
		if spec.group then
		 local imageButton=button(card.Visual,"PreviewItem",""); imageButton.BackgroundTransparency=1; imageButton.Size=UDim2.fromScale(1,1)
		 imageButton.Activated:Connect(activate)
		end
		self.cards[spec.id] = { frame = card, heading = heading, description = description, buy = buy, spec = spec }
	end
	local prestige = box(scroll, "NextAtelier", Theme.chocolateDark)
	self.prestigeCard=prestige
	prestige.Size = UDim2.new(1, -8, 0, 242)
	prestige.LayoutOrder = 100
	local heading = text(prestige, "Title", 19, Theme.accent)
	L.set(heading, "New Workshop")
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
	self.ascend = button(prestige, "Ascend", "Earn 5K pieces to start a new workshop")
	self.ascend.Position = UDim2.new(0, 12, 1, -92)
	self.ascend.Size = UDim2.new(1, -24, 0, 40)
	self.cancel = button(prestige, "CancelReset", "Cancel")
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
	self.balanceTest=box(scroll,"BalanceTest",Theme.chocolateDark)
	self.balanceTest.Size=UDim2.new(1,-8,0,112)
	self.balanceTest.LayoutOrder=101
	self.balanceTest.Visible=false
	local testInfo=text(self.balanceTest,"Info",14,Theme.muted)
	testInfo.Position=UDim2.fromOffset(12,8); testInfo.Size=UDim2.new(1,-24,0,44)
	L.set(testInfo,"Admin · session only. Stored stars are kept.")
	self.togglePrestige=button(self.balanceTest,"TogglePrestige","Disable prestige bonus")
	self.togglePrestige.Position=UDim2.fromOffset(12,60); self.togglePrestige.Size=UDim2.new(1,-24,0,40)
	self.togglePrestige.Activated:Connect(function() remotes.purchase:FireServer("admin_toggle_prestige") end)
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
	if self.external then mode.docked = false end
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

function Atelier:setMode(mode)
    self.scrollPositions=self.scrollPositions or {}
    self.scrollPositions[self.mode or 'upgrades']=self.scroll.CanvasPosition
    self.mode=mode
    if mode=='kitchen' and not self.returningFromPreview then self.selectedPlace=nil end
    if mode=='kitchen' then self.returningFromPreview=false end
    L.set(self.title,if mode=='kitchen' then 'My Kitchen' else 'Upgrades')
    self.prestigeCard.Visible=mode~='kitchen'
    self.scroll.CanvasPosition=self.scrollPositions[mode] or Vector2.zero
    if self.state then self:update(self.state) end
end

function Atelier:setOpen(open)
	if self.docked then return end
	self.view:endDrag(true)
	self.overlay.Visible = open
	self.confirmed = false
	self.view.inputBlocked = open or not (self.state and self.state.ready)
	if self.state then self:update(self.state) end
	if not open and self.onClose then self.onClose() end
end

function Atelier:update(state)
	if not state then return end
	self.state = state
	if not state.ready then return end
	local kitchen=self.mode=='kitchen'
	self.placeMap.Visible=kitchen and self.selectedPlace==nil
	self.placesBack.Visible=kitchen and self.selectedPlace~=nil
	self.scroll.Visible=not kitchen or self.selectedPlace~=nil
	self.scroll.Position=UDim2.fromOffset(12,if kitchen then 160 else 116)
	self.scroll.Size=UDim2.new(1,-24,1,if kitchen then -202 else -158)
	self.balanceTest.Visible=state.canTestBalance==true and self.mode~='kitchen'
	L.set(self.togglePrestige,if state.prestigeDisabled then "Prestige bonus OFF · enable" else "Disable prestige bonus")
	self.view.inputBlocked = self.overlay.Visible and not self.docked
	L.set(self.view.counter, "PIECES  {amount}", {amount=format(state.slices)})
	if state.notice then
		self.notice = state.notice
		self.noticeUntil = os.clock() + 3
	end
	if self.noticeUntil and self.noticeUntil > os.clock() then
		L.set(self.metrics,self.notice.key,self.notice.args)
	else
		L.set(self.metrics,"+{manual} per trick  ·  {rate}/s  ·  ★ {stars}",{manual=format(state.manual),rate=format(state.rate),stars=format(state.stars)})
	end
	L.set(self.balance, "Pieces: {amount}  ·  {rate} per second", {amount=format(state.slices),rate=format(state.rate)})
	L.set(self.saved,state.saveStatus or "")
    if self.mode=='kitchen' and not state.owned.workers_1 then
        L.set(self.balance,'3/3 · Choose the apprentice spot, then hire for free.')
    end
	local affordable = 0
	for id, card in self.cards do
        local catalog=card.spec.group~=nil
        card.frame.Visible=if self.mode=='kitchen' then catalog and card.spec.group==self.selectedPlace else not catalog and ((id~='speed' and id~='cafes') or state.owned.workers_1) and (id~='kitchen' or state.levels.kitchen==0)
        local level=state.levels[id] or 0
        if id=='speed' then
            L.set(card.description,"+20% apprentice speed · current cycle: {seconds}s",{seconds=format(state.cycleSeconds)})
        elseif card.spec.group=='workers' then
            L.set(card.description,"One apprentice · +{reward} per {seconds}s cycle",{reward=format(state.cycleReward),seconds=format(state.cycleSeconds)})
        end
        if catalog or id=='kitchen' then L.set(card.heading,card.spec.name)
        else L.set(card.heading,"{upgrade} · {level}",{upgrade=L.token(card.spec.name),level=level}) end
        local price=state.prices[id]
        local canBuy=price~=nil and state.slices>=price
        if canBuy and card.frame.Visible then affordable+=1 end
        card.buy.BackgroundColor3=if canBuy or catalog then Theme.accent else Theme.chocolateEdge
        card.buy.TextColor3=if canBuy or catalog then Theme.background else Theme.text
        card.buy.AutoButtonColor=canBuy or catalog
        if catalog then
            if state.owned[id] then L.set(card.buy,'View · owned')
            elseif price==0 then L.set(card.buy,'Preview · free apprentice')
            else L.set(card.buy,'Preview · {price} pieces',{price=format(price)}) end
        elseif not price then L.set(card.buy,'Maximum level')
        elseif canBuy then L.set(card.buy,'Buy · {price} pieces',{price=format(price)})
        else L.set(card.buy,'Price {price} · need {missing} more',{price=format(price),missing=format(price-state.slices)}) end
	end
	if affordable>0 then L.set(self.open,"WORKSHOP · {count} available",{count=affordable}) else L.set(self.open,"WORKSHOP · upgrades") end
	local gain = state.prestigeGain
	if gain < 1 then self.confirmed = false end
	if self.confirmed then L.set(self.prestigeInfo,"Reset pieces, all upgrades, apprentices and furniture? Only stars and lifetime stats stay. Gain {stars} stars (+25% income each).",{stars=gain})
	else L.set(self.prestigeInfo,"Earned: {earned}. Stars: 5K for one, 20K for two (+25% income each). Resets pieces, all upgrades, apprentices and furniture.",{earned=format(state.earned)}) end
	self.fill.Size = UDim2.fromScale(math.clamp(state.earned / Config.Economy.prestigeTarget, 0, 1), 1)
	if self.confirmed then L.set(self.ascend,"Confirm reset · +{stars} ★",{stars=gain})
	elseif gain>0 then L.set(self.ascend,"Open a new workshop · +{stars} ★",{stars=gain})
	else L.set(self.ascend,"Goal · earn 5K pieces") end
	self.ascend.BackgroundColor3 = if gain > 0 then Theme.accent else Theme.chocolateEdge
	self.cancel.Visible = self.confirmed
	if not self.welcomed then
		self.welcomed = true
		if (state.offline or 0) >= 0.1 then
			self.notice = {key="While you were away: +{amount}",args={amount=format(state.offline)}}
			self.noticeUntil = os.clock() + 8
			L.set(self.metrics,self.notice.key,self.notice.args)
		end
	end
end

return Atelier
