--!nonstrict
-- Геометрия и анимация едины: различается только источник снимка действий.
local Config=require(game:GetService('ReplicatedStorage'):WaitForChild('Shared').Config)
local Animator=require(script.Parent.ChocolatierAnimator)
local Knife=require(script.Parent.KnifeMotion)
local Station={}; Station.__index=Station
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
function Station.new(view,parent,roomOrigin,x,isPlayer,userId)
 local world=Instance.new('Model'); world.Name='Workstation'; world.Parent=parent
 local self=setmetatable({view=view,world=world,origin=roomOrigin+Vector3.new(x-.75,2.37,-.3),parts={}},Station)
 self.whole=clone(view.scene3D.intact,world); self.whole:PivotTo(CFrame.new(self.origin))
 for name,model in view.scene3D.pieces do self.parts[name]=clone(model,world); show(self.parts[name],false) end
 self.knife=clone(view.scene3D.knife,world); show(self.knife,false)
 self.actor=Animator.new(world,if isPlayer then 'PlayerChocolatier' else 'ApprenticeChocolatier',x,isPlayer,roomOrigin,userId)
 return self
end
function Station:pose(action,working,dt)
 local station=self
 local unit=Config.Scene3D.unitsPerPixel*Config.Scene3D.renderScale
 local scale=Vector2.new(self.view.tileWidth*unit,self.view.tileHeight*unit)
 show(station.whole,not working or action.whole)
 for name,model in station.parts do
  show(model,working and not action.whole and not (action.hidden and action.hidden[name]))
  local offset=action.offsets[name]
  model:PivotTo(CFrame.new(station.origin+Vector3.new(offset.X*scale.X,0,offset.Y*scale.Y)))
 end
 show(station.knife,working and action.cutting)
 local grip=nil
 if working and action.cutting then
  local point=station.origin+Vector3.new(action.knifePoint.X*scale.X,.18,action.knifePoint.Y*scale.Y)
  local direction=Vector3.new(action.knifeDirection.X*scale.X,0,action.knifeDirection.Y*scale.Y)
  local frame=Knife.frame(point,direction,Config.Scene3D,math.rad(-65))
  station.knife:PivotTo(frame)
  grip=Knife.grip(frame,Config.Scene3D)
 end
 self.actor:step(action,station.origin,scale,dt,grip)
end
function Station:destroy()
 self.actor:destroy(); self.world:Destroy()
end
return Station
