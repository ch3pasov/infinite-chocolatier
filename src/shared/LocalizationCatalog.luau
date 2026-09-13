--!nonstrict
-- Английский источник и ручной русский перевод; CSV для Roblox строится из этого каталога.
local Catalog = {}
Catalog.entries = {
	["+0.2 pieces/s · up to 4 hours offline"] = "+0,2 дольки/с · офлайн до 4 часов",
	["+1 piece per trick"] = "+1 долька за каждый фокус",
	["+25% manual and automatic income"] = "+25% к ручному и автоматическому доходу",
	["+{manual} per trick  ·  {rate}/s  ·  ★ {stars}"] = "+{manual} за фокус  ·  {rate}/с  ·  ★ {stars}",
	["ATELIER"] = "АТЕЛЬЕ",
	["ATELIER · upgrades"] = "АТЕЛЬЕ · улучшения",
	["ATELIER · {count} available"] = "АТЕЛЬЕ · доступно {count}",
	["All four cuts are done — the bar separates into five pieces"] = "Все четыре разреза готовы — плитка раскрывается на пять частей",
	["B"] = " млрд",
	["Buy"] = "Купить",
	["Buy · {price} pieces"] = "Купить · {price} долек",
	["Cancel"] = "Отмена",
	["Cannot purchase: check your balance and upgrade level"] = "Покупка недоступна: проверь баланс и уровень",
	["Chocolate Atelier"] = "Шоколадное ателье",
	["Chocolatiers"] = "Шоколатье",
	["Confirm reset · +{stars} ★"] = "Подтвердить сброс · +{stars} ★",
	["Could not load your progress. Wait a moment and rejoin. Your save has not been changed."] = "Не удалось загрузить прогресс. Подожди немного и зайди снова: сохранение не изменено.",
	["Could not renew your save session. Rejoin to continue safely."] = "Не удалось продлить сохранение. Перезайди, чтобы безопасно продолжить.",
	["Craftsmanship"] = "Мастерство",
	["Cut {step} of {total}: continue from the highlighted point"] = "Разрез {step} из {total}: продолжи с подсвеченной точки",
	["Cut {step} of {total}: {instruction}"] = "Разрез {step} из {total}: {instruction}",
	["Done! The bar is whole again, with one original piece left over"] = "Готово: плитка снова целая, а исходная долька осталась снаружи",
	["Earn 5K pieces to start a new atelier"] = "Нужно 5 тыс. заработанных долек",
	["Earn more pieces to start a new atelier"] = "Для нового ателье пока мало заработано",
	["Earned in this atelier: {earned}. The first star costs 5K, two cost 20K. Each adds +25% income permanently. Pieces and upgrades will reset."] = "Заработано в этом ателье: {earned}. Первая звезда за 5 тыс., две — за 20 тыс. Каждая даёт +25% навсегда. Дольки и улучшения сбросятся.",
	["Goal · earn 5K pieces"] = "Цель · 5 тыс. заработанных долек",
	["K"] = " тыс.",
	["LOADING ATELIER…"] = "ЗАГРУЗКА АТЕЛЬЕ…",
	["Loading your progress"] = "Загружаем твой прогресс",
	["M"] = " млн",
	["Maximum level"] = "Максимальный уровень",
	["New Atelier"] = "Новое ателье",
	["New atelier! +{stars} cocoa stars"] = "Новое ателье! +{stars} какао-звёзд",
	["Open a new atelier · +{stars} ★"] = "Открыть новое ателье · +{stars} ★",
	["PIECES  0"] = "ДОЛЬКИ  0",
	["PIECES  {amount}"] = "ДОЛЬКИ  {amount}",
	["Piece collected — the chocolate bar stays whole"] = "Долька собрана — плитка остаётся целой без обратной перемотки",
	["Price {price} · need {missing} more"] = "Цена {price} · не хватает {missing}",
	["Progress saved"] = "Прогресс сохранён",
	["Recipe"] = "Рецептура",
	["Release to finish the cut"] = "Отпусти, чтобы завершить разрез",
	["Reset your pieces and all upgrades? Your stars stay. Gain {stars} more; each permanently adds +25% income."] = "Сбросить дольки и все улучшения? Звёзды сохранятся. Получишь ещё {stars}; каждая навсегда даёт +25% к доходу.",
	["Return to the highlighted point — your cut progress is saved"] = "Вернись к подсвеченной точке — прогресс сохранён",
	["Saving delayed · retrying"] = "Сохранение задерживается · повторяем",
	["Slide the large piece along the arrow — the other piece will follow"] = "Сдвинь крупную часть по стрелке — вторая повторит перестановку",
	["Slide the two-piece strip into the gap at the top"] = "Вставь блок из двух долек в верхнюю нишу",
	["T"] = " трлн",
	["Test session · progress is not saved"] = "Тестовая сессия · без сохранения",
	["Trick complete! +{amount}"] = "Фокус удался! +{amount} долек",
	["Upgrade purchased"] = "Улучшение куплено",
	["While you were away: +{amount}"] = "Пока тебя не было: +{amount} долек",
	["cut off the top strip"] = "отрежь верхнюю полоску",
	["make the main diagonal cut"] = "проведи главную диагональ",
	["separate the single piece from the two-piece strip"] = "раздели одиночную и двойную дольки",
	["separate the upper-right piece"] = "отдели правую верхнюю часть",
	["Pieces: {amount}  ·  {rate} per second"] = "{amount} долек  ·  {rate} в секунду",
	["{upgrade} · {level}"] = "{upgrade} · {level}",
}

function Catalog.format(source,args,locale)
	local template=if string.sub(string.lower(locale or "en"),1,2)=="ru" then Catalog.entries[source] or source else source
	return (template:gsub("{([%w_]+)}",function(key)
		local value=args and args[key]
		return if value~=nil then tostring(value) else "{"..key.."}"
	end))
end
return Catalog
