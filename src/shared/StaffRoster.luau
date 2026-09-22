--!nonstrict
-- Один друг занимает максимум одно место во всей фабрике сервера.
-- Резервируем только купленные места, включая не загруженные комнаты.
local Roster={}
function Roster.build(pools,online,capacities)
 local owners={}; for owner in pools do table.insert(owners,owner) end; table.sort(owners)
 local used=table.clone(online); local result={}; local active={}
 for _,owner in owners do
  local list={}; result[owner]=list
  local capacity=capacities[owner] or 0
  if capacity>0 then
   local friends=table.clone(pools[owner]); table.sort(friends)
   table.insert(active,{friends=friends,list=list,capacity=capacity,cursor=1})
  end
 end
 -- По одному назначению за круг: владелец с меньшим UserId не забирает
 -- весь общий список. Работа ограничена списками друзей, а не числом кафе.
 while #active>0 do
  local nextRound={}
  for _,entry in active do
   while entry.cursor<=#entry.friends do
    local id=entry.friends[entry.cursor]; entry.cursor+=1
    if id>0 and not used[id] then
     used[id]=true; table.insert(entry.list,id); break
    end
   end
   if #entry.list<entry.capacity and entry.cursor<=#entry.friends then table.insert(nextRound,entry) end
  end
  active=nextRound
 end
 return result
end
function Roster.identity(rosters,owner,ordinal)
 local friends=rosters[owner] or {}
 return friends[ordinal] or 0, (math.abs(owner)*131+ordinal*7919)%2147483647
end
return Roster
