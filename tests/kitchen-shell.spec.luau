-- Стыки ограждений не должны оставлять щели или совпадающие лицевые плоскости.
local R=require('@lune/roblox'); local luau=require('@lune/luau'); local fs=require('@lune/fs')
return function(h)
 h.test('стены кухни имеют толщину и сходятся в задних углах',function()
  -- Lune не реализует Model:GetPivot; проверяем локальную геометрию до переноса.
  local source=fs.readFile('src/client/KitchenShell.luau'):gsub('world:PivotTo%([^\n]+','')
  local Shell=luau.load(source,{environment={game={GetService=function() return {WaitForChild=function(self) return self end} end},require=function() return require("../src/shared/KitchenStructure") end,Instance=R.Instance,Vector3=R.Vector3,CFrame=R.CFrame,Color3=R.Color3,Enum=R.Enum},injectGlobals=true})()
  local model=Shell.new(R.Instance.new('Folder'),R.Vector3.zero)
  local back,left,right=model.BackWall,model.LeftWall,model.RightWall
  assert(back.Size.Z>=.5 and left.Size.X>=.5 and right.Size.X>=.5)
  assert(math.abs(back.CFrame.Position.X-back.Size.X/2-(left.CFrame.Position.X+left.Size.X/2))<.0001)
  assert(math.abs(back.CFrame.Position.X+back.Size.X/2-(right.CFrame.Position.X-right.Size.X/2))<.0001)
  assert(math.abs(back.CFrame.Position.Z-back.Size.Z/2-(left.CFrame.Position.Z-left.Size.Z/2))<.0001)
  assert(math.abs(back.CFrame.Position.Y+back.Size.Y/2-(left.CFrame.Position.Y+left.Size.Y/2))<.0001)
  assert(math.abs(model.Floor.CFrame.Position.Z+model.Floor.Size.Z/2-17)<.0001)
  local floor,base=model.Floor,model.Foundation
  -- CFrame/Size движка используют float32.
  local function near(a,b) assert(math.abs(a-b)<.0001) end
  local function lo(p,axis) return p.CFrame.Position[axis]-p.Size[axis]/2 end
  local function hi(p,axis) return p.CFrame.Position[axis]+p.Size[axis]/2 end
  near(lo(floor,'X'),hi(left,'X'))
  near(hi(floor,'X'),lo(right,'X'))
  near(lo(floor,'Z'),hi(back,'Z'))
  for _,p in {floor,left,right,back} do near(lo(p,'Y'),hi(base,'Y')) end
  near(hi(floor,'Y'),-.1)

 end)
end
