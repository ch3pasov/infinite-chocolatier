--!nonstrict
-- Сервер меняет Transparency при входе/выходе из нарезки. Нельзя сохранять
-- это временное значение как исходное: ответ сервера может ещё быть в пути.
-- Примерка владеет только локальной маской и снимает её при возвращении.
local Visibility={}; Visibility.__index=Visibility
function Visibility.new() return setmetatable({items={}},Visibility) end
function Visibility:clear()
 for item in self.items do
  if item.Parent then item.LocalTransparencyModifier=0 end
 end
 self.items={}
end
function Visibility:set(character,visible)
 if visible or character~=self.character then self:clear() end
 self.character=character
 if visible or not character then return end
 for _,item in character:GetDescendants() do
  if item:IsA('BasePart') or item:IsA('Decal') then
   self.items[item]=true
   item.LocalTransparencyModifier=1
  end
 end
end
return Visibility
