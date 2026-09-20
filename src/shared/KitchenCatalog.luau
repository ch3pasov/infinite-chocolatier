--!nonstrict
-- Конечные покупки отделены от повторяемых навыков. Цена зависит от предмета,
-- а бонус — от владения, поэтому выбор внешнего вида не меняет производство.
local Config=require('./Config')
local C={items={},byId={}}
C.decorGroups={'temper','library','clock','plant','rug','art'}
local names={
 workers={'Cocoa Apprentice'},
 temper={'Copper Melter','Cream Temperer','Mint Temperer','Berry Temperer','Golden Temperer'},
 library={'Recipe Notebook','Caramel Recipes','Mint Recipes','Berry Recipes','Grand Recipe Collection'},
 clock={'Cocoa Clock','Caramel Clock','Mint Clock','Berry Clock','Golden Pendulum Clock'},
}
local descriptions={temper='+20% trick reward · bonus while owned',library='+2 pieces per trick · bonus while owned',clock='+10% apprentice speed · bonus while owned'}
for _,spec in Config.Economy.upgrades do
 if names[spec.id] then
  for i,name in names[spec.id] do
   local item={id=spec.id..'_'..i,group=spec.id,variant=i,name=name,description=descriptions[spec.id] or spec.description,
    price=if spec.id=='workers' and i==1 then 0 else math.ceil(spec.baseCost*spec.growth^(i-1))}
   table.insert(C.items,item); C.byId[item.id]=item
  end
 elseif spec.cosmetic then
  local item={id=spec.id,group=spec.id,variant=1,name=spec.name,description=spec.description,price=spec.baseCost}
  table.insert(C.items,item); C.byId[item.id]=item
 end
end
function C.selected(state,group,preview)
 local item=C.byId[preview]
 if item and item.group==group then return item.variant end
 local selected=C.byId[(state.equipped or {})[group]]
 return if selected then selected.variant else 0
end
function C.collection(state,group)
 -- Владение и установленный облик независимы: убранная мебель всё ещё
 -- входит в коллекцию и даёт бонус. Произвольные старые id не считаются.
 local owned,total=0,0
 for _,item in C.items do
  if not group or item.group==group then
   total+=1; if (state.owned or {})[item.id] then owned+=1 end
  end
 end
 local equipped=(state.equipped or {})[group]
 local item=C.byId[equipped]
 if not item or item.group~=group or not (state.owned or {})[equipped] then equipped=nil end
 return {owned=owned,total=total,equipped=equipped}
end
-- Публичный снимок содержит только установленные предметы, без кошелька,
-- остальных покупок и предпросмотра. Одна строка исключает смешение атрибутов.
function C.appearance(state)
 local ids={}
 for _,group in C.decorGroups do table.insert(ids,C.collection(state,group).equipped or '') end
 return table.concat(ids,',')
end
function C.fromAppearance(raw)
 local state={equipped={}}
 if type(raw)~='string' or #raw>256 then return state end
 local ids=string.split(raw,','); if #ids~=#C.decorGroups then return state end
 for index,group in C.decorGroups do
  local item=C.byId[ids[index]]
  if item and item.group==group then state.equipped[group]=item.id end
 end
 return state
end
return C
