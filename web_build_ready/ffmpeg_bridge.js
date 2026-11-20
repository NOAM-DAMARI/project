// גשר ל-ffmpeg.wasm – נטען לפי דרישה רק כשמשתמשים בחיתוך/הפחתת רעש.
// מנוע ראשי: ffmpeg.wasm 0.11.6 + core-st (נבדק, עובד בלי SharedArrayBuffer). גיבוי: ffmpeg.wasm 0.12.
(function () {
  const BASE = 'https://unpkg.com/@ffmpeg/ffmpeg@0.12.10/dist/umd';
  const CORE = 'https://unpkg.com/@ffmpeg/core@0.12.6/dist/umd';
  const LEGACY = 'https://unpkg.com/@ffmpeg/ffmpeg@0.11.6/dist/ffmpeg.min.js';
  const LEGACY_CORE = 'https://unpkg.com/@ffmpeg/core-st@0.11.1/dist/ffmpeg-core.js';
  let loading = null;

  function loadScript(src) {
    return new Promise((ok, fail) => {
      const s = document.createElement('script');
      s.src = src; s.crossOrigin = 'anonymous';
      s.onload = ok; s.onerror = () => fail(new Error('טעינת FFmpeg נכשלה'));
      document.head.appendChild(s);
    });
  }
  async function toBlobURL(url, type) {
    const r = await fetch(url);
    if (!r.ok) throw new Error('טעינת FFmpeg נכשלה (' + r.status + ')');
    return URL.createObjectURL(new Blob([await r.arrayBuffer()], { type }));
  }

  async function loadModern() {
    if (!window.FFmpegWASM) await loadScript(BASE + '/ffmpeg.js');
    const ff = new FFmpegWASM.FFmpeg();
    await ff.load({
      classWorkerURL: await toBlobURL(BASE + '/814.ffmpeg.js', 'text/javascript'),
      coreURL: await toBlobURL(CORE + '/ffmpeg-core.js', 'text/javascript'),
      wasmURL: await toBlobURL(CORE + '/ffmpeg-core.wasm', 'application/wasm'),
    });
    return {
      async run(input, inName, outName, args) {
        await ff.writeFile(inName, input);
        try {
          const code = await ff.exec(Array.from(args));
          if (code !== 0) throw new Error('ffmpeg exit ' + code);
          return await ff.readFile(outName);
        } finally {
          try { await ff.deleteFile(inName); } catch (_) {}
          try { await ff.deleteFile(outName); } catch (_) {}
        }
      },
    };
  }

  async function loadLegacy() {
    if (!window.FFmpeg || !window.FFmpeg.createFFmpeg) await loadScript(LEGACY);
    const ff = FFmpeg.createFFmpeg({ log: false, corePath: LEGACY_CORE, mainName: 'main' });
    await ff.load();
    let queue = Promise.resolve();
    return {
      run(input, inName, outName, args) {
        const job = queue.then(async () => {
          ff.FS('writeFile', inName, input);
          try {
            await ff.run(...Array.from(args));
            return ff.FS('readFile', outName);
          } finally {
            try { ff.FS('unlink', inName); } catch (_) {}
            try { ff.FS('unlink', outName); } catch (_) {}
          }
        });
        queue = job.catch(() => {});
        return job;
      },
    };
  }

  function get() {
    if (!loading) {
      loading = loadLegacy()
        .catch((e) => { console.warn('FFmpeg 0.11 failed, trying 0.12', e); return loadModern(); })
        .catch((e) => { loading = null; throw e; });
    }
    return loading;
  }

  window.lessonFfmpeg = {
    available: async () => { try { await get(); return true; } catch (_) { return false; } },
    run: async (input, inName, outName, argsJson) => (await get()).run(input, inName, outName, JSON.parse(argsJson)),
  };
})();
