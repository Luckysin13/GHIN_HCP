/// The light/dark/system control.
///
/// Its own module because it is the one piece of UI that is pure chrome: it
/// has no opinion about golf, and putting it in `main.dart` would only make
/// that file longer for something the store owns anyway.
library;

import 'package:flutter/material.dart';

import 'design_tokens.dart';
import 'store.dart';

/// App-bar button that sets the app's brightness.
///
/// A menu of the three named modes rather than a button that cycles through
/// them. Cycling is fewer taps, but after the first press the icon says
/// "dark" while meaning "press for light", and a toggle you have to learn is
/// worse than one you can read.
class ThemeModeButton extends StatelessWidget {
  final GolfStore store;
  const ThemeModeButton({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final mode = store.themeMode;
    return PopupMenuButton<ThemeMode>(
      tooltip: 'Appearance',
      icon: Icon(_iconFor(mode)),
      position: PopupMenuPosition.under,
      // The root listens to the store, so this is what repaints the app.
      onSelected: store.setThemeMode,
      itemBuilder: (_) => [
        for (final m in ThemeMode.values)
          PopupMenuItem(
            value: m,
            child: _ModeRow(
              label: _labelFor(m),
              icon: _iconFor(m),
              selected: m == mode,
            ),
          ),
      ],
    );
  }

  static IconData _iconFor(ThemeMode m) => switch (m) {
    ThemeMode.system => Icons.brightness_auto_outlined,
    ThemeMode.light => Icons.light_mode_outlined,
    ThemeMode.dark => Icons.dark_mode_outlined,
  };

  static String _labelFor(ThemeMode m) => switch (m) {
    ThemeMode.system => 'Match system',
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
  };
}

class _ModeRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;

  const _ModeRow({
    required this.label,
    required this.icon,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: Insets.md),
        Text(label, style: AppType.body),
        const Spacer(),
        // A check rather than a filled radio: the list is short, and a check
        // does not imply the others are still selectable afterwards.
        if (selected) Icon(Icons.check, size: 20, color: scheme.primary),
      ],
    );
  }
}
