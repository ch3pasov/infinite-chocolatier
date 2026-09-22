--!nonstrict
-- Один контроллер поз для человека и ученика. Источник действий не знает
-- об устройстве rig; длина рук остаётся постоянной, меняются только суставы.
local Players = game:GetService("Players")
local Appearance=require(script.Parent.FriendAppearance)
local Animator = {}
Animator.__index = Animator
function Animator.new(parent, name, x, isPlayer, roomOrigin, userId)
 local self=setmetatable({alive=true,visible=false,x=x,generation=0,parent=parent},Animator)
 parent:SetAttribute('ActorVisible',false)
 function self:setIdentity(nextId,seed,retry)
  if not self.alive then return end
  nextId=nextId or 0; seed=seed or 1
  local key=tostring(nextId)..':'..tostring(seed)
  local sameIdentity=self.identity==key
  if sameIdentity and not retry then return end
  self.identity=key; self.generation+=1; local generation=self.generation
  -- Статус принадлежит станции, а не rig: иначе пустое место после
  -- ошибки загрузки вообще отсутствует в диагностическом отчёте.
  parent:SetAttribute('ActorAssignedUserId',nextId)
  parent:SetAttribute('ActorLoadState','loading')
  -- При повторе того же назначения запасной повар остаётся до готовности
  -- внешности. Сменившийся друг убирается сразу, чтобы не дублировать игрока.
  if self.rig and not (sameIdentity and retry) then self.rig:Destroy(); self.rig=nil end
  if not self.rig then parent:SetAttribute('ActorAppearanceUserId',0) end
  local function current() return self.alive and self.generation==generation and parent.Parent~=nil end
  -- Очередь назначает друга сразу после создания станции. Даём этому коду
  -- закончить назначение, чтобы не загружать запасной rig перед настоящим.
  task.defer(function()
  if not current() then return end
  local description=Instance.new("HumanoidDescription")
  description.HeadColor=Color3.fromRGB(223,176,130)
  description.LeftArmColor=description.HeadColor; description.RightArmColor=description.HeadColor
  description.TorsoColor=if isPlayer then Color3.fromRGB(90,133,166) else Color3.fromRGB(244,234,209)
  description.LeftLegColor=Color3.fromRGB(64,52,44); description.RightLegColor=description.LeftLegColor
  do
   local random=Random.new(seed)
   local skin={Color3.fromRGB(239,201,165),Color3.fromRGB(207,159,119),Color3.fromRGB(156,105,73),Color3.fromRGB(98,65,49)}
   description.HeadColor=skin[random:NextInteger(1,#skin)]
   description.LeftArmColor=description.HeadColor; description.RightArmColor=description.HeadColor
   description.TorsoColor=Color3.fromHSV(random:NextNumber(),.35,.85)
   description.LeftLegColor=Color3.fromHSV(random:NextNumber(),.3,.3); description.RightLegColor=description.LeftLegColor
  end
  -- R6 сохраняет общие суставы и позы игрока и стажёра.
  local ok,rig,friendLoaded,loadError=Appearance.createRig(Players,description,nextId,Enum.HumanoidRigType.R6,current)
  description:Destroy()
  if not current() then if ok and rig then rig:Destroy() end; return end
  -- Временный сбой Roblox не оставляет станцию без персонажа и не
  -- закрепляет запасную внешность друга навсегда. Обычный rig тоже
  -- создаётся через асинхронный API и может потребовать повтора.
  -- Повтор отменяется вместе со станцией или сменой назначенного друга.
  if not ok or (nextId>0 and not friendLoaded) then
   local attempt=retry or 0
   parent:SetAttribute('ActorLoadState',if attempt<3 then 'retrying' elseif ok then 'fallback' else 'failed')
   warn("Apprentice avatar "..nextId..": "..tostring(loadError or rig))
   if attempt<3 then task.delay(({5,20,60})[attempt+1],function()
    if self.alive and self.generation==generation then self:setIdentity(nextId,seed,attempt+1) end
   end) end
  else parent:SetAttribute('ActorLoadState','ready') end
  if not ok then warn("Could not load chocolatier rig: "..tostring(rig)); return end
  rig.Name=name; rig:ScaleTo(.8)
  rig:SetAttribute("AppearanceUserId",if friendLoaded then nextId else 0)
  rig:SetAttribute("AssignedUserId",nextId)
  parent:SetAttribute('ActorAppearanceUserId',if friendLoaded then nextId else 0)
  if self.rig then self.rig:Destroy() end
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
  self:setVisible(self.visible)
  end)
 end
 self:setIdentity(if isPlayer then userId else 0,1)
 return self
end
function Animator:setVisible(visible)
 if self.visible~=visible then self.parent:SetAttribute('ActorVisible',visible) end
 self.visible=visible
 if not self.rig then return end
 if self.visibleRig==self.rig and self.appliedVisibility==visible then return end
 self.visibleRig=self.rig; self.appliedVisibility=visible
 for part,rest in self.rest do part.Transparency=if visible then rest else 1 end
end
function Animator:step(action, origin, scale, dt, knifeGrip)
 if not self.rig or not self.visible then return end
 local active=action.cutting or not action.whole
 local alpha=1-math.exp(-dt*12)
 -- Одинаковые позы нарезки/переноса для любого источника Action.
 for _,side in {"Left","Right"} do
  local entry=self.motors[side.." Shoulder"]
  if entry then
   local joint=entry.joint
   local tile=if side=="Right" then action.rightHand else action.leftHand
   local target=if side=="Right" and knifeGrip then knifeGrip else origin+Vector3.new(tile.X*scale.X,.2,tile.Y*scale.Y)
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
 self.rig=nil; self.rest=nil; self.motors=nil; self.visibleRig=nil
 self.parent:SetAttribute('ActorVisible',false)
 self.parent:SetAttribute('ActorLoadState',nil)
 self.parent:SetAttribute('ActorAssignedUserId',nil)
 self.parent:SetAttribute('ActorAppearanceUserId',nil)
end
return Animator
