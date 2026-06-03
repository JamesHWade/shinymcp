/* =============================================================================
 * shinymcp — live "MCP App inside AI chat" demo for the pkgdown home page
 * Drop in at:  pkgdown/extra.js   (loaded on every page; only runs on home)
 * Mounts into: <div id="smc-demo"></div>  (placed in index.md)
 * Pure vanilla JS — no dependencies.
 * ========================================================================== */
(function () {
  "use strict";

  function init() {
    var mount = document.getElementById("smc-demo");
    if (!mount || mount.dataset.smcReady) return;
    mount.dataset.smcReady = "1";

    // ---- deterministic Palmer Penguins sample --------------------------------
    function mulberry32(a) {
      return function () {
        a |= 0; a = (a + 0x6D2B79F5) | 0;
        var t = Math.imul(a ^ (a >>> 15), 1 | a);
        t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
      };
    }
    var rng = mulberry32(616);
    function gauss(m, sd) {
      var u = 0, v = 0;
      while (u === 0) u = rng();
      while (v === 0) v = rng();
      return m + sd * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
    }
    var SPEC = {
      Adelie:    { n: 50, bill_length_mm: [38.8, 2.7], bill_depth_mm: [18.3, 1.2], flipper_length_mm: [190, 6.5], body_mass_g: [3700, 460] },
      Chinstrap: { n: 34, bill_length_mm: [48.8, 3.3], bill_depth_mm: [18.4, 1.1], flipper_length_mm: [196, 7.1], body_mass_g: [3733, 384] },
      Gentoo:    { n: 44, bill_length_mm: [47.5, 3.1], bill_depth_mm: [15.0, 1.0], flipper_length_mm: [217, 6.5], body_mass_g: [5076, 504] }
    };
    var COLORS = { Adelie: "#ff6b35", Chinstrap: "#7b2d8e", Gentoo: "#0f7173" };
    var LABELS = { bill_length_mm: "Bill Length (mm)", bill_depth_mm: "Bill Depth (mm)", flipper_length_mm: "Flipper Length (mm)", body_mass_g: "Body Mass (g)" };
    var DATA = [];
    Object.keys(SPEC).forEach(function (sp) {
      var s = SPEC[sp];
      for (var i = 0; i < s.n; i++) DATA.push({
        species: sp,
        bill_length_mm: +gauss(s.bill_length_mm[0], s.bill_length_mm[1]).toFixed(1),
        bill_depth_mm: +gauss(s.bill_depth_mm[0], s.bill_depth_mm[1]).toFixed(1),
        flipper_length_mm: Math.round(gauss(s.flipper_length_mm[0], s.flipper_length_mm[1])),
        body_mass_g: Math.round(gauss(s.body_mass_g[0], s.body_mass_g[1]) / 25) * 25
      });
    });

    // ---- helpers -------------------------------------------------------------
    function fmt(v) { return Math.abs(v) >= 100 ? Math.round(v).toString() : v.toFixed(1); }
    function quant(arr) {
      var a = arr.slice().sort(function (x, y) { return x - y; });
      function q(p) { var idx = p * (a.length - 1), lo = Math.floor(idx), hi = Math.ceil(idx); return a[lo] + (a[hi] - a[lo]) * (idx - lo); }
      var mean = a.reduce(function (s, v) { return s + v; }, 0) / a.length;
      return { min: a[0], med: q(0.5), mean: mean, max: a[a.length - 1] };
    }
    function linreg(pts) {
      var n = pts.length; if (n < 2) return null;
      var sx = 0, sy = 0, sxx = 0, sxy = 0;
      pts.forEach(function (p) { sx += p[0]; sy += p[1]; sxx += p[0] * p[0]; sxy += p[0] * p[1]; });
      var d = n * sxx - sx * sx; if (d === 0) return null;
      var m = (n * sxy - sx * sy) / d;
      return { m: m, b: (sy - m * sx) / n };
    }

    function drawScatter(canvas, st) {
      if (!canvas) return;
      var ratio = window.devicePixelRatio || 1;
      var W = canvas.clientWidth, H = canvas.clientHeight;
      if (!W || !H) return;
      canvas.width = W * ratio; canvas.height = H * ratio;
      var ctx = canvas.getContext("2d");
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.clearRect(0, 0, W, H);
      ctx.fillStyle = "#ffffff"; ctx.fillRect(0, 0, W, H);

      var data = st.species === "All" ? DATA : DATA.filter(function (d) { return d.species === st.species; });
      var xs = data.map(function (d) { return d[st.xVar]; });
      var ys = data.map(function (d) { return d[st.yVar]; });
      var pad = { l: 52, r: 14, t: 14, b: 52 };
      var xmin = Math.min.apply(null, xs), xmax = Math.max.apply(null, xs);
      var ymin = Math.min.apply(null, ys), ymax = Math.max.apply(null, ys);
      var xr = (xmax - xmin) || 1, yr = (ymax - ymin) || 1;
      var x0 = xmin - xr * 0.06, x1 = xmax + xr * 0.06, y0 = ymin - yr * 0.08, y1 = ymax + yr * 0.08;
      function px(v) { return pad.l + ((v - x0) / (x1 - x0)) * (W - pad.l - pad.r); }
      function py(v) { return H - pad.b - ((v - y0) / (y1 - y0)) * (H - pad.t - pad.b); }
      function nice(lo, hi, n) { var step = (hi - lo) / n, o = []; for (var i = 0; i <= n; i++) o.push(lo + step * i); return o; }

      ctx.strokeStyle = "#eceff3"; ctx.fillStyle = "#9aa6b4"; ctx.lineWidth = 1;
      ctx.font = "11px 'JetBrains Mono', monospace"; ctx.textAlign = "right"; ctx.textBaseline = "middle";
      nice(y0, y1, 4).forEach(function (v) { var Y = py(v); ctx.beginPath(); ctx.moveTo(pad.l, Y); ctx.lineTo(W - pad.r, Y); ctx.stroke(); ctx.fillText(fmt(v), pad.l - 8, Y); });
      ctx.textAlign = "center"; ctx.textBaseline = "top";
      nice(x0, x1, 4).forEach(function (v) { ctx.fillText(fmt(v), px(v), H - pad.b + 8); });

      ctx.fillStyle = "#57637a"; ctx.font = "600 12px Inter, sans-serif"; ctx.textAlign = "center"; ctx.textBaseline = "alphabetic";
      ctx.fillText(LABELS[st.xVar], pad.l + (W - pad.l - pad.r) / 2, H - 12);
      ctx.save(); ctx.translate(14, pad.t + (H - pad.t - pad.b) / 2); ctx.rotate(-Math.PI / 2); ctx.fillText(LABELS[st.yVar], 0, 0); ctx.restore();

      var groups = st.species === "All" ? ["Adelie", "Chinstrap", "Gentoo"] : [st.species];
      groups.forEach(function (sp) {
        ctx.fillStyle = COLORS[sp];
        data.filter(function (d) { return d.species === sp; }).forEach(function (d) {
          ctx.globalAlpha = 0.72; ctx.beginPath(); ctx.arc(px(d[st.xVar]), py(d[st.yVar]), 3.6, 0, Math.PI * 2); ctx.fill();
        });
        ctx.globalAlpha = 1;
        if (st.trend) {
          var fit = linreg(data.filter(function (d) { return d.species === sp; }).map(function (d) { return [d[st.xVar], d[st.yVar]]; }));
          if (fit) { ctx.strokeStyle = COLORS[sp]; ctx.lineWidth = 2; ctx.beginPath(); ctx.moveTo(px(x0), py(fit.m * x0 + fit.b)); ctx.lineTo(px(x1), py(fit.m * x1 + fit.b)); ctx.stroke(); }
        }
      });
    }

    function buildStats(st) {
      var data = st.species === "All" ? DATA : DATA.filter(function (d) { return d.species === st.species; });
      var sx = quant(data.map(function (d) { return d[st.xVar]; }));
      var sy = quant(data.map(function (d) { return d[st.yVar]; }));
      var counts = ["Adelie", "Chinstrap", "Gentoo"].map(function (sp) { return [sp, data.filter(function (d) { return d.species === sp; }).length]; }).filter(function (c) { return c[1] > 0; });
      function pad(s, n) { s = String(s); while (s.length < n) s = " " + s; return s; }
      function rpad(s, n) { s = String(s); while (s.length < n) s = s + " "; return s; }
      function row(label, s) { return rpad(label, 16) + " min " + pad(fmt(s.min), 5) + "   med " + pad(fmt(s.med), 5) + "   mean " + pad(fmt(s.mean), 5) + "   max " + pad(fmt(s.max), 5); }
      return [
        "Observations: " + data.length + " penguins", "",
        row(LABELS[st.xVar].replace(/ \(.*/, ""), sx),
        row(LABELS[st.yVar].replace(/ \(.*/, ""), sy), "",
        "species   " + counts.map(function (c) { return c[0] + ":" + c[1]; }).join("   ")
      ].join("\n");
    }

    // ---- markup --------------------------------------------------------------
    var varOpts = Object.keys(LABELS);
    function opts(sel) { return varOpts.map(function (v) { return '<option value="' + v + '"' + (v === sel ? " selected" : "") + ">" + LABELS[v] + "</option>"; }).join(""); }
    var logo = (mount.getAttribute("data-logo") || "logo.png");

    mount.innerHTML =
      '<div class="smc-winbar"><div class="smc-dots"><i></i><i></i><i></i></div>' +
      '<span class="smc-winurl">claude · penguins-explorer</span></div>' +
      '<div class="smc-chat">' +
        '<div class="row-user"><div class="smc-bubble-user">Explore the penguins dataset — plot flipper length vs body mass, colored by species.</div></div>' +
        '<div class="row-asst">' +
          '<div class="smc-asst-mark"><img src="' + logo + '" alt=""></div>' +
          '<div class="smc-asst-body">' +
            '<p class="smc-asst-text">Here\'s an interactive explorer. Adjust the inputs and I\'ll recompute in R:</p>' +
            '<div class="smc-toolcall">⚡ <span>called <code>explore_penguins</code></span> <span class="ok">200 OK</span></div>' +
            '<div class="smc-mcp">' +
              '<div class="smc-mcp-bar"><span class="smc-mcp-title">Palmer Penguins Explorer</span><span class="smc-mcp-badge"><span class="dot"></span>MCP App</span></div>' +
              '<div class="smc-mcp-body">' +
                '<div class="smc-mcp-side">' +
                  '<label class="smc-field"><span>Species</span><select data-k="species"><option>All</option><option>Adelie</option><option>Chinstrap</option><option>Gentoo</option></select></label>' +
                  '<label class="smc-field"><span>X axis</span><select data-k="xVar">' + opts("flipper_length_mm") + '</select></label>' +
                  '<label class="smc-field"><span>Y axis</span><select data-k="yVar">' + opts("body_mass_g") + '</select></label>' +
                  '<label class="smc-check"><input type="checkbox" data-k="trend"><span>Show trend line</span></label>' +
                '</div>' +
                '<div class="smc-mcp-main">' +
                  '<div class="smc-mcp-card"><div class="smc-mcp-head">Scatter Plot</div><div class="smc-plot-wrap"><canvas class="smc-canvas"></canvas><div class="smc-running" style="display:none"><span class="smc-spin"></span>running <code>explore_penguins()</code></div></div></div>' +
                  '<div class="smc-mcp-card"><div class="smc-mcp-head">Summary Statistics</div><pre class="smc-stats"></pre></div>' +
                '</div>' +
              '</div>' +
            '</div>' +
          '</div>' +
        '</div>' +
      '</div>';

    // ---- state machine -------------------------------------------------------
    var st = { species: "All", xVar: "flipper_length_mm", yVar: "body_mass_g", trend: false };
    var applied = Object.assign({}, st);
    var canvas = mount.querySelector(".smc-canvas");
    var running = mount.querySelector(".smc-running");
    var statsEl = mount.querySelector(".smc-stats");
    var timer = null;

    function render() { drawScatter(canvas, applied); statsEl.textContent = buildStats(applied); }
    function commit() {
      running.style.display = "flex";
      if (timer) clearTimeout(timer);
      timer = setTimeout(function () { applied = Object.assign({}, st); running.style.display = "none"; render(); }, 480);
    }
    mount.querySelectorAll("[data-k]").forEach(function (el) {
      el.addEventListener("change", function () {
        var k = el.getAttribute("data-k");
        st[k] = el.type === "checkbox" ? el.checked : el.value;
        commit();
      });
    });
    render();
    window.addEventListener("resize", function () { drawScatter(canvas, applied); });
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
