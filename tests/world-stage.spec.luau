-- Проверяем владение камерой и очистку сцен без запуска графического движка.
local R=require('@lune/roblox')
local luau=require('@lune/luau')
local fs=require('@lune/fs')
return function(h)
 h.test('3D: камеры остаются в мире, скрытая кухня не рендерится, очистка восстанавливает окружение',function()
  local world=R.Instance.new('Workspace')
  local storage=R.Instance.new('ReplicatedStorage')
  local light=R.Instance.new('Lighting'); light.Brightness=3; light.ClockTime=14; light.GlobalShadows=false; light.Ambient=R.Color3.new(); light.OutdoorAmbient=R.Color3.new()
  local original=R.Instance.new('Camera'); original.Parent=world; world.CurrentCamera=original
  local services={Workspace=world,ReplicatedStorage=storage,Lighting=light}
  local Stage=luau.load(fs.readFile('src/client/WorldStage.luau'),{environment={
   game={GetService=function(_,name)return services[name]end},Instance=R.Instance,Enum=R.Enum,Color3=R.Color3,
  },injectGlobals=true})()
  local stage=Stage.new()
  local board,kitchen=stage:createWorld('Board'),stage:createWorld('Kitchen')
  local a,b=stage:createCamera('A',5),stage:createCamera('B',45)
  stage:activate(board,a)
  assert(world.CurrentCamera==a and a:IsDescendantOf(world))
  assert(board.Parent==world and not kitchen:IsDescendantOf(world))
  stage:activate(kitchen,b)
  assert(world.CurrentCamera==b and b:IsDescendantOf(world))
  assert(kitchen.Parent==world and not board:IsDescendantOf(world))
  stage:activate(board,a)
  assert(world.CurrentCamera==a and board.Parent==world)
  assert(light:FindFirstChild("ChocolateHorizon"))
  stage:destroy()
  h.equals(#light:GetChildren(),0)
  assert(world.CurrentCamera==original and light.Brightness==3)
  assert(#storage:GetChildren()==0 and #world:GetChildren()==1)
 end)
end
