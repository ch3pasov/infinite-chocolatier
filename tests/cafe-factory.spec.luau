-- Большая очередь и рост дохода проверяются без создания тысяч объектов Roblox.
local Q=require('../src/shared/CafeQueue')
local R=require('../src/shared/StaffRoster')
local E=require('../src/shared/Economy')
return function(h)
 h.test('новые кафе открываются после найма, каждое даёт ровно двух стажёров',function()
  local d=E.load({slices=20000}); h.equals(E.price(d,'cafes'),nil); h.equals(E.buy(d,'cafes'),false)
  assert(E.buy(d,'kitchen')); h.equals(E.buy(d,'cafes'),false)
  assert(E.buy(d,'workers_1')); h.equals(E.price(d,'cafes'),1000)
  for n=1,4 do
   local before=d.slices; local price=E.price(d,'cafes'); h.equals(price,1000*2^(n-1)); assert(E.buy(d,'cafes'))
   h.equals(d.slices,before-price); h.equals(d.levels.cafes,n); h.equals(d.levels.workers,1+2*n)
   h.near(E.tick(d,E.cycleSeconds(d)),E.manual(d)*(1+2*n))
   d=E.load(d); h.equals(d.levels.cafes,n)
  end
  d.earned=5000; assert(E.prestige(d)); h.equals(d.levels.cafes,0); h.equals(E.rate(d),0)
 end)
 h.test('старые стажёры превращаются в кафе один раз без снижения дохода',function()
  for count=1,100 do
   local d=E.load({levels={workers=count}})
   h.equals(d.levels.cafes,math.ceil((count-1)/2)); assert(d.levels.workers>=count and d.levels.workers<=count+1)
   for _=1,3 do d=E.load(d) end
   h.equals(d.levels.cafes,math.ceil((count-1)/2))
  end
  local d=E.load({collectionVersion=1,levels={kitchen=1},legacyWorkers=2,owned={workers_1=true,workers_3=true,workers_5=true}})
  h.equals(d.levels.workers,5); h.equals(d.levels.cafes,2)
 end)
 h.test('миллион кафе хранится диапазоном и даёт личную очередь ограниченной длины',function()
  local segments=Q.build({{owner=4,index=0,online=true,count=1000000},{owner=4,index=500,online=true},{owner=9,index=0,online=true,count=2}})
  h.equals(#segments,2)
  local preview=Q.preview(segments,4,0,24); h.equals(#preview,24)
  for i,r in preview do h.equals(r.owner,4); h.equals(r.index,i) end
  local owner,index=Q.next(segments,4,1000000); h.equals(owner,9); h.equals(index,0)
  owner,index=Q.next(segments,9,2); h.equals(owner,4); h.equals(index,0)
  h.equals(#Q.preview(Q.build({{owner=4,index=0,online=true,count=0}}),4,0,24),0)
 end)
 h.test('покинутое кафе представлено только занятыми комнатами, оформление стабильно',function()
  local segments=Q.build({{owner=4,index=7,online=false},{owner=9,index=0,online=true,count=0}})
  local owner,index=Q.next(segments,9,0); h.equals(owner,4); h.equals(index,7)
  local a,b=Q.decor(4,7),Q.decor(4,7)
  for group,item in a.equipped do h.equals(b.equipped[group],item) end
  local different=false; local other=Q.decor(4,8)
  for group,item in a.equipped do if other.equipped[group]~=item then different=true end end
  assert(different)
 end)
 h.test('друзья стажёров уникальны на сервере и исключаются при входе настоящего игрока',function()
  local pools={[10]={100,101,102,102},[20]={100,101,103}}
  local rosters=R.build(pools,{[10]=true,[20]=true})
  h.equals(rosters[10][1],100); h.equals(rosters[20][1],103)
  local seen={}
  for owner,list in rosters do for ordinal,id in list do
   assert(not seen[id]); seen[id]=true; h.equals(R.identity(rosters,owner,ordinal),id)
  end end
  local changed=R.build(pools,{[100]=true,[10]=true,[20]=true})
  h.equals(changed[10][1],101)
  local id,seed=R.identity(changed,10,20); h.equals(id,0)
  local _,otherSeed=R.identity(changed,10,21); assert(seed~=otherSeed)
 end)
end
