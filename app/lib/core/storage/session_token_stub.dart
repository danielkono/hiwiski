/// A token for this run of the app only — gone when the app ends.
String? _token;

String? readSessionToken() => _token;

void writeSessionToken(String? token) => _token = token;
