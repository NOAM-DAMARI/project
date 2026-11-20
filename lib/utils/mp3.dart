/// עזרים לקריאת כותרות MP3 – לזיהוי משך ולחיתוך קבצים גדולים לתמלול.
class Mp3Header {
  final int bitrate; // ביטים לשנייה
  final int sampleRate;
  final int offset;
  Mp3Header(this.bitrate, this.sampleRate, this.offset);
}

Mp3Header? findMp3Header(List<int> bytes, [int from = 0]) {
  const bitratesV1 = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0];
  const bitratesV2 = [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160, 0];
  const rates = [44100, 48000, 32000];
  for (var i = from; i + 4 < bytes.length; i++) {
    if (bytes[i] != 0xFF || (bytes[i + 1] & 0xE0) != 0xE0) continue;
    final version = (bytes[i + 1] >> 3) & 3;
    final layer = (bytes[i + 1] >> 1) & 3;
    final bitrateIndex = (bytes[i + 2] >> 4) & 15;
    final sampleIndex = (bytes[i + 2] >> 2) & 3;
    if (version == 1 || layer != 1 || bitrateIndex == 0 || bitrateIndex == 15 || sampleIndex == 3) continue;
    final bitrate = (version == 3 ? bitratesV1[bitrateIndex] : bitratesV2[bitrateIndex]) * 1000;
    final sampleRate = rates[sampleIndex] >> (version == 3 ? 0 : (version == 2 ? 1 : 2));
    return Mp3Header(bitrate, sampleRate, i);
  }
  return null;
}

/// הערכת משך לפי גודל הקובץ וקצב הסיביות (מדויק לקבצי CBR)
Duration? estimateMp3Duration(List<int> head, int totalBytes) {
  final h = findMp3Header(head);
  if (h == null || h.bitrate == 0) return null;
  return Duration(milliseconds: ((totalBytes - h.offset) * 8 * 1000 / h.bitrate).round());
}

/// מיקום תחילת פריים MP3 קרוב (לחיתוך נקי של הקובץ)
int? findFrameSync(List<int> bytes, int from) => findMp3Header(bytes, from)?.offset;
