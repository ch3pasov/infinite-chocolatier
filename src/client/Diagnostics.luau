--!nonstrict
-- Только локальный инструмент владельца: ничего не отправляет на сервер
-- и не меняет профиль. Снимок фиксируется при открытии, чтобы его можно было
-- спокойно выделить даже при ежесекундных обновлениях дохода.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Report = require(Shared.DiagnosticReport)
local Theme = require(script.Parent.Theme)
local L = require(script.Parent.Localization)
local Diagnostics = {}
Diagnostics.__index = Diagnostics

local function round(object)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = object
end

local function label(parent, name, size, color)
	local object = Instance.new("TextLabel")
	object.Name = name; object.BackgroundTransparency = 1
	object.Font = Enum.Font.GothamMedium; object.TextSize = size
	object.TextColor3 = color; object.TextWrapped = true
	object.TextXAlignment = Enum.TextXAlignment.Left; object.Parent = parent
	return object
end

function Diagnostics.new(playerGui, view)
	local self = setmetatable({view = view, errors = {}}, Diagnostics)
	-- Проверка до создания GUI: чужим игрокам не нужны ни элементы, ни связи.
	if Players.LocalPlayer.UserId ~= Config.BalanceTesterUserId then return self end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeveloperDiagnostics"; gui.ResetOnSpawn = false
	gui.DisplayOrder = 100; gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui; self.gui = gui
	local badge = Instance.new("TextButton")
	badge.Name = "VersionBadge"; badge.AnchorPoint = Vector2.new(0, 1)
	badge.Position = UDim2.new(0, 8, 1, -6); badge.Size = UDim2.fromOffset(154, 28)
	badge.BackgroundColor3 = Theme.panel; badge.BackgroundTransparency = .15
	badge.BorderSizePixel = 0; badge.Font = Enum.Font.GothamMedium
	badge.TextSize = 12; badge.TextColor3 = Theme.muted; badge.Parent = gui
	round(badge); self.badge = badge
	local overlay = Instance.new("TextButton")
	overlay.Name = "ReportOverlay"; overlay.Size = UDim2.fromScale(1, 1)
	overlay.Text = ""; overlay.AutoButtonColor = false
	overlay.BackgroundColor3 = Theme.background; overlay.BackgroundTransparency = .18
	overlay.BorderSizePixel = 0; overlay.Visible = false; overlay.ZIndex = 2
	overlay.Parent = gui; self.overlay = overlay
	local panel = Instance.new("Frame")
	panel.Name = "Report"; panel.AnchorPoint = Vector2.new(.5, .5)
	panel.Position = UDim2.fromScale(.5, .5); panel.Size = UDim2.new(1, -24, 1, -24)
	panel.BackgroundColor3 = Theme.panel; panel.BorderSizePixel = 0; panel.Active = true
	panel.Parent = overlay; round(panel)
	local bounds = Instance.new("UISizeConstraint")
	bounds.MaxSize = Vector2.new(650, 550); bounds.Parent = panel
	local title = label(panel, "Title", 22, Theme.accent)
	title.Position = UDim2.fromOffset(16, 10); title.Size = UDim2.new(1, -78, 0, 36)
	L.set(title, "Bug report")
	local close = Instance.new("TextButton")
	close.Name = "Close"; close.Position = UDim2.new(1, -52, 0, 10)
	close.Size = UDim2.fromOffset(36, 36); close.Text = "×"; close.TextSize = 24
	close.Font = Enum.Font.GothamBold; close.BackgroundColor3 = Theme.accent
	close.TextColor3 = Theme.background; close.BorderSizePixel = 0; close.Parent = panel; round(close)
	local help = label(panel, "Help", 13, Theme.muted)
	help.Position = UDim2.fromOffset(16, 50); help.Size = UDim2.new(1, -32, 0, 52)
	L.set(help, "Select the report text and copy it into your message. A screenshot with the version badge also helps.")
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "ReportScroll"; scroll.BackgroundColor3 = Theme.background
	scroll.BorderSizePixel = 0; scroll.Position = UDim2.fromOffset(12, 108)
	scroll.Size = UDim2.new(1, -24, 1, -124); scroll.ScrollBarThickness = 4
	scroll.ScrollBarImageColor3 = Theme.accent
	scroll.CanvasSize = UDim2.fromOffset(0, 0); scroll.Parent = panel
	local body = Instance.new("TextBox")
	body.Name = "ReportText"; body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(10, 8); body.Size = UDim2.new(1, -24, 0, 0)
	body.Font = Enum.Font.Code
	body.TextSize = 13; body.TextColor3 = Theme.text; body.TextWrapped = true
	body.TextXAlignment = Enum.TextXAlignment.Left; body.TextYAlignment = Enum.TextYAlignment.Top
	body.ClearTextOnFocus = false; body.MultiLine = true; body.TextEditable = false
	body.AutoLocalize = false; body.Text = ""; body.Parent = scroll; self.body = body
	body.Focused:Connect(function()
		-- Стандартная обработка первого клика сама ставит курсор после Focused.
		task.defer(function()
			if gui.Parent and body:IsFocused() then body.CursorPosition = 1; body.SelectionStart = #body.Text + 1 end
		end)
	end)
	local function fitText()
		-- TextBox с AutomaticSize внутри ScrollingFrame ограничивался высотой
		-- родителя и прятал последние строки. Считаем полную высоту явно.
		local width = math.max(80, scroll.AbsoluteSize.X - 24)
		local height = TextService:GetTextSize(body.Text, body.TextSize, body.Font, Vector2.new(width, 100000)).Y + 12
		body.Size = UDim2.new(1, -24, 0, height)
		scroll.CanvasSize = UDim2.fromOffset(0, height + 16)
	end
	scroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitText)
	body:GetPropertyChangedSignal("Text"):Connect(fitText)
	badge.Activated:Connect(function() self:open() end)
	close.Activated:Connect(function() self:close() end)
	local escapeConnection = UserInputService.InputBegan:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Escape and overlay.Visible then self:close() end
	end)
	local errorConnection = game:GetService("ScriptContext").Error:Connect(function(message, trace, source)
		if not source or not source:IsDescendantOf(Players.LocalPlayer.PlayerScripts) then return end
		local entry = string.sub(message, 1, 300) .. " | " .. string.sub(trace, 1, 600)
		if self.errors[1] == entry then return end
		table.insert(self.errors, 1, entry)
		if #self.errors > 3 then table.remove(self.errors) end
	end)
	local ownerCleanup = view.gui.Destroying:Connect(function() gui:Destroy() end)
	gui.Destroying:Connect(function()
		escapeConnection:Disconnect(); errorConnection:Disconnect(); ownerCleanup:Disconnect()
		view.diagnosticsOpen = false
	end)
	self:refreshBadge()
	return self
end

function Diagnostics:refreshBadge()
	if not self.badge then return end
	self.badge.TextColor3 = if self.state and self.state.prestigeDisabled then Theme.accent else Theme.muted
	local version = if RunService:IsStudio() then "Studio" else "v" .. tostring(game.PlaceVersion)
	L.set(self.badge, "{version} · ★ {bonus} · report", {
		version = version, bonus = if not self.state then "?" else if self.state.prestigeDisabled then "OFF" else "ON",
	})
end

function Diagnostics:update(state)
	self.state = state; self.receivedAt = os.clock(); self:refreshBadge()
end

function Diagnostics:open()
	if not self.gui or self.view.diagnosticsOpen then return end
	local player = Players.LocalPlayer
	local friends = "?"
	local directory = workspace:FindFirstChild("KitchenIslands")
	for _, room in if directory then directory:GetChildren() else {} do
		if room:GetAttribute("OwnerId") == player.UserId and room:GetAttribute("CafeIndex") == 0 then
			friends = room:GetAttribute("FriendListStatus") or "loading"
		end
	end
	local actors = {}
	-- Обход только по запросу, а не на каждом кадре или сетевом обновлении.
	for _, model in workspace:GetDescendants() do
		if model:IsA("Model") and model:GetAttribute("ActorLoadState") then
			table.insert(actors, {assigned = model:GetAttribute("ActorAssignedUserId"),
				appearance = model:GetAttribute("ActorAppearanceUserId"),
				status = model:GetAttribute("ActorLoadState"), visible = model:GetAttribute("ActorVisible")})
		end
	end
	local camera = workspace.CurrentCamera
	local size = if camera then camera.ViewportSize else Vector2.zero
	self.body.Text = Report.build({
		version = game.PlaceVersion, studio = RunService:IsStudio(), server = game.JobId,
		utc = os.date("!%Y-%m-%dT%H:%M:%SZ"), screen = tostring(size.X) .. "x" .. tostring(size.Y),
		input = UserInputService:GetLastInputType().Name, locale = game:GetService("LocalizationService").RobloxLocaleId,
		mode = player:GetAttribute("KitchenMode"), phase = self.view.active, cut = self.view.cutIndex,
		progress = self.view.cutProgress, stateAge = if self.receivedAt then os.clock() - self.receivedAt else nil,
		state = self.state, friends = friends, actors = actors, errors = self.errors,
	})
	self.view:endDrag(true)
	self.view.diagnosticsOpen = true
	self.overlay.Visible = true
	if self.view.onOverlayChanged then self.view.onOverlayChanged() end
	self.body.Parent.CanvasPosition = Vector2.zero
end

function Diagnostics:close()
	if not self.gui or not self.view.diagnosticsOpen then return end
	self.body:ReleaseFocus()
	self.overlay.Visible = false
	self.view.diagnosticsOpen = false
	if self.view.onOverlayChanged then self.view.onOverlayChanged() end
end

return Diagnostics
