--!nonstrict
-- Реальные позы соседей приходят от сервера. Между двумя снимками сглаживаем
-- движение, но не придумываем следующий разрез и не запускаем цикл за игрока.
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
 self.leaving=Players.PlayerRemoving:Connect(function(player)
  self:remove(player.UserId); self.packets[player.UserId]=nil
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
function Online:add(player,origin)
 local k=self.kitchen
 local world=Instance.new('Model'); world.Name='Neighbor_'..player.UserId; world.Parent=k.world
 Shell.new(world,origin)
 local peer={player=player,origin=origin,world=world}; self.peers[player.UserId]=peer
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
  for _,player in Players:GetPlayers() do
   local origin=player:GetAttribute('KitchenOrigin')
   if player~=k.player and origin and not self.peers[player.UserId] then self:add(player,origin) end
  end
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
function Online:destroy()
 self.receive:Disconnect(); self.leaving:Disconnect()
 self.kitchen.watchPeer=nil
 for id in self.peers do self:remove(id) end
end
return Online
