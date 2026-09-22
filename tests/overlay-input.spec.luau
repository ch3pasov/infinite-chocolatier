--!nonstrict
-- Настоящие обработчики отчёта, дневника и кухни делят один контроллер.
-- Проверяем порядок закрытия окон без зависимости от кадров и ввода мыши.
local fs=require('@lune/fs'); local luau=require('@lune/luau'); local R=require('@lune/roblox')
local Report=require('../src/shared/DiagnosticReport')
local stub=setmetatable({},{__index=function(_,key) return key end})
local function fixture()
 local player={UserId=123,GetAttribute=function() return 'walk' end}
 local world={CurrentCamera={ViewportSize=R.Vector2.new(1280,720)},
  FindFirstChild=function() return nil end,GetDescendants=function() return {} end}
 local services={Players={LocalPlayer=player},RunService={IsStudio=function() return false end},
  UserInputService={GetLastInputType=function() return {Name='Keyboard'} end},
  ReplicatedStorage={WaitForChild=function() return stub end},LocalizationService={RobloxLocaleId='en-us'}}
 local function load(name)
  return luau.load(fs.readFile('src/client/'..name..'.luau'),{environment={
   game={PlaceVersion=1,JobId='test',GetService=function(_,key) return services[key] or {} end},
   workspace=world,script={Parent=stub},Color3=R.Color3,Vector2=R.Vector2,
   require=function(key) return if key=='DiagnosticReport' then Report else {} end,
  },injectGlobals=true})()
 end
 local Kitchen,Diagnostics,Journal=load('Kitchen'),load('Diagnostics'),load('Journal')
 local cancelled,resets,enabled,changes=0,0,true,0
 local view={active='cut',cutIndex=2,cutProgress=55,endDrag=function(_,cancel)
  assert(cancel); cancelled+=1
 end}
 local journal=setmetatable({view=view,state={ready=true},overlay={}},Journal)
 local kitchen=setmetatable({opened=true,view=view,state={ready=true,levels={kitchen=1}},atelier={journal=journal},
  controls={Enable=function() enabled=true; changes+=1 end,Disable=function() enabled=false; changes+=1 end},
  walkController={resetInput=function() resets+=1 end},prompts={{Enabled=true}},
  online={scan=0,blockPrompts=function(self) self.blocked=true end}},{__index=Kitchen})
 kitchen:bindOverlays()
 local diagnostics=setmetatable({view=view,gui={},overlay={},body={Parent={},ReleaseFocus=function() end}},Diagnostics)
 return kitchen,diagnostics,journal,view,function() return enabled,changes,cancelled,resets end
end
return function(h)
 h.test('админский отчёт останавливает прогулку и отклоняет действия под окном',function()
  local k,d,j,v,status=fixture()
  d:open(); local enabled,changes,cancelled,resets=status()
  h.equals(enabled,false); h.equals(cancelled,1); h.equals(resets,1)
  h.equals(k:canWalk(),false); h.equals(k.online.scan,.5)
  h.equals(k.prompts[1].Enabled,false); h.equals(k.online.blocked,true)
  h.equals(v.cutIndex,2); h.equals(v.cutProgress,55)
  k:openShop(); k:watchPlayer({}); k:previewDecor('plant'); k:setOpen(false); j:open()
  h.equals(k.opened,true); h.equals(k.shopping,nil); h.equals(k.focus,nil); h.equals(v.journalOpen,nil)
  d:open(); local _,again=status(); h.equals(again,changes,'повторное открытие не дублирует блокировку')
  d:close(); h.equals(status(),true); h.equals(k:canWalk(),true)
  local _,closed=status(); d:close(); local _,twice=status(); h.equals(closed,twice)
 end)
 h.test('отчёт и дневник возвращают управление только после закрытия обоих окон',function()
  for _,first in {'report','journal'} do
   local k,d,j,v,status=fixture()
   j:open(); d:open(); h.equals(status(),false)
   if first=='report' then d:close() else j:close() end
   h.equals(status(),false); h.equals(k:canWalk(),false)
   if first=='report' then j:close() else d:close() end
   h.equals(status(),true); h.equals(v.diagnosticsOpen,false); h.equals(v.journalOpen,false)
  end
 end)
 h.test('закрытие отчёта не включает прогулку при каталоге, визите, наблюдении и резке',function()
  for _,mode in {'shopping','browsing','focus','cut','loading'} do
   local k,d,_,_,status=fixture()
   if mode=='cut' then k.opened=false elseif mode=='loading' then k.state.ready=false else k[mode]=true end
   d:open(); d:close()
   h.equals(status(),false); h.equals(k:canWalk(),false)
  end
 end)
end
