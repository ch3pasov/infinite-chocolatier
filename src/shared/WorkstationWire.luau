--!nonstrict
-- Сеть передаёт только ограниченную визуальную позу, никогда деньги/покупки.
-- Новые таблицы исключают произвольные ключи и ссылки на объекты из пакета.
local Config=require('./Config')
local Wire={}
local function vector(value,limit)
 return typeof(value)=='Vector2' and value.X==value.X and value.Y==value.Y
  and math.abs(value.X)<=limit and math.abs(value.Y)<=limit
end
function Wire.clean(raw)
 if type(raw)~='table' or type(raw.whole)~='boolean' or type(raw.cutting)~='boolean'
  or type(raw.offsets)~='table' then return nil end
 local a={whole=raw.whole,cutting=raw.cutting,offsets={},hidden={}}
 for _,name in Config.Trick.pieceOrder do
  local offset=raw.offsets[name]
  if not vector(offset,12) then return nil end
  a.offsets[name]=offset
  a.hidden[name]=type(raw.hidden)=='table' and raw.hidden[name]==true
 end
 if a.cutting then
  if not a.whole or not vector(raw.knifePoint,12) or not vector(raw.knifeDirection,12)
   or raw.knifeDirection.Magnitude<.001 then return nil end
  a.knifePoint=raw.knifePoint; a.knifeDirection=raw.knifeDirection
 end
 a.rightHand=a.knifePoint or Vector2.new(1.5,1.8)+a.offsets.upperLeft
 a.leftHand=Vector2.new(3.7,1.2)+a.offsets.upperRight
 return a
end
-- Сравниваются уже сформированные позы, не произвольный сетевой ввод.
-- Точность не округляем: даже небольшой реальный сдвиг должен дойти до зрителя.
function Wire.samePose(a,b)
 if not a or not b or a.whole~=b.whole or a.cutting~=b.cutting then return false end
 for _,name in Config.Trick.pieceOrder do
  if a.offsets[name]~=b.offsets[name] then return false end
  if (a.hidden and a.hidden[name]==true or false)~=(b.hidden and b.hidden[name]==true or false) then return false end
 end
 return not a.cutting or (a.knifePoint==b.knifePoint and a.knifeDirection==b.knifeDirection)
end
function Wire.blend(a,b,t)
 if not a or a.whole~=b.whole or a.cutting~=b.cutting then return b end
 local result={whole=b.whole,cutting=b.cutting,offsets={},hidden=b.hidden}
 t=math.clamp(t,0,1)
 for _,name in Config.Trick.pieceOrder do result.offsets[name]=a.offsets[name]:Lerp(b.offsets[name],t) end
 if b.cutting then
  -- Смена линии разреза не должна рисовать нож поперёк плитки.
  if a.knifeDirection.Unit:Dot(b.knifeDirection.Unit)<.99 then return b end
  result.knifePoint=a.knifePoint:Lerp(b.knifePoint,t); result.knifeDirection=b.knifeDirection
 end
 result.rightHand=a.rightHand:Lerp(b.rightHand,t); result.leftHand=a.leftHand:Lerp(b.leftHand,t)
 return result
end
return Wire
