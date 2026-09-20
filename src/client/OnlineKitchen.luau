--!nonstrict
-- Реальные позы соседей приходят от сервера. Между двумя снимками сглаживаем
-- движение, но не придумываем следующий разрез и не запускаем цикл за игрока.
local Workspace=game:GetService('Workspace')
local Players=game:GetService('Players')
local Shared=game:GetService('ReplicatedStorage'):WaitForChild('Shared')
local Wire=require(Shared.WorkstationWire)
local Action=require(script.Parent.WorkstationAction)
local Station=require(script.Parent.WorkstationView)
local Shell=require(script.Parent.KitchenShell)
local L=require(script.Parent.Localization)
local Online={}; Online.__index=Online
function Online.new(kitchen)
 local self=setmetatable({kitchen=kitchen,peers={},packets={},elapsed=0,scan=0,request=0},Online)
 self.remote=kitchen.atelier.remotes.kitchenAction
 self.receive=self.remote.OnClientEvent:Connect(function(userId,raw)
  local clean=Wire.clean(raw)
  if not clean then return end
  local old=self.packets[userId]
  self.packets[userId]={previous=old and old.current,current=clean,at=os.clock()}
 end)
 self.remote:FireServer()
 return self
end
function Online:remove(id)
 local peer=self.peers[id]; if not peer then return end
 if self.kitchen.watchPeer==peer then self.kitchen:setWalking() end
 if peer.station then peer.station:destroy() end
 peer.world:Destroy(); self.peers[id]=nil
end
function Online:add(player,origin,model)
 local k=self.kitchen
 local world=Instance.new('Model'); world.Name='Neighbor_'..player.UserId; world.Parent=k.world
 Shell.new(world,origin)
 local peer={player=player,origin=origin,world=world,model=model}; self.peers[player.UserId]=peer
 local anchor=Instance.new('Part'); anchor.Name='PlayerWorktable'; anchor.Anchored=true
 anchor.CanCollide=false; anchor.Transparency=1; anchor.Size=Vector3.one
 anchor.Position=origin+Vector3.new(-3.7,2.5,3); anchor.Parent=world
 local prompt=Instance.new('ProximityPrompt'); prompt.ActionText=L.text('Watch player')
 prompt.ObjectText=player.DisplayName..' (@'..player.Name..')'; prompt.MaxActivationDistance=5
 prompt.RequiresLineOfSight=false; prompt.HoldDuration=0; prompt.ClickablePrompt=true; prompt.Enabled=false; prompt.Parent=anchor; peer.prompt=prompt
 prompt.Triggered:Connect(function()
  if k.opened and not k.focus and not k.shopping and peer.station then k:watchPlayer(peer) end
 end)
 local billboard=Instance.new('BillboardGui'); billboard.Size=UDim2.fromOffset(240,48)
 billboard.StudsOffset=Vector3.new(0,3,0); billboard.MaxDistance=65; billboard.Parent=anchor; peer.billboard=billboard
 local text=Instance.new('TextLabel'); text.Size=UDim2.fromScale(1,1); text.BackgroundTransparency=.25
 text.BackgroundColor3=Color3.fromRGB(71,38,27); text.TextColor3=Color3.fromRGB(255,232,192)
 text.TextScaled=true; text.Font=Enum.Font.GothamBold; text.Text=player.DisplayName..'\n@'..player.Name; text.AutoLocalize=false; text.Parent=billboard
 return peer
end
function Online:step(dt)
 local k=self.kitchen
 self.elapsed+=dt; self.scan+=dt
 if self.elapsed>=.1 and not k.opened and k.state and k.state.ready then
  self.elapsed=0
  self.remote:FireServer(Action.player(k.view))
 end
 if not k.opened then return end
 self.request+=dt
 if self.request>=1.1 then self.request=0; self.remote:FireServer() end
 if self.scan>=.5 then
  self.scan=0
  local directory=Workspace:FindFirstChild('KitchenIslands')
  local seen={}; local models=if directory then directory:GetChildren() else {}
  for _,model in models do
   local id=model:GetAttribute('OwnerId'); local origin=model:GetAttribute('Origin')
   if id and origin then
    seen[id]=true
    if id~=k.player.UserId and not self.peers[id] then
     -- Снимок имени остаётся после ухода владельца до последнего гостя.
     local author={UserId=id,DisplayName=model:GetAttribute('DisplayName'),Name=model:GetAttribute('Username')}
     function author:GetAttribute(name)
      local player=Players:GetPlayerByUserId(id)
      return if model:GetAttribute('OwnerOnline') and player and player.Parent then player:GetAttribute(name) else nil
     end
     self:add(author,origin,model)
    end
   end
  end
  for id in self.peers do if not seen[id] then self:remove(id); self.packets[id]=nil end end
  self:updateIslands(models)

 end
 local root=k.player.Character and k.player.Character:FindFirstChild('HumanoidRootPart')
 local position=if root then root.Position else k.origin
 for id,peer in self.peers do
  local near=(position-peer.origin).Magnitude<65 or k.watchPeer==peer
  if near and not peer.station then
   peer.station=Station.new(k.view,peer.world,peer.origin,-3.7,true,id)
  elseif not near and peer.station then
   peer.station:destroy(); peer.station=nil
  end
  peer.prompt.Enabled=near and not k.focus and not k.shopping
  peer.billboard.Enabled=not k.focus
  local packet=self.packets[id]
  if peer.station then
   local working=peer.player:GetAttribute('KitchenMode')=='cut'
   peer.station.actor:setVisible(working and packet~=nil)
   if packet then
    local action=Wire.blend(packet.previous,packet.current,(os.clock()-packet.at)/.1)
    if not working then action=table.clone(action); action.cutting=false end
    peer.station:pose(action,true,dt)
   end
  end
 end
end
-- Физические острова независимы; дальние копии создают личную очередь,
-- не перемещая чужих персонажей и не меняя серверную географию.
function Online:updateIslands(models)
 local k=self.kitchen
 local currentId=k.player:GetAttribute('VisitingKitchen') or k.player.UserId
 local current; local ordered={}
 for _,model in models do
  local id=model:GetAttribute('OwnerId')
  if id then table.insert(ordered,model) end
  if id==currentId then current=model end
  for _,part in model:GetDescendants() do
   if part:IsA('BasePart') then part.LocalTransparencyModifier=if id==currentId then 0 else 1
   elseif part:IsA('SurfaceGui') then part.Enabled=id==currentId
   elseif part:IsA('ProximityPrompt') then
    local home=part.Name=='HomeCafePrompt'
    part.Enabled=id==currentId and k.opened and not k.focus and not k.shopping and (not home or currentId~=k.player.UserId)
    part.ActionText=L.text(if home then 'Return home' elseif #models>1 then 'Next cafe' else 'Waiting for another cafe')
   end
  end
 end
 if not current then return end
 local origin=current:GetAttribute('Origin')
 for _,part in k.world:GetDescendants() do
  if part:IsA('BasePart') and (not self.queue or not part:IsDescendantOf(self.queue)) then
   part.LocalTransparencyModifier=if (part.Position-origin).Magnitude<55 then 0 else 1
  end
 end
 table.sort(ordered,function(a,b) return a:GetAttribute('Origin').X<b:GetAttribute('Origin').X end)
 local index=table.find(ordered,current) or 1
 local key=tostring(currentId)
 for _,model in ordered do key..=':'..model:GetAttribute('OwnerId') end
 if self.queueKey==key then return end
 self.queueKey=key
 if self.queue then self.queue:Destroy() end
 self.queue=Instance.new('Model'); self.queue.Name='DistantCafeQueue'; self.queue.Parent=k.world
 for offset=1,math.min(3,#ordered-1) do
  local model=ordered[(index+offset-1)%#ordered+1]
  -- Очередь за задней стеной видна фиксированной камере; за спиной
  -- камеры (+Z) она полностью исчезала бы из кадра.
  local location=origin+Vector3.new(0,0,-80*offset)
  Shell.new(self.queue,location)
  local floor=Instance.new('Part'); floor.Name='DistantTerrace'; floor.Anchored=true; floor.CanCollide=false; floor.CanQuery=false
  floor.Size=Vector3.new(22,1,11); floor.Position=location+Vector3.new(0,-.6,22.5)
  floor.Color=Color3.fromRGB(151,126,98); floor.TopSurface=Enum.SurfaceType.Smooth; floor.BottomSurface=Enum.SurfaceType.Smooth; floor.Parent=self.queue
  local title=Instance.new('BillboardGui'); title.Size=UDim2.fromOffset(180,35); title.StudsOffset=Vector3.new(0,6,0); title.Parent=floor
  local text=Instance.new('TextLabel'); text.Size=UDim2.fromScale(1,1); text.BackgroundTransparency=1; text.TextColor3=Color3.fromRGB(255,232,192)
  text.TextScaled=true; text.Text=model:GetAttribute('DisplayName'); text.AutoLocalize=false; text.Parent=title
 end
end
function Online:destroy()
 self.receive:Disconnect()
 if self.queue then self.queue:Destroy() end
 self.kitchen.watchPeer=nil
 for id in self.peers do self:remove(id) end
end
return Online
