/// Key names used in scripts <-> Windows virtual-key codes.
/// (Android/Linux backends map the same names to their own codes.)
final Map<String, int> vkByName = _build();

/// Canonical name for a virtual-key code (first registered name wins).
final Map<int, String> nameByVk = () {
  final m = <int, String>{};
  vkByName.forEach((k, v) => m.putIfAbsent(v, () => k));
  return m;
}();

const modifierKeys = {'ctrl', 'shift', 'alt', 'win'};

/// Shift, Ctrl, Alt (generic and left/right) and both Win keys.
bool isModifierVk(int vk) =>
    (vk >= 0x10 && vk <= 0x12) || (vk >= 0xA0 && vk <= 0xA5) || vk == 0x5B || vk == 0x5C;

/// The key of a hotkey that a keyboard hook can hold back: the last
/// non-modifier one ("ctrl+alt+s" -> S). Null for combos of modifiers only
/// ("alt+shift"), which cannot be held back without breaking typing.
int? mainKeyOf(List<int> combo) {
  for (var i = combo.length - 1; i >= 0; i--) {
    if (!isModifierVk(combo[i])) return combo[i];
  }
  return null;
}

/// True when pressing [vk] completes [combo]: it is the main key and all
/// the other keys of the combo are already down.
bool completesCombo(int vk, List<int> combo, bool Function(int vk) isDown) =>
    mainKeyOf(combo) == vk && combo.every((k) => k == vk || isDown(k));

/// Keys that need KEYEVENTF_EXTENDEDKEY.
const extendedVks = {
  0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x2C, 0x2D, 0x2E, 0x5B,
  0x5C, 0x90, 0xA3, 0xA5, //
};

Map<String, int> _build() {
  final m = <String, int>{
    'ctrl': 0x11,
    'control': 0x11,
    'shift': 0x10,
    'alt': 0x12,
    'win': 0x5B,
    'meta': 0x5B,
    'cmd': 0x5B,
    'enter': 0x0D,
    'return': 0x0D,
    'esc': 0x1B,
    'escape': 0x1B,
    'space': 0x20,
    'tab': 0x09,
    'backspace': 0x08,
    'delete': 0x2E,
    'del': 0x2E,
    'insert': 0x2D,
    'home': 0x24,
    'end': 0x23,
    'pageup': 0x21,
    'pagedown': 0x22,
    'left': 0x25,
    'up': 0x26,
    'right': 0x27,
    'down': 0x28,
    'capslock': 0x14,
    'printscreen': 0x2C,
    'pause': 0x13,
    'numlock': 0x90,
    'scrolllock': 0x91,
    'menu': 0x5D,
    'volume_mute': 0xAD,
    'volume_down': 0xAE,
    'volume_up': 0xAF,
    'media_next': 0xB0,
    'media_prev': 0xB1,
    'media_stop': 0xB2,
    'media_play': 0xB3,
    ';': 0xBA,
    '=': 0xBB,
    'plus': 0xBB,
    ',': 0xBC,
    '-': 0xBD,
    'minus': 0xBD,
    '.': 0xBE,
    '/': 0xBF,
    '`': 0xC0,
    '[': 0xDB,
    '\\': 0xDC,
    ']': 0xDD,
    "'": 0xDE,
    'num*': 0x6A,
    'num+': 0x6B,
    'num-': 0x6D,
    'num.': 0x6E,
    'num/': 0x6F,
    'lshift': 0xA0,
    'rshift': 0xA1,
    'lctrl': 0xA2,
    'rctrl': 0xA3,
    'lalt': 0xA4,
    'ralt': 0xA5,
  };
  for (var i = 0; i < 26; i++) {
    m[String.fromCharCode(0x61 + i)] = 0x41 + i;
  }
  for (var i = 0; i < 10; i++) {
    m['$i'] = 0x30 + i;
    m['num$i'] = 0x60 + i;
  }
  for (var i = 1; i <= 24; i++) {
    m['f$i'] = 0x6F + i;
  }
  return m;
}

/// VK codes the recorder watches (everything nameable except L/R variants,
/// which duplicate the generic ctrl/shift/alt codes).
final List<int> recordableVks = nameByVk.keys
    .where((vk) => vk < 0xA0 || vk > 0xA5)
    .toList(growable: false);
