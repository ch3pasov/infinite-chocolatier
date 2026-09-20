--!nonstrict
-- Сосед появляется независимо от момента загрузки атрибутов, уход завершает
-- наблюдение, дальние станции освобождают тяжёлую геометрию.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local Wire=require('../src/shared/WorkstationWire'); local Action=require('../src/client/WorkstationAction')
local Config=require('../src/shared/Config'); local Recipe=require('../src/shared/Recipe')
local function signal()
 local callbacks={}
 return {Connect=function(_,fn) callbacks[fn]=true; return {Disconnect=function() callbacks[fn]=nil end} end,
  Fire=function(_,...) for fn in callbacks do fn(...) end end}
end
return function(h)
 h.test('сосед с новым Instance или координатами заменяет старую комнату без пропущенного опроса',function()
  local stub=setmetatable({},{__index=function(_,key) return key end}); local models={}
  local workspace={FindFirstChild=function() return {GetChildren=function() return models end} end}
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function(_,name) return if name=='Workspace' then workspace else {WaitForChild=function() return stub end} end},
   script={Parent=stub},require=function(name) return if name=='CafeQueue' then require('../src/shared/CafeQueue') else {} end,
  },injectGlobals=true})()
  local function model(x)
   return {origin=R.Vector3.new(x,0,0),GetAttribute=function(self,key)
    return if key=='OwnerId' then 2 elseif key=='Origin' then self.origin else 0
   end}
  end
  local k={player={UserId=1},origin=R.Vector3.zero,opened=true}
  function k:setWalking() self.watchPeer=nil; self.focus=false end
  local online=setmetatable({kitchen=k,peers={},packets={},cycles={},elapsed=0,scan=0,request=0,
   remote={FireServer=function() end},updateIslands=function() end},Online)
  local created=0
  function online:add(source)
   created+=1
   local p={model=source,origin=source.origin,stations={},prompt={},player={UserId=2,GetAttribute=function() end},world={Destroy=function(self) self.destroyed=true end}}
   self.peers['2:0']=p; return p
  end
  models={model(256)}; online:step(.5)
  local first=online.peers['2:0']; online:step(.5); h.equals(created,1)
  local station={actor={setVisible=function() end},destroy=function(self) self.destroyed=true end}
  first.stations={station}; first.station=station; k.watchPeer=first; k.focus=true
  -- Исчезновение и повторное появление между двумя опросами: ключ остался.
  models={model(256)}; online:step(.5)
  local second=online.peers['2:0']
  h.equals(second.model,models[1],'источник остался старой моделью')
  h.equals(created,2); assert(first.world.destroyed and station.destroyed)
  h.equals(k.watchPeer,nil); h.equals(k.focus,false)
  models[1].origin=R.Vector3.new(512,0,0); online:step(.5)
  h.equals(created,3); assert(second.world.destroyed)
  h.equals(online.peers['2:0'].origin,models[1].origin)
  models={}; online:step(.5); h.equals(online.peers['2:0'],nil)
 end)
 h.test('цикл владельца сохраняет фазу при ускорении и долгом отсутствии кадров',function()
  local stub=setmetatable({},{__index=function(_,key) return key end})
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},
   script={Parent=stub},require=function() return {} end,
  },injectGlobals=true})()
  local function model(id,seconds)
   return {seconds=seconds,GetAttribute=function(self,key) return if key=='OwnerId' then id else self.seconds end}
  end
  local home=model(1,10); local copy=model(1,5)
  local online=setmetatable({cycles={},cycleSources={[1]=home}},Online)
  h.near(online:cyclePhase(home,2.3),.23)
  h.near(online:cyclePhase(copy,2.5),.25,'копия читает скорость из общего источника')
  home.seconds=5
  h.near(online:cyclePhase(home,2.5),.25,'новая скорость не меняет текущее положение')
  h.near(online:cyclePhase(copy,3),.35)
  h.near(online:cyclePhase(copy,1003),.35,'пауза учитывается без накопления кадров')
  home.seconds=0
  h.near(online:cyclePhase(home,1003),.35)
  h.near(online:cyclePhase(home,1003.0001),.36,'очень быстрый цикл ограничен 0.01 с')
  local phase=online.cycles[1].phase
  online:cyclePhase(model(2,10),1003)
  h.near(online.cycles[1].phase,phase,'разные владельцы не двигают чужой цикл')
 end)
 h.test('неподвижная ручная станция шлёт редкий снимок, движение сохраняет частоту',function()
  local now=0; local calls={}
  local stub=setmetatable({},{__index=function(_,key) return key end})
  local modules={WorkstationWire=Wire,WorkstationAction=Action}
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},
   script={Parent=stub},require=function(name) return modules[name] or {} end,
   os={clock=function() return now end},
  },injectGlobals=true})()
  local view={intactLayer={Visible=true},active='cut',cutIndex=1,cutProgress=0,
   tileWidth=10,tileHeight=20,pieces={},paths={{points={Vector2.new(0,70),Vector2.new(50,30)},geom={length=100}}}}
  for _,name in Config.Trick.pieceOrder do
   view.pieces[name]={origin=Vector2.zero,motion={Position={X={Offset=0},Y={Offset=0}},Visible=false}}
  end
  local k={opened=false,state={ready=true},view=view}
  local online=setmetatable({kitchen=k,elapsed=0,scan=0,
   remote={FireServer=function(_,a) table.insert(calls,a) end}},Online)
  -- За десять секунд было сто одинаковых пакетов. Редкий повтор остаётся,
  -- чтобы серверный лимит при сетевом всплеске не терял последнюю позу навсегда.
  for i=1,100 do now=i*.1; online:step(.1) end
  assert(#calls>=9 and #calls<=11,'ожидался примерно один снимок в секунду, получили '..#calls)
  local idle=#calls
  for i=1,10 do now=10+i*.1; view.cutProgress=i; online:step(.1) end
  h.equals(#calls,idle+10,'активная резка продолжает идти с частотой 10 Гц')
  h.near((calls[#calls].knifePoint-Action.player(view).knifePoint).Magnitude,0)
  now+=.1; view.pieces.stripSingle.motion.Visible=true; online:step(.1)
  h.equals(#calls,idle+11,'появление кусочка отправляется сразу')
  k.state.ready=false; now+=2; online:step(2)
  h.equals(#calls,idle+11,'неготовое состояние не отправляется')
 end)
 h.test('наблюдатель: поздние атрибуты, сеть, крупный план, дальние столы и уход игрока',function()
  local now=0; local calls={}; local objects={}; local stations={}
  local function new(class)
   local x={ClassName=class,Triggered=signal(),Destroy=function(self) self.destroyed=true end}
   table.insert(objects,x); return x
  end
  local localPlayer={UserId=1,GetAttribute=function() return nil end}; local peer={Parent=true,UserId=2,DisplayName='Neighbor',Name='neighbor'}
  local attrs={KitchenMode='cut'}
  function peer:GetAttribute(key) return attrs[key] end
  local position=R.Vector3.new(0,3,1008)
  localPlayer.Character={FindFirstChild=function() return {Position=position} end}
  local players={PlayerRemoving=signal(),GetPlayers=function() return {localPlayer,peer} end,GetPlayerByUserId=function(_,id) return if id==2 then peer else localPlayer end}
  local models={}
  local directory={GetChildren=function() return models end}
  local world={FindFirstChild=function() return directory end}
  local function model(id,origin,descendants)
   local attributes={OwnerId=id,Origin=origin,OwnerOnline=true,DisplayName='Neighbor',Username='neighbor'}
   return {GetAttribute=function(_,key) return attributes[key] end,SetAttribute=function(_,key,value) attributes[key]=value end,GetDescendants=function() return descendants or {} end}
  end
  local remote={OnClientEvent=signal(),FireServer=function(_,a) table.insert(calls,a or 'request') end}
  local k={player=localPlayer,world={GetChildren=function() return {} end},origin=R.Vector3.new(0,0,1000),opened=true,focus=false,view={recipe=Recipe.build(Config.Recipe)},
   state={ready=true},atelier={remotes={kitchenAction=remote}}}
  function k:setWalking() self.focus=false; self.watchPeer=nil; self.walked=true end
  function k:watchPlayer(p) self.watchPeer=p; self.focus=true end
  local modules={Structure=require("../src/shared/KitchenStructure"),Roster=require("../src/shared/StaffRoster"),Queue=require("../src/shared/CafeQueue"),Config=Config,Decor={update=function() end},Wire=Wire,Action=Action,Shell={new=function() end},Localization={text=function(t) return t end},Station={new=function(_,parent)
   local s={actor={setIdentity=function(self,id) self.identity=id end,setVisible=function(self,v) self.visible=v end},pose=function(self,a) self.action=a end,destroy=function(self) self.destroyed=true end}
   if parent.Name~="DistantCafeQueue" then table.insert(stations,s) end; return s
  end}}
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function(_,n) return if n=='Players' then players elseif n=='Workspace' then world else {WaitForChild=function() return {WorkstationWire='Wire',CafeQueue='Queue',StaffRoster='Roster',Config='Config',KitchenStructure='Structure'} end} end},
   script={Parent={WorkstationAction='Action',WorkstationView='Station',KitchenShell='Shell',KitchenDecor='Decor',Localization='Localization'}},
   require=function(id) return modules[id] end,Instance={new=new},Vector3=R.Vector3,UDim2=R.UDim2,Color3=R.Color3,
   Enum=R.Enum,os={clock=function() return now end},
  },injectGlobals=true})()
  local online=Online.new(k)
  online:step(.5); h.equals(online.peers['2:0'],nil)
  -- Наблюдаем все записи, а не только итоговый текст: мерцание вызывали
  -- два противоположных изменения свойства внутри одного обновления.
  local values={Name='NextCafePrompt',ActionText='Next cafe',Enabled=true}
  local writes={}
  local sign=setmetatable({IsA=function(_,class) return class=='ProximityPrompt' end},{__index=values,__newindex=function(_,key,value)
   table.insert(writes,{key=key,value=value}); values[key]=value
  end})
  local home=model(1,k.origin,{sign}); models={home}
  online:step(.5); h.equals(sign.ActionText,'Waiting for another cafe'); h.equals(#writes,1)
  for _=1,8 do online:step(.5) end
  h.equals(#writes,1,'ожидающая подсказка не должна обновляться каждый опрос')
  home:SetAttribute('StaffRoster','1001,1002,1003'); home:SetAttribute('CafeCount',1); online:step(.5)
  h.equals(#online.queueStations,2); h.equals(online.queueStations[1].station.actor.identity,1002); h.equals(online.queueStations[2].station.actor.identity,1003)
  h.equals(online.queueStations[1].station.actor.visible,true)
  -- Покупка скорости меняет темп, но не переносит руки и куски на другой
  -- этап. Старый os.clock()/cycle скачет здесь с 40% на 63% цикла.
  now=2.3; home:SetAttribute('CycleSeconds',10); online:step(.1)
  local beforeSpeed=online.queueStations[1].station.action
  home:SetAttribute('CycleSeconds',5); online:step(0)
  assert(Wire.samePose(beforeSpeed,online.queueStations[1].station.action),'покупка скорости перескочила на другой этап')
  now=2.4; online:step(.1)
  local faster=Action.cycle(.23+.17+.1/5,Config,k.view.recipe.slides)
  assert(Wire.samePose(faster,online.queueStations[1].station.action),'следующий шаг должен идти с новой скоростью')
  local oldQueueStation=online.queueStations[1].station
  h.equals(sign.ActionText,'Waiting for another cafe'); h.equals(#writes,1)
  online:step(.5); h.equals(#writes,1)
  home:SetAttribute('CafeCount',0); online:step(.5)
  h.equals(sign.ActionText,'Waiting for another cafe'); h.equals(#writes,1)
  assert(oldQueueStation.destroyed); h.equals(#online.queueStations,0)
  local firstObject=#objects+1
  home:SetAttribute("CafeCount",1000000); online:step(.5)
  h.equals(#online.queueStations,8,"три передних и один задний кабинет независимо от числа покупок")
  local rearStations=0
  for _,entry in online.queueStations do if entry.rear then rearStations+=1 end end
  h.equals(rearStations,2,'ближайший кабинет перед камерой содержит настоящие станции')
  local behind=0
  for i=firstObject,#objects do local p=objects[i]
   if p.Name=='DistantFloor' and p.Position.Z>k.origin.Z then behind+=1 end
  end
  h.equals(behind,1,'только второй задний кабинет остаётся облегчённым')
  for i=firstObject,#objects do local p=objects[i]
   if p.Name=='DistantWorkerHead' then
    assert(p.Position.Z<k.origin.Z or p.Position.Z>k.origin.Z+55,'блочный манекен в ближайшем заднем кабинете')
   end
  end
  local queueBefore=online.queue; local stationBefore=online.queueStations[1].station
  local createdBefore=#objects
  home:SetAttribute('StaffRoster','1001,2002,2003'); online:step(.5)
  h.equals(#objects,createdBefore,'смена друзей не должна пересоздавать геометрию очереди')
  h.equals(online.queue,queueBefore); h.equals(online.queueStations[1].station,stationBefore)
  h.equals(stationBefore.actor.identity,2002); h.equals(online.queueStations[2].station.actor.identity,2003)
  home:SetAttribute('StaffRoster',''); online:step(.5)
  h.equals(stationBefore.actor.identity,0,'исчезнувший друг заменяется запасным персонажем')
  h.equals(#objects,createdBefore); assert(not stationBefore.destroyed)
  -- Источник с тем же ключом может прийти новым Instance после повторного
  -- входа. Старые станции сохраняются, атрибуты читаются уже из новой модели.
  home=model(1,k.origin,{sign}); home:SetAttribute('CafeCount',1000000)
  home:SetAttribute('StaffRoster',''); home:SetAttribute('CycleSeconds',5)
  models={home}; online:step(.5)
  h.equals(online.queue,queueBefore); h.equals(online.queueStations[1].source,home)
  home:SetAttribute('StaffRoster','1001,3002,3003'); online:step(.5)
  h.equals(stationBefore.actor.identity,3002); h.equals(#objects,createdBefore)
  home:SetAttribute('HasApprentice',true); online:step(.5)
  assert(stationBefore.destroyed and online.queue~=queueBefore,'изменение состава комнаты пересобирает её')
  home:SetAttribute("CafeCount",0); online:step(.5)
  k.shopping=true; online:step(.5); h.equals(sign.Enabled,false)
  k.shopping=false; online:step(.5); h.equals(sign.Enabled,true)
  attrs.KitchenOrigin=R.Vector3.new(24,0,1000)
  models={model(1,k.origin),model(2,attrs.KitchenOrigin)}
  online:step(.5); assert(online.peers['2:0']); h.equals(#stations,2)
  local p=online.peers['2:0']; assert(p.prompt.Enabled)
  local action=Action.cycle(.7,Config,Recipe.build(Config.Recipe).slides)
  remote.OnClientEvent:Fire(2,action); online:step(.1)
  h.equals(online.queueStations[1].station.actor.visible,true)
  h.near((online.queueStations[1].station.action.offsets.upperLeft-action.offsets.upperLeft).Magnitude,0)
  h.equals(stations[1].actor.visible,true)
  h.near((stations[1].action.offsets.upperLeft-action.offsets.upperLeft).Magnitude,0)
  now=3; online:step(.1)
  h.near((stations[1].action.offsets.upperLeft-action.offsets.upperLeft).Magnitude,0)
  p.prompt.Triggered:Fire(); h.equals(k.watchPeer,p); online:step(.1)
  models[2]:SetAttribute('OwnerOnline',false); players.PlayerRemoving:Fire(peer); online:step(.5)
  assert(online.peers['2:0'],'гость должен продолжать видеть кафе без владельца')
  h.equals(stations[1].actor.visible,false)
  models={models[1]}; online:step(.5)
  assert(k.walked); assert(stations[1].destroyed); h.equals(online.peers['2:0'],nil)
  h.equals(online.cycles[2],nil,'цикл ушедшего владельца освобождается вместе с кафе')
  models[2]=model(2,attrs.KitchenOrigin)
  online:step(.5); assert(online.peers['2:0'])
  position=R.Vector3.new(400,0,1000); online:step(.1); h.equals(online.peers['2:0'].station,nil)
  models[2]=model(2,R.Vector3.new(400,0,1000)); models[2]:SetAttribute('CafeIndex',1)
  models[2]:SetAttribute('Staff1',101); models[2]:SetAttribute('Staff2',102)
  online:step(.5)
  local cafe=online.peers['2:1']; assert(cafe and cafe.staff); h.equals(#cafe.stations,2)
  h.equals(cafe.stations[1].actor.identity,101); h.equals(cafe.stations[2].actor.identity,102)
  h.equals(cafe.stations[1].actor.visible,true); h.equals(cafe.stations[2].actor.visible,true)
  models[2]:SetAttribute('Staff1',103); online:step(.1); h.equals(cafe.stations[1].actor.identity,103)
  local previous=online.packets[2]; online:destroy(); remote.OnClientEvent:Fire(2,action)
  h.equals(online.packets[2],previous)
 end)
 h.test('видимость кухни: очередь не обходится, новые модели и смена кафе учитываются',function()
  local stub=setmetatable({},{__index=function(_,key) return key end})
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},
   script={Parent=stub},require=function() return {} end,
  },injectGlobals=true})()
  local writes=0
  local function part(x)
   local values={Position=R.Vector3.new(x,0,0),LocalTransparencyModifier=0}
   return setmetatable({IsA=function(_,class) return class=='BasePart' end,GetDescendants=function() return {} end},
    {__index=values,__newindex=function(_,key,value) if key=='LocalTransparencyModifier' then writes+=1 end; values[key]=value end})
  end
  local home=part(0); local neighbor=part(256); local anchor=part(10)
  local descendants={home,neighbor}
  local branch={IsA=function() return false end,GetDescendants=function() return descendants end}
  local queue={IsA=function() error('очередь не должна обрабатываться') end,
   GetDescendants=function() error('не разворачивать дальнюю очередь') end}
  local branches={branch,queue,anchor}
  local kitchen={world={GetChildren=function() return branches end}}
  local online=setmetatable({kitchen=kitchen,queue=queue},Online)
  online:updateLocalVisibility(R.Vector3.zero)
  h.equals(home.LocalTransparencyModifier,0); h.equals(neighbor.LocalTransparencyModifier,1)
  h.equals(anchor.LocalTransparencyModifier,0); h.equals(writes,1)
  online:updateLocalVisibility(R.Vector3.zero); h.equals(writes,1,'не повторять неизменные свойства')
  -- Асинхронная загрузка аватара/покупка мебели после предыдущего обхода.
  local late=part(260); table.insert(descendants,late)
  online:updateLocalVisibility(R.Vector3.zero); h.equals(late.LocalTransparencyModifier,1); h.equals(writes,2)
  online:updateLocalVisibility(R.Vector3.new(256,0,0))
  h.equals(home.LocalTransparencyModifier,1); h.equals(anchor.LocalTransparencyModifier,1)
  h.equals(neighbor.LocalTransparencyModifier,0); h.equals(late.LocalTransparencyModifier,0)
  -- Удалённая ветка больше не удерживается в кеше и не получает записи.
  table.remove(descendants,3); table.remove(branches,2); online.queue=nil
  online:updateLocalVisibility(R.Vector3.zero)
  h.equals(late.LocalTransparencyModifier,0); h.equals(home.LocalTransparencyModifier,0)
 end)
end
