--!nonstrict
-- RequestState может получить ready=false до окончания DataStore-загрузки.
-- Исполняем настоящие методы кухни с таким неполным ответом.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local E=require('../src/shared/Economy')
local stub=setmetatable({},{__index=function(_,key) return key end})
local decorated=0
local Kitchen=luau.load(fs.readFile('src/client/Kitchen.luau'),{environment={
 game={GetService=function() return {WaitForChild=function() return stub end} end},
 script={Parent=stub},Color3=R.Color3,
 require=function(name)
  return if name=='KitchenDecor' then {update=function() decorated+=1 end} else {}
 end,
},injectGlobals=true})()
return function(h)
 h.test('наблюдение чужого стажёра выбирает правый стол и возвращает управление без сброса разреза',function()
  local Watch=luau.load(fs.readFile('src/client/Kitchen.luau'),{environment={
   game={GetService=function() return {WaitForChild=function() return stub end} end},
   workspace={FindFirstChild=function() end},script={Parent=stub},Color3=R.Color3,Vector3=R.Vector3,CFrame=R.CFrame,Enum=R.Enum,
   require=function(name)
    return if name=='Localization' then {set=function(label,key,args) label.source=key; label.args=args end,number=tostring}
     elseif name=='KitchenCatalog' then {selected=function() return 0 end}
     elseif name=='WorkstationAction' then {player=function() return {} end,cycle=function() return {} end}
     elseif name=='KitchenDecor' then {update=function() end} else {}
   end,
  },injectGlobals=true})()
  local enabled=true; local modes={}; local activeCamera
  local state=E.snapshot(E.load(nil)); state.ready=true
  local actor={setVisible=function() end}
  local k=setmetatable({opened=true,state=state,origin=R.Vector3.new(0,0,1000),world={},view={cutIndex=3,cutProgress=47,recipe={slides={}}},
   root={AbsoluteSize=R.Vector2.new(390,844)},camera={CFrame=R.CFrame.identity},walkCamera={},panel={},info={},prompts={},
   online={step=function() end,blockPrompts=function() end},
   stations={{actor=actor,pose=function() end},{actor=actor,pose=function() end}},
   controls={Disable=function() enabled=false end,Enable=function() enabled=true end},
   stage={activate=function(_,_,camera) activeCamera=camera end},
   atelier={remotes={kitchenMode={FireServer=function(_,mode) table.insert(modes,mode) end}}},
   walkController={step=function() end},setAvatarVisible=function() end,updateOnboarding=function() end,
  },{__index=Watch})
  local hired=true; local origin=R.Vector3.new(256,0,1000)
  local peer={origin=origin,staff=false,model={GetAttribute=function() return hired end},
   player={DisplayName='Neighbor',GetAttribute=function() return 'walk' end},
   stations={{actor={height=5}},{actor={height=9}}},
  }
  k:watchPlayer(peer,2)
  h.equals(k.watchPeer,peer); h.equals(k.watchSide,2); h.equals(enabled,false); h.equals(activeCamera,k.camera)
  assert(math.abs(k.camera.Focus.Position.X-origin.X-3.7)<.001,'камера должна смотреть на правый стол'); h.near(k.camera.Focus.Position.Y,4.5)
  h.equals(k.info.source,"Watching {name}'s apprentice"); h.equals(k.info.args.name,'Neighbor')
  h.equals(modes[#modes],'watch'); h.equals(k.panel.Visible,true)
  k:setWalking()
  h.equals(k.watchPeer,nil); h.equals(k.watchSide,nil); h.equals(k.focus,false); h.equals(enabled,true); h.equals(activeCamera,k.walkCamera)
  h.equals(modes[#modes],'walk'); h.equals(k.view.cutIndex,3); h.equals(k.view.cutProgress,47)
  k:watchPlayer(peer)
  h.equals(k.watchSide,1); assert(math.abs(k.camera.Focus.Position.X-origin.X+3.7)<.001,'камера игрока должна смотреть на левый стол'); h.near(k.camera.Focus.Position.Y,2.5)
  h.equals(k.info.source,'{name} is away from their worktable')
  k:setWalking(); hired=false; k:watchPlayer(peer,2)
  h.equals(k.focus,false); h.equals(k.watchPeer,nil); h.equals(enabled,true)
 end)
 h.test('кухня переживает ответ загрузки без levels и последующий готовый профиль',function()
  decorated=0
  local closed=0
  local k=setmetatable({opened=false,view={},prompts={{Enabled=true}},guide={},bookGuide={},
   online={step=function() end},atelier={setOpen=function() closed+=1 end}},{__index=Kitchen})
  k:update({ready=false}); k:step(0); k:openShop(); k:setOpen(true); k:watchPlayer({})
  h.equals(k.opened,false); h.equals(k.shopping,nil); h.equals(k.focus,nil)
  h.equals(decorated,0); h.equals(k.prompts[1].Enabled,false)
  local ready=E.snapshot(E.load(nil)); ready.ready=true
  k:update(ready); h.equals(k.state,ready); h.equals(decorated,1)
  local unlocked=E.snapshot(E.load({levels={kitchen=1}})); unlocked.ready=true
  k:update(unlocked); h.equals(closed,1); h.equals(decorated,2)
  k.opened=true
  k:update({ready=false}); k:step(.5)
  k:update(unlocked); h.equals(k.state,unlocked); h.equals(decorated,3)
 end)
end
