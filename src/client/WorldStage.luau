--!nonstrict
-- Один владелец основной камеры. Неактивные сцены хранятся вне Workspace,
-- чтобы кухня не рисовалась поверх доски и не тратила кадры в фоне.
local Workspace=game:GetService('Workspace')
local ReplicatedStorage=game:GetService('ReplicatedStorage')
local Lighting=game:GetService('Lighting')
local Stage={}
Stage.__index=Stage
function Stage.new()
 local self=setmetatable({originalCamera=Workspace.CurrentCamera,lighting={}},Stage)
 self.cameras=Instance.new('Folder'); self.cameras.Name='ChocolateCameras'; self.cameras.Parent=Workspace
 self.storage=Instance.new('Folder'); self.storage.Name='LocalChocolateScenes'; self.storage.Parent=ReplicatedStorage
 for property,value in {Ambient=Color3.fromRGB(150,140,125),OutdoorAmbient=Color3.fromRGB(150,140,125),Brightness=2,ClockTime=10,GlobalShadows=true} do
  self.lighting[property]=Lighting[property]; Lighting[property]=value
 end
 return self
end
function Stage:createWorld(name)
 local world=Instance.new('Model'); world.Name=name; world.Parent=self.storage; return world
end
function Stage:createCamera(name,fov)
 local camera=Instance.new('Camera'); camera.Name=name; camera.CameraType=Enum.CameraType.Scriptable
 camera.FieldOfViewMode=Enum.FieldOfViewMode.Vertical; camera.FieldOfView=fov; camera.Parent=self.cameras
 return camera
end
function Stage:activate(world,camera)
 if self.active and self.active~=world then self.active.Parent=self.storage end
 world.Parent=Workspace; self.active=world
 Workspace.CurrentCamera=camera
end
function Stage:destroy()
 if self.originalCamera and self.originalCamera.Parent then Workspace.CurrentCamera=self.originalCamera end
 if self.active then self.active:Destroy() end
 self.storage:Destroy()
 self.cameras:Destroy()
 for property,value in self.lighting do Lighting[property]=value end
end
return Stage
