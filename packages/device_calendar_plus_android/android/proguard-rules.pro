# Keep all classes in the plugin package for Flutter method channel access
# R8/ProGuard can't detect that Flutter calls into these classes via method channels,
# so we need to explicitly keep them to prevent stripping in release builds
-keep class to.bullet.device_calendar_plus_android.** { *; }

