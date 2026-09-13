--!nonstrict
-- Обновляем CSV для Creator Hub из того же каталога, что используется офлайн.
local fs=require('@lune/fs')
local Catalog=require('../src/shared/LocalizationCatalog')
local keys={}
for key in Catalog.entries do table.insert(keys,key) end
table.sort(keys)
local function cell(value) return '"'..value:gsub('"','""')..'"' end
local lines={'Key,Source,Context,Example,ru'}
for _,key in keys do table.insert(lines,table.concat({cell(key),cell(key),'""','""',cell(Catalog.entries[key])},',')) end
fs.writeFile('localization/en-ru.csv',table.concat(lines,'\n')..'\n')
print(`Экспортировано {#keys} строк локализации`)
