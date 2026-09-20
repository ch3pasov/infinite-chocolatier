--!nonstrict
-- Исполняем жизненный цикл комнаты: коллизии существуют до появления аватара,
-- чужие запросы не меняют режим соседа, повторное появление сохраняет режим.
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local R=require('@lune/roblox')
local function signal()
 local callbacks={}
 return {Connect=function(_,fn) table.insert(callbacks,fn) end,Fire=function(_,...) for _,fn in callbacks do fn(...) end end}
end
return function(h)
 h.test('соседние кухни, возрождение и переиспользование места после выхода',function()
  local world=R.Instance.new('Folder'); local delayed={}
  local players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end}
  local remote={OnServerEvent=signal()}; local run={Heartbeat=signal()}
  local Rooms=luau.load(fs.readFile('src/server/KitchenRooms.luau'),{environment={
   game={GetService=function(_,name) return if name=='Players' then players elseif name=='RunService' then run elseif name=='ReplicatedStorage' then {WaitForChild=function(self) return self end} else world end},
   require=function() return require("../src/shared/KitchenStructure") end,
   Instance=R.Instance,Enum=R.Enum,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,
   task={spawn=function(fn) fn() end,delay=function(_,fn) table.insert(delayed,fn) end},
  },injectGlobals=true})()
  Rooms.start(remote)
  local function player(id)
   local p={UserId=id,Parent=true,CharacterAdded=signal()}
   function p:SetAttribute(k,v) self[k]=v end
   function p:LoadCharacterAsync()
    assert(#world:GetChildren()>0,'спавн без пола')
    local root={Position=R.Vector3.zero}; local hum={Died=signal()}
    local body={Transparency=.2,CanCollide=true,Parent=true,IsA=function(_,kind) return kind=='BasePart' end}; self.body=body
    self.Character={WaitForChild=function() return root end,FindFirstChild=function() return root end,
     GetDescendants=function() return {body} end,FindFirstChildOfClass=function() return hum end,PivotTo=function(_,cf) self.position=cf.Position; root.Position=cf.Position end}
    self.CharacterAdded:Fire(self.Character); self.root=root; self.hum=hum
    -- Движок завершает размещение после CharacterAdded.
    self.position=R.Vector3.zero; root.Anchored=false
   end
   players.PlayerAdded:Fire(p); return p
  end
  local a,b=player(1),player(2)
  -- Сравниваем реальные результаты обоих строителей, включая перенос комнаты.
  local source=fs.readFile('src/client/KitchenShell.luau'):gsub('world:PivotTo%([^\n]+','')
  local Shell=luau.load(source,{environment={
   game={GetService=function() return {WaitForChild=function(self) return self end} end},
   require=function() return require('../src/shared/KitchenStructure') end,
   Instance=R.Instance,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,Enum=R.Enum,
  },injectGlobals=true})()
  local visible=Shell.new(R.Instance.new('Folder'),R.Vector3.zero)
  for _,owner in {a,b} do for _,name in {'BackWall','LeftWall','RightWall'} do
   local hitbox=world['KitchenRoom_'..owner.UserId][name]; local wall=visible[name]
   h.equals(hitbox.Size,wall.Size)
   assert((hitbox.Position-owner.KitchenOrigin-wall.CFrame.Position).Magnitude<.0001)
   assert(math.abs(hitbox.Position.Y+hitbox.Size.Y/2-6.5)<.0001)
   assert(hitbox.CanCollide and hitbox.Transparency==1)
  end end

  h.equals(a.root.Anchored,true); h.equals(b.root.Anchored,true)
  h.equals(a.body.Transparency,1); h.equals(a.body.CanCollide,false)
  assert((a.KitchenOrigin-b.KitchenOrigin).Magnitude==24)
  remote.OnServerEvent:Fire(a,'walk'); h.equals(a.root.Anchored,false); h.equals(b.root.Anchored,true)
  h.near(a.body.Transparency,.2); h.equals(a.body.CanCollide,true)
  remote.OnServerEvent:Fire(a,'bogus'); h.equals(a.root.Anchored,false)
  a.hum.Died:Fire(); delayed[1](); h.equals(a.root.Anchored,false)
  h.near((a.position-(a.KitchenOrigin+R.Vector3.new(0,3,8))).Magnitude,0)
  local hall=world.SharedKitchenHall; local boundaries={}
  for _,part in hall:GetChildren() do if part.Name=='HallBoundary' then
   table.insert(boundaries,part); assert(part.Transparency==1 and part.CanCollide and part.Anchored)
   assert(part.Size.Y>=60)
  end end
  h.equals(#boundaries,4)
  -- Проверяем покрытие всех краёв всего фундамента, а не только коридора.
  assert(hall.Foundation.Position.Y+hall.Foundation.Size.Y/2<-.3)
  h.near(hall.HallFloor.Position.Z-hall.HallFloor.Size.Z/2,1017)
  h.equals(hall.HallFloor.TopSurface,R.Enum.SurfaceType.Smooth)
  local foundation=hall.Foundation; local min=foundation.Position-foundation.Size/2
  local max=R.Vector3.new(foundation.Position.X+foundation.Size.X/2,0,hall.HallFloor.Position.Z+hall.HallFloor.Size.Z/2)
  -- Плиты стыкуются без щели и без объёмного пересечения: тогда их
  -- внешние боковые грани не могут конкурировать за один пиксель.
  h.near(foundation.Position.Z+foundation.Size.Z/2,hall.HallFloor.Position.Z-hall.HallFloor.Size.Z/2)
  local opaque={}
  for _,part in hall:GetChildren() do if part.Transparency==0 then table.insert(opaque,part) end end
  for i=1,#opaque do for j=i+1,#opaque do
   local a,b=opaque[i],opaque[j]
   local overlap=true
   for _,axis in {'X','Y','Z'} do
    local depth=math.min(a.Position[axis]+a.Size[axis]/2,b.Position[axis]+b.Size[axis]/2)-math.max(a.Position[axis]-a.Size[axis]/2,b.Position[axis]-b.Size[axis]/2)
    if depth<=.0001 then overlap=false end
   end
   assert(not overlap,'видимые плиты платформы пересекаются')
  end end
  for _,edge in {{'X',min.X,'Z',35},{'X',max.X,'Z',35},{'Z',min.Z,'X',foundation.Size.X},{'Z',max.Z,'X',foundation.Size.X}} do
   local covered=false
   for _,part in boundaries do if math.abs(part.Position[edge[1]]-edge[2])<.01 and part.Size[edge[3]]>=edge[4] then covered=true end end
   assert(covered,'открытая внешняя граница')
  end
  for _,outside in {R.Vector3.new(0,-9,1008),R.Vector3.new(-13,3,1000),R.Vector3.new(max.X+1,3,1020),R.Vector3.new(0,3,992),R.Vector3.new(0,3,1029)} do
   a.root.Position=outside; a.root.AssemblyLinearVelocity=R.Vector3.new(0,-100,0)
   run.Heartbeat:Fire(.25)
   h.equals(a.position,a.KitchenOrigin+R.Vector3.new(0,3,8))
   h.equals(a.root.AssemblyLinearVelocity,R.Vector3.zero); h.equals(a.KitchenMode,'walk')
  end
  a.root.Position=b.KitchenOrigin+R.Vector3.new(0,3,8); run.Heartbeat:Fire(.25)
  h.equals(a.root.Position,b.KitchenOrigin+R.Vector3.new(0,3,8))
  remote.OnServerEvent:Fire(a,'watch'); h.equals(a.root.Anchored,true)
  players.PlayerRemoving:Fire(a); h.equals(#world:GetChildren(),2)
  local c=player(3); h.equals(c.KitchenOrigin,a.KitchenOrigin)
  players.PlayerRemoving:Fire(c)
  players.PlayerRemoving:Fire(b); h.equals(#world:GetChildren(),1)
  assert(world.SharedKitchenHall:FindFirstChild('Foundation'),'пол гостей должен пережить уход владельца')
 end)
end
