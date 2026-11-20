import 'folder_tools.dart';

Future<List<FreeFile>> listMediaFiles(String folder, List<String> exts) async =>
    const [];

Future<List<String>> copyFilesToFolder(String folder, List<String> sources,
        {String sub = 'inbox'}) async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');

Future<List<ZipEntry>> listImportableZipEntries(
        String zipPath, List<String> allowedExtensions) async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');

Future<int> extractSelectedZipEntries(
        String folder, String zipPath, Set<String> selected,
        {String sub = 'inbox',
        void Function(int done, int total)? onProgress}) async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');

Future<int> extractZipToFolder(String folder, String zipPath,
        {String sub = 'inbox',
        void Function(int done, int total)? onProgress}) async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');

Future<String> makeTempFolder() async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');

Future<void> deleteFolder(String path) async {}

Future<String> writeBytesToFolder(
        String folder, String relative, List<int> bytes) async =>
    throw UnsupportedError('בדפדפן אין גישה לתיקיות במחשב');
