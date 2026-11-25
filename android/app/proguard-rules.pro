# The Mobile Ads SDK brings WorkManager 2.7 with Room 2.2, which creates
# WorkDatabase_Impl by reflection and ships no keep rule for it. Without this,
# R8 removes the constructor and the app crashes at launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }
