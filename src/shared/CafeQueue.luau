--!nonstrict
-- Очередь хранит диапазоны, а не список комнат: миллион покупок стоит O(игроков).
local Queue={}
function Queue.key(owner,index) return tostring(owner)..':'..tostring(index or 0) end
function Queue.build(records)
 local groups={}
 for _,r in records do
  local g=groups[r.owner] or {owner=r.owner,indices={}}; groups[r.owner]=g
  if r.index==0 and r.online then g.count=math.max(0,r.count or 0) end
  g.indices[r.index]=true
 end
 local result={}
 for _,g in groups do
  if g.count~=nil then table.insert(result,{owner=g.owner,first=0,last=g.count})
  else for index in g.indices do table.insert(result,{owner=g.owner,first=index,last=index}) end end
 end
 table.sort(result,function(a,b) return a.owner<b.owner or (a.owner==b.owner and a.first<b.first) end)
 return result
end
function Queue.next(segments,owner,index)
 for i,s in segments do
  if s.owner==owner and index>=s.first and index<=s.last then
   if index<s.last then return owner,index+1 end
   local n=segments[i%#segments+1]; return n.owner,n.first
  end
 end
 local first=segments[1]; if first then return first.owner,first.first end
 return nil
end
-- Посещения отделены от декоративной очереди: только дома других игроков онлайн.
function Queue.nextVisitor(records,viewer,current)
 local ids={}; local seen={}
 for _,r in records do
  if r.index==0 and r.online and r.owner~=viewer and r.owner~=current and not seen[r.owner] then
   seen[r.owner]=true; table.insert(ids,r.owner)
  end
 end
 table.sort(ids)
 for _,id in ids do if id>current then return id end end
 return ids[1]
end
function Queue.preview(segments,owner,index,limit)
 local start=Queue.key(owner,index); local result={}
 for _=1,limit do
  owner,index=Queue.next(segments,owner,index)
  if not owner or Queue.key(owner,index)==start then break end
  table.insert(result,{owner=owner,index=index})
 end
 return result
end
-- Случайное оформление стабильно между посещениями, но не даёт купленных бонусов.
function Queue.decor(owner,index)
 local seed=(math.abs(owner)*97+index*7919)%2147483647
 local equipped={}
 for _,group in {'temper','library','clock','plant','rug','art'} do
  seed=(seed*48271)%2147483647
  local variant=seed%(if group=='plant' or group=='rug' or group=='art' then 2 else 6)
  if variant>0 then equipped[group]=if group=='plant' or group=='rug' or group=='art' then group else group..'_'..variant end
 end
 return {equipped=equipped}
end
return Queue
