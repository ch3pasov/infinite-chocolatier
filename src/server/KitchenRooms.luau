--!nonstrict
-- Сервер держит пол и границы даже тогда, когда клиент смотрит на шоколадку.
-- Разнесённые комнаты пока приватные; это не имитация сетевых действий соседей.
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local Rooms={}
function Rooms.start(remote)
 local rooms={}; local nextSlot=0
 local function solid(parent,name,size,position)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=position
  p.Anchored=true; p.Transparency=1; p.CanCollide=true; p.Parent=parent
  return p
 end
 local function mode(player,value)
  local room=rooms[player]; if not room then return end
  if value~='walk' and value~='cut' and value~='watch' then return end
  room.mode=value
  local char=player.Character
  local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then
   root.Anchored=value~='walk'
   root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
  end
 end
 local function add(player)
  if rooms[player] then return end
  nextSlot+=1
  local origin=Vector3.new(nextSlot*80,0,1000)
  local model=Instance.new('Model'); model.Name='KitchenRoom_'..player.UserId; model.Parent=Workspace
  solid(model,'Floor',Vector3.new(22,1,24),origin+Vector3.new(0,-.6,5))
  for _,wall in {{Vector3.new(22,10,1),Vector3.new(0,4.5,-7)}, {Vector3.new(22,10,1),Vector3.new(0,4.5,17)}, {Vector3.new(1,10,24),Vector3.new(-11,4.5,5)}, {Vector3.new(1,10,24),Vector3.new(11,4.5,5)}} do solid(model,'Wall',wall[1],origin+wall[2]) end
  for _,x in {-3.7,3.7} do solid(model,'Worktable',Vector3.new(6.8,2.3,5.8),origin+Vector3.new(x,1,0)) end
  solid(model,'Cabinets',Vector3.new(18,2.3,1.8),origin+Vector3.new(0,1,-5))
  rooms[player]={model=model,origin=origin,mode='cut'}
  player:SetAttribute('KitchenOrigin',origin)
  local function spawn()
   if not player.Parent or not rooms[player] then return end
   local ok=pcall(function() player:LoadCharacterAsync() end)
   if not ok then task.delay(3,spawn); return end
   if not rooms[player] or not player.Character then return end
   -- LoadCharacterAsync сам устанавливает точку спавна после CharacterAdded.
   -- Наш окончательный перенос должен идти после завершения загрузки.
   player.Character:PivotTo(CFrame.new(origin+Vector3.new(0,3,8)))
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
  if rooms[player] then rooms[player].model:Destroy(); rooms[player]=nil end
 end)
 for _,player in Players:GetPlayers() do add(player) end
end
return Rooms
