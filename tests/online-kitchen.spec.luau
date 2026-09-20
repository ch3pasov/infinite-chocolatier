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
  local function model(id,origin)
   local attributes={OwnerId=id,Origin=origin,OwnerOnline=true,DisplayName='Neighbor',Username='neighbor'}
   return {GetAttribute=function(_,key) return attributes[key] end,SetAttribute=function(_,key,value) attributes[key]=value end,GetDescendants=function() return {} end}
  end
  local remote={OnClientEvent=signal(),FireServer=function(_,a) table.insert(calls,a or 'request') end}
  local k={player=localPlayer,world={GetDescendants=function() return {} end},origin=R.Vector3.new(0,0,1000),opened=true,focus=false,view={},
   state={ready=true},atelier={remotes={kitchenAction=remote}}}
  function k:setWalking() self.focus=false; self.watchPeer=nil; self.walked=true end
  function k:watchPlayer(p) self.watchPeer=p; self.focus=true end
  local modules={Wire=Wire,Action=Action,Shell={new=function() end},Localization={text=function(t) return t end},Station={new=function()
   local s={actor={setVisible=function(self,v) self.visible=v end},pose=function(self,a) self.action=a end,destroy=function(self) self.destroyed=true end}
   table.insert(stations,s); return s
  end}}
  local Online=luau.load(fs.readFile('src/client/OnlineKitchen.luau'),{environment={
   game={GetService=function(_,n) return if n=='Players' then players elseif n=='Workspace' then world else {WaitForChild=function() return {WorkstationWire='Wire'} end} end},
   script={Parent={WorkstationAction='Action',WorkstationView='Station',KitchenShell='Shell',Localization='Localization'}},
   require=function(id) return modules[id] end,Instance={new=new},Vector3=R.Vector3,UDim2=R.UDim2,Color3=R.Color3,
   Enum=R.Enum,os={clock=function() return now end},
  },injectGlobals=true})()
  local online=Online.new(k)
  online:step(.5); h.equals(online.peers[2],nil)
  attrs.KitchenOrigin=R.Vector3.new(24,0,1000)
  models={model(1,k.origin),model(2,attrs.KitchenOrigin)}
  online:step(.5); assert(online.peers[2]); h.equals(#stations,1)
  local p=online.peers[2]; assert(p.prompt.Enabled)
  local action=Action.cycle(.7,Config,Recipe.build(Config.Recipe).slides)
  remote.OnClientEvent:Fire(2,action); online:step(.1)
  h.equals(stations[1].actor.visible,true)
  h.near((stations[1].action.offsets.upperLeft-action.offsets.upperLeft).Magnitude,0)
  now=3; online:step(.1)
  h.near((stations[1].action.offsets.upperLeft-action.offsets.upperLeft).Magnitude,0)
  p.prompt.Triggered:Fire(); h.equals(k.watchPeer,p); online:step(.1); h.equals(p.billboard.Enabled,false)
  models[2]:SetAttribute('OwnerOnline',false); players.PlayerRemoving:Fire(peer); online:step(.5)
  assert(online.peers[2],'гость должен продолжать видеть кафе без владельца')
  h.equals(stations[1].actor.visible,false)
  models={models[1]}; online:step(.5)
  assert(k.walked); assert(stations[1].destroyed); h.equals(online.peers[2],nil)
  models[2]=model(2,attrs.KitchenOrigin)
  online:step(.5); assert(online.peers[2])
  position=R.Vector3.new(400,0,1000); online:step(.1); h.equals(online.peers[2].station,nil)
  -- Личная очередь ограничена тремя копиями, начинается после посещаемого кафе.
  models={model(1,k.origin),model(2,attrs.KitchenOrigin),model(3,R.Vector3.new(512,0,1000)),model(4,R.Vector3.new(768,0,1000)),model(5,R.Vector3.new(1024,0,1000))}
  online:step(.5)
  local count=0
  for _,object in objects do if object.Name=='DistantTerrace' and object.Parent==online.queue then
   count+=1; h.equals(object.Position.X,0); assert(object.Position.Z<1000)
  end end
  h.equals(count,3)
  local oldQueue=online.queue
  function localPlayer:GetAttribute() return 5 end
  online:step(.5); assert(oldQueue.destroyed)
  count=0
  for _,object in objects do if object.Name=='DistantTerrace' and object.Parent==online.queue then count+=1; h.equals(object.Position.X,1024) end end
  h.equals(count,3)
  local previous=online.packets[2]; online:destroy(); remote.OnClientEvent:Fire(2,action)
  h.equals(online.packets[2],previous)
 end)
end
