Future<String?> readLocalJson(String folder) async => null;
Future<void> writeLocalJson(String folder, String value) async => throw UnsupportedError('תיקייה מקומית אינה זמינה בדפדפן');
Future<String?> copyMediaToLocal(String folder, String sourcePath, String name, String sub) async => null;
Future<void> checkLocalFolderWritable(String folder) async => throw UnsupportedError('בדפדפן אי אפשר לחבר תיקייה מקומית – השתמש באפליקציה במחשב או בטלפון');
