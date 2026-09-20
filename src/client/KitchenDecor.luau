--!nonstrict
-- Покупки меняют предметы в комнате. Перестраиваем только при смене набора,
-- а не при каждом секундном обновлении баланса.
local Catalog=require(game:GetService('ReplicatedStorage').Shared.KitchenCatalog)
local Decor={}
function Decor.update(kitchen,state,previewId)
 local selected={}
 for _,group in {'temper','library','clock','plant','rug','art'} do selected[group]=Catalog.selected(state,group,previewId) end
 local key=table.concat({selected.temper,selected.library,selected.clock,selected.plant,selected.rug,selected.art},':')
 local equipped={plant=selected.plant>0,rug=selected.rug>0,art=selected.art>0}
 if kitchen.decorKey==key then return end
 kitchen.decorKey=key
 if kitchen.decorModel then kitchen.decorModel:Destroy() end
 local model=Instance.new('Model'); model.Name='PurchasedKitchenItems'; model.Parent=kitchen.world; kitchen.decorModel=model
 local function part(name,size,pos,color,shape)
  local p=Instance.new('Part'); p.Name=name; p.Size=size; p.Position=kitchen.origin+pos
  p.TopSurface=Enum.SurfaceType.Smooth; p.BottomSurface=Enum.SurfaceType.Smooth
  p.Anchored=true; p.CanCollide=false; p.Material=Enum.Material.SmoothPlastic; p.Color=color
  if shape==Enum.PartType.Ball then
   -- Part-шар берёт минимальный размер: для плоских листьев и какао нужен mesh.
   local mesh=Instance.new('SpecialMesh'); mesh.MeshType=Enum.MeshType.Sphere; mesh.Parent=p
  elseif shape then p.Shape=shape end
  p.Parent=model; return p
 end
 local cocoa=Color3.fromRGB(71,38,27); local cream=Color3.fromRGB(255,232,192); local gold=Color3.fromRGB(231,172,67)
 local colors={Color3.fromRGB(156,90,51),cream,Color3.fromRGB(98,159,136),Color3.fromRGB(157,80,111),gold}
 local v=selected.temper
 if v>0 then
  local width=if v==4 then 2.8 else 2
  part('TemperingMachine',Vector3.new(width,if v==3 then 1.6 else 1,1.4),Vector3.new(-6,2.7,-5),colors[v])
  for i=1,if v==2 or v==5 then 2 else 1 do
   local x=-6+(if v==2 or v==5 then (i-1.5)*.9 else 0)
   local pot=part('CocoaBowl',Vector3.new(.55,.85,.85),Vector3.new(x,if v==3 then 3.75 else 3.4,-5),cocoa,Enum.PartType.Cylinder)
   pot.CFrame*=CFrame.Angles(0,0,math.pi/2)
  end
  if v==4 then
   local gauge=part('MachineGauge',Vector3.new(.65,.65,.12),Vector3.new(-6,2.85,-4.23),cream,Enum.PartType.Ball)
  elseif v==5 then
   for _,x in {-6.85,-5.15} do part('MachineArch',Vector3.new(.12,1.4,.15),Vector3.new(x,3.5,-5.5),gold) end
   part('MachineArchTop',Vector3.new(1.8,.15,.15),Vector3.new(-6,4.2,-5.5),gold)
  end
  for i=1,v do part('MachineButton',Vector3.new(.12,.12,.08),Vector3.new(-6.7+i*.22,2.5,-4.27),gold,Enum.PartType.Ball) end
 end
 v=selected.library
 if v>0 then
  part('RecipeShelf',Vector3.new(3,.15,.8),Vector3.new(-4,4,-6),colors[v])
  if v==1 or v==4 then
   for i=1,if v==1 then 1 else 2 do
    local book=part('RecipeBook',Vector3.new(1.1,.15,.65),Vector3.new(-4+(i-1)*.8,4.18,-5.8),cream)
    book.CFrame*=CFrame.Angles(0,0,if i==1 then .12 else -.12)
   end
  elseif v==3 then
   for i=1,4 do
    local book=part('RecipeBook',Vector3.new(1.3,.16,.55),Vector3.new(-4,4.15+i*.18,-5.8),if i%2==0 then cream else colors[v])
    book.CFrame*=CFrame.Angles(0,i*.3,0)
   end
  else
   for i=1,if v==5 then 9 else 5 do
    part('RecipeBook',Vector3.new(.22,.7+(i%3)*.12,.5),Vector3.new(-5.4+i*.27,4.5,-5.8),if i%2==0 then cream else colors[v])
   end
   if v==5 then
    for _,x in {-5.5,-2.5} do part('LibrarySide',Vector3.new(.15,1.3,.8),Vector3.new(x,4.6,-6),gold) end
    part('LibraryTop',Vector3.new(3.1,.15,.8),Vector3.new(-4,5.3,-6),gold)
   end
  end
 end
 v=selected.clock
 if v>0 then
  local frame=part('ClockFrame',Vector3.new(1.5,1.5,.22),Vector3.new(6,5.5,-6),colors[v],if v==2 then Enum.PartType.Ball else nil)
  if v==3 then frame.CFrame*=CFrame.Angles(0,0,math.pi/4) end
  part('ClockFace',Vector3.new(1.2,1.2,.12),Vector3.new(6,5.5,-5.8),cream,if v==2 or v==4 then Enum.PartType.Ball else nil)
  if v==4 then part('ClockCrown',Vector3.new(1.5,.6,.22),Vector3.new(6,6.2,-6),colors[v],Enum.PartType.Ball) end
  if v==5 then
   part('PendulumCase',Vector3.new(.9,1.1,.2),Vector3.new(6,4.25,-6),cocoa)
   part('PendulumStem',Vector3.new(.08,.8,.1),Vector3.new(6,4.4,-5.8),gold)
   part('PendulumBob',Vector3.new(.45,.45,.12),Vector3.new(6,4,-5.75),gold,Enum.PartType.Ball)
  end
  part('ClockHand',Vector3.new(.07,.45,.08),Vector3.new(6,5.68,-5.68),cocoa)
  part('ClockHand',Vector3.new(.4,.07,.08),Vector3.new(6.15,5.5,-5.68),cocoa)
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
