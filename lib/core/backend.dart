import 'package:cloud_functions/cloud_functions.dart';

/// `flutter run -d chrome --dart-define=USE_EMULATORS=true` usa los emuladores locales
/// (Auth, Firestore y Functions) en vez del proyecto real.
const useEmulators = bool.fromEnvironment('USE_EMULATORS');

/// Las Cloud Functions viven en Santiago, igual que Firestore.
final functions = FirebaseFunctions.instanceFor(region: 'southamerica-west1');
