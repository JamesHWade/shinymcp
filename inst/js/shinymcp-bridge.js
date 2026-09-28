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

  // The same input value after a trip through R, which turns a one-element
  // array into a scalar and may turn a number into a string.
  function sameInputValue(a, b) {
    function scalar(x) {
      return Array.isArray(x) && x.length === 1 ? x[0] : x;
    }
    a = scalar(a);
    b = scalar(b);
    if (sameValue(a, b)) return true;
    return (typeof a === "number" || typeof a === "string") &&
      (typeof b === "number" || typeof b === "string") && String(a) === String(b);
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
    contextListeners: [],
    events: {},
    syncedInstance: null,
    shinyAnnounced: false,
    // Output values, for conditionalPanel() conditions that read them.
    outputValues: {}
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
      // shinyWidgets' text sliders belong to their own binding.
      if (hasClass(el, "sw-slider-text")) return null;
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
    // Values set with Shiny.setInputValue() have no element, so no label.
    if (!el) return null;
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
          if (msg.label !== undefined) setLabel(this, msg.label);
          // updateSelectizeInput(server = TRUE): the choices stay in R. The
          // selection is shown (and read) at once; the rest follow.
          if (typeof msg.url === "string") {
            var keep = msg.value !== undefined ? msg.value : this.get();
            fillServerChoices(el, [], keep);
            this.set(keep === undefined ? null : keep);
            loadServerChoices(el, this, msg.url, keep, "");
            return;
          }
          if (typeof msg.options === "string") {
            var current = this.get();
            el.innerHTML = msg.options;
            if (msg.value === undefined && !el.multiple && current !== null) {
              this.set(current);
            }
          }
          if (msg.value !== undefined) this.set(msg.value);
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

    // fileInput(): in a live app the page reads the files and sends them
    // to the session with the next update, as Shiny's client uploads them.
    // Tools have no argument for a file, so elsewhere the input is off.
    file: function (el) {
      var group = el.closest(".shiny-input-container") || el.parentNode;
      function note(text) {
        if (!group) return;
        var box = group.querySelector(".shinymcp-file-note");
        if (!box) {
          box = document.createElement("div");
          box.className = "shinymcp-file-note";
          group.appendChild(box);
        }
        box.textContent = text;
      }
      if (MODE !== "shiny") {
        el.disabled = true;
        note("File uploads need a live Shiny app.");
        return {
          get: function () { return null; },
          set: function () {},
          receiveMessage: function () {},
          unsupported: true
        };
      }
      var files = null;
      var maxBytes = typeof config.maxUploadBytes === "number" ? config.maxUploadBytes : 5 * 1024 * 1024;
      var nameBox = group ? group.querySelector('input[type="text"]') : null;
      var progress = byId(el.id + "_progress");
      function showProgress(fraction, text) {
        if (!progress) return;
        progress.style.visibility = "visible";
        var bar = progress.querySelector(".progress-bar");
        if (bar) {
          bar.style.width = Math.round(fraction * 100) + "%";
          bar.textContent = text || "";
        }
      }
      function readFile(file) {
        return new Promise(function (resolve, reject) {
          var reader = new FileReader();
          reader.onload = function () {
            var url = String(reader.result || "");
            resolve({ name: file.name, size: file.size, type: file.type || "", data: url.slice(url.indexOf(",") + 1) });
          };
          reader.onerror = function () { reject(reader.error || new Error("read failed")); };
          reader.readAsDataURL(file);
        });
      }
      return {
        // The contents go with the update that changed them, never into
        // the model's context.
        changedOnly: true,
        secret: true,
        get: function () { return files; },
        set: function () {},
        bind: function () {
          var self = this;
          listen(el, ["change"], function () {
            var list = Array.prototype.slice.call(el.files || []);
            if (!list.length) return;
            var total = 0;
            each(list, function (f) { total += f.size; });
            if (total > maxBytes) {
              note("Files up to " + Math.round(maxBytes / 1048576 * 10) / 10 + " MB can be uploaded here.");
              el.value = "";
              return;
            }
            note("");
            if (nameBox) nameBox.value = list.map(function (f) { return f.name; }).join(", ");
            showProgress(0.2, "");
            Promise.all(list.map(readFile)).then(
              function (read) {
                files = read;
                showProgress(1, "Upload complete");
                self.emit();
              },
              function (err) {
                showProgress(0, "");
                note("Couldn't read the file: " + (err && err.message ? err.message : err));
              }
            );
          });
        },
        receiveMessage: function (msg) {
          if (msg.label !== undefined) setLabel(this, msg.label);
        }
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

  // ---------------------------------------------------------------------------
  // Shiny's browser API
  // ---------------------------------------------------------------------------

  // shinymcp-shiny.js defines window.Shiny before any other script, so
  // packages can register bindings and message handlers as they load. Here
  // the page takes over what they registered.
  var shinyApi = window.Shiny && window.Shiny.__shinymcp ? window.Shiny : null;

  function toArray(list) {
    if (!list) return [];
    if (list.nodeType === 1) return [list];
    return Array.prototype.slice.call(list);
  }

  function shinyEvent(el, type, props) {
    var $ = window.jQuery;
    if (!$ || !el) return;
    try {
      $(el).trigger($.Event(type, props || {}));
    } catch (e) {
      logWarn(type + " handler failed", e);
    }
  }

  function connectShiny() {
    if (!shinyApi) return;
    var internal = shinyApi.__shinymcp;
    each(keys(internal.handlers), function (type) {
      state.customHandlers[type] = internal.handlers[type];
    });
    shinyApi.addCustomMessageHandler = function (type, fn) {
      state.customHandlers[type] = fn;
    };
    shinyApi.setInputValue = function (name, value, opts) {
      setShinyInput(name, value, opts || {});
    };
    shinyApi.bindAll = function (scope) {
      var root = scope && scope.jquery ? scope[0] : scope;
      scanInputs(root || document);
      announceOutputs(root || document);
    };
    shinyApi.initializeInputs = function () {};
    shinyApi.renderContent = function (el, content, where) {
      el = el && el.jquery ? el[0] : el;
      if (!el) return;
      var html = typeof content === "string" ? content : (content && content.html) || "";
      loadDeps(content && content.deps && content.deps[0] && content.deps[0].head ? content.deps : null);
      if (!where || where === "replace") {
        setHtml(el, html);
      } else {
        el.insertAdjacentHTML(where, html);
        runScripts(el);
        afterDomChange(el);
      }
    };
    // Bindings registered later (from a dependency that came with
    // renderUI() output, say) bind what's already on the page.
    internal.onRegister = function () {
      if (state.scanned) scanInputs(document);
    };
    var waiting = internal.pending.inputs.splice(0);
    each(waiting, function (call) {
      setShinyInput(call[0], call[1], call[2]);
    });
  }

  // Shiny.setInputValue(): a value from JavaScript rather than a form
  // element, such as a widget's click or selection. "name:type" asks for
  // the input handler registered for that type in R.
  function setShinyInput(name, value, opts) {
    name = String(name);
    var type = null;
    var colon = name.indexOf(":");
    if (colon > 0) {
      type = name.slice(colon + 1);
      name = name.slice(0, colon);
    }
    var a = adapters[name];
    if (!a) {
      a = adapters[name] = {
        id: name,
        kind: "value",
        value: null,
        get: function () { return this.value; },
        set: function (v) { this.value = v; },
        listeners: []
      };
    }
    if (a.kind === "value") {
      a.value = value === undefined ? null : value;
      if (type) a.inputType = type;
    } else {
      a.set(value);
    }
    if (opts && opts.priority === "event") {
      state.events[name] = true;
      a.event = true;
    }
    onInputChanged(a);
    if (a.kind === "value") a.event = false;
  }

  // Inputs whose package registered a Shiny input binding. They are bound
  // before shinymcp's own controls, as Shiny tries registered bindings
  // before its built-in ones.
  function bindCustomInputs(root) {
    if (!shinyApi) return;
    each(shinyApi.inputBindings.getBindings(), function (entry) {
      var binding = entry.binding;
      var found;
      try {
        found = toArray(binding.find(root));
      } catch (e) {
        logWarn("input binding " + (binding.name || "") + " failed to find inputs", e);
        return;
      }
      each(found, function (el) {
        if (el.__shinymcpAdapter) return;
        var id;
        try {
          id = binding.getId(el);
        } catch (e) {
          id = el.id;
        }
        if (!id || adapters[id]) return;
        var adapter = bindingAdapter(binding, el, id);
        el.__shinymcpAdapter = adapter;
        adapter.listeners.push(onInputChanged);
        adapters[id] = adapter;
      });
    });
  }

  function readBinding(binding, el) {
    try {
      return binding.getValue(el);
    } catch (e) {
      return undefined;
    }
  }

  function bindingAdapter(binding, el, id) {
    var $ = window.jQuery;
    try {
      binding.initialize(el);
    } catch (e) {
      logWarn("input binding " + id + " failed to initialize", e);
    }
    var type = null;
    try {
      type = binding.getType(el);
    } catch (e) {
      type = null;
    }
    var adapter = {
      id: id,
      kind: "custom",
      el: el,
      binding: binding,
      inputType: type,
      listeners: [],
      get: function () { return binding.getValue(el); },
      // Set the way the server would update it, so the widget redraws:
      // Shiny's update functions send `value`, some packages' `selected`.
      // Fall back to setValue() when that didn't take.
      set: function (v) {
        if (sameInputValue(readBinding(binding, el), v)) return;
        function failed(e) {
          logWarn("input binding " + id + " couldn't take a value", e);
        }
        try {
          var done = binding.receiveMessage(el, { value: v, selected: v });
          // bslib's bindings answer with a promise.
          if (done && typeof done.then === "function") done.then(null, failed);
        } catch (e) {
          failed(e);
        }
        if (!sameInputValue(readBinding(binding, el), v) && typeof binding.setValue === "function") {
          try {
            binding.setValue(el, v);
          } catch (e) {
            failed(e);
          }
        }
      },
      receiveMessage: function (msg) { return binding.receiveMessage(el, msg); }
    };
    adapter.emit = function () {
      for (var i = 0; i < adapter.listeners.length; i++) adapter.listeners[i](adapter);
    };
    if ($) $(el).data("shiny-input-binding", binding);
    el.classList.add("shiny-bound-input");
    try {
      binding.subscribe(el, function () { adapter.emit(); });
    } catch (e) {
      logWarn("input binding " + id + " failed to subscribe", e);
    }
    shinyEvent(el, "shiny:bound", { binding: binding, bindingType: "input" });
    return adapter;
  }

  // Shiny marks each output it binds, and packages (spinners, for one)
  // listen for it.
  function announceOutputs(root) {
    var scope = root && root.querySelectorAll ? root : document;
    var outputs = toArray(scope.querySelectorAll(
      "[data-shinymcp-output], .shiny-text-output[id], .shiny-html-output[id], .shiny-plot-output[id], .shiny-image-output[id], .html-widget-output[id]"
    ));
    each(outputs, function (el) {
      if (el.__shinymcpBound) return;
      el.__shinymcpBound = true;
      el.classList.add("shiny-bound-output");
      // Shiny keeps the output's binding here; bslib's cards and sidebars
      // read it when they resize. The page resizes plots itself.
      if (window.jQuery) window.jQuery(el).data("shinyOutputBinding", { binding: {}, onResize: function () {} });
      shinyEvent(el, "shiny:bound", { binding: null, bindingType: "output" });
    });
  }

  function announceSession() {
    if (state.shinyAnnounced) return;
    state.shinyAnnounced = true;
    if (shinyApi && state.instance) shinyApi.shinyapp.config.sessionId = state.instance;
    shinyEvent(document, "shiny:connected", {});
    shinyEvent(document, "shiny:sessioninitialized", {});
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
    bindCustomInputs(root || document);
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

  function readInputs(ids, changed) {
    var out = {};
    each(ids || keys(adapters), function (id) {
      var a = adapters[id];
      if (!a || a.unsupported) return;
      // Values set from JavaScript (widget events, Shiny.setInputValue())
      // and uploads go with the update that changed them, not with every
      // update.
      if (changed && (a.kind === "value" || a.changedOnly) && !changed[id]) return;
      try {
        out[id] = a.get();
      } catch (e) {
        logWarn("couldn't read input " + id, e);
      }
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
    updateConditionals();
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
    updateConditionals();
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
  // Server-side selectize choices
  // ---------------------------------------------------------------------------

  // updateSelectizeInput(server = TRUE) keeps the choices in the session and
  // sends a URL to query them, as selectize would while the user types. The
  // page asks the view tool for the first SERVER_CHOICES; when there may be
  // more, a search box above the select asks for the ones that match.
  var SERVER_CHOICES = 1000;

  function loadServerChoices(el, adapter, url, value, query) {
    var match = DATA_URL.exec(url);
    if (!match || !config.runtime) return;
    el.__shinymcpChoicesUrl = url;
    var body = "query=" + encodeURIComponent(query) +
      "&field=" + encodeURIComponent("[\"value\",\"label\"]") +
      "&value=value&conju=and&maxop=" + SERVER_CHOICES;
    dataRequest(decodeURIComponent(match[1]), body).then(function (result) {
      var view = viewMeta(result);
      // A later update replaced these choices.
      if (!view || typeof view.data !== "string" || el.__shinymcpChoicesUrl !== url) return;
      var rows;
      try {
        rows = JSON.parse(view.data);
      } catch (e) {
        return;
      }
      var keep = value !== undefined ? value : adapter.get();
      fillServerChoices(el, rows, keep);
      applying = true;
      try {
        adapter.set(keep === undefined ? null : keep);
        if (!el.multiple && (keep === null || keep === undefined || keep === "")) el.value = "";
      } finally {
        applying = false;
      }
      if (rows.length >= SERVER_CHOICES || query) addChoiceSearch(el, adapter);
      updateConditionals();
    }, function (err) {
      logWarn("couldn't load the choices for " + el.id, err && err.message);
    });
  }

  // Options from selectize's rows ({label, value, optgroup}), keeping the
  // selected values even when a search left them out.
  function fillServerChoices(el, rows, keep) {
    while (el.firstChild) el.removeChild(el.firstChild);
    var kept = keep === null || keep === undefined ? [] : [].concat(keep).map(String);
    if (!el.multiple && kept.length === 0) el.appendChild(new Option("", ""));
    var groups = {};
    var seen = {};
    function add(value, label, group) {
      var option = new Option(label === null || label === undefined ? value : label, value);
      seen[value] = true;
      if (group === null || group === undefined || group === "") {
        el.appendChild(option);
        return;
      }
      if (!groups[group]) {
        groups[group] = document.createElement("optgroup");
        groups[group].label = group;
        el.appendChild(groups[group]);
      }
      groups[group].appendChild(option);
    }
    each(kept, function (v) {
      var inRows = false;
      each(rows, function (row) { if (String(row.value) === v) inRows = true; });
      if (!inRows) add(v, v, null);
    });
    each(rows, function (row) {
      var v = String(row.value);
      if (!seen[v]) add(v, row.label, row.optgroup);
    });
  }

  function addChoiceSearch(el, adapter) {
    if (el.__shinymcpSearch) return;
    var box = document.createElement("input");
    box.type = "search";
    box.className = (hasClass(el, "form-select") || hasClass(el, "form-control") ? "form-control " : "") +
      "shinymcp-choice-search";
    box.placeholder = "Search";
    box.setAttribute("aria-label", "Search the choices");
    el.parentNode.insertBefore(box, el);
    el.__shinymcpSearch = box;
    var timer = null;
    box.addEventListener("input", function () {
      if (timer) clearTimeout(timer);
      timer = setTimeout(function () {
        loadServerChoices(el, adapter, el.__shinymcpChoicesUrl, undefined, box.value);
      }, 300);
    });
  }

  // ---------------------------------------------------------------------------
  // conditionalPanel()
  // ---------------------------------------------------------------------------

  // A conditional panel's condition is a JavaScript expression, which Shiny
  // evaluates with new Function(). The Content Security Policy hosts apply
  // forbids that, so conditions are read here instead: comparisons, &&, ||,
  // !, ?:, arithmetic, typeof, literals (arrays and regular expressions
  // included), input.x, input['x'], output.x, .length, and the string,
  // array, and regular expression methods below.
  // The operators are JavaScript's own, applied to the values. A condition
  // that can't be read shows its panel; one that fails hides it.

  var CONDITION_METHODS = [
    "indexOf", "lastIndexOf", "includes", "join", "concat", "slice",
    "toLowerCase", "toUpperCase", "trim", "startsWith", "endsWith",
    "charAt", "substring", "substr", "toString", "test", "match"
  ];
  var CONDITION_PUNCTUATION = [
    "===", "!==", "==", "!=", "<=", ">=", "&&", "||",
    "<", ">", "!", "(", ")", "[", "]", ".", ",", "+", "-", "*", "/", "%", "?", ":"
  ];
  var parsedConditions = {};
  var unreadableConditions = {};

  function tokenizeCondition(src) {
    var tokens = [];
    var i = 0;
    while (i < src.length) {
      var c = src.charAt(i);
      var rest = src.slice(i);
      var m;
      if (/\s/.test(c)) {
        i++;
      } else if (c === "/" && !afterOperand(tokens)) {
        // A regular expression, as in /^a/.test(input.x).
        var end = i + 1;
        var inClass = false;
        while (end < src.length && (inClass || src.charAt(end) !== "/")) {
          if (src.charAt(end) === "\\") end++;
          else if (src.charAt(end) === "[") inClass = true;
          else if (src.charAt(end) === "]") inClass = false;
          end++;
        }
        if (end >= src.length) throw new Error("unterminated regular expression");
        var flags = /^[gimsuy]*/.exec(src.slice(end + 1))[0];
        tokens.push({ type: "value", value: new RegExp(src.slice(i + 1, end), flags) });
        i = end + 1 + flags.length;
      } else if ((m = /^(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][-+]?[0-9]+)?/.exec(rest))) {
        tokens.push({ type: "value", value: parseFloat(m[0]) });
        i += m[0].length;
      } else if (c === "'" || c === "\"") {
        var j = i + 1;
        var text = "";
        while (j < src.length && src.charAt(j) !== c) {
          if (src.charAt(j) === "\\") {
            j++;
            var e = src.charAt(j);
            text += e === "n" ? "\n" : e === "t" ? "\t" : e;
          } else {
            text += src.charAt(j);
          }
          j++;
        }
        if (j >= src.length) throw new Error("unterminated string");
        tokens.push({ type: "value", value: text });
        i = j + 1;
      } else if ((m = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(rest))) {
        tokens.push({ type: "name", value: m[0] });
        i += m[0].length;
      } else {
        var op = null;
        for (var k = 0; k < CONDITION_PUNCTUATION.length && !op; k++) {
          if (rest.indexOf(CONDITION_PUNCTUATION[k]) === 0) op = CONDITION_PUNCTUATION[k];
        }
        if (!op) throw new Error("unexpected '" + c + "'");
        tokens.push({ type: "op", value: op });
        i += op.length;
      }
    }
    return tokens;
  }

  // Whether the token before a "/" ends an operand, making it division.
  function afterOperand(tokens) {
    var last = tokens[tokens.length - 1];
    if (!last) return false;
    if (last.type === "value") return true;
    if (last.type === "name") return last.value !== "typeof";
    return last.value === ")" || last.value === "]";
  }

  function parseCondition(src) {
    var tokens = tokenizeCondition(src);
    var pos = 0;
    var LEVELS = [["||"], ["&&"], ["==", "!=", "===", "!=="], ["<", "<=", ">", ">="], ["+", "-"], ["*", "/", "%"]];
    var LITERALS = { "true": true, "false": false, "null": null, "undefined": undefined };

    function isOp(value) {
      var t = tokens[pos];
      return !!t && t.type === "op" && t.value === value;
    }
    function expect(value) {
      if (!isOp(value)) throw new Error("expected '" + value + "'");
      pos++;
    }
    function list(close) {
      var items = [];
      if (!isOp(close)) {
        items.push(conditional());
        while (isOp(",")) {
          pos++;
          items.push(conditional());
        }
      }
      expect(close);
      return items;
    }
    function conditional() {
      var test = binary(0);
      if (!isOp("?")) return test;
      pos++;
      var yes = conditional();
      expect(":");
      return { node: "if", test: test, yes: yes, no: conditional() };
    }
    function binary(level) {
      if (level === LEVELS.length) return unary();
      var left = binary(level + 1);
      while (tokens[pos] && tokens[pos].type === "op" && LEVELS[level].indexOf(tokens[pos].value) >= 0) {
        var op = tokens[pos++].value;
        left = { node: level < 2 ? "logical" : "binary", op: op, left: left, right: binary(level + 1) };
      }
      return left;
    }
    function unary() {
      var t = tokens[pos];
      if (t && ((t.type === "op" && (t.value === "!" || t.value === "-" || t.value === "+")) ||
          (t.type === "name" && t.value === "typeof"))) {
        pos++;
        return { node: "unary", op: t.value, arg: unary() };
      }
      return postfix();
    }
    function postfix() {
      var node = primary();
      for (;;) {
        if (isOp(".")) {
          pos++;
          var name = tokens[pos++];
          if (!name || name.type !== "name") throw new Error("expected a name after '.'");
          node = { node: "member", object: node, key: { node: "value", value: name.value } };
        } else if (isOp("[")) {
          pos++;
          var key = conditional();
          expect("]");
          node = { node: "member", object: node, key: key };
        } else if (isOp("(")) {
          if (node.node !== "member") throw new Error("only methods can be called");
          pos++;
          node = { node: "call", method: node, args: list(")") };
        } else {
          return node;
        }
      }
    }
    function primary() {
      var t = tokens[pos++];
      if (!t) throw new Error("unexpected end");
      if (t.type === "value") return { node: "value", value: t.value };
      if (t.type === "name") {
        if (Object.prototype.hasOwnProperty.call(LITERALS, t.value)) return { node: "value", value: LITERALS[t.value] };
        return { node: "name", name: t.value };
      }
      if (t.value === "(") {
        var inner = conditional();
        expect(")");
        return inner;
      }
      if (t.value === "[") return { node: "array", items: list("]") };
      throw new Error("unexpected '" + t.value + "'");
    }

    var tree = conditional();
    if (pos < tokens.length) throw new Error("unexpected '" + tokens[pos].value + "'");
    return tree;
  }

  // `input` and `output` in a condition, narrowed to a module's namespace.
  function conditionScope(prefix) {
    return {
      input: { shinymcpScope: "input", prefix: prefix },
      output: { shinymcpScope: "output", prefix: prefix }
    };
  }

  function conditionMember(object, key) {
    if (object === null || object === undefined) {
      throw new Error("can't read '" + key + "' of " + object);
    }
    if (object.shinymcpScope) {
      var id = object.prefix + String(key);
      if (object.shinymcpScope === "output") return state.outputValues[id];
      var a = adapters[id];
      return a && !a.unsupported ? a.get() : undefined;
    }
    if (typeof object === "string" || Array.isArray(object)) {
      if (key === "length" || typeof key === "number") return object[key];
      return undefined;
    }
    if (typeof object === "object" && Object.prototype.hasOwnProperty.call(object, key)) {
      return object[key];
    }
    return undefined;
  }

  function evaluateCondition(node, scope) {
    var a;
    var b;
    switch (node.node) {
      case "value":
        return node.value;
      case "name":
        if (!Object.prototype.hasOwnProperty.call(scope, node.name)) throw new Error(node.name + " is not defined");
        return scope[node.name];
      case "array":
        var items = [];
        each(node.items, function (item) { items.push(evaluateCondition(item, scope)); });
        return items;
      case "member":
        return conditionMember(evaluateCondition(node.object, scope), evaluateCondition(node.key, scope));
      case "call":
        var target = evaluateCondition(node.method.object, scope);
        var method = evaluateCondition(node.method.key, scope);
        if (target === null || target === undefined || CONDITION_METHODS.indexOf(method) < 0 ||
            typeof target[method] !== "function") {
          throw new Error("can't call " + method + "()");
        }
        var args = [];
        each(node.args, function (arg) { args.push(evaluateCondition(arg, scope)); });
        return target[method].apply(target, args);
      case "unary":
        a = evaluateCondition(node.arg, scope);
        if (node.op === "!") return !a;
        if (node.op === "-") return -a;
        if (node.op === "+") return +a;
        return typeof a;
      case "logical":
        a = evaluateCondition(node.left, scope);
        if (node.op === "&&") return a ? evaluateCondition(node.right, scope) : a;
        return a ? a : evaluateCondition(node.right, scope);
      case "binary":
        a = evaluateCondition(node.left, scope);
        b = evaluateCondition(node.right, scope);
        switch (node.op) {
          case "==": return a == b;
          case "!=": return a != b;
          case "===": return a === b;
          case "!==": return a !== b;
          case "<": return a < b;
          case "<=": return a <= b;
          case ">": return a > b;
          case ">=": return a >= b;
          case "+": return a + b;
          case "-": return a - b;
          case "*": return a * b;
          case "/": return a / b;
          default: return a % b;
        }
      case "if":
        return evaluateCondition(node.test, scope) ? evaluateCondition(node.yes, scope) : evaluateCondition(node.no, scope);
      default:
        throw new Error("unknown expression");
    }
  }

  function conditionHolds(el) {
    var src = el.getAttribute("data-display-if") || "";
    var tree = parsedConditions[src];
    if (tree === undefined) {
      try {
        tree = parseCondition(src);
      } catch (e) {
        tree = null;
        if (!unreadableConditions[src]) {
          unreadableConditions[src] = true;
          logWarn("couldn't read the condition '" + src + "' (" + e.message + "); its panel is shown");
        }
      }
      parsedConditions[src] = tree;
    }
    if (tree === null) return true;
    try {
      return !!evaluateCondition(tree, conditionScope(el.getAttribute("data-ns-prefix") || ""));
    } catch (e2) {
      return false;
    }
  }

  function updateConditionals() {
    if (!document.body) return;
    each(document.querySelectorAll("[data-display-if]"), function (el) {
      var show = conditionHolds(el);
      if (show === hasClass(el, "shiny-conditional--shown")) return;
      el.classList.toggle("shiny-conditional--shown", show);
      // htmlwidgets resize when a panel they're in is shown, as in Shiny.
      if (window.jQuery) window.jQuery(el).trigger(show ? "shown" : "hidden");
    });
  }

  // Panels can arrive with new UI (renderUI(), insertUI(), modals).
  function watchConditionals() {
    if (typeof MutationObserver === "undefined" || !document.body) return;
    var pending = false;
    new MutationObserver(function () {
      if (pending) return;
      pending = true;
      setTimeout(function () {
        pending = false;
        updateConditionals();
      }, 0);
    }).observe(document.body, { childList: true, subtree: true });
  }

  // ---------------------------------------------------------------------------
  // Tools mode
  // ---------------------------------------------------------------------------

  function appTools() {
    return TOOLS.filter(function (t) { return t.app !== false; });
  }

  // The tools to run for the inputs that changed. A tool that takes a
  // button's id runs when the button is pressed, as an eventReactive()
  // does, and not when its other inputs change. A tool that changes
  // something runs only then: never because an input changed. With no list
  // of changes (the Apply button, or a host asking to run), every tool that
  // only reads and waits for no button runs.
  var buttonlessWarned = {};

  function toolsForInputs(changed) {
    var tools = appTools();
    if (!changed) return tools.filter(refreshesOutputs);
    return tools.filter(function (t) {
      var buttons = buttonArguments(t);
      var triggers = buttons.length ? buttons : t.args || [];
      var hit = false;
      for (var i = 0; i < changed.length; i++) {
        if (triggers.indexOf(changed[i]) >= 0) hit = true;
      }
      if (!hit) return false;
      if (buttons.length || refreshesOutputs(t)) return true;
      if (!buttonlessWarned[t.name]) {
        buttonlessWarned[t.name] = true;
        logWarn("tool '" + t.name + "' changes something, so it runs only when a button it takes is pressed; it takes none");
      }
      return false;
    });
  }

  function takenByTool(id) {
    for (var i = 0; i < TOOLS.length; i++) {
      if ((TOOLS[i].args || []).indexOf(id) >= 0) return true;
    }
    return false;
  }

  function buttonArguments(tool) {
    return (tool.args || []).filter(function (arg) {
      var a = adapters[arg];
      return !!a && a.kind === "action";
    });
  }

  // Tools the page may run on its own to fill in outputs: not those that
  // change something, nor those that wait for a button.
  function refreshesOutputs(tool) {
    return tool.readOnly !== false && tool.destructive !== true && !buttonArguments(tool).length;
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

  // Each call says which libraries the page has, and how big its plot
  // outputs are, so plots are drawn to fit.
  function callMeta() {
    var meta = { "shinymcp/caller": "app", "shinymcp/deps": keys(state.loadedDeps) };
    var sizes = outputSizes();
    if (keys(sizes).length) {
      meta["shinymcp/sizes"] = sizes;
      meta["shinymcp/pixelRatio"] = Math.min(window.devicePixelRatio || 1, 2);
    }
    return meta;
  }

  var pendingTools = {};
  var toolCalls = {};

  function callTools(tools) {
    each(tools, function (tool) {
      // Only the latest call to a tool may fill its outputs: an answer for
      // older inputs that arrives after it (a slow server, or one of
      // several behind a load balancer) is dropped.
      var call = (toolCalls[tool.name] || 0) + 1;
      toolCalls[tool.name] = call;
      pendingTools[tool.name] = (pendingTools[tool.name] || 0) + 1;
      var done = function () {
        pendingTools[tool.name] -= 1;
        var latest = call === toolCalls[tool.name];
        if (latest) markRecalculating(tool.outputs, false);
        return latest;
      };
      markRecalculating(tool.outputs, true);
      callTool(tool.name, toolArguments(tool)).then(
        function (result) {
          if (done()) handleResult(result, {});
        },
        function (err) {
          if (done()) showError("The " + tool.name + " tool failed: " + err.message);
        }
      );
    });
  }

  // Plots drawn to fit an output whose size has changed since, or that were
  // drawn before the page could say (the model's call that opened it).
  function plotsToRefit() {
    var ids = [];
    function off(outer, drawn) {
      return Math.abs(outer - drawn) > Math.max(8, drawn * 0.05);
    }
    each(document.querySelectorAll(PLOT_OUTPUTS), function (el) {
      var img = el.querySelector("img[data-shinymcp-fit]");
      if (!img) return;
      var w = parseFloat(img.getAttribute("data-shinymcp-width") || 0);
      var h = parseFloat(img.getAttribute("data-shinymcp-height") || 0);
      var ow = el.clientWidth;
      var oh = el.clientHeight;
      if (!w || !ow) return;
      // An output that takes its image's height only has a width to match.
      var tall = !followsImageHeight(el) && h && oh && off(oh, h);
      if (off(ow, w) || tall) ids.push(outputKey(el));
    });
    return ids;
  }

  // The outputs each tool fills, as its results show when the app doesn't
  // declare them.
  var drawnBy = {};

  function noteDrawn(view) {
    if (!view || typeof view.tool !== "string") return;
    var ids = [];
    if (view.outputs) {
      ids = keys(view.outputs);
    } else if (view.result) {
      var single = allOutputs();
      if (single.length === 1) ids = [single[0].id];
    }
    if (ids.length) drawnBy[view.tool] = ids;
  }

  function drawsAny(tool, ids) {
    var outputs = tool.outputs || drawnBy[tool.name] || [];
    for (var i = 0; i < ids.length; i++) {
      if (outputs.indexOf(ids[i]) >= 0) return true;
    }
    return false;
  }

  // The tools to call again for plots of the wrong size: those the page may
  // run on its own, not already running.
  function toolsToRefit() {
    var ids = plotsToRefit();
    if (!ids.length) return [];
    return appTools().filter(function (t) {
      return refreshesOutputs(t) && !pendingTools[t.name] && drawsAny(t, ids);
    });
  }

  function observePlotFit() {
    if (typeof ResizeObserver === "undefined") return;
    var timer = null;
    var observer = new ResizeObserver(function () {
      if (timer) clearTimeout(timer);
      timer = setTimeout(function () {
        timer = null;
        var tools = toolsToRefit();
        if (tools.length) callTools(tools);
      }, 300);
    });
    each(document.querySelectorAll(PLOT_OUTPUTS), function (el) { observer.observe(el); });
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
  // fills in, except tools that change something or wait for a button. The
  // first tool runs again only if its plots were drawn at the wrong size.
  function fillRemainingOutputs(firstTool) {
    var refit = toolsToRefit();
    var tools = appTools().filter(function (t) {
      return refreshesOutputs(t) && (t.name !== firstTool || refit.indexOf(t) >= 0);
    });
    if (tools.length) callTools(tools);
  }

  // ---------------------------------------------------------------------------
  // Shiny mode: the view's session in R
  // ---------------------------------------------------------------------------

  var inFlight = false;
  var queued = null;

  // Plot outputs a tool can draw to fit: Shiny's plotOutput() and
  // mcp_plot().
  var PLOT_OUTPUTS = '.shiny-plot-output[id], [data-shinymcp-output-type="plot"]';

  // The id a tool's result uses for an output.
  function outputKey(el) {
    return el.getAttribute("data-shinymcp-output") || el.id;
  }

  // An mcp_plot() without a height takes its image's, so only its width
  // is the output's to give.
  function followsImageHeight(el) {
    return hasClass(el, "shinymcp-plot") && !hasClass(el, "shinymcp-plot-fixed");
  }

  function outputSizes() {
    var sizes = {};
    if (MODE !== "tools") {
      each(document.querySelectorAll(".shiny-plot-output[id], .shiny-image-output[id]"), function (el) {
        var w = el.clientWidth;
        var h = el.clientHeight;
        if (w > 0 && h > 0) sizes[el.id] = { width: w, height: h };
      });
      return sizes;
    }
    each(document.querySelectorAll(PLOT_OUTPUTS + ", .shiny-image-output[id]"), function (el) {
      var key = outputKey(el);
      var w = el.clientWidth;
      var h = el.clientHeight;
      if (!key || !(w > 0)) return;
      if (followsImageHeight(el)) sizes[key] = { width: w };
      else if (h > 0) sizes[key] = { width: w, height: h };
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

  // Ask the view tool for data kept in R (DT's server-side rows,
  // selectize's server-side choices). If the view's session is gone, ask
  // once more with everything the page has, and R starts a new one.
  function dataRequest(output, body) {
    function ask(full) {
      var args = { action: "data", instance: state.instance, output: output, body: body };
      if (full) {
        args.inputs = readInputs();
        args.kinds = inputKinds(keys(adapters));
      }
      return callTool(config.runtime.viewTool, args).then(function (result) {
        var view = viewMeta(result);
        if (view && view.gone && !full) return ask(true);
        if (view && view.instance) state.instance = view.instance;
        if (view && view.restarted) {
          // The new session has every input, and the outputs the page shows.
          state.syncedInstance = state.instance;
          if (typeof view.revision === "number") state.viewRevision = view.revision;
          logWarn("the app's R session was restarted; state kept outside inputs was reset");
        }
        return result;
      });
    }
    return ask(false);
  }

  function inputKinds(ids) {
    var kinds = {};
    each(ids, function (id) {
      var a = adapters[id];
      if (!a) return;
      var kind = { kind: a.kind };
      if (a.dataType) kind.dataType = a.dataType;
      if (a.inputType) kind.type = a.inputType;
      kinds[id] = kind;
    });
    return kinds;
  }

  function viewUpdate(changed, extra) {
    var changedSet = {};
    each(changed, function (id) { changedSet[id] = true; });
    var events = keys(state.events);
    // The first update a session gets from this page carries every input,
    // including ones the server knows nothing about until then.
    var sync = !inFlight && state.instance !== state.syncedInstance;
    var payload = assign(
      {
        action: "update",
        inputs: readInputs(null, sync ? null : changedSet),
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
    // Inputs set with priority "event" count even when their value repeats.
    if (events.length) payload.events = events;
    state.events = {};
    if (sync) payload.sync = true;
    inFlight = true;
    return callTool(config.runtime.viewTool, payload).then(
      function (result) {
        inFlight = false;
        handleResult(result, {});
        // The session has every input once a full update has reached it.
        // After an update that failed, it may lack what that update
        // carried, so the next one sends everything again.
        if (!result || result.isError) {
          state.syncedInstance = null;
        } else if (payload.sync) {
          state.syncedInstance = state.instance;
        }
        // The session was gone and R started a new one from this update,
        // which leaves out values set from JavaScript and uploads that
        // didn't change: send it everything the page has, once.
        var view = viewMeta(result);
        if (view && view.restarted && !payload.sync) {
          state.syncedInstance = null;
          viewUpdate([], {});
          return;
        }
        flushQueue();
      },
      function (err) {
        inFlight = false;
        state.syncedInstance = null;
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
        inputs: readInputs(),
        kinds: inputKinds(keys(adapters))
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
      if (MODE === "tools") noteDrawn(view);
      each(view.notifications || [], handleNotification);
      each(view.modals || [], handleModal);
      each(view.uiChanges || [], handleUiChange);
      each(view.customMessages || [], function (m) { dispatchCustomMessage(m.type, m.message); });
      each(view.messages || [], function (text) { sendMessage(text); });
      if (view.modelContext && config.modelContext !== false) publishModelContext(view.modelContext);
      if (view.restarted) logWarn("the app's R session was restarted; state kept outside inputs was reset");
      scheduleTick(view.nextTick);
    } else if (result.structuredContent && typeof result.structuredContent === "object") {
      renderFromStructured(result.structuredContent);
    } else if (!result.isError) {
      var text = resultText(result);
      if (text) renderSingle({ kind: "text", value: text });
    }

    announceSession();
    if (opts.initial && !state.firstResult) {
      state.firstResult = true;
      afterFirstResult(result, view);
    }
  }

  // Timers in the R session (invalidateLater(), reactivePoll()) only run
  // when the page calls, so call when the next one is due: at most once a
  // second, and not while the page is hidden.
  var tickTimer = null;
  var MIN_TICK_MS = typeof config.minTickMs === "number" ? config.minTickMs : 1000;
  function scheduleTick(ms) {
    if (tickTimer) {
      clearTimeout(tickTimer);
      tickTimer = null;
    }
    if (typeof ms !== "number" || MODE !== "shiny") return;
    tickTimer = setTimeout(function () {
      tickTimer = null;
      if (tornDown || !state.instance) return;
      if (document.visibilityState === "hidden") {
        state.tickWhenVisible = true;
        return;
      }
      if (inFlight) {
        scheduleTick(MIN_TICK_MS);
        return;
      }
      viewUpdate([], { tick: true });
    }, Math.max(ms, MIN_TICK_MS));
  }
  document.addEventListener("visibilitychange", function () {
    if (document.visibilityState === "visible" && state.tickWhenVisible) {
      state.tickWhenVisible = false;
      scheduleTick(0);
    }
  });

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
      observePlotFit();
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

  // Hosts that drop _meta leave structured content: for a tool's result,
  // values keyed by output id.
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
      if (!el) return;
      el.classList.toggle("recalculating", !!on);
      if (on) {
        shinyEvent(el, "shiny:outputinvalidated", { name: id });
        shinyEvent(el, "shiny:recalculating", { name: id });
      }
    });
  }

  // One output that fails to draw shouldn't stop the others.
  function renderOutputs(outputs) {
    each(keys(outputs), function (id) {
      var payload = outputs[id] || {};
      recordOutputValue(payload.dom || id, payload);
      var el = findOutput(payload.dom || id);
      if (!el) return;
      safeRender(el, payload, id);
    });
    updateConditionals();
  }

  // What `output.x` is in a condition: the value Shiny's client would hold.
  // Outputs a server function defines without a render function
  // (`output$ready <- reactive(TRUE)`) carry it as `raw`.
  function recordOutputValue(id, payload) {
    if (payload.kind === "keep" || payload.kind === "progress") return;
    if (payload.raw !== undefined) {
      state.outputValues[id] = payload.raw;
    } else if (payload.kind === "clear" || payload.kind === "error") {
      state.outputValues[id] = null;
    } else {
      state.outputValues[id] = payload.value;
    }
  }

  function safeRender(el, payload, id) {
    try {
      if (renderInto(el, payload, id) === "pending") return;
    } catch (e) {
      logWarn("couldn't draw output " + id, e);
      el.textContent = "This output couldn't be drawn: " + (e && e.message ? e.message : e);
      el.classList.add("shiny-output-error");
      shinyEvent(el, "shiny:error", { name: id, error: { message: String(e && e.message ? e.message : e) } });
      return;
    }
    if (payload.kind === "keep" || payload.kind === "progress") return;
    if (payload.kind === "error") {
      shinyEvent(el, "shiny:error", { name: id, error: { message: payload.value || "" } });
    } else {
      shinyEvent(el, "shiny:value", { name: id, value: payload.value });
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
    // Waiting on a task in the session: keep what's shown, look busy.
    if (kind === "progress") {
      if (!hasClass(el, "recalculating")) {
        el.classList.add("recalculating");
        shinyEvent(el, "shiny:recalculating", { name: id });
      }
      return;
    }
    var waiting = loadDeps(payload.deps);
    if (waiting) {
      el.classList.add("recalculating");
      waiting.then(
        function () {
          el.classList.remove("recalculating");
          safeRender(el, assign({}, payload, { deps: null }), id);
        },
        function (err) {
          el.classList.remove("recalculating");
          el.textContent = "This output needs a library that couldn't be loaded: " + err.message;
          el.classList.add("shiny-output-error");
        }
      );
      return "pending";
    }
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
    if (img.height) image.setAttribute("data-shinymcp-height", img.height);
    if (img.fit) image.setAttribute("data-shinymcp-fit", "");
    else image.removeAttribute("data-shinymcp-fit");
    if (img.style) image.setAttribute("style", img.style);
    if (!existing) {
      el.innerHTML = "";
      el.appendChild(image);
    }
    if (hasPlotInteractions(el)) {
      if (image.complete && image.naturalWidth) {
        setupPlotInteractions(el, image, img.coordmap);
      } else {
        image.addEventListener("load", function () {
          setupPlotInteractions(el, image, img.coordmap);
        }, { once: true });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Plot clicks, hovers, and brushes
  // ---------------------------------------------------------------------------

  // plotOutput(click =, dblclick =, hover =, brush =) and imageOutput() send
  // the pointer's position in the plot's data coordinates, as Shiny's
  // client does, so nearPoints() and brushedPoints() work in the server.
  // Each plot comes with its coordmap: the panels of the plot, and how
  // their pixels map to data.

  function hasPlotInteractions(el) {
    return !!(el.getAttribute("data-click-id") || el.getAttribute("data-dblclick-id") ||
      el.getAttribute("data-hover-id") || el.getAttribute("data-brush-id"));
  }

  function plotOption(el, name, fallback) {
    var value = el.getAttribute("data-" + name);
    if (value === null || value === "") return fallback;
    if (/^(true|false)$/i.test(value)) return value.toLowerCase() === "true";
    if (typeof fallback === "number") {
      var n = parseFloat(value);
      return isNaN(n) ? fallback : n;
    }
    return value;
  }

  // x-prefixed values (x, xmin, xmax) by one function, y-prefixed by another.
  function byAxis(values, fx, fy) {
    var out = {};
    each(keys(values), function (key) {
      var c = key.charAt(0);
      out[key] = c === "x" ? fx(values[key]) : c === "y" ? fy(values[key]) : null;
    });
    return out;
  }

  function mapLinear(v, fromMin, fromMax, toMin, toMax) {
    var out = (v - fromMin) * (toMax - toMin) / (fromMax - fromMin) + toMin;
    return Math.min(Math.max(out, Math.min(toMin, toMax)), Math.max(toMin, toMax));
  }

  function preparePlotPanel(panel) {
    var d = panel.domain;
    var r = panel.range;
    var xlog = panel.log && panel.log.x ? panel.log.x : null;
    var ylog = panel.log && panel.log.y ? panel.log.y : null;
    function toImg(v, lo, hi, rlo, rhi, base) {
      return mapLinear(base ? Math.log(v) / Math.log(base) : v, lo, hi, rlo, rhi);
    }
    function toData(v, rlo, rhi, lo, hi, base) {
      var out = mapLinear(v, rlo, rhi, lo, hi);
      return base ? Math.pow(base, out) : out;
    }
    panel.toImg = function (values) {
      return byAxis(values,
        function (v) { return toImg(v, d.left, d.right, r.left, r.right, xlog); },
        function (v) { return toImg(v, d.bottom, d.top, r.bottom, r.top, ylog); });
    };
    panel.toData = function (values) {
      return byAxis(values,
        function (v) { return toData(v, r.left, r.right, d.left, d.right, xlog); },
        function (v) { return toData(v, r.bottom, r.top, d.bottom, d.top, ylog); });
    };
    panel.clipImg = function (p) {
      return {
        x: Math.min(Math.max(p.x, r.left), r.right),
        y: Math.min(Math.max(p.y, r.top), r.bottom)
      };
    };
    return panel;
  }

  function plotCoordmap(img, raw) {
    var map = JSON.parse(JSON.stringify(raw || {}));
    map.panels = map.panels || [];
    map.dims = map.dims || {};
    if (!map.panels.length) {
      var bounds = { top: 0, left: 0, right: img.naturalWidth - 1, bottom: img.naturalHeight - 1 };
      map.panels = [{ domain: bounds, range: bounds, mapping: {} }];
    }
    map.dims.width = map.dims.width || img.naturalWidth;
    map.dims.height = map.dims.height || img.naturalHeight;
    each(map.panels, preparePlotPanel);
    // CSS pixels per coordmap pixel.
    function ratio() {
      var rect = img.getBoundingClientRect();
      return { x: rect.width / map.dims.width, y: rect.height / map.dims.height };
    }
    map.offsetCss = function (e) {
      var rect = img.getBoundingClientRect();
      return { x: e.clientX - rect.left, y: e.clientY - rect.top };
    };
    map.cssToImg = function (values) {
      var k = ratio();
      return byAxis(values, function (v) { return v / k.x; }, function (v) { return v / k.y; });
    };
    map.imgToCss = function (values) {
      var k = ratio();
      return byAxis(values, function (v) { return v * k.x; }, function (v) { return v * k.y; });
    };
    map.cssToImgRatio = function () {
      var k = ratio();
      return { x: 1 / k.x, y: 1 / k.y };
    };
    // The panel under a point, or the nearest within `expand` CSS pixels.
    map.panelAt = function (css, expand) {
      var p = map.cssToImg(css);
      var k = map.cssToImgRatio();
      var ex = (expand || 0) * k.x;
      var ey = (expand || 0) * k.y;
      var best = null;
      var bestDist = Infinity;
      each(map.panels, function (panel) {
        var b = panel.range;
        if (p.x > b.right + ex || p.x < b.left - ex || p.y > b.bottom + ey || p.y < b.top - ey) return;
        var dx = p.x > b.right ? p.x - b.right : p.x < b.left ? p.x - b.left : 0;
        var dy = p.y > b.bottom ? p.y - b.bottom : p.y < b.top ? p.y - b.top : 0;
        var dist = Math.sqrt(dx * dx + dy * dy);
        if (dist < bestDist) {
          best = panel;
          bestDist = dist;
        }
      });
      return best;
    };
    return map;
  }

  function withPanelInfo(coords, panel) {
    each(keys(panel.panel_vars || {}), function (key) { coords[key] = panel.panel_vars[key]; });
    coords.mapping = panel.mapping;
    coords.domain = panel.domain;
    coords.range = panel.range;
    coords.log = panel.log;
    return coords;
  }

  // Set an input to NULL, unless it is already.
  function clearPlotInput(id) {
    var a = adapters[id];
    if (a && a.value !== null && a.value !== undefined) setShinyInput(id, null, {});
  }

  function sendPlotPointer(map, id, e, clip, nullOutside) {
    if (e === null) {
      clearPlotInput(id);
      return;
    }
    var css = map.offsetCss(e);
    var panel = map.panelAt(css, 0);
    if (!panel) {
      if (nullOutside) {
        clearPlotInput(id);
      } else if (!clip) {
        setShinyInput(id, { coords_css: css, coords_img: map.cssToImg(css) }, { priority: "event" });
      }
      return;
    }
    var coordsImg = map.cssToImg(css);
    var data = panel.toData(coordsImg);
    setShinyInput(id, withPanelInfo({
      x: data.x,
      y: data.y,
      coords_css: css,
      coords_img: coordsImg,
      img_css_ratio: map.cssToImgRatio()
    }, panel), { priority: "event" });
  }

  // Call fn at most once per `delay` ms ("throttle"), or `delay` ms after
  // the last call ("debounce").
  function delayed(fn, delay, type) {
    var timer = null;
    var last = 0;
    var args = null;
    function run() {
      timer = null;
      last = Date.now();
      fn.apply(null, args);
    }
    return {
      call: function () {
        args = arguments;
        if (type === "throttle") {
          if (timer) return;
          var wait = Math.max(0, delay - (Date.now() - last));
          timer = setTimeout(run, wait);
        } else {
          if (timer) clearTimeout(timer);
          timer = setTimeout(run, delay);
        }
      },
      now: function () {
        args = arguments;
        if (timer) clearTimeout(timer);
        run();
      },
      pending: function () { return timer !== null; }
    };
  }

  function setupPlotInteractions(el, img, rawCoordmap) {
    var map = plotCoordmap(img, rawCoordmap);
    var previous = el.__shinymcpPlot;
    if (previous) previous.detach();
    var listeners = [];
    function on(target, type, fn) {
      target.addEventListener(type, fn);
      listeners.push([target, type, fn]);
    }
    var plot = {
      map: map,
      detach: function () {
        each(listeners, function (l) { l[0].removeEventListener(l[1], l[2]); });
        listeners = [];
      }
    };
    el.__shinymcpPlot = plot;
    img.draggable = false;
    img.style.webkitUserDrag = "none";
    on(el, "dragstart", function (e) { e.preventDefault(); });

    var clickId = plotOption(el, "click-id", null);
    var dblclickId = plotOption(el, "dblclick-id", null);
    var clickClip = plotOption(el, "click-clip", true);
    var dblclickDelay = plotOption(el, "dblclick-delay", 400);
    var hoverId = plotOption(el, "hover-id", null);

    // A new plot clears clicks and hovers, as in Shiny.
    if (clickId) clearPlotInput(clickId);
    if (dblclickId) clearPlotInput(dblclickId);
    if (hoverId) clearPlotInput(hoverId);

    // A click waits to see whether it is half of a double click.
    var pendingClick = null;
    var clickTimer = null;
    function flushClick() {
      if (pendingClick && clickId) sendPlotPointer(map, clickId, pendingClick, clickClip, false);
      pendingClick = null;
    }
    on(el, "mousedown", function (e) {
      if (e.button !== 0 || (!clickId && !dblclickId)) return;
      if (!dblclickId) {
        sendPlotPointer(map, clickId, e, clickClip, false);
        return;
      }
      if (pendingClick === null) {
        pendingClick = e;
        clickTimer = setTimeout(flushClick, dblclickDelay);
        return;
      }
      clearTimeout(clickTimer);
      if (Math.abs(pendingClick.clientX - e.clientX) > 2 || Math.abs(pendingClick.clientY - e.clientY) > 2) {
        flushClick();
        pendingClick = e;
        clickTimer = setTimeout(flushClick, dblclickDelay);
      } else {
        pendingClick = null;
        sendPlotPointer(map, dblclickId, e, clickClip, false);
      }
    });

    if (hoverId) {
      var hoverClip = plotOption(el, "hover-clip", true);
      var nullOutside = plotOption(el, "hover-null-outside", false);
      var hover = delayed(function (e) {
        sendPlotPointer(map, hoverId, e, hoverClip, nullOutside);
      }, plotOption(el, "hover-delay", 300), plotOption(el, "hover-delay-type", "debounce"));
      on(el, "mousemove", function (e) { hover.call(e); });
      if (nullOutside) on(el, "mouseleave", function () { hover.call(null); });
    }

    if (plotOption(el, "brush-id", null)) setupPlotBrush(el, img, map, on);
  }

  function setupPlotBrush(el, img, map, on) {
    var opts = {
      id: plotOption(el, "brush-id", null),
      fill: plotOption(el, "brush-fill", "#666"),
      stroke: plotOption(el, "brush-stroke", "#000"),
      opacity: plotOption(el, "brush-opacity", 0.3),
      clip: plotOption(el, "brush-clip", true),
      direction: plotOption(el, "brush-direction", "xy"),
      resetOnNew: plotOption(el, "brush-reset-on-new", false)
    };
    var EXPAND = 20;
    var RESIZE = 10;
    var old = el.__shinymcpBrush;
    var brush = { panel: null, css: null, data: null, down: null, start: null, mode: null, sides: null };
    var div = old && old.div && old.div.parentNode === el ? old.div : null;

    if (window.getComputedStyle(el).position === "static") el.style.position = "relative";

    function box(a, b) {
      return { xmin: Math.min(a.x, b.x), xmax: Math.max(a.x, b.x), ymin: Math.min(a.y, b.y), ymax: Math.max(a.y, b.y) };
    }
    function round(v) { return parseFloat(v.toPrecision(14)); }

    // Set the brush from a box in CSS pixels, clipped to its panel and
    // stretched across it for one-direction brushes.
    function setCss(b) {
      var panel = brush.panel;
      var r = panel.range;
      var min = { x: b.xmin, y: b.ymin };
      var max = { x: b.xmax, y: b.ymax };
      if (opts.clip) {
        min = map.imgToCss(panel.clipImg(map.cssToImg(min)));
        max = map.imgToCss(panel.clipImg(map.cssToImg(max)));
      }
      if (opts.direction === "x") {
        min.y = map.imgToCss({ y: r.top }).y;
        max.y = map.imgToCss({ y: r.bottom }).y;
      } else if (opts.direction === "y") {
        min.x = map.imgToCss({ x: r.left }).x;
        max.x = map.imgToCss({ x: r.right }).x;
      }
      brush.css = { xmin: min.x, xmax: max.x, ymin: min.y, ymax: max.y };
      var data = box(panel.toData(map.cssToImg(min)), panel.toData(map.cssToImg(max)));
      brush.data = { xmin: round(data.xmin), xmax: round(data.xmax), ymin: round(data.ymin), ymax: round(data.ymax) };
      draw();
    }
    function draw() {
      if (!div) {
        div = document.createElement("div");
        div.id = el.id + "_brush";
        div.style.position = "absolute";
        div.style.pointerEvents = "none";
        div.style.boxSizing = "border-box";
        el.appendChild(div);
      }
      var border = "1px solid " + opts.stroke;
      div.style.backgroundColor = opts.fill;
      div.style.opacity = opts.opacity;
      div.style.border = opts.direction === "xy" ? border : "none";
      if (opts.direction === "x") { div.style.borderLeft = border; div.style.borderRight = border; }
      if (opts.direction === "y") { div.style.borderTop = border; div.style.borderBottom = border; }
      var b = brush.css;
      div.style.left = (img.offsetLeft + b.xmin) + "px";
      div.style.top = (img.offsetTop + b.ymin) + "px";
      div.style.width = (b.xmax - b.xmin + 1) + "px";
      div.style.height = (b.ymax - b.ymin + 1) + "px";
      div.style.display = "";
    }
    function clear() {
      if (div && div.parentNode) div.parentNode.removeChild(div);
      div = null;
      brush.panel = null;
      brush.css = null;
      brush.data = null;
    }
    function send() {
      if (!brush.data) {
        clearPlotInput(opts.id);
        return;
      }
      var coords = withPanelInfo({
        xmin: brush.data.xmin,
        xmax: brush.data.xmax,
        ymin: brush.data.ymin,
        ymax: brush.data.ymax,
        coords_css: brush.css,
        coords_img: map.cssToImg(brush.css),
        img_css_ratio: map.cssToImgRatio()
      }, brush.panel);
      coords.direction = opts.direction;
      coords.brushId = opts.id;
      coords.outputId = el.id;
      setShinyInput(opts.id, coords, {});
    }
    var sender = delayed(send, plotOption(el, "brush-delay", 300), plotOption(el, "brush-delay-type", "debounce"));

    function inside(css) {
      var b = brush.css;
      return !!b && css.x <= b.xmax && css.x >= b.xmin && css.y <= b.ymax && css.y >= b.ymin;
    }
    function sidesAt(css) {
      var b = brush.css;
      var sides = { left: false, right: false, top: false, bottom: false };
      if (!b) return sides;
      var withinY = css.y <= b.ymax + RESIZE && css.y >= b.ymin - RESIZE;
      var withinX = css.x <= b.xmax + RESIZE && css.x >= b.xmin - RESIZE;
      if (opts.direction !== "y" && withinY) {
        if (css.x < b.xmin && css.x >= b.xmin - RESIZE) sides.left = true;
        else if (css.x > b.xmax && css.x <= b.xmax + RESIZE) sides.right = true;
      }
      if (opts.direction !== "x" && withinX) {
        if (css.y < b.ymin && css.y >= b.ymin - RESIZE) sides.top = true;
        else if (css.y > b.ymax && css.y <= b.ymax + RESIZE) sides.bottom = true;
      }
      return sides;
    }
    function anySide(s) { return s.left || s.right || s.top || s.bottom; }
    function shift(lo, hi, min, max) {
      var d = hi > max ? max - hi : lo < min ? min - lo : 0;
      return [lo + d, hi + d];
    }

    function move(e) {
      var css = map.offsetCss(e);
      if (brush.mode === "brushing") {
        setCss(box(brush.down, css));
      } else if (brush.mode === "dragging") {
        var s = brush.start;
        var dx = css.x - brush.down.x;
        var dy = css.y - brush.down.y;
        var next = { xmin: s.xmin + dx, xmax: s.xmax + dx, ymin: s.ymin + dy, ymax: s.ymax + dy };
        if (opts.clip) {
          var r = brush.panel.range;
          var nImg = map.cssToImg(next);
          var xs = shift(nImg.xmin, nImg.xmax, r.left, r.right);
          var ys = shift(nImg.ymin, nImg.ymax, r.top, r.bottom);
          next = map.imgToCss({ xmin: xs[0], xmax: xs[1], ymin: ys[0], ymax: ys[1] });
        }
        setCss(next);
      } else if (brush.mode === "resizing") {
        var bImg = map.cssToImg(brush.start);
        var dImg = map.cssToImg({ x: css.x - brush.down.x, y: css.y - brush.down.y });
        var pr = brush.panel.range;
        if (brush.sides.left) bImg.xmin = Math.min(Math.max(bImg.xmin + dImg.x, pr.left), bImg.xmax);
        else if (brush.sides.right) bImg.xmax = Math.max(Math.min(bImg.xmax + dImg.x, pr.right), bImg.xmin);
        if (brush.sides.top) bImg.ymin = Math.min(Math.max(bImg.ymin + dImg.y, pr.top), bImg.ymax);
        else if (brush.sides.bottom) bImg.ymax = Math.max(Math.min(bImg.ymax + dImg.y, pr.bottom), bImg.ymin);
        setCss(map.imgToCss(bImg));
      }
      sender.call();
    }
    function up(e) {
      document.removeEventListener("mousemove", move);
      document.removeEventListener("mouseup", up);
      var css = map.offsetCss(e);
      var mode = brush.mode;
      brush.mode = null;
      if (mode === "brushing" && css.x === brush.down.x && css.y === brush.down.y) {
        // A click without a drag clears the brush.
        clear();
        sender.now();
        return;
      }
      if (sender.pending()) sender.now();
    }

    on(el, "mousedown", function (e) {
      if (e.button !== 0 || brush.mode) return;
      var css = map.offsetCss(e);
      if (opts.clip && !map.panelAt(css, EXPAND)) return;
      brush.down = css;
      var sides = sidesAt(css);
      if (brush.css && anySide(sides)) {
        brush.mode = "resizing";
        brush.sides = sides;
        brush.start = brush.css;
      } else if (inside(css)) {
        brush.mode = "dragging";
        brush.start = brush.css;
      } else {
        brush.mode = "brushing";
        brush.panel = map.panelAt(css, EXPAND);
        if (!brush.panel) return;
        var start = map.imgToCss(brush.panel.clipImg(map.cssToImg(css)));
        brush.down = start;
        setCss(box(start, start));
      }
      e.preventDefault();
      document.addEventListener("mousemove", move);
      document.addEventListener("mouseup", up);
    });
    on(el, "mousemove", function (e) {
      if (brush.mode) return;
      var css = map.offsetCss(e);
      var s = sidesAt(css);
      var cursor = "";
      if (brush.css && anySide(s)) {
        cursor = (s.left && s.top) || (s.right && s.bottom) ? "nwse-resize" :
          (s.left && s.bottom) || (s.right && s.top) ? "nesw-resize" :
          s.left || s.right ? "ew-resize" : "ns-resize";
      } else if (inside(css)) {
        cursor = "grab";
      } else if (map.panelAt(css, EXPAND)) {
        cursor = "crosshair";
      }
      el.style.cursor = cursor;
    });

    // A new plot: keep the brush on the same data (on the panel with the
    // same mapping), unless the brush resets on new plots.
    el.__shinymcpBrush = { div: div, panel: old && old.panel, data: old && old.data };
    if (old && old.data && !opts.resetOnNew) {
      var match = null;
      each(map.panels, function (panel) {
        if (!match && JSON.stringify(panel.mapping) === JSON.stringify(old.panel.mapping) &&
            JSON.stringify(panel.panel_vars || {}) === JSON.stringify(old.panel.panel_vars || {})) {
          match = panel;
        }
      });
      if (match) {
        brush.panel = match;
        var cssBox = map.imgToCss(match.toImg(old.data));
        setCss(box({ x: cssBox.xmin, y: cssBox.ymin }, { x: cssBox.xmax, y: cssBox.ymax }));
        sender.now();
      } else {
        clear();
        sender.now();
      }
    } else if (old && old.data) {
      clear();
      sender.now();
    } else if (div) {
      clear();
    }
    // Remember the brush across plots.
    var remember = function () {
      el.__shinymcpBrush = { div: div, panel: brush.panel, data: brush.data };
    };
    on(el, "mouseup", remember);
    on(document, "mouseup", remember);
    remember();
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
    announceOutputs(root);
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
          dataRequest(name, body).then(
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
  // Returns a promise when a library has to be fetched first: results the
  // model gets name large libraries rather than carry them.
  var depFetches = {};
  function loadDeps(deps) {
    var waiting = [];
    each(deps || [], function (dep) {
      var key = dep.name + "@" + dep.version;
      if (state.loadedDeps[key] || state.loadedNames[dep.name]) return;
      if (dep.fetch && !dep.head) {
        waiting.push(fetchDep(key));
        return;
      }
      injectDep(dep);
    });
    return waiting.length ? Promise.all(waiting) : null;
  }

  function fetchDep(key) {
    if (depFetches[key]) return depFetches[key];
    if (!config.runtime || !config.runtime.viewTool) {
      return Promise.reject(new Error("no way to fetch " + key));
    }
    depFetches[key] = callTool(config.runtime.viewTool, { action: "dependency", dependency: key }).then(
      function (result) {
        var view = viewMeta(result);
        if (!view || !view.dependency) throw new Error("couldn't load " + key);
        injectDep(view.dependency);
      },
      function (err) {
        delete depFetches[key];
        throw err;
      }
    );
    return depFetches[key];
  }

  function injectDep(dep) {
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
    updateConditionals();
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
        // A value a widget sets from JavaScript (a picker's "_open") is
        // the widget's own state unless a tool takes it.
        if (a.kind === "value" && !takenByTool(id)) return;
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
      callTools(appTools().filter(refreshesOutputs));
    }
  }

  function init() {
    document.documentElement.classList.add("shinymcp-" + MODE);
    connectShiny();
    scanInputs(document);
    state.scanned = true;
    announceOutputs(document);
    updateConditionals();
    watchConditionals();
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
    setInputValue: function (id, value, opts) {
      setShinyInput(id, value, opts || {});
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
