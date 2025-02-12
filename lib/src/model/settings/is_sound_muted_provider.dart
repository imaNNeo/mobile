import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:lichess_mobile/src/model/settings/settings_repository.dart';

final isSoundMutedProvider =
    StateNotifierProvider.autoDispose<IsSoundMutedNotifier, bool>((ref) {
  final settingsRepository = ref.watch(settingsRepositoryProvider);
  return IsSoundMutedNotifier(
    settingsRepository,
    initialValue: settingsRepository.isSoundMuted(),
  );
});

class IsSoundMutedNotifier extends StateNotifier<bool> {
  IsSoundMutedNotifier(this.settings, {required bool initialValue})
      : super(initialValue);

  final SettingsRepository settings;

  Future<void> toggleSound() async {
    final ok = await settings.toggleSound();
    if (ok) {
      state = settings.isSoundMuted();
    }
  }
}
