--!nonstrict
-- Проверяем экономический результат, границы сеанса и недоверенный протокол.
local E=require('../src/shared/Economy')
local Config=require('../src/shared/Config')
local Service=require('../src/server/SocialService')
local Store=require('../src/server/ProfileStore')
local function fixture()
 local owner,friend,other={UserId=101},{UserId=202},{UserId=303}
 local data=E.load({levels={workers=1}})
 local sessions={[owner]={data=data,tick=0}}
 local present={[owner]=true,[friend]=true,[other]=true}
 local friends={[friend]=true}; local visits={}; local watching={}
 local now=0; local ownerEpoch=1; local callback
 local rooms={}
 function rooms:isFriend(_,p) return present[p] and friends[p]==true end
 function rooms:hasOnlineFriend(p) for f in friends do if present[f] and f~=p then return true end end; return false end
 function rooms:visits() return visits end
 function rooms:manualContext() return ownerEpoch end
 function rooms:watching(_,p) return if present[p] then watching[p] else nil end
 local function accrue(s) E.tick(s.data,now-s.tick); s.tick=now end
 local service=Service.new(E,rooms,sessions,function(_,s) return not s.closing end,accrue,function() return now end,Config.Payout.minInterval)
 return {owner=owner,friend=friend,other=other,data=data,service=service,sessions=sessions,
  advance=function(t) now+=t end,
  present=present,friends=friends,watching=watching,visits=visits,
  ownerEpoch=function(v) ownerEpoch=v end,
  finish=function()
   for i=1,5 do service:step(owner,i) end
   now+=1; return service:complete(owner)
  end,
  visit=function(p,watch)
   table.insert(visits,{owner=owner,guest=p}); watching[p]=watch
   service:refresh()
  end}
end
return function(h)
 h.test('социальные слои складываются внутри и перемножаются между собой',function()
  local d=E.load({stars=4,levels={craft=2,recipe=2,kitchen=1},collectionVersion=2,
   owned={workers_1=true,temper_1=true,library_1=true,clock_1=true}})
  E.addSocial(d,'guests',2,1); E.addSocial(d,'spectators',2,1)
  E.addSocial(d,'guests',3,1); E.addSocial(d,'spectators',3,1)
  d.onlineFriend=true
  local b=E.breakdown(d)
  h.near(b.multiplier,1.5*2*1.2*2*1.2*2)
  h.equals(b.baseReward,5); h.near(E.manual(d),5*b.multiplier)
  h.near(E.cycleSeconds(d),10/1.1); h.near(E.rate(d),E.manual(d)*1.1/10)
  local snapshot=E.snapshot(d)
  h.equals(snapshot.social,nil); h.equals(snapshot.socialCounts.guests,2)
  h.near(snapshot.bonuses.manual,snapshot.manual)
  h.near(snapshot.bonuses.rate,snapshot.rate)
  h.near(snapshot.bonuses.orderBonus,snapshot.order.bonus)
  local preview=E.preview(snapshot,'craft',1)
  h.near(preview.manualGain,b.multiplier)
  d.ignorePrestige=true; h.near(E.manual(d)*2,b.manual)
 end)
 h.test('онлайн-друг не требует посещения, не складывается и исчезает при выходе',function()
  local f=fixture(); f.service:refresh()
  h.equals(f.data.onlineFriend,true); h.near(E.manual(f.data),2)
  h.equals(f.data.socialCounts.guests,0)
  f.friends[f.other]=true; f.service:refresh(); h.near(E.manual(f.data),2)
  f.advance(10); f.present[f.friend]=nil; f.service:refresh()
  h.equals(f.data.slices,0,'ставка не менялась — начисление остаётся в общем таймере')
  f.present[f.other]=nil; f.service:refresh()
  h.equals(f.data.slices,2,'законченный цикл начисляется по прежней ставке')
  h.equals(f.data.onlineFriend,false); h.near(E.manual(f.data),1)
  f.advance(10); f.present[f.friend]=true; f.service:refresh()
  h.equals(f.data.slices,3,'возвращение друга не усиливает прошлый цикл')
  h.equals(f.data.onlineFriend,true)
 end)
 h.test('визит любого игрока считается один раз, а зрителю нужен весь ручной фокус',function()
  local f=fixture(); f.visit(f.other,nil); f.visit(f.friend,7)
  h.equals(f.data.socialCounts.guests,2)
  f.service:step(f.owner,'begin'); local witnesses=f.finish()
  assert(witnesses); h.equals(witnesses[f.friend],7); h.equals(witnesses[f.other],nil)
  f.service:award(f.owner,witnesses); h.equals(f.data.socialCounts.spectators,1)
  f.visit(f.friend,7); f.service:step(f.owner,'begin'); f.service:award(f.owner,f.finish())
  h.equals(f.data.socialCounts.guests,2); h.equals(f.data.socialCounts.spectators,1)
  h.equals(f.service:complete(f.owner),nil,'повтор квитанции завершения')
 end)
 h.test('опоздавший, вышедший, сменивший режим и переставший быть другом зритель не учитывается',function()
  for _,reason in {'late','leave','mode','friend','owner','cancel'} do
   local f=fixture()
   if reason~='late' then f.visit(f.friend,1) end
   f.service:step(f.owner,'begin')
   if reason=='late' then f.visit(f.friend,1)
   elseif reason=='leave' then f.present[f.friend]=nil; f.service:refresh(); f.present[f.friend]=true
   elseif reason=='mode' then f.watching[f.friend]=2
   elseif reason=='friend' then f.friends[f.friend]=nil
   elseif reason=='owner' then f.ownerEpoch(2)
   else f.service:remove(f.friend) end
   f.service:step(f.owner,'begin') -- Не перезапускает уже начатый показ.
   local witnesses=f.finish(); assert(witnesses)
   f.service:award(f.owner,witnesses); h.equals(f.data.socialCounts.spectators,0,reason)
  end
 end)
 h.test('пропущенные, переставленные и мгновенные этапы не дают ручной награды',function()
  local f=fixture()
  h.equals(f.service:complete(f.owner),nil)
  f.service:step(f.owner,'begin'); f.service:step(f.owner,2); h.equals(f.service:complete(f.owner),nil)
  f.service:step(f.owner,'begin')
  for i=1,5 do f.service:step(f.owner,i) end
  h.equals(f.service:complete(f.owner),nil,'слишком быстро')
  f.service:step(f.owner,'begin'); f.service:step(f.owner,'cancel'); h.equals(f.service:complete(f.owner),nil)
  f.service:step(f.owner,'begin'); f.ownerEpoch(nil); h.equals(f.finish(),nil,'финиш вне ручного режима')
 end)
 h.test('пожизненный прогресс переживает престиж, аренду, выход и офлайн без онлайн-множителя',function()
  local now=1000; local record
  local db={UpdateAsync=function(_,_,fn) local value=fn(record); if value then record=value end; return value end}
  local a=Store.new(db,E,Config.Economy,'A',function() return now end)
  local d=a:claim('101')
  E.addSocial(d,'guests',202,101); E.addSocial(d,'spectators',202,101)
  d.earned=5000; assert(E.prestige(d))
  h.equals(d.socialCounts.guests,1); h.equals(d.socialCounts.spectators,1)
  d.owned.workers_1=true; d.levels.workers=1; d.onlineFriend=true
  assert(a:save('101',d,true)); h.equals(record.version,5)
  h.equals(record.data.onlineFriend,nil)
  now+=10
  local b=Store.new(db,E,Config.Economy,'B',function() return now end)
  local loaded,offline=b:claim('101')
  h.near(offline,1.25*1.1*1.5); h.equals(loaded.socialCounts.spectators,1)
  h.equals(E.addSocial(loaded,'guests',202,101),false)
  h.equals(E.addSocial(loaded,'spectators',202,101),false)
  h.equals(E.load({socialCounts={guests=999},onlineFriend=true}).socialCounts.guests,0)
 end)
 h.test('некорректные социальные идентификаторы и сам хозяин не добавляют прогресс',function()
  local d=E.load({social={guests={['2']=true,['02']=true,abc=true,['3']=false,['0']=true,['-1']=true},spectators='bad'}})
  h.equals(d.socialCounts.guests,1); h.equals(d.socialCounts.spectators,0)
  for _,id in {0,-1,0/0,math.huge,1.5,'2',101} do h.equals(E.addSocial(d,'guests',id,101),false) end
  h.equals(E.addSocial(d,'fake',202,101),false)
 end)
 h.test('большие множители сохраняют предел выплаты и согласованность снимка',function()
  local d=E.load({stars=1000000,levels={craft=1e9,recipe=1e9,speed=1e9}})
  d.socialCounts={guests=1000000,spectators=1000000}; d.onlineFriend=true
  local b=E.breakdown(d)
  assert(b.multiplier>1e15 and b.multiplier<math.huge)
  h.equals(b.manual,Config.Economy.maxValue); assert(b.cycleSeconds>0 and b.cycleSeconds<.01)
  h.equals(E.snapshot(d).manual,b.manual)
 end)
end
