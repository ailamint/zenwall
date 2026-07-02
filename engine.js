/*
 * Zenwall collage engine — canvas 2D port of the original WallpaperEngine (C#).
 *
 * Aspect-aware weighted tiling: each image picks a chunk size weighted by its
 * orientation (portrait / landscape / square), then takes the grid slot that
 * sits next to the most already-placed neighbours (so the mosaic grows in
 * clusters instead of scattering). Images are drawn object-fit:cover into
 * their slot. A seeded RNG makes every layout reproducible — same seed, same
 * arrangement — which is what powers "re-roll" and the rotation pack.
 *
 * No build step, no modules: attaches a single global `Zenwall`.
 */
(function (global) {
  'use strict';

  // Deterministic PRNG (mulberry32). 32-bit seed in, [0,1) out.
  function mulberry32(seed) {
    let a = seed >>> 0;
    return function () {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  function weightedRandom(weights, rnd) {
    let sum = 0;
    for (let i = 0; i < weights.length; i++) sum += weights[i];
    let r = rnd() * sum;
    for (let i = 0; i < weights.length; i++) {
      if (r < weights[i]) return i;
      r -= weights[i];
    }
    return 0;
  }

  function fits(grid, cw, ch, r, c, rows, cols) {
    if (r + ch > rows || c + cw > cols) return false;
    for (let i = r; i < r + ch; i++)
      for (let j = c; j < c + cw; j++) if (grid[i][j]) return false;
    return true;
  }

  function markOccupied(grid, cw, ch, r, c) {
    for (let i = r; i < r + ch; i++)
      for (let j = c; j < c + cw; j++) grid[i][j] = true;
  }

  // Score every legal slot by neighbour count (favours clustering), nudged
  // toward the top-left, then pick randomly from the best `topK` for variety.
  // In composed (color) mode topK is small so the sorted pool flows cleanly.
  function findBestPosition(grid, cw, ch, rows, cols, rnd, topK) {
    const positions = [];
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        if (fits(grid, cw, ch, r, c, rows, cols)) {
          let neighbors = 0;
          for (let i = Math.max(0, r - 1); i < Math.min(rows, r + ch + 1); i++)
            for (let j = Math.max(0, c - 1); j < Math.min(cols, c + cw + 1); j++)
              if (grid[i][j]) neighbors++;
          const score = neighbors - r * 0.1 - c * 0.05;
          positions.push([score, r, c]);
        }
      }
    }
    if (!positions.length) return null;
    positions.sort((a, b) => b[0] - a[0]);
    const top = positions.slice(0, Math.max(1, topK || 5));
    const pick = top[Math.floor(rnd() * top.length)];
    return [pick[1], pick[2]];
  }

  // Pick a chunk (w,h in grid cells) from the image's orientation profile.
  function chunkForAspect(aspect, rnd) {
    let ws, hs, wt;
    if (aspect < 0.8) {            // portrait
      ws = [1, 1, 2]; hs = [2, 3, 3]; wt = [8, 6, 4];
    } else if (aspect > 1.3) {     // landscape
      ws = [2, 3, 4, 3]; hs = [1, 1, 2, 2]; wt = [8, 6, 4, 6];
    } else {                       // square-ish
      ws = [1, 2, 2, 1]; hs = [1, 2, 1, 2]; wt = [5, 8, 4, 4];
    }
    const i = weightedRandom(wt, rnd);
    return [ws[i], hs[i]];
  }

  function fallbacksForAspect(aspect) {
    if (aspect < 0.8) return [[1, 2], [1, 1], [2, 1]];
    if (aspect > 1.3) return [[2, 1], [1, 1], [1, 2]];
    return [[2, 2], [1, 1], [2, 1], [1, 2]];
  }

  // Trim pure black (#000000) or pure white (#FFFFFF) borders baked into the
  // source — letterbox bars and the white/black canvas margins common on
  // illustrations. Scan inward from each edge counting whole rows/columns that
  // are (near-)uniformly black or white; stop at the first line that breaks into
  // real colour — the content boundary, which flips the whole line at once. Each
  // edge is counted INDEPENDENTLY, so a subject that bleeds off one edge doesn't
  // stop the others. Coloured photos/art (no black/white frame) trim nothing; a
  // per-side cap plus an all-sides-maxed guard keep a solid black/white image
  // from being gutted. Returns a source rect in original pixel coords.
  function detectContentRect(img, iw, ih) {
    const MAX = 150;         // downscale target — high enough to keep thin borders
    const CAP = 0.45;        // hard cap per side, fraction of dimension
    const BLACK = 17;        // all channels <= this → a black pixel
    const WHITE = 238;       // all channels >= this → a white pixel
    const HIT = 0.985;       // fraction of a line that must be black OR white
    const full = { sx: 0, sy: 0, sw: iw, sh: ih };
    const scale = Math.min(1, MAX / Math.max(iw, ih));
    const w = Math.max(8, Math.round(iw * scale));
    const h = Math.max(8, Math.round(ih * scale));
    let data;
    try {
      const cv = document.createElement('canvas');
      cv.width = w; cv.height = h;
      const c = cv.getContext('2d', { willReadFrequently: true });
      // Nearest-neighbor keeps the border crisp so a near-white margin stays
      // white instead of blending into a grey that fails the test.
      c.imageSmoothingEnabled = false;
      c.drawImage(img, 0, 0, w, h);
      data = c.getImageData(0, 0, w, h).data;
    } catch (e) {
      return full; // tainted canvas (CORS) — leave the image alone
    }

    // Is the row/column at `fixed` uniformly black OR uniformly white?
    function isBorder(fixed, isRow) {
      const n = isRow ? w : h;
      let black = 0, white = 0;
      for (let k = 0; k < n; k++) {
        const i = (isRow ? (fixed * w + k) : (k * w + fixed)) * 4;
        const r = data[i], g = data[i + 1], b = data[i + 2];
        if (r <= BLACK && g <= BLACK && b <= BLACK) black++;
        else if (r >= WHITE && g >= WHITE && b >= WHITE) white++;
      }
      return black / n >= HIT || white / n >= HIT;
    }
    // Count border lines from one edge inward, up to the cap.
    function countEdge(isRow, fromStart, cap) {
      const last = isRow ? h - 1 : w - 1;
      let t = 0;
      while (t < cap && isBorder(fromStart ? t : last - t, isRow)) t++;
      return t;
    }

    const capV = Math.floor(h * CAP);
    const capH = Math.floor(w * CAP);
    const top = countEdge(true, true, capV);
    const bot = countEdge(true, false, capV);
    const left = countEdge(false, true, capH);
    const right = countEdge(false, false, capH);

    if (!top && !bot && !left && !right) return full;
    // Whole image reads as black/white (a blank/near-blank tile) → leave alone.
    if (top >= capV && bot >= capV && left >= capH && right >= capH) return full;

    const sx = Math.round((left / w) * iw);
    const sy = Math.round((top / h) * ih);
    const sw = Math.max(1, iw - sx - Math.round((right / w) * iw));
    const sh = Math.max(1, ih - sy - Math.round((bot / h) * ih));
    if (sw < iw * 0.1 || sh < ih * 0.1) return full; // degenerate crop guard
    return { sx: sx, sy: sy, sw: sw, sh: sh };
  }

  // Draw `img` to cover the rect (x,y,w,h), centre-cropped, clipped to the rect.
  // `src` is the source-pixel rect to use (letterbox crop or full image).
  function drawCover(ctx, img, x, y, w, h, src) {
    const sw = src.sw, sh = src.sh;
    const targetAspect = w / h;
    const srcAspect = sw / sh;
    let ssx, ssy, ssw, ssh;
    if (srcAspect > targetAspect) {
      ssh = sh; ssw = sh * targetAspect;
      ssx = src.sx + (sw - ssw) / 2; ssy = src.sy;
    } else {
      ssw = sw; ssh = sw / targetAspect;
      ssx = src.sx; ssy = src.sy + (sh - ssh) / 2;
    }
    ctx.save();
    ctx.beginPath();
    ctx.rect(x, y, w, h);
    ctx.clip();
    ctx.drawImage(img, ssx, ssy, ssw, ssh, x, y, w, h);
    ctx.restore();
  }

  /*
   * render(canvas, images, opts)
   *   images : array of loaded <img> (or {img, naturalWidth, naturalHeight}),
   *            each optionally carrying a `_col` color signature (see Palette).
   *   opts   : { width, height, cols, gap, bg, seed, arrange, hueShift }
   *            cols sets density; rows is derived for ~square cells.
   *            arrange: 'color' (default, composed) | 'shuffle' (random).
   *            hueShift: 0..1, rotates the color spectrum (defaults to seed-derived).
   * returns  : { rows, cols, placed, seed }
   */
  function render(canvas, images, opts) {
    const width = opts.width;
    const height = opts.height;
    const cols = Math.max(2, opts.cols | 0);
    const gap = opts.gap == null ? 6 : opts.gap;
    const bg = opts.bg || '#000000';
    const seed = (opts.seed == null ? Date.now() : opts.seed) >>> 0;
    const arrange = opts.arrange || 'color';
    // Default hue rotation is derived from the seed, so each re-roll rotates the
    // palette (a different color leads) while staying composed.
    const hueShift = opts.hueShift == null ? ((seed % 997) / 997) : opts.hueShift;

    const rows = Math.max(1, Math.round(cols * (height / width)));

    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = 'high';
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, width, height);

    const cellW = (width - (cols - 1) * gap) / cols;
    const cellH = (height - (rows - 1) * gap) / rows;

    const grid = [];
    for (let r = 0; r < rows; r++) grid.push(new Array(cols).fill(false));

    const rnd = mulberry32(seed);

    // Order the pool. Composed mode (default) sorts by color so similar hues sit
    // together and the mosaic reads as color fields; a tight placement (topK=1)
    // keeps that flow clean. Shuffle mode is the old random arrangement.
    let imgs;
    let topK;
    if (arrange === 'color' && global.Palette) {
      imgs = global.Palette.compose(images, (it) => (it.img || it)._col, { hueShift: hueShift });
      topK = 1;
    } else {
      // Seeded Fisher–Yates shuffle so the pool order is reproducible too.
      imgs = images.slice();
      for (let i = imgs.length - 1; i > 0; i--) {
        const j = Math.floor(rnd() * (i + 1));
        const t = imgs[i]; imgs[i] = imgs[j]; imgs[j] = t;
      }
      topK = 5;
    }

    let idx = 0;
    let attempts = 0;
    const maxAttempts = imgs.length * 3;
    let freeCells = rows * cols;

    while (idx < imgs.length && attempts < maxAttempts && freeCells > 0) {
      attempts++;
      const item = imgs[idx];
      const img = item.img || item;
      const iw = item.naturalWidth || img.naturalWidth;
      const ih = item.naturalHeight || img.naturalHeight;
      if (!iw || !ih) { idx++; continue; }

      // Cache the letterbox-crop rect on the img so re-rolls are cheap.
      if (!img._crop) img._crop = detectContentRect(img, iw, ih);
      const crop = img._crop;
      const aspect = crop.sw / crop.sh;
      let [chunkW, chunkH] = chunkForAspect(aspect, rnd);
      let pos = findBestPosition(grid, chunkW, chunkH, rows, cols, rnd, topK);

      if (!pos) {
        const fbs = fallbacksForAspect(aspect);
        for (let f = 0; f < fbs.length; f++) {
          const p = findBestPosition(grid, fbs[f][0], fbs[f][1], rows, cols, rnd, topK);
          if (p) { chunkW = fbs[f][0]; chunkH = fbs[f][1]; pos = p; break; }
        }
      }

      if (pos) {
        const row = pos[0];
        const col = pos[1];
        idx++;
        const w = chunkW * cellW + (chunkW - 1) * gap;
        const h = chunkH * cellH + (chunkH - 1) * gap;
        const x = col * (cellW + gap);
        const y = row * (cellH + gap);
        drawCover(ctx, img, x, y, w, h, crop);
        markOccupied(grid, chunkW, chunkH, row, col);
        freeCells -= chunkW * chunkH;
      } else {
        // Couldn't place even a 1x1 fallback — grid is effectively full.
        break;
      }
    }

    return { rows: rows, cols: cols, placed: idx, seed: seed };
  }

  global.Zenwall = { render: render, mulberry32: mulberry32 };
})(window);
