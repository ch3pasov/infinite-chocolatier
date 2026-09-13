--!nostrict
-- Исполняем настоящий перенос UI между модальным и закреплённым магазином.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local R = require("@lune/roblox")
local Config = require("../src/shared/Config")
local Layout = require("../src/client/Layout")
local modules = { Config = Config, Layout = Layout, Theme = {} }
local Atelier = luau.load(fs.readFile("src/client/Atelier.luau"), { environment = {
	game = { GetService = function() return { WaitForChild = function() return { Config = "Config" } end } end },
	script = { Parent = { Theme = "Theme", Layout = "Layout" } },
	require = function(name) return modules[name] end,
	Vector2 = R.Vector2, UDim2 = R.UDim2,
}, injectGlobals = true })()

return function(h)
	h.test("магазин закрепляется сбоку без блокировки игры и возвращается в модальный режим", function()
		local root = R.Instance.new("Frame")
		local function make(class)
			local v = R.Instance.new(class or "Frame"); v.Parent = root; return v
		end
		local status = make("TextLabel")
		R.Instance.new("UITextSizeConstraint").Parent = status
		local counter = make("TextLabel")
		local ui = setmetatable({
			view = { root = root, counter = counter, status = status, cutProgress = 95 },
			state = { ready = true }, sidebar = make(), metrics = make("TextLabel"),
			open = make("TextButton"), close = make("TextButton"), overlay = make(), panel = make(),
			panelBounds = make("UISizeConstraint"), title = make("TextLabel"), update = function() end,
		}, Atelier)
		for _, size in { R.Vector2.new(390, 844), R.Vector2.new(1440, 900), R.Vector2.new(844, 390), R.Vector2.new(390, 844) } do
			root.AbsoluteSize = size
			ui:fit()
			local mode = Layout.presentation(size.X, size.Y, Config.Board.viewportPadding)
			h.equals(ui.view.inputBlocked, false)
			h.equals(ui.open.Visible, not mode.docked)
			h.equals(ui.overlay.Visible, mode.docked)
			h.equals(counter.Parent, if mode.landscape then ui.sidebar else root)
			h.equals(status.Parent, counter.Parent)
			h.equals(ui.view.cutProgress, 95)
			if mode.docked then
				h.equals(ui.overlay.Position.X.Offset, size.X - mode.right)
				h.equals(ui.close.Visible, false)
			end
		end
		root:Destroy()
	end)
end
