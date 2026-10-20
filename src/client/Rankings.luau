--!nonstrict
-- Рейтинг читается на самой стене. PlayerGui + Adornee и CanQuery нужны
-- нативным ScrollingFrame: поверхность внутри Workspace не получает ввод.
local Players=game:GetService('Players')
local ReplicatedStorage=game:GetService('ReplicatedStorage')
local HttpService=game:GetService('HttpService')
local Input=game:GetService('UserInputService')
local GuiService=game:GetService('GuiService')
local Run=game:GetService('RunService')
local L=require(script.Parent.Localization)
local Theme=require(script.Parent.Theme)
local Camera=require(script.Parent.RankingsCamera)
local Rankings={};Rankings.__index=Rankings
local keys={'pieces','guests','tricks'}
local titles={pieces='Lifetime pieces',guests='Unique guests',tricks='Manual tricks'}
local compactTitles={pieces='Pieces',guests='Guests',tricks='Tricks'}
local descriptions={pieces='All pieces earned, shown as whole pieces. Spending and prestige keep this total.',
 guests='Unique lifetime cafe visitors. Repeat visits do not add guests.',
 tricks='Completed manual tricks only. Apprentice production does not count.'}
local function label(parent,name,size,color)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Font=Enum.Font.GothamMedium
 t.TextSize=size;t.TextColor3=color or Theme.text;t.TextWrapped=true;t.RichText=false;t.Text='';t.Parent=parent;return t
end
local function textSize(object,min,max)
 object.TextScaled=true;local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=min;limit.MaxTextSize=max;limit.Parent=object
end
local function button(parent,name,caption)
 local b=Instance.new('TextButton');b.Name=name;b.Font=Enum.Font.GothamBold;b.BackgroundColor3=Theme.chocolate
 b.TextColor3=Theme.accent;b.BorderSizePixel=0;b.TextWrapped=true;textSize(b,12,28);L.set(b,caption);b.Parent=parent
 local c=Instance.new('UICorner');c.CornerRadius=UDim.new(0,8);c.Parent=b;return b
end
local function rowText(object,rank,row)
 if row then L.set(object,'{rank}. {name}\n{score}',{rank=tostring(rank),name=row.name,score=L.number(row.score)})
 else L.set(object,'{rank}. —',{rank=tostring(rank)}) end
end
function Rankings.new(owner,view,kitchen)
 local self=setmetatable({view=view,kitchen=kitchen,key='pieces',snapshot={boards={}},world={},pendingRooms={},connections={}},Rankings)
 local gui=Instance.new('ScreenGui');gui.Name='ChocolateRankings';gui.ResetOnSpawn=false;gui.DisplayOrder=35;gui.Parent=owner.Parent;self.gui=gui
 self.playerGui=owner.Parent
 self.camera=Camera.new(kitchen.stage:createCamera('RankingsCamera',50))
 -- Только выход находится на экране; мир и сама доска не закрываются модальным окном.
 local close=button(gui,'Close','Back to cafe');close.AnchorPoint=Vector2.new(1,1)
 close.Position=UDim2.new(1,-12,1,-12);close.Size=UDim2.fromOffset(160,44);close.Visible=false;self.closeButton=close
 local function connect(signal,fn) local c=signal:Connect(fn);table.insert(self.connections,c);return c end
 connect(close.Activated,function() self:close() end)
 connect(Input.InputBegan,function(input)
  if input.KeyCode==Enum.KeyCode.Escape or input.KeyCode==Enum.KeyCode.ButtonB then self:close() end
 end)
 connect(GuiService.MenuOpened,function() self:close() end)
 connect(Players.LocalPlayer.CharacterRemoving,function() self:close() end)
 for _,name in {'VisitingKitchen','VisitingCafeIndex'} do
  connect(Players.LocalPlayer:GetAttributeChangedSignal(name),function() self:close() end)
 end
 connect(Run.RenderStepped,function(dt) self:step(dt) end)
 local folder=ReplicatedStorage:WaitForChild('ChocolateRankings')
 local function update()
  local ok,value=pcall(HttpService.JSONDecode,HttpService,folder:GetAttribute('Snapshot') or '')
  if ok and type(value)=='table' and type(value.boards)=='table' then self.snapshot=value end
  self:render()
 end
 connect(folder:GetAttributeChangedSignal('Snapshot'),update);update()
 local islands=workspace:WaitForChild('KitchenIslands')
 local function added(room)
  local function ready()
   if not gui.Parent or not room.Parent then return end
   local index,origin,ownerId=room:GetAttribute('CafeIndex'),room:GetAttribute('Origin'),room:GetAttribute('OwnerId')
   if index==nil or not origin or not ownerId then return end
   local c=self.pendingRooms[room];if c then c:Disconnect();self.pendingRooms[room]=nil end
   if index==0 then self:addBoard(room,origin) end
  end
  self.pendingRooms[room]=room.AttributeChanged:Connect(ready);ready()
 end
 connect(islands.ChildAdded,added)
 connect(islands.ChildRemoved,function(room)
  local c=self.pendingRooms[room];if c then c:Disconnect();self.pendingRooms[room]=nil end
  local entry=self.world[room]
  if entry then
   if self.entry==entry then self:close() end
   entry.surface:Destroy();entry.part:Destroy();self.world[room]=nil
  end
 end)
 for _,room in islands:GetChildren() do added(room) end
 connect(owner.Destroying,function() gui:Destroy() end)
 gui.Destroying:Connect(function()
  self:close()
  for _,c in self.connections do c:Disconnect() end
  for _,c in self.pendingRooms do c:Disconnect() end;table.clear(self.pendingRooms)
  for _,entry in self.world do entry.surface:Destroy();entry.part:Destroy() end;table.clear(self.world)
  self.camera.camera:Destroy()
 end)
 return self
end
function Rankings:current(entry)
 local p=Players.LocalPlayer
 return entry.room.Parent~=nil and entry.room:GetAttribute('OwnerId')==(p:GetAttribute('VisitingKitchen') or p.UserId)
  and (p:GetAttribute('VisitingCafeIndex') or 0)==0
end
function Rankings:addBoard(room,origin)
 if self.world[room] then return end
 local part=Instance.new('Part');part.Name='GlobalRankingsBoard';part.Anchored=true;part.CanCollide=false;part.CanQuery=true;part.CanTouch=false
 -- Перед картиной по пути от входа: Z=9.7..16.7, картина заканчивается на 9.25.
 -- Спереди нет стола и тумбы каталога; экран целиком помещается на левой стене.
 part.Size=Vector3.new(7,4.25,.25)
 part.CFrame=CFrame.new(origin+Vector3.new(-10.25,4.1,13.2))*CFrame.Angles(0,math.pi/2,0)
 part.Color=Theme.panel;part.Material=Enum.Material.Wood;part.Parent=room
 local surface=Instance.new('SurfaceGui');surface.Name='RankingsSurface';surface.Adornee=part;surface.Face=Enum.NormalId.Back
 surface.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize;surface.LightInfluence=0;surface.MaxDistance=80
 surface.ResetOnSpawn=false;surface.Active=true;surface.Enabled=false;surface.Parent=self.playerGui
 local entry={part=part,room=room,surface=surface,columns={}};self.world[room]=entry
 local background=Instance.new('Frame');background.Name='Board';background.Size=UDim2.fromScale(1,1);background.BackgroundColor3=Theme.panel
 background.BorderSizePixel=0;background.Parent=surface
 local border=Instance.new('Frame');border.Size=UDim2.new(1,-12,1,-12);border.Position=UDim2.fromOffset(6,6);border.BackgroundTransparency=1;border.Parent=background
 local stroke=Instance.new('UIStroke');stroke.Color=Theme.accent;stroke.Thickness=3;stroke.Parent=border
 entry.heading=label(background,'Title',42,Theme.accent);L.set(entry.heading,'Global top 10')
 for _,key in keys do
  local frame=Instance.new('Frame');frame.Name=key;frame.BackgroundTransparency=1;frame.Parent=background
  local title=label(frame,'Title',30,Theme.accent);textSize(title,20,30);L.set(title,titles[key])
  local description=label(frame,'Metric',16,Theme.muted);textSize(description,12,16);L.set(description,descriptions[key])
  local scroll=Instance.new('ScrollingFrame');scroll.Name='Rows';scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0
  scroll.ScrollBarThickness=7;scroll.ScrollBarImageColor3=Theme.accent;scroll.ScrollingDirection=Enum.ScrollingDirection.Y
  scroll.ElasticBehavior=Enum.ElasticBehavior.WhenScrollable;scroll.CanvasSize=UDim2.fromOffset(0,850);scroll.ScrollingEnabled=false;scroll.Active=false;scroll.Parent=frame
  local column={frame=frame,title=title,description=description,scroll=scroll,rows={}};entry.columns[key]=column
  for rank=1,10 do
   local row=label(scroll,'Rank'..rank,28);row.TextXAlignment=Enum.TextXAlignment.Left;textSize(row,12,28)
   row.Position=UDim2.fromOffset(8,(rank-1)*84);row.Size=UDim2.new(1,-28,0,80);column.rows[rank]=row
  end
  local tab=button(background,key..'Tab',titles[key]);entry.columns[key].tab=tab
  tab.Activated:Connect(function() if self.entry==entry and self.camera:ready() then self.key=key;self:fit(entry) end end)
 end
 entry.status=label(background,'Status',17,Theme.muted)
 entry.hint=label(background,'Hint',20,Theme.accent)
 local inspect=Instance.new('TextButton');inspect.Name='Inspect';inspect.Text='';inspect.BackgroundTransparency=1;inspect.Size=UDim2.fromScale(1,1);inspect.ZIndex=5;inspect.Parent=background
 inspect.Activated:Connect(function() self:open(entry) end);entry.inspect=inspect
 local prompt=Instance.new('ProximityPrompt');prompt.Name='RankingsPrompt';prompt.ActionText=L.text('View rankings');prompt.ObjectText=L.text('Global top 10')
 local anchor=Instance.new('Attachment');anchor.Position=Vector3.new(0,-.6,1.5);anchor.Parent=part
 prompt.MaxActivationDistance=4.5;prompt.RequiresLineOfSight=false;prompt.ClickablePrompt=true;prompt.Enabled=false;prompt.Parent=anchor;entry.prompt=prompt
 prompt.Triggered:Connect(function(player) if not player or player==Players.LocalPlayer then self:open(entry) end end)
 self:fit(entry);self:render()
end
function Rankings:fit(entry)
 local focused=self.entry==entry
 local viewport=self.camera.camera.ViewportSize
 local portrait=focused and viewport.X<viewport.Y
 entry.portrait=portrait
 entry.surface.CanvasSize=if portrait then Vector2.new(620,376) else Vector2.new(1020,620)
 entry.heading.Position=UDim2.fromOffset(18,10);entry.heading.Size=UDim2.new(1,-36,0,if portrait then 48 else 54)
 entry.heading.TextSize=42
 for index,key in keys do
  local column=entry.columns[key]
  column.frame.Visible=not portrait or key==self.key
  column.frame.Position=if portrait then UDim2.fromOffset(12,138) else UDim2.fromOffset((index-1)*336+12,80)
  column.frame.Size=if portrait then UDim2.fromOffset(596,182) else UDim2.fromOffset(324,466)
  column.title.Visible=not portrait;column.title.Size=UDim2.new(1,-8,0,58)
  column.description.Position=UDim2.fromOffset(4,if portrait then 0 else 62)
  column.description.Size=UDim2.new(1,-8,0,if portrait then 32 else 60)
  column.description.Visible=not portrait
  column.scroll.Position=UDim2.fromOffset(0,if portrait then 0 else 128)
  column.scroll.Size=UDim2.new(1,0,1,if portrait then 0 else -128)
  -- На телефоне вкладка занимает около 44 экранных пикселей; длинное
  -- описание остаётся в широком виде, а имена получают крупный шрифт.
  column.tab.Visible=portrait;column.tab.Position=UDim2.new((index-1)/3,12,0,58);column.tab.Size=UDim2.new(1/3,-20,0,70)
  L.set(column.tab,if portrait then compactTitles[key] else titles[key])
  for _,row in column.rows do
   local limit=row:FindFirstChildOfClass('UITextSizeConstraint');limit.MinTextSize=if portrait then 18 else 12;limit.MaxTextSize=if portrait then 34 else 28
  end
  column.tab.BackgroundColor3=if key==self.key then Theme.chocolateEdge else Theme.chocolate
 end
 entry.status.Position=UDim2.new(0,18,1,if portrait then -52 else -70);entry.status.Size=UDim2.new(1,-36,0,if portrait then 22 else 30)
 entry.hint.Position=UDim2.new(0,18,1,if portrait then -28 else -36);entry.hint.Size=UDim2.new(1,-36,0,if portrait then 22 else 28)
 entry.status.TextSize=if portrait then 18 else 17;entry.hint.TextSize=if portrait then 22 else 20
 entry.inspect.Visible=not focused
end
function Rankings:open(entry)
 if not self.kitchen:canWalk() then return end
 if not entry then for _,candidate in self.world do if self:current(candidate) then entry=candidate;break end end end
 if not entry or not self:current(entry) then return end
 local root=Players.LocalPlayer.Character and Players.LocalPlayer.Character:FindFirstChild('HumanoidRootPart')
 if not root or (root.Position-entry.prompt.Parent.WorldPosition).Magnitude>entry.prompt.MaxActivationDistance+.5 then return end
 if not self.camera:open(entry.part) then return end
 self.view:endDrag(true);self.entry=entry;self.view.rankingsOpen=true;self.closeButton.Visible=true
 self.kitchen:refreshControls();self.kitchen:setAvatarVisible(false)
 for _,column in entry.columns do
  -- Закрытие и повторное открытие могут произойти между двумя кадрами.
  -- Старый разрешённый ввод не должен пережить начало нового поворота.
  column.scroll.ScrollingEnabled=false;column.scroll.Active=false;column.scroll.CanvasPosition=Vector2.zero
 end
 self:fit(entry);self:render()
end
function Rankings:close()
 local entry=self.entry
 if not entry then return end
 self.entry=nil;self.camera:close();self.closeButton.Visible=false;self.view.rankingsOpen=false
 for _,column in entry.columns do column.scroll.ScrollingEnabled=false;column.scroll.Active=false end
 self.kitchen:refreshControls()
 self.kitchen:setAvatarVisible(not self.kitchen.focus and not self.kitchen.preview)
 self:fit(entry);self:render()
end
function Rankings:step(dt)
 local entry=self.entry
 if entry then
  if not self.kitchen.opened or not self:current(entry) or not self.camera:step(dt) then self:close()
  else
   local portrait=self.camera.camera.ViewportSize.X<self.camera.camera.ViewportSize.Y
   if portrait~=entry.portrait then self:fit(entry) end
  end
 end
 for _,board in self.world do
  local current=self:current(board) and self.kitchen.opened
  board.surface.Enabled=current
  board.prompt.Enabled=current and self.kitchen:canWalk()
  local interactive=self.entry==board and self.camera:ready()
  for _,column in board.columns do column.scroll.ScrollingEnabled=interactive;column.scroll.Active=interactive end
 end
end
function Rankings:render()
 local status='All servers · updates about once a minute after saving'
 local pending,stale,hasRows=false,false,false
 for _,key in keys do
  local board=self.snapshot.boards[key]
  pending=pending or not board or not board.ready
  stale=stale or (board and board.stale)
  hasRows=hasRows or (board and board.rows and #board.rows>0)
 end
 if self.snapshot.studio then status='Studio preview · global records are not loaded'
 elseif stale then status='Rankings delayed · showing the last available results'
 elseif pending then status='Loading rankings'
 elseif not hasRows then status='No records yet · saved progress will appear here' end
 for _,entry in self.world do
  entry.prompt.ActionText=L.text('View rankings');entry.prompt.ObjectText=L.text('Global top 10')
  L.set(entry.status,status)
  L.set(entry.hint,if self.entry==entry then 'Scroll each list with the wheel or a finger' else 'Approach the board to see all 10 players')
  for key,column in entry.columns do
   local board=self.snapshot.boards[key]
   for rank,row in column.rows do rowText(row,rank,board and board.rows and board.rows[rank]) end
  end
 end
end
return Rankings
