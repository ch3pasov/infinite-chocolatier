--!nonstrict
-- Один друг занимает максимум одно место во всей фабрике сервера.
-- Резервируем список даже для не загруженных комнат, не создавая их персонажей.
local Roster={}
function Roster.build(pools,online)
 local owners={}; for owner in pools do table.insert(owners,owner) end; table.sort(owners)
 local used=table.clone(online); local result={}
 for _,owner in owners do
  local friends=table.clone(pools[owner]); table.sort(friends)
  local list={}; result[owner]=list
  for _,id in friends do if id>0 and not used[id] then used[id]=true; table.insert(list,id) end end
 end
 return result
end
function Roster.identity(rosters,owner,ordinal)
 local friends=rosters[owner] or {}
 return friends[ordinal] or 0, (math.abs(owner)*131+ordinal*7919)%2147483647
end
return Roster
