// shinymcp host
//
// The host side of the MCP Apps protocol (2026-01-26). A host loads an app's
// page into a sandboxed iframe, answers the page's requests, and passes its
// tool calls and resource reads on to the app's MCP server.
//
// window.shinymcpHost.create(options) makes one host. shinymcp uses it in
// two places:
//
// * Shiny pages that embed apps (mcp_host_ui(), mcp_embed(), and shinychat
//   tool cards). The glue at the end of this file sends requests to R over
//   the Shiny session.
// * preview_app(), whose page sends requests to the app's HTTP endpoint.
//
// The iframe is sandboxed without allow-same-origin, so the page runs in an
// opaque origin and can reach the host only through postMessage. Its
// Content Security Policy is built from the resource's _meta.ui.csp the way
// the MCP Apps specification describes, so an app that works here makes no
// network requests a chat client would block.
//
// Written in ES5 without dependencies.
(function () {
  "use strict";

  if (window.shinymcpHost && window.shinymcpHost.create) return;

  var APPS_PROTOCOL_VERSION = "2026-01-26";
  var SANDBOX = "allow-scripts allow-forms allow-popups allow-popups-to-escape-sandbox";

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------

  function each(list, fn) {
    if (!list) return;
    for (var i = 0; i < list.length; i++) fn(list[i], i);
  }

  function keys(obj) {
    return obj && typeof obj === "object" ? Object.keys(obj) : [];
  }

  function assign(target) {
    for (var i = 1; i < arguments.length; i++) {
      var src = arguments[i];
      if (!src) continue;
      var k = keys(src);
      for (var j = 0; j < k.length; j++) target[k[j]] = src[k[j]];
    }
    return target;
  }

  function compact(obj) {
    var out = {};
    each(keys(obj), function (k) {
      if (obj[k] !== undefined && obj[k] !== null) out[k] = obj[k];
    });
    return out;
  }

  function sameJson(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
  }

  function errorMessage(err) {
    if (!err) return "Unknown error";
    if (typeof err === "string") return err;
    return err.message || String(err);
  }

  function logWarn() {
    if (window.console && console.warn) {
      console.warn.apply(console, ["[shinymcp host]"].concat(Array.prototype.slice.call(arguments)));
    }
  }

  // ---------------------------------------------------------------------------
  // Content Security Policy and permissions
  // ---------------------------------------------------------------------------

  function domains(list) {
    var out = [];
    each(Array.isArray(list) ? list : [], function (d) {
      // Keep the policy well formed: no whitespace, quotes, or separators.
      if (typeof d === "string" && /^[^\s;,'"]+$/.test(d)) out.push(d);
    });
    return out.join(" ");
  }

  // The policy the MCP Apps specification tells hosts to apply.
  function buildCsp(csp) {
    csp = csp || {};
    var resources = domains(csp.resourceDomains);
    var connect = domains(csp.connectDomains);
    var frames = domains(csp.frameDomains);
    var bases = domains(csp.baseUriDomains);
    function join() {
      return Array.prototype.slice.call(arguments).filter(Boolean).join(" ");
    }
    return [
      "default-src 'none'",
      join("script-src 'self' 'unsafe-inline'", resources),
      join("style-src 'self' 'unsafe-inline'", resources),
      join("connect-src 'self'", connect),
      join("img-src 'self' data: blob:", resources),
      join("font-src 'self' data:", resources),
      join("media-src 'self' data: blob:", resources),
      "frame-src " + (frames || "'none'"),
      "object-src 'none'",
      "base-uri " + (bases || "'self'")
    ].join("; ");
  }

  function escapeAttribute(s) {
    return String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  }

  // Put the policy in a <meta> tag at the top of <head>, before anything the
  // page loads.
  function withCsp(html, csp) {
    var meta = '<meta http-equiv="Content-Security-Policy" content="' + escapeAttribute(buildCsp(csp)) + '">';
    html = String(html || "");
    var head = /<head(\s[^>]*)?>/i.exec(html);
    if (head) {
      var at = head.index + head[0].length;
      return html.slice(0, at) + meta + html.slice(at);
    }
    var root = /<html(\s[^>]*)?>/i.exec(html);
    if (root) {
      var after = root.index + root[0].length;
      return html.slice(0, after) + "<head>" + meta + "</head>" + html.slice(after);
    }
    return meta + html;
  }

  function allowAttribute(permissions) {
    var allow = [];
    permissions = permissions || {};
    if (permissions.camera) allow.push("camera");
    if (permissions.microphone) allow.push("microphone");
    if (permissions.geolocation) allow.push("geolocation");
    if (permissions.clipboardWrite) allow.push("clipboard-write");
    return allow.join("; ");
  }

  // ---------------------------------------------------------------------------
  // Theme and styles of the page hosting the app
  // ---------------------------------------------------------------------------

  function pageTheme() {
    var nodes = [document.documentElement, document.body];
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      if (!el) continue;
      var t = el.getAttribute("data-bs-theme") || el.getAttribute("data-theme");
      if (t === "dark" || t === "light") return t;
    }
    if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) return "dark";
    return "light";
  }

  // A Bootstrap 5 page (bslib) describes its palette and type in CSS
  // variables; pass them on so the app matches the page around it.
  var BOOTSTRAP_STYLES = {
    "--color-background-primary": "--bs-body-bg",
    "--color-background-secondary": "--bs-secondary-bg",
    "--color-background-tertiary": "--bs-tertiary-bg",
    "--color-text-primary": "--bs-body-color",
    "--color-text-secondary": "--bs-secondary-color",
    "--color-text-danger": "--bs-danger-text-emphasis",
    "--color-background-danger": "--bs-danger-bg-subtle",
    "--color-border-danger": "--bs-danger-border-subtle",
    "--color-border-primary": "--bs-border-color",
    "--color-ring-primary": "--bs-primary",
    "--font-sans": "--bs-body-font-family",
    "--font-mono": "--bs-font-monospace",
    "--border-radius-sm": "--bs-border-radius-sm",
    "--border-radius-md": "--bs-border-radius",
    "--border-radius-lg": "--bs-border-radius-lg"
  };

  function bootstrapStyles() {
    if (!window.getComputedStyle || !document.body) return null;
    var computed = window.getComputedStyle(document.body);
    if (!computed.getPropertyValue("--bs-body-bg")) return null;
    var variables = {};
    each(keys(BOOTSTRAP_STYLES), function (name) {
      var value = computed.getPropertyValue(BOOTSTRAP_STYLES[name]);
      value = value ? value.trim() : "";
      if (value) variables[name] = value;
    });
    return keys(variables).length ? { variables: variables } : null;
  }

  // ---------------------------------------------------------------------------
  // Fullscreen: the browser's own, or a fixed overlay where that fails
  // ---------------------------------------------------------------------------

  function fullscreenElement() {
    return document.fullscreenElement || document.webkitFullscreenElement || null;
  }

  function requestFullscreen(el) {
    var fn = el.requestFullscreen || el.webkitRequestFullscreen;
    if (!fn) return null;
    try {
      return fn.call(el) || null;
    } catch (e) {
      return null;
    }
  }

  function exitFullscreen() {
    var fn = document.exitFullscreen || document.webkitExitFullscreen;
    if (fn && fullscreenElement()) {
      try {
        fn.call(document);
      } catch (e) {
        // Nothing to do.
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Downloads the app asks for (ui/download-file)
  // ---------------------------------------------------------------------------

  function fileNameFromUri(uri) {
    var name = String(uri || "").split(/[\\/]/).pop() || "download";
    try {
      name = decodeURIComponent(name);
    } catch (e) {
      // Keep the raw name.
    }
    return name.replace(/[\u0000-\u001f<>:"|?*]/g, "_") || "download";
  }

  function base64ToBlob(data, type) {
    var bytes = atob(String(data));
    var array = new Uint8Array(bytes.length);
    for (var i = 0; i < bytes.length; i++) array[i] = bytes.charCodeAt(i);
    return new Blob([array], { type: type || "application/octet-stream" });
  }

  function saveBlob(blob, name) {
    var url = URL.createObjectURL(blob);
    var a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.rel = "noopener";
    a.style.display = "none";
    document.body.appendChild(a);
    a.click();
    setTimeout(function () {
      URL.revokeObjectURL(url);
      if (a.parentNode) a.parentNode.removeChild(a);
    }, 1000);
  }

  function isSafeUrl(url) {
    return typeof url === "string" && /^(https?:|mailto:)/i.test(url);
  }

  function downloadContents(contents) {
    var saved = 0;
    each(Array.isArray(contents) ? contents : [], function (item) {
      if (!item) return;
      if (item.type === "resource" && item.resource) {
        var r = item.resource;
        var name = fileNameFromUri(r.uri);
        var blob = typeof r.blob === "string"
          ? base64ToBlob(r.blob, r.mimeType)
          : new Blob([r.text === undefined ? "" : String(r.text)], { type: r.mimeType || "text/plain" });
        saveBlob(blob, name);
        saved++;
      } else if (item.type === "resource_link" && isSafeUrl(item.uri)) {
        window.open(item.uri, "_blank", "noopener,noreferrer");
        saved++;
      }
    });
    return saved;
  }

  // ---------------------------------------------------------------------------
  // The host
  // ---------------------------------------------------------------------------

  // options:
  //   container    Element around the iframe; it goes full screen.
  //   iframe       The iframe to load the app into (created if missing).
  //   html         The app's HTML (the ui:// resource's text).
  //   csp, permissions
  //                The resource's _meta.ui.csp and _meta.ui.permissions.
  //   height       "auto" to follow the app's size, or a CSS height.
  //   maxHeight    Largest height, in pixels, for "auto".
  //   tool         Definition of the tool whose call opened the app.
  //   toolInput    Arguments of that call.
  //   toolResult   Its result, a promise of it, or a function returning one.
  //                Sent to the app once it has initialized.
  //   send(message)
  //                Pass a JSON-RPC request to the MCP server. Returns a
  //                promise of the JSON-RPC response.
  //   canCallTool(name)
  //                Whether the app may call a tool (its visibility includes
  //                "app"). Calls it may not make are refused.
  //   hostInfo     {name, version}
  //   theme()      The theme to report; defaults to the page's.
  //   styles()     Style variables to report, {variables, css}.
  //   onEvent(type, detail, host)
  //                "model-context", "message", "tool-call", "log", "size",
  //                "display-mode", "open-link", "download", "error",
  //                "initialized", "busy".
  //   onTraffic(direction, message)
  //                Every message to and from the app ("in" or "out").
  function create(options) {
    var opts = options || {};
    var container = opts.container;
    var iframe = opts.iframe;
    if (!iframe) {
      iframe = document.createElement("iframe");
      (container || document.body).appendChild(iframe);
    }

    var hostInfo = opts.hostInfo || { name: "shinymcp", version: "0" };
    var autoHeight = !opts.height || opts.height === "auto";
    var state = {
      initialized: false,
      disposed: false,
      outbox: [],
      nextId: 1,
      pending: {},
      displayMode: "inline",
      overlay: false,
      context: null,
      modelContext: null,
      busy: 0,
      lastHeight: 0
    };

    // -- Messaging ------------------------------------------------------------

    function post(message) {
      if (state.disposed || !iframe.contentWindow) return;
      if (opts.onTraffic) opts.onTraffic("out", message);
      iframe.contentWindow.postMessage(message, "*");
    }

    function respond(id, result) {
      post({ jsonrpc: "2.0", id: id, result: result || {} });
    }

    function respondError(id, code, message, data) {
      var error = { code: code, message: message };
      if (data !== undefined) error.data = data;
      post({ jsonrpc: "2.0", id: id, error: error });
    }

    // The specification forbids sending anything before the app says it
    // has initialized; hold messages until then.
    function notify(method, params) {
      var message = { jsonrpc: "2.0", method: method, params: params || {} };
      if (!state.initialized) {
        state.outbox.push(message);
        return;
      }
      post(message);
    }

    function request(method, params, timeoutMs) {
      return new Promise(function (resolve, reject) {
        if (state.disposed || !state.initialized) {
          reject(new Error("The app is not running."));
          return;
        }
        var id = "host-" + state.nextId++;
        var timer = null;
        if (timeoutMs) {
          timer = setTimeout(function () {
            delete state.pending[id];
            reject(new Error("The app did not answer " + method + "."));
          }, timeoutMs);
        }
        state.pending[id] = {
          resolve: function (v) {
            if (timer) clearTimeout(timer);
            resolve(v);
          },
          reject: function (e) {
            if (timer) clearTimeout(timer);
            reject(e);
          }
        };
        post({ jsonrpc: "2.0", id: id, method: method, params: params || {} });
      });
    }

    function emit(type, detail) {
      if (typeof opts.onEvent === "function") {
        try {
          opts.onEvent(type, detail, host);
        } catch (e) {
          logWarn("event handler failed for " + type, e);
        }
      }
    }

    function setBusy(delta) {
      var before = state.busy > 0;
      state.busy = Math.max(0, state.busy + delta);
      var after = state.busy > 0;
      if (before !== after) emit("busy", after);
    }

    // Forward a request to the MCP server and relay the answer to the app.
    function forward(message) {
      if (typeof opts.send !== "function") {
        respondError(message.id, -32601, "This host has no MCP server connection.");
        return;
      }
      setBusy(1);
      var forwarded = { jsonrpc: "2.0", id: message.id, method: message.method, params: message.params || {} };
      Promise.resolve()
        .then(function () {
          return opts.send(forwarded);
        })
        .then(
          function (response) {
            setBusy(-1);
            response = response || {};
            if (message.method === "tools/call") {
              emit("tool-call", {
                caller: "app",
                name: forwarded.params.name,
                arguments: forwarded.params.arguments || {},
                result: response.result,
                error: response.error
              });
            }
            if (response.error) {
              respondError(message.id, response.error.code || -32603, response.error.message || "Request failed", response.error.data);
            } else {
              respond(message.id, response.result);
            }
          },
          function (err) {
            setBusy(-1);
            emit("error", { message: errorMessage(err), method: message.method });
            respondError(message.id, -32603, errorMessage(err));
          }
        );
    }

    // -- Host context ---------------------------------------------------------

    function containerDimensions() {
      var width = Math.round((container || iframe).clientWidth || iframe.clientWidth || 0);
      var dims = {};
      if (state.displayMode === "fullscreen") {
        dims.height = window.innerHeight;
      } else if (autoHeight) {
        if (opts.maxHeight) dims.maxHeight = opts.maxHeight;
      } else {
        dims.height = Math.round(iframe.clientHeight);
      }
      if (width > 0) dims.width = width;
      return dims;
    }

    function buildContext() {
      var theme = typeof opts.theme === "function" ? opts.theme() : pageTheme();
      var styles = typeof opts.styles === "function" ? opts.styles(theme) : bootstrapStyles();
      var timeZone;
      try {
        timeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      } catch (e) {
        timeZone = undefined;
      }
      return compact({
        toolInfo: opts.tool ? { tool: opts.tool } : undefined,
        theme: theme,
        styles: styles || undefined,
        displayMode: state.displayMode,
        availableDisplayModes: ["inline", "fullscreen"],
        containerDimensions: containerDimensions(),
        locale: navigator.language || undefined,
        timeZone: timeZone,
        userAgent: hostInfo.name,
        platform: "web",
        deviceCapabilities: {
          touch: "ontouchstart" in window || (navigator.maxTouchPoints || 0) > 0,
          hover: !!(window.matchMedia && window.matchMedia("(hover: hover)").matches)
        }
      });
    }

    // Tell the app what changed since the last context it saw.
    function refreshContext() {
      if (state.disposed || !state.initialized) return;
      var next = buildContext();
      var changes = {};
      var any = false;
      each(keys(next), function (k) {
        if (!state.context || !sameJson(state.context[k], next[k])) {
          changes[k] = next[k];
          any = true;
        }
      });
      state.context = next;
      if (any) notify("ui/notifications/host-context-changed", changes);
    }

    function capabilities() {
      return {
        openLinks: {},
        downloadFile: {},
        serverTools: {},
        serverResources: {},
        logging: {},
        updateModelContext: { text: {}, structuredContent: {} },
        message: { text: {} },
        sandbox: compact({
          permissions: opts.permissions || undefined,
          csp: opts.csp || undefined
        })
      };
    }

    // -- Display modes --------------------------------------------------------

    function setDisplayMode(mode) {
      var target = container || iframe;
      if (mode === state.displayMode) return mode;
      if (mode === "fullscreen") {
        state.displayMode = "fullscreen";
        var requested = requestFullscreen(target);
        if (requested && typeof requested.then === "function") {
          requested.then(null, function () {
            enterOverlay();
          });
        } else if (!fullscreenElement()) {
          enterOverlay();
        }
      } else {
        state.displayMode = "inline";
        if (state.overlay) leaveOverlay();
        if (fullscreenElement() === target) exitFullscreen();
      }
      applyHeight();
      emit("display-mode", state.displayMode);
      setTimeout(refreshContext, 50);
      return state.displayMode;
    }

    function enterOverlay() {
      state.overlay = true;
      (container || iframe).setAttribute("data-shinymcp-fullscreen", "");
      document.addEventListener("keydown", onKeydown);
    }

    function leaveOverlay() {
      state.overlay = false;
      (container || iframe).removeAttribute("data-shinymcp-fullscreen");
      document.removeEventListener("keydown", onKeydown);
    }

    function onKeydown(e) {
      if (e.key === "Escape" && state.overlay) setDisplayMode("inline");
    }

    function onFullscreenChange() {
      var target = container || iframe;
      if (state.displayMode === "fullscreen" && !state.overlay && fullscreenElement() !== target) {
        state.displayMode = "inline";
        applyHeight();
        emit("display-mode", state.displayMode);
        refreshContext();
      }
    }

    function applyHeight() {
      if (state.displayMode === "fullscreen") {
        iframe.style.height = "100%";
      } else if (autoHeight) {
        iframe.style.height = (state.lastHeight || 0) > 0 ? state.lastHeight + "px" : "";
      } else {
        iframe.style.height = String(opts.height);
      }
    }

    // -- Requests and notifications from the app -----------------------------

    function handleRequest(msg) {
      var params = msg.params || {};
      switch (msg.method) {
        case "ui/initialize":
          if (state.initialized) {
            // The page reloaded (its frame was moved or re-rendered). Start
            // over and send it the tool call again.
            state.initialized = false;
            state.outbox = [];
            if (state.sentInput !== undefined) deliverToolInput(state.sentInput);
            if (state.sentResult !== undefined) deliverToolResult(state.sentResult);
          }
          state.context = buildContext();
          respond(msg.id, {
            protocolVersion: APPS_PROTOCOL_VERSION,
            hostInfo: hostInfo,
            hostCapabilities: capabilities(),
            hostContext: state.context
          });
          return;

        case "ping":
          respond(msg.id, {});
          return;

        case "tools/call":
          if (typeof opts.canCallTool === "function" && !opts.canCallTool(params.name)) {
            respondError(msg.id, -32602, "The app can't call the tool " + JSON.stringify(params.name) + ".");
            return;
          }
          forward(msg);
          return;

        case "resources/read":
        case "resources/list":
        case "resources/templates/list":
          forward(msg);
          return;

        case "ui/update-model-context":
          // Each update replaces the one before.
          state.modelContext = params;
          emit("model-context", params);
          respond(msg.id, {});
          return;

        case "ui/message":
          emit("message", params);
          respond(msg.id, {});
          return;

        case "ui/open-link":
          if (!isSafeUrl(params.url)) {
            respond(msg.id, { isError: true });
            return;
          }
          emit("open-link", params.url);
          window.open(params.url, "_blank", "noopener,noreferrer");
          respond(msg.id, {});
          return;

        case "ui/request-display-mode":
          respond(msg.id, { mode: setDisplayMode(params.mode === "fullscreen" ? "fullscreen" : "inline") });
          return;

        case "ui/download-file":
          try {
            var saved = downloadContents(params.contents);
            emit("download", params.contents);
            respond(msg.id, saved ? {} : { isError: true });
          } catch (e) {
            respondError(msg.id, -32603, "Download failed: " + errorMessage(e));
          }
          return;

        default:
          respondError(msg.id, -32601, "Method not supported by this host: " + msg.method);
      }
    }

    function handleNotification(msg) {
      var params = msg.params || {};
      switch (msg.method) {
        case "ui/notifications/initialized":
          if (state.initialized) return;
          state.initialized = true;
          var queued = state.outbox;
          state.outbox = [];
          each(queued, post);
          emit("initialized", {});
          return;

        case "ui/notifications/size-changed":
          if (typeof params.height === "number" && params.height > 0) {
            var h = Math.ceil(params.height);
            if (opts.maxHeight) h = Math.min(h, opts.maxHeight);
            state.lastHeight = h;
            if (autoHeight && state.displayMode !== "fullscreen") iframe.style.height = h + "px";
          }
          emit("size", compact({ width: params.width, height: params.height }));
          return;

        case "notifications/message":
          emit("log", params);
          return;

        default:
          return;
      }
    }

    function handleResponse(msg) {
      var p = state.pending[msg.id];
      if (!p) return;
      delete state.pending[msg.id];
      if (msg.error) {
        var err = new Error(msg.error.message || "Request failed");
        err.code = msg.error.code;
        p.reject(err);
      } else {
        p.resolve(msg.result);
      }
    }

    function onMessage(event) {
      if (state.disposed || event.source !== iframe.contentWindow) return;
      var msg = event.data;
      if (!msg || typeof msg !== "object" || msg.jsonrpc !== "2.0") return;
      if (opts.onTraffic) opts.onTraffic("in", msg);
      var hasId = msg.id !== undefined && msg.id !== null;
      if (msg.method && hasId) handleRequest(msg);
      else if (msg.method) handleNotification(msg);
      else if (hasId) handleResponse(msg);
    }

    // -- Watching the page ----------------------------------------------------

    var observers = [];
    var mediaQueries = [];

    function watchPage() {
      var schedule = debounce(refreshContext, 60);
      if (typeof MutationObserver !== "undefined") {
        var mo = new MutationObserver(schedule);
        mo.observe(document.documentElement, { attributes: true, attributeFilter: ["data-bs-theme", "data-theme", "class", "style"] });
        if (document.body) {
          mo.observe(document.body, { attributes: true, attributeFilter: ["data-bs-theme", "data-theme", "class"] });
        }
        observers.push(mo);
      }
      if (typeof ResizeObserver !== "undefined" && (container || iframe)) {
        var ro = new ResizeObserver(debounce(refreshContext, 150));
        ro.observe(container || iframe);
        observers.push(ro);
      }
      if (window.matchMedia) {
        var mq = window.matchMedia("(prefers-color-scheme: dark)");
        if (mq.addEventListener) mq.addEventListener("change", schedule);
        else if (mq.addListener) mq.addListener(schedule);
        mediaQueries.push({ mq: mq, fn: schedule });
      }
      document.addEventListener("fullscreenchange", onFullscreenChange);
      document.addEventListener("webkitfullscreenchange", onFullscreenChange);
    }

    function unwatchPage() {
      each(observers, function (o) {
        o.disconnect();
      });
      observers = [];
      each(mediaQueries, function (m) {
        if (m.mq.removeEventListener) m.mq.removeEventListener("change", m.fn);
        else if (m.mq.removeListener) m.mq.removeListener(m.fn);
      });
      mediaQueries = [];
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", onFullscreenChange);
      document.removeEventListener("keydown", onKeydown);
    }

    // -- The tool call that opened the app ------------------------------------

    function deliverToolInput(args) {
      state.sentInput = args || {};
      notify("ui/notifications/tool-input", { arguments: state.sentInput });
    }

    function deliverToolResult(result) {
      state.sentResult = result || { content: [] };
      notify("ui/notifications/tool-result", state.sentResult);
    }

    function startToolCall() {
      if (opts.toolInput !== undefined && opts.toolInput !== null) deliverToolInput(opts.toolInput);
      var source = opts.toolResult;
      if (source === undefined || source === null) return;
      if (typeof source === "function") source = source();
      setBusy(1);
      Promise.resolve(source).then(
        function (result) {
          setBusy(-1);
          if (result) deliverToolResult(result);
        },
        function (err) {
          setBusy(-1);
          emit("error", { message: errorMessage(err), method: "tools/call" });
          notify("ui/notifications/tool-cancelled", { reason: errorMessage(err) });
        }
      );
    }

    // -- Public interface -----------------------------------------------------

    var host = {
      iframe: iframe,
      container: container,
      options: opts,
      // Send the app another tool call's arguments and result.
      toolInput: deliverToolInput,
      toolResult: deliverToolResult,
      toolCancelled: function (reason) {
        notify("ui/notifications/tool-cancelled", reason ? { reason: reason } : {});
      },
      // Run changes waiting for a manual trigger, optionally setting inputs.
      execute: function (inputs) {
        notify("x-shinymcp/execute", inputs ? { inputs: inputs } : {});
      },
      reset: function () {
        notify("x-shinymcp/reset", {});
      },
      notify: notify,
      request: request,
      refreshContext: refreshContext,
      modelContext: function () {
        return state.modelContext;
      },
      displayMode: function () {
        return state.displayMode;
      },
      setDisplayMode: setDisplayMode,
      toggleFullscreen: function () {
        return setDisplayMode(state.displayMode === "fullscreen" ? "inline" : "fullscreen");
      },
      isInitialized: function () {
        return state.initialized;
      },
      // Ask the app to shut down, then stop listening. Resolves when done.
      teardown: function (reason) {
        if (state.disposed) return Promise.resolve();
        var done = function () {
          host.dispose();
        };
        if (!state.initialized) {
          done();
          return Promise.resolve();
        }
        return request("ui/resource-teardown", reason ? { reason: reason } : {}, 1500).then(done, done);
      },
      dispose: function () {
        if (state.disposed) return;
        if (state.displayMode === "fullscreen") setDisplayMode("inline");
        state.disposed = true;
        window.removeEventListener("message", onMessage);
        unwatchPage();
        each(keys(state.pending), function (id) {
          state.pending[id].reject(new Error("The app was closed."));
        });
        state.pending = {};
        emit("disposed", {});
      }
    };

    // -- Start ----------------------------------------------------------------

    iframe.setAttribute("sandbox", SANDBOX);
    var allow = allowAttribute(opts.permissions);
    if (allow) iframe.setAttribute("allow", allow);
    if (!iframe.getAttribute("title")) iframe.setAttribute("title", opts.title || "MCP App");
    applyHeight();
    window.addEventListener("message", onMessage);
    watchPage();
    startToolCall();
    iframe.srcdoc = withCsp(opts.html, opts.csp);
    return host;
  }

  function debounce(fn, ms) {
    var timer = null;
    return function () {
      if (timer) clearTimeout(timer);
      timer = setTimeout(function () {
        timer = null;
        fn();
      }, ms);
    };
  }

  window.shinymcpHost = {
    create: create,
    buildCsp: buildCsp,
    withCsp: withCsp,
    pageTheme: pageTheme,
    version: APPS_PROTOCOL_VERSION
  };

  // ---------------------------------------------------------------------------
  // Shiny: hosts whose MCP connection is in R, behind the Shiny session
  // ---------------------------------------------------------------------------
  //
  // Each card or pane carries a descriptor (instance, source, tool,
  // arguments, and the result when there is one), not the page. The host
  // sends it to R to attach; R answers with the page and what to send it.
  // A card restored with a saved conversation attaches the same way. The
  // page's requests go to R, which passes them to the app's server.

  var EVENT_INPUT = "shinymcp_host_event";
  var hosts = {}; // instance id -> {host, container, queued}
  var waiting = {}; // request key -> {resolve, reject}
  var requestSeq = 0;
  var DETACH_GRACE_MS = 1000;

  function hasShiny() {
    return !!(window.Shiny && typeof window.Shiny.setInputValue === "function");
  }

  // R answers only once the session has started: shiny.js sets
  // shinyapp.config when the server's first message arrives.
  function sessionReady() {
    return hasShiny() && !!(window.Shiny.shinyapp && window.Shiny.shinyapp.config);
  }

  function shinyEvent(event) {
    if (!hasShiny()) return false;
    window.Shiny.setInputValue(EVENT_INPUT, event, { priority: "event" });
    return true;
  }

  // Send an event that R answers, and wait for the answer.
  function ask(instanceId, event) {
    return new Promise(function (resolve, reject) {
      var requestId = "r" + ++requestSeq;
      var key = instanceId + "|" + requestId;
      waiting[key] = { resolve: resolve, reject: reject };
      event.instanceId = instanceId;
      event.requestId = requestId;
      if (!shinyEvent(event)) {
        delete waiting[key];
        reject(new Error("The Shiny session isn't connected."));
      }
    });
  }

  function answer(msg, value) {
    var key = msg.instanceId + "|" + msg.requestId;
    var entry = waiting[key];
    if (!entry) return;
    delete waiting[key];
    entry.resolve(value);
  }

  function shinySend(instanceId) {
    return function (message) {
      return ask(instanceId, { type: "request", message: message });
    };
  }

  function readConfig(container) {
    var script = container.querySelector("script.shinymcp-host-config");
    if (!script) return null;
    try {
      return JSON.parse(script.textContent || "null");
    } catch (e) {
      logWarn("could not read the host configuration", e);
      return null;
    }
  }

  function setHostError(container, text) {
    var el = container.querySelector("[data-shinymcp-host-error]");
    if (!el) return;
    el.textContent = text || "";
    if (text) el.removeAttribute("hidden");
    else el.setAttribute("hidden", "");
  }

  function showFallback(container) {
    var el = container.querySelector("[data-shinymcp-host-fallback]");
    if (el) el.removeAttribute("hidden");
    var frame = container.querySelector("iframe[data-shinymcp-host-frame]");
    if (frame) frame.setAttribute("hidden", "");
  }

  function setBusy(container, busy) {
    var busyEl = container.querySelector("[data-shinymcp-host-busy]");
    if (busyEl) busyEl.hidden = !busy;
    if (busy) container.setAttribute("data-shinymcp-busy", "");
    else container.removeAttribute("data-shinymcp-busy");
  }

  function startShinyHost(container, config) {
    if (!config || !config.instanceId) return;
    var instanceId = config.instanceId;
    var existing = hosts[instanceId];
    if (existing) {
      if (existing.container === container) return;
      // The same app re-rendered in a new place: replace the old view.
      if (existing.host) existing.host.dispose();
    }
    var entry = { host: null, container: container, config: config, queued: [], detachedAt: null };
    hosts[instanceId] = entry;
    container.setAttribute("data-shinymcp-started", "");

    var titleEl = container.querySelector(".shinymcp-host-title");
    if (titleEl && !titleEl.textContent && config.title) titleEl.textContent = config.title;
    var runButton = container.querySelector('[data-shinymcp-action="execute"]');
    if (runButton) runButton.hidden = config.trigger !== "manual";
    setBusy(container, true);

    ask(instanceId, { type: "attach", descriptor: config }).then(
      function (reply) {
        if (hosts[instanceId] !== entry) return;
        if (!reply || !reply.ok) {
          setBusy(container, false);
          setHostError(container, (reply && reply.error) || "This app couldn't be shown.");
          showFallback(container);
          return;
        }
        createShinyHost(entry, instanceId, reply);
      },
      function (err) {
        if (hosts[instanceId] !== entry) return;
        setBusy(container, false);
        setHostError(container, errorMessage(err));
        showFallback(container);
      }
    );
  }

  function createShinyHost(entry, instanceId, reply) {
    var container = entry.container;
    var config = entry.config;
    var page = reply.page || {};
    var iframe = container.querySelector("iframe[data-shinymcp-host-frame]");
    var appTools = Array.isArray(reply.appTools) ? reply.appTools : [];
    var fullButton = container.querySelector('[data-shinymcp-action="fullscreen"]');
    var runButton = container.querySelector('[data-shinymcp-action="execute"]');
    var titleEl = container.querySelector(".shinymcp-host-title");
    if (reply.title) {
      if (titleEl) titleEl.textContent = reply.title;
      if (iframe) iframe.setAttribute("title", reply.title);
    }
    if (page.prefersBorder === false) container.setAttribute("data-shinymcp-border", "false");

    var hasResult = reply.toolResult !== undefined && reply.toolResult !== null;
    var host = create({
      container: container,
      iframe: iframe,
      html: page.html,
      csp: page.csp,
      permissions: page.permissions,
      height: config.height || "auto",
      title: reply.title || config.title,
      tool: reply.tool,
      toolInput: reply.toolInput || {},
      toolResult: hasResult ? reply.toolResult : undefined,
      hostInfo: { name: "shinymcp-shiny", version: config.version || "0" },
      send: shinySend(instanceId),
      canCallTool: function (name) {
        return appTools.indexOf(name) >= 0;
      },
      onEvent: function (type, detail) {
        switch (type) {
          case "model-context":
            shinyEvent({ instanceId: instanceId, type: "notification", method: "ui/update-model-context", params: detail });
            break;
          case "message":
            shinyEvent({ instanceId: instanceId, type: "notification", method: "ui/message", params: detail });
            break;
          case "size":
            shinyEvent({ instanceId: instanceId, type: "notification", method: "ui/notifications/size-changed", params: detail });
            break;
          case "busy":
            setBusy(container, detail);
            break;
          case "error":
            setHostError(container, detail.message);
            break;
          case "initialized":
            setHostError(container, "");
            break;
          case "display-mode":
            if (fullButton) {
              var on = detail === "fullscreen";
              fullButton.setAttribute("aria-pressed", on ? "true" : "false");
              fullButton.textContent = on ? "Exit full screen" : "Full screen";
            }
            break;
          default:
            break;
        }
      }
    });
    entry.host = host;
    setBusy(container, !hasResult && !reply.cancelled);
    if (reply.cancelled) host.toolCancelled(reply.cancelled);

    if (runButton) {
      runButton.onclick = function () {
        host.execute();
      };
    }
    if (fullButton) {
      fullButton.onclick = function () {
        host.toggleFullscreen();
      };
    }
    var queued = entry.queued;
    entry.queued = [];
    each(queued, function (msg) {
      runCommand(entry, msg);
    });
  }

  function runCommand(entry, msg) {
    var host = entry.host;
    if (!host) {
      entry.queued.push(msg);
      return;
    }
    switch (msg.command) {
      case "tool-result":
        setBusy(entry.container, false);
        host.toolResult(msg.result);
        break;
      case "tool-cancelled":
        setBusy(entry.container, false);
        host.toolCancelled(msg.reason);
        setHostError(entry.container, msg.reason);
        break;
      case "execute":
        host.execute(msg.inputs || null);
        break;
      case "reset":
        host.reset();
        break;
      default:
        break;
    }
  }

  function stopShinyHost(instanceId, tellServer) {
    var entry = hosts[instanceId];
    if (!entry) return;
    delete hosts[instanceId];
    if (entry.host) entry.host.dispose();
    if (tellServer) shinyEvent({ instanceId: instanceId, type: "dispose" });
    each(keys(waiting), function (key) {
      if (key.indexOf(instanceId + "|") === 0) {
        waiting[key].reject(new Error("The app was closed."));
        delete waiting[key];
      }
    });
  }

  // Load the app again, from a new attach: after the pane's tool is called
  // with other arguments. A tool from another app brings its own trigger.
  function reopenShinyHost(instanceId, trigger) {
    var entry = hosts[instanceId];
    if (!entry) return;
    var container = entry.container;
    var config = entry.config;
    if (trigger) config.trigger = trigger;
    var done = function () {
      if (hosts[instanceId] !== entry) return;
      delete hosts[instanceId];
      container.removeAttribute("data-shinymcp-started");
      setHostError(container, "");
      startShinyHost(container, config);
    };
    if (entry.host) entry.host.teardown("The app is opening again.").then(done, done);
    else done();
  }

  function scan(root) {
    var found = [];
    if (root && root.nodeType === 1 && root.matches && root.matches("[data-shinymcp-host]")) found.push(root);
    each((root || document).querySelectorAll ? (root || document).querySelectorAll("[data-shinymcp-host]") : [], function (el) {
      found.push(el);
    });
    each(found, function (container) {
      if (container.hasAttribute("data-shinymcp-started")) return;
      var config = readConfig(container);
      if (config) startShinyHost(container, config);
    });
  }

  // A host whose container left the page is shut down, unless it comes back
  // right away (some UI frameworks move nodes around).
  function prune() {
    var now = Date.now();
    each(keys(hosts), function (id) {
      var entry = hosts[id];
      if (entry.container.isConnected) {
        entry.detachedAt = null;
      } else if (!entry.detachedAt) {
        entry.detachedAt = now;
        setTimeout(prune, DETACH_GRACE_MS + 50);
      } else if (now - entry.detachedAt >= DETACH_GRACE_MS) {
        stopShinyHost(id, true);
      }
    });
  }

  function startObserving() {
    if (sessionReady()) scan(document);
    if (typeof MutationObserver === "undefined") return;
    new MutationObserver(function (mutations) {
      var removed = false;
      each(mutations, function (m) {
        if (sessionReady()) {
          each(m.addedNodes, function (node) {
            if (node.nodeType === 1) scan(node);
          });
        }
        if (m.removedNodes && m.removedNodes.length) removed = true;
      });
      if (removed) prune();
    }).observe(document.documentElement, { childList: true, subtree: true });
  }

  function registerShinyHandlers() {
    if (!window.Shiny || typeof window.Shiny.addCustomMessageHandler !== "function") return false;
    if (window.shinymcpHost.shinyHandlers) return true;
    window.shinymcpHost.shinyHandlers = true;

    window.Shiny.addCustomMessageHandler("shinymcp-host-init", function (msg) {
      var container = document.getElementById(msg.id);
      if (!container) return;
      var script = container.querySelector("script.shinymcp-host-config");
      if (!script) {
        script = document.createElement("script");
        script.type = "application/json";
        script.className = "shinymcp-host-config";
        container.appendChild(script);
      }
      script.textContent = JSON.stringify(msg.config || {});
      container.removeAttribute("data-shinymcp-started");
      startShinyHost(container, msg.config || {});
    });

    window.Shiny.addCustomMessageHandler("shinymcp-host-attached", function (msg) {
      answer(msg, msg);
    });

    window.Shiny.addCustomMessageHandler("shinymcp-host-response", function (msg) {
      answer(msg, msg.response || {});
    });

    window.Shiny.addCustomMessageHandler("shinymcp-host-command", function (msg) {
      var entry = hosts[msg.instanceId];
      if (!entry) return;
      switch (msg.command) {
        case "dispose":
          if (!entry.host) {
            stopShinyHost(msg.instanceId, false);
            break;
          }
          entry.host.teardown().then(function () {
            stopShinyHost(msg.instanceId, false);
          });
          break;
        case "reopen":
          reopenShinyHost(msg.instanceId, msg.trigger);
          break;
        default:
          runCommand(entry, msg);
      }
    });

    // Requests can't be answered once the session is gone.
    if (window.jQuery) {
      window.jQuery(document).on("shiny:disconnected", function () {
        each(keys(waiting), function (key) {
          waiting[key].reject(new Error("The Shiny session ended."));
          delete waiting[key];
        });
      });
    }
    return true;
  }

  // Cards and panes attach once the session has started: R answers them.
  function boot() {
    registerShinyHandlers();
    if (window.jQuery) {
      window.jQuery(document).on("shiny:connected", registerShinyHandlers);
      window.jQuery(document).on("shiny:sessioninitialized", function () {
        registerShinyHandlers();
        scan(document);
      });
    }
    startObserving();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
