--!nonstrict
-- Сервер меняет Transparency при входе/выходе из нарезки. Нельзя сохранять
-- это временное значение как исходное: ответ сервера может ещё быть в пути.
-- Примерка владеет только локальной маской и снимает её при возвращении.
local Visibility={}; Visibility.__index=Visibility
function Visibility.new() return setmetatable({items={}},Visibility) end
function Visibility:clear()
 if self.added then self.added:Disconnect(); self.added=nil end
 if self.removing then self.removing:Disconnect(); self.removing=nil end
 for item in self.items do
  if item.Parent then item.LocalTransparencyModifier=0 end
 end
 self.items={}
end
function Visibility:set(character,visible)
 if visible or character~=self.character then self:clear() end
 self.character=character
 if visible or not character then return end
 if not self.added then
  local function added(item)
   if self.character~=character then return end
   if item:IsA('BasePart') or item:IsA('Decal') then
    self.items[item]=true; item.LocalTransparencyModifier=1
   end
  end
  -- Наблюдение вызывает set каждый кадр. Состав аватара меняется событиями,
  -- поэтому полный обход нужен только при входе; поздняя одежда скрывается сразу.
  self.added=character.DescendantAdded:Connect(added)
  self.removing=character.DescendantRemoving:Connect(function(item)
   if self.items[item] then
    -- Предмет, перенесённый из аватара в мир, больше не принадлежит маске.
    self.items[item]=nil; item.LocalTransparencyModifier=0
   end
  end)
  for _,item in character:GetDescendants() do added(item) end
 else
  -- Штатная камера может сбросить локальную маску. Возвращаем только
  -- изменившиеся значения, не трогая серверную Transparency.
  for item in self.items do
   if item.LocalTransparencyModifier~=1 then item.LocalTransparencyModifier=1 end
  end
 end
end
return Visibility
