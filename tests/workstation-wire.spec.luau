--!nonstrict
-- Прогоняем настоящий формат ручного ввода через сервер к наблюдателю.
local Wire=require('../src/shared/WorkstationWire')
local Action=require('../src/client/WorkstationAction')
local Relay=require('../src/server/KitchenRelay')
local Config=require('../src/shared/Config')
local Recipe=require('../src/shared/Recipe')
local V3=require('@lune/roblox').Vector3
local function signal()
 local f={}; return {Connect=function(_,cb) table.insert(f,cb) end,Fire=function(_,...) for _,cb in f do cb(...) end end}
end
local function pose(t) return Action.cycle(t,Config,Recipe.build(Config.Recipe).slides) end
return function(h)
 h.test('сравнение сетевой позы замечает малое движение и видимость куска',function()
  local a=Wire.clean(pose(.1)); local b=Wire.clean(pose(.1))
  h.equals(Wire.samePose(nil,b),false); h.equals(Wire.samePose(a,b),true)
  b.knifePoint+=Vector2.new(.00001,0); h.equals(Wire.samePose(a,b),false)
  b=Wire.clean(pose(.1)); b.knifeDirection=-b.knifeDirection; h.equals(Wire.samePose(a,b),false)
  b=Wire.clean(pose(.1)); b.hidden.stripSingle=true; h.equals(Wire.samePose(a,b),false)
  b=Wire.clean(pose(.1)); b.offsets.stripDouble+=Vector2.new(.00001,0); h.equals(Wire.samePose(a,b),false)
  b=Wire.clean(pose(.1)); b.cutting=false; h.equals(Wire.samePose(a,b),false)
  b=Wire.clean(pose(.1)); b.whole=false; h.equals(Wire.samePose(a,b),false)
  local held=Wire.clean(pose(.7)); local copy=Wire.clean(pose(.7))
  copy.knifePoint=Vector2.new(9,9)
  h.equals(Wire.samePose(held,copy),true,'скрытый нож не является частью видимой позы')
 end)
 h.test('видимый сосед в очереди получает позы несмотря на удалённый физический остров',function()
  local now=0; local sent={}; local queries=0
  local function player(id,x)
   local attrs={KitchenOrigin=V3.new(x,0,1000),KitchenMode='walk',VisitingKitchen=id,VisitingCafeIndex=0}
   return {UserId=id,Parent=true,attrs=attrs,GetAttribute=function(_,k) return attrs[k] end,
    Character={FindFirstChild=function() return {Position=V3.new(x,3,1008)} end}}
  end
  local author,observer,far=player(1,0),player(2,256),player(3,512)
  author.attrs.KitchenMode='cut'
  local players={PlayerRemoving=signal(),GetPlayers=function() return {author,observer,far} end}
  local remote={OnServerEvent=signal(),FireClient=function(_,p,id,a) table.insert(sent,{p,id,a}) end}
  Relay.start(players,remote,Wire,function() return now end,function(p)
   queries+=1
   return if p==observer and p.attrs.VisitingKitchen==2 then {[1]=true} else {}
  end)
  remote.OnServerEvent:Fire(author,pose(.1))
  h.equals(#sent,1); h.equals(sent[1][1],observer); h.equals(sent[1][2],1)
  local firstQueries=queries
  now=.1; remote.OnServerEvent:Fire(author,pose(.15))
  h.equals(#sent,2); h.equals(queries,firstQueries,'очередь не пересчитывается на каждый пакет')
  remote.OnServerEvent:Fire(observer); h.equals(#sent,3,'новому наблюдателю доступен кеш')
  observer.attrs.VisitingKitchen=3
  now=.2; remote.OnServerEvent:Fire(author,pose(.2))
  h.equals(#sent,3,'смена посещаемой комнаты сразу отменяет старую подписку')
  observer.attrs.VisitingKitchen=2; observer.attrs.KitchenMode='cut'
  now=.3; remote.OnServerEvent:Fire(author,pose(.25)); h.equals(#sent,3)
  observer.attrs.KitchenMode='walk'
  now=1; remote.OnServerEvent:Fire(author,pose(.3)); h.equals(#sent,4)
  players.PlayerRemoving:Fire(author); author.Parent=nil
  now=2; remote.OnServerEvent:Fire(observer); h.equals(#sent,4)
 end)
 h.test('сеть отвергает некорректные и неограниченные координаты, не принимает деньги/автора',function()
  h.equals(Wire.clean(false),nil); h.equals(Wire.clean({}),nil)
  for _,v in {Vector2.new(0/0,0),Vector2.new(math.huge,0),Vector2.new(13,0),'bad'} do
   local a=pose(.2); a.offsets.upperLeft=v; h.equals(Wire.clean(a),nil)
  end
  local a=pose(.2); a.knifeDirection=Vector2.zero; h.equals(Wire.clean(a),nil)
  a=pose(.2); a.whole=false; h.equals(Wire.clean(a),nil)
  a=pose(.2); a.slices=1e9; a.userId=99; a.rightHand=Vector2.new(100,100)
  local clean=Wire.clean(a); assert(clean); h.equals(clean.slices,nil); h.equals(clean.userId,nil)
  h.near((clean.rightHand-clean.knifePoint).Magnitude,0)
 end)
 h.test('нож плавно движется между снимками, смена разреза не рисует ложную диагональ',function()
  local a,b=Wire.clean(pose(.01)),Wire.clean(pose(.08))
  local halfway=Wire.blend(a,b,.5)
  h.near((halfway.knifePoint-(a.knifePoint+b.knifePoint)/2).Magnitude,0)
  local nextCut=Wire.clean(pose(.25)); h.equals(Wire.blend(b,nextCut,.5),nextCut)
  local split=Wire.clean(pose(.6)); h.equals(Wire.blend(b,split,.5),split)
 end)
 h.test('перестановки передаются в единицах плитки без изменения формы',function()
  local a,b=Wire.clean(pose(.65)),Wire.clean(pose(.7))
  local mid=Wire.blend(a,b,.5)
  for _,name in Config.Trick.pieceOrder do h.near((mid.offsets[name]-(a.offsets[name]+b.offsets[name])/2).Magnitude,0) end
 end)
 h.test('два клиента: настоящий ручной разрез, ограничение частоты, кеш и выход автора',function()
  local now=0; local sent={}
  local function player(id,x,mode)
   local attrs={KitchenOrigin=V3.new(x,0,1000),KitchenMode=mode}
   return {UserId=id,Parent=true,attrs=attrs,GetAttribute=function(_,k) return attrs[k] end,
    Character={FindFirstChild=function() return {Position=V3.new(x,3,1008)} end}}
  end
  local author,observer,far,cutting=player(1,0,'cut'),player(2,24,'walk'),player(3,240,'walk'),player(4,48,'cut')
  local players={PlayerRemoving=signal(),GetPlayers=function() return {author,observer,far,cutting} end}
  local remote={OnServerEvent=signal(),FireClient=function(_,p,id,a) table.insert(sent,{p,id,a}) end}
  Relay.start(players,remote,Wire,function() return now end)
  local pieces={}
  for _,name in Config.Trick.pieceOrder do pieces[name]={origin=Vector2.zero,motion={Position={X={Offset=0},Y={Offset=0}},Visible=false}} end
  local manual=Action.player({intactLayer={Visible=true},active='cut',cutIndex=1,cutProgress=50,
   tileWidth=10,tileHeight=20,pieces=pieces,paths={{points={Vector2.new(0,70),Vector2.new(50,30)},geom={length=100}}}})
  manual.userId=999
  remote.OnServerEvent:Fire(author,manual)
  h.equals(#sent,1); h.equals(sent[1][1],observer); h.equals(sent[1][2],1)
  h.near((sent[1][3].knifePoint-manual.knifePoint).Magnitude,0)
  remote.OnServerEvent:Fire(author,manual); h.equals(#sent,1)
  now=.1; remote.OnServerEvent:Fire(author,manual); h.equals(#sent,2)
  -- Новый наблюдатель получает уже существующий снимок без ожидания жеста.
  remote.OnServerEvent:Fire(observer); h.equals(#sent,3)
  remote.OnServerEvent:Fire(observer); h.equals(#sent,3)
  now=20; remote.OnServerEvent:Fire(observer); h.equals(#sent,4,'кеш доступен, даже если автор давно не отправлял позу')
  h.near((sent[4][3].knifePoint-manual.knifePoint).Magnitude,0)
  players.PlayerRemoving:Fire(author); author.Parent=nil
  now=22; remote.OnServerEvent:Fire(observer); h.equals(#sent,4)
 end)
end
