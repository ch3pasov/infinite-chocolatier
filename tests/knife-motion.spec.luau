--!nonstrict
local R=require('@lune/roblox')
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local Knife=luau.load(fs.readFile('src/client/KnifeMotion.luau'),{environment={CFrame=R.CFrame,Vector3=R.Vector3},injectGlobals=true})()
return function(h)
 h.test('кончик большого ножа остаётся на разрезе при любом наклоне',function()
  for _,size in {1,2.2} do
   local settings={knifeScale=size,renderScale=.25,unitsPerPixel=.02}
   for _,direction in {R.Vector3.new(1,0,-1),R.Vector3.new(0,0,1),R.Vector3.new(1,0,0)} do
    for _,roll in {Knife.cutRoll,Knife.restRoll} do
     local point=R.Vector3.new(5,.18,8)
     local frame=Knife.frame(point,direction,settings,roll)
     local tip=frame:PointToWorldSpace(Knife.tip*size*.25)
     assert((tip-point).Magnitude<.00001)
     local grip=Knife.grip(frame,settings)
     assert((grip-tip).Magnitude>.4*size)
     assert((grip-tip):Dot(direction.Unit)>0,"Рукоять должна идти впереди кончика при прежнем направлении жеста")
    end
   end
  end
 end)
 h.test('нож стоит ребром, а режущая кромка следует линии без бокового завала',function()
  local settings={knifeScale=2.2,renderScale=.25}
  for angle=0,350,10 do
   local direction=R.Vector3.new(math.cos(math.rad(angle)),0,math.sin(math.rad(angle)))
   for _,roll in {Knife.cutRoll,Knife.restRoll} do
    local frame=Knife.frame(R.Vector3.zero,direction,settings,roll)
    local normal=frame:VectorToWorldSpace(R.Vector3.yAxis)
    assert(math.abs(normal.Y)<1e-6,'Плоскость лезвия должна быть вертикальной')
    local edge=frame:VectorToWorldSpace(R.Vector3.zAxis)
    local projection=R.Vector3.new(edge.X,0,edge.Z).Unit
    assert(projection:Dot(direction)>.99999,'Кромка не должна поворачиваться поперёк разреза')
    assert(edge.Y>0 and edge.Y<.1,'Рукоять лишь немного выше кончика')
   end
  end
 end)
 h.test('лезвие при резке не проваливается в верхушки шоколада',function()
  local settings={knifeScale=2.2,renderScale=.25}
  for angle=0,350,10 do
   local direction=R.Vector3.new(math.cos(math.rad(angle)),0,math.sin(math.rad(angle)))
   local frame=Knife.frame(R.Vector3.zero,direction,settings,Knife.cutRoll)
   for _,vertex in Knife.profile do
    for _,height in {0,.055} do
     local p=frame:PointToWorldSpace((vertex+R.Vector3.new(0,height,0))*.55)
     assert(p.Y>=-1e-6,'Сталь должна оставаться выше точки контакта')
    end
   end
  end
 end)
end
