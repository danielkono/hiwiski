/// Outside the browser the app is installed, not served: there is no build to compare.
Future<String?> fetchServedBuild() async => null;

/// Outside the browser there is no page to reload.
void reloadPage() {}
