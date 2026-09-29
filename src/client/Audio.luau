--!nonstrict
-- Звуки принадлежат одной клиентской сцене: стажёры и серверные тики
-- не создают хор повторных наград, а удаление GUI освобождает весь пул.
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config)
local Theme = require(script.Parent.Theme)

local Audio = {}
Audio.__index = Audio

function Audio.new(gui)
 local self = setmetatable({enabled=true, sounds={}, last={}, tokens={}, buttons={}, connections={}, destroyed=false}, Audio)
 self.folder=Instance.new("Folder"); self.folder.Name="ChocolateAudio"; self.folder.Parent=SoundService
 self.group=Instance.new("SoundGroup"); self.group.Name="ChocolateMix"; self.group.Volume=1; self.group.Parent=self.folder
 local preload={}
 for name,spec in Config.Audio.effects do
  local sound=Instance.new("Sound"); sound.Name=name; sound.SoundId=spec.id
  sound.Volume=spec.volume; sound.PlaybackSpeed=spec.speed or 1; sound.SoundGroup=self.group
  sound.Parent=self.folder; self.sounds[name]=sound; table.insert(preload,sound)
 end
 -- Загрузка не задерживает профиль или первый жест. Поздний звук не
 -- догоняет действие: пока файл не готов, пропускаем только аудио.
 task.spawn(function()
  if self.destroyed then return end
  pcall(function() ContentProvider:PreloadAsync(preload) end)
 end)
 local controls=Instance.new("ScreenGui"); controls.Name="ChocolateAudioControls"
 controls.ResetOnSpawn=false; controls.IgnoreGuiInset=true; controls.DisplayOrder=20; controls.Parent=gui.Parent
 self.gui=controls
 local b=Instance.new("TextButton"); b.Name="SoundToggle"; b.AnchorPoint=Vector2.new(1,0)
 b.Position=UDim2.new(1,-12,0,16); b.Size=UDim2.fromOffset(44,36)
 b.Text="♪"; b.Font=Enum.Font.GothamBold; b.TextSize=23; b.AutoLocalize=false
 b.BackgroundColor3=Theme.panel; b.TextColor3=Theme.accent; b.BorderSizePixel=0; b.Parent=controls
 local corner=Instance.new("UICorner"); corner.CornerRadius=UDim.new(0,10); corner.Parent=b
 self.toggle=b; b:SetAttribute("SoundEnabled",true)
 table.insert(self.connections,b.Activated:Connect(function() self:setEnabled(not self.enabled) end))
 local playerGui=gui.Parent
 for _,object in playerGui:GetDescendants() do self:bindButton(object) end
 table.insert(self.connections,playerGui.DescendantAdded:Connect(function(object) self:bindButton(object) end))
 table.insert(self.connections,UserInputService.WindowFocusReleased:Connect(function() self:stopMotion() end))
 table.insert(self.connections,GuiService.MenuOpened:Connect(function() self:stopMotion() end))
 table.insert(self.connections,gui.Destroying:Connect(function() self:destroy() end))
 return self
end

function Audio:bindButton(object)
 if self.destroyed or not object:IsA("GuiButton") or self.buttons[object] then return end
 local screen=object:FindFirstAncestorWhichIsA("ScreenGui")
 if not screen or not ({InfiniteChocolate=true,ChocolateJournal=true,KitchenExperiment=true})[screen.Name] then return end
 local connections={}
 self.buttons[object]=connections
 connections[1]=object.Activated:Connect(function() self:play("ui") end)
 connections[2]=object.Destroying:Connect(function()
  for _,connection in connections do connection:Disconnect() end
  self.buttons[object]=nil
 end)
end

function Audio:play(name)
 if self.destroyed or not self.enabled then return false end
 local sound=self.sounds[name]; local spec=Config.Audio.effects[name]
 if not sound or not sound.IsLoaded then return false end
 local now=os.clock()
 if self.last[name] and now-self.last[name]<(spec.cooldown or 0.08) then return false end
 self.last[name]=now; self.tokens[name]=(self.tokens[name] or 0)+1
 local token=self.tokens[name]
 sound:Stop(); sound.TimePosition=0; sound:Play()
 if spec.duration then
  task.delay(spec.duration,function()
   if not self.destroyed and self.tokens[name]==token then sound:Stop() end
  end)
 end
 return true
end

function Audio:stopMotion()
 for _,name in {"cutMotion","slide"} do
  self.tokens[name]=(self.tokens[name] or 0)+1
  local sound=self.sounds[name]; if sound then sound:Stop() end
 end
end

function Audio:setEnabled(enabled)
 if self.destroyed then return end
 self.enabled=enabled==true; self.group.Volume=if self.enabled then 1 else 0
 self.toggle.Text=if self.enabled then "♪" else "♪×"
 self.toggle.TextColor3=if self.enabled then Theme.accent else Theme.muted
 self.toggle:SetAttribute("SoundEnabled",self.enabled)
 if not self.enabled then
  for _,sound in self.sounds do sound:Stop() end
  for name in self.tokens do self.tokens[name]+=1 end
 else self:play("ui") end
end

function Audio:update(state)
 if self.destroyed or not state or not state.ready then return end
 -- Подтверждение покупки и награда приходят только в ответе сервера,
 -- а не выводятся из меняющегося кошелька или повторяемого lastOrder.
 if type(state.reward)=="number" and state.reward>0 and state.reward<math.huge then self:play("reward") end
 local key=state.notice and state.notice.key
 if key=="Upgrade purchased" or key=="Purchased {count} upgrades" then self:play("purchase")
 elseif key=="New workshop! +{stars} cocoa stars" then self:play("prestige")
 elseif key=="Cannot purchase: check your balance and upgrade level" then self:play("denied") end
end

function Audio:destroy()
 if self.destroyed then return end
 self.destroyed=true
 for _,connection in self.connections do connection:Disconnect() end
 for _,connections in self.buttons do for _,connection in connections do connection:Disconnect() end end
 self.buttons={}; self.folder:Destroy(); self.gui:Destroy()
end

return Audio
