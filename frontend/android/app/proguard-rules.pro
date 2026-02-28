# Suppress warnings for Play Core classes referenced by Flutter's deferred
# components (not used in this app — safe to ignore)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.app.FlutterPlayStoreSplitApplication
-dontwarn io.flutter.embedding.engine.deferredcomponents.**

# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep video_player
-keep class com.google.android.exoplayer2.** { *; }

# Kotlin
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
