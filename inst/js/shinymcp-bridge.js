// shinymcp bridge
//
// Runs inside an MCP App's page and speaks the MCP Apps protocol
// (2026-01-26) to the host over postMessage. It finds the page's inputs,
// sends their values to the app's tools, and draws the results into the
// page's outputs.
//
// Two modes, set by the page's configuration:
//
// * "tools": the page belongs to mcp_app(). Each tool's arguments are
//   filled from inputs whose ids (or data-shinymcp-input attributes) match
//   the argument names; tools run when their inputs change.
// * "shiny": the page is a Shiny app served live with as_mcp_app(). Every
//   input change goes to the app's view tool with the id of this view, and
//   R answers with the outputs that changed, as a Shiny session would.
//
// Written in ES5 without dependencies so it can be inlined into any page.
(function () {
  "use strict";

  if (window.shinymcp && window.shinymcp.__bridge) return;

  var APPS_PROTOCOL_VERSION = "2026-01-26";
  var VIEW_META = "shinymcp/view";

  // ---------------------------------------------------------------------------
  // Small utilities
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

  function hasClass(el, cls) {
    return !!(el && el.classList && el.classList.contains(cls));
  }

  var cssEscape =
    typeof CSS !== "undefined" && typeof CSS.escape === "function"
      ? function (s) { return CSS.escape(s); }
      : function (s) {
          return String(s).replace(/([!"#$%&'()*+,./:;<=>?@[\\\]^`{|}~])/g, "\\$1");
        };

  function byId(id) {
    return id ? document.getElementById(id) : null;
  }

  function sameValue(a, b) {
    return JSON.stringify(a) === JSON.stringify(b);
  }

  function logWarn() {
    if (window.console && console.warn) {
      var args = ["[shinymcp]"].concat(Array.prototype.slice.call(arguments));
      console.warn.apply(console, args);
    }
  }

  function pad2(n) {
    return (n < 10 ? "0" : "") + n;
  }

  // Local calendar date as YYYY-MM-DD.
  function formatDate(d) {
    return d.getFullYear() + "-" + pad2(d.getMonth() + 1) + "-" + pad2(d.getDate());
  }

  function todayString() {
    return formatDate(new Date());
  }

  function parseNumber(v) {
    if (v === null || v === undefined || v === "") return null;
    var n = parseFloat(v);
    return isNaN(n) ? null : n;
  }

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  var config = {};
  (function readConfig() {
    var el = byId("shinymcp-config");
    if (!el) return;
    try {
      config = JSON.parse(el.textContent || "{}") || {};
    } catch (e) {
      logWarn("could not read the page configuration", e);
    }
  })();

  var MODE = config.mode === "shiny" ? "shiny" : "tools";
  var TOOLS = Array.isArray(config.tools) ? config.tools : [];
  var TRIGGER = config.trigger || "debounce";
  var DEBOUNCE_MS = typeof config.debounceMs === "number" ? config.debounceMs : 250;

  // ---------------------------------------------------------------------------
  // JSON-RPC over postMessage
  // ---------------------------------------------------------------------------

  var nextId = 1;
  var pending = {};
  var tornDown = false;
  var connected = !!(window.parent && window.parent !== window);

  function post(message) {
    if (!connected || tornDown) return;
    window.parent.postMessage(message, "*");
  }

  function request(method, params) {
    if (tornDown) return Promise.reject(new Error("The app has been closed."));
    if (!connected) return Promise.reject(new Error("The app is not running inside an MCP host."));
    var id = nextId++;
    var message = { jsonrpc: "2.0", id: id, method: method };
    if (params !== undefined) message.params = params;
    return new Promise(function (resolve, reject) {
      pending[id] = { resolve: resolve, reject: reject, method: method };
      post(message);
    });
  }

  function notify(method, params) {
    var message = { jsonrpc: "2.0", method: method };
    if (params !== undefined) message.params = params;
    post(message);
  }

  function respond(id, result) {
    post({ jsonrpc: "2.0", id: id, result: result || {} });
  }

  function respondError(id, code, message) {
    post({ jsonrpc: "2.0", id: id, error: { code: code, message: message } });
  }

  function onMessage(event) {
    if (tornDown || event.source !== window.parent) return;
    var data = event.data;
    if (!data || data.jsonrpc !== "2.0") return;

    if (data.id !== undefined && data.id !== null && !data.method) {
      var p = pending[data.id];
      if (!p) return;
      delete pending[data.id];
      if (data.error) {
        var err = new Error(data.error.message || "Request failed");
        err.code = data.error.code;
        err.data = data.error.data;
        p.reject(err);
      } else {
        p.resolve(data.result);
      }
      return;
    }
    if (!data.method) return;
    if (data.id !== undefined && data.id !== null) {
      handleHostRequest(data);
    } else {
      handleHostNotification(data.method, data.params || {});
    }
  }

  function handleHostRequest(msg) {
    switch (msg.method) {
      case "ping":
        respond(msg.id, {});
        break;
      case "ui/resource-teardown":
        closeView();
        respond(msg.id, {});
        teardown();
        break;
      default:
        respondError(msg.id, -32601, "Method not supported by this app: " + msg.method);
    }
  }

  function handleHostNotification(method, params) {
    switch (method) {
      case "ui/notifications/tool-input":
        state.toolInputSeen = true;
        applyToolInput(params.arguments || {});
        break;
      case "ui/notifications/tool-input-partial":
        break;
      case "ui/notifications/tool-result":
        state.toolResultSeen = true;
        handleResult(params, { initial: true });
        break;
      case "ui/notifications/tool-cancelled":
        setBusy(-state.busy);
        if (!state.firstResult) selfInit();
        break;
      case "ui/notifications/host-context-changed":
        applyHostContext(params);
        break;
      // shinymcp's own hosts send these: run changes now (the "manual"
      // trigger), optionally setting inputs first, or restore the inputs
      // the view opened with.
      case "x-shinymcp/execute":
        if (params.inputs && typeof params.inputs === "object") {
          setInputsSilently(params.inputs);
          each(keys(params.inputs), function (id) { state.changed[id] = true; });
        }
        runPending(true);
        break;
      case "x-shinymcp/reset":
        resetInputs();
        break;
      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------

  var state = {
    hostContext: {},
    hostCapabilities: {},
    initialized: false,
    toolInputSeen: false,
    toolResultSeen: false,
    firstResult: false,
    busy: 0,
    entryTool: null,
    instance: null,
    viewRevision: null,
    changed: {},
    dirty: false,
    revision: 0,
    loadedDeps: {},
    loadedNames: {},
    customHandlers: {},
    contextListeners: []
  };
  each(config.deps || [], function (key) {
    state.loadedDeps[key] = true;
    state.loadedNames[String(key).replace(/@[^@]*$/, "")] = true;
  });

  // ---------------------------------------------------------------------------
  // Host context: theme, style variables, fonts, sizing
  // ---------------------------------------------------------------------------

  // MCP Apps style variables mapped onto Bootstrap's, so bslib pages follow
  // the host's palette and type.
  var BOOTSTRAP_VARS = {
    "--color-background-primary": ["--bs-body-bg"],
    "--color-background-secondary": ["--bs-secondary-bg", "--bs-tertiary-bg"],
    "--color-text-primary": ["--bs-body-color", "--bs-emphasis-color"],
    "--color-text-secondary": ["--bs-secondary-color"],
    "--color-border-primary": ["--bs-border-color"],
    "--color-ring-primary": ["--bs-focus-ring-color"],
    "--font-sans": ["--bs-body-font-family", "--bs-font-sans-serif"],
    "--font-mono": ["--bs-font-monospace"],
    "--border-radius-md": ["--bs-border-radius"],
    "--border-radius-sm": ["--bs-border-radius-sm"],
    "--border-radius-lg": ["--bs-border-radius-lg"]
  };

  function applyHostContext(ctx) {
    if (!ctx || typeof ctx !== "object") return;
    assign(state.hostContext, ctx);
    var root = document.documentElement;
    // Bootstrap 3 and 4 pages (fluidPage() and friends) were drawn for a
    // light background and have no dark mode: keep them light and leave
    // their colors alone.
    var lightOnly = hasClass(root, "shinymcp-bs3") || hasClass(root, "shinymcp-bs4");

    if (ctx.theme === "light" || ctx.theme === "dark") {
      var theme = lightOnly ? "light" : ctx.theme;
      root.setAttribute("data-theme", theme);
      root.setAttribute("data-bs-theme", theme);
      root.style.colorScheme = theme;
    }
    if (typeof ctx.locale === "string" && ctx.locale) {
      root.lang = ctx.locale;
    }
    var styles = ctx.styles || {};
    if (styles.variables && typeof styles.variables === "object" && config.hostStyles !== false && !lightOnly) {
      each(keys(styles.variables), function (name) {
        var value = styles.variables[name];
        if (name.indexOf("--") !== 0 || typeof value !== "string") return;
        root.style.setProperty(name, value);
        each(BOOTSTRAP_VARS[name] || [], function (bsName) {
          root.style.setProperty(bsName, value);
        });
      });
    }
    if (styles.css && typeof styles.css.fonts === "string" && !byId("shinymcp-host-fonts")) {
      var style = document.createElement("style");
      style.id = "shinymcp-host-fonts";
      style.textContent = styles.css.fonts;
      document.head.appendChild(style);
    }
    var dims = ctx.containerDimensions;
    if (dims && typeof dims === "object") {
      if (typeof dims.height === "number") {
        root.style.height = "100vh";
        root.classList.add("shinymcp-fixed-height");
      } else {
        root.style.height = "";
        root.classList.remove("shinymcp-fixed-height");
      }
    }
    if (ctx.displayMode) {
      root.setAttribute("data-display-mode", ctx.displayMode);
    }
    // A live Shiny view redraws what depends on the theme or display mode.
    if (MODE === "shiny" && state.firstResult && (ctx.theme !== undefined || ctx.displayMode !== undefined)) {
      scheduleHostRefresh();
    }
    // The tool call that opened this view, when the host says.
    if (ctx.toolInfo && ctx.toolInfo.tool && typeof ctx.toolInfo.tool.name === "string") {
      state.entryTool = ctx.toolInfo.tool.name;
    }
    each(state.contextListeners, function (fn) {
      try {
        fn(state.hostContext);
      } catch (e) {
        logWarn("host context listener failed", e);
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Inputs
  //
  // Each input gets an adapter with get(), set(value), receiveMessage(msg),
  // and change listeners. Adapters give Shiny's inputs native behaviour in a
  // page without Shiny's JavaScript: sliders become range inputs, date
  // pickers become date inputs, action buttons count their clicks.
  // ---------------------------------------------------------------------------

  var adapters = {}; // DOM id -> adapter

  function inputKind(el) {
    var tag = el.tagName.toLowerCase();
    var type = (el.getAttribute("type") || "").toLowerCase();
    if (hasClass(el, "shiny-input-radiogroup") || el.getAttribute("data-shinymcp-type") === "radio") return "radio";
    if (hasClass(el, "shiny-input-checkboxgroup")) return "checkbox-group";
    if (hasClass(el, "shiny-date-range-input")) return "date-range";
    if (hasClass(el, "shiny-date-input")) return "date";
    if (hasClass(el, "shiny-tab-input")) return "tabs";
    if (tag === "select") return el.multiple ? "select-multiple" : "select";
    if (tag === "textarea") return "textarea";
    if ((tag === "button" || tag === "a") && hasClass(el, "action-button")) return "action";
    if (tag === "button" && el.getAttribute("data-shinymcp-type") === "button") return "action";
    if (tag === "input") {
      if (hasClass(el, "js-range-slider")) return el.getAttribute("data-type") === "double" ? "slider-range" : "slider";
      if (type === "range") return "slider";
      if (type === "checkbox") return "checkbox";
      if (type === "number") return "number";
      if (type === "password") return "password";
      if (type === "file") return "file";
      if (type === "date") return "date";
      if (type === "radio" || type === "submit" || type === "button" || type === "hidden") return null;
      return "text";
    }
    return null;
  }

  function makeAdapter(el, id) {
    var kind = inputKind(el);
    if (!kind) return null;
    var factory = ADAPTERS[kind] || ADAPTERS.text;
    var adapter = factory(el);
    adapter.id = id || el.id;
    adapter.kind = kind;
    adapter.el = el;
    adapter.listeners = [];
    adapter.emit = function () {
      for (var i = 0; i < adapter.listeners.length; i++) adapter.listeners[i](adapter);
    };
    if (adapter.bind) adapter.bind();
    return adapter;
  }

  function listen(el, events, fn) {
    each(events, function (ev) {
      el.addEventListener(ev, fn);
    });
  }

  function labelFor(adapter) {
    var el = adapter.el;
    var label = document.querySelector('label[for="' + cssEscape(el.id || adapter.id) + '"]');
    if (!label) {
      var group = el.closest ? el.closest(".shiny-input-container, .shinymcp-input-group, .form-group") : null;
      label = group ? group.querySelector("label") : null;
    }
    return label;
  }

  function setLabel(adapter, text) {
    var label = labelFor(adapter);
    if (label && typeof text === "string") label.textContent = text;
  }

  // Tabsets (tabsetPanel(id =), navbarPage(id =), bslib navsets). The
  // value is the shown pane's; Bootstrap's own script switches panes.
  function tabContent(ul) {
    var tabsetId = ul.getAttribute("data-tabsetid");
    return tabsetId ? document.querySelector('.tab-content[data-tabsetid="' + cssEscape(tabsetId) + '"]') : null;
  }

  function tabAnchor(ul, value) {
    var anchors = ul.querySelectorAll("a[data-value]");
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var toggle = a.getAttribute("data-bs-toggle") || a.getAttribute("data-toggle");
      if (toggle === "tab" && a.getAttribute("data-value") === String(value)) return a;
    }
    return null;
  }

  // Through jQuery when it has a tab plugin: Bootstrap 3's, or on
  // Bootstrap 4 and 5 pages bslib's shim for Shiny's Bootstrap 3 markup.
  function activateTab(a) {
    if (!a) return;
    var $ = window.jQuery;
    var bs = window.bootstrap;
    if ($ && $.fn && $.fn.tab) {
      $(a).tab("show");
    } else if (bs && bs.Tab && bs.Tab.getOrCreateInstance) {
      bs.Tab.getOrCreateInstance(a).show();
    } else {
      a.click();
    }
  }

  function shownTab(ul) {
    var content = tabContent(ul);
    if (content) {
      var panes = content.children;
      for (var i = 0; i < panes.length; i++) {
        if (hasClass(panes[i], "tab-pane") && hasClass(panes[i], "active")) {
          return panes[i].getAttribute("data-value");
        }
      }
    }
    var anchors = ul.querySelectorAll("a[data-value]");
    for (var j = 0; j < anchors.length; j++) {
      var a = anchors[j];
      var toggle = a.getAttribute("data-bs-toggle") || a.getAttribute("data-toggle");
      if (toggle === "tab" && (hasClass(a, "active") || hasClass(a.parentNode, "active"))) {
        return a.getAttribute("data-value");
      }
    }
    return null;
  }

  var ADAPTERS = {
    tabs: function (el) {
      var last = null;
      return {
        get: function () { return shownTab(el); },
        set: function (v) {
          if (v === null || v === undefined) return;
          activateTab(tabAnchor(el, v));
          last = String(v);
        },
        // Tell the session if the shown tab changed. Bootstrap switches
        // panes after a click, and again after a fade.
        check: function () {
          var self = this;
          function compare() {
            var now = shownTab(el);
            if (now !== last) {
              last = now;
              self.emit();
            }
          }
          setTimeout(compare, 0);
          setTimeout(compare, 400);
        },
        bind: function () {
          var self = this;
          last = shownTab(el);
          listen(el, ["click"], function () { self.check(); });
        },
        receiveMessage: function (msg) {
          if (msg.value !== undefined) this.set(msg.value);
        }
      };
    },

    text: function (el) {
      var updateOnChange = el.getAttribute("data-update-on") === "change";
      return {
        get: function () { return el.value; },
        set: function (v) { el.value = v === null || v === undefined ? "" : String(v); },
        bind: function () {
          var self = this;
          listen(el, updateOnChange ? ["change"] : ["input", "change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.placeholder !== undefined) el.placeholder = msg.placeholder;
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
      };
    },

    textarea: function (el) {
      var adapter = ADAPTERS.text(el);
      return adapter;
    },

    password: function (el) {
      var adapter = ADAPTERS.text(el);
      adapter.secret = true;
      return adapter;
    },

    number: function (el) {
      var updateOnChange = el.getAttribute("data-update-on") === "change";
      return {
        get: function () { return parseNumber(el.value); },
        set: function (v) { el.value = v === null || v === undefined ? "" : String(v); },
        bind: function () {
          var self = this;
          listen(el, updateOnChange ? ["change"] : ["input", "change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          each(["min", "max", "step"], function (k) {
            if (msg[k] !== undefined && msg[k] !== null) el.setAttribute(k, msg[k]);
          });
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
      };
    },

    checkbox: function (el) {
      return {
        get: function () { return !!el.checked; },
        set: function (v) { el.checked = !!v; },
        bind: function () {
          var self = this;
          listen(el, ["change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) {
            var span = el.parentNode && el.parentNode.querySelector("span");
            if (span) span.textContent = msg.label;
            else setLabel(this, msg.label);
          }
        }
      };
    },

    select: function (el) {
      // A select Shiny meant for selectize: style it as Bootstrap styles a
      // plain one.
      var selectized = el.id && el.parentNode &&
        el.parentNode.querySelector('script[data-for="' + cssEscape(el.id) + '"]');
      if (selectized && !hasClass(el, "form-control") && !hasClass(el, "form-select")) {
        var bs5 = window.getComputedStyle &&
          window.getComputedStyle(document.documentElement).getPropertyValue("--bs-body-bg");
        el.classList.add(bs5 ? "form-select" : "form-control");
      }
      return {
        get: function () {
          if (el.multiple) {
            var out = [];
            each(el.options, function (o) { if (o.selected) out.push(o.value); });
            return out;
          }
          return el.selectedIndex >= 0 ? el.value : null;
        },
        set: function (v) {
          if (el.multiple) {
            var values = Array.isArray(v) ? v.map(String) : v === null || v === undefined ? [] : [String(v)];
            each(el.options, function (o) { o.selected = values.indexOf(o.value) >= 0; });
          } else if (v !== null && v !== undefined) {
            el.value = String(Array.isArray(v) ? v[0] : v);
          }
        },
        bind: function () {
          var self = this;
          listen(el, ["change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (typeof msg.options === "string") {
            var current = this.get();
            el.innerHTML = msg.options;
            if (msg.value === undefined && !el.multiple && current !== null) {
              this.set(current);
            }
          }
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
      };
    },

    "select-multiple": function (el) {
      return ADAPTERS.select(el);
    },

    radio: function (el) {
      function radios() {
        return el.querySelectorAll('input[type="radio"]');
      }
      return {
        get: function () {
          var checked = el.querySelector('input[type="radio"]:checked');
          return checked ? checked.value : null;
        },
        set: function (v) {
          each(radios(), function (r) { r.checked = v !== null && v !== undefined && r.value === String(v); });
        },
        bind: function () {
          var self = this;
          listen(el, ["change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (typeof msg.options === "string") {
            var group = el.querySelector(".shiny-options-group") || el;
            group.innerHTML = msg.options;
          }
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
      };
    },

    "checkbox-group": function (el) {
      function boxes() {
        return el.querySelectorAll('input[type="checkbox"]');
      }
      return {
        get: function () {
          var out = [];
          each(boxes(), function (b) { if (b.checked) out.push(b.value); });
          return out;
        },
        set: function (v) {
          var values = Array.isArray(v) ? v.map(String) : v === null || v === undefined ? [] : [String(v)];
          each(boxes(), function (b) { b.checked = values.indexOf(b.value) >= 0; });
        },
        bind: function () {
          var self = this;
          listen(el, ["change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (typeof msg.options === "string") {
            var group = el.querySelector(".shiny-options-group") || el;
            group.innerHTML = msg.options;
          }
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
      };
    },

    date: function (el) {
      // Shiny's dateInput: a container (with the id) around a text input
      // meant for bootstrap-datepicker. Use the browser's date input.
      var input = el.tagName.toLowerCase() === "input" ? el : el.querySelector("input");
      if (input) {
        input.type = "date";
        var initial = input.getAttribute("data-initial-date");
        input.value = initial || input.value || todayString();
        if (input.getAttribute("data-min-date")) input.min = input.getAttribute("data-min-date");
        if (input.getAttribute("data-max-date")) input.max = input.getAttribute("data-max-date");
      }
      return {
        get: function () { return input && input.value ? input.value : null; },
        set: function (v) { if (input) input.value = v ? String(v).slice(0, 10) : ""; },
        bind: function () {
          var self = this;
          if (input) listen(input, ["change"], function () { self.emit(); });
        },
        receiveMessage: function (msg) {
          if (!input) return;
          if (msg.min !== undefined) input.min = msg.min || "";
          if (msg.max !== undefined) input.max = msg.max || "";
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        },
        dataType: "date"
      };
    },

    "date-range": function (el) {
      var inputs = el.querySelectorAll("input");
      each(inputs, function (input) {
        input.type = "date";
        input.value = input.getAttribute("data-initial-date") || input.value || todayString();
        if (input.getAttribute("data-min-date")) input.min = input.getAttribute("data-min-date");
        if (input.getAttribute("data-max-date")) input.max = input.getAttribute("data-max-date");
      });
      return {
        get: function () {
          var out = [];
          each(inputs, function (input) { out.push(input.value || null); });
          return out;
        },
        set: function (v) {
          if (v && typeof v === "object" && !Array.isArray(v)) v = [v.start, v.end];
          if (!Array.isArray(v)) return;
          each(inputs, function (input, i) { if (v[i]) input.value = String(v[i]).slice(0, 10); });
        },
        bind: function () {
          var self = this;
          each(inputs, function (input) { listen(input, ["change"], function () { self.emit(); }); });
        },
        receiveMessage: function (msg) {
          each(inputs, function (input) {
            if (msg.min !== undefined) input.min = msg.min || "";
            if (msg.max !== undefined) input.max = msg.max || "";
          });
          if (msg.value !== undefined) this.set(msg.value);
          if (msg.label !== undefined) setLabel(this, msg.label);
        },
        dataType: "date"
      };
    },

    slider: function (el) {
      return sliderAdapter(el, false);
    },

    "slider-range": function (el) {
      return sliderAdapter(el, true);
    },

    action: function (el) {
      var count = 0;
      if (el.tagName.toLowerCase() === "a") el.setAttribute("href", "#");
      return {
        get: function () { return count; },
        set: function (v) {
          var n = parseInt(v, 10);
          if (!isNaN(n)) count = n;
        },
        bind: function () {
          var self = this;
          el.addEventListener("click", function (e) {
            e.preventDefault();
            if (el.disabled || hasClass(el, "disabled")) return;
            count++;
            self.emit();
          });
        },
        receiveMessage: function (msg) {
          if (msg.label !== undefined) {
            var label = el.querySelector(".action-label") || el;
            label.innerHTML = msg.label;
          }
          if (msg.disabled !== undefined) {
            el.disabled = !!msg.disabled;
            el.classList.toggle("disabled", !!msg.disabled);
          }
        },
        event: true
      };
    },

    file: function (el) {
      el.disabled = true;
      var group = el.closest(".shiny-input-container") || el.parentNode;
      if (group && !group.querySelector(".shinymcp-file-note")) {
        var note = document.createElement("div");
        note.className = "shinymcp-file-note";
        note.textContent = "File uploads aren't available in chat.";
        group.appendChild(note);
      }
      return {
        get: function () { return null; },
        set: function () {},
        receiveMessage: function () {},
        unsupported: true
      };
    }
  };

  // Shiny's sliderInput renders an <input class="js-range-slider"> with its
  // settings in data attributes, meant for ionRangeSlider. Draw range inputs
  // instead: one, or two sharing a track for a range. Date sliders count
  // milliseconds, as ionRangeSlider does.
  function sliderAdapter(el, range) {
    var isNative = (el.getAttribute("type") || "").toLowerCase() === "range";
    var dataType = el.getAttribute("data-data-type") || "number";
    var min = parseNumber(isNative ? el.min : el.getAttribute("data-min"));
    var max = parseNumber(isNative ? el.max : el.getAttribute("data-max"));
    var step = parseNumber(isNative ? el.step : el.getAttribute("data-step"));
    var from = parseNumber(isNative ? el.value : el.getAttribute("data-from"));
    var to = parseNumber(el.getAttribute("data-to"));
    var ranges = [];
    var fill = null;
    var label = document.createElement("output");
    label.className = "shinymcp-slider-value";

    function format(v) {
      if (v === null || isNaN(v)) return "";
      if (dataType === "date") return new Date(v).toISOString().slice(0, 10);
      if (dataType === "datetime") return new Date(v).toISOString().slice(0, 16).replace("T", " ");
      var prefix = el.getAttribute("data-prefix") || "";
      var postfix = el.getAttribute("data-postfix") || "";
      return prefix + String(v) + postfix;
    }

    function toValue(v) {
      if (v === null) return null;
      if (dataType === "date") return new Date(v).toISOString().slice(0, 10);
      if (dataType === "datetime") return new Date(v).toISOString();
      return v;
    }

    function fromValue(v) {
      if (v === null || v === undefined) return null;
      // updateSliderInput() sends dates as milliseconds, in strings.
      if ((dataType === "date" || dataType === "datetime") && typeof v === "string" && !/^-?[0-9.]+$/.test(v)) {
        var t = Date.parse(v.length === 10 ? v + "T00:00:00Z" : v);
        return isNaN(t) ? null : t;
      }
      return parseNumber(v);
    }

    function makeRange(value, name) {
      var input = document.createElement("input");
      input.type = "range";
      if (min !== null) input.min = min;
      if (max !== null) input.max = max;
      input.step = step !== null ? step : "any";
      if (value !== null) input.value = value;
      if (name) input.setAttribute("aria-label", name);
      return input;
    }

    function numbers() {
      var vals = [];
      each(ranges, function (r) { vals.push(parseNumber(r.value)); });
      vals.sort(function (a, b) { return a - b; });
      return vals;
    }

    function refresh() {
      var vals = numbers();
      label.textContent = range ? format(vals[0]) + " \u2013 " + format(vals[1]) : format(vals[0]);
      if (fill) {
        var lo = min === null ? 0 : min;
        var span = max === null || max === lo ? 1 : max - lo;
        var a = range ? (vals[0] - lo) / span : 0;
        var b = ((range ? vals[1] : vals[0]) - lo) / span;
        fill.style.left = Math.max(0, Math.min(1, a)) * 100 + "%";
        fill.style.right = (1 - Math.max(0, Math.min(1, b))) * 100 + "%";
      }
    }

    if (isNative) {
      ranges.push(el);
      el.parentNode.insertBefore(label, el.nextSibling);
    } else {
      var wrap = document.createElement("div");
      wrap.className = range ? "shinymcp-slider shinymcp-slider-range" : "shinymcp-slider";
      var track = document.createElement("div");
      track.className = "shinymcp-slider-track";
      fill = document.createElement("div");
      fill.className = "shinymcp-slider-fill";
      track.appendChild(fill);
      var values = range ? [from, to] : [from];
      each(values, function (v, i) {
        var input = makeRange(v, range ? (i === 0 ? "Minimum" : "Maximum") : null);
        track.appendChild(input);
        ranges.push(input);
      });
      wrap.appendChild(track);
      wrap.appendChild(label);
      el.style.display = "none";
      el.parentNode.insertBefore(wrap, el.nextSibling);
      var labelEl = document.querySelector('label[for="' + cssEscape(el.id) + '"]');
      if (labelEl && ranges[0]) {
        ranges[0].id = el.id + "-shinymcp-range";
        labelEl.setAttribute("for", ranges[0].id);
      }
    }
    refresh();

    return {
      get: function () {
        var vals = numbers();
        if (!range) return toValue(vals[0]);
        return [toValue(vals[0]), toValue(vals[1])];
      },
      set: function (v) {
        var vals = Array.isArray(v) ? v : [v];
        each(ranges, function (r, i) {
          var n = fromValue(vals[i]);
          if (n !== null) r.value = n;
        });
        refresh();
      },
      bind: function () {
        var self = this;
        each(ranges, function (r) {
          listen(r, ["input"], refresh);
          listen(r, ["change"], function () { self.emit(); });
        });
      },
      receiveMessage: function (msg) {
        if (msg.min !== undefined) { min = fromValue(msg.min); each(ranges, function (r) { r.min = min; }); }
        if (msg.max !== undefined) { max = fromValue(msg.max); each(ranges, function (r) { r.max = max; }); }
        if (msg.step !== undefined) { step = parseNumber(msg.step); each(ranges, function (r) { r.step = step; }); }
        if (msg.value !== undefined) this.set(msg.value);
        if (msg.label !== undefined) setLabel(this, msg.label);
        refresh();
      },
      dataType: dataType
    };
  }

  // Find input elements in a subtree. In "shiny" mode every Shiny-style
  // input counts; in "tools" mode only those tied to tool arguments.
  var INPUT_SELECTOR = [
    "[data-shinymcp-input]",
    "select[id]",
    "textarea[id]",
    "input[id]",
    ".shiny-input-radiogroup[id]",
    ".shiny-input-checkboxgroup[id]",
    ".shiny-date-input[id]",
    ".shiny-date-range-input[id]",
    ".shiny-tab-input[id]",
    ".action-button[id]"
  ].join(",");

  function scanInputs(root) {
    var found = [];
    var candidates = (root || document).querySelectorAll(INPUT_SELECTOR);
    if (root && root.matches && root.matches(INPUT_SELECTOR)) found.push(root);
    each(candidates, function (el) { found.push(el); });
    each(found, function (el) {
      if (el.__shinymcpAdapter) return;
      // Inputs inside a group or date container belong to the container.
      var owner = el.parentNode && el.parentNode.closest
        ? el.parentNode.closest(".shiny-input-radiogroup[id], .shiny-input-checkboxgroup[id], .shiny-date-input[id], .shiny-date-range-input[id], [data-shinymcp-type='radio']")
        : null;
      if (owner && owner !== el) return;
      var id = el.getAttribute("data-shinymcp-input") || el.id;
      if (!id) return;
      if (el.tagName.toLowerCase() === "input" && (el.type === "radio" || el.type === "checkbox") && el.name && el.closest("[data-shinymcp-type='radio'], .shiny-input-radiogroup, .shiny-input-checkboxgroup")) return;
      // In "tools" mode the data-shinymcp-input name wins (a module's
      // namespaced element carries its tool argument name there).
      var key = MODE === "tools" ? id : el.id || id;
      if (adapters[key]) return;
      var adapter = makeAdapter(el, key);
      if (!adapter) return;
      el.__shinymcpAdapter = adapter;
      adapter.listeners.push(onInputChanged);
      adapters[key] = adapter;
    });
  }

  function readInputs(ids) {
    var out = {};
    each(ids || keys(adapters), function (id) {
      var a = adapters[id];
      if (a && !a.unsupported) out[id] = a.get();
    });
    return out;
  }

  // Set input values without triggering tool calls.
  var applying = false;
  function setInputsSilently(values) {
    applying = true;
    try {
      each(keys(values), function (id) {
        var a = adapters[id];
        if (a && !a.event) a.set(values[id]);
      });
    } finally {
      applying = false;
    }
  }

  function applyToolInput(args) {
    if (MODE === "tools") setInputsSilently(args);
    // In "shiny" mode the result's view state carries every input value.
  }

  var initialSnapshot = null;
  function resetInputs() {
    if (!initialSnapshot) return;
    setInputsSilently(initialSnapshot);
    each(keys(initialSnapshot), function (id) { state.changed[id] = true; });
    runPending(true);
  }

  // ---------------------------------------------------------------------------
  // Reacting to input changes
  // ---------------------------------------------------------------------------

  var timer = null;
  var submitButton = null;

  function onInputChanged(adapter) {
    if (applying || tornDown) return;
    state.changed[adapter.id] = true;
    state.dirty = true;
    if (submitButton) submitButton.disabled = false;
    scheduleModelContext();
    if (TRIGGER === "submit" || TRIGGER === "manual") return;
    if (adapter.event || TRIGGER === "change") {
      runPending(false);
      return;
    }
    if (timer) clearTimeout(timer);
    timer = setTimeout(function () {
      timer = null;
      runPending(false);
    }, DEBOUNCE_MS);
  }

  function runPending(force) {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
    var changed = keys(state.changed);
    if (!changed.length && !force) return;
    state.changed = {};
    state.dirty = false;
    if (submitButton) submitButton.disabled = true;
    if (MODE === "shiny") {
      viewUpdate(changed, {});
    } else {
      callTools(toolsForInputs(force && !changed.length ? null : changed));
    }
  }

  // ---------------------------------------------------------------------------
  // Tools mode
  // ---------------------------------------------------------------------------

  function appTools() {
    return TOOLS.filter(function (t) { return t.app !== false; });
  }

  function toolsForInputs(changed) {
    var tools = appTools();
    if (!changed) return tools;
    return tools.filter(function (t) {
      var args = t.args || [];
      for (var i = 0; i < changed.length; i++) {
        if (args.indexOf(changed[i]) >= 0) return true;
      }
      return false;
    });
  }

  function toolArguments(tool) {
    var out = {};
    each(tool.args || [], function (arg) {
      var a = adapters[arg];
      if (!a || a.unsupported) return;
      var v = a.get();
      if (v !== null && v !== undefined) out[arg] = v;
    });
    return out;
  }

  function callMeta() {
    var meta = { "shinymcp/caller": "app", "shinymcp/deps": keys(state.loadedDeps) };
    return meta;
  }

  function callTools(tools) {
    each(tools, function (tool) {
      markRecalculating(tool.outputs, true);
      callTool(tool.name, toolArguments(tool)).then(
        function (result) {
          markRecalculating(tool.outputs, false);
          handleResult(result, {});
        },
        function (err) {
          markRecalculating(tool.outputs, false);
          showError("The " + tool.name + " tool failed: " + err.message);
        }
      );
    });
  }

  function callTool(name, args) {
    setBusy(1);
    return request("tools/call", { name: name, arguments: args || {}, _meta: callMeta() }).then(
      function (result) {
        setBusy(-1);
        return result;
      },
      function (err) {
        setBusy(-1);
        throw err;
      }
    );
  }

  // After the host's first result, run the other tools once so every output
  // fills in, except tools that say they change something.
  function fillRemainingOutputs(firstTool) {
    var tools = appTools().filter(function (t) {
      return t.name !== firstTool && t.readOnly !== false && t.destructive !== true;
    });
    if (tools.length) callTools(tools);
  }

  // ---------------------------------------------------------------------------
  // Shiny mode: the view's session in R
  // ---------------------------------------------------------------------------

  var inFlight = false;
  var queued = null;

  function outputSizes() {
    var sizes = {};
    each(document.querySelectorAll(".shiny-plot-output[id], .shiny-image-output[id]"), function (el) {
      var w = el.clientWidth;
      var h = el.clientHeight;
      if (w > 0 && h > 0) sizes[el.id] = { width: w, height: h };
    });
    return sizes;
  }

  // What the R session may want to know about the chat client.
  function hostSummary() {
    var ctx = state.hostContext;
    var out = {};
    each(["theme", "displayMode", "locale", "timeZone", "platform"], function (k) {
      if (typeof ctx[k] === "string") out[k] = ctx[k];
    });
    return out;
  }

  function inputKinds(ids) {
    var kinds = {};
    each(ids, function (id) {
      var a = adapters[id];
      if (a) kinds[id] = a.dataType ? { kind: a.kind, dataType: a.dataType } : { kind: a.kind };
    });
    return kinds;
  }

  function viewUpdate(changed, extra) {
    var payload = assign(
      {
        action: "update",
        inputs: readInputs(),
        changed: changed,
        kinds: inputKinds(keys(adapters)),
        sizes: outputSizes(),
        pixelRatio: Math.min(window.devicePixelRatio || 1, 2),
        host: hostSummary()
      },
      extra
    );
    if (state.instance) payload.instance = state.instance;
    if (state.viewRevision) payload.revision = state.viewRevision;
    if (inFlight) {
      // One call at a time: fold later changes into the next call.
      queued = queued || { changed: {} };
      each(changed, function (id) { queued.changed[id] = true; });
      return;
    }
    inFlight = true;
    return callTool(config.runtime.viewTool, payload).then(
      function (result) {
        inFlight = false;
        handleResult(result, {});
        flushQueue();
      },
      function (err) {
        inFlight = false;
        showError("The app's R session didn't respond: " + err.message);
        flushQueue();
      }
    );
  }

  function flushQueue() {
    if (!queued) return;
    var ids = keys(queued.changed);
    queued = null;
    viewUpdate(ids, {});
  }

  function closeView() {
    if (MODE !== "shiny" || !state.instance || !config.runtime) return;
    // Best effort: the host may already be gone.
    request("tools/call", {
      name: config.runtime.viewTool,
      arguments: { action: "close", instance: state.instance },
      _meta: callMeta()
    })["catch"](function () {});
  }

  function download(outputId) {
    if (MODE !== "shiny") return;
    setBusy(1);
    request("tools/call", {
      name: config.runtime.viewTool,
      arguments: {
        action: "download",
        instance: state.instance,
        output: outputId,
        inputs: readInputs()
      },
      _meta: callMeta()
    }).then(
      function (result) {
        setBusy(-1);
        if (result && result.isError) {
          showError(resultText(result));
          return;
        }
        var view = viewMeta(result);
        if (view && view.instance) state.instance = view.instance;
        if (view && view.download) saveFile(view.download);
      },
      function (err) {
        setBusy(-1);
        showError("Download failed: " + err.message);
      }
    );
  }

  // Ask the host to save a file; sandboxed pages can't download themselves.
  function saveFile(file) {
    var resource = {
      uri: "file:///" + encodeURIComponent(file.filename || "download"),
      mimeType: file.mimeType || "application/octet-stream",
      blob: file.data
    };
    return request("ui/download-file", {
      contents: [{ type: "resource", resource: resource }]
    }).then(
      function (result) {
        if (result && result.isError) showToast({ html: "The download was cancelled.", type: "warning" });
      },
      function () {
        showToast({
          html: "This chat client doesn't support downloads from apps.",
          type: "warning"
        });
      }
    );
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  function viewMeta(result) {
    return result && result._meta ? result._meta[VIEW_META] : null;
  }

  function resultText(result) {
    var parts = [];
    each((result && result.content) || [], function (block) {
      if (block && block.type === "text") parts.push(block.text || "");
    });
    return parts.join("\n");
  }

  function handleResult(result, opts) {
    if (!result) return;
    var view = viewMeta(result);
    if (result.isError) {
      showError(resultText(result) || "The tool reported an error.");
    } else {
      clearError();
    }

    if (view) {
      if (opts.initial && view.tool && !state.entryTool) state.entryTool = view.tool;
      if (view.instance) state.instance = view.instance;
      if (typeof view.revision === "number") state.viewRevision = view.revision;
      if (view.inputs) setInputsSilently(view.inputs);
      each(view.inputMessages || [], function (m) { receiveInputMessage(m.id, m.message); });
      if (view.outputs) renderOutputs(view.outputs);
      if (view.result) renderSingle(view.result);
      each(view.notifications || [], handleNotification);
      each(view.modals || [], handleModal);
      each(view.uiChanges || [], handleUiChange);
      each(view.customMessages || [], function (m) { dispatchCustomMessage(m.type, m.message); });
      each(view.messages || [], function (text) { sendMessage(text); });
      if (view.modelContext && config.modelContext !== false) publishModelContext(view.modelContext);
      if (view.restarted) logWarn("the app's R session was restarted; state kept outside inputs was reset");
    } else if (result.structuredContent && typeof result.structuredContent === "object") {
      renderFromStructured(result.structuredContent);
    } else if (!result.isError) {
      var text = resultText(result);
      if (text) renderSingle({ kind: "text", value: text });
    }

    if (opts.initial && !state.firstResult) {
      state.firstResult = true;
      afterFirstResult(result, view);
    }
  }

  var hostTimer = null;
  function scheduleHostRefresh() {
    if (hostTimer) clearTimeout(hostTimer);
    hostTimer = setTimeout(function () {
      hostTimer = null;
      if (state.instance) viewUpdate([], {});
    }, 100);
  }

  function afterFirstResult(result, view) {
    initialSnapshot = readInputs();
    if (MODE === "shiny") {
      if (!view || !view.instance) {
        // The host dropped the result's _meta; start a session of our own.
        viewUpdate([], { all: true });
        return;
      }
      // Tell the session about this page (plot sizes, pixel density, theme):
      // the model's call that opened it knew none of that.
      setTimeout(function () {
        viewUpdate([], {});
      }, 50);
      observePlotSizes();
    } else {
      fillRemainingOutputs(state.entryTool);
    }
  }

  function needsResize() {
    var ratio = Math.min(window.devicePixelRatio || 1, 2);
    var needed = false;
    each(document.querySelectorAll(".shiny-plot-output[id] img"), function (img) {
      var out = img.parentNode;
      var rendered = parseFloat(img.getAttribute("data-shinymcp-width") || img.getAttribute("width") || 0);
      if (ratio > 1.2 || (rendered && Math.abs(out.clientWidth - rendered) > Math.max(8, rendered * 0.05))) {
        needed = true;
      }
    });
    return needed;
  }

  function observePlotSizes() {
    if (typeof ResizeObserver === "undefined") return;
    var resizeTimer = null;
    var observer = new ResizeObserver(function () {
      if (resizeTimer) clearTimeout(resizeTimer);
      resizeTimer = setTimeout(function () {
        if (needsResize()) viewUpdate([], {});
      }, 300);
    });
    each(document.querySelectorAll(".shiny-plot-output[id]"), function (el) { observer.observe(el); });
  }

  // Results from older servers or hosts that drop _meta: strings keyed by
  // output id.
  function renderFromStructured(structured) {
    var outputs = {};
    each(keys(structured), function (id) {
      var v = structured[id];
      if (typeof v === "string" && findOutput(id)) outputs[id] = { kind: "text", value: v };
    });
    renderOutputs(outputs);
  }

  // ---------------------------------------------------------------------------
  // Outputs
  // ---------------------------------------------------------------------------

  function findOutput(id) {
    var el = document.querySelector('[data-shinymcp-output="' + cssEscape(id) + '"]');
    return el || byId(id);
  }

  function allOutputs() {
    return document.querySelectorAll(
      "[data-shinymcp-output], .shiny-text-output[id], .shiny-html-output[id], .shiny-plot-output[id], .shiny-image-output[id], .html-widget-output[id]"
    );
  }

  function markRecalculating(ids, on) {
    each(ids || [], function (id) {
      var el = findOutput(id);
      if (el) el.classList.toggle("recalculating", !!on);
    });
  }

  // One output that fails to draw shouldn't stop the others.
  function renderOutputs(outputs) {
    each(keys(outputs), function (id) {
      var payload = outputs[id] || {};
      var el = findOutput(payload.dom || id);
      if (!el) return;
      safeRender(el, payload, id);
    });
  }

  function safeRender(el, payload, id) {
    try {
      renderInto(el, payload, id);
    } catch (e) {
      logWarn("couldn't draw output " + id, e);
      el.textContent = "This output couldn't be drawn: " + (e && e.message ? e.message : e);
      el.classList.add("shiny-output-error");
    }
  }

  function renderSingle(payload) {
    var outputs = allOutputs();
    if (outputs.length === 1) safeRender(outputs[0], payload, outputs[0].id);
  }

  function clearOutputError(el) {
    el.classList.remove("shiny-output-error", "shiny-output-error-validation", "recalculating");
  }

  function renderInto(el, payload, id) {
    var kind = payload.kind || "text";
    if (kind === "keep") return;
    loadDeps(payload.deps);
    clearOutputError(el);
    var declared = el.getAttribute("data-shinymcp-output-type");

    switch (kind) {
      case "clear":
        el.innerHTML = "";
        break;
      case "error":
        el.textContent = payload.value || "";
        el.classList.add("shiny-output-error");
        if (payload.validation) el.classList.add("shiny-output-error-validation");
        break;
      case "text":
        if (declared === "html" || declared === "table") el.innerHTML = payload.value;
        else if (declared === "plot") renderImage(el, { src: "data:image/png;base64," + payload.value });
        else el.textContent = payload.value === null || payload.value === undefined ? "" : payload.value;
        break;
      case "html":
      case "table":
        setHtml(el, payload.value);
        break;
      case "plot":
      case "image":
        renderImage(el, typeof payload.value === "string" ? { src: payload.value } : payload.value);
        break;
      case "widget":
        if (typeof payload.value === "string" && payload.value.charAt(0) === "{") {
          renderWidget(el, payload.value);
        } else {
          setHtml(el, payload.value);
        }
        break;
      case "download":
        renderDownload(el, payload, id);
        break;
      default:
        el.textContent = String(payload.value);
    }
  }

  function renderImage(el, img) {
    if (!img || !img.src) {
      el.innerHTML = "";
      return;
    }
    var existing = el.querySelector("img[data-shinymcp-img]");
    var image = existing || document.createElement("img");
    image.setAttribute("data-shinymcp-img", "");
    image.src = img.src;
    image.alt = img.alt || "";
    if (img.width) image.setAttribute("data-shinymcp-width", img.width);
    if (img.style) image.setAttribute("style", img.style);
    if (!existing) {
      el.innerHTML = "";
      el.appendChild(image);
    }
  }

  function renderDownload(el, payload, id) {
    var value = payload.value || {};
    if (value.data) {
      // A file returned by a tool (mcp_result_pdf()).
      el.innerHTML = "";
      var button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-default btn-outline-secondary shinymcp-download";
      button.textContent = value.label || "Download " + (value.filename || "file");
      button.addEventListener("click", function () { saveFile(value); });
      el.appendChild(button);
      return;
    }
    // A Shiny downloadButton(): enable it and fetch the file on click.
    el.classList.remove("disabled");
    el.removeAttribute("aria-disabled");
    el.removeAttribute("tabindex");
    if (!el.__shinymcpDownload) {
      el.__shinymcpDownload = true;
      el.addEventListener("click", function (e) {
        e.preventDefault();
        download(id);
      });
    }
  }

  // Insert HTML the way Shiny does: run inline scripts, render widgets, and
  // pick up new inputs and outputs.
  function setHtml(el, html) {
    el.innerHTML = html === null || html === undefined ? "" : html;
    runScripts(el);
    afterDomChange(el);
  }

  function runScripts(root) {
    each(root.querySelectorAll("script"), function (old) {
      var type = (old.getAttribute("type") || "").toLowerCase();
      if (type && type !== "text/javascript" && type !== "module" && type !== "application/javascript") return;
      var script = document.createElement("script");
      each(old.attributes, function (attr) { script.setAttribute(attr.name, attr.value); });
      script.textContent = old.textContent;
      old.parentNode.replaceChild(script, old);
    });
  }

  function afterDomChange(root) {
    if (window.HTMLWidgets && root.querySelector && root.querySelector(".html-widget")) {
      try {
        window.HTMLWidgets.staticRender();
      } catch (e) {
        logWarn("widget render failed", e);
      }
    }
    if (MODE === "shiny") scanInputs(root);
  }

  // Widgets that keep their data in R (DT's server-side tables) fetch it
  // with jQuery from a Shiny data URL, session/<token>/dataobj/<name>.
  // Answer those requests through the view tool: the page can't reach R
  // over the network.
  var DATA_URL = /^session\/[a-z0-9]+\/dataobj\/([^?]+)/;
  var dataTransportInstalled = false;

  function installDataTransport() {
    var $ = window.jQuery;
    if (dataTransportInstalled || MODE !== "shiny" || !$ || !$.ajaxTransport) return;
    dataTransportInstalled = true;
    $.ajaxTransport("+*", function (options) {
      var url = String(options.url || "");
      var match = DATA_URL.exec(url);
      if (!match) return undefined;
      var aborted = false;
      return {
        send: function (headers, complete) {
          var name = decodeURIComponent(match[1]);
          // GET requests carry their parameters in the URL.
          var query = url.indexOf("?") >= 0 ? url.slice(url.indexOf("?") + 1) : "";
          var body = typeof options.data === "string" ? options.data : options.data ? $.param(options.data) : "";
          if (!body) body = query;
          callTool(config.runtime.viewTool, {
            action: "data",
            instance: state.instance,
            output: name,
            body: body
          }).then(
            function (result) {
              if (aborted) return;
              var view = viewMeta(result);
              if (!result || result.isError || !view || typeof view.data !== "string") {
                complete(500, "error", { text: resultText(result) || "No data." });
                return;
              }
              complete(200, "success", { text: view.data }, "Content-Type: application/json");
            },
            function (err) {
              if (!aborted) complete(500, "error", { text: err.message });
            }
          );
        },
        abort: function () {
          aborted = true;
        }
      };
    });
  }

  // htmlwidgets turn the JavaScript in a widget's options (htmlwidgets::JS())
  // into functions with eval(), which the Content Security Policy of an MCP
  // App forbids. Inline scripts are allowed, so evaluate through one.
  var evalCount = 0;

  function evalScript(code) {
    var slot = "__shinymcpEval" + evalCount++;
    var script = document.createElement("script");
    script.textContent = "window." + slot + " = (" + code + "\n);";
    document.head.appendChild(script);
    document.head.removeChild(script);
    var value = window[slot];
    try {
      delete window[slot];
    } catch (e) {
      window[slot] = undefined;
    }
    return value;
  }

  // The same walk as HTMLWidgets.evaluateStringMember(): a dotted path, with
  // "\." for a dot inside a name.
  function splitMemberPath(member) {
    var parts = [];
    var current = "";
    var str = String(member);
    for (var i = 0; i < str.length; i++) {
      var ch = str.charAt(i);
      if (ch === "\\" && str.charAt(i + 1) === ".") {
        current += ".";
        i++;
      } else if (ch === ".") {
        parts.push(current);
        current = "";
      } else {
        current += ch;
      }
    }
    parts.push(current);
    return parts;
  }

  function evaluateStringMember(obj, member) {
    var parts = splitMemberPath(member);
    for (var i = 0; i < parts.length; i++) {
      var part = parts[i];
      if (obj === null || typeof obj !== "object" || !(part in obj)) return;
      if (i === parts.length - 1) {
        if (typeof obj[part] === "string") obj[part] = evalScript(obj[part]);
      } else {
        obj = obj[part];
      }
    }
  }

  function patchHtmlwidgets() {
    var hw = window.HTMLWidgets;
    if (hw && !hw.__shinymcpPatched) {
      hw.__shinymcpPatched = true;
      hw.evaluateStringMember = evaluateStringMember;
    }
  }

  // Render an htmlwidget output from the JSON a Shiny render function sends.
  function renderWidget(el, json) {
    installDataTransport();
    patchHtmlwidgets();
    var data;
    try {
      data = JSON.parse(json);
    } catch (e) {
      logWarn("bad widget data", e);
      return;
    }
    var bindings = (window.HTMLWidgets && window.HTMLWidgets.widgets) || [];
    var binding = null;
    each(bindings, function (b) { if (!binding && hasClass(el, b.name)) binding = b; });
    if (!binding) {
      el.textContent = "This widget's JavaScript isn't loaded.";
      return;
    }
    if (!el.__shinymcpWidget) {
      el.__shinymcpWidget = {
        instance: binding.initialize ? binding.initialize(el, el.offsetWidth, el.offsetHeight) : null
      };
      if (binding.resize && typeof ResizeObserver !== "undefined") {
        new ResizeObserver(function () {
          binding.resize(el, el.offsetWidth, el.offsetHeight, el.__shinymcpWidget.instance);
        }).observe(el);
      }
    }
    var instance = el.__shinymcpWidget.instance;
    if (data.evals && window.HTMLWidgets.evaluateStringMember) {
      each(Array.isArray(data.evals) ? data.evals : [data.evals], function (member) {
        window.HTMLWidgets.evaluateStringMember(data.x, member);
      });
    }
    binding.renderValue(el, data.x, instance);
    var hooks = data.jsHooks && data.jsHooks.render;
    each(hooks || [], function (hook) {
      try {
        var code = typeof hook === "object" ? hook.code : hook;
        var extra = typeof hook === "object" ? [hook.data] : [];
        var fn = evalScript(code);
        fn.apply(instance, [el, data.x].concat(extra));
      } catch (e) {
        logWarn("widget hook failed", e);
      }
    });
  }

  // HTML dependencies arrive with outputs that need them. Load each library
  // once, whatever the version: a second copy of jQuery, say, would replace
  // the first and drop the plugins attached to it.
  function loadDeps(deps) {
    each(deps || [], function (dep) {
      var key = dep.name + "@" + dep.version;
      if (state.loadedDeps[key] || state.loadedNames[dep.name]) return;
      state.loadedDeps[key] = true;
      state.loadedNames[dep.name] = true;
      var holder = document.createElement("div");
      holder.innerHTML = dep.head || "";
      each(Array.prototype.slice.call(holder.childNodes), function (node) {
        if (node.nodeType !== 1) return;
        var tag = node.tagName.toLowerCase();
        if (tag === "script") {
          var script = document.createElement("script");
          each(node.attributes, function (attr) { script.setAttribute(attr.name, attr.value); });
          script.textContent = node.textContent;
          document.head.appendChild(script);
        } else {
          document.head.appendChild(node);
        }
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Messages from the R session (runtime mode)
  // ---------------------------------------------------------------------------

  function receiveInputMessage(id, message) {
    var a = adapters[id];
    if (!a || !a.receiveMessage) return;
    applying = true;
    try {
      a.receiveMessage(message || {});
    } finally {
      applying = false;
    }
  }

  var toastRoot = null;
  var toasts = {};

  function showToast(opts) {
    if (!toastRoot) {
      toastRoot = document.createElement("div");
      toastRoot.id = "shinymcp-notifications";
      toastRoot.setAttribute("role", "status");
      document.body.appendChild(toastRoot);
    }
    var id = opts.id || "toast-" + nextId++;
    removeToast(id);
    var box = document.createElement("div");
    box.className = "shinymcp-notification shinymcp-notification-" + (opts.type || "default");
    var body = document.createElement("div");
    body.innerHTML = opts.html || "";
    box.appendChild(body);
    if (opts.closeButton !== false) {
      var close = document.createElement("button");
      close.type = "button";
      close.setAttribute("aria-label", "Close");
      close.textContent = "×";
      close.addEventListener("click", function () { removeToast(id); });
      box.appendChild(close);
    }
    toastRoot.appendChild(box);
    toasts[id] = box;
    var duration = opts.duration === undefined ? 5000 : opts.duration;
    if (duration) setTimeout(function () { removeToast(id); }, duration);
  }

  function removeToast(id) {
    var box = toasts[id];
    if (box && box.parentNode) box.parentNode.removeChild(box);
    delete toasts[id];
  }

  function handleNotification(n) {
    var msg = n.message || {};
    loadDeps(msg.deps);
    if (n.type === "remove") {
      removeToast(msg.id || msg);
      return;
    }
    showToast({
      id: msg.id,
      html: (msg.html || "") + (msg.action || ""),
      type: msg.type,
      duration: msg.duration === null ? 0 : msg.duration,
      closeButton: msg.closeButton
    });
  }

  var modalBackdrop = null;

  function closeModal() {
    if (modalBackdrop && modalBackdrop.parentNode) modalBackdrop.parentNode.removeChild(modalBackdrop);
    modalBackdrop = null;
  }

  function handleModal(m) {
    if (m.type === "remove") {
      closeModal();
      return;
    }
    var msg = m.message || {};
    loadDeps(msg.deps);
    closeModal();
    modalBackdrop = document.createElement("div");
    modalBackdrop.className = "shinymcp-modal-backdrop";
    modalBackdrop.innerHTML = msg.html || "";
    document.body.appendChild(modalBackdrop);
    var modal = modalBackdrop.querySelector(".modal");
    if (modal) {
      modal.classList.add("show");
      modal.style.display = "block";
    }
    var easyClose = modal && modal.getAttribute("data-bs-backdrop") !== "static" && modal.getAttribute("data-backdrop") !== "static";
    modalBackdrop.addEventListener("click", function (e) {
      var dismiss = e.target.closest ? e.target.closest('[data-dismiss="modal"], [data-bs-dismiss="modal"]') : null;
      if (dismiss || (easyClose && e.target === modalBackdrop)) closeModal();
    });
    runScripts(modalBackdrop);
    afterDomChange(modalBackdrop);
  }

  // insertTab(), removeTab(), hideTab() and showTab(), as Shiny's client
  // does them.
  function tabTargets(ul, target) {
    var a = tabAnchor(ul, target);
    if (!a) {
      var any = ul.querySelectorAll("a[data-value]");
      for (var i = 0; i < any.length; i++) {
        if (any[i].getAttribute("data-value") === String(target)) a = any[i];
      }
    }
    if (!a) return null;
    var panes = [];
    var content = tabContent(ul);
    if (content) {
      var menu = a.nextElementSibling;
      if (menu && hasClass(menu, "dropdown-menu")) {
        // A menu: every tab in it.
        var menuId = menu.getAttribute("data-tabsetid");
        each(content.querySelectorAll('.tab-pane[id^="tab-' + menuId + '-"]'), function (p) { panes.push(p); });
      } else {
        var pane = content.querySelector('.tab-pane[data-value="' + cssEscape(String(target)) + '"]');
        if (pane) panes.push(pane);
      }
    }
    return { li: a.parentNode, panes: panes };
  }

  function ensureShownTab(ul) {
    if (shownTab(ul) !== null) return;
    var anchors = ul.querySelectorAll("a[data-value]");
    for (var i = 0; i < anchors.length; i++) {
      var a = anchors[i];
      var toggle = a.getAttribute("data-bs-toggle") || a.getAttribute("data-toggle");
      if (toggle === "tab" && a.parentNode.style.display !== "none") {
        activateTab(a);
        return;
      }
    }
  }

  function tabIndex(ul, tabsetId) {
    var highest = 0;
    each(ul.querySelectorAll("a[href]"), function (a) {
      var match = (a.getAttribute("href") || "").match(new RegExp("#tab-" + tabsetId + "-([0-9]+)$"));
      if (match) highest = Math.max(highest, Number(match[1]));
    });
    return highest + 1;
  }

  function handleTabChange(change) {
    var ul = byId(change.id);
    if (!ul) return;
    if (change.op === "tab-visibility" || change.op === "remove-tab") {
      var found = tabTargets(ul, change.target);
      if (!found) return;
      var items = [found.li].concat(found.panes);
      each(items, function (el) {
        if (change.op === "remove-tab") {
          if (el.parentNode) el.parentNode.removeChild(el);
        } else if (change.type === "show") {
          el.style.display = "";
        } else {
          el.style.display = "none";
          el.classList.remove("active");
        }
      });
      ensureShownTab(ul);
      if (ul.__shinymcpAdapter) ul.__shinymcpAdapter.check();
      return;
    }
    // insert-tab
    var li = change.li || {};
    var div = change.div || {};
    loadDeps(li.deps);
    loadDeps(div.deps);
    var holder = document.createElement("div");
    holder.innerHTML = li.html || "";
    var item = holder.querySelector("li");
    if (!item) return;
    var tabset = ul;
    var tabsetId = ul.getAttribute("data-tabsetid");
    if (change.menu) {
      var toggle = ul.querySelector('a.dropdown-toggle[data-value="' + cssEscape(change.menu) + '"]');
      var menu = toggle ? toggle.nextElementSibling : null;
      if (menu && hasClass(menu, "dropdown-menu")) {
        tabset = menu;
        tabsetId = menu.getAttribute("data-tabsetid");
      }
    }
    var link = item.querySelector("a");
    var paneId = null;
    if (link && (link.getAttribute("data-bs-toggle") || link.getAttribute("data-toggle")) === "tab") {
      paneId = "tab-" + tabsetId + "-" + tabIndex(tabset, tabsetId);
      link.setAttribute("href", "#" + paneId);
      if (link.hasAttribute("data-bs-target")) link.setAttribute("data-bs-target", "#" + paneId);
    }
    var target = change.target !== undefined && change.target !== null ? tabTargets(ul, change.target) : null;
    if (target && target.li.parentNode) {
      target.li.parentNode.insertBefore(item, change.position === "before" ? target.li : target.li.nextSibling);
    } else if (change.position === "before") {
      tabset.insertBefore(item, tabset.firstChild);
    } else {
      tabset.appendChild(item);
    }
    var content = tabContent(ul);
    if (content) {
      var paneHolder = document.createElement("div");
      paneHolder.innerHTML = div.html || "";
      var nodes = Array.prototype.slice.call(paneHolder.childNodes);
      each(nodes, function (node) {
        content.appendChild(node);
        if (node.nodeType === 1) {
          if (paneId && node.id === "tab-tsid-id") node.id = paneId;
          runScripts(node);
          afterDomChange(node);
        }
      });
    }
    afterDomChange(item);
    if (change.select && link) {
      activateTab(link);
      if (ul.__shinymcpAdapter) ul.__shinymcpAdapter.check();
    }
  }

  function handleUiChange(change) {
    if (change.op === "tab-visibility" || change.op === "remove-tab" || change.op === "insert-tab") {
      handleTabChange(change);
      return;
    }
    if (change.op === "remove") {
      var targets = change.multiple
        ? document.querySelectorAll(change.selector)
        : [document.querySelector(change.selector)];
      each(targets, function (el) {
        if (el && el.parentNode) el.parentNode.removeChild(el);
      });
      return;
    }
    if (change.op !== "insert") return;
    var content = change.content || {};
    loadDeps(content.deps);
    var where = { beforeBegin: "beforebegin", afterBegin: "afterbegin", beforeEnd: "beforeend", afterEnd: "afterend" }[change.where] || "beforeend";
    var places = change.multiple
      ? document.querySelectorAll(change.selector)
      : [document.querySelector(change.selector)];
    each(places, function (el) {
      if (!el) return;
      var holder = document.createElement("div");
      holder.innerHTML = content.html || "";
      var nodes = Array.prototype.slice.call(holder.childNodes);
      var parent = where === "beforebegin" || where === "afterend" ? el.parentNode : el;
      each(nodes, function (node) {
        if (where === "beforebegin") parent.insertBefore(node, el);
        else if (where === "afterbegin") parent.insertBefore(node, el.firstChild);
        else if (where === "afterend") parent.insertBefore(node, el.nextSibling);
        else parent.appendChild(node);
        if (node.nodeType === 1) {
          runScripts(node);
          afterDomChange(node);
        }
      });
    });
  }

  function dispatchCustomMessage(type, message) {
    var handler = state.customHandlers[type];
    if (handler) {
      try {
        handler(message);
      } catch (e) {
        logWarn("custom message handler failed for " + type, e);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Model context
  // ---------------------------------------------------------------------------

  var MAX_CONTEXT_BYTES = 4000;
  var contextTimer = null;

  function publishModelContext(params) {
    if (!params) return;
    state.revision++;
    if (params.structuredContent && typeof params.structuredContent === "object") {
      params.structuredContent.revision = state.revision;
    }
    request("ui/update-model-context", params)["catch"](function (err) {
      logWarn("the host did not accept a context update", err && err.message);
    });
  }

  function describeValue(v) {
    if (v === null || v === undefined) return "none";
    if (Array.isArray(v)) return v.length ? v.join(", ") : "none";
    var s = String(v);
    return s.length > 200 ? s.slice(0, 200) + "..." : s;
  }

  // In "tools" mode the page itself tells the model what the user changed.
  // In "shiny" mode the R session decides (mcp_model_context()).
  function scheduleModelContext() {
    if (MODE !== "tools" || config.modelContext === false) return;
    if (contextTimer) clearTimeout(contextTimer);
    contextTimer = setTimeout(function () {
      contextTimer = null;
      var inputs = {};
      var parts = [];
      each(keys(adapters), function (id) {
        var a = adapters[id];
        if (a.secret || a.unsupported || a.event) return;
        var v = a.get();
        inputs[id] = v;
        var label = labelFor(a);
        parts.push((label ? label.textContent.trim() : id) + " = " + describeValue(v));
      });
      var text = "In the " + (config.app || "app") + " app, the user set: " + parts.join("; ") + ".";
      var structured = { app: config.app, inputs: inputs };
      if (JSON.stringify(structured).length > MAX_CONTEXT_BYTES) {
        structured = { app: config.app, note: "Input values too large to include." };
      }
      publishModelContext({ content: [{ type: "text", text: text }], structuredContent: structured });
    }, Math.max(DEBOUNCE_MS, 400));
  }

  // ---------------------------------------------------------------------------
  // Busy state and errors
  // ---------------------------------------------------------------------------

  var busyTimer = null;
  function setBusy(delta) {
    state.busy = Math.max(0, state.busy + delta);
    var root = document.documentElement;
    if (state.busy > 0) {
      if (!busyTimer && !root.classList.contains("shinymcp-busy")) {
        busyTimer = setTimeout(function () {
          busyTimer = null;
          if (state.busy > 0) root.classList.add("shinymcp-busy");
        }, 150);
      }
    } else {
      if (busyTimer) {
        clearTimeout(busyTimer);
        busyTimer = null;
      }
      root.classList.remove("shinymcp-busy");
    }
  }

  var errorBanner = null;
  function showError(message) {
    if (!document.body) return;
    if (!errorBanner) {
      errorBanner = document.createElement("div");
      errorBanner.id = "shinymcp-error";
      errorBanner.setAttribute("role", "alert");
      var text = document.createElement("div");
      text.className = "shinymcp-error-text";
      var close = document.createElement("button");
      close.type = "button";
      close.setAttribute("aria-label", "Dismiss");
      close.textContent = "×";
      close.addEventListener("click", clearError);
      errorBanner.appendChild(text);
      errorBanner.appendChild(close);
      document.body.insertBefore(errorBanner, document.body.firstChild);
    }
    errorBanner.querySelector(".shinymcp-error-text").textContent = message;
    errorBanner.hidden = false;
  }

  function clearError() {
    if (errorBanner) errorBanner.hidden = true;
  }

  // ---------------------------------------------------------------------------
  // Host requests the page can make
  // ---------------------------------------------------------------------------

  function sendMessage(text) {
    return request("ui/message", {
      role: "user",
      content: [{ type: "text", text: String(text) }]
    });
  }

  // ---------------------------------------------------------------------------
  // Size reporting (the SDK's approach: height at max-content, width of the
  // viewport, sent only when it changes)
  // ---------------------------------------------------------------------------

  function setupAutoResize() {
    var lastW = 0;
    var lastH = 0;
    var scheduled = false;
    function measure() {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(function () {
        scheduled = false;
        var html = document.documentElement;
        var original = html.style.height;
        html.style.height = "max-content";
        var h = Math.ceil(html.getBoundingClientRect().height);
        html.style.height = original;
        var w = Math.ceil(window.innerWidth);
        if (w !== lastW || h !== lastH) {
          lastW = w;
          lastH = h;
          notify("ui/notifications/size-changed", { width: w, height: h });
        }
      });
    }
    measure();
    if (typeof ResizeObserver !== "undefined") {
      var observer = new ResizeObserver(measure);
      observer.observe(document.documentElement);
      observer.observe(document.body);
    }
  }

  // ---------------------------------------------------------------------------
  // Start-up
  // ---------------------------------------------------------------------------

  function setupSubmit() {
    if (TRIGGER !== "submit") return;
    submitButton = document.querySelector("[data-shinymcp-submit], button.shiny-submit-button, button[type='submit']");
    if (!submitButton) {
      var bar = document.createElement("div");
      bar.className = "shinymcp-submit-bar";
      submitButton = document.createElement("button");
      submitButton.type = "button";
      submitButton.className = "btn btn-primary";
      submitButton.textContent = "Apply";
      bar.appendChild(submitButton);
      (document.querySelector(".shinymcp-app") || document.body).appendChild(bar);
    }
    submitButton.disabled = true;
    submitButton.addEventListener("click", function (e) {
      e.preventDefault();
      runPending(true);
    });
  }

  // The host normally sends the model's tool call (tool-input, then
  // tool-result) right after start-up. A page opened any other way, or a
  // host that sends neither, gets its first outputs by calling tools itself.
  function selfInit() {
    if (state.firstResult) return;
    state.firstResult = true;
    initialSnapshot = readInputs();
    if (MODE === "shiny") {
      viewUpdate([], { all: true }).then(observePlotSizes);
    } else {
      callTools(appTools().filter(function (t) { return t.readOnly !== false && t.destructive !== true; }));
    }
  }

  function init() {
    scanInputs(document);
    setupSubmit();
    window.addEventListener("message", onMessage);
    each(document.querySelectorAll(".shiny-download-link[id]"), function (el) {
      if (MODE === "shiny") renderDownload(el, {}, el.id);
    });

    if (!connected) {
      logWarn("not inside an MCP host; the page will not call any tools");
      return;
    }

    var availableModes = ["inline", "fullscreen"];
    request("ui/initialize", {
      protocolVersion: APPS_PROTOCOL_VERSION,
      appInfo: { name: config.app || "shinymcp-app", version: config.version || "0.0.0" },
      appCapabilities: { availableDisplayModes: availableModes }
    }).then(
      function (result) {
        result = result || {};
        state.initialized = true;
        state.hostCapabilities = result.hostCapabilities || {};
        state.hostInfo = result.hostInfo || {};
        applyHostContext(result.hostContext || {});
        notify("ui/notifications/initialized", {});
        setupAutoResize();
        // Give the host a moment to send the model's tool call.
        setTimeout(function () {
          if (!state.toolInputSeen && !state.toolResultSeen) selfInit();
        }, 1200);
      },
      function (err) {
        logWarn("ui/initialize failed", err && err.message);
      }
    );
  }

  function teardown() {
    if (tornDown) return;
    tornDown = true;
    window.removeEventListener("message", onMessage);
    if (timer) clearTimeout(timer);
    if (contextTimer) clearTimeout(contextTimer);
    each(keys(pending), function (id) {
      pending[id].reject(new Error("The app has been closed."));
    });
    pending = {};
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  window.shinymcp = {
    __bridge: true,
    version: config.version,
    // Call one of the app's tools. Resolves with the MCP result.
    callTool: function (name, args) {
      return callTool(name, args || {});
    },
    // Read a resource the app declared (mcp_app(resources = )).
    readResource: function (uri) {
      return request("resources/read", { uri: uri });
    },
    // Replace what the model knows about this app.
    updateModelContext: function (context) {
      if (typeof context === "string") context = { content: [{ type: "text", text: context }] };
      else if (context && !context.content && !context.structuredContent) context = { structuredContent: context };
      return request("ui/update-model-context", context);
    },
    // Post a message to the chat as the user.
    sendMessage: sendMessage,
    openLink: function (url) {
      return request("ui/open-link", { url: String(url) });
    },
    requestDisplayMode: function (mode) {
      var available = state.hostContext.availableDisplayModes;
      if (Array.isArray(available) && available.indexOf(mode) < 0) {
        return Promise.resolve({ mode: state.hostContext.displayMode || "inline" });
      }
      return request("ui/request-display-mode", { mode: mode });
    },
    // Save a file: {filename, mimeType, data (base64) or text}.
    downloadFile: function (file) {
      if (file && typeof file.text === "string" && !file.data) {
        return request("ui/download-file", {
          contents: [{
            type: "resource",
            resource: {
              uri: "file:///" + encodeURIComponent(file.filename || "download.txt"),
              mimeType: file.mimeType || "text/plain",
              text: file.text
            }
          }]
        });
      }
      return saveFile(file || {});
    },
    log: function (level, data) {
      notify("notifications/message", { level: level || "info", logger: config.app || "shinymcp", data: data });
    },
    getHostContext: function () {
      return assign({}, state.hostContext);
    },
    onHostContextChanged: function (fn) {
      if (typeof fn === "function") state.contextListeners.push(fn);
    },
    getInputs: function () {
      return readInputs();
    },
    // Set an input from your own JavaScript, as Shiny.setInputValue() does.
    setInputValue: function (id, value) {
      if (adapters[id]) {
        adapters[id].set(value);
        onInputChanged(adapters[id]);
        return;
      }
      adapters[id] = {
        id: id,
        kind: "unknown",
        get: function () { return value; },
        set: function (v) { value = v; },
        listeners: []
      };
      onInputChanged(adapters[id]);
    },
    addCustomMessageHandler: function (type, fn) {
      state.customHandlers[type] = fn;
    },
    // Run any changes waiting for the Apply button.
    submit: function () {
      runPending(true);
    }
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
