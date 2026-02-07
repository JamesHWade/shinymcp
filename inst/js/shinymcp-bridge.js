// shinymcp-bridge.js
// MCP Apps postMessage/JSON-RPC bridge for shinymcp
// Implements the official MCP Apps postMessage protocol (SEP-1865).
// No external dependencies required.
(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  var config = {};
  var inputListeners = [];
  var messageHandler = null;
  var tornDown = false;
  var nextId = 1;
  var pendingRequests = {};
  var hostContext = null;

  // ---------------------------------------------------------------------------
  // Utility: read the value of a form element
  // ---------------------------------------------------------------------------
  function getInputValue(el) {
    if (!el) return null;
    var tag = el.tagName.toLowerCase();
    var type = (el.getAttribute("type") || "").toLowerCase();

    if (tag === "select") return el.value;
    if (tag === "textarea") return el.value;

    if (tag === "input") {
      if (type === "checkbox") return el.checked;
      if (type === "number" || type === "range") {
        var num = parseFloat(el.value);
        return isNaN(num) ? null : num;
      }
      if (type === "radio") {
        var name = el.getAttribute("name");
        if (name) {
          var form = el.closest("form") || document;
          var checked = form.querySelector(
            'input[type="radio"][name="' + name + '"]:checked'
          );
          return checked ? checked.value : null;
        }
        return el.checked ? el.value : null;
      }
      return el.value;
    }

    if (tag === "button" || type === "button" || type === "submit") {
      return el.value || el.textContent || true;
    }

    if (el.value !== undefined) return el.value;
    return el.textContent || null;
  }

  // ---------------------------------------------------------------------------
  // Utility: collect all current input values
  // ---------------------------------------------------------------------------
  function collectAllInputs() {
    var inputs = {};
    var elements = document.querySelectorAll("[data-shinymcp-input]");
    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      var id = el.getAttribute("data-shinymcp-input");
      if (id) {
        inputs[id] = getInputValue(el);
      }
    }
    return inputs;
  }

  // ---------------------------------------------------------------------------
  // Utility: update an output element
  // ---------------------------------------------------------------------------
  function updateOutput(id, value, type) {
    var el = document.querySelector(
      '[data-shinymcp-output="' + id + '"]'
    );
    if (!el) return;

    type = type || el.getAttribute("data-shinymcp-output-type") || "text";

    switch (type) {
      case "text":
        el.textContent = value;
        break;
      case "html":
        el.innerHTML = value;
        break;
      case "plot":
        el.innerHTML =
          '<img src="data:image/png;base64,' + value + '" alt="Plot output">';
        break;
      case "table":
        el.innerHTML = value;
        break;
      default:
        el.textContent = value;
    }
  }

  // ---------------------------------------------------------------------------
  // JSON-RPC messaging via postMessage
  // ---------------------------------------------------------------------------
  function sendRequest(method, params) {
    if (tornDown) return null;
    if (!window.parent || window.parent === window) return null;

    var id = nextId++;
    var message = {
      jsonrpc: "2.0",
      id: id,
      method: method,
    };
    if (params !== undefined) {
      message.params = params;
    }

    return new Promise(function (resolve) {
      pendingRequests[id] = resolve;
      window.parent.postMessage(message, "*");
    });
  }

  function sendNotification(method, params) {
    if (tornDown) return;
    if (!window.parent || window.parent === window) return;

    var message = {
      jsonrpc: "2.0",
      method: method,
    };
    if (params !== undefined) {
      message.params = params;
    }

    window.parent.postMessage(message, "*");
  }

  function sendResponse(id, result) {
    if (tornDown) return;
    if (!window.parent || window.parent === window) return;

    window.parent.postMessage(
      {
        jsonrpc: "2.0",
        id: id,
        result: result || {},
      },
      "*"
    );
  }

  // ---------------------------------------------------------------------------
  // Input change handling
  // ---------------------------------------------------------------------------
  function onInputChanged(event) {
    var el = event.target.closest("[data-shinymcp-input]");
    if (!el) return;

    // Update model context with current input values
    sendNotification("ui/update-model-context", {
      structuredContent: collectAllInputs(),
    });
  }

  function attachInputListeners() {
    var elements = document.querySelectorAll("[data-shinymcp-input]");
    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      var tag = el.tagName.toLowerCase();
      var type = (el.getAttribute("type") || "").toLowerCase();

      var events = [];
      if (
        tag === "select" ||
        type === "checkbox" ||
        type === "radio" ||
        type === "range"
      ) {
        events.push("change");
      } else if (tag === "input" || tag === "textarea") {
        events.push("input");
        events.push("change");
      } else if (tag === "button" || type === "button" || type === "submit") {
        events.push("click");
      } else {
        events.push("change");
        events.push("input");
      }

      for (var j = 0; j < events.length; j++) {
        el.addEventListener(events[j], onInputChanged);
        inputListeners.push({ element: el, event: events[j] });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Handle incoming messages from the host
  // ---------------------------------------------------------------------------
  function handleHostMessage(event) {
    if (tornDown) return;

    var data = event.data;
    if (!data || data.jsonrpc !== "2.0") return;

    // Handle responses to our requests
    if (data.id !== undefined && data.result !== undefined) {
      var resolve = pendingRequests[data.id];
      if (resolve) {
        delete pendingRequests[data.id];
        resolve(data.result);
      }
      return;
    }

    // Handle notifications and requests from host
    if (!data.method) return;

    switch (data.method) {
      case "ui/notifications/tool-result":
        handleToolResult(data.params);
        break;

      case "ui/notifications/tool-input":
        handleToolInput(data.params);
        break;

      case "ui/notifications/tool-input-partial":
        // Streaming partial input - could update UI progressively
        break;

      case "ui/notifications/tool-cancelled":
        // Tool was cancelled
        break;

      case "ui/notifications/host-context-changed":
        if (data.params) {
          hostContext = data.params;
        }
        break;

      case "ui/resource-teardown":
        // Respond to teardown request then clean up
        sendResponse(data.id, {});
        teardown();
        break;

      default:
        break;
    }
  }

  function handleToolResult(params) {
    if (!params) return;

    var content = params.content;
    if (!content || !Array.isArray(content)) return;

    // Extract text content from the tool result
    var textContent = "";
    for (var i = 0; i < content.length; i++) {
      if (content[i].type === "text") {
        textContent += content[i].text;
      }
    }

    // Try to parse as structured content and update outputs
    if (params.structuredContent && typeof params.structuredContent === "object") {
      var keys = Object.keys(params.structuredContent);
      for (var j = 0; j < keys.length; j++) {
        updateOutput(keys[j], params.structuredContent[keys[j]]);
      }
    } else if (textContent) {
      // Update all text outputs with the raw text result
      var outputs = document.querySelectorAll("[data-shinymcp-output]");
      if (outputs.length === 1) {
        var outputType =
          outputs[0].getAttribute("data-shinymcp-output-type") || "text";
        updateOutput(
          outputs[0].getAttribute("data-shinymcp-output"),
          textContent,
          outputType
        );
      }
    }
  }

  function handleToolInput(params) {
    if (!params || !params.arguments) return;

    // Update input elements with the tool arguments
    var args = params.arguments;
    var keys = Object.keys(args);
    for (var i = 0; i < keys.length; i++) {
      var inputId = keys[i];
      var value = args[inputId];
      var el = document.querySelector(
        '[data-shinymcp-input="' + inputId + '"]'
      );
      if (el) {
        var tag = el.tagName.toLowerCase();
        var type = (el.getAttribute("type") || "").toLowerCase();
        if (type === "checkbox") {
          el.checked = !!value;
        } else if (tag === "select" || tag === "input" || tag === "textarea") {
          el.value = value;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Teardown: clean up all listeners and observers
  // ---------------------------------------------------------------------------
  function teardown() {
    if (tornDown) return;
    tornDown = true;

    for (var i = 0; i < inputListeners.length; i++) {
      var entry = inputListeners[i];
      entry.element.removeEventListener(entry.event, onInputChanged);
    }
    inputListeners = [];

    if (messageHandler) {
      window.removeEventListener("message", messageHandler);
      messageHandler = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Initialization: implements the official MCP Apps ui/initialize handshake
  // ---------------------------------------------------------------------------
  function init() {
    // Read config from embedded JSON
    var configEl = document.getElementById("shinymcp-config");
    if (configEl) {
      try {
        config = JSON.parse(configEl.textContent);
      } catch (e) {
        console.warn("[shinymcp-bridge] Failed to parse config:", e);
        config = {};
      }
    }

    // Set up postMessage listener
    messageHandler = handleHostMessage;
    window.addEventListener("message", messageHandler);

    // Attach input change listeners
    attachInputListeners();

    // Send ui/initialize request per MCP Apps spec
    var initPromise = sendRequest("ui/initialize", {
      protocolVersion: "2025-06-18",
      clientInfo: {
        name: config.appName || "shinymcp-app",
        version: config.version || "0.0.1",
      },
      capabilities: {},
      appCapabilities: {
        availableDisplayModes: ["inline"],
      },
    });

    // Handle initialize response
    if (initPromise) {
      initPromise.then(function (result) {
        hostContext = result.hostContext || null;

        // Send initialized notification
        sendNotification("ui/notifications/initialized", {});
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Start on DOMContentLoaded (or immediately if already loaded)
  // ---------------------------------------------------------------------------
  if (
    document.readyState === "complete" ||
    document.readyState === "interactive"
  ) {
    init();
  } else {
    document.addEventListener("DOMContentLoaded", init);
  }
})();
