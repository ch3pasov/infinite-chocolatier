--!nonstrict
-- Доски показывают серверный снимок. Приближение открывает читаемый список
-- на маленьком экране; клиент никогда не отправляет очки на сервер.
local Players=game:GetService('Players')
local ReplicatedStorage=game:GetService('ReplicatedStorage')
local HttpService=game:GetService('HttpService')
local UserInputService=game:GetService('UserInputService')
local L=require(script.Parent.Localization)
local Theme=require(script.Parent.Theme)
local Rankings={}; Rankings.__index=Rankings
local keys={'pieces','guests','tricks'}
local titles={pieces='Lifetime pieces',guests='Unique guests',tricks='Manual tricks'}
local descriptions={pieces='All pieces earned, shown as whole pieces. Spending and prestige keep this total.',
 guests='Unique lifetime cafe visitors. Repeat visits do not add guests.',
 tricks='Completed manual tricks only. Apprentice production does not count.'}
local function label(parent,name,position,size,textSize,color)
 local t=Instance.new('TextLabel');t.Name=name;t.BackgroundTransparency=1;t.Position=position;t.Size=size
 t.Font=Enum.Font.GothamMedium;t.TextSize=textSize;t.TextColor3=color or Theme.text
 t.TextWrapped=true;t.RichText=false;t.Text='';t.Parent=parent;return t
end
local function button(parent,name,caption,position,size)
 local b=Instance.new('TextButton');b.Name=name;b.Position=position;b.Size=size;b.Font=Enum.Font.GothamBold
 b.BackgroundColor3=Theme.chocolate;b.TextColor3=Theme.accent;b.BorderSizePixel=0;b.TextSize=14
 b.TextWrapped=true;b.TextScaled=true;L.set(b,caption);b.Parent=parent
 local c=Instance.new('UITextSizeConstraint');c.MinTextSize=10;c.MaxTextSize=14;c.Parent=b
 local corner=Instance.new('UICorner');corner.CornerRadius=UDim.new(0,10);corner.Parent=b;return b
end
function Rankings.new(owner,view,kitchen)
 local self=setmetatable({view=view,kitchen=kitchen,key='pieces',snapshot={boards={}},world={},pendingRooms={},connections={}},Rankings)
 local gui=Instance.new('ScreenGui');gui.Name='ChocolateRankings';gui.ResetOnSpawn=false;gui.DisplayOrder=35;gui.IgnoreGuiInset=false;gui.Parent=owner.Parent;self.gui=gui
 local overlay=Instance.new('TextButton');overlay.Name='Overlay';overlay.Text='';overlay.AutoButtonColor=false
 overlay.Size=UDim2.fromScale(1,1);overlay.BackgroundColor3=Theme.background;overlay.BackgroundTransparency=.15;overlay.Visible=false;overlay.Parent=gui;self.overlay=overlay
 local panel=Instance.new('Frame');panel.Name='Rankings';panel.AnchorPoint=Vector2.new(.5,.5);panel.Position=UDim2.fromScale(.5,.5)
 panel.Size=UDim2.new(1,-24,1,-24);panel.BackgroundColor3=Theme.panel;panel.BorderSizePixel=0;panel.Active=true;panel.Parent=overlay;self.panel=panel
 local bounds=Instance.new('UISizeConstraint');bounds.MaxSize=Vector2.new(580,650);bounds.Parent=panel
 local title=label(panel,'Title',UDim2.fromOffset(16,10),UDim2.new(1,-76,0,42),22,Theme.accent);L.set(title,'Global top 10');self.title=title
 self.closeButton=button(panel,'Close','×',UDim2.new(1,-50,0,12),UDim2.fromOffset(36,36));self.closeButton.Activated:Connect(function() self:close() end)
 self.tabs={}
 for index,key in keys do
  local b=button(panel,key,titles[key],UDim2.new((index-1)/3,8,0,58),UDim2.new(1/3,-12,0,40));self.tabs[key]=b
  b.Activated:Connect(function() self.key=key;self:render() end)
 end
 self.help=label(panel,'Metric',UDim2.fromOffset(16,104),UDim2.new(1,-32,0,64),13,Theme.muted)
 local scroll=Instance.new('ScrollingFrame');scroll.Name='Rows';scroll.Position=UDim2.fromOffset(12,174);scroll.Size=UDim2.new(1,-24,1,-230)
 scroll.BackgroundTransparency=1;scroll.BorderSizePixel=0;scroll.ScrollBarThickness=4;scroll.ScrollBarImageColor3=Theme.accent;scroll.CanvasSize=UDim2.fromOffset(0,560);scroll.Active=true;scroll.Parent=panel;self.scroll=scroll
 self.rows={}
 for i=1,10 do
  local row=label(scroll,'Rank'..i,UDim2.fromOffset(8,(i-1)*54),UDim2.new(1,-24,0,50),16)
  row.TextXAlignment=Enum.TextXAlignment.Left;row.TextScaled=true
  local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=10;limit.MaxTextSize=16;limit.Parent=row;self.rows[i]=row
 end
 self.status=label(panel,'Status',UDim2.new(0,16,1,-48),UDim2.new(1,-32,0,40),12,Theme.muted)
 local function connect(signal,fn) local c=signal:Connect(fn);table.insert(self.connections,c);return c end
 connect(panel:GetPropertyChangedSignal('AbsoluteSize'),function() self:fit() end);self:fit()
 connect(UserInputService.InputBegan,function(input) if input.KeyCode==Enum.KeyCode.Escape then self:close() end end)
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
   -- Модель и её атрибуты могут реплицироваться разными пакетами.
   local index=room:GetAttribute('CafeIndex')
   local origin=room:GetAttribute('Origin')
   if index==nil or not origin then return end
   local c=self.pendingRooms[room];if c then c:Disconnect();self.pendingRooms[room]=nil end
   if index==0 then self:addBoard(room,origin) end
  end
  self.pendingRooms[room]=room.AttributeChanged:Connect(ready);ready()
 end
 connect(islands.ChildAdded,added)
 connect(islands.ChildRemoved,function(room)
  local c=self.pendingRooms[room];if c then c:Disconnect();self.pendingRooms[room]=nil end
  local b=self.world[room];if b then b.part:Destroy();self.world[room]=nil end
 end)
 for _,room in islands:GetChildren() do added(room) end
 connect(owner.Destroying,function() gui:Destroy() end)
 gui.Destroying:Connect(function()
  self:close();for _,c in self.connections do c:Disconnect() end
  for _,c in self.pendingRooms do c:Disconnect() end;table.clear(self.pendingRooms)
  for _,entry in self.world do entry.part:Destroy() end;table.clear(self.world)
 end)
 return self
end
function Rankings:addBoard(room,origin)
 if self.world[room] then return end
 local part=Instance.new('Part');part.Name='GlobalRankingsBoard';part.Anchored=true;part.CanCollide=false;part.CanQuery=false;part.CanTouch=false
 -- Камера прогулки смотрит с юга. Доска над дальней стеной видна из кафе
 -- и не заслоняет проход, аватар, столы или купленный настенный декор.
 part.Size=Vector3.new(17,7,.35);part.Position=origin+Vector3.new(0,10,-6.2);part.Color=Theme.panel;part.Material=Enum.Material.Wood;part.Parent=room
 local surface=Instance.new('SurfaceGui');surface.Name='RankingsSurface';surface.Face=Enum.NormalId.Back;surface.CanvasSize=Vector2.new(1020,420)
 -- Текст не темнеет вместе с деревянной панелью; дальние копии не рисуют
 -- плавающие подписи над соседними островами за пределами прогулочной кухни.
 surface.LightInfluence=0;surface.MaxDistance=80;surface.Parent=part
 local border=Instance.new('Frame');border.Size=UDim2.new(1,-12,1,-12);border.Position=UDim2.fromOffset(6,6);border.BackgroundTransparency=1;border.Parent=surface
 local stroke=Instance.new('UIStroke');stroke.Color=Theme.accent;stroke.Thickness=3;stroke.Parent=border
 local heading=label(surface,'Title',UDim2.fromOffset(20,12),UDim2.new(1,-40,0,52),48,Theme.accent);L.set(heading,'Global top 10')
 local entry={part=part,columns={}};self.world[room]=entry
 for index,key in keys do
  local x=(index-1)*340
  local title=label(surface,key..'Title',UDim2.fromOffset(x+12,74),UDim2.fromOffset(316,54),34,Theme.accent);L.set(title,titles[key])
  title.TextScaled=true;local titleLimit=Instance.new('UITextSizeConstraint');titleLimit.MinTextSize=22;titleLimit.MaxTextSize=34;titleLimit.Parent=title
  entry.columns[key]={}
  for rank=1,3 do
   local row=label(surface,key..rank,UDim2.fromOffset(x+16,136+(rank-1)*62),UDim2.fromOffset(308,58),22)
   row.TextScaled=true;local limit=Instance.new('UITextSizeConstraint');limit.MinTextSize=18;limit.MaxTextSize=30;limit.Parent=row
   row.TextXAlignment=Enum.TextXAlignment.Left;entry.columns[key][rank]=row
  end
 end
 local footer=label(surface,'Open',UDim2.fromOffset(20,338),UDim2.new(1,-40,0,60),23,Theme.muted);entry.footer=footer
 local prompt=Instance.new('ProximityPrompt');prompt.Name='RankingsPrompt';prompt.ActionText=L.text('View rankings');prompt.ObjectText=L.text('Global top 10')
 local anchor=Instance.new('Attachment');anchor.Position=Vector3.new(0,-6.5,1.3);anchor.Parent=part
 prompt.MaxActivationDistance=8;prompt.RequiresLineOfSight=false;prompt.Parent=anchor
 entry.prompt=prompt
 prompt.Triggered:Connect(function(player) if not player or player==Players.LocalPlayer then self:open() end end)
 self:render()
end
function Rankings:open()
 if not self.kitchen:canWalk() then return end
 self.view:endDrag(true);self.overlay.Visible=true;self.view.rankingsOpen=true;self.kitchen:refreshControls()
 self.scroll.CanvasPosition=Vector2.zero;self:render()
end
function Rankings:close()
 self.overlay.Visible=false;self.view.rankingsOpen=false;self.kitchen:refreshControls()
end
local function rowText(label,rank,row,short)
 if row then
  -- На дальней доске длинное имя не должно уменьшать весь результат.
  -- Полное имя остаётся в открываемом списке и в самом серверном снимке.
  local name=if short and #row.name>12 then string.sub(row.name,1,11)..'…' else row.name
  L.set(label,'{rank}. {name}\n{score}',{rank=tostring(rank),name=name,score=L.number(row.score)})
 else L.set(label,'{rank}. —',{rank=tostring(rank)}) end
end
function Rankings:render()
 for key,b in self.tabs do b.BackgroundColor3=if key==self.key then Theme.chocolateEdge else Theme.chocolate end
 L.set(self.help,descriptions[self.key])
 local board=self.snapshot.boards[self.key] or {rows={}}
 for i,label in self.rows do rowText(label,i,board.rows and board.rows[i]) end
 local status=if self.snapshot.studio then 'Studio preview · global records are not loaded'
  elseif board.stale then 'Rankings delayed · showing the last available results'
  elseif not board.ready then 'Loading rankings'
  elseif #board.rows==0 then 'No records yet · saved progress will appear here'
 else 'All servers · updates about once a minute after saving'
 L.set(self.status,status)
 for _,entry in self.world do
  if entry.prompt then
   local action,object=L.text('View rankings'),L.text('Global top 10')
   if entry.prompt.ActionText~=action then entry.prompt.ActionText=action end
   if entry.prompt.ObjectText~=object then entry.prompt.ObjectText=object end
  end
  L.set(entry.footer,if self.snapshot.studio then 'Studio preview · global records are not loaded' else 'Approach the board to see all 10 players')
  for key,rows in entry.columns do local source=self.snapshot.boards[key]
   for i,label in rows do rowText(label,i,source and source.rows[i],true) end
  end
 end
end
function Rankings:fit()
 -- В низком горизонтальном телефоне остаётся хотя бы одна полная строка;
 -- остальные места доступны прокруткой, описание и состояние не перекрывают её.
 local tight=self.panel.AbsoluteSize.Y<360
 self.title.Size=UDim2.new(1,-76,0,if tight then 30 else 42)
 self.title.TextSize=if tight then 18 else 22
 self.closeButton.Position=UDim2.new(1,-50,0,if tight then 6 else 12)
 for index,key in keys do self.tabs[key].Position=UDim2.new((index-1)/3,8,0,if tight then 46 else 58) end
 self.help.Position=UDim2.fromOffset(16,if tight then 90 else 104)
 self.help.Size=UDim2.new(1,-32,0,if tight then 48 else 64)
 self.help.TextSize=if tight then 11 else 13
 self.scroll.Position=UDim2.fromOffset(12,if tight then 140 else 174)
 self.scroll.Size=UDim2.new(1,-24,1,if tight then -182 else -230)
 self.status.Position=UDim2.new(0,16,1,if tight then -36 else -48)
 self.status.Size=UDim2.new(1,-32,0,if tight then 30 else 40)
 self.status.TextSize=if tight then 10 else 12
end
return Rankings
