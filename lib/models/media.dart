/// שדות קובץ מדיה משותפים לשירים ולשיעורים.
///
/// - [filePath]  נתיב מקומי במכשיר (לא תקף במכשירים אחרים אחרי סנכרון).
/// - [remoteUrl] כתובת הורדה ציבורית (GitHub Releases / raw).
/// - [assetApi]  כתובת ה-API של הקובץ ב-GitHub Releases – מאפשרת הורדה ממאגר פרטי ומחיקה.
mixin MediaFields {
  String? filePath;
  String? fileName;
  String? remoteUrl;
  String? assetApi;
  int? fileSize;
  int? clipStartMs;
  int? clipEndMs;

  bool get isClip =>
      clipStartMs != null && clipEndMs != null && clipEndMs! > clipStartMs!;

  bool get hasMedia =>
      filePath != null || remoteUrl != null || assetApi != null;
  bool get isInCloud => remoteUrl != null || assetApi != null;

  Map<String, dynamic> mediaJson() => {
        'filePath': filePath,
        'fileName': fileName,
        'remoteUrl': remoteUrl,
        'assetApi': assetApi,
        'fileSize': fileSize,
        'clipStartMs': clipStartMs,
        'clipEndMs': clipEndMs,
      };

  void readMedia(Map j) {
    filePath = j['filePath'];
    fileName = j['fileName'];
    remoteUrl = j['remoteUrl'];
    assetApi = j['assetApi'];
    fileSize = (j['fileSize'] as num?)?.toInt();
    clipStartMs = (j['clipStartMs'] as num?)?.toInt();
    clipEndMs = (j['clipEndMs'] as num?)?.toInt();
    // תאימות לאחור: בגרסה הקודמת כתובת ה-GitHub נשמרה בתוך filePath
    if (remoteUrl == null && (filePath?.startsWith('http') ?? false)) {
      remoteUrl = filePath;
      filePath = null;
    }
  }

  void clearMedia() {
    filePath = null;
    fileName = null;
    remoteUrl = null;
    assetApi = null;
    fileSize = null;
    clipStartMs = null;
    clipEndMs = null;
  }
}
