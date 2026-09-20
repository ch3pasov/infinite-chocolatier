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
