--!nonstrict
-- Один контроллер поз для человека и ученика. Источник действий не знает
-- об устройстве rig; длина рук остаётся постоянной, меняются только суставы.
local Players = game:GetService("Players")
local Appearance=require(script.Parent.FriendAppearance)
local Animator = {}
Animator.__index = Animator
function Animator.new(parent, name, x, isPlayer, roomOrigin, userId)
 local self=setmetatable({alive=true,visible=false,x=x},Animator)
 task.spawn(function()
  local description=Instance.new("HumanoidDescription")
  description.HeadColor=Color3.fromRGB(223,176,130)
  description.LeftArmColor=description.HeadColor; description.RightArmColor=description.HeadColor
  description.TorsoColor=if isPlayer then Color3.fromRGB(90,133,166) else Color3.fromRGB(244,234,209)
  description.LeftLegColor=Color3.fromRGB(64,52,44); description.RightLegColor=description.LeftLegColor
  if not isPlayer then
   local player=Players.LocalPlayer
   userId=Appearance.pickFriend(Players,player and player.UserId,math.random)
  end
  if not self.alive then description:Destroy(); return end
  -- R6 сохраняет общие суставы и позы игрока и стажёра.
  local ok,rig=Appearance.createRig(Players,description,userId,Enum.HumanoidRigType.R6)
  description:Destroy()
  if not ok then warn("Could not load chocolatier rig: "..tostring(rig)); return end
  if not self.alive or not parent.Parent then rig:Destroy(); return end
  rig.Name=name; rig:ScaleTo(.8)
  self.rig=rig; self.rest={}; self.motors={}
  local root=rig:FindFirstChild("HumanoidRootPart")
  -- Сгенерированная модель может иметь pivot не в корне; иначе персонаж
  -- оказывается по плечи внутри стола при одинаковой высоте станции.
  rig.PrimaryPart=root
  local humanoid=rig:FindFirstChildOfClass("Humanoid")
  humanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
  humanoid.AutoRotate=false
  for _,item in rig:GetDescendants() do
   if item:IsA("BasePart") then
    item.CanCollide=false; item.CanTouch=false; item.CanQuery=false
    item.Anchored=item==root; self.rest[item]=item.Transparency
   elseif item:IsA("Decal") then self.rest[item]=item.Transparency
   elseif item:IsA("Motor6D") then self.motors[item.Name]={joint=item,c0=item.C0}
   elseif item:IsA("BaseScript") then item:Destroy() end
  end
  rig.Parent=parent
  rig:PivotTo(CFrame.new((roomOrigin or Vector3.zero)+Vector3.new(x,2.4,-2.9))*CFrame.Angles(0,math.pi,0))
  self:setStyle(self.style or 0)
  self:setVisible(self.visible)
 end)
 return self
end
-- Фартук отличает варианты ученика, сохраняя внешность друга и общие суставы.
function Animator:setStyle(variant)
 self.style=variant
 if not self.rig or self.apronStyle==variant then return end
 self.apronStyle=variant
 if self.apron then
  for _,p in self.apron:GetChildren() do self.rest[p]=nil end
  self.apron:Destroy()
 end
 if variant==0 then return end
 local torso=self.rig:FindFirstChild('Torso')
 if not torso then return end
 local colors={Color3.fromRGB(108,62,39),Color3.fromRGB(232,175,85),Color3.fromRGB(94,159,130),Color3.fromRGB(155,77,114),Color3.fromRGB(255,217,117)}
 local model=Instance.new('Model'); model.Name='ApprenticeApron'; model.Parent=self.rig; self.apron=model
 local function piece(name,size,offset,color)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Color=color
  p.CanCollide=false; p.CanTouch=false; p.CanQuery=false; p.Massless=true
  p.CFrame=torso.CFrame*CFrame.new(offset); p.Parent=model
  local weld=Instance.new('WeldConstraint'); weld.Part0=torso; weld.Part1=p; weld.Parent=p
  self.rest[p]=0; p.Transparency=if self.visible then 0 else 1
 end
 piece('Collar',Vector3.new(1.55,.28,.95),Vector3.new(0,.55,0),colors[variant])
 piece('Apron',Vector3.new(1.1,1.3,.1),Vector3.new(0,-.2,-.43),colors[variant])
 for i=1,variant do piece('Badge',Vector3.new(.09,.1,.04),Vector3.new(-.36+(i-1)*.18,.23,-.51),Color3.fromRGB(255,244,220)) end
end
function Animator:setVisible(visible)
 self.visible=visible
 if not self.rig then return end
 for part,rest in self.rest do part.Transparency=if visible then rest else 1 end
end
function Animator:step(action, origin, scale, dt)
 if not self.rig or not self.visible then return end
 local active=action.cutting or not action.whole
 local alpha=1-math.exp(-dt*12)
 -- Одинаковые позы нарезки/переноса для любого источника Action.
 for _,side in {"Left","Right"} do
  local entry=self.motors[side.." Shoulder"]
  if entry then
   local joint=entry.joint
   local tile=if side=="Right" then action.rightHand else action.leftHand
   local target=origin+Vector3.new(tile.X*scale.X,.2,tile.Y*scale.Y)
   local shoulder=joint.Part0.CFrame:PointToWorldSpace(entry.c0.Position)
   local desired=entry.c0
   if active then
    local rotation=CFrame.lookAt(shoulder,target)*CFrame.Angles(math.pi/2,0,0)
    local arm=rotation*CFrame.new(0,-joint.Part1.Size.Y/2,0)
    desired=joint.Part0.CFrame:ToObjectSpace(arm*joint.C1)
   end
   joint.C0=joint.C0:Lerp(desired,alpha)
  end
 end
 local neck=self.motors.Neck
 if neck then neck.joint.C0=neck.joint.C0:Lerp(neck.c0*CFrame.Angles(if active then -.2 else 0,0,0),alpha) end
end
function Animator:destroy()
 self.alive=false
 if self.rig then self.rig:Destroy() end
end
return Animator
