--!nonstrict
-- Наблюдение отделено от ручного ввода и экономики. Станция принимает снимок
-- участника: локального игрока, стажёра или соседа по серверу.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Action = require(script.Parent.WorkstationAction)
local Station=require(script.Parent.WorkstationView)
local Shell=require(script.Parent.KitchenShell)
local Online=require(script.Parent.OnlineKitchen)
local L = require(script.Parent.Localization)
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local Decor=require(script.Parent.KitchenDecor)
local Kitchen = {}
local cocoa = Color3.fromRGB(71,38,27)
local cream = Color3.fromRGB(255,232,192)
local sage = Color3.fromRGB(83,112,97)
local gold = Color3.fromRGB(255,194,64)
local function part(parent,name,size,pos,color)
 local p=Instance.new("Part")
 p.Name=name; p.Size=size; p.CFrame=CFrame.new(pos); p.Color=color
 p.Anchored=true; p.CanCollide=false; p.Material=Enum.Material.SmoothPlastic
 p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
 p.Parent=parent
 return p
end
local function label(parent,name,pos,size)
 local t=Instance.new("TextLabel"); t.Name=name; t.Position=pos; t.Size=size
 t.BackgroundTransparency=1; t.TextColor3=cream; t.Font=Enum.Font.GothamBold
 t.TextScaled=true; t.TextWrapped=true; t.Parent=parent
 local limit=Instance.new("UITextSizeConstraint"); limit.MaxTextSize=22; limit.MinTextSize=11; limit.Parent=t
 return t
end
local function button(parent,name,text,pos,size,callback)
 local b=Instance.new("TextButton"); b.Name=name; b.Position=pos; b.Size=size
 b.BackgroundColor3=gold; b.TextColor3=cocoa; b.Font=Enum.Font.GothamBold; b.TextSize=16
 b.TextWrapped=true; b.Parent=parent; L.set(b,text)
 local c=Instance.new("UICorner"); c.CornerRadius=UDim.new(0,12); c.Parent=b
 b.Activated:Connect(callback); return b
end
function Kitchen.new(view,atelier)
 local self=setmetatable({view=view,atelier=atelier,opened=false,focus=false}, {__index=Kitchen})
 local player=Players.LocalPlayer; self.player=player
 while not player:GetAttribute('KitchenOrigin') do player:GetAttributeChangedSignal('KitchenOrigin'):Wait() end
 self.origin=player:GetAttribute('KitchenOrigin')
 self.controls=require(player:WaitForChild('PlayerScripts'):WaitForChild('PlayerModule')):GetControls()
 self.controls:Disable()
 pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false) end)
 local gui=Instance.new("ScreenGui"); gui.Name="KitchenExperiment"; gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.DisplayOrder=20; gui.Parent=view.gui.Parent; self.gui=gui
 local root=Instance.new("Frame"); root.Name="Kitchen"; root.Size=UDim2.fromScale(1,1)
 root.BackgroundColor3=cocoa; root.Visible=false; root.Parent=gui; self.root=root
 root.BackgroundTransparency=1
 local viewport=Instance.new("Frame"); viewport.Size=UDim2.new(1,0,1,-150)
 viewport.BackgroundTransparency=1; viewport.Parent=root; self.viewport=viewport
 self.stage=view.scene3D.stage
 local world=self.stage:createWorld("KitchenStations"); self.world=world
 local camera=self.stage:createCamera("KitchenCamera",45); self.camera=camera
 self.walkCamera=self.stage:createCamera("KitchenWalkCamera",70)
 Shell.new(world,self.origin)
 self.stations={Station.new(view,world,self.origin,-3.7,true),Station.new(view,world,self.origin,3.7,false)}
 local panel=Instance.new("Frame"); panel.BackgroundColor3=cocoa; panel.BackgroundTransparency=.08
 panel.Position=UDim2.new(0,12,1,-150); panel.Size=UDim2.new(1,-24,0,138); panel.Parent=root
 self.panel=panel
 self.title=label(panel,"Title",UDim2.fromOffset(12,8),UDim2.new(1,-24,0,30)); L.set(self.title,"Chocolate kitchen")
 self.info=label(panel,"Info",UDim2.fromOffset(12,44),UDim2.new(1,-24,0,30))
 self.back=button(panel,"Back","Back to walking",UDim2.new(0,12,1,-50),UDim2.new(1,-24,0,38),function() self:setWalking() end)
 self.enter=button(gui,"EnterKitchen","Walk around kitchen",UDim2.new(.5,-82,0,12),UDim2.fromOffset(164,32),function() self:setOpen(true) end)
 local function fitEnter()
  self.enter.Position=UDim2.new(.5,-82,0,if view.root.AbsoluteSize.X>view.root.AbsoluteSize.Y then 12 else 134)
 end
 view.root:GetPropertyChangedSignal('AbsoluteSize'):Connect(fitEnter); fitEnter()
 self.prompts={}
 local function prompt(name,caption,position,callback)
  local anchor=part(world,name,Vector3.new(.2,.2,.2),self.origin+position,cocoa); anchor.Transparency=1
  local prompt=Instance.new('ProximityPrompt'); prompt.ActionText=L.text(caption); prompt.ObjectText=L.text(name)
  prompt.MaxActivationDistance=5; prompt.RequiresLineOfSight=false; prompt.HoldDuration=0; prompt.ClickablePrompt=true; prompt.Enabled=false; prompt.Parent=anchor
  prompt.Triggered:Connect(function() if self.opened and not self.focus and not self.shopping then callback() end end)
  self.prompts[name]=prompt
 end
 prompt('My worktable','Cut chocolate',Vector3.new(-3.7,2,3),function() self:setOpen(false) end)
 prompt('Apprentice worktable','Watch apprentice',Vector3.new(3.7,2,3),function()
  if self.state.levels.workers<1 then return end
  self.focus=true; self.controls:Disable(); atelier.remotes.kitchenMode:FireServer('watch')
  self.stage:activate(self.world,self.camera); self:step(0)
 end)
 part(world,'CatalogStand',Vector3.new(1.6,1.7,1),self.origin+Vector3.new(-8,.75,8),cocoa)
 local book=part(world,'KitchenCatalog',Vector3.new(1.9,.18,1.3),self.origin+Vector3.new(-8,1.75,8),gold)
 book.CFrame*=CFrame.Angles(math.rad(15),0,0)
 part(world,'CatalogPages',Vector3.new(1.7,.12,1.1),self.origin+Vector3.new(-8,1.9,8),cream)
 prompt('Kitchen upgrades','Shop & decorate',Vector3.new(-8,2.5,8),function() self:openShop() end)
 self.characterConnection=player.CharacterAdded:Connect(function(char)
  local humanoid=char:WaitForChild('Humanoid')
  self.walkCamera.CameraSubject=humanoid
  if self.opened and not self.focus and not self.shopping then self:setWalking() else self.controls:Disable() end
 end)
 self.online=Online.new(self)
 self.render=RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
 gui.Destroying:Connect(function()
  self.render:Disconnect()
  self.characterConnection:Disconnect(); self:setAvatarVisible(true); self.controls:Enable()
  self.online:destroy()
  for _,station in self.stations do station:destroy() end
 end)
 view.gui.Destroying:Connect(function() gui:Destroy() end)
 return self
end
function Kitchen:setAvatarVisible(visible)
 if visible then
  for item,transparency in self.hiddenAvatar or {} do
   if item.Parent then item.Transparency=transparency end
  end
  self.hiddenAvatar=nil
 else
  self.hiddenAvatar=self.hiddenAvatar or {}
  local char=self.player.Character
  if char then for _,item in char:GetDescendants() do
   if item:IsA('BasePart') or item:IsA('Decal') then
    if self.hiddenAvatar[item]==nil then self.hiddenAvatar[item]=item.Transparency end
    item.Transparency=1
   end
  end end
 end
end
function Kitchen:setWalking()
 self.focus=false; self.shopping=false; self.watchPeer=nil
 self:setAvatarVisible(true)
 pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,true) end)
 self.controls:Enable()
 self.walkCamera.CameraType=Enum.CameraType.Custom
 local char=self.player.Character
 local humanoid=char and char:FindFirstChildOfClass('Humanoid')
 self.walkCamera.CameraSubject=humanoid
 if not self.walkStarted then
  local target=self.origin+Vector3.new(0,2,4)
  self.walkCamera.CFrame=CFrame.lookAt(target+Vector3.new(0,7,12),target)
  self.walkStarted=true
 end
 self.stage:activate(self.world,self.walkCamera)
 self.atelier.remotes.kitchenMode:FireServer('walk')
end
function Kitchen:openShop()
 self.shopping=true; self.controls:Disable(); self.atelier.remotes.kitchenMode:FireServer('watch')
 local shop=self.atelier
 shop.external=true; shop.overlay.Parent=self.gui; shop:fit(); shop:setOpen(true)
 shop.onClose=function()
  shop.onClose=nil; shop.external=false; shop.overlay.Parent=self.view.gui; shop:fit()
  self:setWalking()
 end
end
function Kitchen:setOpen(open)
 if open and not (self.state and self.state.ready) then return end
 self.view:endDrag(true)
 self.opened=open; self.root.Visible=open; self.enter.Visible=not open
 self.view.observingKitchen=open
 self.view.gui.Enabled=not open
 if open then
  self:setWalking()
 else
  self.focus=false; self.controls:Disable()
  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false) end)
  self.atelier.remotes.kitchenMode:FireServer('cut')
  self.stage:activate(self.view.scene3D.world,self.view.scene3D.camera)
  self.atelier:update(self.state)
 end
 for name,prompt in self.prompts do prompt.Enabled=open and (name~='Apprentice worktable' or self.state.levels.workers>0) end
end
function Kitchen:update(state)
 self.state=state; self.syncedAt=os.clock()
 if state.ready then Decor.update(self,state) end
end
function Kitchen:step(dt)
 self.online:step(dt)
 if not self.opened or not self.state then return end
 local state=self.state; local working=state.levels.workers>0
 for name,prompt in self.prompts do prompt.Enabled=not self.focus and not self.shopping and (name~='Apprentice worktable' or working) end
 self.panel.Visible=self.focus
 self.stations[1].actor:setVisible(false)
 if not working and self.focus and not self.watchPeer then self:setWalking() end
 if self.focus then
 self:setAvatarVisible(false)
 self.camera.CameraType=Enum.CameraType.Scriptable
 local aspect=self.root.AbsoluteSize.X/math.max(1,self.root.AbsoluteSize.Y-150)
 local target=if self.watchPeer then self.watchPeer.origin+Vector3.new(-3.7,2.1,-.4) else self.origin+Vector3.new(3.7,2.1,-.4)
 local distance=if self.focus then 8 else 16
 distance*=math.max(1,1.5/aspect)
 local cf=CFrame.lookAt(target+Vector3.new(0,distance*.8,distance),target)
 -- Нижняя панель занимает 150 px: центр кухни сдвигается выше неё.
 local focal=math.max(60,self.root.AbsoluteSize.Y-150)/(2*math.tan(math.rad(45)/2))
 cf+=cf.UpVector*(-75*(cf.Position-target).Magnitude/focal)
 self.camera.FieldOfView=math.deg(2*math.atan(math.tan(math.rad(45)/2)*self.root.AbsoluteSize.Y/math.max(60,self.root.AbsoluteSize.Y-150)))
 self.camera.CFrame=if dt==0 then cf else self.camera.CFrame:Lerp(cf,1-math.exp(-dt*7))
 self.camera.Focus=CFrame.new(target)
 end
 self.stations[2].actor:setVisible(working)
 if self.watchPeer then
  L.set(self.info,if self.watchPeer.player:GetAttribute("KitchenMode")=="cut" then "Watching {name} · live" else "{name} is away from their worktable",{name=self.watchPeer.player.DisplayName})
 elseif working then L.set(self.info,"Apprentices: {count} · {seconds}s per trick",{count=state.levels.workers,seconds=L.number(state.cycleSeconds)})
 else L.set(self.info,"Hire your first apprentice in the workshop") end
 local t=((state.productionRemainder or 0)+(os.clock()-(self.syncedAt or os.clock()))/state.cycleSeconds)%1
 self.stations[1]:pose(Action.player(self.view),true,dt)
 self.stations[2]:pose(Action.cycle(t,Config,self.view.recipe.slides),working,dt)
end
function Kitchen:watchPlayer(peer)
 if not self.opened or self.shopping then return end
 self.watchPeer=peer; self.focus=true
 self.controls:Disable(); self.atelier.remotes.kitchenMode:FireServer('watch')
 self.stage:activate(self.world,self.camera); self:step(0)
end
return Kitchen
