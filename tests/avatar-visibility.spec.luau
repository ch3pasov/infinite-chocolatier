--!nonstrict
local Visibility=require('../src/client/AvatarVisibility')
local function item(kind,transparency)
 return {Parent=true,Transparency=transparency,LocalTransparencyModifier=0,IsA=function(_,name) return name==kind end}
end
local function signal()
 local connections={}; local s={}
 function s:Connect(callback)
  local c={Connected=true,callback=callback}; function c:Disconnect() self.Connected=false end
  table.insert(connections,c); return c
 end
 function s:Fire(value) for _,c in connections do if c.Connected then c.callback(value) end end end
 function s:count() local count=0; for _,c in connections do if c.Connected then count+=1 end end; return count end
 return s
end
local function character(items)
 local c={DescendantAdded=signal(),DescendantRemoving=signal(),scans=0}
 function c:GetDescendants() self.scans+=1; return items end
 return c
end
return function(h)
 h.test('выход из примерки не возвращает устаревшую серверную невидимость',function()
  local body,face,root=item('BasePart',1),item('Decal',1),item('BasePart',1)
  local character=character({body,face,root})
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
  local old=character({a}); local items={b}
  local new=character(items); local mask=Visibility.new()
  mask:set(old,false); mask:set(new,false); h.equals(a.LocalTransparencyModifier,0)
  table.insert(items,accessory); new.DescendantAdded:Fire(accessory); h.equals(accessory.LocalTransparencyModifier,1)
  h.equals(old.DescendantAdded:count(),0); h.equals(old.DescendantRemoving:count(),0)
  old.DescendantAdded:Fire(a); h.equals(a.LocalTransparencyModifier,0)
  mask:set(new,true); mask:set(new,true)
  h.equals(b.LocalTransparencyModifier,0); h.equals(accessory.LocalTransparencyModifier,0)
  h.equals(accessory.Transparency,.4)
  h.equals(new.DescendantAdded:count(),0); h.equals(new.DescendantRemoving:count(),0)
 end)
 h.test('маска не обходит аватар каждый кадр, освобождает снятую вещь и переживает сброс камеры',function()
  local body,accessory=item('BasePart',0),item('BasePart',.4)
  local items={body,accessory}; local char=character(items); local mask=Visibility.new()
  mask:set(char,false)
  for _=1,100 do mask:set(char,false) end
  h.equals(char.scans,1); h.equals(char.DescendantAdded:count(),1)
  body.LocalTransparencyModifier=0; mask:set(char,false); h.equals(body.LocalTransparencyModifier,1)
  char.DescendantRemoving:Fire(accessory); table.remove(items,2)
  mask:set(char,false); h.equals(accessory.LocalTransparencyModifier,0); h.equals(mask.items[accessory],nil)
  h.equals(accessory.Transparency,.4)
  mask:set(char,true); mask:set(char,false)
  h.equals(char.scans,2); h.equals(char.DescendantAdded:count(),1)
  mask:set(nil,true); h.equals(body.LocalTransparencyModifier,0)
  h.equals(char.DescendantAdded:count(),0); h.equals(char.DescendantRemoving:count(),0)
 end)
end
