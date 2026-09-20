--!nostrict
-- Исполняем настоящий перенос UI между модальным и закреплённым магазином.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local R = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Layout = require("../src/client/Layout")
local modules = { Config = Config, Layout = Layout, Theme = {}, Economy=require("../src/shared/Economy"), Localization={number=tostring,token=function(x) return x end,set=function(object,value,args) object.Text=value; object.Args=args end}, KitchenCatalog=require("../src/shared/KitchenCatalog") }
local Atelier = luau.load(fs.readFile("src/client/Atelier.luau"), { environment = {
	game = { GetService = function() return { WaitForChild = function() return { Config = "Config", KitchenCatalog="KitchenCatalog", Economy="Economy" } end } end },
	script = { Parent = { Theme = "Theme", Layout = "Layout", Localization="Localization" } },
	require = function(name) return modules[name] end,
	Vector2 = R.Vector2, UDim2 = R.UDim2,
}, injectGlobals = true })()

return function(h)
 h.test('статус сохранения показывает возраст, но не скрывает ошибку или Studio',function()
  local ui=setmetatable({saved={}},Atelier)
  ui:updateSaveStatus({saveStatus='Progress saved',saveAge=0})
  h.equals(ui.saved.Text,'Progress saved')
  ui:updateSaveStatus({saveStatus='Progress saved',saveAge=29})
  h.equals(ui.saved.Text,'Saved {seconds}s ago'); h.equals(ui.saved.Args.seconds,'29')
  ui:updateSaveStatus({saveStatus='Saving delayed · retrying',saveAge=80})
  h.equals(ui.saved.Text,'Saving delayed · retrying')
  ui:updateSaveStatus({saveStatus='Test session · progress is not saved',saveAge=80})
  h.equals(ui.saved.Text,'Test session · progress is not saved')
  ui:updateSaveStatus({saveStatus='Progress saved'})
  h.equals(ui.saved.Text,'Progress saved','старый снимок без возраста остаётся совместимым')
 end)
 h.test('ответ загрузки блокирует ручной ввод и отменяет активное перетаскивание',function()
  local cancelled=false; local journalState
  local ui=setmetatable({state={ready=true},view={inputBlocked=false,endDrag=function(_,cancel) cancelled=cancel end},
   metrics={},saved={},journal={update=function(_,state) journalState=state end}},Atelier)
  local loading={ready=false}
  ui:update(loading)
  h.equals(ui.view.inputBlocked,true); h.equals(cancelled,true)
  h.equals(ui.state,loading); h.equals(journalState,loading)
  h.equals(ui.metrics.Text,'Loading your progress')
 end)
 h.test("переключатель количества меняет запрос навыков, но не разовые покупки кухни",function()
  local E=require('../src/shared/Economy')
  local sent={}
  local state=E.snapshot(E.load({slices=10000})); state.ready=true
  local ui=setmetatable({state=state,update=function() end,remotes={purchase={FireServer=function(_,...) table.insert(sent,{...}) end}}},Atelier)
  local craft,kitchen
  for _,spec in Config.Economy.upgrades do if spec.id=='craft' then craft=spec elseif spec.id=='kitchen' then kitchen=spec end end
  ui:setQuantity(10); local price,count=ui:quote(craft); h.equals(count,10)
  h.equals(price,E.quote(state,'craft',10)); ui:purchase(craft)
  h.equals(sent[1][1],'craft'); h.equals(sent[1][2],10)
  ui:purchase(kitchen); h.equals(sent[2][1],'kitchen'); h.equals(sent[2][2],1)
  ui:setQuantity('max'); ui:purchase(craft); h.equals(sent[3][2],'max')
  state.slices=0; ui:purchase(craft); h.equals(#sent,3)
  ui:setQuantity('invalid'); h.equals(ui.quantity,'max')
 end)
	h.test("магазин закрепляется сбоку без блокировки игры и возвращается в модальный режим", function()
		local root = R.Instance.new("Frame")
		local function make(class)
			local v = R.Instance.new(class or "Frame"); v.Parent = root; return v
		end
		local status = make("TextLabel")
		R.Instance.new("UITextSizeConstraint").Parent = status
		local counter = make("TextLabel")
		local ui = setmetatable({
			view = { root = root, counter = counter, status = status, cutProgress = 95 },
			state = { ready = true }, sidebar = make(), metrics = make("TextLabel"),
			open = make("TextButton"), close = make("TextButton"), overlay = make(), panel = make(),
			panelBounds = make("UISizeConstraint"), title = make("TextLabel"), update = function() end,
			journal = { fit = function(self,_,_,position,size) self.position=position; self.size=size end },
		}, Atelier)
		for _, size in { R.Vector2.new(390, 844), R.Vector2.new(1440, 900), R.Vector2.new(844, 390), R.Vector2.new(568,320), R.Vector2.new(812,375), R.Vector2.new(390, 844) } do
			root.AbsoluteSize = size
			ui:fit()
			local mode = Layout.presentation(size.X, size.Y, Config.Board.viewportPadding)
			h.equals(ui.view.inputBlocked, false)
			h.equals(ui.open.Visible, not mode.docked)
			h.equals(ui.overlay.Visible, mode.docked)
			h.equals(counter.Parent, if mode.landscape then ui.sidebar else root)
			h.equals(status.Parent, counter.Parent)
			h.equals(ui.view.cutProgress, 95)
			if mode.landscape then
				assert(status.Position.Y.Offset>=ui.journal.position.Y.Offset+ui.journal.size.Y.Offset+4)
				if not mode.docked then
					local buttonTop=ui.sidebar.Size.Y.Offset+ui.open.Position.Y.Offset-ui.open.Size.Y.Offset
					assert(status.Position.Y.Offset+status.Size.Y.Offset<=buttonTop-6,"подсказка перекрыла кнопку улучшений")
				end
			end
			if mode.docked then
				h.equals(ui.overlay.Position.X.Offset, size.X - mode.right)
				h.equals(ui.close.Visible, false)
			end
		end
		root:Destroy()
	end)
 h.test('два меню разделяют конечные покупки и бесконечные навыки, открытие исчезает после оплаты',function()
  local E=require('../src/shared/Economy')
  local C=require('../src/shared/KitchenCatalog')
  local ui=setmetatable({quantityBar={},quantityButtons={},journal={update=function() end},view={counter={},endDrag=function() end},overlay={Visible=false},cards={},placeMap={},placesBack={},scroll={},metrics={},balance={},balanceTest={},togglePrestige={},saved={},open={},prestigeInfo={},fill={},ascend={},cancel={}},Atelier)
  local specs={}
  for _,spec in Config.Economy.upgrades do if spec.id=='kitchen' or spec.maxLevel==math.huge then table.insert(specs,spec) end end
  for _,spec in C.items do table.insert(specs,spec) end
  for _,spec in specs do ui.cards[spec.id]={spec=spec,frame={},description={},heading={},buy={}} end
  local d=E.load({slices=25})
  local function refresh(mode)
   ui.mode=mode; local state=E.snapshot(d); state.ready=true; ui:update(state)
  end
  ui:update({ready=false}); refresh('upgrades')
  h.equals(ui.view.inputBlocked,false,'готовый профиль снова разрешает резать')
  h.equals(ui.cards.kitchen.frame.Visible,true); h.equals(ui.cards.craft.frame.Visible,true)
  h.equals(ui.cards.clock_1.frame.Visible,false); h.equals(ui.cards.speed.frame.Visible,false); h.equals(ui.cards.cafes.frame.Visible,false)
  assert(E.buy(d,'kitchen')); refresh('upgrades'); h.equals(ui.cards.kitchen.frame.Visible,false)
  refresh('kitchen')
  h.equals(ui.placeMap.Visible,true); h.equals(ui.scroll.Visible,false)
  for _,spec in C.items do h.equals(ui.cards[spec.id].frame.Visible,false) end
  ui.selectedPlace='clock'; refresh('kitchen')
  h.equals(ui.placeMap.Visible,false); h.equals(ui.scroll.Visible,true)
  for _,spec in C.items do h.equals(ui.cards[spec.id].frame.Visible,spec.group=='clock') end
  ui.selectedPlace='workers'; refresh('kitchen'); h.equals(ui.cards.workers_1.frame.Visible,true)
  h.equals(ui.cards.clock_1.frame.Visible,false)
  h.equals(ui.cards.craft.frame.Visible,false); h.equals(ui.cards.recipe.frame.Visible,false)
  h.equals(ui.balance.Text,'3/3 · Choose the apprentice spot, then hire for free.')
  assert(E.buy(d,'workers_1')); refresh('upgrades'); h.equals(ui.cards.speed.frame.Visible,true); h.equals(ui.cards.cafes.frame.Visible,true)
 end)

end
