--!nonstrict
-- Покупки меняют предметы в комнате. Перестраиваем только при смене набора,
-- а не при каждом секундном обновлении баланса.
local Decor={}
function Decor.update(kitchen,state)
 local levels=state.levels; local equipped=state.decor or {}
 local key=table.concat({levels.temper,levels.library,levels.clock,tostring(equipped.plant),tostring(equipped.rug),tostring(equipped.art)},':')
 if kitchen.decorKey==key then return end
 kitchen.decorKey=key
 if kitchen.decorModel then kitchen.decorModel:Destroy() end
 local model=Instance.new('Model'); model.Name='PurchasedKitchenItems'; model.Parent=kitchen.world; kitchen.decorModel=model
 local function part(name,size,pos,color,shape)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=kitchen.origin+pos
  p.Anchored=true; p.CanCollide=false; p.Material=Enum.Material.SmoothPlastic; p.Color=color
  if shape==Enum.PartType.Ball then
   -- Part-шар берёт минимальный размер: для плоских листьев и какао нужен mesh.
   local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.Sphere; mesh.Parent=p
  elseif shape then p.Shape=shape end
  p.Parent=model; return p
 end
 local cocoa=Color3.fromRGB(71,38,27); local cream=Color3.fromRGB(255,232,192); local gold=Color3.fromRGB(231,172,67)
 if levels.temper>0 then
  part('TemperingMachine',Vector3.new(2,1,1.4),Vector3.new(-6,2.7,-5),Color3.fromRGB(149,171,173))
  local pot=part('CocoaBowl',Vector3.new(.55,1.2,1.2),Vector3.new(-6,3.4,-5),cocoa,Enum.PartType.Cylinder); pot.CFrame*=CFrame.Angles(0,0,math.pi/2)
  for i=1,levels.temper do part('MachineLevel',Vector3.new(.15,.15,.08),Vector3.new(-6.7+i*.22,2.7,-4.27),gold,Enum.PartType.Ball) end
 end
 if levels.library>0 then
  part('RecipeShelf',Vector3.new(3,.15,.8),Vector3.new(-4,4,-6),cocoa)
  for i=1,levels.library*2 do
   part('RecipeBook',Vector3.new(.22,.7+(i%3)*.12,.5),Vector3.new(-5.4+i*.25,4.45,-5.8),if i%2==0 then cream else Color3.fromRGB(106,141,117))
  end
 end
 if levels.clock>0 then
  part('ClockFrame',Vector3.new(1.5,1.5,.18),Vector3.new(6,5.8,-6),gold)
  part('ClockFace',Vector3.new(1.3,1.3,.2),Vector3.new(6,5.8,-5.98),cream)
  part('ClockHand',Vector3.new(.07,.5,.1),Vector3.new(6,6,-5.82),cocoa)
  part('ClockHand',Vector3.new(.4,.07,.1),Vector3.new(6.15,5.8,-5.82),cocoa)
 end
 if equipped.plant then
  part('CocoaPot',Vector3.new(1.1,1.1,1.1),Vector3.new(8.5,.45,9),cocoa)
  part('CocoaStem',Vector3.new(.16,2,.16),Vector3.new(8.5,1.8,9),cocoa)
  for i=1,5 do
   local leaf=part('CocoaLeaf',Vector3.new(1.5,.3,.8),Vector3.new(8.5+(if i%2==0 then .35 else -.35),1.4+i*.3,9),Color3.fromRGB(72,124,83),Enum.PartType.Ball)
   leaf.CFrame*=CFrame.Angles(0,i,if i%2==0 then .3 else -.3)
  end
 end
 if equipped.rug then
  part('CaramelRug',Vector3.new(8,.04,5),Vector3.new(0,-.075,9),cocoa)
  part('CaramelWeave',Vector3.new(7.5,.045,4.5),Vector3.new(0,-.065,9),gold)
  for i=-2,2 do part('RugPattern',Vector3.new(.18,.05,4.3),Vector3.new(i*1.3,-.055,9),cream) end
 end
 if equipped.art then
  part('ArtFrame',Vector3.new(.2,3.1,2.5),Vector3.new(-10.3,4,8),gold)
  part('ArtCanvas',Vector3.new(.22,2.7,2.1),Vector3.new(-10.25,4,8),cream)
  part('GoldenCocoa',Vector3.new(.26,1.9,1.1),Vector3.new(-10.1,4,8),cocoa,Enum.PartType.Ball)
 end
end
return Decor
