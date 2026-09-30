--!nonstrict
-- Музыка и эффекты имеют независимые группы: выключение одной не меняет
-- другую. Настройки принадлежат клиенту и не вмешиваются в профиль игрока.
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local StarterGui = game:GetService("StarterGui")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local Theme = require(script.Parent.Theme)
local L = require(script.Parent.Localization)
local Audio = {}
Audio.__index = Audio

local function make(class,parent,name)
 local object=Instance.new(class); object.Name=name; object.Parent=parent
 return object
end
local function rounded(object,radius)
 local corner=make("UICorner",object,"Corner"); corner.CornerRadius=UDim.new(0,radius)
end
local function label(parent,name,size)
 local object=make("TextLabel",parent,name)
 object.BackgroundTransparency=1; object.Font=Enum.Font.GothamMedium
 object.TextSize=size; object.TextColor3=Theme.text; object.TextXAlignment=Enum.TextXAlignment.Left
 return object
end
local function button(parent,name,text)
 local object=make("TextButton",parent,name)
 object.Font=Enum.Font.GothamBold; object.TextSize=22; object.Text=text; object.AutoLocalize=false
 object.BackgroundColor3=Theme.chocolateDark; object.TextColor3=Theme.accent; object.BorderSizePixel=0
 rounded(object,8); return object
end
function Audio:connect(signal,callback)
 table.insert(self.connections,signal:Connect(callback))
end

function Audio.new(gui,view)
 local self=setmetatable({view=view,sounds={},last={},tokens={},buttons={},connections={},rows={},
  volumes=table.clone(Config.Audio.defaults),destroyed=false},Audio)
 self.folder=make("Folder",SoundService,"ChocolateAudio")
 self.groups={}
 for _,channel in {"effects","music"} do
  local group=make("SoundGroup",self.folder,channel); group.Volume=self.volumes[channel]; self.groups[channel]=group
 end
 local preload={}
 for name,spec in Config.Audio.effects do
  local sound=make("Sound",self.folder,name); sound.SoundId=spec.id
  sound.Volume=spec.volume; sound.PlaybackSpeed=spec.speed or 1; sound.SoundGroup=self.groups.effects
  self.sounds[name]=sound; table.insert(preload,sound)
 end
 self.music=make("Sound",self.folder,"ClassicalMusic"); self.music.SoundId=Config.Audio.music.id
 self.music.Volume=Config.Audio.music.volume; self.music.SoundGroup=self.groups.music; self.music.Looped=true
 -- Большая музыкальная запись загружается отдельно и не задерживает короткие
 -- эффекты. Ни звук, ни его сбой не блокируют профиль и первый жест.
 task.spawn(function()
  if not self.destroyed then pcall(function() ContentProvider:PreloadAsync(preload) end) end
 end)
 task.spawn(function()
  if self.destroyed then return end
  pcall(function() ContentProvider:PreloadAsync({self.music}) end)
  self:startMusic()
 end)
 self.gui=make("ScreenGui",gui.Parent,"ChocolateAudioControls")
 self.gui.ResetOnSpawn=false; self.gui.IgnoreGuiInset=true; self.gui.DisplayOrder=40
 self.toggle=button(self.gui,"SoundToggle","♪")
 self.toggle.AnchorPoint=Vector2.new(1,0); self.toggle.Position=UDim2.new(1,-12,0,16)
 self.toggle.Size=UDim2.fromOffset(44,36); self.toggle.TextSize=23; self.toggle.BackgroundColor3=Theme.panel
 self.shade=button(self.gui,"Dismiss",""); self.shade.Size=UDim2.fromScale(1,1)
 self.shade.BackgroundTransparency=1; self.shade.Visible=false; self.shade.ZIndex=2
 self.panel=make("Frame",self.gui,"Settings"); self.panel.AnchorPoint=Vector2.new(1,0)
 self.panel.Position=UDim2.new(1,-12,0,60); self.panel.Size=UDim2.new(1,-24,0,232)
 self.panel.BackgroundColor3=Theme.panel; self.panel.BorderSizePixel=0; self.panel.Visible=false; self.panel.Active=true; self.panel.ZIndex=3
 rounded(self.panel,12)
 local limit=make("UISizeConstraint",self.panel,"WidthLimit"); limit.MaxSize=Vector2.new(320,232)
 local title=label(self.panel,"Title",18); title.Position=UDim2.fromOffset(16,10); title.Size=UDim2.new(1,-68,0,30); title.ZIndex=4
 L.set(title,"Audio settings")
 local close=button(self.panel,"Close","×"); close.Position=UDim2.new(1,-44,0,8); close.Size=UDim2.fromOffset(32,32); close.ZIndex=4
 self:createRow("music","Music",48); self:createRow("effects","Game sounds",124)
 local note=label(self.panel,"Hint",12); note.Position=UDim2.fromOffset(16,204); note.Size=UDim2.new(1,-32,0,20); note.TextColor3=Theme.muted; note.ZIndex=4
 L.set(note,"0% = off")
 self:connect(self.toggle.Activated,function() self:setOpen(not self.panel.Visible); self:play("ui") end)
 self:connect(close.Activated,function() self:setOpen(false); self:play("ui") end)
 self:connect(self.shade.Activated,function() self:setOpen(false) end)
 self:connect(UserInputService.InputChanged,function(input)
  local drag=self.drag
  if drag and (input==drag.input or drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then
   self:slide(drag.channel,input.Position.X)
  end
 end)
 self:connect(UserInputService.InputEnded,function(input)
  local drag=self.drag
  if drag and (input==drag.input or drag.input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then self.drag=nil end
 end)
 self:connect(UserInputService.InputBegan,function(input)
  if not self.panel.Visible then return end
  if input.KeyCode==Enum.KeyCode.Escape then self:setOpen(false); return end
  for channel,row in self.rows do
   if GuiService.SelectedObject==row.track then
    if input.KeyCode==Enum.KeyCode.Left or input.KeyCode==Enum.KeyCode.DPadLeft then self:setVolume(channel,self.volumes[channel]-.1)
    elseif input.KeyCode==Enum.KeyCode.Right or input.KeyCode==Enum.KeyCode.DPadRight then self:setVolume(channel,self.volumes[channel]+.1) end
   end
  end
 end)
 local function interrupted() self:setOpen(false); self:stopMotion() end
 self:connect(UserInputService.WindowFocusReleased,interrupted)
 self:connect(GuiService.MenuOpened,interrupted)
 self:connect(gui.Destroying,function() self:destroy() end)
 for _,channel in {"effects","music"} do self:renderVolume(channel) end
 for _,object in gui.Parent:GetDescendants() do self:bindButton(object) end
 self:connect(gui.Parent.DescendantAdded,function(object) self:bindButton(object) end)
 return self
end

function Audio:createRow(channel,source,y)
 local frame=make("Frame",self.panel,channel.."Row"); frame.Position=UDim2.fromOffset(0,y); frame.Size=UDim2.new(1,0,0,76)
 frame.BackgroundTransparency=1; frame.ZIndex=4
 local caption=label(frame,"Label",15); caption.Position=UDim2.fromOffset(16,0); caption.Size=UDim2.new(1,-94,0,28); caption.ZIndex=4; L.set(caption,source)
 local value=label(frame,"Value",14); value.Position=UDim2.new(1,-76,0,0); value.Size=UDim2.fromOffset(60,28); value.TextXAlignment=Enum.TextXAlignment.Right; value.AutoLocalize=false; value.ZIndex=4
 local minus=button(frame,"Minus","−"); minus.Position=UDim2.fromOffset(12,32); minus.Size=UDim2.fromOffset(32,36); minus.ZIndex=4
 local plus=button(frame,"Plus","+"); plus.Position=UDim2.new(1,-44,0,32); plus.Size=UDim2.fromOffset(32,36); plus.ZIndex=4
 local track=button(frame,"Slider",""); track.Position=UDim2.fromOffset(52,32); track.Size=UDim2.new(1,-104,0,36); track.BackgroundTransparency=1; track.ZIndex=4
 local rail=make("Frame",track,"Rail"); rail.AnchorPoint=Vector2.new(0,.5); rail.Position=UDim2.fromScale(0,.5); rail.Size=UDim2.new(1,0,0,8); rail.BackgroundColor3=Theme.chocolateRaised; rail.BorderSizePixel=0; rail.ZIndex=4; rounded(rail,4)
 local fill=make("Frame",rail,"Fill"); fill.Size=UDim2.fromScale(0,1); fill.BackgroundColor3=Theme.accent; fill.BorderSizePixel=0; fill.ZIndex=5; rounded(fill,4)
 local thumb=make("Frame",track,"Thumb"); thumb.AnchorPoint=Vector2.new(.5,.5); thumb.Size=UDim2.fromOffset(16,16); thumb.BackgroundColor3=Theme.accentSoft; thumb.BorderSizePixel=0; thumb.ZIndex=6; rounded(thumb,8)
 self.rows[channel]={track=track,value=value,fill=fill,thumb=thumb}
 self:connect(minus.Activated,function() self:setVolume(channel,self.volumes[channel]-.1) end)
 self:connect(plus.Activated,function() self:setVolume(channel,self.volumes[channel]+.1); if channel=="effects" then self:play("ui") end end)
 self:connect(track.InputBegan,function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
   self.drag={input=input,channel=channel}; self:slide(channel,input.Position.X)
  end
 end)
end

function Audio:setOpen(open)
 if self.destroyed then return end
 open=open==true
 -- В прогулке список игроков Roblox перекрывает правый верхний угол.
 -- На время окна прячем его, затем возвращаем прежнее состояние.
 if open and not self.panel.Visible then
  local ok,enabled=pcall(function() return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) end)
  if ok then
   self.playerListBefore=enabled
   pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false) end)
  end
 elseif not open and self.playerListBefore~=nil then
  local enabled=self.playerListBefore; self.playerListBefore=nil
  pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,enabled) end)
 end
 self.panel.Visible=open; self.shade.Visible=open; self.drag=nil
 if self.view then
  self.view.audioSettingsOpen=self.panel.Visible
  if self.panel.Visible and self.view.drag then self.view:endDrag(true) end
  -- Кухня пересчитывает доступность управления по всем верхним окнам:
  -- закрытие звука не должно разблокировать всё ещё открытый дневник.
  if self.view.onOverlayChanged then self.view.onOverlayChanged() end
 end
 self.gui:SetAttribute("SettingsOpen",self.panel.Visible)
end
function Audio:slide(channel,x)
 local track=self.rows[channel].track
 if track.AbsoluteSize.X>0 then self:setVolume(channel,(x-track.AbsolutePosition.X)/track.AbsoluteSize.X) end
end
function Audio:renderVolume(channel)
 local volume=self.volumes[channel]; local row=self.rows[channel]
 row.value.Text=tostring(math.floor(volume*100+.5)).."%"
 row.fill.Size=UDim2.fromScale(volume,1); row.thumb.Position=UDim2.fromScale(volume,.5)
 self.gui:SetAttribute(channel.."Volume",volume)
 self.toggle.Text=if self.volumes.music==0 and self.volumes.effects==0 then "♪×" else "♪"
end
function Audio:setVolume(channel,value)
 if self.destroyed or not self.groups[channel] or type(value)~="number" or value~=value then return end
 local volume=math.floor(math.clamp(value,0,1)*100+.5)/100
 self.volumes[channel]=volume; self.groups[channel].Volume=volume; self:renderVolume(channel)
 if channel=="effects" and volume==0 then
  for name,sound in self.sounds do sound:Stop(); self.tokens[name]=(self.tokens[name] or 0)+1 end
 elseif channel=="music" then self:startMusic() end
end
function Audio:startMusic()
 if not self.destroyed and self.volumes.music>0 and self.music.IsLoaded and not self.music.IsPlaying then self.music:Play() end
end

function Audio:bindButton(object)
 if self.destroyed or not object:IsA("GuiButton") or self.buttons[object] then return end
 local screen=object:FindFirstAncestorWhichIsA("ScreenGui")
 if not screen or not ({InfiniteChocolate=true,ChocolateJournal=true,KitchenExperiment=true})[screen.Name] then return end
 local connections={}; self.buttons[object]=connections
 connections[1]=object.Activated:Connect(function() self:play("ui") end)
 connections[2]=object.Destroying:Connect(function()
  for _,connection in connections do connection:Disconnect() end; self.buttons[object]=nil
 end)
end
function Audio:play(name)
 if self.destroyed or self.volumes.effects==0 then return false end
 local sound=self.sounds[name]; local spec=Config.Audio.effects[name]
 if not sound or not sound.IsLoaded then return false end
 local now=os.clock()
 if self.last[name] and now-self.last[name]<(spec.cooldown or .08) then return false end
 self.last[name]=now; self.tokens[name]=(self.tokens[name] or 0)+1; local token=self.tokens[name]
 sound:Stop(); sound.TimePosition=0; sound:Play()
 if spec.duration then task.delay(spec.duration,function()
  if not self.destroyed and self.tokens[name]==token then sound:Stop() end
 end) end
 return true
end
function Audio:stopMotion()
 self.tokens.slide=(self.tokens.slide or 0)+1
 if self.sounds.slide then self.sounds.slide:Stop() end
end
function Audio:update(state)
 if self.destroyed or not state or not state.ready then return end
 -- Только ответ сервера подтверждает награду; пассивные снимки молчат.
 if type(state.reward)=="number" and state.reward>0 and state.reward<math.huge then self:play("reward") end
 local key=state.notice and state.notice.key
 if key=="Upgrade purchased" or key=="Purchased {count} upgrades" then self:play("purchase")
 elseif key=="New workshop! +{stars} cocoa stars" then self:play("prestige")
 elseif key=="Cannot purchase: check your balance and upgrade level" then self:play("denied") end
end
function Audio:destroy()
 if self.destroyed then return end
 self:setOpen(false); self.destroyed=true
 for _,connection in self.connections do connection:Disconnect() end
 for _,connections in self.buttons do for _,connection in connections do connection:Disconnect() end end
 self.buttons={}; self.music:Stop(); self.folder:Destroy(); self.gui:Destroy()
end
return Audio
