--!nonstrict
local Visibility=require('../src/client/AvatarVisibility')
local function item(kind,transparency)
 return {Parent=true,Transparency=transparency,LocalTransparencyModifier=0,IsA=function(_,name) return name==kind end}
end
return function(h)
 h.test('выход из примерки не возвращает устаревшую серверную невидимость',function()
  local body,face,root=item('BasePart',1),item('Decal',1),item('BasePart',1)
  local character={GetDescendants=function() return {body,face,root} end}
  local mask=Visibility.new()
  mask:set(character,false)
  -- Ответ на watch приходит уже после открытия примерки.
  body.Transparency=0; face.Transparency=.25
  mask:set(character,false)
  h.equals(body.Transparency,0); h.equals(face.Transparency,.25)
  h.equals(body.LocalTransparencyModifier,1)
  mask:set(character,true)
  h.equals(body.Transparency,0); h.equals(face.Transparency,.25)
  h.equals(body.LocalTransparencyModifier,0); h.equals(face.LocalTransparencyModifier,0)
  h.equals(root.Transparency,1)
  -- Даже более поздний серверный ответ не конфликтует с уже снятой маской.
  body.Transparency=1; mask:set(character,false); mask:set(character,true)
  body.Transparency=0; h.equals(body.LocalTransparencyModifier,0)
 end)
 h.test('смена персонажа, поздний аксессуар и повторный выход очищают локальную маску',function()
  local a,b,accessory=item('BasePart',0),item('BasePart',0),item('BasePart',.4)
  local old={GetDescendants=function() return {a} end}; local items={b}
  local new={GetDescendants=function() return items end}; local mask=Visibility.new()
  mask:set(old,false); mask:set(new,false); h.equals(a.LocalTransparencyModifier,0)
  table.insert(items,accessory); mask:set(new,false); h.equals(accessory.LocalTransparencyModifier,1)
  mask:set(new,true); mask:set(new,true)
  h.equals(b.LocalTransparencyModifier,0); h.equals(accessory.LocalTransparencyModifier,0)
  h.equals(accessory.Transparency,.4)
 end)
end
