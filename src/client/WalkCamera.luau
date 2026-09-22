--!nonstrict
-- Азимут неизменен: экранное «вперёд» всегда ведёт к столам (-Z).
-- Отдельная Scriptable-камера не наследует первое лицо и поворот Roblox.
local Input=game:GetService('UserInputService')
local Gui=game:GetService('GuiService')
local Run=game:GetService('RunService')
local Workspace=game:GetService('Workspace')
local Camera={}; Camera.__index=Camera
function Camera.new(player,camera,enabled)
 local self=setmetatable({player=player,camera=camera,enabled=enabled,distance=24,pitch=30,touches={},connections={}},Camera)
 local function connect(signal,callback) table.insert(self.connections,signal:Connect(callback)) end
 connect(Input.InputBegan,function(input,processed)
  if processed or not self:active() then return end
  if input.UserInputType==Enum.UserInputType.MouseButton2 then
   self.dragging=true; self.oldMouse=Input.MouseBehavior
   Input.MouseBehavior=Enum.MouseBehavior.LockCurrentPosition
  elseif input.UserInputType==Enum.UserInputType.Touch then self.touches[input]=input.Position end
 end)
 connect(Input.InputChanged,function(input,processed)
  if not self:active() then return end
  if input.UserInputType==Enum.UserInputType.MouseMovement and self.dragging then
   self:adjust(input.Delta.Y*.2,0)
  elseif input.UserInputType==Enum.UserInputType.MouseWheel and not processed then
   self:adjust(0,-input.Position.Z*1.5)
  elseif self.touches[input] then
   local previous=self.touches[input]; local other
   for finger,position in self.touches do if finger~=input then other=position; break end end
   if other then
    self:adjust(0,((previous-other).Magnitude-(input.Position-other).Magnitude)*.04)
   else self:adjust((input.Position.Y-previous.Y)*.2,0) end
   self.touches[input]=input.Position
  elseif input.KeyCode==Enum.KeyCode.Thumbstick2 then
   self.stick=if processed then 0 else input.Position.Y
  end
 end)
 connect(Input.InputEnded,function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self:releaseMouse() end
  self.touches[input]=nil
  if input.KeyCode==Enum.KeyCode.Thumbstick2 then self.stick=0 end
 end)
 connect(Input.WindowFocusReleased,function() self:resetInput() end)
 -- Меню может забрать отпускание мыши/стика. Освобождаем захват сразу,
 -- даже если следующий RenderStep придёт только после закрытия меню.
 connect(Gui.MenuOpened,function() self:resetInput() end)
 connect(Input.TextBoxFocused,function() self:resetInput() end)
 self.binding='ChocolateWalkCamera'
 Run:BindToRenderStep(self.binding,Enum.RenderPriority.Camera.Value+1,function(dt) self:step(dt) end)
 return self
end
function Camera:active()
 return Workspace.CurrentCamera==self.camera and self.enabled() and not Gui.MenuIsOpen and not Input:GetFocusedTextBox()
end
function Camera:adjust(pitch,zoom)
 self.pitch=math.clamp(self.pitch+pitch,25,70)
 self.distance=math.clamp(self.distance+zoom,8,32)
end
function Camera:releaseMouse()
 if self.dragging then Input.MouseBehavior=self.oldMouse; self.dragging=false end
end
function Camera:resetInput()
 self:releaseMouse(); self.touches={}; self.stick=0
end
function Camera:step(dt)
 if not self:active() then self:resetInput(); return end
 local character=self.player.Character
 local root=character and character:FindFirstChild('HumanoidRootPart')
 if not root then return end
 if math.abs(self.stick or 0)>.15 then self:adjust(-self.stick*45*dt,0) end
 local target=root.Position+Vector3.new(0,1.5,0)
 local angle=math.rad(self.pitch)
 local offset=Vector3.new(0,math.sin(angle),math.cos(angle))*self.distance
 self.camera.CameraType=Enum.CameraType.Scriptable
 self.camera.CFrame=CFrame.new(target+offset)*CFrame.Angles(-angle,0,0)
 self.camera.Focus=CFrame.new(target)
end
function Camera:destroy()
 self:resetInput()
 Run:UnbindFromRenderStep(self.binding)
 for _,connection in self.connections do connection:Disconnect() end
end
return Camera
