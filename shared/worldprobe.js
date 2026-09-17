/* worldprobe.js — the scene-data debug port shared by the three worlds.
 *
 * Every world exposes window.__world(): a few kB of JSON describing what the
 * page actually built and where it ended up on screen for the camera that is
 * currently set. The hard gates of the polish loop read that JSON instead of a
 * screenshot; pictures are left to the aesthetic gate, which is a throwaway
 * process (see ../AGENTS.md).
 *
 * Classic script, no module, no build — the pages open from file:// too.
 *
 * Schema (schema: 1):
 *   { schema, world, t, camera:{...}, viewport:{w,h,dpr}, render:{...},
 *     objects:[ { name, present, count?, bbox:[x0,y0,z0,x1,y1,z1],
 *                 screen:[x,y,w,h], inView, cover, ...world-specific } ] }
 *   bbox is world space; screen is CSS pixels in the current viewport; cover is
 *   the fraction of the frame the screen rect takes, so "is it there and is it
 *   more than a speck" is one number.
 *
 * A probe reads the same tables the draw code reads, through the same
 * projection the draw code uses. Never give it a second copy of a formula: a
 * mirror that drifts reports a world nobody is rendering.
 */
(function () {
'use strict';

function n2(v) { return Math.round(v * 100) / 100; }
function n4(v) { return Math.round(v * 10000) / 10000; }

function Probe(cfg) {
  this.cfg = cfg;
  this.objects = [];
}

/* points: array of [x,y,z] world samples of the thing — corners of its box, the
 * ends of its trunks, one point per instance. Enough to bound it, not a mesh. */
Probe.prototype.add = function (name, points, extra) {
  var vp = this.cfg.viewport();
  var e = { name: name, present: !!(points && points.length) };
  if (points && points.length) {
    var x0 = Infinity, y0 = Infinity, z0 = Infinity;
    var x1 = -Infinity, y1 = -Infinity, z1 = -Infinity;
    var sx0 = Infinity, sy0 = Infinity, sx1 = -Infinity, sy1 = -Infinity;
    var front = 0, inside = 0;
    for (var i = 0; i < points.length; i++) {
      var p = points[i];
      if (p[0] < x0) x0 = p[0];
      if (p[1] < y0) y0 = p[1];
      if (p[2] < z0) z0 = p[2];
      if (p[0] > x1) x1 = p[0];
      if (p[1] > y1) y1 = p[1];
      if (p[2] > z1) z1 = p[2];
      var s = this.cfg.project(p[0], p[1], p[2]);
      if (!s) continue;
      front++;
      if (s.x >= 0 && s.y >= 0 && s.x <= vp.w && s.y <= vp.h) inside++;
      if (s.x < sx0) sx0 = s.x;
      if (s.y < sy0) sy0 = s.y;
      if (s.x > sx1) sx1 = s.x;
      if (s.y > sy1) sy1 = s.y;
    }
    e.bbox = [n2(x0), n2(y0), n2(z0), n2(x1), n2(y1), n2(z1)];
    if (front) {
      e.screen = [Math.round(sx0), Math.round(sy0), Math.round(sx1 - sx0), Math.round(sy1 - sy0)];
      var ix = Math.min(vp.w, sx1) - Math.max(0, sx0);
      var iy = Math.min(vp.h, sy1) - Math.max(0, sy0);
      /* a single sample has a rect of zero width, so a point inside the frame
       * counts as in view on its own */
      e.inView = inside > 0 || (ix > 0 && iy > 0);
      e.cover = (ix > 0 && iy > 0) ? n4(ix * iy / (vp.w * vp.h)) : 0;
    } else {
      e.screen = null;
      e.inView = false;
      e.cover = 0;
    }
    e.behind = points.length - front;
    /* how many of the samples land inside the frame. For a box that is its
     * corners; for a field of instances it is the answer to "how many of these
     * are actually in this picture". */
    e.inViewCount = inside;
    e.samples = points.length;
  }
  if (extra) for (var k in extra) if (Object.prototype.hasOwnProperty.call(extra, k)) e[k] = extra[k];
  this.objects.push(e);
  return e;
};

/* corners of an axis-aligned box, the usual eight samples */
Probe.prototype.box = function (name, min, max, extra) {
  var pts = [];
  for (var i = 0; i < 8; i++) {
    pts.push([(i & 1) ? max[0] : min[0], (i & 2) ? max[1] : min[1], (i & 4) ? max[2] : min[2]]);
  }
  return this.add(name, pts, extra);
};

window.PoemProbe = {
  n2: n2,
  n4: n4,

  /* cfg: { viewport: () => ({w,h,dpr}), project: (x,y,z) => ({x,y}) | null }
   * collect(probe) fills in objects and returns the head fields. */
  install: function (world, cfg, collect) {
    window.__world = function () {
      var p = new Probe(cfg);
      var head;
      try {
        head = collect(p) || {};
      } catch (err) {
        return { schema: 1, world: world, error: String((err && err.stack) || err) };
      }
      var out = { schema: 1, world: world };
      for (var k in head) if (Object.prototype.hasOwnProperty.call(head, k)) out[k] = head[k];
      out.viewport = cfg.viewport();
      out.objects = p.objects;
      return out;
    };
  }
};

})();
