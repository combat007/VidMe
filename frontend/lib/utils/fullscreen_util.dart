// Conditional export: web implementation on browser, stub elsewhere.
export 'fullscreen_util_stub.dart'
    if (dart.library.html) 'fullscreen_util_web.dart';
