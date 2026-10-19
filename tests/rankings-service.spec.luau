--!nonstrict
-- Исполняем облачный адаптер с поддельным хранилищем: Studio обязан вообще
-- не запрашивать OrderedDataStore, а живой адаптер сохраняет максимум.
local fs=require('@lune/fs')
local luau=require('@lune/luau')
local serde=require('@lune/serde')
local Rankings=require('../src/server/Rankings')
local function fixture(studio)
 local f={stores={},reads=0,writes=0,now=100,folders={},names=0,budgets={}}
 local function store(name)
  assert(not studio,'Studio requested cloud records')
  if not f.stores[name] then
   local values={}
   f.stores[name]={values=values,
    UpdateAsync=function(_,id,callback) f.writes+=1;values[id]=callback(values[id]);return values[id] end,
    GetSortedAsync=function(_,ascending,size)
     assert(ascending==false and size==10);f.reads+=1
     local rows={};for id,value in values do table.insert(rows,{key=id,value=value}) end
     return {GetCurrentPage=function() return rows end}
    end,
   }
  end
  return f.stores[name]
 end
 local services={RunService={IsStudio=function() return studio end},ReplicatedStorage={},
  DataStoreService={GetOrderedDataStore=function(_,name) return store(name) end,
   GetRequestBudgetForRequestType=function(_,kind) assert(kind=='list' or kind=='write' or kind=='read');return f.budgets[kind] or 100 end},
  HttpService={JSONEncode=function(_,value) f.snapshot=value;return serde.encode('json',value) end},
  Players={GetNameFromUserIdAsync=function(_,id) f.names+=1;return 'Player_'..id end}}
 local Service=luau.load(fs.readFile('src/server/RankingsService.luau'),{environment={
  game={GetService=function(_,key) return services[key] end},script={Parent={Rankings='Rankings'}},require=function() return Rankings end,
  Instance={new=function() local folder={SetAttribute=function() end};table.insert(f.folders,folder);return folder end},
  Enum={DataStoreRequestType={OrderedList='list',OrderedWrite='write',OrderedRead='read'}},
  os={clock=function() return f.now end},warn=function() end,
  task={spawn=function(fn) f.worker=coroutine.create(fn) end,wait=function() coroutine.yield() end},
 },injectGlobals=true})()
 f.service=Service.start()
 function f.step() if f.worker then local ok,err=coroutine.resume(f.worker);assert(ok,err) end end
 return f
end
return function(h)
 h.test('адаптер Studio не создаёт глобальные хранилища и помечает пустой просмотр',function()
  local f=fixture(true);f.service:record(11,{lifetime=100});f.step()
  h.equals(f.reads,0);h.equals(f.writes,0);h.equals(f.snapshot.studio,true)
 end)
 h.test('облачный адаптер обновляет три максимума и читает независимые топы',function()
  local f=fixture(false);f.service:record(11,{lifetime=100,rounds=7,socialCounts={guests=2}});f.step()
  h.equals(f.writes,3);h.equals(f.reads,3);h.equals(f.snapshot.boards.pieces.rows[1].score,100)
  h.equals(f.snapshot.boards.guests.rows[1].score,2);h.equals(f.snapshot.boards.tricks.rows[1].score,7)
  h.equals(f.names,1,'имя повторно запрашивалось для каждой категории')
  f.service:record(11,{lifetime=50,rounds=1});f.now+=70;f.step();h.equals(f.writes,3)
  local s=f.stores.ChocolateRankings_v1_pieces;s.values['11']=300
  f.service:record(11,{lifetime=200});f.now+=70;f.step();h.equals(s.values['11'],300)
 end)
 h.test('запись рейтинга ждёт оба бюджета UpdateAsync, затем догоняет профиль',function()
  local f=fixture(false);f.budgets.read=0;f.service:record(11,{lifetime=10});f.step()
  h.equals(f.writes,0);h.equals(f.reads,3)
  f.budgets.read=100;f.now+=70;f.step();h.equals(f.writes,1)
  h.equals(f.snapshot.boards.pieces.rows[1].score,10)
 end)
end
