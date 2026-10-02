--!nonstrict
-- Канонический снимок действий в координатах плитки. Его можно воспроизводить
-- локально или получать по сети, не меняя геометрию, rig и анимации станции.
local Motion = require("./Motion3D")
local Action = {}
local function hands(action)
 action.rightHand=action.knifePoint or (Vector2.new(1.5,1.8)+(action.offsets.upperLeft or Vector2.zero))
 action.leftHand=Vector2.new(3.7,1.2)+(action.offsets.upperRight or Vector2.zero)
 return action
end
function Action.cycle(t,config,slides,tileWidth,tileHeight)
 t=t%1
 local a={whole=t<.45,cutting=t<.45,offsets={}}
 local phase,p="explode",(t-.45)/.13
 if t>=.84 then phase,p="strip",math.min(1,(t-.84)/.12)
 elseif t>=.74 then phase,p="join",(t-.74)/.1
 elseif t>=.58 then phase,p="large",(t-.58)/.16 end
 for _,name in config.Trick.pieceOrder do
  a.offsets[name]=Motion.pose(name,phase,math.clamp(p,0,1),config.Scene3D.layouts.landscape,slides,config.Scene3D.passageY)
 end
 if a.cutting then
  -- Время распределяется по длине в мире, а не по числу разрезов.
  -- Долька вытянута: вертикальную длину нельзя считать в квадратных клетках.
  local width=tileWidth or config.Trick.baseTileWidth
  local height=tileHeight or config.Trick.baseTileHeight
  local lengths,total={},0
  for i,cut in config.Recipe.cuts do
   local dx,dy=cut[2][1]-cut[1][1],cut[2][2]-cut[1][2]
   local length=math.sqrt((dx*width)^2+(dy*height)^2)
   lengths[i]=length; total+=length
  end
  local distance=t/.45*total
  for i,cut in config.Recipe.cuts do
   local length=lengths[i]
   if distance<length or i==#lengths then
    local start,finish=Vector2.new(table.unpack(cut[1])),Vector2.new(table.unpack(cut[2]))
    a.knifePoint=start:Lerp(finish,math.clamp(distance/math.max(length,1e-9),0,1))
    a.knifeDirection=finish-start
    break
   end
   distance-=length
  end
 end
 return hands(a)
end
function Action.player(view,config)
 local a={whole=view.intactLayer.Visible,cutting=view.active=="cut" or view.active=="finishingCut",offsets={},hidden={}}
 for name,piece in view.pieces do
  if view.planarPhase and not a.whole then
   -- В общей кухне у игрока и NPC один стол и один маршрут. Переносим
   -- фактический прогресс жеста, сохраняя адаптивную раскладку самого игрока.
   a.offsets[name]=Motion.pose(name,view.planarPhase,view.planarProgress,
    config.Scene3D.layouts.landscape,view.recipe.slides,config.Scene3D.passageY)
  else
   local pos=piece.motion.Position
   a.offsets[name]=Vector2.new((pos.X.Offset-piece.origin.X)/view.tileWidth,(pos.Y.Offset-piece.origin.Y)/view.tileHeight)
  end
  a.hidden[name]=not piece.motion.Visible
 end
 if a.cutting then
  local path=view.paths[view.cutIndex]
  local start,finish=path.points[1],path.points[#path.points]
  local p=start:Lerp(finish,math.clamp(view.cutProgress/path.geom.length,0,1))
  a.knifePoint=Vector2.new(p.X/view.tileWidth,p.Y/view.tileHeight)
  a.knifeDirection=Vector2.new((finish.X-start.X)/view.tileWidth,(finish.Y-start.Y)/view.tileHeight)
 end
 return hands(a)
end
return Action
