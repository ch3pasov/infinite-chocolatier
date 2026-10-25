--!nonstrict
-- Автоматические назначения не повторяются. Личный выбор главного кафе
-- имеет приоритет; два владельца вправе выбрать одного общего друга.
local Roster={}
function Roster.build(pools,online,capacities,choices)
 local owners={}; for owner in pools do table.insert(owners,owner) end; table.sort(owners)
 local used=table.clone(online); local result={}; local active={}
 -- Сначала резервируем все личные выборы, иначе ранняя автоматическая
 -- очередь могла бы занять друга, выбранного другим владельцем.
 for _,owner in owners do
  local id=choices and choices[owner]
  if id and not online[id] and (capacities[owner] or 0)>0 and table.find(pools[owner],id) then
   result[owner]={id}; used[id]=true
  end
 end
 for _,owner in owners do
  local list=result[owner] or {}; result[owner]=list
  local capacity=capacities[owner] or 0
  if capacity>#list then
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
-- Передаём только страницу, а не тысячи друзей при каждом открытии меню.
function Roster.page(pool,online,details,query,page)
 query=string.lower(query or ''):gsub('^%s*@?',''):gsub('%s*$','')
 local candidates={}; local seen={}
 for _,id in pool or {} do if not online[id] and not seen[id] then
  seen[id]=true
  local friend=details[id] or {id=id,name=tostring(id),displayName=tostring(id)}
  if query=='' or string.find(string.lower(friend.name),query,1,true) or string.find(string.lower(friend.displayName),query,1,true) then
   table.insert(candidates,friend)
  end
 end end
 table.sort(candidates,function(a,b)
  local left,right=string.lower(a.name),string.lower(b.name)
  return if left==right then a.id<b.id else left<right
 end)
 local pages=math.max(1,math.ceil(#candidates/12)); page=math.clamp(page or 1,1,pages)
 local items={}; for index=(page-1)*12+1,math.min(page*12,#candidates) do table.insert(items,candidates[index]) end
 return {items=items,page=page,pages=pages,total=#candidates}
end
return Roster
