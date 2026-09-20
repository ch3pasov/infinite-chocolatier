--!nonstrict
-- Превью собираются тем же построителем, что предметы в комнате: внешний вид
-- карточки не расходится с покупкой. Здесь нет анимаций и загрузок из сети.
local Decor=require(script.Parent.KitchenDecor)
local Thumbnails={}
function Thumbnails.new(parent,spec)
 local viewport=Instance.new('ViewportFrame'); viewport.Name='ItemPreview'
 viewport.BackgroundTransparency=1; viewport.Size=UDim2.fromScale(1,1); viewport.Parent=parent
 viewport.Ambient=Color3.fromRGB(210,210,210); viewport.LightColor=Color3.new(1,1,1); viewport.LightDirection=Vector3.new(-1,-1,-1)
 local world=Instance.new('WorldModel'); world.Parent=viewport
 local model
 if spec.group=='workers' then
  -- Силуэт обозначает рабочее место, а не обещает конкретный скин друга.
  model=Instance.new('Model'); model.Parent=world
  for _,p in {{'Head',Vector3.new(1,1,1),Vector3.new(0,2,0),Color3.fromRGB(237,195,147)},
   {'Torso',Vector3.new(2,2,1),Vector3.new(0,.5,0),Color3.fromRGB(98,159,136)},
   {'LeftArm',Vector3.new(.7,2,.7),Vector3.new(-1.4,.5,0),Color3.fromRGB(237,195,147)},
   {'RightArm',Vector3.new(.7,2,.7),Vector3.new(1.4,.5,0),Color3.fromRGB(237,195,147)}} do
   local part=Instance.new('Part'); part.Name=p[1]; part.Size=p[2]; part.Position=p[3]; part.Color=p[4]; part.Anchored=true; part.Parent=model
  end
 else
  local scene={world=world,origin=Vector3.zero}
  Decor.update(scene,{equipped={}},spec.id); model=scene.decorModel
 end
 local cf,size=model:GetBoundingBox()
 local direction=if spec.group=='art' then Vector3.new(1,.25,.5) elseif spec.group=='rug' then Vector3.new(.15,1,.65) else Vector3.new(.3,.25,1)
 local camera=Instance.new('Camera'); camera.FieldOfView=35
 camera.CFrame=CFrame.lookAt(cf.Position+direction.Unit*math.max(size.X,size.Y,size.Z)*2.1,cf.Position)
 camera.Parent=viewport; viewport.CurrentCamera=camera
 return viewport
end
return Thumbnails
