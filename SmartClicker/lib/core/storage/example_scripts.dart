// Example scripts written on the first start (folder "Примеры").


const examplesFolder = 'Примеры';

const exampleScripts = <String, String>{
  'Пример 1 - клики': '''// Простой пример: 5 кликов по центру экрана.
// Запуск: кнопка ▶ (перед стартом есть отсчёт — успейте открыть нужное окно).
// Стоп: F12, пауза: F8 (клавиши меняются в настройках).

wait(1s)

repeat (5) {
    click(50%, 50%, offset: 10)   // центр экрана, разброс ±10 px
    wait(800..1200)               // случайная пауза 0.8–1.2 с
}

log("Готово!")
''',
  'Пример 2 - условия и пиксели': '''// Клик только если пиксель нужного цвета.
// Точку и цвет удобно взять клавишей F6 (наведите курсор и нажмите).

let x = 50%
let y = 50%

log("Цвет в точке:", pixel(x, y))

if (pixel_is(x, y, "#FFFFFF", tolerance: 20)) {
    click(x, y)
} else {
    log("Цвет другой — не кликаю")
}

// Ждать появления цвета до 5 секунд
if (wait_pixel(x, y, "#FF0000", timeout: 5s)) {
    log("Появился красный")
} else {
    log("Не дождался")
}
''',
  'Пример 3 - окно и клавиатура': '''// Работа с конкретным окном: открыть Блокнот и напечатать текст.

launch("notepad.exe")   // если Блокнот уже открыт, второй не запускается
                        // (нужен ещё один — launch("notepad.exe", new: true))
wait(1500)

if (focus_window("notepad")) {
    require_window("notepad")   // ввод идёт, только пока Блокнот активен
    use_window("notepad")       // координаты считаются от окна Блокнота

    click(50%, 50%)
    type("Привет от SmartClicker! ", delay: 30)
    paste("Этот текст вставлен через буфер обмена.")
    key("enter")
    key("ctrl+a")
} else {
    log("Блокнот не найден")
}

// Дальше снова работаем со всем экраном и любыми окнами.
// Без этих двух строк следующие клики считались бы от окна Блокнота.
use_screen()
require_window(null)
''',
  'Пример 4 - функции и данные': '''// Функции, счётчик между запусками, защита по батарее.

function collect(n) {
    log(`Сбор №\${n}`)
    click(40%, 60%)
    wait(300..500)
    drag(30%, 50%, 70%, 50%, 400)   // свайп слева направо
}

let total = load_data("total", 0)

for (i in 1..3) {
    let battery = battery_level()
    if (battery != null && battery < 15 && !is_charging()) {
        notify("Стоп", "Батарея разряжена")
        exit()
    }
    collect(i)
    total++
}

save_data("total", total)
log("Всего сборов за всё время:", total)
''',
};
