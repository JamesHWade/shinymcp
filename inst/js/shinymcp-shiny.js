/*
 * window.Shiny for pages that run without shiny.js.
 *
 * Packages written for Shiny's browser client register input and output
 * bindings, call Shiny.setInputValue(), and add custom message handlers as
 * their scripts load. This script runs first, in <head>, so they find the
 * API they expect. It only collects what they register; the shinymcp bridge
 * connects it to the app when it starts, replacing the placeholders below.
 *
 * ES5, no dependencies.
 */
(function () {
  "use strict";
  if (window.Shiny) return;

  var script = document.currentScript;
  var version = (script && script.getAttribute("data-shiny-version")) || "1.10.0";

  function BindingRegistry() {
    this.bindings = [];
    this.bindingNames = {};
  }
  BindingRegistry.prototype.register = function (binding, name, priority) {
    var entry = { binding: binding, priority: priority || 0 };
    // Newest first: among equal priorities, a later registration wins.
    this.bindings.unshift(entry);
    if (name) {
      this.bindingNames[name] = entry;
      binding.name = name;
    }
    if (typeof Shiny.__shinymcp.onRegister === "function") Shiny.__shinymcp.onRegister();
  };
  BindingRegistry.prototype.setPriority = function (name, priority) {
    var entry = this.bindingNames[name];
    if (!entry) throw "Tried to set priority on unknown binding " + name;
    entry.priority = priority || 0;
  };
  BindingRegistry.prototype.getPriority = function (name) {
    var entry = this.bindingNames[name];
    return entry ? entry.priority : false;
  };
  BindingRegistry.prototype.getBindings = function () {
    // A stable sort, highest priority first.
    var indexed = [];
    for (var i = 0; i < this.bindings.length; i++) indexed.push({ entry: this.bindings[i], index: i });
    indexed.sort(function (a, b) {
      return (b.entry.priority - a.entry.priority) || (a.index - b.index);
    });
    var out = [];
    for (var j = 0; j < indexed.length; j++) out.push(indexed[j].entry);
    return out;
  };

  function InputBinding() {}
  InputBinding.prototype.find = function () { throw "Not implemented"; };
  InputBinding.prototype.getId = function (el) { return el.getAttribute("data-input-id") || el.id; };
  InputBinding.prototype.getType = function () { return null; };
  InputBinding.prototype.getValue = function () { throw "Not implemented"; };
  InputBinding.prototype.subscribe = function () {};
  InputBinding.prototype.unsubscribe = function () {};
  InputBinding.prototype.receiveMessage = function () { throw "Not implemented"; };
  InputBinding.prototype.getState = function () { throw "Not implemented"; };
  InputBinding.prototype.getRatePolicy = function () { return null; };
  InputBinding.prototype.initialize = function () {};
  InputBinding.prototype.dispose = function () {};

  function OutputBinding() {}
  OutputBinding.prototype.find = function () { throw "Not implemented"; };
  OutputBinding.prototype.renderValue = function () { throw "Not implemented"; };
  OutputBinding.prototype.getId = function (el) { return el.getAttribute("data-input-id") || el.id; };
  OutputBinding.prototype.onValueChange = function (el, data) {
    this.clearError(el);
    return this.renderValue(el, data);
  };
  OutputBinding.prototype.onValueError = function (el, err) { this.renderError(el, err); };
  OutputBinding.prototype.renderError = function (el, err) {
    this.clearError(el);
    if (!err || err.message === "") {
      el.innerHTML = "";
      return;
    }
    el.className += " shiny-output-error";
    el.textContent = err.message;
  };
  OutputBinding.prototype.clearError = function (el) {
    el.className = el.className.replace(/(^|\s)shiny-output-error\S*/g, "");
  };
  OutputBinding.prototype.showProgress = function (el, show) {
    var cls = " recalculating";
    el.className = el.className.replace(/(^|\s)recalculating(\s|$)/g, " ").replace(/\s+$/, "");
    if (show) el.className += cls;
  };

  function versionParts(v) {
    return String(v).replace(/-/, ".").replace(/(\.0)+[^.]*$/, "").split(".");
  }
  function compareVersion(a, op, b) {
    var pa = versionParts(a);
    var pb = versionParts(b);
    var diff = 0;
    for (var i = 0; i < Math.min(pa.length, pb.length) && diff === 0; i++) {
      diff = parseInt(pa[i], 10) - parseInt(pb[i], 10);
    }
    if (diff === 0) diff = pa.length - pb.length;
    switch (op) {
      case "==": return diff === 0;
      case ">=": return diff >= 0;
      case ">": return diff > 0;
      case "<=": return diff <= 0;
      case "<": return diff < 0;
      default: throw "Unknown operator: " + op;
    }
  }

  // Calls made before the bridge starts wait here.
  var pending = { inputs: [], messages: [] };
  var handlers = {};

  var Shiny = {
    version: version,
    InputBinding: InputBinding,
    OutputBinding: OutputBinding,
    inputBindings: new BindingRegistry(),
    outputBindings: new BindingRegistry(),
    compareVersion: compareVersion,
    $escape: function (s) {
      return String(s).replace(/([!"#$%&'()*+,./:;<=>?@\[\\\]^`{|}~])/g, "\\$1");
    },
    setInputValue: function (name, value, opts) {
      pending.inputs.push([name, value, opts || {}]);
    },
    onInputChange: function (name, value, opts) {
      return Shiny.setInputValue(name, value, opts);
    },
    forgetLastInputValue: function () {},
    addCustomMessageHandler: function (type, fn) {
      handlers[type] = fn;
    },
    bindAll: function () {},
    unbindAll: function () {},
    initializeInputs: function () {},
    renderDependencies: function () {},
    renderDependenciesAsync: function () {
      return Promise.resolve();
    },
    renderContent: function (el, content, where) {
      var html = typeof content === "string" ? content : (content && content.html) || "";
      if (!where || where === "replace") el.innerHTML = html;
      else el.insertAdjacentHTML(where, html);
    },
    renderContentAsync: function (el, content, where) {
      Shiny.renderContent(el, content, where);
      return Promise.resolve();
    },
    renderHtml: function (html, el, deps, where) {
      Shiny.renderContent(el, { html: html, deps: deps }, where);
    },
    renderHtmlAsync: function (html, el, deps, where) {
      Shiny.renderHtml(html, el, deps, where);
      return Promise.resolve();
    },
    notifications: { show: function () {}, remove: function () {} },
    modal: { show: function () {}, remove: function () {} },
    showReconnectDialog: function () {},
    hideReconnectDialog: function () {},
    inDevMode: function () { return false; },
    shinyapp: {
      config: { workerId: "", sessionId: "shinymcp" },
      isConnected: function () { return true; },
      $inputValues: {},
      $values: {},
      $errors: {}
    },
    user: null,
    __shinymcp: { pending: pending, handlers: handlers, onRegister: null }
  };

  window.Shiny = Shiny;
})();
