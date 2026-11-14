import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// B / Esc — go back. Handled at the app root (pops routes, never exits).
class GamepadBackIntent extends Intent {
  const GamepadBackIntent();
}

/// Start — open the system menu / settings.
class GamepadMenuIntent extends Intent {
  const GamepadMenuIntent();
}

/// X — contextual action (theme defined, e.g. "add game").
class GamepadContextIntent extends Intent {
  const GamepadContextIntent();
}

/// Y — secondary action (theme defined, e.g. "toggle favourite").
class GamepadAltIntent extends Intent {
  const GamepadAltIntent();
}

/// Select / View — theme defined (e.g. info overlay).
class GamepadSelectIntent extends Intent {
  const GamepadSelectIntent();
}

/// L1 (-1) / R1 (+1) — jump between categories / pages.
class GamepadPageIntent extends Intent {
  const GamepadPageIntent(this.delta);
  final int delta;
}

/// Key bindings layered on top of [WidgetsApp.defaultShortcuts], which
/// already map arrows/D-Pad → [DirectionalFocusIntent] and A/Enter → [ActivateIntent].
///
/// Analog sticks / HAT D-Pads are converted to D-Pad key events natively
/// (`AnalogDpadMapper.kt`), so they flow through the same pipeline.
abstract final class GamepadShortcuts {
  static const Map<ShortcutActivator, Intent> bindings = {
    // Confirm
    SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
    // Back
    SingleActivator(LogicalKeyboardKey.gameButtonB): GamepadBackIntent(),
    SingleActivator(LogicalKeyboardKey.escape): GamepadBackIntent(),
    SingleActivator(LogicalKeyboardKey.backspace): GamepadBackIntent(),
    // Face buttons
    SingleActivator(LogicalKeyboardKey.gameButtonX): GamepadContextIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonY): GamepadAltIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonStart): GamepadMenuIntent(),
    SingleActivator(LogicalKeyboardKey.gameButtonSelect): GamepadSelectIntent(),
    // Shoulders
    SingleActivator(LogicalKeyboardKey.gameButtonLeft1): GamepadPageIntent(-1),
    SingleActivator(LogicalKeyboardKey.gameButtonRight1): GamepadPageIntent(1),
    // Keyboard fallbacks (emulator / scrcpy / desktop testing)
    SingleActivator(LogicalKeyboardKey.keyX): GamepadContextIntent(),
    SingleActivator(LogicalKeyboardKey.keyY): GamepadAltIntent(),
    SingleActivator(LogicalKeyboardKey.keyM): GamepadMenuIntent(),
    SingleActivator(LogicalKeyboardKey.keyQ): GamepadPageIntent(-1),
    SingleActivator(LogicalKeyboardKey.keyE): GamepadPageIntent(1),
  };
}
