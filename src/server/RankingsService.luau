--!nonstrict
-- Облачные вызовы живут отдельно от модели и не выполняются в Studio.
local Rankings=require(script.Parent.Rankings)
local Service={}
function Service.start()
 local ReplicatedStorage=game:GetService('ReplicatedStorage')
 local DataStoreService=game:GetService('DataStoreService')
 local HttpService=game:GetService('HttpService')
 local Players=game:GetService('Players')
 local studio=game:GetService('RunService'):IsStudio()
 local folder=Instance.new('Folder'); folder.Name='ChocolateRankings'; folder.Parent=ReplicatedStorage
 local backend
 if not studio then
  local stores,names={},{}; local nameCount=0
  backend={
   budget=function(kind)
    if kind=='read' then return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedList)>0 end
    -- UpdateAsync расходует оба бюджета. Рейтинг не должен вставать
    -- в очередь сетевого запроса при исчерпанном бюджете чтения.
    return DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedWrite)>0
     and DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.OrderedRead)>0
   end,
   write=function(key,id,value)
    if not stores[key] then stores[key]=DataStoreService:GetOrderedDataStore('ChocolateRankings_v1_'..key) end
    stores[key]:UpdateAsync(id,function(old) return math.max(if type(old)=='number' then old else 0,value) end)
   end,
   read=function(key)
    if not stores[key] then stores[key]=DataStoreService:GetOrderedDataStore('ChocolateRankings_v1_'..key) end
    return stores[key]:GetSortedAsync(false,10):GetCurrentPage()
   end,
   name=function(id)
    local cached=names[id]
    if cached and cached.untilTime>os.clock() then return cached.name end
    if not cached then
     if nameCount>=128 then table.clear(names); nameCount=0 end
     nameCount+=1
    end
    local ok,name=pcall(function() return Players:GetNameFromUserIdAsync(id) end)
    names[id]={name=if ok then name else tostring(id),untilTime=os.clock()+(if ok then 3600 else 300)}
    return names[id].name
   end,
  }
 end
 local model=Rankings.new(backend)
 local function publish()
  folder:SetAttribute('Snapshot',HttpService:JSONEncode({studio=studio,boards=model.boards}))
 end
 publish()
 if not studio then task.spawn(function()
  local nextRead=0
  while folder.Parent do
   -- Вызовы ограничены по числу, бюджету и частоте. Профили сохраняются
   -- независимо; в очереди остаётся только наибольший подтверждённый итог.
   local ok=pcall(function()
    model:flush(12)
    if os.clock()>=nextRead then model:refresh(); publish(); nextRead=os.clock()+60 end
   end)
   if not ok then warn('Chocolate rankings delayed') end
   task.wait(10)
  end
 end) end
 return {record=function(_,id,data) if not studio then model:offer(id,data) end end}
end
return Service
