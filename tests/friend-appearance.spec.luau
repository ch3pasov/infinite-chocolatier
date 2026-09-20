--!nonstrict
local A=require('../src/client/FriendAppearance')
return function(h)
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
