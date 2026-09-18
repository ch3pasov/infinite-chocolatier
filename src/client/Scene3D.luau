--!nonstrict
-- Объёмная рабочая станция читает состояние Game. Экономика, жесты и
-- геометрия фокуса остаются прежними; рендер можно отключить одним флагом.
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Geom = require(Shared.Geom)
local Layout = require(script.Parent.Layout)
local Projection = require(script.Parent.Projection3D)
local Solid = require(script.Parent.SolidGeometry)
local Motion = require(script.Parent.Motion3D)
local WorldStage = require(script.Parent.WorldStage)
local Scene = {}
Scene.__index = Scene
local settings = Config.Scene3D
local unit = settings.unitsPerPixel
local renderScale = settings.renderScale
local function renderFrame(frame)
	return frame.Rotation + frame.Position*renderScale
end
local function project(camera,size,fov,point)
	return Projection.project(camera,size,fov,point*renderScale)
end
local function color(name) return Color3.fromRGB(table.unpack(settings.colors[name])) end

local function part(parent, name, size, frame, tint, kind)
	-- Движок округляет меньшие детали до 0,001 stud. Отбрасываем только
	-- субпиксельные клинья, иначе округление создаёт лишние перекрытия.
	if kind=='WedgePart' and math.min(size.X,size.Y,size.Z)*renderScale<0.001 then return nil end
	local p = Instance.new(kind or "Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size*renderScale, renderFrame(frame), tint
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end
local function model(name)
	local m = Instance.new("Model")
	m.Name, m.WorldPivot = name, CFrame.identity
	return m
end
local function prism(parent, name, polygon, bottom, top, tint)
	for _, spec in Solid.prism(polygon, bottom, top, unit) do
		part(parent,name,spec.size,spec.frame,tint,spec.kind or "WedgePart")
	end
end
local function chamfer(parent, outer, inner, bottom, top, tint, clipper)
	-- Наклонная грань ловит свет иначе, чем плоское лицо шоколадки.
	-- Клиппинг выполняется в плоскости каждой грани с восстановлением высоты.
	for i,a in outer do
		local j=i%#outer+1
		local b,c,d=outer[j],inner[j],inner[i]
		local edge=b-a
		local inward=d-a
		local denom=Geom.cross(edge,inward)
		if math.abs(denom)>1e-8 then
			local polygon=clipper({a,b,c,d})
			local function world(p)
				local t=Geom.cross(edge,p-a)/denom
				return Vector3.new(p.X*unit,bottom+(top-bottom)*t,p.Y*unit)
			end
			for k=2,#polygon-1 do
				for _, w in Solid.wedges(world(polygon[1]),world(polygon[k]),world(polygon[k+1]),0.012) do
					part(parent,"SlopedBevel",w.size,w.frame,tint,"WedgePart")
				end
			end
		end
	end
end
local function present(m, parent, visible)
	-- Геометрия живёт весь раунд: переходы меняют видимость, а не создают
	-- тысячи деталей повторно.
	if m.Parent ~= parent then m.Parent = parent end
	if m:GetAttribute("Shown") == visible then return end
	m:SetAttribute("Shown",visible)
	for _,p in m:GetDescendants() do
		if p:IsA("BasePart") then p.Transparency=if visible then (p:GetAttribute("RestTransparency") or 0) else 1 end
	end
end

function Scene:clip(polygon, spec)
	if not spec then return polygon end
	local b = spec.bounds
	for _, edge in {
		{Vector2.new(b[1]*self.view.tileWidth,10000), Vector2.new(b[1]*self.view.tileWidth,-10000)},
		{Vector2.new(b[3]*self.view.tileWidth,-10000), Vector2.new(b[3]*self.view.tileWidth,10000)},
		{Vector2.new(-10000,b[2]*self.view.tileHeight), Vector2.new(10000,b[2]*self.view.tileHeight)},
		{Vector2.new(10000,b[4]*self.view.tileHeight), Vector2.new(-10000,b[4]*self.view.tileHeight)},
	} do
		polygon = Geom.clipPolygon(polygon,{a=edge[1],b=edge[2]},false)
	end
	if spec.clip ~= "rect" then
		local shift = if spec.clip == "upper" then Vector2.new(0, Config.Trick.opticalStretchRows*self.view.tileHeight) else Vector2.zero
		polygon = Geom.clipPolygon(polygon,{a=self.view.diagonal.a+shift,b=self.view.diagonal.b+shift},spec.clip=="upper")
	end
	return polygon
end

function Scene:chocolate(name, spec)
	local m = model(name)
	local v = self.view
	local shadow=self:clip(Solid.outline(0,0,v.boardWidth,v.boardHeight,0),spec)
	for i,p in shadow do shadow[i]=p+Vector2.new(4,6) end
	-- Непрозрачный смешанный цвет вместо сортировки наложенных прозрачных
	-- треугольников: такая контактная тень не вспыхивает при перемещении.
	prism(m,"ContactShadow",shadow,-0.025,-0.015,color("wood"):Lerp(Color3.fromRGB(51,30,18),0.38))
	prism(m,"ChocolateBody",self:clip(Solid.outline(0,0,v.boardWidth,v.boardHeight,0),spec),0,settings.baseHeight,color("body"))
	local gap = math.max(3,math.floor(math.min(v.tileWidth,v.tileHeight)*Config.Trick.tileGapRatio+0.5))
	local bevel = math.max(3,math.floor(math.min(v.tileWidth,v.tileHeight)*Config.Trick.bevelRatio+0.5))
	for row=0,v.recipe.rows-1 do
		for col=0,v.recipe.cols-1 do
			-- Все части вырезаются из одинаковых профилей. Никакой новой полосы
			-- в конце перестановки не появляется: кромка выдавлена заранее.
			for _, layer in {
				{gap,gap,settings.baseHeight,0.29,"bevel",5},
				{gap+bevel,gap+bevel,0.29,0.40,"face",4},
				{gap+bevel*2,gap+bevel*2.5,0.40,settings.surfaceHeight,"relief",3},
			} do
				local polygon = Solid.outline(col*v.tileWidth+layer[1],row*v.tileHeight+layer[2],
					v.tileWidth-2*layer[1],v.tileHeight-2*layer[2],layer[6])
				prism(m,layer[5],self:clip(polygon,spec),layer[3],layer[4],color(layer[5]))
			end
			local outer=Solid.outline(col*v.tileWidth+gap,row*v.tileHeight+gap,v.tileWidth-2*gap,v.tileHeight-2*gap,5)
			local inner=Solid.outline(col*v.tileWidth+gap+bevel,row*v.tileHeight+gap+bevel,v.tileWidth-2*(gap+bevel),v.tileHeight-2*(gap+bevel),4)
			chamfer(m,outer,inner,0.29,0.40,color("bevel"),function(p) return self:clip(p,spec) end)
		end
	end
	for _,p in m:GetChildren() do p:SetAttribute("RestTransparency",p.Transparency) end
	return m
end

function Scene:makeTable()
	if self.tableModel then self.tableModel:Destroy() end
	self.tableModel=Instance.new('Model')
	self.tableModel.Parent=self.world
	local b = self.view.layoutBounds
	local x,z = (b.minX+b.maxX)*unit/2,(b.minY+b.maxY)*unit/2
	local w,h = (b.maxX-b.minX)*unit+1.5,(b.maxY-b.minY)*unit+1.5
	part(self.tableModel,"SageWorktop",Vector3.new(180,0.4,180),CFrame.new(x,-0.85,z),color("table"))
	prism(self.tableModel,"BoardEdge",Solid.outline((x-w/2)/unit,(z-h/2)/unit,w/unit,h/unit,18),-0.52,-0.12,color("woodEdge"))
	prism(self.tableModel,"MapleBoard",Solid.outline((x-w/2)/unit,(z-h/2)/unit,w/unit,h/unit,18),-0.12,-0.035,color("wood"))
	-- Тонкие волокна древесины лежат вне шоколадки и не напоминают разрезы.
	for i=1,12 do
		local px = x-w/2+0.2+i*(w-0.4)/13
		part(self.tableModel,"WoodGrain",Vector3.new(0.012,0.004,h-0.35),CFrame.new(px,-0.026,z),color("wood"):Lerp(color("grain"),0.42))
	end
end

-- Все части находятся в одном мире и перемещаются целиком, без подмены камер.
function Scene:layer(name, _z)
	local world=Instance.new('Model')
	world.Name=name
	world.Parent=self.world
	return {world=world}
end

function Scene:attachPiece(name,m)
	-- В настоящем мире тень отбрасывает сама геометрия. Копии плоских теней
	-- пересекались бы при соединении и давали мерцание глубины.
	for _,p in m:GetChildren() do
		if p.Name=='ContactShadow' then p:Destroy() end
	end
	m.Parent=self.world
	self.layers[name]={model=m}
end

function Scene:posePiece(name,visible,offset,fade)
	local layer=self.layers[name]
	local m=layer.model
	present(m,self.world,visible)
	local position=offset*renderScale
	if layer.position~=position then m:PivotTo(CFrame.new(position)); layer.position=position end
	fade=fade or 0
	if layer.fade~=fade then
		layer.fade=fade
		for _,p in m:GetDescendants() do
			if p:IsA('BasePart') then
				local rest=p:GetAttribute('RestTransparency') or 0
				p.Transparency=if visible then rest+(1-rest)*fade else 1
			end
		end
	end
end

function Scene.new(view)
	local self = setmetatable({view=view,pieces={},layers={},effects={},hints={},time=0,lastCrumb=-1},Scene)
	self.stage=WorldStage.new()
	local frame=Instance.new('Frame')
	frame.Name='ChocolateWorldInput'
	frame.BackgroundTransparency=1
	frame.Size=UDim2.fromScale(1,1)
	frame.Active=false
	frame.Parent=view.root
	self.frame=frame
	view.root.BackgroundTransparency=1
	self.world=self.stage:createWorld('ChocolateWorkstation')
	self.camera=self.stage:createCamera('ChocolateCamera',settings.fieldOfView)
	self.stage:activate(self.world,self.camera)
	self:makeTable()
	self.intact = self:chocolate("WholeBar")
	self:attachPiece('WholeBar',self.intact)
	for _,name in Config.Trick.pieceOrder do
		self.pieces[name]=self:chocolate(name,Config.Trick.pieces[name])
		self:attachPiece(name,self.pieces[name])
	end
	self.overlay=self:layer('KnifeAndGuides',8)
	self.knife = model("ChefKnife")
	-- Лезвие имеет настоящий острый носик, обух и отдельную рукоять.
	prism(self.knife,"SteelBlade",{Vector2.new(0,-43),Vector2.new(13,-18),Vector2.new(13,27),Vector2.new(-7,27),Vector2.new(-7,-22)},0,0.055,color("knife"))
	part(self.knife,"BladeSpine",Vector3.new(0.04,0.055,1),CFrame.new(-0.14,0.065,-0.05),Color3.fromRGB(240,246,235))
	part(self.knife,"Handle",Vector3.new(0.27,0.20,0.77),CFrame.new(0.04,0.12,0.92),color("handle"))
	for _, z in {0.70,1.12} do
		local rivet=part(self.knife,"Rivet",Vector3.new(0.06,0.025,0.06),CFrame.new(0.04,0.23,z),color("knife"))
		rivet.Shape=Enum.PartType.Ball
	end
	self.knife.Parent = self.overlay.world
	view.board.Visible = false
	view.scene3D = self
	self:fit()
	self:step(0)
	self.resize = view.root:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() self:fit() end)
	self.render = RunService.RenderStepped:Connect(function(dt) self:step(dt) end)
	self.cleanup = view.gui.Destroying:Connect(function() self:destroy() end)
	return self
end

function Scene:fit()
	local size = self.view.root.AbsoluteSize
	if size.X < 1 or size.Y < 1 then return end
	local mode = Layout.presentation(size.X,size.Y,Config.Board.viewportPadding)
	local top = if mode.landscape then 12 else 174
	local bottom = if mode.landscape then 12 else 96
	local left = if mode.landscape then mode.left+12 else 8
	local right = if mode.landscape then mode.right+12 else 8
	-- Основная камера занимает весь экран. Симметричный запас оставляет
	-- шоколадку между панелями, а ввод использует ту же полную проекцию.
	local area = Vector2.new(math.max(60,size.X-2*math.max(left,right)),math.max(60,size.Y-2*math.max(top,bottom)))
	self.size=size
	self.camera.FieldOfView=Projection.expandedFov(settings.fieldOfView,area.Y,size.Y)
	local b=self.view.layoutBounds
	self.camera.CFrame = renderFrame(Projection.fit(area,{minX=b.minX-24,maxX=b.maxX+24,minY=b.minY-24,maxY=b.maxY+32},settings))
	self.camera.Focus = CFrame.new(Vector3.new((b.minX+b.maxX)*unit/2,settings.surfaceHeight,(b.minY+b.maxY)*unit/2)*renderScale)
	-- Консервативный масштаб сохраняет удобные допуски пальца при перспективе.
	local center = Vector3.new(self.view.boardWidth*unit/2,settings.surfaceHeight,self.view.boardHeight*unit/2)
	local p = project(self.camera.CFrame,size,self.camera.FieldOfView,center)
	local px = project(self.camera.CFrame,size,self.camera.FieldOfView,center+Vector3.new(unit,0,0))
	local py = project(self.camera.CFrame,size,self.camera.FieldOfView,center+Vector3.new(0,0,unit))
	self.view.boardScale.Scale = math.min((px-p).Magnitude,(py-p).Magnitude)
end

function Scene:screenToBoard(screen)
	local p = Vector2.new(screen.X,screen.Y)-self.frame.AbsolutePosition
	if not self.size then return Vector2.new(-100000,-100000) end
	local hit = Projection.unproject(self.camera.CFrame,self.size,self.camera.FieldOfView,p,settings.surfaceHeight*renderScale)
	return if hit then Vector2.new(hit.X/(unit*renderScale),hit.Z/(unit*renderScale)) else Vector2.new(-100000,-100000)
end
function Scene:boardToScreen(p)
	return self.frame.AbsolutePosition-self.view.root.AbsolutePosition+project(self.camera.CFrame,self.size,self.camera.FieldOfView,Vector3.new(p.X*unit,settings.surfaceHeight,p.Y*unit))
end

-- След ножа лежит на том же профиле, из которого построены дольки.
-- Высота меняется на фасках и в канавках, поэтому проекция не прямая.
function Scene:surfaceAt(p)
	local v=self.view
	local gap=math.max(3,math.floor(math.min(v.tileWidth,v.tileHeight)*Config.Trick.tileGapRatio+0.5))
	local bevel=math.max(3,math.floor(math.min(v.tileWidth,v.tileHeight)*Config.Trick.bevelRatio+0.5))
	local col,row=math.floor(p.X/v.tileWidth),math.floor(p.Y/v.tileHeight)
	local function outline(dx,dy,corner)
		return Solid.outline(col*v.tileWidth+dx,row*v.tileHeight+dy,v.tileWidth-2*dx,v.tileHeight-2*dy,corner)
	end
	local function inside(poly)
		for i,a in poly do
			if Geom.cross(poly[i%#poly+1]-a,p-a)<-1e-7 then return false end
		end
		return true
	end
	local outer=outline(gap,gap,5)
	if not inside(outer) then return settings.baseHeight end
	local inner=outline(gap+bevel,gap+bevel,4)
	if not inside(inner) then
		for i,a in outer do
			local j=i%#outer+1
			if inside({a,outer[j],inner[j],inner[i]}) then
				local edge=outer[j]-a
				local t=Geom.cross(edge,p-a)/Geom.cross(edge,inner[i]-a)
				return 0.29+0.11*math.clamp(t,0,1)
			end
		end
		return 0.29
	end
	if inside(outline(gap+bevel*2,gap+bevel*2.5,3)) then return settings.surfaceHeight end
	return 0.40
end

function Scene:reliefSeam(gui)
	local m=model('ReliefSeam')
	m.Parent=self.overlay.world
	local size=Vector2.new(gui.Size.X.Offset,gui.Size.Y.Offset)
	local center=Vector2.new(gui.Position.X.Offset,gui.Position.Y.Offset)+size*(Vector2.new(0.5,0.5)-gui.AnchorPoint)
	local angle=math.rad(gui.Rotation)
	local delta=Vector2.new(math.cos(angle),math.sin(angle))*size.X
	local start=center-delta/2
	local count=math.max(1,math.ceil(size.X))
	-- Одна тонкая кромка вместо пары широких полос, парящих над плиткой.
	local function point(t)
		local p=start+delta*t
		return Vector3.new(p.X*unit,self:surfaceAt(p)+0.008,p.Y*unit)
	end
	local a=point(0)
	for i=1,count do
		local b=point(i/count)
		local line=part(m,'CutEdge',Vector3.new(0.012,0.012,(b-a).Magnitude),CFrame.lookAt((a+b)/2,b),gui.BackgroundColor3)
		line.Transparency=gui.BackgroundTransparency
		line:SetAttribute("RestTransparency",line.Transparency)
		a=b
	end
	return m
end

function Scene:syncHints()
	for _, layer in {self.view.hintLayer,self.view.progressLayer,self.view.seamLayer} do
		for _, gui in layer:GetChildren() do
			if gui:IsA("Frame") then
				local p = self.hints[gui]
				if layer==self.view.seamLayer then
					-- Тёмная подложка 2D не нужна: глубину уже даёт рельеф.
					if gui.ZIndex==411 then
						if not p then p=self:reliefSeam(gui); self.hints[gui]=p end
						present(p,self.overlay.world,gui.Visible)
					end
					continue
				end
				if not p then
					p=part(self.overlay.world,"Guide",Vector3.one,CFrame.identity,gui.BackgroundColor3)
					self.hints[gui]=p
				end
				local size = Vector2.new(gui.Size.X.Offset,gui.Size.Y.Offset)
				local center = Vector2.new(gui.Position.X.Offset,gui.Position.Y.Offset)+size*(Vector2.new(0.5,0.5)-gui.AnchorPoint)
				p.Size = Vector3.new(math.max(0.015,size.X*unit),0.018,math.max(0.015,size.Y*unit))*renderScale
				-- Тёмная линия и её тонкая кромка раньше лежали в одной
				-- плоскости. UI ZIndex сам по себе в 3D глубину не разделяет.
				local height=if layer==self.view.seamLayer then 0.025+math.clamp(gui.ZIndex-410,0,1)*0.012
					elseif layer==self.view.progressLayer then 0.055 else 0.08
				p.CFrame = renderFrame(CFrame.new(center.X*unit,settings.surfaceHeight+height,center.Y*unit)*CFrame.Angles(0,-math.rad(gui.Rotation),0))
				p.Color = gui.BackgroundColor3
				p.Transparency = if gui.Visible then gui.BackgroundTransparency else 1
				if gui.Name == "Start" then p.Shape=Enum.PartType.Ball; p.Size=Vector3.new(size.X*unit,0.07,size.Y*unit)*renderScale end
			end
		end
	end
	for gui,p in self.hints do
		if not gui.Parent then p:Destroy(); self.hints[gui]=nil end
	end
end

function Scene:burst(point, count, golden)
	for i=1,count do
		if #self.effects >= 48 then break end
		local angle = (i/count*2*math.pi)+self.time*4
		local size = if golden then 0.075 else 0.045+(i%3)*0.018
		local p=part(self.overlay.world,if golden then "JoinSpark" else "CocoaCrumb",Vector3.one*size,CFrame.new(point),if golden then Color3.fromRGB(255,206,91) else color("bevel"))
		if golden then p.Material=Enum.Material.Neon end
		table.insert(self.effects,{part=p,origin=point,velocity=Vector3.new(math.cos(angle)*1.2,1.3+i%3*0.2,math.sin(angle)*1.2),age=0,life=if golden then 0.6 else 0.45})
	end
end

function Scene:step(dt)
	if self.view.observingKitchen then return end
    -- Стандартный спавн Roblox возвращает камеру в Custom. В режиме нарезки
    -- восстанавливаем нашу проекцию после этого события, не отключая аватар.
    if self.camera.CameraType ~= Enum.CameraType.Scriptable then
        self.camera.CameraType = Enum.CameraType.Scriptable
        self:fit()
    end
	self.time += dt
	local v = self.view
	local intact = v.intactLayer.Visible
	self:posePiece('WholeBar',intact,Vector3.zero,0)
	for name,m in self.pieces do
		local p=v.pieces[name]
		local reward = name==Config.Trick.rewardPiece and (v.active=="done" or v.active=="collecting")
		local visible=p.motion.Visible and (not intact or reward)
		local fade=0
		local position = p.motion.Position
		local raw=Vector2.new(position.X.Offset-p.origin.X,position.Y.Offset-p.origin.Y)
		local offset=Motion.offset(name,raw,v.active,settings,v.recipe.slides,v.tileWidth,v.tileHeight)
		if reward and v.active=="collecting" then
			local elapsed=math.clamp((self.time-(self.collectStarted or self.time))/Config.Trick.collectionDuration,0,1)
			offset += Vector3.new(-elapsed*0.3,elapsed*0.8,0)
			fade=elapsed
		end
		self:posePiece(name,visible,offset,fade)
	end
	self:syncHints()
	if v.active=="cut" or v.active=="finishingCut" then
		local path=v.paths[v.cutIndex]
		local p=Geom.pointAt(path.geom,v.cutProgress)
		local direction=path.points[#path.points]-path.points[1]
		local target=Vector3.new(p.X*unit,settings.surfaceHeight+0.06,p.Y*unit)
		local cutting = v.drag and v.drag.kind=="cut" or v.active=="finishingCut"
		local lift=if cutting then 0 else 0.18+math.sin(self.time*2)*0.025
		self.knife:PivotTo(renderFrame(CFrame.lookAt(target+Vector3.new(0,lift,0),target+Vector3.new(direction.X, lift,direction.Y))*CFrame.new(0,0,0.86)*CFrame.Angles(0,0,math.rad(if cutting then -65 else -12))))
		present(self.knife,self.overlay.world,true)
		if cutting and math.abs(v.cutProgress-self.lastCrumb)>7 then self:burst(target,2,false); self.lastCrumb=v.cutProgress end
	else present(self.knife,self.overlay.world,false) end
	if self.previousActive~=v.active then
		if v.active=="collecting" then self.collectStarted=self.time end
		if v.active=="done" or (v.active=="assembleStrip" and self.previousActive~=nil) then
			for i=1,5 do
				local x=i*v.tileWidth-v.tileWidth/2
				local y=Geom.lineYAtX(v.diagonal,x)
				self:burst(Vector3.new(x*unit,settings.surfaceHeight+0.06,y*unit),3,true)
			end
		end
	end
	self.previousActive=v.active
	for i=#self.effects,1,-1 do
		local effect=self.effects[i]
		effect.age += dt
		if effect.age>=effect.life then effect.part:Destroy(); table.remove(self.effects,i)
		else
			local t=effect.age
			local at=effect.origin+effect.velocity*t+Vector3.new(0,-3*t*t,0)
			effect.part.CFrame=renderFrame(CFrame.new(at)*CFrame.Angles(t*5,t*3,t*6))
			effect.part.Transparency=t/effect.life
		end
	end
end

function Scene:destroy()
	if self.render then self.render:Disconnect() end
	if self.resize then self.resize:Disconnect() end
	if self.cleanup then self.cleanup:Disconnect() end
	for _, m in self.pieces do m:Destroy() end
	self.intact:Destroy()
	self.knife:Destroy()
	self.frame:Destroy()
	self.stage:destroy()
end
return Scene
