// Conditional export: web implementation on browser, stub elsewhere.
export 'web_video_util_stub.dart'
    if (dart.library.html) 'web_video_util_web.dart';
