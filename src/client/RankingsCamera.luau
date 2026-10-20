--!nonstrict
-- Просмотр стены владеет отдельной камерой: прогулка сохраняет свой масштаб
-- и наклон, а закрытие не отбирает камеру у другого режима или нового персонажа.
local Workspace=game:GetService('Workspace')
local Camera={};Camera.__index=Camera
local duration=.45
function Camera.new(camera) return setmetatable({camera=camera},Camera) end
function Camera.pose(part,viewport)
 local aspect=math.max(1,viewport.X)/math.max(1,viewport.Y)
 local tangent=math.tan(math.rad(50)/2)
 local distance=math.min(18,math.max(part.Size.Y/(2*tangent*.70),part.Size.X/(2*tangent*aspect*.88)))
 -- На узком телефоне расширяем поле зрения, а не выносим камеру за
 -- противоположную стену, которая иначе перекрыла бы всё табло.
 local fov=math.deg(2*math.atan(math.max(tangent,part.Size.Y/(2*distance*.70),part.Size.X/(2*distance*aspect*.88))))
 local target=part.Position+part.CFrame.ZVector*(part.Size.Z/2+.02)
 return CFrame.lookAt(target+part.CFrame.ZVector*distance,target,part.CFrame.UpVector),target,fov
end
function Camera:open(part)
 if self.part or not part.Parent or not Workspace.CurrentCamera then return false end
 self.previous=Workspace.CurrentCamera;self.part=part;self.elapsed=0
 self.start=self.previous.CFrame;self.startFov=self.previous.FieldOfView
 self.camera.CFrame=self.start;self.camera.Focus=self.previous.Focus;self.camera.FieldOfView=self.startFov
 Workspace.CurrentCamera=self.camera
 return true
end
function Camera:step(dt)
 if not self.part then return false end
 if not self.part.Parent or Workspace.CurrentCamera~=self.camera then return false end
 self.elapsed=math.min(duration,self.elapsed+dt)
 local t=self.elapsed/duration;local alpha=t*t*(3-2*t)
 local pose,target,fov=Camera.pose(self.part,self.camera.ViewportSize)
 self.camera.CFrame=self.start:Lerp(pose,alpha)
 self.camera.Focus=CFrame.new(target)
 self.camera.FieldOfView=self.startFov+(fov-self.startFov)*alpha
 return true
end
function Camera:ready() return self.part~=nil and self.elapsed>=duration end
function Camera:close()
 if self.part and Workspace.CurrentCamera==self.camera and self.previous and self.previous.Parent then
  Workspace.CurrentCamera=self.previous
 end
 self.part=nil;self.previous=nil
end
return Camera
