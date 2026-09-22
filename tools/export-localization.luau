--!nonstrict
-- Обновляем CSV для Creator Hub из того же каталога, что используется офлайн.
local fs=require('@lune/fs')
local process=require('@lune/process')
local Catalog=require('../src/shared/LocalizationCatalog')
local keys={}
for key in Catalog.entries do table.insert(keys,key) end
table.sort(keys)
local function cell(value) return '"'..value:gsub('"','""')..'"' end
local lines={'Key,Source,Context,Example,ru'}
for _,key in keys do table.insert(lines,table.concat({cell(key),cell(key),'""','""',cell(Catalog.entries[key])},',')) end
local csv=table.concat(lines,'\n')..'\n'
if #process.args==1 and process.args[1]=='--check' then
 assert(fs.readFile('localization/en-ru.csv')==csv,'CSV устарел: выполните lune run tools/export-localization')
 print(`Локализация актуальна: {#keys} строк`)
else
 assert(#process.args==0,'Использование: lune run tools/export-localization [--check]')
 fs.writeFile('localization/en-ru.csv',csv)
 print(`Экспортировано {#keys} строк локализации`)
end
