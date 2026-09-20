--!strict
-- Модель и движение используют одни опоры: кончик касается разреза,
-- остальная кромка поднимается над шоколадом, а цель для кисти находится в рукояти.
local Knife = {}
Knife.tip = Vector3.new(0, 0, -.95)
Knife.handle = Vector3.new(-.23, .025, .94)
Knife.cutRoll = math.rad(-38)
Knife.restRoll = math.rad(-8)
-- Профиль сантоку: прямой режущий край и плавно опускающийся к носику обух.
Knife.profile = {
 Vector3.new(0,0,-.95), Vector3.new(-.20,0,-.85),
 Vector3.new(-.34,0,-.65), Vector3.new(-.40,0,-.40),
 Vector3.new(-.40,0,.48), Vector3.new(0,0,.48),
}
function Knife.frame(point, direction, settings, roll)
 local scale=settings.renderScale*settings.knifeScale
 local rotation=CFrame.lookAt(Vector3.zero,direction)*CFrame.Angles(0,0,roll)*CFrame.Angles(math.rad(-5),0,0)
 return CFrame.new(point)*rotation*CFrame.new(-Knife.tip*scale)
end
function Knife.grip(frame,settings)
 return frame:PointToWorldSpace(Knife.handle*settings.renderScale*settings.knifeScale)
end
return Knife
