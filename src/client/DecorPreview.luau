--!nonstrict
-- Предпросмотр не меняет профиль: подтверждением служит только снимок сервера.
local Preview={}
function Preview.begin(id,state)
 local group=string.match(id,'^([^_]+)')
 return {id=id,group=group,owned=state.owned[id],equipped=state.equipped[group],confirmed=false}
end
function Preview.update(preview,state)
 if state.owned[preview.id]~=preview.owned or state.equipped[preview.group]~=preview.equipped then preview.confirmed=true end
 return if preview.confirmed then nil else preview.id
end
return Preview
