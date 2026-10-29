# Serialization uses generated companions/serializers; preserve model metadata and names
# for persisted JSON. kotlinx.serialization also supplies its own consumer rules.
-keepattributes Signature,InnerClasses,EnclosingMethod,RuntimeVisibleAnnotations,AnnotationDefault
-keep @kotlinx.serialization.Serializable class com.paply.** { *; }
-keepclassmembers class com.paply.** {
    *** Companion;
    kotlinx.serialization.KSerializer serializer(...);
}
-keep,includedescriptorclasses class com.paply.**$$serializer { *; }

# Worker class names are persisted in the WorkManager database and loaded by name.
-keep,allowoptimization class com.paply.** extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
# Manifest entry points are also rooted by AGP; retain receiver/provider constructors.
-keep,allowoptimization class com.paply.** extends android.content.BroadcastReceiver { public <init>(); }
-keep,allowoptimization class com.paply.** extends android.appwidget.AppWidgetProvider { public <init>(); }

# Compose is compiled code, not reflective UI. Its AndroidX consumer rules apply;
# a blanket keep of androidx.compose would disable useful shrinking/optimization.
# Core JSON uses explicit JsonElement access (no reflective model adapter).

# BuildConfig.DEBUG is false in Release: R8 must remove these debug-only hooks.
-checkdiscard class com.paply.android.DebugControlReceiver
-checkdiscard class com.paply.android.CaptureDebug
