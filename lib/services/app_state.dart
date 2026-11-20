import '../models/playlist.dart';
import '../models/lesson.dart';
import '../models/lesson_import_info.dart';
import '../models/media.dart';
import '../models/singer.dart';
import '../models/song.dart';
import '../models/unassigned_media.dart';
import 'file_service.dart';
import 'github_media.dart';
import 'local_sync.dart';
import 'storage.dart';
import 'folder_tools.dart';
import 'storage_provider.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

String _mergeRepositorySnapshots(Iterable<String> rawSnapshots) {
  final merged = <String, dynamic>{};
  const listKeys = [
    'singers',
    'songs',
    'lessons',
    'playlists',
    'unassignedMedia',
  ];
  final records = <String, Map<String, Map<String, dynamic>>>{
    for (final key in listKeys) key: <String, Map<String, dynamic>>{},
  };
  final parashot = <String, String>{};
  final importedInfo = <String, dynamic>{};

  for (final raw in rawSnapshots) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) continue;
    for (final key in listKeys) {
      final values = decoded[key];
      if (values is! List) continue;
      for (final value in values) {
        if (value is! Map) continue;
        final item = Map<String, dynamic>.from(value);
        final id = item['id']?.toString();
        final identity = id == null || id.isEmpty
            ? 'json:${jsonEncode(item)}'
            : 'id:$id';
        records[key]!.putIfAbsent(identity, () => item);
      }
    }
    final names = decoded['customParashot'];
    if (names is List) {
      for (final value in names.whereType<String>()) {
        parashot.putIfAbsent(value.toLowerCase(), () => value);
      }
    }
    final savedInfo = decoded['importedLessonInfo'];
    if (savedInfo is Map) {
      for (final entry in savedInfo.entries) {
        importedInfo.putIfAbsent(entry.key.toString(), () => entry.value);
      }
    }
  }

  for (final key in listKeys) {
    merged[key] = records[key]!.values.toList();
  }
  merged['customParashot'] = parashot.values.toList();
  merged['importedLessonInfo'] = importedInfo;
  merged['_updatedAt'] = DateTime.now().toUtc().toIso8601String();
  return jsonEncode(merged);
}

class AppState extends ChangeNotifier {
  late SharedPreferences _p;
  SharedPreferences get prefs => _p;

  List<Singer> singers = [];
  List<Song> songs = [];
  List<Lesson> lessons = [];
  List<Playlist> playlists = [];

  bool dark = false;
  final darkMode = ValueNotifier<bool>(false);

  String githubOwner = 'NOAM-DAMARI';
  String githubRepo = 'LessonSong';
  String githubBranch = 'main';
  String githubToken = '';
  bool githubEnabled = false;
  String localFolder = '';

  /// מקור האחסון הפעיל: GitHub, תיקייה מקומית או שניהם.
  String storageMode = 'github';

  bool get localEnabled =>
      !kIsWeb &&
      localFolder.isNotEmpty &&
      const {'local', 'both'}.contains(storageMode);
  bool syncing = false;
  String syncMessage = 'לא מחובר ל-GitHub';
  DateTime? lastSync;

  List<String> customParashot = [];
  List<UnassignedMedia> unassignedMedia = [];
  Map<String, LessonImportInfo> importedLessonInfo = {};

  String? livePointLessonId;
  int? livePointIndex;

  /// יש שינויים מקומיים שעדיין לא נשמרו ב-GitHub
  bool _dirty = false;

  Timer? _pushTimer;
  DateTime _dataUpdatedAt = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  bool get githubReady =>
      githubEnabled &&
      githubToken.isNotEmpty &&
      const {'github', 'both'}.contains(storageMode);

  String get githubApiBase =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/contents';

  String get githubUrl => '$githubApiBase/data/music_manager.json';

  String githubRawUrl(String path) =>
      'https://raw.githubusercontent.com/$githubOwner/$githubRepo/$githubBranch/$path';

  Map<String, String> get githubHeaders => {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer $githubToken',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Map<String, String> get _headers =>
      {...githubHeaders, 'Content-Type': 'application/json'};

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();

    dark = _p.getBool('dark') ?? false;
    darkMode.value = dark;
    githubOwner = _p.getString('githubOwner') ?? githubOwner;
    githubRepo = _p.getString('githubRepo') ?? githubRepo;
    githubBranch = _p.getString('githubBranch') ?? githubBranch;
    githubToken = _p.getString('githubToken') ?? '';
    githubEnabled = _p.getBool('githubEnabled') ?? false;
    localFolder = _p.getString('localFolder') ?? '';
    final savedMode = _p.getString('storageMode');
    final legacyDriveMode =
        const {'drive', 'localDrive', 'githubDrive'}.contains(savedMode);
    final needsLocalFallback = savedMode == null ||
        savedMode == 'localDrive' ||
        (savedMode == 'drive' && !githubEnabled) ||
        (savedMode == 'githubDrive' && !githubEnabled);
    if (needsLocalFallback && localFolder.isEmpty) {
      localFolder = await defaultMediaFolder() ?? '';
      if (localFolder.isNotEmpty)
        await _p.setString('localFolder', localFolder);
    }
    storageMode = switch (savedMode) {
      'local' || 'localDrive' when localFolder.isNotEmpty => 'local',
      'both' when localFolder.isNotEmpty => githubEnabled ? 'both' : 'local',
      'githubDrive' when localFolder.isNotEmpty =>
        githubEnabled ? 'both' : 'local',
      'drive' when githubEnabled => 'github',
      'drive' when localFolder.isNotEmpty => 'local',
      null when localFolder.isNotEmpty => githubEnabled ? 'both' : 'local',
      _ => 'github',
    };
    if (savedMode == null || legacyDriveMode) {
      await _p.setString('storageMode', storageMode);
    }
    await _p.remove('driveClientId');
    await _p.remove('driveFolderId');
    await _p.remove('driveFolderName');
    await _p.remove('driveImportedFileIds');
    await _p.remove('mirrorFolder');
    _dirty = _p.getBool('dirty') ?? false;
    _dataUpdatedAt = DateTime.tryParse(_p.getString('dataUpdatedAt') ?? '') ??
        _dataUpdatedAt;

    final raw = _p.getString('data');
    if (raw != null) {
      try {
        restore(raw);
      } catch (_) {
        syncMessage = 'הנתונים המקומיים אינם תקינים';
      }
    }
    if (localEnabled && !_dirty) {
      try {
        final folderRaw = await readLocalJson(localFolder);
        if (folderRaw != null && folderRaw.trim().isNotEmpty) {
          restore(folderRaw);
          await _p.setString('data', folderRaw);
        }
      } catch (_) {
        syncMessage = 'לא ניתן לקרוא את תיקיית הסנכרון המקומית';
      }
    }

    if (githubReady || localEnabled) unawaited(syncNow());

    notifyListeners();
  }

  String export({bool includeSettings = false}) => jsonEncode({
        if (includeSettings) 'settings': exportSettings(),
        'singers': singers,
        'songs': songs,
        'lessons': lessons,
        'playlists': playlists,
        'customParashot': customParashot,
        'unassignedMedia': unassignedMedia,
        'importedLessonInfo': {
          for (final entry in importedLessonInfo.entries)
            entry.key: entry.value.toJson()
        },
        '_updatedAt': _dataUpdatedAt.toUtc().toIso8601String(),
      });

  void restore(String raw) {
    final d = jsonDecode(raw);

    singers =
        (d['singers'] as List? ?? []).map((e) => Singer.fromJson(e)).toList();
    songs = (d['songs'] as List? ?? []).map((e) => Song.fromJson(e)).toList();
    lessons =
        (d['lessons'] as List? ?? []).map((e) => Lesson.fromJson(e)).toList();
    playlists = (d['playlists'] as List? ?? [])
        .map((e) => Playlist.fromJson(e))
        .toList();
    customParashot = List<String>.from(d['customParashot'] ?? []);
    unassignedMedia = ((d['unassignedMedia'] ?? []) as List)
        .map((entry) => UnassignedMedia.fromJson(entry as Map))
        .toList();
    final savedInfo = d['importedLessonInfo'];
    importedLessonInfo = savedInfo is Map
        ? savedInfo.map((key, value) =>
            MapEntry(key.toString(), LessonImportInfo.fromJson(value as Map)))
        : <String, LessonImportInfo>{};
    final updatedAt = DateTime.tryParse(d['_updatedAt']?.toString() ?? '');
    if (updatedAt != null) {
      _dataUpdatedAt = updatedAt.toUtc();
    } else if (_dataUpdatedAt.millisecondsSinceEpoch == 0 &&
        (singers.isNotEmpty ||
            songs.isNotEmpty ||
            lessons.isNotEmpty ||
            playlists.isNotEmpty ||
            customParashot.isNotEmpty ||
            unassignedMedia.isNotEmpty ||
            importedLessonInfo.isNotEmpty)) {
      _dataUpdatedAt = DateTime.now().toUtc();
    }
  }

  void _setDirty(bool v) {
    _dirty = v;
    _p.setBool('dirty', v);
  }

  Timer? _diskTimer;
  Future<void> _diskQueue = Future<void>.value();
  bool _notifyScheduled = false;

  /// שמירה: מעדכנת את המסך מיד, כותבת לדיסק אחרי 400ms של שקט (כתיבה אחת ולא עשרות),
  /// ומעלה ל-GitHub אחרי 2 שניות. כך הקלדה לא תוקעת את האפליקציה.
  /// [notify]=false – לשדות טקסט שלא צריכים לבנות את המסך מחדש בכל הקשה.
  void save({bool notify = true}) {
    _dataUpdatedAt = DateTime.now().toUtc();
    _diskTimer?.cancel();
    _diskTimer = Timer(const Duration(milliseconds: 400), flushNow);
    if (notify) _scheduleNotify();

    if (githubReady) _setDirty(true);
    if (githubReady) {
      _pushTimer?.cancel();
      _pushTimer = Timer(const Duration(seconds: 2), _queuePush);
    }
  }

  /// כתיבה מיידית לדיסק (נקרא גם כשהאפליקציה עוברת לרקע). כתיבות לא חופפות.
  Future<void> flushNow() {
    _diskTimer?.cancel();
    final raw = export();
    _diskQueue = _diskQueue.catchError((_) {}).then((_) async {
      try {
        await _p.setString('data', raw);
        await _p.setString(
            'dataUpdatedAt', _dataUpdatedAt.toUtc().toIso8601String());
      } catch (e) {
        debugPrint('preferences save failed: $e');
      }
      if (localEnabled) {
        try {
          await writeLocalJson(localFolder, raw);
        } catch (e) {
          syncMessage = 'שמירה לתיקייה המקומית נכשלה: ${_short(e)}';
        }
      }
    });
    return _diskQueue;
  }

  /// מאחד עדכוני מסך ולא קורא ל-notifyListeners באמצע בניית מסך (מונע לולאות Rebuild).
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    void run() {
      _notifyScheduled = false;
      notifyListeners();
    }

    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => run());
    } else {
      scheduleMicrotask(run);
    }
  }

  void _queuePush() => unawaited(syncNow());

  Future<void> configureGitHub({
    required String owner,
    required String repo,
    required String branch,
    required String token,
  }) async {
    githubOwner = owner.trim();
    githubRepo = repo.trim();
    githubBranch = branch.trim().isEmpty ? 'main' : branch.trim();
    githubToken = token.trim();
    githubEnabled = true;

    await _p.setString('githubOwner', githubOwner);
    await _p.setString('githubRepo', githubRepo);
    await _p.setString('githubBranch', githubBranch);
    await _p.setString('githubToken', githubToken);
    await _p.setBool('githubEnabled', true);

    notifyListeners();
    await syncNow();
  }

  Future<void> clearLocalSiteData() async {
    _diskTimer?.cancel();
    _pushTimer?.cancel();
    restore('{}');
    await _p.remove('data');
    await _p.remove('dataUpdatedAt');
    await _p.remove('dirty');
    _dirty = false;
    await clearCache();
    notifyListeners();
  }

  Map<String, dynamic> exportSettings() {
    final result = <String, dynamic>{
      'githubOwner': githubOwner,
      'githubRepo': githubRepo,
      'githubBranch': githubBranch,
      'githubToken': githubToken,
      'githubEnabled': githubEnabled,
      'storageMode': storageMode,
      'localFolder': localFolder,
      'dark': dark,
    };
    for (final key in _p.getKeys()) {
      if (key.startsWith('tr_')) {
        final value = _p.get(key);
        if (value != null) result[key] = value;
      }
    }
    return result;
  }

  Future<void> importSettings(Map<String, dynamic> values) async {
    String read(String key, String current) {
      final value = values[key]?.toString().trim() ?? '';
      return value.isEmpty ? current : value;
    }

    githubOwner = read('githubOwner', githubOwner);
    githubRepo = read('githubRepo', githubRepo);
    githubBranch = read('githubBranch', githubBranch);
    githubToken = read('githubToken', githubToken);
    await _p.setString('githubOwner', githubOwner);
    await _p.setString('githubRepo', githubRepo);
    await _p.setString('githubBranch', githubBranch);
    if (githubToken.isNotEmpty) await _p.setString('githubToken', githubToken);

    if (values['githubEnabled'] is bool) {
      githubEnabled = values['githubEnabled'] as bool;
      await _p.setBool('githubEnabled', githubEnabled);
    } else if (githubToken.isNotEmpty) {
      githubEnabled = true;
      await _p.setBool('githubEnabled', true);
    }
    if (values['storageMode'] is String &&
        const {'github', 'local', 'both'}.contains(values['storageMode'])) {
      storageMode = values['storageMode'] as String;
      await _p.setString('storageMode', storageMode);
    }
    if (values['localFolder'] is String) {
      localFolder = (values['localFolder'] as String).trim();
      await _p.setString('localFolder', localFolder);
    }
    if (values['dark'] is bool) {
      dark = values['dark'] as bool;
      darkMode.value = dark;
      await _p.setBool('dark', dark);
    }

    for (final entry in values.entries) {
      final key = entry.key.toString();
      if (key.startsWith('tr_') && entry.value != null) {
        await _p.setString(key, entry.value.toString());
      }
    }
    notifyListeners();
    if (githubReady) await syncNow();
  }

  Future<void> configureLocalFolder(String folder) async {
    final f = folder.trim();
    if (f.isNotEmpty) await checkLocalFolderWritable(f);
    localFolder = f;
    if (f.isNotEmpty && storageMode == 'github') {
      storageMode = githubEnabled ? 'both' : 'local';
      await _p.setString('storageMode', storageMode);
    }
    // אם בתיקייה כבר יש נתונים ואין כאן נתונים – טוענים מהתיקייה במקום לדרוס
    if (localEnabled && singers.isEmpty && songs.isEmpty && lessons.isEmpty) {
      final existing = await readLocalJson(localFolder);
      if (existing != null && existing.trim().length > 2) {
        restore(existing);
        await _p.setString('localFolder', localFolder);
        await _p.setString('data', existing);
        _scheduleNotify();
        return;
      }
    }
    await _p.setString('localFolder', localFolder);
    if (localEnabled) await writeLocalJson(localFolder, export());
    notifyListeners();
  }

  Future<void> disconnectLocalFolder() async {
    localFolder = '';
    await _p.remove('localFolder');
    if (storageMode == 'local' || storageMode == 'both') {
      storageMode = 'github';
      await _p.setString('storageMode', storageMode);
    }
    notifyListeners();
  }

  /// בחירת מקור אחסון – פרטי GitHub נשמרים גם כשעובדים מקומית.
  Future<void> setStorageMode(String mode) async {
    if (!const {'github', 'local', 'both'}.contains(mode)) mode = 'github';
    if (mode != 'github' && localFolder.isEmpty) mode = 'github';
    storageMode = mode;
    await _p.setString('storageMode', mode);
    if (localEnabled) {
      try {
        await writeLocalJson(localFolder, export());
      } catch (_) {}
    }
    syncMessage = switch (mode) {
      'local' => 'עובד מול התיקייה המקומית. הגדרות GitHub נשמרו.',
      'both' => 'סנכרון כפול פעיל: GitHub + תיקייה מקומית',
      _ => githubReady ? 'עובד מול GitHub' : 'יש להגדיר חיבור ל-GitHub',
    };
    notifyListeners();
    if (githubReady) unawaited(syncNow());
  }

  /// ניתוק זמני: ה-Token ופרטי המאגר נשמרים, כך שאפשר להתחבר שוב בלחיצה
  Future<void> disconnectGitHub() async {
    githubEnabled = false;
    await _p.setBool('githubEnabled', false);
    syncMessage = 'החיבור ל-GitHub הושהה (הפרטים נשמרו)';
    notifyListeners();
  }

  /// מחיקה מלאה של ה-Token מהמכשיר
  Future<void> forgetGitHubToken() async {
    githubEnabled = false;
    githubToken = '';
    await _p.setBool('githubEnabled', false);
    await _p.remove('githubToken');
    syncMessage = 'ה-Token נמחק מהמכשיר';
    notifyListeners();
  }

  /// נתיבים/שמות של קבצים שכבר משויכים לשיעור או לשיר
  Set<String> get _usedFileKeys => {
        for (final m in [...songs, ...lessons]) ...[
          if (m.filePath != null)
            m.filePath!.replaceAll('\\', '/').toLowerCase(),
          if (m.fileName != null) m.fileName!.toLowerCase(),
        ],
      };

  Future<void> addCustomParasha(String name) => addCustomParashot([name]);

  Future<void> addCustomParashot(Iterable<String> names) async {
    var changed = false;
    for (final name in names) {
      final value = name.trim();
      if (value.isEmpty ||
          customParashot.any(
              (item) => item.toLowerCase() == value.toLowerCase())) continue;
      customParashot.add(value);
      changed = true;
    }
    if (changed) save();
  }

  LessonImportInfo? importedInfoFor(String? key) =>
      key == null ? null : importedLessonInfo[key];

  void setImportedLessonInfo(Map<String, LessonImportInfo> values) {
    importedLessonInfo.addAll(values);
    save();
  }

  void consumeImportedLessonInfo(String? key) {
    if (key != null && importedLessonInfo.remove(key) != null)
      save(notify: false);
  }

  void addUnassignedMedia(UnassignedMedia media) {
    unassignedMedia.removeWhere((item) => item.id == media.id);
    unassignedMedia.add(media);
    save();
  }

  UnassignedMedia? unassignedById(String id) {
    for (final media in unassignedMedia) {
      if (media.id == id) return media;
    }
    return null;
  }

  void consumeUnassignedMedia(String? id) {
    if (id == null) return;
    unassignedMedia.removeWhere((media) => media.id == id);
    save(notify: false);
  }

  Future<void> deleteUnassignedMedia(String id) async {
    final media = unassignedById(id);
    if (media == null) return;
    _dropFiles(media.filePath, media.assetApi, except: media);
    unassignedMedia.removeWhere((item) => item.id == id);
    save();
  }

  /// קבצי מדיה בתיקייה המקומית שעדיין לא שויכו לשיעור או לשיר.
  Future<List<FreeFile>> freeMediaFiles(
      {List<String> extensions = importExts}) async {
    if (!localEnabled) return const [];
    final used = _usedFileKeys;
    final all = await listMediaFiles(localFolder, extensions);
    return [
      for (final f in all)
        if (!used.contains(f.path.replaceAll('\\', '/').toLowerCase()) &&
            !used.contains(f.name.toLowerCase()) &&
            // עותקים שהאפליקציה יצרה נשמרים בשם <timestamp>_<name>
            !used.contains(
                f.name.replaceFirst(RegExp(r'^\d{10,}_'), '').toLowerCase()))
          f,
    ];
  }

  List<StorageProvider> _activeStorageProviders() => [
        if (githubReady)
          GitHubJsonStorageProvider(
            owner: githubOwner,
            repository: githubRepo,
            branch: githubBranch,
            token: githubToken,
          ),
        if (localEnabled) LocalJsonStorageProvider(localFolder),
      ];

  Future<void> syncNow() async {
    final providers = _activeStorageProviders();
    if (providers.isEmpty) {
      syncMessage = 'יש להגדיר מקור אחסון פעיל';
      notifyListeners();
      return;
    }
    if (syncing) return;

    final syncStartedAt = _dataUpdatedAt;
    syncing = true;
    syncMessage =
        'מסנכרן בין ${providers.map((provider) => provider.name).join(' + ')}...';
    notifyListeners();

    try {
      final currentData = export();
      final currentHasData = singers.isNotEmpty ||
          songs.isNotEmpty ||
          lessons.isNotEmpty ||
          playlists.isNotEmpty ||
          customParashot.isNotEmpty ||
          unassignedMedia.isNotEmpty ||
          importedLessonInfo.isNotEmpty;
      StorageSnapshot? latest;
      if (_dirty ||
          _dataUpdatedAt.millisecondsSinceEpoch > 0 ||
          currentHasData) {
        latest =
            StorageSnapshot(rawData: currentData, updatedAt: _dataUpdatedAt);
      }

      final snapshots =
          await Future.wait(providers.map((provider) => provider.read()));
      for (final snapshot in snapshots.whereType<StorageSnapshot>()) {
        if (latest == null || snapshot.updatedAt.isAfter(latest.updatedAt))
          latest = snapshot;
      }
      latest ??=
          StorageSnapshot(rawData: currentData, updatedAt: _dataUpdatedAt);

      restore(latest.rawData);
      final canonical =
          StorageSnapshot(rawData: export(), updatedAt: _dataUpdatedAt);
      for (final provider in providers) {
        await provider.write(canonical);
      }
      await _p.setString('data', canonical.rawData);
      await _p.setString(
          'dataUpdatedAt', _dataUpdatedAt.toUtc().toIso8601String());
      _setDirty(false);
      lastSync = DateTime.now();
      syncMessage =
          'סונכרן בהצלחה: ${providers.map((provider) => provider.name).join(' + ')}';
    } catch (e) {
      syncMessage = 'שגיאת סנכרון: ${_short(e)}';
    } finally {
      syncing = false;
      if (githubReady && _dataUpdatedAt.isAfter(syncStartedAt)) {
        _pushTimer?.cancel();
        _pushTimer = Timer(const Duration(seconds: 2), _queuePush);
      }
      notifyListeners();
    }
  }

  Future<void> importFromGitHub() async {
    if (!githubReady) throw Exception('יש לחבר מאגר GitHub לפני הייבוא');
    final provider = GitHubJsonStorageProvider(
      owner: githubOwner,
      repository: githubRepo,
      branch: githubBranch,
      token: githubToken,
    );
    final snapshot = await provider.read();
    if (snapshot == null) {
      syncMessage = 'לא נמצאו נתונים במאגר';
      notifyListeners();
      return;
    }
    restore(snapshot.rawData);
    _dataUpdatedAt = snapshot.updatedAt;
    await flushNow();
    _setDirty(false);
    syncMessage = 'הנתונים יובאו מ-GitHub';
    notifyListeners();
  }

  Future<void> syncMissingData() async {
    final providers = _activeStorageProviders();
    if (providers.isEmpty) throw Exception('יש להגדיר מקור אחסון פעיל');
    if (syncing) return;

    syncing = true;
    syncMessage = 'ממזג נתונים חסרים בין מקורות האחסון...';
    notifyListeners();
    try {
      final snapshots = await Future.wait(providers.map((provider) => provider.read()));
      final raw = _mergeRepositorySnapshots([
        export(),
        for (final snapshot in snapshots.whereType<StorageSnapshot>()) snapshot.rawData,
      ]);
      restore(raw);
      _dataUpdatedAt = DateTime.now().toUtc();
      await flushNow();
      final canonical = StorageSnapshot(rawData: export(), updatedAt: _dataUpdatedAt);
      for (final provider in providers) {
        await provider.write(canonical);
      }
      _setDirty(false);
      lastSync = DateTime.now();
      syncMessage = 'הסנכרון הושלם: נשמרו ויובאו נתונים חסרים';
    } catch (error) {
      syncMessage = 'שגיאת סנכרון: ${_short(error)}';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> uploadMissingToGitHub() async {
    if (!githubReady) throw Exception('יש לחבר מאגר GitHub לפני ההעלאה');
    if (syncing) return;

    syncing = true;
    syncMessage = 'בודק ומעלה נתונים שחסרים במאגר...';
    notifyListeners();
    try {
      final provider = GitHubJsonStorageProvider(
        owner: githubOwner,
        repository: githubRepo,
        branch: githubBranch,
        token: githubToken,
      );
      final remote = await provider.read();
      final raw = _mergeRepositorySnapshots([
        export(),
        if (remote != null) remote.rawData,
      ]);
      await provider.write(StorageSnapshot.fromRaw(raw));
      lastSync = DateTime.now();
      syncMessage = 'הועלו למאגר הנתונים שחסרו. הנתונים המקומיים לא שונו.';
    } catch (error) {
      syncMessage = 'שגיאת העלאה: ${_short(error)}';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<bool> pullFromGitHub() async {
    final uri =
        Uri.parse(githubUrl).replace(queryParameters: {'ref': githubBranch});
    final response = await http.get(uri, headers: _headers);

    if (response.statusCode == 404) return false;
    if (response.statusCode != 200) {
      throw Exception('GitHub GET ${response.statusCode}: ${response.body}');
    }

    final result = jsonDecode(response.body);
    final content = (result['content'] as String).replaceAll('\n', '');
    final raw = utf8.decode(base64Decode(content));
    if (raw.trim() == '{}' || raw.trim().isEmpty) return false;

    restore(raw);
    await _p.setString('data', raw);
    return true;
  }

  /// העלאת קובץ קטן (תמונת זמר) דרך Contents API.
  Future<String> uploadMediaBytes({
    required String fileName,
    required List<int> bytes,
    String folder = 'songs',
  }) async {
    if (!githubReady)
      throw Exception('יש להגדיר חיבור ל-GitHub לפני העלאת קובץ');
    if (bytes.length > 50 * 1024 * 1024)
      throw Exception('קובץ גדול מדי לתמונה');

    final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final path =
        'media/$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final uri = Uri.parse('$githubApiBase/$path');
    final response = await http.put(
      uri,
      headers: _headers,
      body: jsonEncode({
        'message': 'העלאת מדיה: $safeName',
        'content': base64Encode(bytes),
        'branch': githubBranch,
      }),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
          'GitHub media PUT ${response.statusCode}: ${response.body}');
    }
    return path;
  }

  Future<void> ensureRepositoryStructure() async {
    for (final path in ['data/music_manager.json', 'media/singers/.gitkeep']) {
      final uri = Uri.parse('$githubApiBase/$path');
      final existing = await http.get(
          uri.replace(queryParameters: {'ref': githubBranch}),
          headers: _headers);
      if (existing.statusCode == 200) continue;
      if (existing.statusCode != 404) {
        throw Exception('GitHub GET ${existing.statusCode}: ${existing.body}');
      }
      await http.put(
        uri,
        headers: _headers,
        body: jsonEncode({
          'message': 'יצירת מבנה Music Manager',
          'content':
              base64Encode(utf8.encode(path.endsWith('.json') ? '{}' : '')),
          'branch': githubBranch,
        }),
      );
    }
  }

  Future<void> pushToGitHub() async {
    if (!githubReady) return;

    final uri = Uri.parse(githubUrl);
    String? sha;

    final getResponse = await http.get(
        uri.replace(queryParameters: {'ref': githubBranch}),
        headers: _headers);

    if (getResponse.statusCode == 200) {
      sha = jsonDecode(getResponse.body)['sha'];
    } else if (getResponse.statusCode != 404) {
      throw Exception(
          'GitHub GET ${getResponse.statusCode}: ${getResponse.body}');
    }

    final body = <String, dynamic>{
      'message': 'עדכון נתוני Music Manager',
      'content': base64Encode(utf8.encode(export())),
      'branch': githubBranch,
    };
    if (sha != null) body['sha'] = sha;

    final response =
        await http.put(uri, headers: _headers, body: jsonEncode(body));

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('GitHub PUT ${response.statusCode}: ${response.body}');
    }

    _setDirty(false);
    lastSync = DateTime.now();
    syncMessage = 'הנתונים נשמרו ב-GitHub';
  }

  void setDark(bool v) {
    dark = v;
    darkMode.value = v;
    _p.setBool('dark', v);
    notifyListeners();
  }

  Singer? singer(String id) {
    for (final s in singers) {
      if (s.id == id) return s;
    }
    return null;
  }

  Song? songById(String id) {
    for (final s in songs) {
      if (s.id == id) return s;
    }
    return null;
  }

  Lesson? lessonById(String id) {
    for (final l in lessons) {
      if (l.id == id) return l;
    }
    return null;
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  /// מחיקת הקבצים (מקומי + ענן) – לא חוסם את הממשק
  void _dropFiles(String? localPath, String? assetApi, {MediaFields? except}) {
    final isReferenced = <MediaFields>[...songs, ...lessons, ...unassignedMedia].any(
      (media) => !identical(media, except) &&
          ((localPath != null && media.filePath == localPath) ||
              (assetApi != null && media.assetApi == assetApi)),
    );
    if (isReferenced) return;
    if (localPath != null) deleteMedia(localPath).catchError((_) {});
    if (assetApi != null && githubReady)
      GitHubMedia.deleteAsset(assetApi).catchError((_) {});
  }

  void deleteSinger(Singer s) {
    for (final song in songs.where((x) => x.singerId == s.id).toList()) {
      _removeSong(song);
    }
    singers.remove(s);
    save();
  }

  void _removeSong(Song s) {
    _dropFiles(s.filePath, s.assetApi, except: s);
    songs.remove(s);
    for (final p in playlists) {
      p.songIds.remove(s.id);
    }
  }

  void deleteSong(Song s) {
    _removeSong(s);
    save();
  }

  void deleteLesson(Lesson l) {
    _dropFiles(l.filePath, l.assetApi, except: l);
    _p.remove('pos_${l.id}');
    lessons.remove(l);
    save();
  }

  static String _short(Object e) {
    final s = e.toString().replaceFirst('Exception: ', '');
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }
}

final app = AppState();
