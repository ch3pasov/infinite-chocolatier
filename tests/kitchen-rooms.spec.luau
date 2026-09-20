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
  function players:GetFriendsAsync() return {IsFinished=true,GetCurrentPage=function() return {{Id=1001},{Id=1002},{Id=1003},{Id=1004}} end} end
  local remote={OnServerEvent=signal()}; local run={Heartbeat=signal()}; local prompts={}; local now=0
  local Rooms=luau.load(fs.readFile('src/server/KitchenRooms.luau'):gsub('prompt.Triggered:Connect%(', 'connectPrompt(prompt,'),{environment={
   game={GetService=function(_,name) return if name=='Players' then players elseif name=='RunService' then run elseif name=='ReplicatedStorage' then {WaitForChild=function(_,name) return if name=='Shared' then {WaitForChild=function(_,module) return module end} else name end} else world end},
   require=function(name) return require("../src/shared/"..name) end,
   Instance=R.Instance,Enum=R.Enum,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,UDim2=R.UDim2,
   os={clock=function() return now end},connectPrompt=function(prompt,fn) prompts[prompt]=fn end,
   task={spawn=function(fn) fn() end,delay=function(_,fn) table.insert(delayed,fn) end},
  },injectGlobals=true})()
  local controller=Rooms.start(remote)
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
  local directory=world.KitchenIslands
  local function visit(p,roomId,home)
   now+=1
   local board=directory['KitchenRoom_'..roomId][if home then 'HomeCafeArrow' else 'NextCafeArrow']
   p.root.Position=board.Position
   prompts[board:FindFirstChildOfClass('ProximityPrompt')](p)
  end
  -- Сравниваем реальные результаты обоих строителей, включая перенос комнаты.
  local source=fs.readFile('src/client/KitchenShell.luau'):gsub('world:PivotTo%([^\n]+','')
  local Shell=luau.load(source,{environment={
   game={GetService=function() return {WaitForChild=function(self) return self end} end},
   require=function() return require('../src/shared/KitchenStructure') end,
   Instance=R.Instance,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,Enum=R.Enum,
  },injectGlobals=true})()
  local visible=Shell.new(R.Instance.new('Folder'),R.Vector3.zero)
  for _,owner in {a,b} do for _,name in {'BackWall','LeftWall','RightWall'} do
   local hitbox=directory['KitchenRoom_'..owner.UserId][name]; local wall=visible[name]
   h.equals(hitbox.Size,wall.Size)
   assert((hitbox.Position-owner.KitchenOrigin-wall.CFrame.Position).Magnitude<.0001)
   assert(math.abs(hitbox.Position.Y+hitbox.Size.Y/2-6.5)<.0001)
   assert(hitbox.CanCollide and hitbox.Transparency==1)
  end end

  h.equals(a.root.Anchored,true); h.equals(b.root.Anchored,true)
  h.equals(a.body.Transparency,1); h.equals(a.body.CanCollide,false)
  assert((a.KitchenOrigin-b.KitchenOrigin).Magnitude==256)
  remote.OnServerEvent:Fire(a,'walk'); h.equals(a.root.Anchored,false); h.equals(b.root.Anchored,true)
  h.near(a.body.Transparency,.2); h.equals(a.body.CanCollide,true)
  remote.OnServerEvent:Fire(a,'bogus'); h.equals(a.root.Anchored,false)
  a.hum.Died:Fire(); delayed[1](); h.equals(a.root.Anchored,false)
  h.near((a.position-(a.KitchenOrigin+R.Vector3.new(0,3,12))).Magnitude,0)
  local hall=directory.KitchenRoom_1; local boundaries={}
  for _,part in hall:GetChildren() do if part.Name=='IslandBoundary' then
   table.insert(boundaries,part); assert(part.Transparency==1 and part.CanCollide and part.Anchored)
   assert(part.Size.Y>=60)
  end end
  h.equals(#boundaries,4)
  -- Проверяем покрытие всех краёв всего фундамента, а не только коридора.
  assert(hall.Foundation.Position.Y+hall.Foundation.Size.Y/2<-.3)
  h.equals(hall:FindFirstChild('HallFloor'),nil)
  h.equals(hall.Foundation.Transparency,1)
  h.equals(hall.Floor.Transparency,1)
  local foundation=hall.Foundation; local min=foundation.Position-foundation.Size/2
  local max=foundation.Position+foundation.Size/2
  for _,name in {'HomeCafeArrow','NextCafeArrow'} do
   local board=hall[name]
   h.near(math.abs(board.Position.X-a.KitchenOrigin.X),10.25)
   h.near(board.Position.Z-a.KitchenOrigin.Z,11)
   assert(math.abs(board.CFrame.LookVector.X)>.99)
  end
  for _,edge in {{'X',min.X,'Z',24},{'X',max.X,'Z',24},{'Z',min.Z,'X',foundation.Size.X},{'Z',max.Z,'X',foundation.Size.X}} do
   local covered=false
   for _,part in boundaries do if math.abs(part.Position[edge[1]]-edge[2])<.01 and part.Size[edge[3]]>=edge[4] then covered=true end end
   assert(covered,'открытая внешняя граница')
  end
  for _,outside in {R.Vector3.new(0,-9,1008),R.Vector3.new(-12,3,1000),R.Vector3.new(max.X+1,3,1020),R.Vector3.new(0,3,992),R.Vector3.new(0,3,1029)} do
   a.root.Position=outside; a.root.AssemblyLinearVelocity=R.Vector3.new(0,-100,0)
   run.Heartbeat:Fire(.25)
   h.equals(a.position,a.KitchenOrigin+R.Vector3.new(0,3,12))
   h.equals(a.root.AssemblyLinearVelocity,R.Vector3.zero); h.equals(a.KitchenMode,'walk')
  end
  -- Нельзя вызвать переход издалека или во время нарезки.
  local arrow=directory.KitchenRoom_1.NextCafeArrow
  local trigger=prompts[arrow:FindFirstChildOfClass('ProximityPrompt')]
  a.root.Position=a.KitchenOrigin; trigger(a); h.equals(a.VisitingKitchen,1)
  remote.OnServerEvent:Fire(a,'cut'); visit(a,1,false); h.equals(a.VisitingKitchen,1)
  remote.OnServerEvent:Fire(a,'walk'); visit(a,1,false)
  h.equals(a.VisitingKitchen,2); h.equals(a.position,b.KitchenOrigin+R.Vector3.new(0,3,12))
  -- Последний гость удерживает остров после выхода владельца.
  players.PlayerRemoving:Fire(b); assert(directory:FindFirstChild('KitchenRoom_2'))
  h.equals(directory.KitchenRoom_2:GetAttribute('OwnerOnline'),false)
  local c=player(3); assert(c.KitchenOrigin~=b.KitchenOrigin,'занятое гостем место переиспользовано')
  remote.OnServerEvent:Fire(c,'walk'); visit(c,3,false); visit(c,1,false)
  h.equals(c.VisitingKitchen,1,'кафе ушедшего владельца недоступно новым гостям')
  -- Возвращение владельца использует сохранённый остров без дубликатов.
  local returned=player(2); h.equals(returned.KitchenOrigin,b.KitchenOrigin)
  h.equals(#directory:GetChildren(),3)
  visit(c,1,false); h.equals(c.VisitingKitchen,2)
  players.PlayerRemoving:Fire(returned); assert(directory:FindFirstChild('KitchenRoom_2'))
  visit(a,2,true); h.equals(a.VisitingKitchen,1)
  assert(directory:FindFirstChild('KitchenRoom_2'),'в кафе ещё один гость')
  remote.OnServerEvent:Fire(c,'cut'); h.equals(c.VisitingKitchen,3)
  h.equals(directory:FindFirstChild('KitchenRoom_2'),nil)
  local d=player(4); h.equals(d.KitchenOrigin,b.KitchenOrigin)
  -- Переход по кругу и выход последнего гостя тоже освобождают остров.
  visit(a,1,false); visit(a,3,false); h.equals(a.VisitingKitchen,4)
  players.PlayerRemoving:Fire(d); assert(directory:FindFirstChild('KitchenRoom_4'))
  players.PlayerRemoving:Fire(a)
  h.equals(directory:FindFirstChild('KitchenRoom_4'),nil)
  h.equals(directory:FindFirstChild('KitchenRoom_1'),nil)
  players.PlayerRemoving:Fire(c); h.equals(#directory:GetChildren(),0)
  -- Свои покупки видны в очереди, но не становятся целями телепортации.
  local e=player(10)
  controller:sync(e,{levels={cafes=1000000},owned={workers_1=true},cycleSeconds=4})
  h.equals(#directory:GetChildren(),1)
  remote.OnServerEvent:Fire(e,'walk'); visit(e,10,false)
  h.equals(e.VisitingKitchen,10); h.equals(e.VisitingCafeIndex,0)
  h.equals(#directory:GetChildren(),1)
  local friend=player(1001)
  assert(directory.KitchenRoom_10:GetAttribute('Staff1')~=1001)
  visit(e,10,false); h.equals(e.VisitingKitchen,1001); h.equals(e.VisitingCafeIndex,0)
  visit(e,1001,true); h.equals(e.VisitingKitchen,10)
  players.PlayerRemoving:Fire(friend)
  local f=player(20); remote.OnServerEvent:Fire(f,'walk')
  visit(f,20,false); visit(f,10,false)
  h.equals(f.VisitingKitchen,10); h.equals(f.VisitingCafeIndex,0)
  players.PlayerRemoving:Fire(e)
  assert(directory:FindFirstChild('KitchenRoom_10'))
  visit(f,10,true); h.equals(directory:FindFirstChild('KitchenRoom_10'),nil)
  players.PlayerRemoving:Fire(f); h.equals(#directory:GetChildren(),0)
  -- Ошибка при входе не закрепляет пустой список на весь сеанс.
  local fetch=players.GetFriendsAsync; local attempts=0
  players.GetFriendsAsync=function(self)
   attempts+=1; if attempts==1 then error('temporary friends failure') end
   return fetch(self)
  end
  local pending=#delayed
  local retryOwner=player(30)
  h.equals(directory.KitchenRoom_30:GetAttribute('Staff1'),0)
  h.equals(directory.KitchenRoom_30:GetAttribute('FriendListStatus'),'retrying')
  delayed[pending+1]()
  h.equals(attempts,2)
  h.equals(directory.KitchenRoom_30:GetAttribute('Staff1'),1001)
  h.equals(directory.KitchenRoom_30:GetAttribute('FriendListStatus'),'ready')
  players.PlayerRemoving:Fire(retryOwner)

 end)
end
