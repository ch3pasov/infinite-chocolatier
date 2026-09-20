--!nonstrict
-- Сводка следует серверному снимку: число кафе не равно числу работников,
-- а длительность цикла учитывает купленные часы даже после их скрытия.
local fs=require('@lune/fs'); local luau=require('@lune/luau')
local Economy=require('../src/shared/Economy')
return function(h)
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
end
