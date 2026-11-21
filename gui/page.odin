package frostrig_gui

import "core:fmt"
import "core:strings"

// The 3D viewer is a single self-contained page: one HTML document, no CDN, no
// build step.  It polls /gui/trace and renders the torus matrix with a Canvas
// 2D painter, so it works on any browser the operator has on hand.
//
// The raw strings below must stay backtick-free, which is why the page uses
// plain string concatenation instead of template literals.

// page_html returns the self-contained viewer document.  `token` is the
// per-process secret the page echoes back on every /gui/trace poll; it is
// spliced into the script so a scanner that never loads the page cannot read
// walk coordinates.
page_html :: proc(token: string) -> string {
	head := `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>frostrig Worm/2 - 3D walk</title>
<style>
html, body { margin: 0; padding: 0; height: 100%; background: #070a12;
  color: #cfd8e3; font: 12px/1.45 ui-monospace, "Cascadia Mono", Consolas, monospace;
  overflow: hidden; }
#c { position: fixed; inset: 0; display: block; cursor: grab; }
#c.drag { cursor: grabbing; }
#hud { position: fixed; top: 10px; left: 10px; padding: 8px 10px;
  background: rgba(10, 14, 24, 0.72); border: 1px solid #1d2636;
  border-radius: 4px; white-space: pre; pointer-events: none; }
#help { position: fixed; right: 12px; bottom: 10px; padding: 6px 9px;
  background: rgba(10, 14, 24, 0.72); border: 1px solid #1d2636;
  border-radius: 4px; pointer-events: none; color: #7f8ea3; }
</style>
</head>
<body>
<canvas id="c"></canvas>
<div id="hud">connecting...</div>
<div id="help">drag rotate &nbsp;|&nbsp; wheel / pinch zoom &nbsp;|&nbsp; double-click reset</div>
<script>
`
	body_start := `
(function () {
  var cv = document.getElementById('c');
  var g = cv.getContext('2d');
  var hud = document.getElementById('hud');
  var W = 0, H = 0, DPR = 1;
`
	token_line := fmt.tprintf("  var TRACE_TOKEN = %q;\n", token)
	body_rest := `
  function resize() {
    DPR = window.devicePixelRatio || 1;
    W = window.innerWidth;
    H = window.innerHeight;
    cv.width = Math.round(W * DPR);
    cv.height = Math.round(H * DPR);
    cv.style.width = W + 'px';
    cv.style.height = H + 'px';
    g.setTransform(DPR, 0, 0, DPR, 0, 0);
  }
  window.addEventListener('resize', resize);
  resize();

  // ---- camera -------------------------------------------------------------
  var yaw = -0.62, pitch = 0.46, zoom = 1.0;

  function rotY(x, y, z, a) {
    var ca = Math.cos(a), sa = Math.sin(a);
    return [x * ca + z * sa, y, -x * sa + z * ca];
  }
  function rotX(x, y, z, a) {
    var ca = Math.cos(a), sa = Math.sin(a);
    return [x, y * ca - z * sa, y * sa + z * ca];
  }
  function project(x, y, z) {
    var r = rotY(x, y, z, yaw);
    r = rotX(r[0], r[1], r[2], pitch);
    var s = zoom * (H / 2) / (1 + r[2] / 260);
    return [W / 2 + r[0] * s, H / 2 - r[1] * s];
  }

  // ---- trace state --------------------------------------------------------
  // dims comes from the server so a shrunken matrix (FROSTRIG_WORM2_ROWS)
  // still fills the frame instead of being drawn as a fixed 1024x1024 grid.
  var dims = { rows: 1024, cols: 1024, layers: 2 };
  var cell = 1024;
  var trail = [];
  var stride = 1;
  var steps = 0, hashes = 0;
  var lastH = 0, lastHT = performance.now(), rate = 0;

  function fmtRate() {
    if (rate >= 1e6) return (rate / 1e6).toFixed(2) + ' M';
    if (rate >= 1e3) return (rate / 1e3).toFixed(1) + ' k';
    return rate.toFixed(0);
  }

  function rebuildLattice() {
    var pts = [];
    var rs = Math.min(dims.rows, 96), cs = Math.min(dims.cols, 96);
    var lz = Math.min(dims.layers, 4);
    for (var l = 0; l < lz; l++) {
      var zc = (l - (lz - 1) / 2) * 22;
      for (var r = 0; r < rs; r++) {
        for (var c = 0; c < cs; c++) {
          var xc = (c - (cs - 1) / 2) * 2.2;
          var yc = (r - (rs - 1) / 2) * 2.2;
          var p = project(xc, yc, zc);
          pts.push(p[0], p[1]);
        }
      }
    }
    return pts;
  }

  function updateHud() {
    var cur = trail.length ? trail[trail.length - 1] : null;
    var curTxt = cur ? ('(' + cur.x + ',' + cur.y + ',' + cur.z + ')') : '(--)';
    hud.textContent =
      'frostrig  Worm/2  3D walk' + '\n' +
      'grid      ' + dims.rows + ' x ' + dims.cols + ' x ' + dims.layers +
        ' cells of ' + cell + ' bytes' + '\n' +
      'walk      step ' + steps + '  (' + stride + ' steps per marked cell)' + '\n' +
      'hashes    ' + hashes + '  ' + fmtRate() + ' H/s' + '\n' +
      'worm      ' + curTxt + '   trail ' + trail.length + ' cells';
  }

  function draw() {
    g.clearRect(0, 0, W, H);
    g.fillStyle = '#070a12';
    g.fillRect(0, 0, W, H);

    // faint lattice
    var pts = rebuildLattice();
    g.fillStyle = 'rgba(60, 80, 120, 0.25)';
    for (var i = 0; i < pts.length; i += 2) {
      g.fillRect(pts[i], pts[i + 1], 1, 1);
    }

    // trail, oldest faintest
    for (var i = 0; i < trail.length; i++) {
      var c = trail[i];
      var a = 0.15 + 0.85 * (i + 1) / trail.length;
      var p = project((c.x - dims.rows / 2) * 0.05, (c.y - dims.cols / 2) * 0.05,
        (c.z - (dims.layers - 1) / 2) * 12);
      var r = 2 + 4 * a;
      g.beginPath();
      g.arc(p[0], p[1], r, 0, Math.PI * 2);
      g.fillStyle = 'rgba(80, 220, 160, ' + a.toFixed(3) + ')';
      g.fill();
    }
    requestAnimationFrame(draw);
  }

  function poll() {
    fetch('/gui/trace', { cache: 'no-store', headers: { 'X-Trace-Token': TRACE_TOKEN } })
      .then(function (r) { return r.json(); })
      .then(function (t) {
        var changed = t.rows !== dims.rows || t.cols !== dims.cols || t.layers !== dims.layers;
        dims = { rows: t.rows, cols: t.cols, layers: t.layers };
        cell = t.cell || cell;
        if (changed) rebuildLattice();
        trail = t.trail || [];
        stride = t.stride || 1;
        steps = t.steps || 0;
        hashes = t.hashes || 0;
        var now = performance.now();
        if (now - lastHT >= 1000) {
          rate = (hashes - lastH) * 1000 / (now - lastHT);
          lastH = hashes;
          lastHT = now;
        }
        updateHud();
      })
      .catch(function () {
        hud.textContent = 'trace unavailable';
      });
  }

  // ---- input --------------------------------------------------------------
  var dragging = false, px = 0, py = 0;
  cv.addEventListener('mousedown', function (e) {
    dragging = true; px = e.clientX; py = e.clientY;
    cv.classList.add('drag');
  });
  window.addEventListener('mouseup', function () {
    dragging = false; cv.classList.remove('drag');
  });
  window.addEventListener('mousemove', function (e) {
    if (!dragging) return;
    yaw += (e.clientX - px) * 0.005;
    pitch += (e.clientY - py) * 0.005;
    pitch = Math.max(-1.5, Math.min(1.5, pitch));
    px = e.clientX; py = e.clientY;
  });
  cv.addEventListener('wheel', function (e) {
    e.preventDefault();
    zoom *= e.deltaY < 0 ? 1.1 : 0.9;
    zoom = Math.max(0.2, Math.min(6, zoom));
  }, { passive: false });
  cv.addEventListener('dblclick', function () {
    yaw = -0.62; pitch = 0.46; zoom = 1.0;
  });
  cv.addEventListener('touchstart', function (e) {
    if (e.touches.length === 1) {
      px = e.touches[0].clientX; py = e.touches[0].clientY;
    }
  }, { passive: true });
  cv.addEventListener('touchmove', function (e) {
    if (e.touches.length === 1) {
      var tx = e.touches[0].clientX, ty = e.touches[0].clientY;
      yaw += (tx - px) * 0.005;
      pitch += (ty - py) * 0.005;
      pitch = Math.max(-1.5, Math.min(1.5, pitch));
      px = tx; py = ty;
    }
  }, { passive: true });

  poll();
  setInterval(poll, 100);
  draw();
})();
`
	tail := "</script>\\n</body>\\n</html>\\n"
	return strings.concatenate([]string{head, body_start, token_line, body_rest, tail})
}
