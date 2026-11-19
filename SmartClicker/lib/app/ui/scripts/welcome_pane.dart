// Shown instead of the editor when no script is open: how to start and the
// features worth knowing (the ghost first).

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../new_script/new_script_dialog.dart';

class WelcomePane extends StatelessWidget {
  final AppController app;
  const WelcomePane(this.app, {super.key});

  Widget _feature(IconData? icon, String emoji, String title, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 32,
            child: icon == null ? Text(emoji, style: const TextStyle(fontSize: 20)) : Icon(icon, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: Color(0xFFA0A7B5), fontSize: 13)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final ghost = app.settings.ghostKey.isEmpty ? '👻' : app.settings.ghostKey.toUpperCase();
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Начните со скрипта', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text('Создайте его из шаблона или запишите свои действия — код появится сам.',
                style: TextStyle(color: Color(0xFFA0A7B5))),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => showNewScript(context, app),
              icon: const Icon(Icons.add),
              label: const Text('Новый скрипт'),
            ),
            const SizedBox(height: 24),
            _feature(null, '👻', 'Призрак — проверить, ничего не нажав',
                'Пока скрипт работает, $ghost включает призрака: скрипт идёт дальше, но его клики и '
                    'клавиши только показываются кольцом. Дошли до важного нажатия — включили, '
                    'посмотрели, куда попадёт клик, выключили. Во время записи наоборот: ваши клики '
                    'записываются, но не нажимаются.'),
            _feature(Icons.ads_click, '', 'Стоп-кадр для точек, цвета и областей',
                '«Инструменты» → «Взять координаты кликом», пипетка, «Выделить область»: экран замирает, '
                    'клик никуда не попадает, рядом с курсором лупа.'),
            _feature(Icons.smart_toy_outlined, '', 'Нейросеть напишет скрипт',
                '«Справка» → «Скопировать промпт для ИИ», допишите задачу. В справке «Программа: где что» '
                    'нейросеть найдёт, где какая кнопка, и подскажет план.'),
          ]),
        ),
      ),
    );
  }
}
