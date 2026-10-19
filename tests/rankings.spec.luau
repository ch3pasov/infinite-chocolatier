--!nonstrict
-- Сбои производного рейтинга не должны портить деньги или прошлый снимок.
local Rankings=require('../src/server/Rankings')
local Economy=require('../src/shared/Economy')
local function fixture()
 local f={writes={},records={},allowed=true,failWrite=false,failRead=false}
 f.model=Rankings.new({budget=function() return f.allowed end,
  write=function(key,id,value)
   table.insert(f.writes,{key=key,id=id,value=value})
   if f.onWrite then f.onWrite(key,id,value) end
   if f.failWrite then error('network') end
  end,
  read=function(key) if f.failRead then error('network') end;return f.records[key] or {} end,
  name=function(id) if id==99 then error('name unavailable') end;return 'Player_'..id end,
 });return f
end
return function(h)
 h.test('рейтинг берёт все заработанные дольки, уникальных гостей и ручные раунды',function()
  local data=Economy.load({slices=20,lifetime=123.99,rounds=7})
  Economy.addSocial(data,'guests',22,11);Economy.addSocial(data,'guests',22,11)
  local v=Rankings.metrics(data);h.equals(v.pieces,123);h.equals(v.guests,1);h.equals(v.tricks,7)
  data.slices=0;data.earned=1e10;data.levels.workers=10
  h.equals(Rankings.metrics(data).pieces,123);h.equals(Rankings.metrics(data).tricks,7)
 end)
 h.test('престиж и автоматическое производство не сбрасывают ручной рекорд',function()
  local data=Economy.load({earned=1e7,lifetime=1e7,rounds=9,collectionVersion=2,owned={workers_1=true},levels={kitchen=1}})
  Economy.tick(data,10);local before=Rankings.metrics(data)
  h.equals(before.tricks,9);assert(before.pieces>1e7)
  assert(Economy.prestige(data));local after=Rankings.metrics(data)
  h.equals(after.pieces,before.pieces);h.equals(after.tricks,9)
 end)
 h.test('невалидные и дробные показатели не уходят в OrderedDataStore',function()
  local v=Rankings.metrics({lifetime=0/0,rounds=math.huge,socialCounts={guests=-7}})
  for _,key in Rankings.keys do h.equals(v[key],0) end
  h.equals(Rankings.metrics({lifetime=1e30,rounds=3.9}).pieces,1e15)
  h.equals(Rankings.metrics({rounds=3.9}).tricks,3)
  local f=fixture();for _,id in {0,-1,1.5,math.huge,'bad'} do f.model:offer(id,{lifetime=10}) end
  f.model:flush(10);h.equals(#f.writes,0)
 end)
 h.test('очередь объединяет итоги и не перезаписывает прежние рекорды меньшими',function()
  local f=fixture();f.model:offer(11,{lifetime=100,rounds=5});f.model:offer(11,{lifetime=50,rounds=2})
  f.model:flush(10);h.equals(#f.writes,2);h.equals(f.writes[1].value,100);h.equals(f.writes[2].value,5)
  f.model:flush(10);h.equals(#f.writes,2)
  f.model:offer(11,{lifetime=110,rounds=5});f.model:flush(10);h.equals(#f.writes,3);h.equals(f.writes[3].value,110)
 end)
 h.test('рейтинг соблюдает лимит вызовов и бюджет, затем повторяет сбой',function()
  local f=fixture();f.model:offer(11,{lifetime=10,rounds=5,socialCounts={guests=2}})
  f.allowed=false;f.model:flush(10);h.equals(#f.writes,0)
  f.allowed=true;f.failWrite=true;f.model:flush(1);h.equals(#f.writes,1)
  f.failWrite=false;f.model:flush(2);h.equals(#f.writes,3)
  f.model:flush(2);h.equals(#f.writes,4)
 end)
 h.test('более новый итог во время записи остаётся в очереди',function()
  local f=fixture();f.model:offer(11,{lifetime=10})
  f.onWrite=function() f.onWrite=nil;f.model:offer(11,{lifetime=20}) end
  f.model:flush(10);h.equals(f.writes[1].value,10)
  f.model:flush(10);h.equals(f.writes[2].value,20)
 end)
 h.test('долгая недоступность облака ограничивает очередь 256 игроками',function()
  local f=fixture();for id=1,400 do f.model:offer(id,{lifetime=id}) end
  h.equals(#f.model.order,256);h.equals(f.model.pending[1],nil);assert(f.model.pending[400])
 end)
 h.test('топ отбрасывает мусор, сортирует и сохраняет независимые категории',function()
  local f=fixture();f.records.pieces={{key='99',value=123},{key='12',value=456},{key='11',value=456},{key='12',value=999},{key='0',value=9},{key='3',value=0/0}}
  f.records.guests={{key='7',value=3}};f.model:refresh()
  local rows=f.model.boards.pieces.rows;h.equals(#rows,3);h.equals(rows[1].id,11);h.equals(rows[2].id,12)
  h.equals(rows[3].name,'99');h.equals(f.model.boards.guests.rows[1].id,7)
  h.equals(f.model.boards.tricks.ready,true);h.equals(#f.model.boards.tricks.rows,0)
 end)
 h.test('сбой чтения сохраняет предыдущие строки и помечает их устаревшими',function()
  local f=fixture();f.records.pieces={{key='11',value=9}};f.model:refresh()
  f.failRead=true;f.model:refresh();h.equals(f.model.boards.pieces.rows[1].score,9);h.equals(f.model.boards.pieces.stale,true)
  f.failRead=false;f.records.pieces={{key='11',value=12}};f.model:refresh()
  h.equals(f.model.boards.pieces.rows[1].score,12);h.equals(f.model.boards.pieces.stale,false)
 end)
 h.test('Studio без backend не читает и не пишет глобальные рекорды',function()
  local r=Rankings.new(nil);r:offer(11,{lifetime=10});r:flush(10);r:refresh()
  h.equals(r.boards.pieces.ready,false);h.equals(#r.boards.pieces.rows,0)
 end)
end
