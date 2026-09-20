--!strict
-- Опора ножа — кончик лезвия: смена размера не сдвигает линию разреза.
local Knife = {}
function Knife.frame(point, direction, settings, roll)
 local scale=settings.renderScale*settings.knifeScale
 return CFrame.lookAt(point,point+direction)*CFrame.new(0,0,43*settings.unitsPerPixel*scale)*CFrame.Angles(0,0,roll)
end
function Knife.grip(frame,settings)
 return frame:PointToWorldSpace(Vector3.new(.04,.12,.92)*settings.renderScale*settings.knifeScale)
end
return Knife
