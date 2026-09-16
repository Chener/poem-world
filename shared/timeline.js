/* poem-world — shared polish timeline.
 * Reads a JSONL polish log (one round per line) and renders a traceable, collapsible
 * right-hand rail: what changed, what the independent critic said, the biggest
 * remaining gap, and the six fixed-camera shots for that round.
 *
 * Works over http(s) (GitHub Pages) via fetch(). Under file:// fetch is blocked by
 * CORS, so each world also ships log.js, which sets window.__POEM_LOG__ to the same
 * lines; we fall back to that so the page is genuinely "open the file and it works".
 */
(function (global) {
  'use strict';

  function esc(s) {
    return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function parseJsonl(text) {
    var out = [];
    text.split('\n').forEach(function (line) {
      line = line.trim();
      if (!line || line[0] === '#') return;
      try { out.push(JSON.parse(line)); } catch (e) { /* a half-written line is not fatal */ }
    });
    return out;
  }

  function load(url) {
    return fetch(url, { cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.text(); })
      .then(parseJsonl)
      .catch(function () {
        if (global.__POEM_LOG__) return global.__POEM_LOG__.slice();
        return null; // signals "could not read the log", distinct from "log is empty"
      });
  }

  function scoreClass(n) {
    if (n == null) return 'none';
    if (n >= 9) return 'win';
    if (n >= 7) return 'ok';
    if (n >= 5) return 'mid';
    return 'low';
  }

  /* A tiny inline sparkline of critic scores across rounds — the arc of the polish. */
  function sparkline(rounds) {
    var pts = rounds.filter(function (r) { return typeof r.score === 'number'; });
    if (pts.length < 2) return '';
    var W = 220, H = 34, pad = 3;
    var d = pts.map(function (r, i) {
      var x = pad + (W - 2 * pad) * (pts.length === 1 ? 0 : i / (pts.length - 1));
      var y = H - pad - (H - 2 * pad) * (Math.max(0, Math.min(10, r.score)) / 10);
      return (i ? 'L' : 'M') + x.toFixed(1) + ' ' + y.toFixed(1);
    }).join(' ');
    var dots = pts.map(function (r, i) {
      var x = pad + (W - 2 * pad) * (i / (pts.length - 1));
      var y = H - pad - (H - 2 * pad) * (Math.max(0, Math.min(10, r.score)) / 10);
      return '<circle cx="' + x.toFixed(1) + '" cy="' + y.toFixed(1) + '" r="2.4" class="sp-dot ' + scoreClass(r.score) + '"><title>轮 ' + esc(r.round) + '：' + esc(r.score) + '/10</title></circle>';
    }).join('');
    return '<svg class="spark" viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="critic 评分随轮次变化">' +
      '<line x1="' + pad + '" y1="' + (H - pad - (H - 2 * pad) * 0.9) + '" x2="' + (W - pad) + '" y2="' + (H - pad - (H - 2 * pad) * 0.9) + '" class="sp-goal"/>' +
      '<path d="' + d + '" class="sp-line"/>' + dots + '</svg>';
  }

  function renderRound(r, isLast) {
    var shots = Array.isArray(r.shots) ? r.shots : (r.shots ? [r.shots] : []);
    var thumbs = shots.map(function (s, i) {
      var name = (String(s).split('/').pop() || '').replace(/\.png$/, '');
      return '<a class="shot" href="' + esc(s) + '" target="_blank" rel="noopener" title="' + esc(name) + '">' +
        '<img loading="lazy" src="' + esc(s) + '" alt="轮 ' + esc(r.round) + ' 机位 ' + esc(name) + '">' +
        '<span>' + esc(name) + '</span></a>';
    }).join('');

    return '<details class="rnd" ' + (isLast ? 'open' : '') + '>' +
      '<summary>' +
        '<span class="n">' + esc(r.round) + '</span>' +
        '<span class="t">' + esc(r.title || r.changed || '') + '</span>' +
        (typeof r.score === 'number'
          ? '<span class="sc ' + scoreClass(r.score) + '">' + esc(r.score) + '</span>'
          : '<span class="sc none">·</span>') +
      '</summary>' +
      '<div class="body">' +
        (r.at ? '<div class="when">' + esc(r.at) + '</div>' : '') +
        (r.changed ? '<p class="fld"><b>改了</b>' + esc(r.changed) + '</p>' : '') +
        (r.why ? '<p class="fld"><b>为什么</b>' + esc(r.why) + '</p>' : '') +
        (r.critic ? '<blockquote class="critic"><b>critic</b>' + esc(r.critic) + '</blockquote>' : '') +
        (r.gap ? '<p class="fld gap"><b>最大缺口</b>' + esc(r.gap) + '</p>' : '') +
        (r.noticed ? '<p class="fld noticed"><b>顺带看见（留给以后）</b>' + esc(r.noticed) + '</p>' : '') +
        (r.version ? '<p class="fld"><b>快照</b><a href="' + esc(r.version) + '" target="_blank" rel="noopener">' + esc(r.version) + '</a></p>' : '') +
        (thumbs ? '<div class="shots">' + thumbs + '</div>' : '') +
      '</div>' +
    '</details>';
  }

  /** mount({ el, log, onReady }) — el: container, log: url to the .jsonl */
  function mount(opts) {
    var el = typeof opts.el === 'string' ? document.querySelector(opts.el) : opts.el;
    if (!el) return;
    el.innerHTML = '<div class="tl-load">读取打磨记录…</div>';
    return load(opts.log).then(function (rounds) {
      if (rounds === null) {
        el.innerHTML = '<div class="tl-load">读不到 <code>' + esc(opts.log) + '</code>。' +
          '本地直接双击打开时浏览器会挡住读取；用 <code>python3 -m http.server</code> 起一个本地服务，' +
          '或直接看线上版。</div>';
        return null;
      }
      rounds.sort(function (a, b) { return (a.round || 0) - (b.round || 0); });
      var scored = rounds.filter(function (r) { return typeof r.score === 'number'; });
      var best = scored.length ? Math.max.apply(null, scored.map(function (r) { return r.score; })) : null;
      var latest = scored.length ? scored[scored.length - 1].score : null;

      el.innerHTML =
        '<div class="tl-head">' +
          '<div class="tl-stat"><span class="k">轮次</span><b>' + rounds.length + '</b>' +
            (latest != null ? '<span class="k">最新</span><b class="' + scoreClass(latest) + '">' + latest + '/10</b>' : '') +
            (best != null ? '<span class="k">最好</span><b class="' + scoreClass(best) + '">' + best + '/10</b>' : '') +
          '</div>' +
          sparkline(rounds) +
        '</div>' +
        '<div class="tl-rounds">' +
          rounds.map(function (r, i) { return renderRound(r, i === rounds.length - 1); }).join('') +
        '</div>';
      if (opts.onReady) opts.onReady(rounds);
      return rounds;
    });
  }

  global.PolishTimeline = { mount: mount, parseJsonl: parseJsonl };
})(window);
