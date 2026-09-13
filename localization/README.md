# Локализация

Английский — язык исходных текстов. Ручной русский перевод находится в
`src/shared/LocalizationCatalog.luau` и доступен клиенту без облака.
`src/client/Localization.luau` обновляет привязанные подписи при изменении
языка Roblox и использует облачный Translator:FormatByKey для других языков.
Числа и названия улучшений передаются параметрами, а не склеиваются с фразой.

После изменения каталога выполнить `lune run tools/export-localization`.
Полученный `localization/en-ru.csv` содержит английские источники и русский
перевод; его нужно обновлять в Creator Hub → Localization → Table Management
через Upload CSV, без удаления существующей таблицы.

В настройках опыта выбрать Source Language: English, включить Capture text
from experience UI while users play и автоматический перевод поддерживаемых
Roblox языков. Ручные русские строки не нужно заменять автопереводом.
Не добавлять пустые колонки других языков в экспорт: Roblox может расценить
пустые значения как ручное удаление уже существующих переводов.

На 2026-09-13 код и CSV подготовлены; настройка облачной таблицы пока НЕ
выполнена: Creator Hub требует входа владельца. До загрузки таблицы
отсутствующие облачные переводы заменяются английским. Автоперевод Roblox
не обязан появляться немедленно после загрузки новых строк.

Документация Roblox:
- https://create.roblox.com/docs/production/localization/add-translations
- https://create.roblox.com/docs/production/localization/automatic-translations
- https://create.roblox.com/docs/production/localization/localize-with-scripting
