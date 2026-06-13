import 'package:flutter/widgets.dart';

/// Global navigator key used by the GoRouter (app.dart) and by services that
/// need to navigate without a BuildContext (e.g. push-notification taps).
/// Lives in its own leaf file to avoid an import cycle with app.dart.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
