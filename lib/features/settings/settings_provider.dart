// lib/features/settings/settings_provider.dart
//
// FIXED (#23): This file previously re-declared SettingsState, SettingsNotifier,
// settingsProvider, businessConfigProvider, and discountsAllowedProvider —
// identical copies of what already exists in business_config.dart.
// Having both imported together causes a Dart "duplicate provider" runtime error.
//
// Fix: All definitions are removed from here. This file now simply re-exports
// the canonical definitions from business_config.dart. Any file that was
// importing settings_provider.dart will continue to work with no import changes.

export '../../config/business_config.dart'
    show
        SettingsState,
        SettingsNotifier,
        settingsProvider,
        businessConfigProvider,
        discountsAllowedProvider;