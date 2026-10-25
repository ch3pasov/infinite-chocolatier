--!nonstrict
-- Сервер материализует только домашние и посещаемые кафе. Купленная очередь
-- задаётся числом: её длина не требует столько же моделей, связей и аватаров.
local Shared=game:GetService('ReplicatedStorage'):WaitForChild('Shared')
local Structure=require(Shared:WaitForChild('KitchenStructure'))
local Queue=require(Shared:WaitForChild('CafeQueue'))
local Roster=require(Shared:WaitForChild('StaffRoster'))
local Catalog=require(Shared:WaitForChild('KitchenCatalog'))
local Players=game:GetService('Players')
local Workspace=game:GetService('Workspace')
local RunService=game:GetService('RunService')
local PhysicsService=game:GetService('PhysicsService')
local avatarGroup='ChocolateAvatars'
local Rooms={}
function Rooms.start(remote,visitRemote)
 -- На месте входа остаётся скрытый аватар режущего хозяина. Humanoid может
 -- восстановить коллизии тела; группа исключает опору на него и на гостей,
 -- сохраняя обычное столкновение с полом, мебелью и границами острова.
 if not PhysicsService:IsCollisionGroupRegistered(avatarGroup) then PhysicsService:RegisterCollisionGroup(avatarGroup) end
 PhysicsService:CollisionGroupSetCollidable(avatarGroup,avatarGroup,false)
 local homes,slots,visitors,byKey,pools={},{},{},{},{}
 local leaving={}
 local function onlinePlayers()
  local online={}
  for _,player in Players:GetPlayers() do if not leaving[player.UserId] then online[player.UserId]=true end end
  for player in homes do online[player.UserId]=true end
  return online
 end
 local socialChanged
 local function notify() if socialChanged then socialChanged() end end
 local function invalidateWatch(player)
  local home=homes[player]
  if home then home.watchTarget=nil; home.socialEpoch=(home.socialEpoch or 0)+1 end
 end
 local function hide(room,part)
  if not part:IsA('BasePart') and not part:IsA('Decal') then return end
  if room.hidden[part]==nil then
   room.hidden[part]={transparency=part.Transparency,collide=part:IsA('BasePart') and part.CanCollide}
   -- Клиент клонирует готовый аватар для стола, поэтому временную маску
   -- передаём отдельно от настоящей прозрачности тела и аксессуаров.
   part:SetAttribute('KitchenOriginalTransparency',part.Transparency)
  end
  part.Transparency=1
  if part:IsA('BasePart') then part.CanCollide=false end
 end
 local function atTable(player,room)
  local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
  if not root then return false end
  local p=root.Position-room.origin
  -- Передняя сторона левого, ручного стола; правый принадлежит стажёру.
  return math.abs(p.X+3.7)<=4 and p.Z>=2.9 and p.Z<=8 and p.Y>=0 and p.Y<=7
 end
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
  for _,other in slots do if other.id==room.id then return true end end
  pools[room.id]=nil
  return true
 end
 local function refreshStaff()
  local online=onlinePlayers()
  local capacities,choices={},{}
  for _,home in slots do if home.index==0 then choices[home.id]=home.apprenticeUserId end end
  for _,room in slots do if room.model:GetAttribute('HasApprentice') then
   -- После ухода владельца в очереди остаются только комнаты с гостями.
   -- Исчезнувшие покупные кафе больше не должны удерживать общих друзей.
   local capacity=if room.index>0 then room.index*2+1 elseif room.owner then 1+room.count*2 else 1
   capacities[room.id]=math.max(capacities[room.id] or 0,capacity)
  end end
  local rosters=Roster.build(pools,online,capacities,choices)
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
 local function enter(player,room)
  invalidateWatch(player)
  local previous=visitors[player]; visitors[player]=room
  player:SetAttribute('VisitingKitchen',room.id); player:SetAttribute('VisitingCafeIndex',room.index)
  local char=player.Character; local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then
   char:PivotTo(CFrame.new(room.origin+Vector3.new(0,3,12)))
   root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero
  end
  if previous and previous~=room and cleanup(previous) then refreshStaff() end
  notify()
 end
 local create
 local function sign(room,name,x)
  local position=room.origin+Vector3.new(x,2,11)
  local rotation=CFrame.Angles(0,if x<0 then math.pi/2 else -math.pi/2,0)
  local board=solid(room.model,name..'Arrow',Vector3.new(3.6,1.3,.3),position+Vector3.new(0,1,0))
  board.CFrame=CFrame.new(board.Position)*rotation
  board.Transparency=0; board.Color=Color3.fromRGB(255,194,64)
  local function stroke(offset,size,angle)
   local mark=solid(room.model,name..'Mark',size,board.Position+offset)
   mark.Transparency=0; mark.Color=Color3.fromRGB(71,38,27); mark.CanCollide=false; mark.CanQuery=false
   mark.CFrame=board.CFrame*CFrame.new(offset)*CFrame.Angles(0,0,angle or 0)
  end
  stroke(Vector3.new(0,0,.2),Vector3.new(1.8,.16,.08))
  stroke(Vector3.new(.65,.22,.2),Vector3.new(.7,.16,.08),-math.pi/4)
  stroke(Vector3.new(.65,-.22,.2),Vector3.new(.7,.16,.08),math.pi/4)
  local prompt=Instance.new('ProximityPrompt'); prompt.Name=name..'Prompt'; prompt.ActionText='Choose a cafe'
  prompt.ObjectText='Infinite Chocolatier'; prompt.MaxActivationDistance=7; prompt.RequiresLineOfSight=false; prompt.Parent=board
  prompt.Triggered:Connect(function(player)
   local own=homes[player]; local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if not own or own.mode~='walk' or not root or (root.Position-board.Position).Magnitude>9 or visitors[player]~=room then return end
   local now=os.clock(); if now<(own.nextVisit or 0) then return end
   if now<(own.nextDirectory or 0) then return end
   own.nextDirectory=now+.5; visitRemote:FireClient(player,'open')
  end)
 end
 -- Выбор из меню не даёт обходить физическую стрелку, режим прогулки
 -- или уход владельца. Возвращение домой проходит те же проверки.
 visitRemote.OnServerEvent:Connect(function(player,id)
  if type(id)~='number' or id~=id or id==math.huge or id%1~=0 then return end
  local own=homes[player]; local room=visitors[player]
  local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
  local board=room and room.model:FindFirstChild('NextCafeArrow')
  if not own or own.mode~='walk' or not root or not board or (root.Position-board.Position).Magnitude>9 then
   visitRemote:FireClient(player,'close'); return
  end
  local target=byKey[Queue.key(id,0)]
  if target==room then visitRemote:FireClient(player,'close'); return end
  local now=os.clock(); if now<(own.nextVisit or 0) then return end; own.nextVisit=now+.5
  if not target or not target.owner then visitRemote:FireClient(player,'unavailable'); return end
  enter(player,target); visitRemote:FireClient(player,'arrived')
 end)
 create=function(player,index,source)
  local id=player.UserId; local key=Queue.key(id,index)
  if byKey[key] then return byKey[key] end
  local slot=1; while slots[slot] do slot+=1 end
  local origin=Vector3.new((slot-1)*256,0,1000)
  local model=Instance.new('Model'); model.Name='KitchenRoom_'..id..(if index==0 then '' else '_'..index); model.Parent=directory
  local room={model=model,origin=origin,slot=slot,id=id,index=index,key=key,owner=player,count=0,mode='cut',hidden={},friends={}}
  slots[slot]=room; byKey[key]=room
  model:SetAttribute('OwnerId',id); model:SetAttribute('CafeIndex',index); model:SetAttribute('RoomKey',key); model:SetAttribute('Origin',origin)
  model:SetAttribute('DisplayName',player.DisplayName or tostring(id)); model:SetAttribute('Username',player.Name or tostring(id))
  model:SetAttribute('OwnerOnline',true); model:SetAttribute('CafeCount',0)
  model:SetAttribute('CycleSeconds',if source then source.model:GetAttribute('CycleSeconds') else 10)
  model:SetAttribute('HasApprentice',index>0)
  -- Видимое основание принадлежит клиентской оболочке, иначе две одинаковые
  -- поверхности снова мерцают. Здесь остаётся только физическая опора.
  for name,spec in {Foundation=Structure.foundation,Floor=Structure.floor} do
   solid(model,name,Vector3.new(table.unpack(spec.size)),origin+Vector3.new(table.unpack(spec.position)))
  end
  for _,boundary in {
   {Vector3.new(23,64,1),Vector3.new(0,31,17)}, {Vector3.new(23,64,1),Vector3.new(0,31,-7)},
   {Vector3.new(1,64,24),Vector3.new(-11,31,5)}, {Vector3.new(1,64,24),Vector3.new(11,31,5)},
  } do solid(model,'IslandBoundary',boundary[1],origin+boundary[2]) end
  for _,wall in Structure.walls do solid(model,wall.name,Vector3.new(table.unpack(wall.size)),origin+Vector3.new(table.unpack(wall.position))) end
  for _,x in {-3.7,3.7} do solid(model,'Worktable',Vector3.new(6.8,2.3,5.8),origin+Vector3.new(x,1,0)) end
  solid(model,'Cabinets',Vector3.new(18,2.3,1.8),origin+Vector3.new(0,1,-5))
  sign(room,'NextCafe',10.25); refreshStaff()
  return room
 end
 local function mode(player,value,targetId,side)
  local room=homes[player]; if not room or (value~='walk' and value~='cut' and value~='watch') then return end
  local visited=visitors[player]
  local target=if value=='watch' and room.mode=='walk' and side==1 and visited and visited.index==0
   and visited.owner and visited.owner~=player and visited.id==targetId and atTable(player,visited) then visited.owner else nil
  invalidateWatch(player); room.watchTarget=target
  if value=='cut' and visitors[player]~=room then enter(player,room) end
  room.mode=value; player:SetAttribute('KitchenMode',value)
  local char=player.Character
  if room.character~=char then room.character=char; room.hidden={} end
  if char then
   if value=='cut' then
    for _,p in char:GetDescendants() do hide(room,p) end
   else
    for p,saved in room.hidden do if p.Parent then
     p.Transparency=saved.transparency; if p:IsA('BasePart') then p.CanCollide=saved.collide end
     p:SetAttribute('KitchenOriginalTransparency',nil)
    end end
    room.hidden={}
   end
  end
  local root=char and char:FindFirstChild('HumanoidRootPart')
  if root then root.Anchored=value~='walk'; root.AssemblyLinearVelocity=Vector3.zero; root.AssemblyAngularVelocity=Vector3.zero end
  notify()
 end
 local elapsed=0
 RunService.Heartbeat:Connect(function(dt)
  elapsed+=dt; if elapsed<.25 then return end; elapsed=0
  for player,own in homes do
   local room=visitors[player] or own; local root=player.Character and player.Character:FindFirstChild('HumanoidRootPart')
   if root then local p=root.Position-room.origin
    if p.Y< -8 or math.abs(p.X)>11 or p.Z< -7 or p.Z>17 then enter(player,room) end
    if own.watchTarget and not atTable(player,room) then invalidateWatch(player) end
   end
  end
  notify()
 end)
 local function add(player)
  if homes[player] then return end
  leaving[player.UserId]=nil
  local room=create(player,0); room.owner=player; room.mode='cut'; room.hidden={}
  room.model:SetAttribute('OwnerOnline',true); homes[player]=room; visitors[player]=room
  player:SetAttribute('VisitingKitchen',room.id); player:SetAttribute('VisitingCafeIndex',0)
  player:SetAttribute('KitchenMode','cut'); player:SetAttribute('KitchenOrigin',room.origin)
  refreshStaff()
  local function loadFriends(attempt)
   if homes[player]~=room then return end
   local friends,details={},{}
   local ok,err=pcall(function()
    if player.UserId<=0 then return end
    local pages=Players:GetFriendsAsync(player.UserId)
    while true do
     for _,friend in pages:GetCurrentPage() do if type(friend.Id)=='number' and friend.Id>0 and friend.Id~=player.UserId then
      table.insert(friends,friend.Id)
      details[friend.Id]={id=friend.Id,name=friend.Username or tostring(friend.Id),displayName=friend.DisplayName or friend.Username or tostring(friend.Id)}
     end end
     if pages.IsFinished then break end; pages:AdvanceToNextPageAsync()
    end
   end)
   if homes[player]~=room then return end
   -- Неполный ответ добавляет подтверждённых друзей, но не отменяет
   -- прежних: отсутствие на первой странице ещё не означает удаление.
   -- Только полный список заменяет старый и применяет разрыв дружбы.
   if not ok then
    local seen={}; local merged=table.clone(pools[player.UserId] or {})
    for _,id in merged do seen[id]=true end
    for _,id in friends do if not seen[id] then seen[id]=true; table.insert(merged,id) end end
    friends=merged
    for id,detail in room.friendDetails or {} do if not details[id] then details[id]=detail end end
   end
   room.friendDetails=details
   pools[player.UserId]=friends
   -- Проверки зрителей идут на каждом этапе и несколько раз в секунду.
   -- Индекс строится только при обновлении API, а не сканирует весь список
   -- друзей для каждой пары игроков в серверном цикле.
   room.friends={}; for _,id in friends do room.friends[id]=true end
   room.model:SetAttribute('FriendListStatus',if ok then 'ready' else 'retrying')
   refreshStaff(); notify()
   if ok then task.delay(120,function() loadFriends(0) end) end
   if not ok then
    warn('Apprentice friends '..player.UserId..': '..tostring(err))
    if attempt<3 then task.delay(({5,20,60})[attempt+1],function() loadFriends(attempt+1) end)
    else
     room.model:SetAttribute('FriendListStatus','unavailable')
     task.delay(120,function() loadFriends(0) end)
    end
   end
  end
  task.spawn(function() loadFriends(0) end)
  local function spawn()
   if not player.Parent or not homes[player] then return end
   local ok=pcall(function() player:LoadCharacterAsync() end)
   if not ok then task.delay(3,spawn); return end
   if not homes[player] or not player.Character then return end
   enter(player,visitors[player] or room); mode(player,room.mode)
  end
  local function clearCollisionBinding()
   invalidateWatch(player); notify()
   if room.collisionAdded then room.collisionAdded:Disconnect(); room.collisionAdded=nil end
  end
  player.CharacterRemoving:Connect(clearCollisionBinding)
  local avatarRevision=0
  player.CharacterAppearanceLoaded:Connect(function(char)
   if homes[player]~=room or player.Character~=char then return end
   char:SetAttribute('AvatarReady',true)
   avatarRevision+=1; player:SetAttribute('AvatarRevision',avatarRevision)
  end)
  player.CharacterAdded:Connect(function(char)
   clearCollisionBinding()
   room.character=char; room.hidden={}
   local function collision(part)
    if homes[player]~=room or player.Character~=char then return end
    if part:IsA('BasePart') then part.CollisionGroup=avatarGroup end
    -- Одежда и аксессуары могут прийти после CharacterAdded и mode(cut).
    -- Сохраняем их собственную прозрачность до маски, иначе они останутся
    -- парить у стола или не восстановятся при возвращении к прогулке.
    if room.mode=='cut' then hide(room,part) end
   end
   room.collisionAdded=char.DescendantAdded:Connect(collision)
   for _,part in char:GetDescendants() do collision(part) end
   local root=char:WaitForChild('HumanoidRootPart',10); local humanoid=char:FindFirstChildOfClass('Humanoid')
   if not root or homes[player]~=room or player.Character~=char then return end
   char:PivotTo(CFrame.new((visitors[player] or room).origin+Vector3.new(0,3,12))); mode(player,room.mode)
   if humanoid then
    -- Клиент отдельно отключает этот же режим: настройка не реплицируется.
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing,false)
    humanoid.Died:Connect(function()
     if homes[player]~=room or player.Character~=char then return end
     invalidateWatch(player); notify(); task.delay(3,spawn)
    end)
   end
  end)
  task.spawn(spawn)
 end
 remote.OnServerEvent:Connect(function(player,value,targetId,side)
  local home=homes[player]
  -- Повтор команды не означает выход из режима: иначе он обнуляет эпоху
  -- непрерывного наблюдения и лишний раз пересчитывает весь сервер.
  -- watch без прежней цели по-прежнему может открыть примерку и снять зрителя.
  if home and home.mode==value then
   if value~='watch' or not home.watchTarget or (side==1 and targetId==home.watchTarget.UserId) then return end
  end
  mode(player,value,targetId,side)
 end)
 -- Внутренний mode после спавна всегда применяется заново: движок мог
 -- завершить размещение и сбросить Anchored уже после CharacterAdded.
 Players.PlayerAdded:Connect(add)
 Players.PlayerRemoving:Connect(function(player)
  leaving[player.UserId]=true
  local visiting=visitors[player]; local home=homes[player]
  if home and home.collisionAdded then home.collisionAdded:Disconnect(); home.collisionAdded=nil end
  homes[player]=nil; visitors[player]=nil
  local owned={}; for _,room in slots do if room.id==player.UserId then table.insert(owned,room) end end
  for _,room in owned do
   room.owner=nil; room.character=nil; room.hidden={}; room.model:SetAttribute('OwnerOnline',false); cleanup(room)
  end
  if visiting and visiting.id~=player.UserId then cleanup(visiting) end
  -- GetPlayers ещё содержит уходящего. Исключение возвращает личный выбор
  -- сразу, без ожидания нового входа или фонового обновления друзей.
  refreshStaff(); notify()
 end)
 for _,player in Players:GetPlayers() do add(player) end
 local function isFriend(owner,guest)
  return homes[owner]~=nil and homes[guest]~=nil and owner~=guest
   and homes[owner].friends[guest.UserId]==true
 end
 return {onSocialChange=function(_,callback) socialChanged=callback end,
 friendStatus=function(_,player)
  local home=homes[player]
  return if home then home.model:GetAttribute('FriendListStatus') or 'loading' else 'loading'
 end,
 canChooseStaff=function(_,player,id)
  local home=homes[player]
  return home~=nil and (id==0 or (home.friends[id]==true and not onlinePlayers()[id]))
 end,
 staffPage=function(_,player,query,page)
  local home=homes[player]; if not home then return {items={},page=1,pages=1,total=0,status='loading'} end
  local result=Roster.page(pools[player.UserId],onlinePlayers(),home.friendDetails or {},query,page)
  result.status=home.model:GetAttribute('FriendListStatus') or 'loading'
  result.current=home.model:GetAttribute('Staff1') or 0
  result.selected=home.apprenticeUserId or 0
  result.selectedName=(home.friendDetails or {})[result.selected]
  return result
 end,
 isFriend=function(_,owner,guest) return isFriend(owner,guest) end,
 hasOnlineFriend=function(_,owner)
  for guest in homes do if isFriend(owner,guest) then return true end end
  return false
 end,
 visits=function()
  local result={}
  for guest,room in visitors do
   if room.index==0 and room.owner and homes[guest] and guest~=room.owner then
    table.insert(result,{owner=room.owner,guest=guest})
   end
  end
  return result
 end,
 manualContext=function(_,player)
  local home=homes[player]
  local char=player.Character; local root=char and char:FindFirstChild('HumanoidRootPart')
  local hum=char and char:FindFirstChildOfClass('Humanoid')
  if not root or not hum or (hum.Health and hum.Health<=0) then return nil end
  return if home and home.mode=='cut' and visitors[player]==home then (home.socialEpoch or 0) else nil
 end,
 watching=function(_,owner,guest)
  local home=homes[guest]; local room=visitors[guest]
  if not home or not room or not homes[owner] or room.owner~=owner or room.index~=0
   or home.mode~='watch' or home.watchTarget~=owner or not atTable(guest,room) then return nil end
  local char=guest.Character; local humanoid=char and char:FindFirstChildOfClass('Humanoid')
  -- Одна позиция корня ещё не подтверждает живого зрителя во время спавна.
  if not humanoid or (humanoid.Health and humanoid.Health<=0) then return nil end
  return home.socialEpoch
 end,
 visiblePlayers=function(_,player)
  local current=visitors[player] or homes[player]; if not current then return {} end
  local records={}
  for _,room in slots do
   table.insert(records,{owner=room.id,index=room.index,online=room.owner~=nil,count=room.count})
  end
  return Queue.animatedPlayers(Queue.build(records),current.id,current.index,player.UserId)
 end,sync=function(_,player,state)
  local home=homes[player]; if not home then return end
  local count=state.levels.cafes or 0; local hired=state.owned.workers_1==true
  local selected=state.apprenticeUserId or 0
  local staffChanged=home.count~=count or home.model:GetAttribute('HasApprentice')~=hired or home.apprenticeUserId~=selected
  home.apprenticeUserId=selected
  home.count=count; home.model:SetAttribute('CafeCount',home.count)
  local appearance=Catalog.appearance(state)
  if home.model:GetAttribute('CafeAppearance')~=appearance then home.model:SetAttribute('CafeAppearance',appearance) end
  for _,room in slots do if room.id==player.UserId then
   room.model:SetAttribute('CycleSeconds',state.cycleSeconds)
   room.model:SetAttribute('HasApprentice',if room.index==0 then hired else true)
  end end
  if staffChanged then refreshStaff() end
 end}
end
return Rooms
