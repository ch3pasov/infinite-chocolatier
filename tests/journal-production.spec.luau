--!nonstrict
-- Сводка следует серверному снимку: число кафе не равно числу работников,
-- а длительность цикла учитывает купленные часы даже после их скрытия.
local fs=require('@lune/fs'); local luau=require('@lune/luau')
local Economy=require('../src/shared/Economy')
return function(h)
 h.test('страница бонусов показывает канонический снимок и компактные крайние числа',function()
  local stub=setmetatable({},{__index=function(_,name) return name end})
  local Journal=luau.load(fs.readFile('src/client/Journal.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},script={Parent=stub},
   require=function(name) return if name=='Localization' then {number=function(n) return n end,set=function(label,key,args) label.key=key; label.args=args end} else {} end,
  },injectGlobals=true})()
  local rows={}; for _,key in {'base','recipe','stars','temper','online','guests','spectators','total','manual','workers','speed','cycle','income','orders','rules'} do rows[key]={value={},help={}} end
  local ui=setmetatable({bonusRows=rows,tabs={bonuses={},journal={}},pages={},calculations={}},Journal)
  ui:updateBonuses({ready=false}); h.equals(ui.tabs.bonuses.Visible,false)
  local data=Economy.load({stars=3,levels={workers=1,speed=8,recipe=2}})
  data.onlineFriend=true; Economy.addSocial(data,'guests',77,1); Economy.addSocial(data,'spectators',77,1)
  local state=Economy.snapshot(data); state.ready=true; ui:updateBonuses(state)
  h.equals(ui.tabs.bonuses.Visible,true)
  h.near(rows.total.value.args.factor,state.bonuses.multiplier)
  h.near(rows.manual.value.args.reward,state.manual)
  h.near(rows.income.value.args.rate,state.rate)
  h.near(rows.cycle.value.args.seconds,state.cycleSeconds)
  h.equals(rows.guests.value.args.count,1); h.equals(rows.spectators.value.args.count,1)
  ui:selectPage('bonuses'); h.equals(ui.pages.Visible,false); h.equals(ui.calculations.Visible,true)
  ui:selectPage('journal'); h.equals(ui.pages.Visible,true); h.equals(ui.calculations.Visible,false)
  state.bonuses.multiplier=1e28; state.bonuses.cycleSeconds=1e-8
  ui:updateBonuses(state)
  h.equals(rows.total.value.args.factor,'1e+28'); h.equals(rows.cycle.value.args.seconds,'1e-08')
  local catalog=require('../src/shared/LocalizationCatalog')
  for _,row in rows do assert(catalog.entries[row.value.key],row.value.key); assert(catalog.entries[row.help.key],row.help.key) end
 end)
 h.test('сводка фабрики учитывает найм, новые кафе, бонусы и сброс',function()
  local stub=setmetatable({},{__index=function(_,name) return name end})
  local Journal=luau.load(fs.readFile('src/client/Journal.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},script={Parent=stub},
   require=function(name) return if name=='Localization' then {number=function(n) return n end,set=function(label,key,args) label.key=key; label.args=args end} else {} end,
  },injectGlobals=true})()
  local ui=setmetatable({productionCard={},productionCount={},productionRate={},productionCycle={},productionHelp={}},Journal)
  ui:updateProduction({ready=false}); h.equals(ui.productionCard.Visible,false)
  local data=Economy.load({slices=10000,earned=5000,levels={kitchen=1}})
  local function update() local state=Economy.snapshot(data); state.ready=true; ui:updateProduction(state) end
  update(); h.equals(ui.productionCount.args.cafes,1); h.equals(ui.productionCount.args.workers,0)
  h.equals(ui.productionRate.key,'No apprentices yet'); h.equals(ui.productionCycle.Visible,false)
  assert(Economy.buy(data,'workers_1')); update()
  h.equals(ui.productionCount.args.workers,1); h.equals(ui.productionCycle.args.reward,1); h.equals(ui.productionCycle.args.seconds,10)
  assert(Economy.buy(data,'cafes')); assert(Economy.buy(data,'craft')); assert(Economy.buy(data,'clock_1')); update()
  h.equals(ui.productionCount.args.cafes,2); h.equals(ui.productionCount.args.workers,3)
  h.equals(ui.productionCycle.args.reward,2); h.near(ui.productionCycle.args.seconds,10/1.1)
  h.near(ui.productionRate.args.rate,.66)
  assert(Economy.buy(data,'clock_1')); update(); h.near(ui.productionRate.args.rate,.66,'скрытые часы сохраняют бонус')
  assert(Economy.prestige(data)); update()
  h.equals(ui.productionCount.args.cafes,1); h.equals(ui.productionCount.args.workers,0); h.equals(ui.productionCycle.Visible,false)
  ui:updateProduction({ready=false}); h.equals(ui.productionCard.Visible,false)
 end)
 h.test('дневник отклоняет конфликтующее меню и один раз восстанавливает ввод',function()
  local stub=setmetatable({},{__index=function(_,name) return name end})
  local Journal=luau.load(fs.readFile('src/client/Journal.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},script={Parent=stub},require=function() return {} end,
  },injectGlobals=true})()
  local allowed=false; local toggles={}; local cancelled=0
  local view={cutIndex=3,cutProgress=.4,endDrag=function(_,cancel) assert(cancel); cancelled+=1 end}
  local ui=setmetatable({view=view,overlay={},state={ready=false},
   canOpen=function() return allowed end,onToggle=function(open) table.insert(toggles,open) end},Journal)
  ui:open(); h.equals(#toggles,0)
  ui.state.ready=true; ui:open(); h.equals(#toggles,0)
  allowed=true; ui:open(); ui:open()
  h.equals(#toggles,1); h.equals(toggles[1],true); h.equals(cancelled,1)
  h.equals(view.cutIndex,3); h.equals(view.cutProgress,.4)
  ui:close(); ui:close(); h.equals(#toggles,2); h.equals(toggles[2],false)
  h.equals(view.journalOpen,false); h.equals(ui.overlay.Visible,false)
 end)

end
