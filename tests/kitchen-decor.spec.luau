--!nonstrict
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local R=require('@lune/roblox')
local E=require('../src/shared/Economy')
local Preview=require('../src/client/DecorPreview')
local Decor=luau.load(fs.readFile('src/client/KitchenDecor.luau'),{environment={game={GetService=function() return {Shared={KitchenCatalog='catalog'}} end},require=function() return require('../src/shared/KitchenCatalog') end,Instance=R.Instance,Vector3=R.Vector3,Color3=R.Color3,CFrame=R.CFrame,Enum=R.Enum},injectGlobals=true})()
return function(h)
 h.test('купленные предметы появляются в своей комнате без пересборки при начислении',function()
  local kitchen={world=R.Instance.new('Model'),origin=R.Vector3.new(80,0,1000)}
  local state=E.load({slices=1000,earned=5000})
  Decor.update(kitchen,state); h.equals(#kitchen.decorModel:GetChildren(),0)
  for _,id in {'kitchen','temper_1','library_1','clock_1','plant','rug','art'} do assert(E.buy(state,id)) end
  Decor.update(kitchen,state)
  local model=kitchen.decorModel
  for _,name in {'TemperingMachine','RecipeBook','ClockFace','CocoaPot','CaramelRug','GoldenCocoa'} do assert(model:FindFirstChild(name),name) end
  for _,p in model:GetChildren() do assert((p.Position-kitchen.origin).Magnitude<20) end
  E.credit(state,1); Decor.update(kitchen,state); h.equals(kitchen.decorModel,model)
  E.buy(state,'plant'); Decor.update(kitchen,state); h.equals(kitchen.decorModel:FindFirstChild('CocoaPot'),nil)
  assert(E.prestige(state)); Decor.update(kitchen,state)
  h.equals(#kitchen.decorModel:GetChildren(),0)
 end)
 h.test('примерка не списывает деньги и отменяется без изменения профиля',function()
  local kitchen={world=R.Instance.new('Model'),origin=R.Vector3.new(0,0,1000)}
  local state=E.load({slices=0})
  local preview=Preview.begin('plant',state)
  Decor.update(kitchen,state,Preview.update(preview,state))
  assert(kitchen.decorModel:FindFirstChild('CocoaPot'))
  h.equals(state.levels.plant,0); h.equals(state.decor.plant,false); h.equals(state.slices,0)
  E.credit(state,1); Decor.update(kitchen,state,Preview.update(preview,state))
  assert(kitchen.decorModel:FindFirstChild('CocoaPot')); h.equals(preview.confirmed,false)
  Decor.update(kitchen,state)
  h.equals(kitchen.decorModel:FindFirstChild('CocoaPot'),nil)
 end)
 h.test('серверная покупка сохраняет модель примерки, снятие и повторная установка работают',function()
  local kitchen={world=R.Instance.new('Model'),origin=R.Vector3.new(0,0,1000)}
  local state=E.load({slices=1000,levels={kitchen=1}}); local preview=Preview.begin('art',state)
  Decor.update(kitchen,state,Preview.update(preview,state)); local before=kitchen.decorModel
  assert(E.buy(state,'art')); Decor.update(kitchen,state,Preview.update(preview,state))
  h.equals(preview.confirmed,true); h.equals(kitchen.decorModel,before)
  assert(E.buy(state,'art')); Decor.update(kitchen,state,Preview.update(preview,state))
  h.equals(kitchen.decorModel:FindFirstChild('ArtFrame'),nil)
  local ownedPreview=Preview.begin('art',state)
  Decor.update(kitchen,state,Preview.update(ownedPreview,state)); assert(kitchen.decorModel:FindFirstChild('ArtFrame'))
  assert(E.buy(state,'art')); Decor.update(kitchen,state,Preview.update(ownedPreview,state))
  assert(kitchen.decorModel:FindFirstChild('ArtFrame'))
 end)

 h.test('пять моделей каждой коллекции различаются геометрией, примерка не меняет бонусы',function()
  local kitchen={world=R.Instance.new('Model'),origin=R.Vector3.zero}
  local d=E.load({slices=100000,levels={kitchen=1}})
  for _,group in {'clock','temper','library'} do
   local seen={}
   for i=1,5 do
    local rate=E.manual(d)
    Decor.update(kitchen,d,group..'_'..i)
    local signature={}
    for _,part in kitchen.decorModel:GetChildren() do table.insert(signature,part.Name..tostring(part.Size)..tostring(part.CFrame)..tostring(part:FindFirstChildOfClass('SpecialMesh')~=nil)) end
    local key=table.concat(signature,';'); assert(not seen[key],group..' '..i); seen[key]=true
    h.near(E.manual(d),rate); h.equals(d.owned[group..'_'..i],false)
   end
  end
 end)

end
