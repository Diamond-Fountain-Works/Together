# Kotlin serialization uses generated serializers; no blanket reflection keep rules.
# The optional native adapter is instantiated at the transport boundary in legacy builds.
-keep class com.together.android.p2p.NativeSessionFactory { public <init>(); public *; }
# UniFFI's generated JNA declarations and Structure field names are native ABI contracts.
-keep class computer.iroh.** { *; }
-keep interface computer.iroh.** { *; }
# JNA initIDs resolves Java class/field/method names from native code (including
# Pointer.peer and Structure.memory/typeInfo). Keeping only native methods is
# insufficient. Follow JNA's Android guidance for this dependency, while R8
# continues to optimize the application and other dependencies.
# https://github.com/java-native-access/jna/blob/5.15.0/www/FrequentlyAskedQuestions.md#jna-on-android
-keep class com.sun.jna.** { *; }
# Desktop-only JNA AWT helpers are not available on Android; the app never calls them.
-dontwarn java.awt.**
-keep class * extends com.sun.jna.Structure { *; }
-keep interface * extends com.sun.jna.Library { *; }
