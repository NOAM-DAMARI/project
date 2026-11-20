import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import '../models/item.dart';
import '../models/media.dart';
import 'app_state.dart';
import 'media_resolver.dart';

enum TrackKind { song, lesson }

enum LoopSetting { off, all, one }

class Track {
  final String id;
  final TrackKind kind;
  final String title, subtitle;
  final MediaFields media;
  final int? color;
  Track(this.id, this.kind, this.title, this.subtitle, this.media,
      {this.color});

  /// פריט מהרשימה (שיעור או שיר) – רק שם וקובץ, בלי פרטים נוספים
  factory Track.item(Item i) => Track(
        i.id,
        i.kind == ItemKind.lesson ? TrackKind.lesson : TrackKind.song,
        i.title,
        i.kind == ItemKind.lesson ? 'שיעור' : 'שיר',
        i,
      );
}

/// נגן אחד לכל האפליקציה – ההשמעה ממשיכה גם כשעוברים בין מסכים.
class PlayerService extends ChangeNotifier {
  static final AndroidLoudnessEnhancer? _boost =
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          ? AndroidLoudnessEnhancer()
          : null;
  final AudioPlayer p = AudioPlayer(
    audioPipeline:
        _boost == null ? null : AudioPipeline(androidAudioEffects: [_boost!]),
  );
  final _rnd = Random();

  List<Track> queue = [];
  int index = -1;
  final List<int> _history = [];

  bool shuffle = false;
  LoopSetting repeat = LoopSetting.off;

  bool loading = false;
  double? downloadProgress;
  String? error;

  Timer? _sleepTimer;
  DateTime? sleepAt;
  bool sleepAtEnd = false;

  int _loadToken = 0;

  /// מסך הנגן המלא של השיר/שיעור הנוכחי פתוח – מסתירים את הנגן המוקטן
  final fullScreenOpen = ValueNotifier<String?>(null);

  /// נקרא ממסכי הנגן המלא. נדחה למיקרו-משימה כדי לא לעדכן ממשק באמצע בנייה.
  void markFullScreen(String id, bool open) => Future.microtask(() {
        if (open) {
          fullScreenOpen.value = id;
        } else if (fullScreenOpen.value == id) {
          fullScreenOpen.value = null;
        }
      });

  static const speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  PlayerService() {
    p.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onCompleted();
    });
  }

  Timer? _posTimer;
  Timer? _segmentTimer;

  Track? get current =>
      index >= 0 && index < queue.length ? queue[index] : null;
  bool isCurrent(String id) => current?.id == id;
  bool get hasNext =>
      queue.length > 1 &&
      (shuffle || index + 1 < queue.length || repeat == LoopSetting.all);

  /// השמעת רשימה (רשימת השמעה / כל השירים של זמר וכו')
  Future<void> playQueue(List<Track> tracks,
      {int start = 0, bool shuffled = false}) async {
    if (tracks.isEmpty) return;
    _savePosition();
    queue = [...tracks];
    _history.clear();
    shuffle = shuffled;
    index = shuffled
        ? _rnd.nextInt(queue.length)
        : start.clamp(0, queue.length - 1);
    await _load(autoplay: true);
  }

  /// הוספת פריט לסוף התור בלי לעצור את הפריט שמתנגן כעת.
  void enqueue(Track track) {
    if (queue.any((item) => item.id == track.id)) return;
    queue = [...queue, track];
    notifyListeners();
  }

  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= queue.length || newIndex < 0 || newIndex >= queue.length) return;
    final items = [...queue];
    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);
    if (index == oldIndex) {
      index = newIndex;
    } else if (oldIndex < index && newIndex >= index) {
      index--;
    } else if (oldIndex > index && newIndex <= index) {
      index++;
    }
    queue = items;
    notifyListeners();
  }

  void removeQueuedTrack(int queueIndex) {
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    if (queueIndex == index && p.playing) p.pause();
    queue = [...queue]..removeAt(queueIndex);
    if (queue.isEmpty) {
      index = -1;
    } else if (queueIndex < index) {
      index--;
    } else if (queueIndex == index) {
      index = index.clamp(0, queue.length - 1).toInt();
    }
    notifyListeners();
  }

  /// פתיחת שיר/שיעור בודד. אם הוא כבר נטען – רק ממשיכים.
  Future<void> open(Track t, {bool autoplay = true}) async {
    if (isCurrent(t.id) && error == null) {
      if (autoplay && !p.playing) p.play();
      return;
    }
    _savePosition();
    final inQueue = queue.indexWhere((x) => x.id == t.id);
    if (inQueue >= 0) {
      _history.add(index);
      index = inQueue;
    } else {
      queue = [t];
      index = 0;
      _history.clear();
    }
    await _load(autoplay: autoplay);
  }

  StreamSubscription<Duration>? _segSub;

  /// סוף הקטע שמתנגן כרגע (null = ניגון רגיל)
  int? segmentEndMs;

  /// ניגון קטע בלבד: מתחיל ב-[startMs] ועוצר אוטומטית ב-[endMs] לפי מיקום הנגן
  /// (עובד נכון גם במהירות x2 וגם אחרי דילוגים).
  Future<void> playSegment(Track track, int startMs, int endMs) async {
    _segmentTimer?.cancel();
    await _segSub?.cancel();
    if (!isCurrent(track.id) || error != null)
      await open(track, autoplay: false);
    if (!isCurrent(track.id) || error != null) return;
    await p.seek(Duration(milliseconds: startMs));
    segmentEndMs = endMs > startMs ? endMs : null;
    if (segmentEndMs != null) _watchSegment(track, segmentEndMs!);
    notifyListeners();
    unawaited(p.play());
  }

  void _watchSegment(Track track, int endMs) {
    segmentEndMs = endMs;
    _segSub?.cancel();
    _segSub = p.positionStream.listen((position) {
      if (!isCurrent(track.id) || segmentEndMs == null) return;
      if (position.inMilliseconds >= endMs) {
        p.pause();
        segmentEndMs = null;
        _segSub?.cancel();
        notifyListeners();
      }
    });
  }

  void cancelSegment() {
    segmentEndMs = null;
    _segSub?.cancel();
    notifyListeners();
  }

  Future<void> retry() => _load(autoplay: true);

  Future<void> _load({required bool autoplay}) async {
    final t = current;
    if (t == null) return;
    final token = ++_loadToken;
    _posTimer ??=
        Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
    error = null;
    loading = true;
    downloadProgress = null;
    notifyListeners();

    try {
      await _segSub?.cancel();
      segmentEndMs = null;
      await p.stop();
      final local = MediaResolver.availableLocally(t.media);
      if (local != null) {
        await p.setFilePath(local);
      } else if (t.media.remoteUrl != null) {
        // הזרמה ישירה (מהיר); אם נכשל (למשל מאגר פרטי) – מורידים ומנגנים מהמכשיר
        try {
          await p.setUrl(t.media.remoteUrl!,
              headers: MediaResolver.streamHeaders(t.media.remoteUrl!));
        } catch (_) {
          if (kIsWeb || token != _loadToken) rethrow;
          await _downloadThenSet(t, token);
        }
      } else if (t.media.assetApi != null && !kIsWeb) {
        await _downloadThenSet(t, token);
      } else {
        throw Exception('לא הועלה קובץ שמע');
      }
      if (token != _loadToken) return;

      await p
          .setLoopMode(repeat == LoopSetting.one ? LoopMode.one : LoopMode.off);
      final speed = app.prefs.getDouble('speed_${t.kind.name}') ?? 1.0;
      await p.setSpeed(speed);
      final savedVolume = app.prefs.getDouble('player_volume');
      if (savedVolume != null) await setVolume(savedVolume);
      if (t.media.isClip) {
        await p.seek(Duration(milliseconds: t.media.clipStartMs!));
        _watchSegment(t, t.media.clipEndMs!);
      } else if (t.kind == TrackKind.lesson) {
        final saved = app.prefs.getInt('pos_${t.id}');
        if (saved != null && saved > 5000)
          await p.seek(Duration(milliseconds: saved));
      }
      loading = false;
      downloadProgress = null;
      notifyListeners();
      if (autoplay) unawaited(p.play());
    } catch (e) {
      if (token != _loadToken) return;
      loading = false;
      downloadProgress = null;
      error = _friendly(e);
      notifyListeners();
    }
  }

  Future<void> _downloadThenSet(Track t, int token) async {
    var lastPct = -1;
    final path =
        await MediaResolver.ensureLocal(t.media, onProgress: (got, total) {
      if (token != _loadToken || total == null) return;
      final pct = got * 100 ~/ total;
      if (pct != lastPct) {
        lastPct = pct;
        downloadProgress = got / total;
        notifyListeners();
      }
    });
    if (path == null) throw Exception('לא ניתן להוריד את הקובץ');
    if (token == _loadToken) {
      if (kIsWeb) {
        await p.setUrl(path);
      } else {
        await p.setFilePath(path);
      }
    }
  }

  double get volume => _volume;

  /// מקסימום עוצמה: באנדרואיד עד 200% (מגבר עוצמה), בשאר הפלטפורמות 100%.
  double get maxVolume => _boost != null ? 2.0 : 1.0;
  double _volume = 1.0;

  Future<void> volumeStep(double delta) => setVolume(volume + delta);

  /// השתקה וחזרה לעוצמה הקודמת
  double _beforeMute = 1.0;
  bool get muted => _volume == 0;
  Future<void> toggleMute() async {
    if (muted) {
      await setVolume(_beforeMute <= 0 ? 1.0 : _beforeMute);
    } else {
      _beforeMute = _volume;
      await setVolume(0);
    }
  }

  Future<void> setVolume(double value) async {
    final next = value.clamp(0.0, maxVolume).toDouble();
    _volume = next;
    await p.setVolume(next.clamp(0.0, 1.0).toDouble());
    final boost = _boost;
    if (boost != null) {
      try {
        // 0dB עד 100%, ומעליו עד כ-+12dB
        await boost.setEnabled(next > 1.0);
        if (next > 1.0) await boost.setTargetGain((next - 1.0) * 12.0);
      } catch (_) {}
    }
    await app.prefs.setDouble('player_volume', next);
    notifyListeners();
  }

  void togglePlay() {
    if (current == null) return;
    if (error != null) {
      retry();
    } else if (p.playing) {
      p.pause();
    } else {
      p.play();
    }
  }

  Future<void> next({bool auto = false}) async {
    if (queue.isEmpty) return;
    int? n;
    if (shuffle && queue.length > 1) {
      do {
        n = _rnd.nextInt(queue.length);
      } while (n == index);
    } else if (index + 1 < queue.length) {
      n = index + 1;
    } else if (repeat == LoopSetting.all) {
      n = 0;
    }
    if (n == null) {
      if (auto) {
        await p.pause();
        await p.seek(Duration.zero);
      }
      return;
    }
    _savePosition();
    _history.add(index);
    index = n;
    await _load(autoplay: true);
  }

  Future<void> previous() async {
    if (p.position > const Duration(seconds: 3) || queue.length <= 1) {
      await p.seek(Duration.zero);
      return;
    }
    _savePosition();
    index = _history.isNotEmpty
        ? _history.removeLast()
        : (index - 1 + queue.length) % queue.length;
    await _load(autoplay: true);
  }

  void skip(int seconds) {
    var t = p.position + Duration(seconds: seconds);
    final d = p.duration ?? Duration.zero;
    if (t < Duration.zero) t = Duration.zero;
    if (d > Duration.zero && t > d) t = d;
    p.seek(t);
  }

  Future<void> seekTo(Track t, int ms) async {
    if (!isCurrent(t.id)) await open(t);
    await p.seek(Duration(milliseconds: ms));
    if (!p.playing) unawaited(p.play());
  }

  void setSpeed(double v) {
    p.setSpeed(v);
    final t = current;
    if (t != null) app.prefs.setDouble('speed_${t.kind.name}', v);
    notifyListeners();
  }

  void toggleShuffle() {
    shuffle = !shuffle;
    notifyListeners();
  }

  void cycleRepeat() {
    repeat = LoopSetting.values[(repeat.index + 1) % LoopSetting.values.length];
    p.setLoopMode(repeat == LoopSetting.one ? LoopMode.one : LoopMode.off);
    notifyListeners();
  }

  /// טיימר שינה: null = ביטול, Duration.zero = בסוף הקטע הנוכחי
  void setSleep(Duration? d) {
    _sleepTimer?.cancel();
    sleepAt = null;
    sleepAtEnd = false;
    if (d == Duration.zero) {
      sleepAtEnd = true;
    } else if (d != null) {
      sleepAt = DateTime.now().add(d);
      _sleepTimer = Timer(d, () {
        p.pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  bool get sleepActive => sleepAt != null || sleepAtEnd;

  Future<void> close() async {
    _savePosition();
    _loadToken++;
    await p.stop();
    queue = [];
    index = -1;
    error = null;
    loading = false;
    setSleep(null);
    notifyListeners();
  }

  /// המשך האזנה לשיעורים – נשמר מקומית
  int? savedPosition(String lessonId) => app.prefs.getInt('pos_$lessonId');

  void _savePosition() {
    final t = current;
    if (t == null || t.kind != TrackKind.lesson || loading || error != null)
      return;
    final pos = p.position.inMilliseconds;
    if (pos > 5000) app.prefs.setInt('pos_${t.id}', pos);
  }

  void _onCompleted() {
    final t = current;
    if (t != null && t.kind == TrackKind.lesson)
      app.prefs.remove('pos_${t.id}');
    if (sleepAtEnd) {
      sleepAtEnd = false;
      p.pause();
      p.seek(Duration.zero);
      notifyListeners();
      return;
    }
    next(auto: true);
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('SocketException') || s.contains('Failed host lookup'))
      return 'אין חיבור לאינטרנט';
    if (s.contains('(404)') || s.contains('404')) return 'הקובץ לא נמצא בענן';
    if (s.contains('Source error') || s.contains('PlayerException'))
      return 'לא ניתן לנגן את הקובץ';
    return s.replaceFirst('Exception: ', '');
  }
}

final player = PlayerService();
