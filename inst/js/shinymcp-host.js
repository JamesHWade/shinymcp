(function () {
  "use strict";

  var PROTOCOL_VERSION = "2025-06-18";
  var BUS_INPUT_ID = "shinymcp_host_event";
  var hosts = {};
  var pendingToolCalls = {};
  var domObserver = null;
  var disconnectDisposeTimers = {};
  var DISCONNECT_DISPOSE_DELAY_MS = 1000;

  function jsonParse(text) {
    try {
      return JSON.parse(text);
    } catch (e) {
      return null;
    }
  }

  function hasShiny() {
    return !!(window.Shiny && typeof window.Shiny.setInputValue === "function");
  }

  function setError(container, text) {
    var errorEl = container.querySelector("[data-shinymcp-host-error]");
    if (!errorEl) return;
    if (text) {
      errorEl.textContent = text;
      errorEl.setAttribute("data-visible", "true");
    } else {
      errorEl.textContent = "";
      errorEl.removeAttribute("data-visible");
    }
  }

  function setStatus(container, state, text) {
    var statusEl = container.querySelector("[data-shinymcp-host-status]");
    if (!statusEl) return;
    statusEl.textContent = text || "";
    container.setAttribute("data-shinymcp-state", state || "idle");
  }

  function extractResultText(result) {
    if (!result || !result.content || !Array.isArray(result.content)) {
      return "";
    }

    var parts = [];
    for (var i = 0; i < result.content.length; i++) {
      if (result.content[i] && result.content[i].type === "text") {
        parts.push(result.content[i].text || "");
      }
    }
    return parts.join("\n").replace(/^\s+|\s+$/g, "");
  }

  function sendHostEvent(event) {
    if (!hasShiny()) return;
    window.Shiny.setInputValue(BUS_INPUT_ID, event, { priority: "event" });
  }

  function hostKey(instanceId, requestId) {
    return instanceId + ":" + requestId;
  }

  function showControls(container, trigger) {
    var toolbar = container.querySelector("[data-shinymcp-host-toolbar]");
    var execute = container.querySelector('[data-shinymcp-action="execute"]');
    var reset = container.querySelector('[data-shinymcp-action="reset"]');
    var interactive = trigger === "submit" || trigger === "manual";

    if (toolbar) {
      toolbar.style.display = "";
    }

    if (execute) {
      execute.style.display = interactive ? "" : "none";
      execute.textContent = trigger === "manual" ? "Run" : "Apply";
    }

    if (reset) {
      reset.style.display = interactive ? "" : "none";
    }
  }

  function readContainerConfig(container) {
    var script = container.querySelector(".shinymcp-host-config");
    if (!script) return null;
    return jsonParse(script.textContent || "");
  }

  function writeContainerConfig(container, config) {
    var script = container.querySelector(".shinymcp-host-config");
    if (!script) {
      script = document.createElement("script");
      script.type = "application/json";
      script.className = "shinymcp-host-config";
      container.appendChild(script);
    }
    script.textContent = JSON.stringify(config || {});
  }

  function bindControls(container, host, trigger) {
    var execute = container.querySelector('[data-shinymcp-action="execute"]');
    var reset = container.querySelector('[data-shinymcp-action="reset"]');
    var fullscreen = container.querySelector(
      '[data-shinymcp-action="fullscreen"]'
    );

    showControls(container, trigger);

    if (execute && !execute._shinymcpBound) {
      execute.addEventListener("click", function () {
        host.execute();
      });
      execute._shinymcpBound = true;
    }

    if (reset && !reset._shinymcpBound) {
      reset.addEventListener("click", function () {
        host.reset();
      });
      reset._shinymcpBound = true;
    }

    if (fullscreen && !fullscreen._shinymcpBound) {
      fullscreen.addEventListener("click", function () {
        host.toggleFullscreen();
      });
      fullscreen._shinymcpBound = true;
    }
  }

  function createHost(options) {
    var container = options.container;
    var iframe = options.iframe;
    var config = options.config || {};
    var disposed = false;
    var fullscreenFallback = false;
    var fullscreenListenersBound = false;

    function fullscreenElement() {
      return (
        document.fullscreenElement ||
        document.webkitFullscreenElement ||
        null
      );
    }

    function requestFullscreen(el) {
      if (el.requestFullscreen) {
        return el.requestFullscreen();
      }
      if (el.webkitRequestFullscreen) {
        return el.webkitRequestFullscreen();
      }
      return null;
    }

    function exitDocumentFullscreen() {
      if (document.exitFullscreen) {
        return document.exitFullscreen();
      }
      if (document.webkitExitFullscreen) {
        return document.webkitExitFullscreen();
      }
      return null;
    }

    function bindFullscreenListeners() {
      if (fullscreenListenersBound) return;
      document.addEventListener("fullscreenchange", onFullscreenChange);
      document.addEventListener("webkitfullscreenchange", onFullscreenChange);
      document.addEventListener("keydown", onKeydown);
      fullscreenListenersBound = true;
    }

    function unbindFullscreenListeners() {
      if (!fullscreenListenersBound) return;
      document.removeEventListener("fullscreenchange", onFullscreenChange);
      document.removeEventListener("webkitfullscreenchange", onFullscreenChange);
      document.removeEventListener("keydown", onKeydown);
      fullscreenListenersBound = false;
    }

    function isFullscreen() {
      return fullscreenElement() === container || fullscreenFallback;
    }

    function updateFullscreenButton() {
      var button = container.querySelector('[data-shinymcp-action="fullscreen"]');
      var active = isFullscreen();
      if (!button) return;
      button.setAttribute("aria-pressed", active ? "true" : "false");
      button.textContent = active ? "Exit full screen" : "Full screen";
      button.setAttribute(
        "title",
        active ? "Exit full screen" : "Full screen"
      );
    }

    function enterFallbackFullscreen() {
      bindFullscreenListeners();
      fullscreenFallback = true;
      container.setAttribute("data-shinymcp-fullscreen", "true");
      updateFullscreenButton();
    }

    function exitFallbackFullscreen() {
      fullscreenFallback = false;
      container.removeAttribute("data-shinymcp-fullscreen");
      updateFullscreenButton();
      unbindFullscreenListeners();
    }

    function enterFullscreen() {
      bindFullscreenListeners();
      var requested = requestFullscreen(container);
      if (requested && typeof requested["catch"] === "function") {
        requested["catch"](function () {
          enterFallbackFullscreen();
        });
        return;
      }
      if (!requested) {
        enterFallbackFullscreen();
      }
    }

    function exitFullscreen() {
      if (fullscreenElement() === container) {
        var exited = exitDocumentFullscreen();
        if (exited && typeof exited["catch"] === "function") {
          exited["catch"](function () {
            exitFallbackFullscreen();
          });
        }
        return;
      }
      exitFallbackFullscreen();
    }

    function onFullscreenChange() {
      if (fullscreenElement() !== container) {
        fullscreenFallback = false;
        container.removeAttribute("data-shinymcp-fullscreen");
        unbindFullscreenListeners();
      }
      updateFullscreenButton();
    }

    function onKeydown(event) {
      if (event.key === "Escape" && fullscreenFallback) {
        exitFallbackFullscreen();
      }
    }

    function postToIframe(message) {
      if (!iframe || !iframe.contentWindow) return;
      iframe.contentWindow.postMessage(message, "*");
    }

    function respond(id, result) {
      postToIframe({
        jsonrpc: "2.0",
        id: id,
        result: result || {},
      });
    }

    function notify(method, params) {
      var message = {
        jsonrpc: "2.0",
        method: method,
      };
      if (params !== undefined) {
        message.params = params;
      }
      postToIframe(message);
    }

    function setHostStatus(state, text) {
      if (options.setStatus) {
        options.setStatus(state, text, host);
      } else {
        setStatus(container, state, text);
      }
    }

    function getInitializeResult() {
      if (typeof options.initialize === "function") {
        return options.initialize(host);
      }
      return {
        protocolVersion: PROTOCOL_VERSION,
        hostInfo: {
          name: "shinymcp-host",
          version: "0.1.0",
        },
        hostCapabilities: {},
        hostContext: options.hostContext || null,
      };
    }

    function handleRequest(message) {
      var params = message.params || {};

      if (message.method === "ui/initialize") {
        Promise.resolve(getInitializeResult())
          .then(function (result) {
            respond(message.id, result || {});
            setHostStatus("connected", "ready");
          })
          ["catch"](function (err) {
            respond(message.id, {
              protocolVersion: PROTOCOL_VERSION,
              hostInfo: { name: "shinymcp-host", version: "0.1.0" },
              hostCapabilities: {},
            });
            setHostStatus("error", "initialize error");
            setError(container, err && err.message ? err.message : String(err));
          });
        return;
      }

      if (message.method === "tools/call") {
        setHostStatus("running", "running...");
        setError(container, "");
        Promise.resolve(
          options.callTool({
            requestId: message.id,
            name: params.name,
            arguments: params.arguments || {},
          }, host)
        )
          .then(function (result) {
            respond(message.id, result);
            notify("ui/notifications/tool-result", result);

            if (result && result.isError) {
              setHostStatus("error", "tool error");
              setError(container, extractResultText(result));
            } else {
              setHostStatus("connected", "ready");
            }
          })
          ["catch"](function (err) {
            var errorText = err && err.message ? err.message : String(err);
            var result = {
              content: [{ type: "text", text: "Host error: " + errorText }],
              isError: true,
            };
            respond(message.id, result);
            setHostStatus("error", "tool error");
            setError(container, "Host error: " + errorText);
          });
        return;
      }

      if (message.method === "ui/resource-teardown") {
        respond(message.id, {});
        host.dispose();
        return;
      }

      respond(message.id, {});
    }

    function handleNotification(message) {
      if (
        message.method === "ui/notifications/size-changed" &&
        (config.height === "auto" || config.height == null) &&
        !isFullscreen()
      ) {
        var nextHeight = message.params && message.params.height;
        if (typeof nextHeight === "number" && nextHeight > 0) {
          iframe.style.height = Math.min(nextHeight + 2, 2000) + "px";
        }
      }

      if (
        message.method === "ui/update-model-context" &&
        (config.trigger === "submit" || config.trigger === "manual")
      ) {
        setHostStatus("dirty", "changes pending");
      }

      if (typeof options.onNotification === "function") {
        options.onNotification(message.method, message.params || {}, host);
      }
    }

    function onMessage(event) {
      if (disposed || !iframe || event.source !== iframe.contentWindow) {
        return;
      }

      var message = event.data;
      if (!message || message.jsonrpc !== "2.0") {
        return;
      }

      if (message.method && message.id !== undefined) {
        handleRequest(message);
        return;
      }

      if (message.method) {
        handleNotification(message);
      }
    }

    var host = {
      config: config,
      container: container,
      iframe: iframe,
      notify: notify,
      execute: function (toolArgs) {
        if (toolArgs && typeof toolArgs === "object") {
          notify("ui/notifications/tool-input", { arguments: toolArgs });
        }
        notify("ui/notifications/trigger-tool-call", {});
      },
      reset: function () {
        notify("ui/notifications/reset", {});
        setError(container, "");
      },
      toggleFullscreen: function () {
        if (isFullscreen()) {
          exitFullscreen();
        } else {
          enterFullscreen();
        }
      },
      dispose: function () {
        if (disposed) return;
        disposed = true;
        window.removeEventListener("message", onMessage);
        if (isFullscreen()) {
          exitFullscreen();
        } else {
          unbindFullscreenListeners();
        }
        cancelDisconnectedHostDispose(config.instanceId);
        delete hosts[config.instanceId];
        if (typeof options.onDispose === "function") {
          options.onDispose(host);
        }
      },
    };

    bindControls(container, host, config.trigger);

    if (config.height && config.height !== "auto") {
      iframe.style.height = String(config.height);
    }

    if (options.appSrcdoc != null) {
      iframe.srcdoc = options.appSrcdoc;
    }
    if (options.appSrc != null) {
      iframe.src = options.appSrc;
    }

    window.addEventListener("message", onMessage);
    updateFullscreenButton();
    hosts[config.instanceId] = host;
    return host;
  }

  function callToolViaShiny(request, host) {
    return new Promise(function (resolve, reject) {
      if (!hasShiny()) {
        reject(new Error("Shiny is not available for shinymcp host transport"));
        return;
      }

      var key = hostKey(host.config.instanceId, request.requestId);
      pendingToolCalls[key] = { resolve: resolve, reject: reject };

      sendHostEvent({
        instanceId: host.config.instanceId,
        method: "tools/call",
        requestId: request.requestId,
        params: {
          name: request.name,
          arguments: request.arguments || {},
        },
      });
    });
  }

  function initContainer(container) {
    if (!container) return;

    if (container._shinymcpHost) {
      cancelDisconnectedHostDispose(container._shinymcpHost.config.instanceId);
      return;
    }

    var config = readContainerConfig(container);
    if (!config || !config.instanceId || !config.appHtml) return;
    cancelDisconnectedHostDispose(config.instanceId);

    var iframe = container.querySelector("[data-shinymcp-host-frame]");
    if (!iframe) return;

    container.style.setProperty(
      "--shinymcp-fixed-height",
      config.height && config.height !== "auto" ? String(config.height) : "420px"
    );

    container._shinymcpHost = createHost({
      container: container,
      iframe: iframe,
      config: config,
      appSrcdoc: config.appHtml,
      hostContext: {
        instanceId: config.instanceId,
        initialArguments: config.initialArguments || null,
      },
      initialize: function () {
        return {
          protocolVersion: PROTOCOL_VERSION,
          hostInfo: {
            name: "shinymcp-shiny-host",
            version: "0.1.0",
          },
          hostCapabilities: {},
          hostContext: {
            instanceId: config.instanceId,
            initialArguments: config.initialArguments || null,
          },
        };
      },
      callTool: callToolViaShiny,
      onNotification: function (method, params) {
        sendHostEvent({
          instanceId: config.instanceId,
          method: method,
          params: params || {},
        });
      },
      onDispose: function () {
        sendHostEvent({
          instanceId: config.instanceId,
          method: "ui/resource-teardown",
          params: {},
        });
      },
    });

    setStatus(container, "connecting", "connecting...");
  }

  function cancelDisconnectedHostDispose(instanceId) {
    var timer = disconnectDisposeTimers[instanceId];
    if (!timer) return;
    clearTimeout(timer);
    delete disconnectDisposeTimers[instanceId];
  }

  function scheduleDisconnectedHostDispose(host) {
    var instanceId = host && host.config && host.config.instanceId;
    if (!instanceId || disconnectDisposeTimers[instanceId]) return;

    disconnectDisposeTimers[instanceId] = setTimeout(function () {
      delete disconnectDisposeTimers[instanceId];
      if (hosts[instanceId] !== host) return;
      if (!host.container || host.container.isConnected) return;
      host.dispose();
    }, DISCONNECT_DISPOSE_DELAY_MS);
  }

  function scanForHosts(root) {
    var scope = root && root.querySelectorAll ? root : document;
    // querySelectorAll only matches descendants, so check the root itself too.
    // Some hosts (e.g. shinychat's raw-HTML component) inject our container as a
    // top-level added node via innerHTML, in which case it IS the scanned node.
    if (
      scope.nodeType === 1 &&
      scope.matches &&
      scope.matches("[data-shinymcp-host]")
    ) {
      initContainer(scope);
    }
    var nodes = scope.querySelectorAll("[data-shinymcp-host]");
    for (var i = 0; i < nodes.length; i++) {
      initContainer(nodes[i]);
    }
  }

  function pruneDisconnectedHosts() {
    var ids = Object.keys(hosts);
    for (var i = 0; i < ids.length; i++) {
      var host = hosts[ids[i]];
      if (!host || !host.container) continue;
      if (host.container.isConnected) {
        cancelDisconnectedHostDispose(ids[i]);
      } else {
        scheduleDisconnectedHostDispose(host);
      }
    }
  }

  function ensureObserver() {
    if (domObserver || typeof MutationObserver === "undefined") return;
    domObserver = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var added = mutations[i].addedNodes;
        for (var j = 0; j < added.length; j++) {
          if (added[j] && added[j].nodeType === 1) {
            scanForHosts(added[j]);
          }
        }
      }
      pruneDisconnectedHosts();
    });

    if (document.documentElement) {
      domObserver.observe(document.documentElement, {
        childList: true,
        subtree: true,
      });
    }
  }

  window.shinymcpHost = window.shinymcpHost || {};
  window.shinymcpHost.createHost = createHost;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      scanForHosts(document);
      ensureObserver();
    });
  } else {
    scanForHosts(document);
    ensureObserver();
  }

  if (window.Shiny && typeof window.Shiny.addCustomMessageHandler === "function") {
    window.Shiny.addCustomMessageHandler("shinymcp-host-init", function (msg) {
      var container = document.getElementById(msg.id);
      if (!container) return;
      writeContainerConfig(container, msg.config || {});
      initContainer(container);
    });

    window.Shiny.addCustomMessageHandler("shinymcp-host-response", function (msg) {
      var key = hostKey(msg.instanceId, msg.requestId);
      var pending = pendingToolCalls[key];
      if (!pending) return;
      delete pendingToolCalls[key];
      pending.resolve(msg.result || {});
    });

    window.Shiny.addCustomMessageHandler("shinymcp-host-command", function (msg) {
      var host = hosts[msg.instanceId];
      if (!host) return;

      if (msg.command === "execute") {
        host.execute(msg.arguments || null);
        return;
      }

      if (msg.command === "reset") {
        host.reset();
        return;
      }

      if (msg.command === "dispose") {
        host.dispose();
      }
    });
  }
})();
