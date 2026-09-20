--!nonstrict
-- Список строится из уже реплицированных домашних комнат. Выбор лишь
-- отправляет намерение: сервер ещё раз проверяет стрелку и присутствие хозяина.
local Players=game:GetService("Players")
local Workspace=game:GetService("Workspace")
local RunService=game:GetService("RunService")
local UserInputService=game:GetService("UserInputService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Queue=require(Shared.CafeQueue)
local Theme=require(script.Parent.Theme)
local L=require(script.Parent.Localization)
local Directory={}; Directory.__index=Directory
local function round(object,radius)
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,radius or 12); corner.Parent=object
end
local function label(parent,name,size,color)
 local t=Instance.new("TextLabel"); t.Name=name; t.BackgroundTransparency=1
 t.Font=Enum.Font.GothamMedium; t.TextColor3=color or Theme.text; t.TextSize=size
 t.TextXAlignment=Enum.TextXAlignment.Left; t.TextWrapped=true; t.Parent=parent
 t.TextScaled=true; local constraint=Instance.new("UITextSizeConstraint"); constraint.MinTextSize=10; constraint.MaxTextSize=size; constraint.Parent=t
 return t
end
local function button(parent,name,caption)
 local b=Instance.new("TextButton"); b.Name=name; b.BorderSizePixel=0; b.BackgroundColor3=Theme.accent
 b.Font=Enum.Font.GothamBold; b.TextColor3=Theme.background; b.TextSize=17; b.TextWrapped=true; b.Parent=parent
 round(b); L.set(b,caption); return b
end
function Directory.new(kitchen)
 local self=setmetatable({kitchen=kitchen,entries={},elapsed=0},Directory)
 self.remote=kitchen.atelier.remotes.cafeVisit
 local gui=Instance.new("ScreenGui"); gui.Name="CafeDirectory"; gui.IgnoreGuiInset=true
 gui.ResetOnSpawn=false; gui.DisplayOrder=30; gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; gui.Parent=kitchen.gui.Parent; self.gui=gui
 local overlay=Instance.new("Frame"); overlay.Name="Overlay"; overlay.Size=UDim2.fromScale(1,1)
 overlay.BackgroundColor3=Theme.background; overlay.BackgroundTransparency=.18; overlay.BorderSizePixel=0
 overlay.Active=true; overlay.Visible=false; overlay.Parent=gui; self.overlay=overlay
 local panel=Instance.new("Frame"); panel.Name="Directory"; panel.BackgroundColor3=Theme.panel; panel.BorderSizePixel=0
 panel.AnchorPoint=Vector2.new(.5,.5); panel.Position=UDim2.fromScale(.5,.5); panel.Size=UDim2.new(1,-24,1,-32); panel.Parent=overlay; round(panel); self.panel=panel
 local bounds=Instance.new("UISizeConstraint"); bounds.MaxSize=Vector2.new(480,600); bounds.Parent=panel
 local title=label(panel,"Title",23,Theme.accent); title.Position=UDim2.fromOffset(16,12); title.Size=UDim2.new(1,-84,0,44); L.set(title,"Visit a cafe")
 local close=button(panel,"Close","×"); close.Position=UDim2.new(1,-54,0,16); close.Size=UDim2.fromOffset(38,38); close.Activated:Connect(function() self:close() end)
 self.status=label(panel,"Status",14,Theme.muted); self.status.Position=UDim2.fromOffset(16,65); self.status.Size=UDim2.new(1,-32,0,42)
 local scroll=Instance.new("ScrollingFrame"); scroll.Name="Cafes"; scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0
 scroll.Position=UDim2.fromOffset(12,118); scroll.Size=UDim2.new(1,-24,1,-188)
 scroll.ScrollBarThickness=4; scroll.ScrollBarImageColor3=Theme.accent; scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.CanvasSize=UDim2.fromOffset(0,0); scroll.Parent=panel; self.scroll=scroll
 local layout=Instance.new("UIListLayout"); layout.SortOrder=Enum.SortOrder.LayoutOrder; layout.Padding=UDim.new(0,10); layout.Parent=scroll
 self.empty=label(panel,"Empty",18,Theme.muted); self.empty.Position=UDim2.fromOffset(24,145); self.empty.Size=UDim2.new(1,-48,0,120)
 self.empty.TextXAlignment=Enum.TextXAlignment.Center; L.set(self.empty,"Other players' cafes will appear here when they join this server.")
 self.next=button(panel,"Next","Next cafe →"); self.next.Position=UDim2.new(0,16,1,-56); self.next.Size=UDim2.new(1,-32,0,40)
 self.next.Activated:Connect(function()
  local k=self.kitchen; local id=Queue.nextVisitor(self.entries,k.player.UserId,k.player:GetAttribute("VisitingKitchen") or k.player.UserId)
  if id then self:visit(id) end
 end)
 self.receive=self.remote.OnClientEvent:Connect(function(action)
  if action=="open" then self:open()
  elseif action=="unavailable" then
   self.busy=false; self.key=nil; self:refresh()
   self.noticeUntil=os.clock()+3; L.set(self.status,"That cafe is no longer available. Choose another.")
  elseif action=="arrived" or action=="close" then self:close() end
 end)
 self.step=RunService.Heartbeat:Connect(function(dt)
  if not self.overlay.Visible then return end
  self.elapsed+=dt; if self.elapsed<.5 then return end; self.elapsed=0
  if self.busy and os.clock()>(self.busyUntil or 0) then self.busy=false end
  self:refresh()
 end)
 self.input=UserInputService.InputBegan:Connect(function(input)
  if input.KeyCode==Enum.KeyCode.Escape and overlay.Visible then self:close() end
 end)
 return self
end
function Directory:open()
 local k=self.kitchen
 if not k.opened or k.focus or k.shopping then return end
 k.browsing=true; k.controls:Disable(); self.busy=false; self.noticeUntil=nil
 self.overlay.Visible=true; self.key=nil; self:refresh()
end
function Directory:close()
 self.overlay.Visible=false; self.busy=false
 local k=self.kitchen; k.browsing=false
 if k.opened and not k.focus and not k.shopping then k.controls:Enable() end
end
function Directory:visit(id)
 if not self.overlay.Visible or self.busy then return end
 local allowed=false
 for _,entry in self.entries do if entry.owner==id then allowed=true; break end end
 if not allowed then return end
 self.busy=true; self.busyUntil=os.clock()+3
 L.set(self.status,"Visiting cafe…"); self.remote:FireServer(id)
end
function Directory:refresh()
 local k=self.kitchen; local records={}; local folder=Workspace:FindFirstChild("KitchenIslands")
 for _,model in if folder then folder:GetChildren() else {} do
  local id=model:GetAttribute("OwnerId")
  if id then table.insert(records,{owner=id,index=model:GetAttribute("CafeIndex") or 0,
   online=model:GetAttribute("OwnerOnline"),count=model:GetAttribute("CafeCount") or 0,
   name=model:GetAttribute("DisplayName") or tostring(id),username=model:GetAttribute("Username") or tostring(id)}) end
 end
 self.entries=Queue.visitors(records,k.player.UserId,k.player:GetAttribute("VisitingKitchen") or k.player.UserId)
 if not self.busy and os.clock()>(self.noticeUntil or 0) then L.set(self.status,"Players to visit: {count}",{count=#self.entries}) end
 self.empty.Visible=#self.entries==0
 self.next.Active=#self.entries>0; self.next.AutoButtonColor=#self.entries>0
 self.next.BackgroundColor3=if #self.entries>0 then Theme.accent else Theme.chocolateDark
 self.next.TextColor3=if #self.entries>0 then Theme.background else Theme.muted
 local key=""
 for _,entry in self.entries do key..=entry.owner..":"..entry.name..":"..entry.username..":"..entry.count.."/" end
 if self.key==key then return end; self.key=key
 for _,child in self.scroll:GetChildren() do if child:IsA("GuiObject") then child:Destroy() end end
 for index,entry in self.entries do
  local row=button(self.scroll,"Cafe_"..entry.owner,""); row.BackgroundColor3=Theme.chocolate; row.LayoutOrder=index; row.Size=UDim2.new(1,-8,0,88)
  row.Activated:Connect(function() self:visit(entry.owner) end)
  local portrait=Instance.new("ImageLabel"); portrait.Name="Avatar"; portrait.BackgroundColor3=Theme.chocolateDark; portrait.BorderSizePixel=0
  portrait.Position=UDim2.fromOffset(10,16); portrait.Size=UDim2.fromOffset(56,56); portrait.Parent=row; round(portrait,28)
  local initial=label(portrait,"Initial",22,Theme.accentSoft); initial.Size=UDim2.fromScale(1,1); initial.TextXAlignment=Enum.TextXAlignment.Center
  initial.Text=string.sub(entry.name,1,(utf8.offset(entry.name,2) or (#entry.name+1))-1); initial.AutoLocalize=false
  portrait:GetPropertyChangedSignal("IsLoaded"):Connect(function() initial.Visible=not portrait.IsLoaded end)
  local name=label(row,"Name",18,Theme.accentSoft); name.Position=UDim2.fromOffset(78,6); name.Size=UDim2.new(1,-116,0,27); name.Text=entry.name
  local username=label(row,"Username",12,Theme.muted); username.Position=UDim2.fromOffset(78,33); username.Size=UDim2.new(1,-116,0,18); username.Text="@"..entry.username
  name.AutoLocalize=false; username.AutoLocalize=false
  local count=label(row,"Factory",12,Theme.text); count.Position=UDim2.fromOffset(78,55); count.Size=UDim2.new(1,-116,0,24)
  L.set(count,"Factory: {count} cafes",{count=L.number(entry.count+1)})
  local arrow=label(row,"Visit",25,Theme.accent); arrow.Position=UDim2.new(1,-32,0,26); arrow.Size=UDim2.fromOffset(24,34); arrow.Text="›"
  task.spawn(function()
   local ok,image=pcall(function() return Players:GetUserThumbnailAsync(entry.owner,Enum.ThumbnailType.HeadShot,Enum.ThumbnailSize.Size100x100) end)
   if ok and portrait.Parent then portrait.Image=image end
  end)
 end
end
function Directory:destroy()
 self.receive:Disconnect(); self.step:Disconnect(); self.input:Disconnect(); self:close(); self.gui:Destroy()
end
return Directory
