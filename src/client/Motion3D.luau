--!strict
-- Перенос крупного куска по дуге: сначала поднять, пронести над соседом,
-- выйти за его край и только затем опустить. Обратный жест идёт той же дугой.
local Motion = {}
function Motion.offset(name, raw, active, settings, slides, tileWidth, tileHeight)
	local result=Vector3.new(raw.X*settings.unitsPerPixel,0,raw.Y*settings.unitsPerPixel)
	if name~='upperLeft' or (active~='assembleLarge' and active~='snappingLarge') then return result end
	local start=settings.exploded[name]
	local finish=slides[name]
	local a=Vector2.new(start.dx*tileWidth,start.dy*tileHeight)
	local delta=Vector2.new((finish.dx-start.dx)*tileWidth,(finish.dy-start.dy)*tileHeight)
	local t=math.clamp((raw-a):Dot(delta)/delta:Dot(delta),0,1)
	local ramp=math.clamp(math.min(t/0.12,(1-t)/0.12),0,1)
	local lift=ramp*ramp*(3-2*ramp)*settings.carryHeight
	local bow=settings.carryBow*t*(1-t)
	-- Боковой обход идёт по касательной к диагонали, иначе его носик
	-- войдёт в неподвижное основание перед приземлением.
	return result+Vector3.new(bow*tileWidth*settings.unitsPerPixel,lift,-0.4*bow*tileHeight*settings.unitsPerPixel)
end
return Motion
