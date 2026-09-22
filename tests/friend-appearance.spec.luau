--!nonstrict
local A=require('../src/client/FriendAppearance')
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local function concurrentAppearance()
 return luau.load(fs.readFile('src/client/FriendAppearance.luau'),{environment={
  task={wait=function() coroutine.yield() end},
 },injectGlobals=true})()
end
local function resume(thread)
 local ok,err=coroutine.resume(thread); assert(ok,err)
end
return function(h)
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
