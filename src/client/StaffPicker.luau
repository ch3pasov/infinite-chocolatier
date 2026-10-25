--!nonstrict
-- Меню использует серверный список друзей: клиент не назначает постороннего
-- пользователя и не считает отсутствие друга на своём устройстве доказательством.
local Players=game:GetService('Players')
local L=require(script.Parent.Localization)
local Theme=require(script.Parent.Theme)
local Picker={}; Picker.__index=Picker
local function label(parent,name,height)
 local t=Instance.new('TextLabel'); t.Name=name; t.BackgroundTransparency=1
 t.TextColor3=Theme.text; t.Font=Enum.Font.GothamMedium; t.TextScaled=true; t.TextWrapped=true
 t.Size=UDim2.new(1,-8,0,height); t.Parent=parent
 local c=Instance.new('UITextSizeConstraint');c.MinTextSize=11;c.MaxTextSize=16;c.Parent=t
 return t
end
local function button(parent,name,text,height)
 local b=Instance.new('TextButton');b.Name=name;b.Size=UDim2.new(1,-8,0,height or 38)
 b.BackgroundColor3=Theme.accent;b.TextColor3=Theme.background;b.Font=Enum.Font.GothamBold
 b.TextScaled=true;b.TextWrapped=true;b.BorderSizePixel=0;b.Parent=parent;L.set(b,text)
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,8);c.Parent=b
 local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=11;limit.MaxTextSize=16;limit.Parent=b
 return b
end
function Picker.new(parent,remote,onToggle)
 local self=setmetatable({alive=true,opened=false,request=0,query='',page=1,rows={},remote=remote,onToggle=onToggle},Picker)
 local frame=Instance.new('Frame');frame.Name='StaffPicker';frame.BackgroundColor3=Theme.panel
 frame.BorderSizePixel=0;frame.Position=UDim2.fromOffset(12,70);frame.Size=UDim2.new(1,-24,1,-112)
 frame.Visible=false;frame.Parent=parent;self.frame=frame
 local scroll=Instance.new('ScrollingFrame');scroll.Name='Friends';scroll.Position=UDim2.fromOffset(0,112);scroll.Size=UDim2.new(1,0,1,-158)
 scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=4
 scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y;scroll.CanvasSize=UDim2.fromOffset(0,0);scroll.Parent=frame;self.scroll=scroll
 local layout=Instance.new('UIListLayout');layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Padding=UDim.new(0,8);layout.Parent=scroll
 local back=button(frame,'Back','Back to apprentice',32);back.Size=UDim2.new(.35,-4,0,32)
 back.Activated:Connect(function() self:setOpen(false) end)
 self.hint=label(scroll,'Hint',56);self.hint.LayoutOrder=2
 self.automatic=button(frame,'Automatic','Automatic selection',32);self.automatic.Position=UDim2.fromScale(.35,0);self.automatic.Size=UDim2.new(.65,-4,0,32)
 self.automatic.Activated:Connect(function() self:send('select',0) end)
 local search=Instance.new('TextBox');search.Name='Search';search.Position=UDim2.fromOffset(0,40);search.Size=UDim2.new(1,-8,0,36)
 search.BackgroundColor3=Theme.chocolateDark;search.TextColor3=Theme.text;search.Font=Enum.Font.GothamMedium
 search.TextSize=16;search.Text='';search.ClearTextOnFocus=false;search.TextTruncate=Enum.TextTruncate.AtEnd;search.Parent=frame
 -- Отдельная подпись сохраняет штатную смену языка, не перезаписывая ввод.
 local searchLabel=label(search,'Placeholder',36);searchLabel.Position=UDim2.fromOffset(8,0);searchLabel.Size=UDim2.new(1,-16,1,0)
 searchLabel.TextColor3=Theme.muted;searchLabel.TextXAlignment=Enum.TextXAlignment.Left;L.set(searchLabel,'Search by name or @username')
 self.search=search
 search:GetPropertyChangedSignal('Text'):Connect(function()
  self.query=search.Text;self.page=1;self:send('list')
  searchLabel.Visible=search.Text==''
 end)
 self.status=label(frame,'Status',28);self.status.Position=UDim2.fromOffset(0,80)
 frame:GetPropertyChangedSignal('AbsoluteSize'):Connect(function() self.hint.Visible=frame.AbsoluteSize.Y>=340 end)
 local footer=Instance.new('Frame');footer.Name='Pages';footer.BackgroundTransparency=1
 footer.Position=UDim2.new(0,0,1,-38);footer.Size=UDim2.new(1,0,0,38);footer.Parent=frame
 self.previous=button(footer,'Previous','‹');self.previous.Size=UDim2.new(.2,-4,1,0)
 self.pageLabel=label(footer,'Page',38);self.pageLabel.Position=UDim2.fromScale(.2,0);self.pageLabel.Size=UDim2.new(.4,-4,1,0)
 local refresh=button(footer,'Refresh','Refresh');refresh.Position=UDim2.fromScale(.6,0);refresh.Size=UDim2.new(.2,-4,1,0)
 self.next=button(footer,'Next','›');self.next.Position=UDim2.fromScale(.8,0);self.next.Size=UDim2.new(.2,-4,1,0)
 self.previous.Activated:Connect(function() if self.page>1 then self.page-=1;self:send('list') end end)
 self.next.Activated:Connect(function() if self.page<(self.pages or 1) then self.page+=1;self:send('list') end end)
 refresh.Activated:Connect(function() self:send('list') end)
 self.connection=remote.OnClientEvent:Connect(function(result) self:receive(result) end)
 local function changed() if self.opened then self:send('list') end end
 self.added=Players.PlayerAdded:Connect(changed);self.removing=Players.PlayerRemoving:Connect(changed)
 frame.Destroying:Connect(function()
  self.alive=false;self.request+=1;self.connection:Disconnect();self.added:Disconnect();self.removing:Disconnect()
 end)
 return self
end
function Picker:setOpen(open)
 if not self.alive then return end
 self.opened=open;self.frame.Visible=open;self.request+=1
 self.hint.Visible=self.frame.AbsoluteSize.Y>=340
 if open then self.page=1;self.scroll.CanvasPosition=Vector2.zero;self:send('list') else self.search:ReleaseFocus() end
 self.onToggle()
end
function Picker:send(action,id)
 if not self.alive or not self.opened then return end
 self.request+=1;local token=self.request
 L.set(self.status,'Loading friends…')
 -- Поиск объединяет быстрые нажатия; номер запроса отсекает старый ответ
 -- после нового поиска, закрытия или повторного открытия этого меню.
 task.delay(.3,function()
  if not self.alive or not self.opened or self.request~=token then return end
  self.remote:FireServer({action=action,id=id,query=string.sub(self.query,1,80),page=self.page,request=token})
  task.delay(8,function()
   if self.alive and self.opened and self.request==token and self.received~=token then L.set(self.status,'Friends are unavailable. Try refresh.') end
  end)
 end)
end
function Picker:receive(result)
 if not self.alive or not self.opened or result.request~=self.request then return end
 self.received=result.request;self.page=result.page;self.pages=result.pages
 for _,row in self.rows do row:Destroy() end;self.rows={}
 local selected=result.selected or 0;local detail=result.selectedName
 local name=detail and (detail.displayName..' (@'..detail.name..')') or L.text('Previously selected friend')
 if selected==0 then L.set(self.hint,'Choose any friend who is not on this server. This only changes your main cafe.')
 elseif result.current==selected then L.set(self.hint,'Selected apprentice: {name}',{name=name})
 else L.set(self.hint,'{name} is unavailable. Using automatic selection for now.',{name=name}) end
 L.set(self.automatic,if selected==0 then '✓ Automatic selection' else 'Automatic selection')
 L.set(self.pageLabel,'{page} / {pages}',{page=self.page,pages=self.pages})
 self.previous.Active=self.page>1;self.next.Active=self.page<self.pages
 if result.notice then L.set(self.status,result.notice)
 elseif selected>0 and not self.hint.Visible then
  L.set(self.status,if result.current==selected then 'Selected apprentice: {name}' else '{name} is unavailable. Using automatic selection for now.',{name=name})
 elseif #result.items==0 then L.set(self.status,if result.status=='ready' then 'No matching friends outside this server.' else 'Friends are still loading. Try refresh shortly.')
 else L.set(self.status,'Friends available: {count}',{count=result.total}) end
 for index,friend in result.items do
  local row=button(self.scroll,'Friend_'..friend.id,'',58);row.LayoutOrder=10+index
  local portrait=Instance.new('ImageLabel');portrait.Name='Portrait';portrait.BackgroundTransparency=1
  portrait.Position=UDim2.fromOffset(6,6);portrait.Size=UDim2.fromOffset(46,46)
  portrait.Image='rbxthumb://type=AvatarHeadShot&id='..friend.id..'&w=150&h=150';portrait.Parent=row
  local caption=label(row,'Name',50);caption.Position=UDim2.fromOffset(60,4);caption.Size=UDim2.new(1,-68,1,-8)
  caption.TextColor3=Theme.background;caption.TextXAlignment=Enum.TextXAlignment.Left
  L.set(caption,if selected==friend.id then '✓ {name}\n@{username}' else '{name}\n@{username}',{name=friend.displayName,username=friend.name})
  row.Activated:Connect(function() self:send('select',friend.id) end)
  table.insert(self.rows,row)
 end
 -- Небольшой опрос обновляет уже открытое меню после фоновой загрузки
 -- списка или разрыва дружбы. Новый ввод отменяет прежний таймер.
 local token=self.request
 task.delay(if result.status=='ready' then 15 else 3,function()
  if self.alive and self.opened and self.request==token then self:send('list') end
 end)
end
return Picker
