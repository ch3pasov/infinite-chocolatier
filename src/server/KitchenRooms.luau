--!nonstrict
local Structure=require(game:GetService('ReplicatedStorage'):WaitForChild('Shared'):WaitForChild('KitchenStructure'))
-- Сервер держит пол и границы даже тогда, когда клиент смотрит на шоколадку.
-- Соседние рабочие места соединены общим проходом, а слоты переиспользуются.
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local RunService=game:GetService('RunService')
local Rooms={}
function Rooms.start(remote)
 local rooms={}; local slots={}
 local corridor=Instance.new('Model'); corridor.Name='SharedKitchenHall'; corridor.Parent=Workspace
 local function solid(parent,name,size,position)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=position
  p.Anchored=true; p.Transparency=1; p.CanCollide=true
  p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
  p.Material=Enum.Material.SmoothPlastic; p.Parent=parent
  return p
 end
 local capacity=math.max(1,Players.MaxPlayers or 50)
 local length=capacity*24
 -- Основание заканчивается у прохода: перекрывающиеся плиты давали
 -- совпадающие передние и боковые грани, мерцавшие при движении камеры.
 -- Общий пол остаётся и после ухода владельца комнаты.
 local foundation=solid(corridor,'Foundation',Vector3.new(length,1,24),Vector3.new(length/2-12,-.85,1005))
 foundation.Transparency=0; foundation.Color=Color3.fromRGB(194,173,142)
 -- Коридор начинается ровно у торца комнат (Z=1017), а фундамент ниже
 -- чистового пола: ни одна видимая поверхность не делит с ним плоскость.
 local floor=solid(corridor,'HallFloor',Vector3.new(length,1,11),Vector3.new(length/2-12,-.6,1022.5))
 floor.Transparency=0; floor.Color=Color3.fromRGB(151,126,98)
 -- Прозрачный внешний периметр не закрывает фиксированную камеру.
 -- Он окружает весь фундамент, включая промежутки и ещё пустые кухни.
 for _,wall in {
  {Vector3.new(length+1,64,1),Vector3.new(length/2-12,31,1028)},
  {Vector3.new(length+1,64,1),Vector3.new(length/2-12,31,993)},
  {Vector3.new(1,64,35),Vector3.new(-12,31,1010.5)},
  {Vector3.new(1,64,35),Vector3.new(length-12,31,1010.5)},
 } do solid(corridor,'HallBoundary',wall[1],wall[2]) end
 -- Страховка от провала физики/телепорта за край: возвращаем в свою кухню,
 -- не убивая персонажа и не сбрасывая экономику или раунд.
 local elapsed=0
 RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt; if elapsed<.25 then return end; elapsed=0
  for player,room in rooms do
   local char=player.Character
   local root=char and char:FindFirstChild('HumanoidRootPart')
   if root then
    local p=root.Position
    if p.Y< -8 or p.X< -12 or p.X>length-12 or p.Z<993 or p.Z>1028 then
     char:PivotTo(CFrame.new(room.origin+Vector3.new(0,3,8)))
     root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
    end
   end
  end
 end)
 local function mode(player,value)
  local room=rooms[player]; if not room then return end
  if value~='walk' and value~='cut' and value~='watch' then return end
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
  local slot=1; while slots[slot] do slot+=1 end
  slots[slot]=player
  local origin=Vector3.new((slot-1)*24,0,1000)
  local model=Instance.new('Model'); model.Name='KitchenRoom_'..player.UserId; model.Parent=Workspace
  solid(model,'Floor',Vector3.new(22,1,24),origin+Vector3.new(0,-.6,5))
  for _,wall in Structure.walls do
   solid(model,wall.name,Vector3.new(table.unpack(wall.size)),origin+Vector3.new(table.unpack(wall.position)))
  end
  for _,x in {-3.7,3.7} do solid(model,'Worktable',Vector3.new(6.8,2.3,5.8),origin+Vector3.new(x,1,0)) end
  solid(model,'Cabinets',Vector3.new(18,2.3,1.8),origin+Vector3.new(0,1,-5))
  rooms[player]={model=model,origin=origin,mode='cut',slot=slot,hidden={}}
  player:SetAttribute('KitchenMode','cut')
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
  if rooms[player] then slots[rooms[player].slot]=nil; rooms[player].model:Destroy(); rooms[player]=nil end
 end)
 for _,player in Players:GetPlayers() do add(player) end
end
return Rooms
