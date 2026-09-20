--!nonstrict
local Structure=require(game:GetService('ReplicatedStorage'):WaitForChild('Shared'):WaitForChild('KitchenStructure'))
-- Один набор мебели для своей кухни и видимых соседей; передняя сторона
-- открыта в общий проход. Коллизиями владеет сервер.
local Shell={}
local cocoa=Color3.fromRGB(71,38,27)
local cream=Color3.fromRGB(255,232,192)
local sage=Color3.fromRGB(83,112,97)
local function part(parent,name,size,pos,color)
 local p=Instance.new("Part")
 p.Name=name; p.Size=size; p.CFrame=CFrame.new(pos); p.Color=color
 p.Anchored=true; p.CanCollide=false; p.Material=Enum.Material.SmoothPlastic
 p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
 p.Parent=parent
 return p
end
function Shell.new(parent,origin)
 local world=Instance.new('Model'); world.Name='KitchenFurniture'; world.Parent=parent
 part(world,"Floor",Vector3.new(22,.2,24),Vector3.new(0,-.2,5),Color3.fromRGB(181,160,130))
 for _,wall in Structure.walls do
  part(world,wall.name,Vector3.new(table.unpack(wall.size)),Vector3.new(table.unpack(wall.position)),sage)
 end
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
 for _,x in {-3.7,3.7} do
  part(world,'Worktable',Vector3.new(6.8,.25,5.8),Vector3.new(x,2.1,0),Color3.fromRGB(165,113,65))
  for _,dx in {-2.8,2.8} do for _,z in {-2.3,2.3} do
   part(world,'Leg',Vector3.new(.3,2,.3),Vector3.new(x+dx,1,z),cocoa)
  end end
  part(world,'CuttingBoard',Vector3.new(6.4,.12,5.5),Vector3.new(x,2.3,0),Color3.fromRGB(207,161,101))
 end
 world:PivotTo(CFrame.new(origin)*world:GetPivot())
 return world
end
return Shell
