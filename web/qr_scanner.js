// Camera capture and QR decoding for the web app.
// Frames are grabbed from a <video> element and decoded by zxing-cpp compiled
// to WebAssembly (bundled under zxing/, no CDN needed). Dart only receives the
// decoded text.
(function () {
  'use strict';

  let prepared = false;
  const state = {
    stream: null,
    running: false,
    canvas: null,
    ctx: null,
    frames: 0,
    generation: 0,
  };

  function prepare() {
    if (prepared) return;
    prepared = true;
    ZXingWASM.prepareZXingModule({
      overrides: {
        locateFile: (path, prefix) =>
          path.endsWith('.wasm')
            ? new URL('zxing/' + path, document.baseURI).href
            : prefix + path,
      },
      fireImmediately: true,
    });
  }

  const readerOptions = {
    formats: ['QRCode'],
    tryHarder: false,
    tryRotate: false,
    tryInvert: false,
    tryDownscale: true,
    maxNumberOfSymbols: 1,
  };

  function nextFrame(video) {
    return new Promise((resolve) => {
      if (typeof video.requestVideoFrameCallback === 'function') {
        video.requestVideoFrameCallback(() => resolve());
      } else {
        setTimeout(resolve, 30);
      }
    });
  }

  async function loop(video, onText, generation) {
    while (state.running && state.generation === generation) {
      const w = video.videoWidth;
      const h = video.videoHeight;
      if (video.readyState >= 2 && w > 0 && h > 0) {
        // Scan the centred square only, like the native apps.
        const side = Math.min(w, h);
        if (!state.canvas || state.canvas.width !== side) {
          state.canvas = document.createElement('canvas');
          state.canvas.width = side;
          state.canvas.height = side;
          state.ctx = state.canvas.getContext('2d', { willReadFrequently: true });
        }
        state.ctx.drawImage(video, (w - side) / 2, (h - side) / 2, side, side, 0, 0, side, side);
        const image = state.ctx.getImageData(0, 0, side, side);
        try {
          const results = await ZXingWASM.readBarcodes(image, readerOptions);
          state.frames++;
          for (const r of results) {
            if (r.isValid && r.text) onText(r.text);
          }
        } catch (e) {
          console.warn('QR decode failed', e);
        }
      }
      await nextFrame(video);
    }
  }

  async function start(video, deviceId, onText) {
    prepare();
    await stop();
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      throw new Error('Dieser Browser erlaubt keinen Kamerazugriff (HTTPS nötig).');
    }
    const size = { width: { ideal: 1920 }, height: { ideal: 1080 } };
    const video_constraints = deviceId
      ? { deviceId: { exact: deviceId }, ...size }
      : { facingMode: { ideal: 'environment' }, ...size };
    const stream = await navigator.mediaDevices.getUserMedia({ audio: false, video: video_constraints });
    state.stream = stream;
    video.setAttribute('playsinline', '');
    video.setAttribute('autoplay', '');
    video.muted = true;
    video.srcObject = stream;
    await video.play();
    state.running = true;
    state.generation++;
    loop(video, onText, state.generation);
    const settings = stream.getVideoTracks()[0].getSettings();
    return JSON.stringify({
      deviceId: settings.deviceId || null,
      width: settings.width || 0,
      height: settings.height || 0,
      facingMode: settings.facingMode || null,
    });
  }

  async function stop() {
    state.running = false;
    if (state.stream) {
      for (const track of state.stream.getTracks()) track.stop();
      state.stream = null;
    }
  }

  async function listCameras() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.enumerateDevices) return '[]';
    const devices = await navigator.mediaDevices.enumerateDevices();
    return JSON.stringify(
      devices.filter((d) => d.kind === 'videoinput').map((d) => ({ id: d.deviceId, label: d.label })),
    );
  }

  function framesAnalyzed() {
    return state.frames;
  }

  window.instantShareScanner = { start, stop, listCameras, framesAnalyzed };
})();
