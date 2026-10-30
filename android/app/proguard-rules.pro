-keep class com.dexterous.** { *; }
-keep class * extends com.google.gson.TypeAdapter
-keepattributes Signature
-keepattributes *Annotation*

# Flutter wrapper and plugins
-keep class io.flutter.** { *; }

# Streak app classes & background services/workers
-keep class com.streak.app.** { *; }

# AndroidX WorkManager & Glance for home screen widgets
-keep class androidx.glance.** { *; }
-keep class androidx.work.** { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
