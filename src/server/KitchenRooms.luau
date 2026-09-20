--!nonstrict
-- Сервер материализует только домашние и посещаемые кафе. Купленная очередь
-- задаётся числом: её длина не требует столько же моделей, связей и аватаров.
local Shared=game:GetService('ReplicatedStorage'):WaitForChild('Shared')
local Structure=require(Shared:WaitForChild('KitchenStructure'))
local Queue=require(Shared:WaitForChild('CafeQueue'))
local Roster=require(Shared:WaitForChild('StaffRoster'))
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local RunService=game:GetService('RunService')
local Rooms={}
function Rooms.start(remote)
 local homes,slots,visitors,byKey,pools={},{},{},{},{}
 local directory=Instance.new('Folder'); directory.Name='KitchenIslands'; directory.Parent=Workspace
 local function solid(parent,name,size,position)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=position
  p.Anchored=true; p.Transparency=1; p.CanCollide=true
  p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
  p.Material=Enum.Material.SmoothPlastic; p.Parent=parent; return p
 end
 local function cleanup(room)
  if room.index==0 and room.owner then return end
  for _,visiting in visitors do if visiting==room then return end end
  slots[room.slot]=nil; byKey[room.key]=nil; room.model:Destroy()
  for _,other in slots do if other.id==room.id then return end end
  pools[room.id]=nil
 end
 local function refreshStaff()
  local online={}
  for _,player in Players:GetPlayers() do online[player.UserId]=true end
  for player in homes do online[player.UserId]=true end
  local rosters=Roster.build(pools,online)
  for _,room in slots do
   -- Дальние копии получают те же назначения, что посещаемая комната.
   room.model:SetAttribute("StaffRoster",table.concat(rosters[room.id] or {},","))
   for side=1,2 do
    local ordinal=if room.index==0 then 1 else room.index*2+side-1
    local id,seed=Roster.identity(rosters,room.id,ordinal)
    room.model:SetAttribute('Staff'..side,id); room.model:SetAttribute('StaffSeed'..side,seed)
   end
  end
 end
 local function records()
  local records={}
  for _,room in slots do table.insert(records,{owner=room.id,index=room.index,online=room.owner~=nil,count=room.count}) end
  return records
 end
 local function enter(player,room)
  local previous=visitors[player]; visitors[player]=room
  player:SetAttribute('VisitingKitchen',room.id); player:SetAttribute('VisitingCafeIndex',room.index)
  local char=player.Character; local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then
   char:PivotTo(CFrame.new(room.origin+Vector3.new(0,3,19)))
   root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
  end
  if previous and previous~=room then cleanup(previous) end
 end
 local create
 local function sign(room,name,x,home)
  local position=room.origin+Vector3.new(x,2,22)
  local post=solid(room.model,name,Vector3.new(.25,3,.25),position-Vector3.new(0,.5,0))
  post.Transparency=0; post.Color=Color3.fromRGB(71,38,27)
  local board=solid(room.model,name..'Arrow',Vector3.new(3.6,1.3,.3),position+Vector3.new(0,1,0))
  board.Transparency=0; board.Color=Color3.fromRGB(255,194,64)
  local function stroke(offset,size,angle)
   local mark=solid(room.model,name..'Mark',size,board.Position+offset)
   mark.Transparency=0; mark.Color=post.Color; mark.CanCollide=false; mark.CanQuery=false
   mark.CFrame*=CFrame.Angles(0,0,angle or 0)
  end
  if home then
   stroke(Vector3.new(-.25,.22,.2),Vector3.new(.65,.13,.08),math.pi/4)
   stroke(Vector3.new(.25,.22,.2),Vector3.new(.65,.13,.08),-math.pi/4)
   stroke(Vector3.new(-.38,-.18,.2),Vector3.new(.13,.5,.08)); stroke(Vector3.new(.38,-.18,.2),Vector3.new(.13,.5,.08))
   stroke(Vector3.new(0,-.42,.2),Vector3.new(.88,.13,.08))
  else
   stroke(Vector3.new(0,0,.2),Vector3.new(1.8,.16,.08))
   stroke(Vector3.new(.65,.22,.2),Vector3.new(.7,.16,.08),-math.pi/4)
   stroke(Vector3.new(.65,-.22,.2),Vector3.new(.7,.16,.08),math.pi/4)
  end
  local prompt=Instance.new('ProximityPrompt'); prompt.Name=name..'Prompt'; prompt.ActionText=if home then 'Return home' else 'Next cafe'
  prompt.ObjectText='Infinite Chocolatier'; prompt.MaxActivationDistance=7; prompt.RequiresLineOfSight=false; prompt.Parent=board
  prompt.Triggered:Connect(function(player)
   local own=homes[player]; local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if not own or own.mode~='walk' or not root or (root.Position-board.Position).Magnitude>9 or visitors[player]~=room then return end
   local now=os.clock(); if now<(own.nextVisit or 0) then return end; own.nextVisit=now+.5
   if home then enter(player,own); return end
   local id=Queue.nextVisitor(records(),player.UserId,room.id)
   if not id then return end
   local target=byKey[Queue.key(id,0)]
   if not target or not target.owner then return end
   enter(player,target)
  end)
 end
 create=function(player,index,source)
  local id=player.UserId; local key=Queue.key(id,index)
  if byKey[key] then return byKey[key] end
  local slot=1; while slots[slot] do slot+=1 end
  local origin=Vector3.new((slot-1)*256,0,1000)
  local model=Instance.new('Model'); model.Name='KitchenRoom_'..id..(if index==0 then '' else '_'..index); model.Parent=directory
  local room={model=model,origin=origin,slot=slot,id=id,index=index,key=key,owner=player,count=0,mode='cut',hidden={}}
  slots[slot]=room; byKey[key]=room
  model:SetAttribute('OwnerId',id); model:SetAttribute('CafeIndex',index); model:SetAttribute('RoomKey',key); model:SetAttribute('Origin',origin)
  model:SetAttribute('DisplayName',player.DisplayName or tostring(id)); model:SetAttribute('Username',player.Name or tostring(id))
  model:SetAttribute('OwnerOnline',true); model:SetAttribute('CafeCount',0)
  model:SetAttribute('CycleSeconds',if source then source.model:GetAttribute('CycleSeconds') else 10)
  model:SetAttribute('HasApprentice',index>0)
  local foundation=solid(model,'Foundation',Vector3.new(22,1,24),origin+Vector3.new(0,-.85,5))
  foundation.Transparency=0; foundation.Color=Color3.fromRGB(194,173,142)
  local hall=solid(model,'HallFloor',Vector3.new(22,1,11),origin+Vector3.new(0,-.6,22.5))
  hall.Transparency=0; hall.Color=Color3.fromRGB(151,126,98)
  for _,boundary in {
   {Vector3.new(23,64,1),Vector3.new(0,31,28)}, {Vector3.new(23,64,1),Vector3.new(0,31,-7)},
   {Vector3.new(1,64,35),Vector3.new(-11,31,10.5)}, {Vector3.new(1,64,35),Vector3.new(11,31,10.5)},
  } do solid(model,'IslandBoundary',boundary[1],origin+boundary[2]) end
  solid(model,'Floor',Vector3.new(22,1,24),origin+Vector3.new(0,-.6,5))
  for _,wall in Structure.walls do solid(model,wall.name,Vector3.new(table.unpack(wall.size)),origin+Vector3.new(table.unpack(wall.position))) end
  for _,x in {-3.7,3.7} do solid(model,'Worktable',Vector3.new(6.8,2.3,5.8),origin+Vector3.new(x,1,0)) end
  solid(model,'Cabinets',Vector3.new(18,2.3,1.8),origin+Vector3.new(0,1,-5))
  sign(room,'NextCafe',6,false); sign(room,'HomeCafe',-6,true); refreshStaff()
  return room
 end
 local function mode(player,value)
  local room=homes[player]; if not room or (value~='walk' and value~='cut' and value~='watch') then return end
  if value=='cut' and visitors[player]~=room then enter(player,room) end
  room.mode=value; player:SetAttribute('KitchenMode',value)
  local char=player.Character
  if room.character~=char then room.character=char; room.hidden={} end
  if char then
   if value=='cut' then
    for _,p in char:GetDescendants() do if p:IsA('BasePart') or p:IsA('Decal') then
     if room.hidden[p]==nil then room.hidden[p]={transparency=p.Transparency,collide=p:IsA('BasePart') and p.CanCollide} end
     p.Transparency=1; if p:IsA('BasePart') then p.CanCollide=false end
    end end
   else
    for p,saved in room.hidden do if p.Parent then
     p.Transparency=saved.transparency; if p:IsA('BasePart') then p.CanCollide=saved.collide end
    end end
    room.hidden={}
   end
  end
  local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then root.Anchored=value~='walk'; root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
 end
 local elapsed=0
 RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt; if elapsed<.25 then return end; elapsed=0
  for player,own in homes do
   local room=visitors[player] or own; local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root then local p=root.Position-room.origin
    if p.Y< -8 or math.abs(p.X)>11 or p.Z< -7 or p.Z>28 then enter(player,room) end
   end
  end
 end)
 local function add(player)
  if homes[player] then return end
  local room=create(player,0); room.owner=player; room.mode='cut'; room.hidden={}
  room.model:SetAttribute('OwnerOnline',true); homes[player]=room; visitors[player]=room
  player:SetAttribute('VisitingKitchen',room.id); player:SetAttribute('VisitingCafeIndex',0)
  player:SetAttribute('KitchenMode','cut'); player:SetAttribute('KitchenOrigin',room.origin)
  refreshStaff()
  task.spawn(function()
   local friends={}
   local ok=pcall(function()
    if player.UserId<=0 then return end
    local pages=Players:GetFriendsAsync(player.UserId)
    while true do
     for _,friend in pages:GetCurrentPage() do if type(friend.Id)=='number' and friend.Id>0 then table.insert(friends,friend.Id) end end
     if pages.IsFinished then break end; pages:AdvanceToNextPageAsync()
    end
   end)
   if homes[player]~=room then return end
   pools[player.UserId]=if ok then friends else {}; refreshStaff()
  end)
  local function spawn()
   if not player.Parent or not homes[player] then return end
   local ok=pcall(function() player:LoadCharacterAsync() end)
   if not ok then task.delay(3,spawn); return end
   if not homes[player] or not player.Character then return end
   enter(player,visitors[player] or room); mode(player,room.mode)
  end
  player.CharacterAdded:Connect(function(char)
   local root=char:WaitForChild('HumanoidRootPart',10); local humanoid=char:FindFirstChildOfClass('Humanoid')
   if not root or not homes[player] then return end
   char:PivotTo(CFrame.new((visitors[player] or room).origin+Vector3.new(0,3,19))); mode(player,room.mode)
   if humanoid then humanoid.Died:Connect(function() task.delay(3,spawn) end) end
  end)
  task.spawn(spawn)
 end
 remote.OnServerEvent:Connect(mode); Players.PlayerAdded:Connect(add)
 Players.PlayerRemoving:Connect(function(player)
  local visiting=visitors[player]; homes[player]=nil; visitors[player]=nil
  local owned={}; for _,room in slots do if room.id==player.UserId then table.insert(owned,room) end end
  for _,room in owned do
   room.owner=nil; room.character=nil; room.hidden={}; room.model:SetAttribute('OwnerOnline',false); cleanup(room)
  end
  if visiting and visiting.id~=player.UserId then cleanup(visiting) end
  -- PlayerRemoving ещё видит уходящего в GetPlayers; освобождать его внешность
  -- немедленно необязательно, а вход нового друга исключает её синхронно.
  refreshStaff()
 end)
 for _,player in Players:GetPlayers() do add(player) end
 return {sync=function(_,player,state)
  local home=homes[player]; if not home then return end
  home.count=state.levels.cafes or 0; home.model:SetAttribute('CafeCount',home.count)
  for _,room in slots do if room.id==player.UserId then
   room.model:SetAttribute('CycleSeconds',state.cycleSeconds)
   room.model:SetAttribute('HasApprentice',if room.index==0 then state.owned.workers_1==true else true)
  end end
 end}
end
return Rooms
