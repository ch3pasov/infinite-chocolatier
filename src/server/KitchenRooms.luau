--!nonstrict
local Structure=require(game:GetService('ReplicatedStorage'):WaitForChild('Shared'):WaitForChild('KitchenStructure'))
-- Сервер держит пол и границы даже тогда, когда клиент смотрит на шоколадку.
-- Каждый остров имеет свою площадку; слот освобождается лишь без владельца и гостей.
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local RunService=game:GetService('RunService')
local Rooms={}
function Rooms.start(remote)
 local rooms={}; local slots={}; local visitors={}
 local directory=Instance.new('Folder'); directory.Name='KitchenIslands'; directory.Parent=Workspace
 local function solid(parent,name,size,position)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=position
  p.Anchored=true; p.Transparency=1; p.CanCollide=true
  p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
  p.Material=Enum.Material.SmoothPlastic; p.Parent=parent
  return p
 end
 local function cleanup(room)
  if room.owner then return end
  for _,visiting in visitors do if visiting==room then return end end
  slots[room.slot]=nil; room.model:Destroy()
 end
 local function enter(player,room)
  local previous=visitors[player]
  visitors[player]=room; player:SetAttribute('VisitingKitchen',room.id)
  local char=player.Character
  local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then
   char:PivotTo(CFrame.new(room.origin+Vector3.new(0,3,19)))
   root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
  end
  if previous and previous~=room then cleanup(previous) end
 end
 local function sign(room,name,x,home)
  local position=room.origin+Vector3.new(x,2,22)
  local post=solid(room.model,name,Vector3.new(.25,3,.25),position-Vector3.new(0,.5,0))
  post.Transparency=0; post.Color=Color3.fromRGB(71,38,27)
  local board=solid(room.model,name..'Arrow',Vector3.new(3.6,1.3,.3),position+Vector3.new(0,1,0))
  board.Transparency=0; board.Color=Color3.fromRGB(255,194,64)
  -- Объёмные пиктограммы не зависят от поддержки символов шрифтом.
  local function stroke(offset,size,angle)
   local mark=solid(room.model,name..'Mark',size,board.Position+offset)
   mark.Transparency=0; mark.Color=post.Color; mark.CanCollide=false; mark.CanQuery=false
   mark.CFrame*=CFrame.Angles(0,0,angle or 0)
  end
  if home then
   stroke(Vector3.new(-.25,.22,.2),Vector3.new(.65,.13,.08),math.pi/4)
   stroke(Vector3.new(.25,.22,.2),Vector3.new(.65,.13,.08),-math.pi/4)
   stroke(Vector3.new(-.38,-.18,.2),Vector3.new(.13,.5,.08))
   stroke(Vector3.new(.38,-.18,.2),Vector3.new(.13,.5,.08))
   stroke(Vector3.new(0,-.42,.2),Vector3.new(.88,.13,.08))
  else
   stroke(Vector3.new(0,0,.2),Vector3.new(1.8,.16,.08))
   stroke(Vector3.new(.65,.22,.2),Vector3.new(.7,.16,.08),-math.pi/4)
   stroke(Vector3.new(.65,-.22,.2),Vector3.new(.7,.16,.08),math.pi/4)
  end
  local prompt=Instance.new('ProximityPrompt'); prompt.Name=name..'Prompt'; prompt.ActionText=if home then 'Return home' else 'Next cafe'
  prompt.ObjectText='Infinite Chocolatier'; prompt.MaxActivationDistance=7; prompt.RequiresLineOfSight=false; prompt.Parent=board
  prompt.Triggered:Connect(function(player)
   local own=rooms[player]; local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   -- Даже поддельный вызов не переносит удалённого или занятого игрока.
   if not own or own.mode~='walk' or not root or (root.Position-board.Position).Magnitude>9 then return end
   if visitors[player]~=room then return end
   local now=os.clock(); if now<(own.nextVisit or 0) then return end
   own.nextVisit=now+.5
   if home then enter(player,own); return end
   local nextRoom
   for slot,candidate in slots do
    if candidate~=room and slot>room.slot and (not nextRoom or slot<nextRoom.slot) then nextRoom=candidate end
   end
   if not nextRoom then
    for slot,candidate in slots do if candidate~=room and (not nextRoom or slot<nextRoom.slot) then nextRoom=candidate end end
   end
   if nextRoom then enter(player,nextRoom) end
  end)
 end
 local elapsed=0
 RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt; if elapsed<.25 then return end; elapsed=0
  for player,own in rooms do
   local room=visitors[player] or own
   local char=player.Character; local root=char and char:FindFirstChild('HumanoidRootPart')
   if root then
    local p=root.Position-room.origin
    if p.Y< -8 or math.abs(p.X)>11 or p.Z< -7 or p.Z>28 then enter(player,room) end
   end
  end
 end)
 local function mode(player,value)
  local room=rooms[player]; if not room then return end
  if value~='walk' and value~='cut' and value~='watch' then return end
  if value=='cut' and visitors[player]~=room then enter(player,room) end
  room.mode=value
  player:SetAttribute('KitchenMode',value)
  -- За рабочим столом виден анимированный дубль, а настоящий аватар скрыт.
  -- Сохранённые значения возвращаются при прогулке, включая аксессуары.
  local char=player.Character
  if room.character~=char then room.character=char; room.hidden={} end
  if char then
   if value=='cut' then
    for _,p in char:GetDescendants() do
     if p:IsA('BasePart') or p:IsA('Decal') then
      if room.hidden[p]==nil then room.hidden[p]={transparency=p.Transparency,collide=p:IsA('BasePart') and p.CanCollide} end
      p.Transparency=1
      if p:IsA('BasePart') then p.CanCollide=false end
     end
    end
   else
    for p,saved in room.hidden do if p.Parent then
     p.Transparency=saved.transparency
     if p:IsA('BasePart') then p.CanCollide=saved.collide end
    end end
    room.hidden={}
   end
  end
  local char=player.Character
  local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then
   root.Anchored=value~='walk'
   root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
  end
 end
 local function add(player)
  if rooms[player] then return end
  local retained
  for _,candidate in slots do if candidate.id==player.UserId then retained=candidate; break end end
  local slot=1; while slots[slot] do slot+=1 end
  if retained then slot=retained.slot end
  local origin=Vector3.new((slot-1)*256,0,1000)
  local model
  if not retained then
  model=Instance.new('Model'); model.Name='KitchenRoom_'..player.UserId; model.Parent=directory
  model:SetAttribute('OwnerId',player.UserId); model:SetAttribute('Origin',origin)
  model:SetAttribute('DisplayName',player.DisplayName or tostring(player.UserId))
  model:SetAttribute('Username',player.Name or tostring(player.UserId)); model:SetAttribute('OwnerOnline',true)
  local foundation=solid(model,'Foundation',Vector3.new(22,1,24),origin+Vector3.new(0,-.85,5))
  foundation.Transparency=0; foundation.Color=Color3.fromRGB(194,173,142)
  local hall=solid(model,'HallFloor',Vector3.new(22,1,11),origin+Vector3.new(0,-.6,22.5))
  hall.Transparency=0; hall.Color=Color3.fromRGB(151,126,98)
  for _,boundary in {
   {Vector3.new(23,64,1),Vector3.new(0,31,28)},
   {Vector3.new(23,64,1),Vector3.new(0,31,-7)},
   {Vector3.new(1,64,35),Vector3.new(-11,31,10.5)},
   {Vector3.new(1,64,35),Vector3.new(11,31,10.5)},
  } do solid(model,'IslandBoundary',boundary[1],origin+boundary[2]) end
  solid(model,'Floor',Vector3.new(22,1,24),origin+Vector3.new(0,-.6,5))
  for _,wall in Structure.walls do
   solid(model,wall.name,Vector3.new(table.unpack(wall.size)),origin+Vector3.new(table.unpack(wall.position)))
  end
  for _,x in {-3.7,3.7} do solid(model,'Worktable',Vector3.new(6.8,2.3,5.8),origin+Vector3.new(x,1,0)) end
  solid(model,'Cabinets',Vector3.new(18,2.3,1.8),origin+Vector3.new(0,1,-5))
  else model=retained.model end
  local room=retained or {model=model,origin=origin,slot=slot,id=player.UserId}
  room.mode='cut'; room.hidden={}; room.owner=player
  model:SetAttribute('OwnerOnline',true)
  rooms[player]=room; slots[slot]=room; visitors[player]=room
  player:SetAttribute('VisitingKitchen',room.id)
  if not retained then sign(room,'NextCafe',6,false); sign(room,'HomeCafe',-6,true) end
  player:SetAttribute('KitchenMode','cut')
  player:SetAttribute('KitchenOrigin',origin)
  local function spawn()
   if not player.Parent or not rooms[player] then return end
   local ok=pcall(function() player:LoadCharacterAsync() end)
   if not ok then task.delay(3,spawn); return end
   if not rooms[player] or not player.Character then return end
   -- LoadCharacterAsync сам устанавливает точку спавна после CharacterAdded.
   -- Наш окончательный перенос должен идти после завершения загрузки.
   enter(player,visitors[player] or rooms[player])
   mode(player,rooms[player].mode)
  end
  player.CharacterAdded:Connect(function(char)
   local root=char:WaitForChild('HumanoidRootPart',10)
   local humanoid=char:FindFirstChildOfClass('Humanoid')
   if not root or not rooms[player] then return end
   char:PivotTo(CFrame.new(origin+Vector3.new(0,3,8)))
   mode(player,rooms[player].mode)
   if humanoid then humanoid.Died:Connect(function()
    task.delay(3,spawn)
   end) end
  end)
  task.spawn(spawn)
 end
 remote.OnServerEvent:Connect(mode)
 Players.PlayerAdded:Connect(add)
 Players.PlayerRemoving:Connect(function(player)
  local own=rooms[player]; local visiting=visitors[player]
  rooms[player]=nil; visitors[player]=nil
  if own then
   own.owner=nil; own.character=nil; own.hidden={}
   own.model:SetAttribute('OwnerOnline',false); cleanup(own)
  end
  if visiting and visiting~=own then cleanup(visiting) end
 end)
 for _,player in Players:GetPlayers() do add(player) end
end
return Rooms
