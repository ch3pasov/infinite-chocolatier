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
function Action.cycle(t,config,slides)
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
  local segment=t/.45*4
  local cut=config.Recipe.cuts[math.min(4,math.floor(segment)+1)]
  local start,finish=Vector2.new(table.unpack(cut[1])),Vector2.new(table.unpack(cut[2]))
  a.knifePoint=start:Lerp(finish,segment%1); a.knifeDirection=finish-start
 end
 return hands(a)
end
function Action.player(view)
 local a={whole=view.intactLayer.Visible,cutting=view.active=="cut" or view.active=="finishingCut",offsets={},hidden={}}
 for name,piece in view.pieces do
  local pos=piece.motion.Position
  a.offsets[name]=Vector2.new((pos.X.Offset-piece.origin.X)/view.tileWidth,(pos.Y.Offset-piece.origin.Y)/view.tileHeight)
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
