--!nonstrict
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local R=require('@lune/roblox')
local E=require('../src/shared/Economy')
local Decor=luau.load(fs.readFile('src/client/KitchenDecor.luau'),{environment={Instance=R.Instance,Vector3=R.Vector3,Color3=R.Color3,CFrame=R.CFrame,Enum=R.Enum},injectGlobals=true})()
return function(h)
 h.test('купленные предметы появляются в своей комнате без пересборки при начислении',function()
  local kitchen={world=R.Instance.new('Model'),origin=R.Vector3.new(80,0,1000)}
  local state=E.load({slices=1000,earned=5000})
  Decor.update(kitchen,state); h.equals(#kitchen.decorModel:GetChildren(),0)
  for _,id in {'temper','library','clock','plant','rug','art'} do assert(E.buy(state,id)) end
  Decor.update(kitchen,state)
  local model=kitchen.decorModel
  for _,name in {'TemperingMachine','RecipeBook','ClockFace','CocoaPot','CaramelRug','GoldenCocoa'} do assert(model:FindFirstChild(name),name) end
  for _,p in model:GetChildren() do assert((p.Position-kitchen.origin).Magnitude<20) end
  E.credit(state,1); Decor.update(kitchen,state); h.equals(kitchen.decorModel,model)
  E.buy(state,'plant'); Decor.update(kitchen,state); h.equals(kitchen.decorModel:FindFirstChild('CocoaPot'),nil)
  assert(E.prestige(state)); Decor.update(kitchen,state)
  h.equals(kitchen.decorModel:FindFirstChild('TemperingMachine'),nil)
  assert(kitchen.decorModel:FindFirstChild('CaramelRug'))
 end)
end
