--!nonstrict
-- Заказ остаётся ненавязчивой частью HUD. Журнал открывается по желанию,
-- не останавливает производство и не меняет сохранённый прогресс разреза.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Orders = require(Shared.Orders)
local Theme = require(script.Parent.Theme)
local L = require(script.Parent.Localization)
local Journal = {}; Journal.__index = Journal

local function round(object, radius)
	local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,radius or 10); c.Parent=object
end
local function frame(parent,name,color)
	local f=Instance.new("Frame"); f.Name=name; f.BackgroundColor3=color; f.BorderSizePixel=0; f.Parent=parent; round(f); return f
end
local function label(parent,name,size,color)
	local t=Instance.new("TextLabel"); t.Name=name; t.BackgroundTransparency=1
	t.Font=Enum.Font.GothamMedium; t.TextSize=size; t.TextColor3=color or Theme.text
	t.TextWrapped=true; t.TextXAlignment=Enum.TextXAlignment.Left; t.Parent=parent; return t
end
local function scaled(t,maxSize)
	t.TextScaled=true; local limit=Instance.new("UITextSizeConstraint")
	limit.MinTextSize=10; limit.MaxTextSize=maxSize; limit.Parent=t
end
local function fill(parent,name,y)
	local track=frame(parent,name,Theme.background); track.Position=UDim2.new(0,12,0,y); track.Size=UDim2.new(1,-24,0,5)
	local bar=frame(track,"Fill",Theme.accent); bar.Size=UDim2.fromScale(0,1); return bar
end

function Journal.new(gui,view)
	local self=setmetatable({view=view,stats={}},Journal)
	local chip=Instance.new("TextButton"); chip.Name="OrderCard"; chip.Text=""
	chip.BackgroundColor3=Theme.chocolateDark; chip.BorderSizePixel=0; chip.ZIndex=910
	chip.Parent=view.root; round(chip); self.chip=chip; chip.Visible=false
	local icon=frame(chip,"ChocolateBox",Theme.chocolateRaised)
	icon.Size=UDim2.fromOffset(28,28); icon.Position=UDim2.fromOffset(12,12)
	local ribbon=frame(icon,"Ribbon",Theme.accent); ribbon.Position=UDim2.fromOffset(11,0); ribbon.Size=UDim2.fromOffset(6,28)
	local cross=frame(icon,"Cross",Theme.accent); cross.Position=UDim2.fromOffset(0,11); cross.Size=UDim2.fromOffset(28,6)
	self.icon=icon
	self.chipTitle=label(chip,"Title",14,Theme.accentSoft); scaled(self.chipTitle,14)
	self.chipInfo=label(chip,"Progress",12,Theme.muted); scaled(self.chipInfo,12)
	self.chipFill=fill(chip,"ProgressTrack",68)
	local journalGui=Instance.new("ScreenGui"); journalGui.Name="ChocolateJournal"; journalGui.ResetOnSpawn=false
	-- Дневник начинается ниже системной панели: её кнопки всегда рисуются
	-- поверх игры и прежде закрывали заголовок на телефоне.
	journalGui.IgnoreGuiInset=false; journalGui.DisplayOrder=30; journalGui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; journalGui.Parent=gui.Parent
	local overlay=frame(journalGui,"JournalOverlay",Theme.background)
	overlay.Size=UDim2.fromScale(1,1); overlay.BackgroundTransparency=.12
	overlay.ZIndex=1100; overlay.Active=true; overlay.Visible=false; self.overlay=overlay
	local panel=frame(overlay,"Journal",Theme.panel); self.panel=panel
	panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5)
	panel.Size=UDim2.new(1,-24,1,-32)
	local bounds=Instance.new("UISizeConstraint"); bounds.MaxSize=Vector2.new(520,670); bounds.Parent=panel
	local title=label(panel,"Title",24,Theme.accent); title.Position=UDim2.fromOffset(16,12); title.Size=UDim2.new(1,-86,0,46)
	scaled(title,24); L.set(title,"Chocolate journal")
	local close=Instance.new("TextButton"); close.Name="Close"; close.Text="×"; close.TextSize=24
	close.Font=Enum.Font.GothamBold; close.TextColor3=Theme.background; close.BackgroundColor3=Theme.accent; close.BorderSizePixel=0
	close.Position=UDim2.new(1,-54,0,16); close.Size=UDim2.fromOffset(38,38); close.Parent=panel; round(close)
	local scroll=Instance.new("ScrollingFrame"); scroll.Name="Pages"; scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
	scroll.Position=UDim2.fromOffset(12,110); scroll.Size=UDim2.new(1,-24,1,-124)
	scroll.ScrollBarThickness=4; scroll.ScrollBarImageColor3=Theme.accent
	scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.Parent=panel
	local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Padding=UDim.new(0,12); layout.Parent=scroll
 self.pages=scroll
 local calculations=Instance.new('ScrollingFrame'); calculations.Name='Calculations'
 calculations.BackgroundTransparency=1; calculations.BorderSizePixel=0
 calculations.Position=scroll.Position; calculations.Size=scroll.Size
 calculations.ScrollBarThickness=4; calculations.ScrollBarImageColor3=Theme.accent
 calculations.AutomaticCanvasSize=Enum.AutomaticSize.Y; calculations.CanvasSize=UDim2.fromOffset(0,0)
 calculations.Visible=false; calculations.Parent=panel; self.calculations=calculations
 local calcLayout=Instance.new('UIListLayout'); calcLayout.SortOrder=Enum.SortOrder.LayoutOrder
 calcLayout.Padding=UDim.new(0,10); calcLayout.Parent=calculations
 self.tabs={}; self.bonusRows={}
 for i,spec in {{'journal','Orders and progress'},{'bonuses','Bonuses and calculations'}} do
  local tab=Instance.new('TextButton'); tab.Name=spec[1]; tab.TextSize=14; tab.Font=Enum.Font.GothamMedium
  tab.TextColor3=Theme.accentSoft; tab.BackgroundColor3=Theme.chocolate; tab.BorderSizePixel=0
  tab.Position=UDim2.new((i-1)*.5,12-(i-1)*6,0,66); tab.Size=UDim2.new(.5,-18,0,34)
  tab.Parent=panel; round(tab); scaled(tab,14); L.set(tab,spec[2]); self.tabs[spec[1]]=tab
  tab.Activated:Connect(function() self:selectPage(spec[1]) end)
 end
 for i,key in {'base','recipe','stars','temper','online','guests','spectators','total','manual','workers','speed','cycle','income','orders','rules'} do
  local card=frame(calculations,key,Theme.chocolateDark); card.LayoutOrder=i
  -- Высота следует переносу текста: русский и большие множители не обрезаются на телефоне.
  card.Size=UDim2.new(1,-8,0,0); card.AutomaticSize=Enum.AutomaticSize.Y
  local padding=Instance.new('UIPadding'); padding.PaddingTop=UDim.new(0,12); padding.PaddingBottom=UDim.new(0,12)
  padding.PaddingLeft=UDim.new(0,12); padding.PaddingRight=UDim.new(0,12); padding.Parent=card
  local stack=Instance.new('UIListLayout'); stack.SortOrder=Enum.SortOrder.LayoutOrder; stack.Padding=UDim.new(0,8); stack.Parent=card
  local t=label(card,'Formula',16,Theme.accentSoft); t.Size=UDim2.new(1,0,0,0); t.AutomaticSize=Enum.AutomaticSize.Y; t.LayoutOrder=1
  local help=label(card,'Explanation',13,Theme.muted); help.Size=UDim2.new(1,0,0,0); help.AutomaticSize=Enum.AutomaticSize.Y; help.LayoutOrder=2
  self.bonusRows[key]={value=t,help=help}
 end
 self:selectPage('journal')
	local away=frame(scroll,"OfflineEarnings",Theme.chocolateDark); away.LayoutOrder=0; away.Size=UDim2.new(1,-8,0,150); away.Visible=false; self.offlineCard=away
	local awayTitle=label(away,"Title",18,Theme.accentSoft); awayTitle.Position=UDim2.fromOffset(12,8); awayTitle.Size=UDim2.new(1,-24,0,28)
	L.set(awayTitle,"While you were away")
	self.offlineAmount=label(away,"Amount",22,Theme.accent); self.offlineAmount.Position=UDim2.fromOffset(12,40); self.offlineAmount.Size=UDim2.new(1,-24,0,30); scaled(self.offlineAmount,22)
	self.offlineTime=label(away,"Time",13,Theme.muted); self.offlineTime.Position=UDim2.fromOffset(12,76); self.offlineTime.Size=UDim2.new(1,-24,0,24)
	self.offlineHelp=label(away,"Help",12,Theme.muted); self.offlineHelp.Position=UDim2.fromOffset(12,106); self.offlineHelp.Size=UDim2.new(1,-24,0,34)
	local order=frame(scroll,"CurrentOrder",Theme.chocolate); order.LayoutOrder=1; order.Size=UDim2.new(1,-8,0,176)
	self.orderTitle=label(order,"Title",20,Theme.accentSoft); self.orderTitle.Position=UDim2.fromOffset(12,8); self.orderTitle.Size=UDim2.new(1,-24,0,34)
	scaled(self.orderTitle,20)
	self.orderProgress=label(order,"Progress",15); self.orderProgress.Position=UDim2.fromOffset(12,47); self.orderProgress.Size=UDim2.new(1,-24,0,24)
	self.orderBonus=label(order,"Bonus",16,Theme.accent); self.orderBonus.Position=UDim2.fromOffset(12,77); self.orderBonus.Size=UDim2.new(1,-24,0,28)
	self.orderFill=fill(order,"ProgressTrack",114)
	local help=label(order,"Help",12,Theme.muted); help.Position=UDim2.fromOffset(12,126); help.Size=UDim2.new(1,-24,0,40)
	L.set(help,"Take your time. Only tricks you finish by hand fill orders.")
	local receipt=frame(scroll,"LastOrder",Theme.chocolateDark); receipt.LayoutOrder=2; receipt.Size=UDim2.new(1,-8,0,150); receipt.Visible=false; self.receiptCard=receipt
	local receiptTitle=label(receipt,"Title",14,Theme.muted); receiptTitle.Position=UDim2.fromOffset(12,8); receiptTitle.Size=UDim2.new(1,-24,0,26); scaled(receiptTitle,14); L.set(receiptTitle,"Last packed order")
	self.receiptName=label(receipt,"Order",19,Theme.accentSoft); self.receiptName.Position=UDim2.fromOffset(12,37); self.receiptName.Size=UDim2.new(1,-24,0,30); scaled(self.receiptName,19)
	self.receiptBonus=label(receipt,"Bonus",18,Theme.accent); self.receiptBonus.Position=UDim2.fromOffset(12,71); self.receiptBonus.Size=UDim2.new(1,-24,0,28); scaled(self.receiptBonus,18)
	local receiptHelp=label(receipt,"Help",12,Theme.muted); receiptHelp.Position=UDim2.fromOffset(12,105); receiptHelp.Size=UDim2.new(1,-24,0,36); scaled(receiptHelp,12); L.set(receiptHelp,"Bonus already added. This receipt stays until you leave.")
	local rank=frame(scroll,"Rank",Theme.chocolateDark); rank.LayoutOrder=3; rank.Size=UDim2.new(1,-8,0,106)
	self.rankTitle=label(rank,"Title",20,Theme.accentSoft); self.rankTitle.Position=UDim2.fromOffset(12,8); self.rankTitle.Size=UDim2.new(1,-24,0,32); scaled(self.rankTitle,20)
	self.rankInfo=label(rank,"Next",13,Theme.muted); self.rankInfo.Position=UDim2.fromOffset(12,43); self.rankInfo.Size=UDim2.new(1,-24,0,38)
	self.rankFill=fill(rank,"ProgressTrack",88)
	local production=frame(scroll,"Production",Theme.chocolate); production.LayoutOrder=4; production.Size=UDim2.new(1,-8,0,194)
	self.productionCard=production
	local productionTitle=label(production,"Title",20,Theme.accentSoft); productionTitle.Position=UDim2.fromOffset(12,8); productionTitle.Size=UDim2.new(1,-24,0,30); scaled(productionTitle,20); L.set(productionTitle,"My factory")
	self.productionCount=label(production,"Count",14,Theme.muted); self.productionCount.Position=UDim2.fromOffset(12,40); self.productionCount.Size=UDim2.new(1,-24,0,28); scaled(self.productionCount,14)
	self.productionRate=label(production,"Rate",20,Theme.accent); self.productionRate.Position=UDim2.fromOffset(12,72); self.productionRate.Size=UDim2.new(1,-24,0,30); scaled(self.productionRate,20)
	self.productionCycle=label(production,"Cycle",14); self.productionCycle.Position=UDim2.fromOffset(12,106); self.productionCycle.Size=UDim2.new(1,-24,0,38); scaled(self.productionCycle,14)
	self.productionHelp=label(production,"Help",12,Theme.muted); self.productionHelp.Position=UDim2.fromOffset(12,148); self.productionHelp.Size=UDim2.new(1,-24,0,36); scaled(self.productionHelp,12)
	for index,spec in {{"rounds","Tricks by hand"},{"ordersCompleted","Orders packed"},{"lifetime","Lifetime pieces"},{"stars","Cocoa stars"}} do
		local card=frame(scroll,spec[1],Theme.chocolateDark); card.LayoutOrder=index+4; card.Size=UDim2.new(1,-8,0,58)
		local name=label(card,"Label",14,Theme.muted); name.Position=UDim2.fromOffset(12,6); name.Size=UDim2.new(.64,-12,1,-12); L.set(name,spec[2])
		local amount=label(card,"Value",22,Theme.accentSoft); amount.Position=UDim2.new(.64,0,0,6); amount.Size=UDim2.new(.36,-12,1,-12)
		amount.TextXAlignment=Enum.TextXAlignment.Right; scaled(amount,22); self.stats[spec[1]]=amount
	end
	chip.Activated:Connect(function() self:open() end)
	close.Activated:Connect(function() self:close() end)
	local escapeConnection=game:GetService("UserInputService").InputBegan:Connect(function(input)
		if input.KeyCode==Enum.KeyCode.Escape and overlay.Visible then self:close() end
	end)
	-- Журнал — соседний ScreenGui; удаление основного GUI само его не убирает.
	local ownerCleanup=gui.Destroying:Connect(function() journalGui:Destroy() end)
	journalGui.Destroying:Connect(function()
		escapeConnection:Disconnect(); ownerCleanup:Disconnect()
		view.journalOpen=false
	end)
	return self
end

function Journal:open()
	if not self.state or not self.state.ready or self.view.journalOpen or self.view.diagnosticsOpen then return end
	if self.canOpen and not self.canOpen() then return end
	self.view:endDrag(true); self.view.journalOpen=true; self.overlay.Visible=true
	if self.onToggle then self.onToggle(true) end
end

function Journal:close()
	local wasOpen=self.view.journalOpen
	self.overlay.Visible=false; self.view.journalOpen=false
	if wasOpen and self.onToggle then self.onToggle(false) end
end

function Journal:fit(parent,compact,position,size)
	self.compact=compact; self.chip.Parent=parent; self.chip.Position=position; self.chip.Size=size
	self.icon.Visible=not compact
	self.chipTitle.Position=UDim2.fromOffset(if compact then 10 else 48,if compact then 3 else 8)
	self.chipTitle.Size=UDim2.new(1,if compact then -20 else -60,0,if compact then 16 else 32)
	self.chipInfo.Position=UDim2.fromOffset(10,if compact then 17 else 42)
	self.chipInfo.Size=UDim2.new(1,-20,0,if compact then 16 else 20)
	self.chipFill.Parent.Position=UDim2.new(0,10,1,if compact then -4 else -8)
	self.chipFill.Parent.Size=UDim2.new(1,-20,0,if compact then 2 else 4)
	if self.state then self:update(self.state) end
end

function Journal:selectPage(page)
 self.pages.Visible=page=='journal'; self.calculations.Visible=page=='bonuses'
 for key,tab in self.tabs do tab.BackgroundColor3=if key==page then Theme.chocolateRaised else Theme.chocolate end
end

function Journal:updateBonuses(state)
 local b=state.bonuses
 if not self.bonusRows then return end
 self.tabs.bonuses.Visible=state.ready==true and b~=nil
 if not b then return end
 local function n(value)
  -- Очень быстрый цикл нельзя округлять до нуля, огромный множитель — обрезать.
  if (value>0 and value<.01) or value>=1e15 then return string.format('%.3g',value) end
  return L.number(value)
 end
 local function row(key,formula,args,help,helpArgs)
  L.set(self.bonusRows[key].value,formula,args); L.set(self.bonusRows[key].help,help,helpArgs)
 end
 row('base','Base: {base} + {craft} + {library} = {reward}',{base=n(b.base),craft=n(b.craft),library=n(b.library),reward=n(b.baseReward)},
  'Base piece + craftsmanship + owned recipe books. Hidden furniture keeps its bonus.')
 row('recipe','Recipe income: ×{factor}',{factor=n(b.recipe)},'Recipe upgrades multiply manual and apprentice rewards.')
 row('stars','{stars} cocoa stars: ×{factor}',{stars=n(b.stars),factor=n(b.star)},
  if b.starsEnabled then 'Each star adds {percent}% in this layer.' else 'Star income is temporarily disabled for this test session.',{percent=n(b.starPercent)})
 row('temper','Owned tempering machines: ×{factor}',{factor=n(b.temper)},'Every owned machine contributes, including hidden models.')
 row('online','Friends on this server: ×{factor}',{factor=n(b.online)},if b.friendStatus=='ready' then 'At least one online friend doubles income. No visit needed; more friends do not stack.'
  else 'Friend list is loading or retrying. Only confirmed friendships count for now.')
 row('guests','{count} unique guests: ×{factor}',{count=n(b.guestCount),factor=n(b.guests)},'Lifetime cafe guests: 1 + {count} × {percent}%. Repeat visits do not count.',{count=n(b.guestCount),percent=n(b.guestPercent)})
 row('spectators','{count} unique friend spectators: ×{factor}',{count=n(b.spectatorCount),factor=n(b.spectators)},
  '1 + {count} × {percent}%. A friend must watch at your manual table from the first cut through both moves. Joining late does not count.',{count=n(b.spectatorCount),percent=n(b.spectatorPercent)})
 row('total','Total income multiplier: ×{factor}',{factor=n(b.multiplier)},
  'Recipe × stars × machines × online friend × guests × spectators. The same friend can contribute to all three social layers.')
 row('manual','Manual trick: {base} × {factor} = +{reward}',{base=n(b.baseReward),factor=n(b.multiplier),reward=n(b.manual)},
  'Server reward, capped at {cap}. A new spectator bonus starts with the next trick.',{cap=n(b.maxValue)})
 row('workers','Apprentices: {count} · +{reward} each cycle',{count=n(b.workers),reward=n(b.manual)},'Each new cafe adds two apprentices. Your home has the first one.')
 row('speed','Cycle speed: 1 + {skill} + {clock} = ×{speed}',{skill=n(b.skillSpeed),clock=n(b.clockSpeed),speed=n(b.speed)},'Practiced Hands and owned clocks add speed. Income multipliers do not shorten the cycle.')
 row('cycle','Cycle: {base}s ÷ {speed} = {seconds}s',{base=n(b.baseSeconds),speed=n(b.speed),seconds=n(b.cycleSeconds)},'This is the current server cycle, including hidden clocks.')
 row('income','Factory income: +{rate}/s',{rate=n(b.rate)},'Payments arrive in whole cycles. {workers} apprentices × {reward} pieces ÷ {seconds}s.',{workers=n(b.workers),reward=n(b.manual),seconds=n(b.cycleSeconds)})
 row('orders','Current order bonus: +{bonus}',{bonus=n(b.orderBonus)},'Manual reward × {factor}; only finished manual tricks advance the order.',{factor=n(b.orderFactor)})
 row('rules','Lifetime progress and offline income',{},'Guests and spectators survive prestige and rejoining. Online-friend ×2 is never saved or used offline. All income layers affect manual tricks, apprentices and order rewards; plants, rugs and wall art are cosmetic.')
end

function Journal:updateProduction(state)
	self.productionCard.Visible=state.ready==true
	if not state.ready then return end
	local workers=state.levels.workers or 0
	L.set(self.productionCount,"{cafes} cafes · {workers} apprentices",{cafes=L.number((state.levels.cafes or 0)+1),workers=L.number(workers)})
	self.productionCycle.Visible=workers>0
	if workers>0 then
		L.set(self.productionRate,"+{rate} pieces per second",{rate=L.number(state.rate)})
		L.set(self.productionCycle,"Each apprentice: +{reward} every {seconds}s",{reward=L.number(state.cycleReward),seconds=L.number(state.cycleSeconds)})
		L.set(self.productionHelp,"Each new cafe adds two apprentices. Your home has the first one.")
	else
		L.set(self.productionRate,"No apprentices yet")
		L.set(self.productionHelp,"Hire your first apprentice to start automatic production.")
	end
end
function Journal:update(state)
	self.state=state; local order=state.order
	local receipt=state.lastOrder
	self.receiptCard.Visible=state.ready==true and receipt~=nil
	if self.receiptCard.Visible then
		L.set(self.receiptName,receipt.name)
		L.set(self.receiptBonus,"Bonus received: +{bonus}",{bonus=L.number(receipt.bonus)})
	end
	self:updateProduction(state)
 self:updateBonuses(state)
	self.offlineCard.Visible=(state.offline or 0)>=.1
	if self.offlineCard.Visible then
		L.set(self.offlineAmount,"+{amount} pieces",{amount=L.number(state.offline)})
		local report=state.offlineReport or {}; local seconds=math.floor(report.seconds or 0)
		if seconds>=3600 then
			L.set(self.offlineTime,"Apprentices worked: {hours}h {minutes}m",{hours=math.floor(seconds/3600),minutes=math.floor(seconds%3600/60)})
		elseif seconds>=60 then
			L.set(self.offlineTime,"Apprentices worked: {minutes}m {seconds}s",{minutes=math.floor(seconds/60),seconds=seconds%60})
		else L.set(self.offlineTime,"Apprentices worked: {seconds}s",{seconds=seconds}) end
		L.set(self.offlineHelp,if report.capped then "Already added to your balance. The 4h offline limit was reached." else "Already added to your balance. Apprentices work offline for up to 4h.")
	end
	self.chip.Visible=state.ready==true and order~=nil
	if not order then return end
	L.set(self.chipTitle,if self.compact then "Order · {done}/{total}" else order.name,{done=order.progress,total=order.required})
	L.set(self.chipInfo,if self.compact then "+{bonus} · journal ›" else "{done}/{total} · +{bonus} bonus",{done=order.progress,total=order.required,bonus=L.number(order.bonus)})
	self.chipFill.Size=UDim2.fromScale(order.progress/order.required,1)
	L.set(self.orderTitle,order.name)
	L.set(self.orderProgress,"{done}/{total} tricks by hand",{done=order.progress,total=order.required})
	L.set(self.orderBonus,"Reward: +{bonus} bonus pieces",{bonus=L.number(order.bonus)})
	self.orderFill.Size=self.chipFill.Size
	local rank,nextRank=Orders.rank(state.rounds)
	L.set(self.rankTitle,rank.name)
	if nextRank then
		L.set(self.rankInfo,"Next: {rank} · {remaining} more tricks",{rank=L.token(nextRank.name),remaining=L.number(nextRank.rounds-state.rounds)})
		self.rankFill.Size=UDim2.fromScale(math.clamp((state.rounds-rank.rounds)/(nextRank.rounds-rank.rounds),0,1),1)
	else L.set(self.rankInfo,"Every trick is part of your story."); self.rankFill.Size=UDim2.fromScale(1,1) end
	for key,t in self.stats do L.set(t,"{value}",{value=L.number(state[key] or 0)}) end
end
return Journal
