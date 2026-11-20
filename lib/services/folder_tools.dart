export 'folder_tools_stub.dart' if (dart.library.io) 'folder_tools_io.dart';

/// קובץ מדיה בתיקייה המקומית שעדיין לא משויך לשיעור או לשיר
class FreeFile {
  final String path, name, relative;
  final int size;
  const FreeFile(
      {required this.path,
      required this.name,
      required this.relative,
      required this.size});
}

class ZipEntry {
  final String path;
  final int size;
  const ZipEntry({required this.path, required this.size});
}
