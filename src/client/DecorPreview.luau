--!nonstrict
-- Предпросмотр не меняет профиль: подтверждением служит только снимок сервера.
local Preview={}
function Preview.begin(id,state)
 return {id=id,level=state.levels[id],equipped=state.decor[id],confirmed=false}
end
function Preview.update(preview,state)
 if state.levels[preview.id]~=preview.level or state.decor[preview.id]~=preview.equipped then preview.confirmed=true end
 return if preview.confirmed then nil else preview.id
end
return Preview
