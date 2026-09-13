--!nonstrict
-- Наблюдение отделено от ручного ввода и экономики. Станция принимает снимок
-- участника: позже его можно получать с сервера для других игроков.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Motion = require(script.Parent.Motion3D)
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
 local viewport=Instance.new("ViewportFrame"); viewport.Size=UDim2.new(1,0,1,-150)
 viewport.BackgroundColor3=sage; viewport.Ambient=Color3.fromRGB(165,159,144)
 viewport.LightColor=Color3.fromRGB(255,231,196); viewport.LightDirection=Vector3.new(-1,-2,-1)
 viewport.Parent=root; self.viewport=viewport
 local world=Instance.new("WorldModel"); world.Name="KitchenStations"; world.Parent=viewport
 local camera=Instance.new("Camera"); camera.FieldOfView=45; camera.Parent=viewport; viewport.CurrentCamera=camera; self.camera=camera
 part(world,"Floor",Vector3.new(18,.2,15),Vector3.new(0,-.2,0),Color3.fromRGB(181,160,130))
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
  if i==2 then
   for name,m in view.scene3D.pieces do station.parts[name]=clone(m,world); show(station.parts[name],false) end
   station.knife=clone(view.scene3D.knife,world)
  end
  self.stations[i]=station
 end
 local chef=Instance.new("Model"); chef.Name="ApprenticeChef"; chef.Parent=world; self.chef=chef
 part(chef,"Torso",Vector3.new(1.1,1.2,.65),Vector3.new(3.7,2,-3.4),cream)
 part(chef,"Apron",Vector3.new(.85,1.1,.1),Vector3.new(3.7,1.85,-3.02),sage)
 part(chef,"Head",Vector3.new(.8,.8,.75),Vector3.new(3.7,3,-3.4),Color3.fromRGB(210,157,113))
 part(chef,"HatBand",Vector3.new(.9,.25,.85),Vector3.new(3.7,3.52,-3.4),cream)
 for i=-1,1 do local p=part(chef,"ChefHat",Vector3.new(.55,.55,.8),Vector3.new(3.7+i*.28,3.8,-3.4),cream); p.Shape=Enum.PartType.Ball end
 for _,x in {3.45,3.95} do
  part(chef,"Leg",Vector3.new(.35,1.1,.5),Vector3.new(x,.85,-3.4),cocoa)
  part(chef,"Eye",Vector3.new(.08,.1,.04),Vector3.new(x,3.08,-3.01),cocoa)
 end
 self.arms={}
 for _,x in {3.05,4.35} do
  table.insert(self.arms,{upper=part(chef,"UpperArm",Vector3.new(.32,1,.32),Vector3.new(x,2,-3),cream),lower=part(chef,"Forearm",Vector3.new(.28,1,.28),Vector3.new(x,2,-3),cream)})
 end
 local panel=Instance.new("Frame"); panel.BackgroundColor3=cocoa; panel.BackgroundTransparency=.08
 panel.Position=UDim2.new(0,12,1,-150); panel.Size=UDim2.new(1,-24,0,138); panel.Parent=root
 self.title=label(panel,"Title",UDim2.fromOffset(12,8),UDim2.new(1,-24,0,30)); L.set(self.title,"Chocolate kitchen")
 self.info=label(panel,"Info",UDim2.fromOffset(12,44),UDim2.new(1,-24,0,30))
 button(panel,"Back","Back to my chocolate",UDim2.new(0,12,1,-50),UDim2.new(.5,-18,0,38),function() self:setOpen(false) end)
 self.watch=button(panel,"Watch","Watch apprentice",UDim2.new(.5,6,1,-50),UDim2.new(.5,-18,0,38),function() self.focus=not self.focus; L.set(self.watch,if self.focus then "View kitchen" else "Watch apprentice") end)
 self.enter=button(gui,"EnterKitchen","View kitchen",UDim2.new(1,-156,0,12),UDim2.fromOffset(144,38),function() self:setOpen(true) end)
 self.render=RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
 gui.Destroying:Connect(function() self.render:Disconnect() end)
 view.gui.Destroying:Connect(function() gui:Destroy() end)
 return self
end
function Kitchen:setOpen(open)
 if open and not (self.state and self.state.ready) then return end
 self.view:endDrag(true)
 self.opened=open; self.root.Visible=open; self.enter.Visible=not open
 self.view.observingKitchen=open
 self.view.gui.Enabled=not open
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
 local aspect=self.viewport.AbsoluteSize.X/math.max(1,self.viewport.AbsoluteSize.Y)
 local target=if self.focus then Vector3.new(3.7,2.1,-.4) else Vector3.new(0,1.6,-1)
 local distance=if self.focus then 8 else 16
 distance*=math.max(1,1.5/aspect)
 local cf=CFrame.lookAt(target+Vector3.new(0,distance*.8,distance),target)
 self.camera.CFrame=self.camera.CFrame:Lerp(cf,1-math.exp(-dt*7))
 show(self.chef,working)
 if working then L.set(self.info,"Apprentices: {count} · {seconds}s per trick",{count=state.levels.workers,seconds=L.number(state.cycleSeconds)})
 else L.set(self.info,"Hire your first apprentice in the workshop") end
 local s=self.stations[2]
 local t=((state.productionRemainder or 0)+(os.clock()-(self.syncedAt or os.clock()))/state.cycleSeconds)%1
 show(s.whole,not working or t<.45)
 for name,m in s.parts do
  show(m,working and t>=.45)
  local phase,p="explode",(t-.45)/.13
  if t>=.84 then phase,p="strip",math.min(1,(t-.84)/.12)
  elseif t>=.74 then phase,p="join",(t-.74)/.1
  elseif t>=.58 then phase,p="large",(t-.58)/.16 end
  local offset=Motion.pose(name,phase,math.clamp(p,0,1),Config.Scene3D.layouts.landscape,self.view.recipe.slides,Config.Scene3D.passageY)
  local unit=Config.Scene3D.unitsPerPixel*Config.Scene3D.renderScale
  m:PivotTo(CFrame.new(s.origin+Vector3.new(offset.X*self.view.tileWidth*unit,0,offset.Y*self.view.tileHeight*unit)))
 end
 show(s.knife,working and t<.45)
 if working then
  local index=math.min(4,math.floor(t/.45*4)+1)
  local cut=Config.Recipe.cuts[index]; local p=math.clamp((t/.45*4)%1,0,1)
  local u=Config.Scene3D.unitsPerPixel*Config.Scene3D.renderScale
  local a,b=Vector3.new(cut[1][1]*self.view.tileWidth*u,.18,cut[1][2]*self.view.tileHeight*u),Vector3.new(cut[2][1]*self.view.tileWidth*u,.18,cut[2][2]*self.view.tileHeight*u)
  local point=s.origin+a:Lerp(b,p)
  s.knife:PivotTo(CFrame.lookAt(point,point+(b-a))*CFrame.Angles(0,0,-math.pi/3))
  for i,arm in self.arms do
   local shoulder=Vector3.new(if i==1 then 3.05 else 4.35,2.5,-3.2)
   local hand=if t<.45 then point else s.origin+Vector3.new(math.sin(t*math.pi*6)*.7,.25,.6)
   local elbow=shoulder:Lerp(hand,.48)+Vector3.new(if i==1 then -.48 else .48,-.25,0)
   for _,segment in {{arm.upper,shoulder,elbow},{arm.lower,elbow,hand}} do
    local bone,a,b=table.unpack(segment)
    bone.Size=Vector3.new(.28,(b-a).Magnitude,.28)
    bone.CFrame=CFrame.lookAt((a+b)/2,b)*CFrame.Angles(math.pi/2,0,0)
   end
  end
 end
end
return Kitchen
