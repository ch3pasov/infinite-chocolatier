--!strict
-- Идентификаторы остаются только в сохранении; клиент получает счётчики.
-- Два независимых множества позволяют одному человеку дать оба бонуса.
local Social = {}
local function key(id)
 if type(id)~='number' or id~=id or id<=0 or id%1~=0 or id>9007199254740991 then return nil end
 return string.format('%.0f',id)
end
function Social.load(raw)
 local sets,counts={guests={},spectators={}},{guests=0,spectators=0}
 if type(raw)=='table' then
  for kind,set in sets do
   if type(raw[kind])=='table' then
    for id,value in raw[kind] do
     local canonical=if type(id)=='string' then key(tonumber(id)) else nil
     if value==true and canonical==id then set[id]=true; counts[kind]+=1 end
    end
   end
  end
 end
 return sets,counts
end
function Social.add(data,kind,id,ownerId)
 if kind~='guests' and kind~='spectators' then return false end
 local idKey=key(id)
 if not idKey or id==ownerId or data.social[kind][idKey] then return false end
 data.social[kind][idKey]=true; data.socialCounts[kind]+=1
 return true
end
return Social
