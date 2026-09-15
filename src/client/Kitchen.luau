--!nonstrict
-- Наблюдение отделено от ручного ввода и экономики. Станция принимает снимок
-- участника: позже его можно получать с сервера для других игроков.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Action = require(script.Parent.WorkstationAction)
local ChocolatierAnimator = require(script.Parent.ChocolatierAnimator)
local L = require(script.Parent.Localization)
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
local function show(model,visible)
 if model:GetAttribute("KitchenShown")==visible then return end
 model:SetAttribute("KitchenShown",visible)
 for _,p in model:GetDescendants() do
  if p:IsA("BasePart") then p.Transparency=if visible then 0 else 1 end
 end
end
local function clone(source,parent)
 local m=source:Clone(); m:SetAttribute("KitchenShown",nil); m.Parent=parent; show(m,true); return m
end
function Kitchen.new(view,atelier)
 local self=setmetatable({view=view,atelier=atelier,opened=false,focus=false}, {__index=Kitchen})
 local gui=Instance.new("ScreenGui"); gui.Name="KitchenExperiment"; gui.ResetOnSpawn=false
 gui.IgnoreGuiInset=true; gui.DisplayOrder=20; gui.Parent=view.gui.Parent; self.gui=gui
 local root=Instance.new("Frame"); root.Name="Kitchen"; root.Size=UDim2.fromScale(1,1)
 root.BackgroundColor3=cocoa; root.Visible=false; root.Parent=gui; self.root=root
 root.BackgroundTransparency=1
 local viewport=Instance.new("Frame"); viewport.Size=UDim2.new(1,0,1,-150)
 viewport.BackgroundTransparency=1; viewport.Parent=root; self.viewport=viewport
 self.stage=view.scene3D.stage
 local world=self.stage:createWorld("KitchenStations"); self.world=world
 local camera=self.stage:createCamera("KitchenCamera",45); self.camera=camera
 part(world,"Floor",Vector3.new(180,.2,180),Vector3.new(0,-.2,0),Color3.fromRGB(181,160,130))
 part(world,"BackWall",Vector3.new(18,7,.2),Vector3.new(0,3,-6),sage)
 part(world,"LeftWall",Vector3.new(.2,7,15),Vector3.new(-9,3,0),sage)
 for x=-8,8,2 do
  part(world,"Cabinet",Vector3.new(1.9,2,1.5),Vector3.new(x,1,-5),cream)
  part(world,"Handle",Vector3.new(.6,.08,.08),Vector3.new(x,1.6,-4.2),cocoa)
 end
 part(world,"Countertop",Vector3.new(18,.2,1.8),Vector3.new(0,2.1,-5),cocoa)
 part(world,"WindowFrame",Vector3.new(4.8,2.8,.2),Vector3.new(0,4.4,-5.8),cream)
 part(world,"Window",Vector3.new(4.4,2.4,.21),Vector3.new(0,4.4,-5.65),Color3.fromRGB(157,201,210))
 part(world,"WindowCross",Vector3.new(.12,2.4,.25),Vector3.new(0,4.4,-5.5),cream)
 part(world,"Shelf",Vector3.new(4,.15,.7),Vector3.new(5.5,4,-5.5),cocoa)
 for i=1,4 do
  local jar=part(world,"CocoaJar",Vector3.new(.45,.7,.45),Vector3.new(3.9+i*.65,4.45,-5.4),if i%2==0 then cream else cocoa)
  jar.Shape=Enum.PartType.Cylinder; jar.CFrame*=CFrame.Angles(0,0,math.pi/2)
 end
 self.stations={}
 for i,x in {-3.7,3.7} do
  local origin=Vector3.new(x,2.3,0)
  part(world,"Worktable",Vector3.new(6.8,.25,5.8),Vector3.new(x,2.1,0),Color3.fromRGB(165,113,65))
  for _,dx in {-2.8,2.8} do for _,z in {-2.3,2.3} do
   part(world,"Leg",Vector3.new(.3,2,.3),Vector3.new(x+dx,1,z),cocoa)
  end end
  part(world,"CuttingBoard",Vector3.new(6.4,.12,5.5),origin,Color3.fromRGB(207,161,101))
  local station={origin=origin+Vector3.new(-.75,.07,-.3),parts={}}
  station.whole=clone(view.scene3D.intact,world)
  station.whole:PivotTo(CFrame.new(station.origin))
  do
   for name,m in view.scene3D.pieces do station.parts[name]=clone(m,world); show(station.parts[name],false) end
   station.knife=clone(view.scene3D.knife,world)
  end
  self.stations[i]=station
 end
 self.actors={
  ChocolatierAnimator.new(world,"PlayerChocolatier",-3.7,true),
  ChocolatierAnimator.new(world,"ApprenticeChocolatier",3.7,false),
 }
 local panel=Instance.new("Frame"); panel.BackgroundColor3=cocoa; panel.BackgroundTransparency=.08
 panel.Position=UDim2.new(0,12,1,-150); panel.Size=UDim2.new(1,-24,0,138); panel.Parent=root
 self.title=label(panel,"Title",UDim2.fromOffset(12,8),UDim2.new(1,-24,0,30)); L.set(self.title,"Chocolate kitchen")
 self.info=label(panel,"Info",UDim2.fromOffset(12,44),UDim2.new(1,-24,0,30))
 button(panel,"Back","Back to my chocolate",UDim2.new(0,12,1,-50),UDim2.new(.5,-18,0,38),function() self:setOpen(false) end)
 self.watch=button(panel,"Watch","Watch apprentice",UDim2.new(.5,6,1,-50),UDim2.new(.5,-18,0,38),function() self.focus=not self.focus; L.set(self.watch,if self.focus then "View kitchen" else "Watch apprentice") end)
 self.enter=button(gui,"EnterKitchen","View kitchen",UDim2.new(1,-156,0,12),UDim2.fromOffset(144,38),function() self:setOpen(true) end)
 self.render=RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
 gui.Destroying:Connect(function()
  self.render:Disconnect()
  for _,actor in self.actors do actor:destroy() end
 end)
 view.gui.Destroying:Connect(function() gui:Destroy() end)
 return self
end
function Kitchen:setOpen(open)
 if open and not (self.state and self.state.ready) then return end
 self.view:endDrag(true)
 self.opened=open; self.root.Visible=open; self.enter.Visible=not open
 self.view.observingKitchen=open
 self.view.gui.Enabled=not open
 if open then
  self:step(0)
  self.stage:activate(self.world,self.camera)
 else
  self.stage:activate(self.view.scene3D.world,self.view.scene3D.camera)
 end
 if not open then self.atelier:update(self.state) end
end
function Kitchen:update(state)
 self.state=state; self.syncedAt=os.clock()
end
function Kitchen:step(dt)
 if not self.opened or not self.state then return end
 local state=self.state; local working=state.levels.workers>0
 self.watch.Visible=working
 if not working then self.focus=false end
 local aspect=self.root.AbsoluteSize.X/math.max(1,self.root.AbsoluteSize.Y-150)
 local target=if self.focus then Vector3.new(3.7,2.1,-.4) else Vector3.new(0,1.6,-1)
 local distance=if self.focus then 8 else 16
 distance*=math.max(1,1.5/aspect)
 local cf=CFrame.lookAt(target+Vector3.new(0,distance*.8,distance),target)
 -- Нижняя панель занимает 150 px: центр кухни сдвигается выше неё.
 local focal=math.max(60,self.root.AbsoluteSize.Y-150)/(2*math.tan(math.rad(45)/2))
 cf+=cf.UpVector*(-75*(cf.Position-target).Magnitude/focal)
 self.camera.FieldOfView=math.deg(2*math.atan(math.tan(math.rad(45)/2)*self.root.AbsoluteSize.Y/math.max(60,self.root.AbsoluteSize.Y-150)))
 self.camera.CFrame=if dt==0 then cf else self.camera.CFrame:Lerp(cf,1-math.exp(-dt*7))
 self.camera.Focus=CFrame.new(target)
 self.actors[1]:setVisible(true)
 self.actors[2]:setVisible(working)
 if working then L.set(self.info,"Apprentices: {count} · {seconds}s per trick",{count=state.levels.workers,seconds=L.number(state.cycleSeconds)})
 else L.set(self.info,"Hire your first apprentice in the workshop") end
 local t=((state.productionRemainder or 0)+(os.clock()-(self.syncedAt or os.clock()))/state.cycleSeconds)%1
 self:poseStation(1,Action.player(self.view),true,dt)
 self:poseStation(2,Action.cycle(t,Config,self.view.recipe.slides),working,dt)
end
function Kitchen:poseStation(index,action,working,dt)
 local station=self.stations[index]
 local unit=Config.Scene3D.unitsPerPixel*Config.Scene3D.renderScale
 local scale=Vector2.new(self.view.tileWidth*unit,self.view.tileHeight*unit)
 show(station.whole,not working or action.whole)
 for name,model in station.parts do
  show(model,working and not action.whole and not (action.hidden and action.hidden[name]))
  local offset=action.offsets[name]
  model:PivotTo(CFrame.new(station.origin+Vector3.new(offset.X*scale.X,0,offset.Y*scale.Y)))
 end
 show(station.knife,working and action.cutting)
 if working and action.cutting then
  local point=station.origin+Vector3.new(action.knifePoint.X*scale.X,.18,action.knifePoint.Y*scale.Y)
  local direction=Vector3.new(action.knifeDirection.X*scale.X,0,action.knifeDirection.Y*scale.Y)
  station.knife:PivotTo(CFrame.lookAt(point,point+direction)*CFrame.Angles(0,0,-math.pi/3))
 end
 self.actors[index]:step(action,station.origin,scale,dt)
end
return Kitchen
