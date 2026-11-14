// Reference of the ClickScript language: every command in short; the start of
// the prompt for an AI chat.


/// Language reference shown on the Help page. The same text is the prompt
/// for an AI assistant ("Скопировать промпт для ИИ").
const String languageReference = r'''
ЯЗЫК СКРИПТОВ SmartClicker (ClickScript)
========================================

Синтаксис похож на JavaScript. Точки с запятой не обязательны. Слова await и
async можно писать, но они не нужны: любая команда сама ждёт своего завершения,
а пауза (F8) и стоп (F12) срабатывают в любом месте, даже внутри wait().

ОСНОВЫ
------
// комментарий          /* многострочный комментарий */
let x = 10              // переменная (let, var, const — одинаково)
x = x + 1               x += 5      x++
let s = "текст"         let t = `шаблон: ${x + 1}`
let a = [1, 2, 3]       a.push(4)   a[0]   a.length
let o = {name: "A", n: 1}           o.name   o["n"]
true  false  null

Операторы: + - * / %   == != < <= > >=   && || !   условие ? a : b

ОСОБЫЕ ЗНАЧЕНИЯ
---------------
50%            проценты от ширины/высоты экрана (или окна, см. use_window)
960            пиксели
1000..1500     диапазон: случайное число от 1000 до 1500 при каждом использовании
3s  500ms  2m  1h      время (всё переводится в миллисекунды): wait(3s)
"#FF0000" или #FF0000   цвет

УПРАВЛЕНИЕ
----------
if (условие) { ... } else if (...) { ... } else { ... }
while (условие) { ... }
for (let i = 0; i < 10; i++) { ... }
for (i in 1..5) { ... }          // 1,2,3,4,5
for (item in массив) { ... }     // также: for (let item of массив)
repeat (5) { ... }               // повторить 5 раз
repeat { ... }                   // бесконечно (остановка: break, exit(), F12)
break   continue
switch (x) { case 1: ... break  case "a": ... break  default: ... }
function имя(a, b) { return a + b }
let f = (a, b) => a + b
try { ... } catch (e) { log(e) } finally { ... }
throw "текст ошибки"

Именованные аргументы: click(50%, 40%, offset: 10, button: "right")

МЫШЬ
----
click(x, y)                      клик левой кнопкой
   необязательно: button: "left"|"right"|"middle", count: 2, offset: 10 (разброс ±px),
                  hold: 100 (мс удержания), duration: 300 (плавный подвод курсора, мс)
click()                          клик там, где сейчас курсор
double_click(x, y)   right_click(x, y)   middle_click(x, y)
move(x, y, duration: 300)        переместить курсор
drag(x1, y1, x2, y2, 400)        зажать, провести, отпустить (он же swipe)
hold(x, y, 1500)                 зажать на 1.5 с
scroll(3)                        колесо вниз на 3 деления; scroll(-3) — вверх
scroll(3, x, y)                  прокрутка в точке
mouse_down(x, y)   mouse_up(x, y)   ручное зажатие/отпускание
mouse_pos()                      {x, y, px, py} — пиксели и проценты
mouse_path("x,y,мс x,y,мс ...")  провести курсор по записанной траектории; мс — пауза
                                 перед точкой. Необязательно: unit: "%" (координаты в
                                 процентах), speed: 2 (вдвое быстрее). Обычно эту
                                 команду создаёт запись в режиме «Полная траектория»

КЛАВИАТУРА
----------
key("enter")   key("ctrl+c")   key("alt+f4")   key("a", count: 3, hold: 100)
key_down("shift")   key_up("shift")
type("Привет")                   посимвольный ввод (любой язык, раскладка не важна)
type("text", delay: 50)          с паузой между символами (по умолчанию 50 мс, Настройки: если слать
                                 все буквы разом, Блокнот Windows 11 и др. теряют часть)
                                 длинный текст быстрее вставить: paste("текст")
paste("длинный текст")           через буфер обмена + Ctrl+V (быстро)
Имена клавиш: a-z, 0-9, f1-f24, enter, esc, space, tab, backspace, delete, insert,
home, end, pageup, pagedown, left, right, up, down, ctrl, shift, alt, win,
capslock, printscreen, num0-num9, volume_up, volume_down, volume_mute,
media_play, media_next, media_prev, а также ; = , - . / ` [ \ ] '

ВРЕМЯ
-----
wait(1000)   wait(1s)   wait(800..1200)
wait_until("14:30")              ждать до указанного времени (сегодня или завтра)
now()                            миллисекунды (для замеров)
elapsed()                        сколько мс работает скрипт
time() → "14:30:05"   date() → "2026-01-31"
clock() → {year, month, day, weekday, hour, minute, second}

ЭКРАН
-----
pixel(x, y) → "#RRGGBB"
pixel_is(x, y, "#FF0000", tolerance: 10) → true/false
wait_pixel(x, y, "#FF0000", timeout: 10s, tolerance: 10) → true, если дождались
avg_color(x, y, w, h) → средний цвет области
find_color("#FF0000", x, y, w, h, tolerance: 10) → {x, y} или null
   (без области — поиск по всему экрану); результат можно передать в click(точка)
color_diff("#FF0000", "#F00000") → 0..255, чем меньше, тем ближе цвета

ТЕКСТ И КАРТИНКИ НА ЭКРАНЕ
--------------------------
Область всегда задаётся четырьмя числами: x, y, ширина, высота (можно в %).
read_text(x, y, w, h) → текст в области; строки разделены переносом
   engine: "paddle" — точное распознавание PaddleOCR (~1 с, хорошо читает мелкий,
   цветной и игровой текст; обычно выбрано по умолчанию), engine: "windows" — быстрое
   встроенное в Windows (доли секунды, только чёткий обычный текст).
   Без engine — как выбрано в программе. Для быстрого: lang: "en-US" — язык,
   scale: 3 — увеличить мелкий текст.
text_in(x, y, w, h, "Готово") → true/false; регистр и лишние пробелы не важны
wait_text(x, y, w, h, "Готово", timeout: 10s, interval: 500) → true, если дождались
read_number(x, y, w, h) → число (счётчик, цена) или null
screenshot("имя", x, y, w, h) → сохраняет имя.png в папку files (без области — весь экран)
find_image("имя", x, y, w, h, tolerance: 20, scale: "auto") → {x, y, w, h, scale} или null
   {x, y} — центр найденной картинки; без области — весь экран
wait_image("имя", timeout: 10s) → {x, y} или null
click_image("имя", timeout: 5s) → true, если картинка нашлась и клик сделан
   scale: "auto" — картинка могла стать крупнее или мельче (другое разрешение,
   масштаб Windows, размер окна игры): ищется от 0.5 до 2 размеров образца;
   scale: 0.8..1.3 — свой диапазон, scale: 1.5 — около этого масштаба.
   С масштабом поиск дольше (обычно 0,3–1 с на весь экран, маленькая картинка —
   до 3 с; область поиска и узкий диапазон ускоряют) и допускает больше отличий;
   в ответе есть scale — найденный масштаб, и w, h — размер на экране.
   Распознавание не бывает буква-в-букву: сравнивайте через text_in / contains,
   а не через ==. Без scale картинка ищется пиксель-в-пиксель в том же масштабе.
screen_size() → {w, h}

ОКНА И ПРОЦЕССЫ
---------------
Окно ищется по имени процесса ("notepad" или "notepad.exe") или части заголовка.
Если у программы несколько окон, укажите оба: "notepad.exe|отчёт" — процесс и
часть заголовка через вертикальную черту.
active_window() → {title, process, pid, x, y, w, h}
windows() → массив всех окон
window_exists("Game")   is_window_active("Game")
focus_window("Game") → true/false       вывести окно на передний план
set_window_bounds("Game", 0, 0, 1280, 720)
use_window("Game")       координаты и проценты считаются от этого окна
use_screen()             вернуть отсчёт от экрана
require_window("Game")   БЕЗОПАСНОСТЬ: клики и клавиши идут только в это окно; если
                         сверху другое — окно выводится вперёд (focus: false — ждать,
                         пока его сделают активным). require_window(null) — снять
with_window("Game") {    use_window + require_window ТОЛЬКО внутри скобок; после
    click(50%, 50%)      блока всё как было (use_screen() писать не нужно).
}                        Скобка { — на той же строке. with_window("Game", focus: false)
                         Окна нет — ждёт до 30 с (timeout: 0 — сразу ошибка, timeout: 2m).
                         restore: true — после блока вернуть вперёд окно, что было активно
is_process_running("game.exe")   kill_process("game.exe")
launch("C:/Games/game.exe")      запустить программу/файл/ссылку. Если программа уже
                                 запущена, второй экземпляр НЕ открывается (вернёт false)
launch("notepad.exe", new: true) открыть ещё один экземпляр в любом случае
run_command("ipconfig") → {code, out, err};  run_command("...", wait: false)

СИСТЕМА И ДАННЫЕ
----------------
battery_level() → 0..100 или null     is_charging()     is_network_connected()
get_clipboard()   set_clipboard("текст")
read_file("a.txt")  write_file("a.txt", "текст")  append_file(...)  file_exists(...)
save_data("gold", 1500)   load_data("gold", 0)    память между запусками
cpu_usage() → загрузка процессора, % (замер за 0,5 с; interval: 1000 — дольше)
cpu_usage("game.exe") → сколько процессора берёт программа, % от всех ядер; null — не запущена
ram_usage() → занято памяти, %        ram_usage("game.exe") → память программы, МБ или null
ram_info() → {total, free, used} в МБ
system_power("lock") — заблокировать экран; "sleep" — сон, "hibernate" — гибернация,
   "shutdown" — выключить, "restart" — перезагрузить, "logoff" — выйти из учётной записи.
   Всё, кроме "lock", нужно сначала разрешить: Настройки → Запуск.
   Пример — дождаться конца загрузки и усыпить компьютер:
       wait_text(820, 400, 300, 60, "Готово", timeout: 3h)
       system_power("sleep")

ВОПРОСЫ ПРИ ЗАПУСКЕ
-------------------
let times = ask("Сколько раз кликать?", 10)        поле с числом (10 — по умолчанию)
let mode  = ask("Режим", "быстро", options: ["быстро", "медленно"])   выпадающий список
let sell  = ask("Продавать мусор?", true)          флажок да/нет
let name  = ask("Имя персонажа", "")               поле для текста
   Все вопросы скрипта (и скриптов из run_script) показываются одним окном при нажатии
   «Запуск». Последний ответ запоминается и подставляется в следующий раз. При запуске
   по клавише, по расписанию, автозапуском, с мини-панели и при перезапуске после ошибки
   окна нет — берутся последние ответы (или значения по умолчанию).
   Текст вопроса и значения пишите как есть, без вычислений: ask("Сколько?", 10).

ПРОЧЕЕ
------
log("текст", значение)   warn("...")      запись в лог
notify("Заголовок", "Текст")             всплывающая плашка в программе
run_script("Имя скрипта")                выполнить другой скрипт (его функции
                                         остаются доступны — можно делать библиотеки)
run_script("Папка/Имя скрипта")          скрипт из папки; можно и просто по имени
exit()                                   завершить скрипт
random(1, 10)  random_int(1, 10)  chance(30%)  pick([1, 2, 3])
str(x)  int(x)  float(x)  len(x)  type_of(x)  to_json(x)  from_json(s)
abs floor ceil round sqrt pow min max    (также Math.floor(...) и т.п.)
set_option("human", true)        плавные движения по кривой, живые паузы
set_option("click_offset", 5)    разброс всех кликов ±5 px
set_option("time_jitter", 15%)   разброс всех wait ±15%
set_option("type_delay", 30)     пауза между буквами type, мс (по умолчанию из настроек, 50)

Строки: s.length  s.toUpperCase()  s.toLowerCase()  s.trim()  s.includes("a")
        s.startsWith  s.endsWith  s.indexOf  s.split(",")  s.replace("a","b")  s.substring(0, 3)
Массивы: push pop shift unshift includes indexOf join slice reverse sort concat
         map filter forEach find some every
Объекты: keys(o)  o.has("k")  o.remove("k")

ЧЕГО НЕТ (не используйте): классы, import/require, регулярные выражения, Promise,
setTimeout, оператор typeof (есть функция type_of), значения параметров по умолчанию.

ПРИМЕР
------
// Фарм: 100 кругов, клик по кнопке, если она зелёная
require_window("Game")
use_window("Game")
set_option("human", true)

repeat (100) {
    if (wait_pixel(50%, 80%, "#22CC44", timeout: 5s, tolerance: 25)) {
        click(50%, 80%, offset: 8)
    } else {
        log("Кнопка не появилась, пробую ещё раз")
    }
    wait(1500..2500)
}
notify("Готово", "100 кругов пройдено")
''';

const String aiPromptHeader = '''
Ты пишешь скрипты для автокликера SmartClicker. Используй ТОЛЬКО описанный ниже
язык и функции. Отвечай одним блоком кода без пояснений внутри кода, кроме
коротких комментариев. Координаты по возможности задавай в процентах.
Всегда добавляй паузы wait() между действиями. Для бесконечных циклов
обязательно ставь wait() внутри цикла.
''';
