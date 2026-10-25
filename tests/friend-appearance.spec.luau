--!nonstrict
local A=require('../src/client/FriendAppearance')
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local R=require('@lune/roblox')
local function character(kind)
 local model=R.Instance.new('Model'); model.Archivable=false; model:SetAttribute('AvatarReady',true)
 local hum=R.Instance.new('Humanoid'); hum.RigType=R.Enum.HumanoidRigType[kind or 'R15']; hum.Parent=model
 local root=R.Instance.new('Part'); root.Name='HumanoidRootPart'; root.Transparency=1; root.Parent=model
 local head=R.Instance.new('Part'); head.Name='Head'; head.Color=R.Color3.fromRGB(220,170,120); head.Parent=model
 local shirt=R.Instance.new('Shirt'); shirt.ShirtTemplate='rbxassetid://1234'; shirt.Parent=model
 return model
end
local function concurrentAppearance()
 return luau.load(fs.readFile('src/client/FriendAppearance.luau'),{environment={
  task={wait=function() coroutine.yield() end},
 },injectGlobals=true})()
end
local function resume(thread)
 local ok,err=coroutine.resume(thread); assert(ok,err)
end
return function(h)
 h.test('игрок за столом сохраняет реальные цвета, одежду и свой R15 или R6 без чтения описания',function()
  for _,kind in {'R15','R6'} do
   local source=character(kind)
   local players={GetPlayerByUserId=function(_,id) h.equals(id,12); return {Character=source} end,
    GetHumanoidDescriptionFromUserIdAsync=function() error('не брать устаревшее описание аккаунта') end,
    CreateHumanoidModelFromDescriptionAsync=function() error('не собирать игрока из пустого описания') end}
   local ok,rig,loaded,err,original=A.createPlayerRig(players,{},12,'R15')
   assert(ok and loaded and not err and rig~=source); h.equals(original,source)
   h.equals(rig.Humanoid.RigType,source.Humanoid.RigType); h.equals(rig.Head.Color,source.Head.Color)
   h.equals(rig.Shirt.ShirtTemplate,source.Shirt.ShirtTemplate); h.equals(source.Archivable,false)
   h.equals(rig.HumanoidRootPart.Transparency,1)
   rig:Destroy(); source:Destroy()
  end
 end)
 h.test('копия скрытого игрока снимает обе маски и не переносит скрипты, инструменты и щит',function()
  local source=character(); source.Head.Transparency=1; source.Head.LocalTransparencyModifier=1
  source.Head:SetAttribute('KitchenOriginalTransparency',.35)
  local face=R.Instance.new('Decal'); face.Transparency=1; face:SetAttribute('KitchenOriginalTransparency',.2); face.Parent=source.Head
  for _,kind in {'LocalScript','Script','Tool','ForceField'} do R.Instance.new(kind).Parent=source end
  local ok,rig=A.createPlayerRig({GetPlayerByUserId=function() return {Character=source} end},{},12,'R15')
  assert(ok); h.near(rig.Head.Transparency,.35); h.equals(rig.Head.LocalTransparencyModifier,0)
  h.near(rig.Head.Decal.Transparency,.2); h.equals(rig.Head:GetAttribute('KitchenOriginalTransparency'),nil)
  for _,kind in {'LocalScript','Script','Tool','ForceField'} do h.equals(rig:FindFirstChildOfClass(kind),nil) end
  h.equals(source.Head.Transparency,1); h.equals(source.Head.LocalTransparencyModifier,1)
  h.near(source.Head:GetAttribute('KitchenOriginalTransparency'),.35); h.equals(source.Archivable,false)
  rig:Destroy(); source:Destroy()
 end)
 h.test('ожидание готового спавна не создаёт чёрного болванчика и отменяется при смене персонажа',function()
  for _,cancel in {'ready','station','respawn','timeout'} do
   local appearance=concurrentAppearance(); local source=character(); source:SetAttribute('AvatarReady',nil)
   local p={Character=source}; local current=true; local ok,rig
   local thread=coroutine.create(function()
    ok,rig=appearance.createPlayerRig({GetPlayerByUserId=function() return p end},{},12,'R15',function() return current end)
   end)
   resume(thread); h.equals(coroutine.status(thread),'suspended'); h.equals(rig,nil)
   if cancel=='ready' then source:SetAttribute('AvatarReady',true)
   elseif cancel=='station' then current=false
   elseif cancel=='respawn' then p.Character=character() end
   for _=1,100 do if coroutine.status(thread)~='dead' then resume(thread) end end
   h.equals(coroutine.status(thread),'dead'); h.equals(ok,cancel=='ready')
   if rig then rig:Destroy() end
   h.equals(source.Archivable,false); source:Destroy()
   if p.Character~=source then p.Character:Destroy() end
  end
 end)
 h.test('сбой клонирования восстанавливает Archivable, онлайн-игрок без тела не берётся из кэша стажёра',function()
  local source={Archivable=false,GetAttribute=function() return true end,FindFirstChildOfClass=function() return {} end,
   FindFirstChild=function() return {} end,Clone=function() error('clone failure') end}
  local players={GetPlayerByUserId=function() return {Character=source} end}
  local ok,_,_,err=A.createPlayerRig(players,{},12,'R15')
  h.equals(ok,false); h.equals(source.Archivable,false); assert(tostring(err):find('clone failure'))
  source=nil
  h.equals(A.createPlayerRig(players,{},12,'R15'),false)
 end)
 h.test('отсутствующий игрок загружается с сохранением современной одежды через R15',function()
  local description={Destroy=function() end}
  local players={GetPlayerByUserId=function() return nil end,
   GetHumanoidDescriptionFromUserIdAsync=function() return description end,
   CreateHumanoidModelFromDescriptionAsync=function(_,desc,kind) h.equals(desc,description); h.equals(kind,'R15'); return 'offline-avatar' end}
  local ok,rig,loaded=A.createPlayerRig(players,{},9210,'R15')
  assert(ok and loaded); h.equals(rig,'offline-avatar')
 end)
 h.test('отменённая копия перестаёт ждать чужое описание и не повторяет запрос',function()
  local appearance=concurrentAppearance(); local calls,models=0,0
  local players={GetHumanoidDescriptionFromUserIdAsync=function()
   calls+=1; coroutine.yield(); error('offline')
  end,CreateHumanoidModelFromDescriptionAsync=function() models+=1; return {} end}
  local first=coroutine.create(function() appearance.createRig(players,{},9101,'R6') end)
  local current=true; local cancelled
  local second=coroutine.create(function() cancelled=not appearance.createRig(players,{},9101,'R6',function() return current end) end)
  resume(first); resume(second)
  current=false; resume(second)
  h.equals(coroutine.status(second),'dead'); h.equals(cancelled,true)
  resume(first)
  h.equals(calls,1); h.equals(models,1)
 end)
 h.test('ожидающие копии делят сетевую ошибку, а следующая попытка может восстановиться',function()
  local appearance=concurrentAppearance(); local calls,models=0,0; local offline=true
  local function description() return {Clone=function() return description() end,Destroy=function() end} end
  local players={GetHumanoidDescriptionFromUserIdAsync=function()
   calls+=1; if calls==1 then coroutine.yield() end
   if offline then error('temporary outage') end
   return description()
  end,CreateHumanoidModelFromDescriptionAsync=function() models+=1; return {} end}
  local results={}; local threads={}
  for i=1,6 do
   threads[i]=coroutine.create(function()
    local ok,_,loaded,err=appearance.createRig(players,{},9102,'R6')
    results[i]={ok=ok,loaded=loaded,error=err}
   end)
   resume(threads[i])
  end
  for _,thread in threads do resume(thread) end
  h.equals(calls,1); h.equals(models,6)
  for _,result in results do assert(result.ok and not result.loaded and tostring(result.error):find('temporary outage')) end
  offline=false
  local ok,_,loaded=appearance.createRig(players,{},9102,'R6')
  assert(ok and loaded); h.equals(calls,2); h.equals(models,7)
 end)
 h.test('отмена инициатора не лишает оставшиеся копии успешно загруженного друга',function()
  local appearance=concurrentAppearance(); local calls=0; local descriptions={}
  local function description()
   return {Clone=function(self) assert(not self.destroyed); return description() end,
    Destroy=function(self) self.destroyed=true end}
  end
  local players={GetHumanoidDescriptionFromUserIdAsync=function() calls+=1; coroutine.yield(); return description() end,
   CreateHumanoidModelFromDescriptionAsync=function(_,d) assert(not d.destroyed); table.insert(descriptions,d); return {} end}
  local current=true; local ownerResult; local loaded={}; local threads={}
  local first=coroutine.create(function() ownerResult=appearance.createRig(players,{},9103,'R6',function() return current end) end)
  resume(first)
  for i=1,3 do
   threads[i]=coroutine.create(function() local ok,_,friend=appearance.createRig(players,{},9103,'R6'); loaded[i]=ok and friend end)
   resume(threads[i])
  end
  current=false; resume(first)
  for _,thread in threads do resume(thread); h.equals(coroutine.status(thread),'dead') end
  h.equals(ownerResult,false); h.equals(calls,1); h.equals(#descriptions,3)
  for _,ready in loaded do assert(ready) end
  assert(descriptions[1]~=descriptions[2] and descriptions[2]~=descriptions[3])
  for _,d in descriptions do assert(d.destroyed) end
 end)
 h.test('отмена назначения не создаёт rig после ожидания описания',function()
  local current=true; local destroyed=false; local calls=0
  local appearance={Destroy=function() destroyed=true end}
  local players={GetHumanoidDescriptionFromUserIdAsync=function() current=false; return appearance end,
   CreateHumanoidModelFromDescriptionAsync=function() calls+=1 end}
  local ok,rig=A.createRig(players,{},9001,'R6',function() return current end)
  h.equals(ok,false); h.equals(rig,nil); h.equals(destroyed,true); h.equals(calls,0)
  ok,rig=A.createRig({}, {},9002,'R6',function() return false end)
  h.equals(ok,false); h.equals(rig,nil)
 end)
 h.test('отменённая ошибка модели друга не запускает запасную загрузку',function()
  local current=true; local calls=0; local destroyed=false
  local appearance={Destroy=function() destroyed=true end}
  local players={GetHumanoidDescriptionFromUserIdAsync=function() return appearance end,
   CreateHumanoidModelFromDescriptionAsync=function() calls+=1; current=false; error('late failure') end}
  local ok=A.createRig(players,{},9003,'R6',function() return current end)
  h.equals(ok,false); h.equals(calls,1); h.equals(destroyed,true)
 end)
 h.test('стажёр выбирает друга со всех страниц и пропускает самого игрока',function()
  local pages={IsFinished=false,index=1}
  function pages:GetCurrentPage() return if self.index==1 then {{Id=10},{Id=20}} else {{Id=30}} end
  function pages:AdvanceToNextPageAsync() self.index=2; self.IsFinished=true end
  local selected=A.pickFriend({GetFriendsAsync=function(_,id) h.equals(id,10); return pages end},10,function() return 1 end)
  h.equals(selected,30)
 end)
 h.test('пустой список, ошибка страниц и тестовый UserId сохраняют обычного стажёра',function()
  h.equals(A.pickFriend({},-1,math.random),nil)
  h.equals(A.pickFriend({GetFriendsAsync=function() error('offline') end},10,math.random),nil)
  h.equals(A.pickFriend({GetFriendsAsync=function() return {IsFinished=true,GetCurrentPage=function() return {} end} end},10,math.random),nil)
  h.equals(A.pickFriend({GetFriendsAsync=function() return {IsFinished=false,GetCurrentPage=function() return {{Id=20}} end,AdvanceToNextPageAsync=function() error('timeout') end} end},10,math.random),nil)
 end)
 h.test('внешность друга применяется к общему rig, описание освобождается',function()
  local destroyed=false; local appearance={Destroy=function() destroyed=true end}; local default={}
  local ok,rig=A.createRig({GetHumanoidDescriptionFromUserIdAsync=function(_,id) h.equals(id,20); return appearance end,
   CreateHumanoidModelFromDescriptionAsync=function(_,desc,kind) h.equals(desc,appearance); h.equals(kind,'R6'); return 'friendRig' end},default,20,'R6')
  h.equals(ok,true); h.equals(rig,'friendRig'); h.equals(destroyed,true)
 end)
 h.test('ошибки внешности и создания модели друга откатываются к обычному повару',function()
  for _,fetchFails in {true,false} do
   local default={}; local destroyed=false
   local appearance={Destroy=function() destroyed=true end}
   local ok,rig=A.createRig({GetHumanoidDescriptionFromUserIdAsync=function() if fetchFails then error('failed') end; return appearance end,
    CreateHumanoidModelFromDescriptionAsync=function(_,desc) if desc==appearance then error('bad asset') end; h.equals(desc,default); return 'defaultRig' end},default,20,'R6')
   h.equals(ok,true); h.equals(rig,'defaultRig'); h.equals(destroyed,not fetchFails)
  end
 end)
 h.test('временная ошибка внешности не кэшируется как успешный случайный стажёр',function()
  local calls=0; local desc={Destroy=function() end}
  local players={GetHumanoidDescriptionFromUserIdAsync=function()
   calls+=1; if calls==1 then error('temporary timeout') end; return desc
  end,CreateHumanoidModelFromDescriptionAsync=function(_,d) return if d==desc then 'friend' else 'fallback' end}
  local ok,rig,loaded,err=A.createRig(players,{},8001,'R6')
  assert(ok and rig=='fallback' and loaded==false and tostring(err):find('temporary timeout'))
  ok,rig,loaded=A.createRig(players,{},8001,'R6')
  assert(ok and rig=='friend' and loaded==true); h.equals(calls,2)
 end)
 h.test('копии друга повторно используют описание, но создают независимые модели',function()
  local calls=0; local descriptions={}
  local function description()
   return {Clone=function() return description() end,Destroy=function() end}
  end
  local players={GetHumanoidDescriptionFromUserIdAsync=function() calls+=1; return description() end,
   CreateHumanoidModelFromDescriptionAsync=function(_,d) table.insert(descriptions,d); return {} end}
  local _,a=A.createRig(players,{},8002,'R6')
  local _,b=A.createRig(players,{},8002,'R6')
  h.equals(calls,1); assert(a~=b and descriptions[1]~=descriptions[2])
 end)

end
