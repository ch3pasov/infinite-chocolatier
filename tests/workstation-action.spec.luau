--!nonstrict
local Action=require("../src/client/WorkstationAction")
local Config=require("../src/shared/Config")
local Recipe=require("../src/shared/Recipe")
return function(h)
 local slides=Recipe.build(Config.Recipe).slides
 local function durations(w,h)
  local lengths={math.sqrt((5*w)^2+(2*h)^2),2.3*h,3*w,h}
  local total=0; for _,n in lengths do total+=n end
  for i,n in lengths do lengths[i]=.45*n/total end
  return lengths
 end
 local timing=durations(Config.Trick.baseTileWidth,Config.Trick.baseTileHeight)
 h.test("ученик проходит четыре настоящих разреза",function()
  local start=0
  for index,cut in Config.Recipe.cuts do
   local a=Action.cycle(start+timing[index]/2,Config,slides)
   start+=timing[index]
   h.equals(a.cutting,true)
   h.near(a.knifePoint.X,(cut[1][1]+cut[2][1])/2)
   h.near(a.knifePoint.Y,(cut[1][2]+cut[2][2])/2)
   if index==2 or index==4 then
    assert(a.knifeDirection.Y<0,'Стажёр должен вести оба вертикальных разреза снизу вверх')
   end
  end
 end)
 h.test("игрок и ученик дают одну позу для одинакового разреза",function()
  local auto=Action.cycle(timing[1]/2,Config,slides)
  local manual=Action.player({intactLayer={Visible=true},active="cut",cutIndex=1,cutProgress=50,
   tileWidth=10,tileHeight=20,pieces={},paths={{points={Vector2.new(0,70),Vector2.new(50,30)},geom={length=100}}}})
  h.equals(manual.whole,auto.whole)
  h.equals(manual.cutting,auto.cutting)
  h.near((manual.rightHand-auto.rightHand).Magnitude,0)
  h.near((manual.knifeDirection-auto.knifeDirection).Magnitude,0)
 end)
 h.test("конец цикла сохраняет собранные смещения и нож убран",function()
  local a=Action.cycle(.99,Config,slides)
  h.equals(a.cutting,false)
  h.equals(a.whole,false)
  for name,slide in slides do
   h.near(a.offsets[name].X,slide.dx)
   h.near(a.offsets[name].Y,slide.dy)
  end
 end)
 h.test("скорость ножа одинакова на длинном и коротком разрезах с учётом формы дольки",function()
  for _,size in {{58,92},{66,104},{10,20}} do
   local w,hg=size[1],size[2]; local time=durations(w,hg)
   local start,previousSpeed=0,nil
   for i,duration in time do
    local a=Action.cycle(start+duration*.4,Config,slides,w,hg)
    local b=Action.cycle(start+duration*.6,Config,slides,w,hg)
    local delta=b.knifePoint-a.knifePoint
    local speed=math.sqrt((delta.X*w)^2+(delta.Y*hg)^2)/(duration*.2)
    -- Координаты Vector2 округляются до float32: сравниваем относительную скорость.
    if previousSpeed then h.near(speed/previousSpeed,1) end
    previousSpeed=speed
    local begin=Action.cycle(start+1e-10,Config,slides,w,hg)
    h.near((begin.knifePoint-Vector2.new(table.unpack(Config.Recipe.cuts[i][1]))).Magnitude,0)
    start+=duration
   end
   assert(time[1]>time[4]*3)
   h.near(start,.45)
   h.equals(Action.cycle(.45,Config,slides,w,hg).cutting,false)
  end
 end)

end
