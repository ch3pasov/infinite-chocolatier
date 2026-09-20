--!nonstrict
-- Наблюдение отделено от ручного ввода и экономики. Станция принимает снимок
-- участника: локального игрока, стажёра или соседа по серверу.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.KitchenCatalog)
local Action = require(script.Parent.WorkstationAction)
local Station=require(script.Parent.WorkstationView)
local Shell=require(script.Parent.KitchenShell)
local Online=require(script.Parent.OnlineKitchen)
local L = require(script.Parent.Localization)
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local Decor=require(script.Parent.KitchenDecor)
local Preview=require(script.Parent.DecorPreview)
local AvatarVisibility=require(script.Parent.AvatarVisibility)
local WalkCamera=require(script.Parent.WalkCamera)
local CafeDirectory=require(script.Parent.CafeDirectory)
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
 self.avatarVisibility=AvatarVisibility.new()
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
 self.walkController=WalkCamera.new(player,self.walkCamera,function() return self.opened and not self.focus and not self.shopping and not self.browsing and not view.diagnosticsOpen end)
 Shell.new(world,self.origin)
 self.stations={Station.new(view,world,self.origin,-3.7,true),Station.new(view,world,self.origin,3.7,false)}
 local panel=Instance.new("Frame"); panel.BackgroundColor3=cocoa; panel.BackgroundTransparency=.08
 panel.Position=UDim2.new(0,12,1,-150); panel.Size=UDim2.new(1,-24,0,138); panel.Parent=root
 self.panel=panel
 local previewPanel=Instance.new('Frame'); previewPanel.Name='DecorationPreview'; previewPanel.BackgroundColor3=cocoa
 previewPanel.Position=UDim2.new(0,12,1,-176); previewPanel.Size=UDim2.new(1,-24,0,164); previewPanel.Visible=false; previewPanel.Parent=root
 self.previewPanel=previewPanel
 self.previewTitle=label(previewPanel,'Title',UDim2.fromOffset(12,6),UDim2.new(1,-24,0,28))
 self.previewInfo=label(previewPanel,'Info',UDim2.fromOffset(12,38),UDim2.new(1,-24,0,32))
 self.previewBuy=button(previewPanel,'Buy','Buy',UDim2.fromOffset(12,78),UDim2.new(1,-24,0,36),function()
  local state=self.state; local id=self.preview and self.preview.id
  if not state or not state.ready then return end
  if not id or os.clock()<(self.previewNextBuy or 0) then return end
  if Catalog.byId[id].group=='workers' and state.equipped.workers==id then return end
  local price=state.prices[id]
  if state.owned[id] or (price and state.slices>=price) then
   self.previewNextBuy=os.clock()+.5; atelier.remotes.purchase:FireServer(id)
  end
 end)
 button(previewPanel,'Back','Back to catalog',UDim2.fromOffset(12,120),UDim2.new(1,-24,0,32),function() self:setWalking(); self:openShop() end)
 atelier.onPreview=function(id) self:previewDecor(id) end
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
  prompt.Triggered:Connect(function() if self.opened and self.state and self.state.ready and not self.focus and not self.shopping and not self.browsing then callback() end end)
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
 self.catalogBook=book
 part(world,'CatalogPages',Vector3.new(1.7,.12,1.1),self.origin+Vector3.new(-8,1.9,8),cream)
 prompt('Kitchen upgrades','My Kitchen',Vector3.new(-8,2.5,8),function() self:openShop() end)
 self.characterConnection=player.CharacterAdded:Connect(function(char)
  local humanoid=char:WaitForChild('Humanoid')
  self.walkCamera.CameraSubject=humanoid
  if self.opened and not self.focus and not self.shopping then self:setWalking() else self.controls:Disable() end
 end)
 self.online=Online.new(self)
 self.directory=CafeDirectory.new(self)
 self.render=RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
 gui.Destroying:Connect(function()
  self.render:Disconnect(); self.walkController:destroy()
  self.characterConnection:Disconnect(); self:setAvatarVisible(true); self.controls:Enable()
  self.online:destroy()
  self.directory:destroy()
  for _,station in self.stations do station:destroy() end
 end)
 view.gui.Destroying:Connect(function() gui:Destroy() end)
 return self
end
function Kitchen:setAvatarVisible(visible)
 self.avatarVisibility:set(self.player.Character,visible)
end
function Kitchen:setWalking()
 if self.directory then self.directory:close() end
 self.preview=nil
 if self.previewPanel then self.previewPanel.Visible=false end
 if self.state and self.state.ready then Decor.update(self,self.state) end
 self.focus=false; self.shopping=false; self.watchPeer=nil
 self:setAvatarVisible(true)
 pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,true) end)
 self.controls:Enable()
 self.stage:activate(self.world,self.walkCamera)
 self.walkController:step(0)
 self.atelier.remotes.kitchenMode:FireServer('walk')
end
function Kitchen:openShop()
 if not self.state or not self.state.ready or self.state.levels.kitchen<1 then return end
 self.shopping=true; self.controls:Disable(); self.atelier.remotes.kitchenMode:FireServer('watch')
 local shop=self.atelier
 shop.external=true; shop:setMode('kitchen'); shop.overlay.Parent=self.gui; shop:fit(); shop:setOpen(true)
 shop.onClose=function()
  shop.onClose=nil; shop:setMode('upgrades'); shop.external=false; shop.overlay.Parent=self.view.gui; shop:fit()
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
 if not state then return end
 local previous=self.state; self.state=state
 -- Ответ во время загрузки содержит только ready=false. Его нельзя читать
 -- как экономический снимок, иначе следующий готовый профиль тоже падает.
 if not state.ready then
  for _,prompt in self.prompts do prompt.Enabled=false end
  return
 end
 local justUnlocked=previous and previous.ready and previous.levels.kitchen==0 and state.levels.kitchen>0
 self.syncedAt=os.clock()
 if justUnlocked and not self.opened then self.atelier:setOpen(false) end
 if state.ready then
  if self.preview then self:updatePreview() else Decor.update(self,state) end
 end
end
function Kitchen:step(dt)
 self.online:step(dt)
 self:updateOnboarding()
 if not self.opened or not self.state or not self.state.ready then return end
 local state=self.state; local working=state.levels.workers>0
 for name,prompt in self.prompts do prompt.Enabled=not self.focus and not self.shopping and not self.browsing and (name~='Apprentice worktable' or working) and (name~='Kitchen upgrades' or state.levels.kitchen>0) end
 self.panel.Visible=self.focus
 self.stations[1].actor:setVisible(false)
 if not working and self.focus and not self.watchPeer then self:setWalking() end
 if self.focus or self.preview then
 self:setAvatarVisible(false)
 self.camera.CameraType=Enum.CameraType.Scriptable
 local aspect=self.root.AbsoluteSize.X/math.max(1,self.root.AbsoluteSize.Y-150)
 local target=if self.watchPeer then self.watchPeer.origin+Vector3.new(if self.watchPeer.staff then 0 else -3.7,2.1,-.4) else self.origin+Vector3.new(3.7,2.1,-.4)
 local lookOffset
 if self.preview then
  local shots={workers={Vector3.new(3.7,3,-2),Vector3.new(0,3,7)},temper={Vector3.new(-6,3,-5),Vector3.new(2,2,5)},library={Vector3.new(-4,4,-6),Vector3.new(1,1,5)},clock={Vector3.new(6,5.6,-6),Vector3.new(-1,0,5)},plant={Vector3.new(8.5,1.5,9),Vector3.new(-3,2,5)},rug={Vector3.new(0,0,9),Vector3.new(0,8,5)},art={Vector3.new(-10.1,4,8),Vector3.new(6,1,1)}}
  local shot=shots[self.previewSpec.group]; target=self.origin+shot[1]; lookOffset=shot[2]
 end
 local distance=if self.focus then (if self.watchPeer and self.watchPeer.staff then 12 else 8) else 16
 distance*=math.max(1,1.5/aspect)
 local cf=CFrame.lookAt(target+(if lookOffset then lookOffset*math.max(1,1.3/aspect) else Vector3.new(0,distance*.8,distance)),target)
 -- Нижняя панель занимает 150 px: центр кухни сдвигается выше неё.
 local focal=math.max(60,self.root.AbsoluteSize.Y-150)/(2*math.tan(math.rad(45)/2))
 cf+=cf.UpVector*(-75*(cf.Position-target).Magnitude/focal)
 self.camera.FieldOfView=math.deg(2*math.atan(math.tan(math.rad(45)/2)*self.root.AbsoluteSize.Y/math.max(60,self.root.AbsoluteSize.Y-150)))
 self.camera.CFrame=if dt==0 then cf else self.camera.CFrame:Lerp(cf,1-math.exp(-dt*7))
 self.camera.Focus=CFrame.new(target)
 end
 local previewId=if self.preview then Preview.update(self.preview,state) else nil
 local variant=Catalog.selected(state,'workers',previewId)
 local directory=workspace:FindFirstChild('KitchenIslands')
 local home=directory and directory:FindFirstChild('KitchenRoom_'..self.player.UserId)
 if home then self.stations[2].actor:setIdentity(home:GetAttribute('Staff1'),home:GetAttribute('StaffSeed1')) end
 self.stations[2].actor:setVisible(variant>0)
 if self.watchPeer and self.watchPeer.staff then
  L.set(self.info,"Watch apprentices")
 elseif self.watchPeer then
  L.set(self.info,if self.watchPeer.player:GetAttribute("KitchenMode")=="cut" then "Watching {name} · live" else "{name} is away from their worktable",{name=self.watchPeer.player.DisplayName})
 elseif working then L.set(self.info,"Apprentices: {count} · {seconds}s per trick",{count=state.levels.workers,seconds=L.number(state.cycleSeconds)})
 else L.set(self.info,"Hire your first apprentice in the workshop") end
 local t=((state.productionRemainder or 0)+(os.clock()-(self.syncedAt or os.clock()))/state.cycleSeconds)%1
 self.stations[1]:pose(Action.player(self.view),true,dt)
 self.stations[2]:pose(Action.cycle(t,Config,self.view.recipe.slides,self.view.tileWidth,self.view.tileHeight),working or variant>0,dt)
end
function Kitchen:previewDecor(id)
 local spec=Catalog.byId[id]
 if not spec or not self.state or not self.state.ready then return end
 if self.atelier.external then self.atelier:setOpen(false) end
 if not self.opened then self:setOpen(true) end
 self.preview=Preview.begin(id,self.state); self.previewSpec=spec
 self.focus=false; self.shopping=true; self.controls:Disable()
 self.previewPanel.Visible=true; self.atelier.overlay.Visible=false
 self.atelier.remotes.kitchenMode:FireServer('watch')
 self.stage:activate(self.world,self.camera); self:updatePreview(); self:step(0)
end
function Kitchen:updatePreview()
 local state=self.state; local id=self.preview.id
 Decor.update(self,state,Preview.update(self.preview,state))
 L.set(self.previewTitle,self.previewSpec.name)
 local owned=state.owned[id]==true
 local installed=state.equipped[self.previewSpec.group]==id
 local worker=self.previewSpec.group=='workers'
 L.set(self.previewInfo,if id=='workers_1' and not owned then '3/3 · Hire your prepaid apprentice below.' elseif not owned then 'Preview · not purchased' elseif installed and worker then 'Working in your kitchen' elseif installed then 'Placed in your kitchen' elseif not self.preview.confirmed then 'Preview · already owned' else 'Put away · purchase bonuses remain')
 local price=state.prices[id]
 local available=not (worker and installed) and (owned or (price and state.slices>=price))
 self.previewBuy.AutoButtonColor=available==true
 self.previewBuy.BackgroundColor3=if available then gold else cocoa
 self.previewBuy.TextColor3=if available then cocoa else cream
 if owned and worker then L.set(self.previewBuy,if installed then 'Selected apprentice' else 'Select apprentice')
 elseif owned then L.set(self.previewBuy,if installed then 'Put away · owned' else 'Place · owned')
 elseif available and price==0 then L.set(self.previewBuy,'Hire for free · prepaid')
 elseif available then L.set(self.previewBuy,'Buy · {price} pieces',{price=L.number(price)})
 else L.set(self.previewBuy,'Price {price} · need {missing} more',{price=L.number(price or 0),missing=L.number(math.max(0,(price or 0)-state.slices))}) end
end
-- Подсказка восстанавливается после входа: оплата и первый найм хранятся на сервере.
function Kitchen:updateOnboarding()
 local state=self.state
 local active=state and state.ready and state.levels.kitchen>0 and not state.owned.workers_1
 if not self.guide then
  self.guide=label(self.gui,'KitchenGuide',UDim2.new(.5,-170,0,180),UDim2.fromOffset(340,80))
  self.guide.AnchorPoint=Vector2.new(.5,0)
  self.guide.Size=UDim2.new(1,-24,0,80)
  local bounds=Instance.new('UISizeConstraint'); bounds.MaxSize=Vector2.new(340,80); bounds.Parent=self.guide
  self.guide.BackgroundColor3=cocoa; self.guide.BackgroundTransparency=.1
  local mark=Instance.new('BillboardGui'); mark.Name='FirstApprenticeGuide'; mark.Size=UDim2.fromOffset(180,60)
  mark.StudsOffset=Vector3.new(0,3,0); mark.AlwaysOnTop=true; mark.Adornee=self.catalogBook; mark.Parent=self.gui
  local caption=label(mark,'Label',UDim2.fromScale(0,0),UDim2.fromScale(1,1)); L.set(caption,'2 · Open this book')
  self.bookGuide=mark
 end
 self.guide.Visible=active==true and not self.shopping
 self.bookGuide.Enabled=active==true and self.opened and not self.shopping
 if not active then return end
 local source=if not self.opened then '1/3 · Tap Walk around kitchen above to meet your apprentice.' elseif self.shopping then '3/3 · Choose the apprentice spot, then hire for free.' else '2/3 · Walk to the golden book on the left and open My Kitchen.'
 L.set(self.guide,source)
 self.guide.Position=if self.opened then UDim2.new(.5,0,0,70) else UDim2.new(.5,0,0,180)
end

function Kitchen:watchPlayer(peer)
 if not self.opened or self.shopping or not self.state or not self.state.ready then return end
 self.watchPeer=peer; self.focus=true
 self.controls:Disable(); self.atelier.remotes.kitchenMode:FireServer('watch')
 self.stage:activate(self.world,self.camera); self:step(0)
end
return Kitchen
