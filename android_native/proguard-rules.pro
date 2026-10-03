# WorkManager/Room instantiate this generated database through reflection.
# AGP 9/R8 removed its public no-arg constructor in the distributed RC APK,
# crashing InitializationProvider before Flutter could render a first frame.
-keep class androidx.work.impl.WorkDatabase_Impl { public <init>(); }
-keepnames class androidx.work.impl.WorkDatabase

# PDFBox's optional JPX codecs are not used by the overlay bridge.
-dontwarn com.gemalto.jp2.JP2Decoder
-dontwarn com.gemalto.jp2.JP2Encoder
