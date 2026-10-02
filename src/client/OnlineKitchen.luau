--!nonstrict
-- Живые игроки используют сетевые позы; автоматические кафе — общий цикл
-- стажёра. В памяти только посещённые острова и ограниченная дальняя очередь.
local Workspace=game:GetService('Workspace')
local Players=game:GetService('Players')
local Shared=game:GetService('ReplicatedStorage'):WaitForChild('Shared')
local Wire=require(Shared.WorkstationWire)
local Queue=require(Shared.CafeQueue)
local Roster=require(Shared.StaffRoster)
local Catalog=require(Shared.KitchenCatalog)
local Config=require(Shared.Config)
local Structure=require(Shared.KitchenStructure)
local Action=require(script.Parent.WorkstationAction)
local Station=require(script.Parent.WorkstationView)
local Shell=require(script.Parent.KitchenShell)
local Decor=require(script.Parent.KitchenDecor)
local L=require(script.Parent.Localization)
local Online={}; Online.__index=Online
local function transparency(part,value)
 if part.LocalTransparencyModifier~=value then part.LocalTransparencyModifier=value end
end
function Online.new(kitchen)
 local self=setmetatable({kitchen=kitchen,peers={},packets={},cycles={},elapsed=0,scan=0,request=0},Online)
 self.remote=kitchen.atelier.remotes.kitchenAction
 self.receive=self.remote.OnClientEvent:Connect(function(userId,raw)
  local clean=Wire.clean(raw); if not clean then return end
  local old=self.packets[userId]; self.packets[userId]={previous=old and old.current,current=clean,at=os.clock()}
 end)
 self.remote:FireServer(); return self
end
function Online:blockPrompts()
 -- Домашняя стрелка выполняется сервером напрямую: её нужно выключить
 -- сразу при открытии окна, не дожидаясь следующего опроса островов.
 for _,peer in self.peers do peer.prompt.Enabled=false end
 local directory=Workspace:FindFirstChild('KitchenIslands')
 for _,model in if directory then directory:GetChildren() else {} do
  for _,part in model:GetDescendants() do if part:IsA('ProximityPrompt') then part.Enabled=false end end
 end
end
function Online:releaseStations(peer)
 for _,station in peer.stations do station:destroy() end
 peer.stations={}; peer.station=nil
end
function Online:remove(key)
 local peer=self.peers[key]; if not peer then return end
 if self.kitchen.watchPeer==peer then self.kitchen:setWalking() end
 self:releaseStations(peer)
 peer.world:Destroy(); self.peers[key]=nil
end
function Online:add(model)
 local k=self.kitchen; local id=model:GetAttribute('OwnerId'); local index=model:GetAttribute('CafeIndex') or 0
 local key=Queue.key(id,index); local origin=model:GetAttribute('Origin')
 local world=Instance.new('Model'); world.Name='Neighbor_'..key; world.Parent=k.world; Shell.new(world,origin)
 local author={UserId=id,DisplayName=model:GetAttribute('DisplayName'),Name=model:GetAttribute('Username')}
 function author:GetAttribute(name)
  local player=Players:GetPlayerByUserId(id)
  return if model:GetAttribute('OwnerOnline') and player and player.Parent then player:GetAttribute(name) else nil
 end
 local peer={player=author,origin=origin,world=world,model=model,staff=index>0,index=index,stations={}}
 self.peers[key]=peer
 if peer.staff then Decor.update(peer,Queue.decor(id,index)) end
 local anchor=Instance.new('Part'); anchor.Name='PlayerWorktable'; anchor.Anchored=true
 anchor.CanCollide=false; anchor.Transparency=1; anchor.Size=Vector3.one; anchor.Position=origin+Vector3.new(-3.7,2.5,3); anchor.Parent=world
 local prompt=Instance.new('ProximityPrompt'); prompt.ActionText=L.text(if peer.staff then 'Watch apprentices' else 'Watch player')
 prompt.ObjectText=author.DisplayName..(if peer.staff then ' · '..index else ' (@'..author.Name..')')
 prompt.MaxActivationDistance=5; prompt.RequiresLineOfSight=false; prompt.HoldDuration=0; prompt.ClickablePrompt=true; prompt.Enabled=false; prompt.Parent=anchor; peer.prompt=prompt
 prompt.Triggered:Connect(function() if k:canWalk() and peer.station then k:watchPlayer(peer) end end)
 return peer
end
function Online:clearQueue()
 for _,entry in self.queueStations or {} do entry.station:destroy() end
 self.queueStations={}; self.queueDecor={}; self.queueRooms={}; self.queueKey=nil; self.queueAnchor=nil
 if self.queue then self.queue:Destroy(); self.queue=nil end
end
function Online:updateDecor(room,source)
 local raw=source:GetAttribute('CafeAppearance') or ''
 if room.appearanceKey==raw then return end
 room.appearanceKey=raw
 Decor.update(room,Catalog.fromAppearance(raw))
end
function Online:refreshQueueDecor(sources)
 for _,room in self.queueDecor or {} do
  local source=sources[room.owner]
  if source then self:updateDecor(room,source) end
 end
end
function Online:refreshQueueStaff(sources)
 local rosters={}
 for _,entry in self.queueStations or {} do
  local source=sources[entry.owner]; entry.source=source
  if entry.index>0 or entry.side==2 then
   local raw=source:GetAttribute('StaffRoster') or ''
   if entry.staffKey~=raw then
    local roster=rosters[entry.owner]
    if not roster then
     roster={}; rosters[entry.owner]=roster
     for id in string.gmatch(raw,'%d+') do table.insert(roster,tonumber(id)) end
    end
    local ordinal=if entry.index>0 then entry.index*2+entry.side-1 else 1
    local id,seed=Roster.identity(rosters,entry.owner,ordinal)
    entry.station.actor:setIdentity(id,seed); entry.staffKey=raw
   end
  end
 end
end
function Online:publishPlayer()
 local action=Action.player(self.kitchen.view); local now=os.clock()
 -- Редкое повторение восстанавливает последнюю позу, если сервер отбросил
 -- пакет при всплеске частоты. Новый зритель получает серверный кеш отдельно.
 if not Wire.samePose(self.lastPublished,action) or now-(self.publishedAt or -math.huge)>=1 then
  self.remote:FireServer(action); self.lastPublished=action; self.publishedAt=now
 end
end
function Online:cyclePhase(model,now)
 local id=model:GetAttribute('OwnerId')
 model=if self.cycleSources then self.cycleSources[id] or model else model
 local seconds=math.max(.01,model:GetAttribute('CycleSeconds') or 10)
 local clock=self.cycles[id]
 if not clock then
  clock={phase=(now/seconds)%1,seconds=seconds,at=now}; self.cycles[id]=clock
 else
  -- Сначала доходим по прежнему темпу, затем принимаем новое улучшение.
  -- Деление всего времени на новую длительность перескакивало между этапами.
  clock.phase=(clock.phase+math.max(0,now-clock.at)/clock.seconds)%1
  clock.seconds=seconds; clock.at=now
 end
 return clock.phase
end
function Online:step(dt)
 local k=self.kitchen; self.elapsed+=dt; self.scan+=dt
 if k.opened then self.lastPublished=nil end
 if self.elapsed>=.1 and not k.opened and k.state and k.state.ready then self.elapsed=0; self:publishPlayer() end
 if k.opened then
  self.request+=dt; if self.request>=1.1 then self.request=0; self.remote:FireServer() end
 end
 if self.scan>=.5 then
  self.scan=0
  local directory=Workspace:FindFirstChild('KitchenIslands'); local models=if directory then directory:GetChildren() else {}
  local seen={}; local owners={}
  for _,model in models do
   local id=model:GetAttribute('OwnerId'); local origin=model:GetAttribute('Origin'); local index=model:GetAttribute('CafeIndex') or 0
   if id and origin then
    local key=Queue.key(id,index); seen[key]=true; owners[id]=true
    if id~=k.player.UserId or index>0 then
     local peer=self.peers[key]
     -- Между опросами хозяин может вернуться с тем же ключом комнаты.
     -- Прежняя оболочка тогда хранит удалённую модель и старые координаты.
     if peer and (peer.model~=model or peer.origin~=origin) then self:remove(key); peer=nil end
     if not peer and k.opened then peer=self:add(model) end
     if peer then
      if k.opened then
       if not peer.staff then self:updateDecor(peer,model) end
      else
       if peer.station then self:releaseStations(peer) end
       peer.prompt.Enabled=false
      end
     end
    end
   end
  end
  for key in self.peers do if not seen[key] then self:remove(key) end end
  for id in self.packets do if not owners[id] then self.packets[id]=nil end end
  for id in self.cycles do if not owners[id] then self.cycles[id]=nil end end
  self:updateIslands(models)
 end
 -- Ушедшие владельцы очищаются и во время ручной резки. Пока кухня
 -- закрыта, новые модели, запросы чужих поз и анимации не запускаются.
 if not k.opened then return end
 local now=os.clock()
 for _,entry in self.queueStations or {} do
  local phase=self:cyclePhase(entry.source,now)
  local working=entry.index>0 or (entry.side==2 and entry.source:GetAttribute('HasApprentice')==true)
  local action=Action.cycle((phase+entry.side*.17)%1,Config,k.view.recipe.slides,k.view.tileWidth,k.view.tileHeight)
  if entry.index==0 and entry.side==1 then
   local player=Players:GetPlayerByUserId(entry.owner)
   local packet=self.packets[entry.owner]
   working=player~=nil and player:GetAttribute('KitchenMode')=='cut' and packet~=nil
   if working then action=Wire.blend(packet.previous,packet.current,(os.clock()-packet.at)/.1) end
  end
  entry.station.actor:setVisible(working)
  entry.station:pose(action,working,dt)
 end
 local root=k.player.Character and k.player.Character:FindFirstChild('HumanoidRootPart'); local position=if root then root.Position else k.origin
 for _,peer in self.peers do
  local near=(position-peer.origin).Magnitude<55 or k.watchPeer==peer
  if near and not peer.station then
   peer.stations[1]=Station.new(k.view,peer.world,peer.origin,-3.7,not peer.staff,peer.player.UserId)
   peer.stations[2]=Station.new(k.view,peer.world,peer.origin,3.7,false)
   peer.station=peer.stations[1]
  elseif not near and peer.station then
   self:releaseStations(peer)
  end
  peer.prompt.Enabled=near and k:canWalk()
  if peer.station then
   local packet=self.packets[peer.player.UserId]
   local phase=self:cyclePhase(peer.model,now)
   for side,station in peer.stations do
    if side==1 and not peer.staff then
     local working=peer.player:GetAttribute('KitchenMode')=='cut'
     station.actor:setVisible(working and packet~=nil)
     if packet then
      local action=Wire.blend(packet.previous,packet.current,(os.clock()-packet.at)/.1)
      if not working then action=table.clone(action); action.cutting=false end
      station:pose(action,true,dt)
     end
    else
     local working=peer.staff or peer.model:GetAttribute('HasApprentice')==true
     local staffSide=if peer.staff then side else 1
     station.actor:setIdentity(peer.model:GetAttribute('Staff'..staffSide),peer.model:GetAttribute('StaffSeed'..staffSide))
     station.actor:setVisible(working)
     station:pose(Action.cycle((phase+side*.17)%1,Config,k.view.recipe.slides,k.view.tileWidth,k.view.tileHeight),working,dt)
    end
   end
  end
 end
end
function Online:updateLocalVisibility(origin)
 local function update(part)
  if part:IsA('BasePart') then transparency(part,if (part.Position-origin).Magnitude<55 then 0 else 1) end
 end
 -- Очередь сама выбирает дальнюю детализацию. Не разворачиваем тысячи её
 -- потомков ради последующего IsDescendantOf. Остальные ветки читаем заново:
 -- новый аватар или купленный декор появится без отдельного кеша/подписок.
 for _,branch in self.kitchen.world:GetChildren() do
  if branch~=self.queue then
   update(branch)
   for _,part in branch:GetDescendants() do update(part) end
  end
 end
end
function Online:updateIslands(models)
 local k=self.kitchen; local owner=k.player:GetAttribute('VisitingKitchen') or k.player.UserId
 local index=k.player:GetAttribute('VisitingCafeIndex') or 0; local currentKey=Queue.key(owner,index)
 local current; local records={}; local sources={}; local prompts={}
 for _,model in models do
  local id=model:GetAttribute('OwnerId'); local n=model:GetAttribute('CafeIndex') or 0
  -- Атрибуты приходят отдельно от Model: до Origin комнату нельзя
  -- использовать ни как место наблюдения, ни как источник дальней копии.
  if id and model:GetAttribute('Origin') then
   local key=Queue.key(id,n); if key==currentKey then current=model end
   table.insert(records,{owner=id,index=n,online=model:GetAttribute('OwnerOnline'),count=model:GetAttribute('CafeCount') or 0})
   if not sources[id] or n==0 then sources[id]=model end
   for _,part in model:GetDescendants() do
    if part:IsA('BasePart') then transparency(part,if key==currentKey then 0 else 1)
    elseif part:IsA('ProximityPrompt') then
     table.insert(prompts,{prompt=part,current=key==currentKey})
    end
   end
  end
 end
 -- Домашняя модель — общий источник скорости, чтобы репликация атрибутов
 -- нескольких комнат одного владельца не чередовала старый и новый темп.
 self.cycleSources=sources
 local segments=Queue.build(records); local preview,ahead=Queue.window(segments,owner,index,k.player.UserId)
 -- Сразу назначаем окончательный текст: промежуточное Next cafe каждые
 -- полсекунды перезапускало встроенную подсказку и скрывало значок клавиши.
 for _,entry in prompts do
  local prompt=entry.prompt
  local enabled=entry.current and k:canWalk()
  local text=L.text('Choose a cafe')
  if prompt.ActionText~=text then prompt.ActionText=text end
  if prompt.Enabled~=enabled then prompt.Enabled=enabled end
 end
 if not current then self:clearQueue(); return end
 local origin=current:GetAttribute('Origin')
 local key=currentKey..':'..tostring(origin)
 for _,entry in preview do key..='/'..Queue.key(entry.owner,entry.index)..':'..tostring(sources[entry.owner]:GetAttribute('HasApprentice')) end
 if not k.opened then
  -- Неизменную очередь можно быстро вернуть при прогулке, но старые
  -- комнаты не удерживаются до следующего открытия после ухода соседей,
  -- престижа или замены серверного Instance. Новую очередь строим при входе.
  local stale=self.queueKey~=key
  for _,entry in self.queueStations or {} do
   if entry.source~=sources[entry.owner] then stale=true; break end
  end
  if stale then self:clearQueue() end
  return
 end
 self:updateLocalVisibility(origin)
 if self.queueKey==key then self:refreshQueueStaff(sources); self:refreshQueueDecor(sources); return end
 local anchor=currentKey..':'..tostring(origin)
 if self.queueAnchor~=anchor then
  self:clearQueue(); self.queueAnchor=anchor
 end
 self.queueKey=key
 if not self.queue then
  self.queue=Instance.new('Model'); self.queue.Name='DistantCafeQueue'; self.queue.Parent=k.world
 end
 -- Позиция в очереди — отдельное место. Покупка или вход соседа заменяет
 -- только изменившиеся места; прежние аватары, ножи и куски не создаются заново.
 local previous=self.queueRooms or {}; local rooms={}
 self.queueStations={}; self.queueDecor={}
 for offset,entry in preview do
  local rear=offset>ahead
  local slot=if rear then -(offset-ahead) else offset
  local detailed,animated=Queue.detail(offset,ahead)
  local source=sources[entry.owner]
  local roomKey=Queue.key(entry.owner,entry.index)..':'..tostring(source:GetAttribute('HasApprentice'))..':'..tostring(detailed)..':'..tostring(animated)
  local room=previous[slot]; previous[slot]=nil
  if room and room.key~=roomKey then self:destroyQueueRoom(room); room=nil end
  if not room then
   local location=origin+Vector3.new(0,0,-38*slot)
   room=self:buildQueueRoom(entry,source,location,detailed,animated,rear,slot)
   room.key=roomKey
  end
  rooms[slot]=room
  for _,station in room.stations do table.insert(self.queueStations,station) end
  if room.decor then table.insert(self.queueDecor,room.decor) end
 end
 for _,room in previous do self:destroyQueueRoom(room) end
 self.queueRooms=rooms
 self:refreshQueueStaff(sources); self:refreshQueueDecor(sources)
end
function Online:destroyQueueRoom(room)
 for _,entry in room.stations do entry.station:destroy() end
 room.world:Destroy()
end
function Online:buildQueueRoom(entry,source,location,detailed,animated,rear,slot)
 local k=self.kitchen
 local world=Instance.new('Model'); world.Name='QueueRoom_'..slot; world.Parent=self.queue
 local room={world=world,stations={}}
 local function part(parent,name,size,position,color)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=position; p.Color=color
  p.Anchored=true; p.CanCollide=false; p.CanQuery=false; p.CanTouch=false
  p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth; p.Parent=parent; return p
 end
 if detailed then
  Shell.new(room.world,location)
  if entry.index>0 then Decor.update({world=room.world,origin=location},Queue.decor(entry.owner,entry.index))
  else
   room.decor={world=room.world,origin=location,owner=entry.owner}
   self:updateDecor(room.decor,source)
  end
  -- Полные станции есть в трёх передних комнатах и одной ближайшей задней.
  -- Количество станций ограничено независимо от числа купленных кафе.
  if animated then
   for side,x in {-3.7,3.7} do
    local isPlayer=entry.index==0 and side==1
    local station=Station.new(k.view,room.world,location,x,isPlayer,entry.owner)
    table.insert(room.stations,{station=station,source=source,owner=entry.owner,index=entry.index,side=side,rear=rear})
   end
  end
 else
  for name,spec in {DistantFloor=Structure.floor,DistantFoundation=Structure.foundation} do
   part(room.world,name,Vector3.new(table.unpack(spec.size)),location+Vector3.new(table.unpack(spec.position)),
    if name=='DistantFloor' then Color3.fromRGB(181,160,130) else Color3.fromRGB(194,173,142))
  end
  for _,wall in Structure.walls do
   part(room.world,'DistantWall',Vector3.new(table.unpack(wall.size)),location+Vector3.new(table.unpack(wall.position)),Color3.fromRGB(83,112,97))
  end
  for _,x in {-3.7,3.7} do part(room.world,'DistantTable',Vector3.new(6.8,.4,5.8),location+Vector3.new(x,2.1,0),Color3.fromRGB(207,161,101)) end
 end
 if not animated then
  for side,x in {-3.7,3.7} do
   part(room.world,'DistantChocolate',Vector3.new(1.5,.12,2.4),location+Vector3.new(x,2.4,0),Color3.fromRGB(87,43,25))
   if entry.index>0 or (side==2 and source:GetAttribute('HasApprentice')) then
    local color=Color3.fromHSV(((entry.owner*131+entry.index*7919+side*997)%360)/360,.35,.85)
    part(room.world,'DistantWorkerBody',Vector3.new(1.5,1.6,.8),location+Vector3.new(x,3.2,-2.9),color)
    part(room.world,'DistantWorkerHead',Vector3.new(.8,.8,.8),location+Vector3.new(x,4.4,-2.9),Color3.fromRGB(207,159,119))
    for _,dx in {-.95,.95} do part(room.world,'DistantWorkerArm',Vector3.new(.5,.5,1.5),location+Vector3.new(x+dx,2.9,-2),Color3.fromRGB(207,159,119)) end
   end
  end
 end
 return room
end

function Online:destroy()
 self.receive:Disconnect(); self:clearQueue(); self.kitchen.watchPeer=nil
 for key in self.peers do self:remove(key) end
 self.cycles={}; self.cycleSources=nil
end
return Online
