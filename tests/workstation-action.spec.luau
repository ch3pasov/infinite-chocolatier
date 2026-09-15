--!nonstrict
local Action=require("../src/client/WorkstationAction")
local Config=require("../src/shared/Config")
local Recipe=require("../src/shared/Recipe")
return function(h)
 local slides=Recipe.build(Config.Recipe).slides
 h.test("ученик проходит четыре настоящих разреза",function()
  for index,cut in Config.Recipe.cuts do
   local a=Action.cycle(((index-1)+.5)*.45/4,Config,slides)
   h.equals(a.cutting,true)
   h.near(a.knifePoint.X,(cut[1][1]+cut[2][1])/2)
   h.near(a.knifePoint.Y,(cut[1][2]+cut[2][2])/2)
  end
 end)
 h.test("игрок и ученик дают одну позу для одинакового разреза",function()
  local auto=Action.cycle(.45/8,Config,slides)
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
end
