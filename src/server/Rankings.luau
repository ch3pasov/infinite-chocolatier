--!nonstrict
-- Рейтинг — производная от сохранённого профиля, а не второе хранилище денег.
-- Ошибка или отставание таблицы никогда не отменяет сохранение игрока.
local Rankings={}; Rankings.__index=Rankings
Rankings.keys={'pieces','guests','tricks'}
local maximum=1e15
local function integer(value)
 if type(value)~='number' or value~=value or value==math.huge or value==-math.huge then return 0 end
 return math.floor(math.clamp(value,0,maximum))
end
local function identity(id)
 local value=tonumber(id)
 return if value and value>0 and value<2^53 and value%1==0 then value else nil
end
function Rankings.metrics(data)
 return {pieces=integer(data.lifetime),guests=integer(data.socialCounts and data.socialCounts.guests),tricks=integer(data.rounds)}
end
function Rankings.new(backend)
 local self=setmetatable({backend=backend,pending={},written={},order={},boards={}},Rankings)
 for _,key in Rankings.keys do self.boards[key]={rows={},ready=false,stale=false} end
 return self
end
function Rankings:offer(id,data)
 id=identity(id); if not id then return end
 local values=Rankings.metrics(data)
 if not self.pending[id] then
  -- Долгий сбой облака не удерживает всех когда-либо прошедших игроков.
  -- Потерянная производная восстановится из профиля при следующем входе.
  if #self.order>=256 then
   local old=table.remove(self.order,1); self.pending[old]=nil; self.written[old]=nil
  end
  table.insert(self.order,id); self.pending[id]={}
 end
 for _,key in Rankings.keys do self.pending[id][key]=math.max(self.pending[id][key] or 0,values[key]) end
end
function Rankings:flush(limit)
 if not self.backend then return end
 local calls=0
 for _,id in table.clone(self.order) do
  local values=self.pending[id]
  if values then
   local written=self.written[id] or {}; self.written[id]=written
   for _,key in Rankings.keys do
    local value=values[key]
    if value>0 and value>(written[key] or 0) then
     if calls>=limit or not self.backend.budget('write') then return end
     calls+=1
     local ok=pcall(self.backend.write,key,tostring(id),value)
     if ok then written[key]=value end
    end
   end
  end
 end
end
function Rankings:refresh()
 if not self.backend then return end
 for _,key in Rankings.keys do
  local board=self.boards[key]
  if not self.backend.budget('read') then board.stale=true; continue end
  local ok,records=pcall(self.backend.read,key)
  if not ok or type(records)~='table' then board.stale=true; continue end
  local rows,seen={},{}
  for _,record in records do
   local id=identity(record.key); local score=integer(record.value)
   if id and score>0 and not seen[id] then
    seen[id]=true
    table.insert(rows,{id=id,score=score})
   end
  end
  table.sort(rows,function(a,b) return if a.score==b.score then a.id<b.id else a.score>b.score end)
  while #rows>10 do table.remove(rows) end
  for _,row in rows do
   local named,name=pcall(self.backend.name,row.id)
   row.name=if named and type(name)=='string' and #name>0 then name else tostring(row.id)
  end
  self.boards[key]={rows=rows,ready=true,stale=false}
 end
end
return Rankings
