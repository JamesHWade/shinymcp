// shinymcp-bridge.js
// MCP Apps postMessage/JSON-RPC bridge for shinymcp
// No external dependencies required.
(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  var config = {};
  var inputListeners = [];
  var resizeObserver = null;
  var messageHandler = null;
  var tornDown = false;

  // ---------------------------------------------------------------------------
  // Utility: read the value of a form element
  // ---------------------------------------------------------------------------
  function getInputValue(el) {
    if (!el) return null;
    var tag = el.tagName.toLowerCase();
    var type = (el.getAttribute("type") || "").toLowerCase();

    // Select element
    if (tag === "select") {
      return el.value;
    }

    // Textarea
    if (tag === "textarea") {
      return el.value;
    }

    // Input elements by type
    if (tag === "input") {
      if (type === "checkbox") {
        return el.checked;
      }
      if (type === "number" || type === "range") {
        var num = parseFloat(el.value);
        return isNaN(num) ? null : num;
      }
      if (type === "radio") {
        // For radio buttons, find the checked one in the same name group
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
      // text, email, url, date, etc.
      return el.value;
    }

    // Button-like elements
    if (tag === "button" || type === "button" || type === "submit") {
      return el.value || el.textContent || true;
    }

    // Fallback: try value, then textContent
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
        // HTML output from trusted MCP host/R server
        el.innerHTML = value;
        break;

      case "plot":
        // Base64 plot image from trusted MCP host/R server
        el.innerHTML =
          '<img src="data:image/png;base64,' + value + '" alt="Plot output">';
        break;

      case "table":
        // HTML table from trusted MCP host/R server
        el.innerHTML = value;
        break;

      default:
        el.textContent = value;
    }
  }

  // ---------------------------------------------------------------------------
  // Utility: send a JSON-RPC message to the host via postMessage
  // ---------------------------------------------------------------------------
  function sendMessage(method, params) {
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

  // ---------------------------------------------------------------------------
  // Input change handling
  // ---------------------------------------------------------------------------
  function onInputChanged(event) {
    var el = event.target.closest("[data-shinymcp-input]");
    if (!el) return;

    var inputId = el.getAttribute("data-shinymcp-input");
    var value = getInputValue(el);
    var allInputs = collectAllInputs();

    sendMessage("ui/input-changed", {
      inputId: inputId,
      value: value,
      allInputs: allInputs,
    });
  }

  function attachInputListeners() {
    var elements = document.querySelectorAll("[data-shinymcp-input]");
    for (var i = 0; i < elements.length; i++) {
      var el = elements[i];
      var tag = el.tagName.toLowerCase();
      var type = (el.getAttribute("type") || "").toLowerCase();

      // Determine which event(s) to listen for
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
    if (!data || data.jsonrpc !== "2.0" || !data.method) return;

    switch (data.method) {
      case "ui/tool-result":
        handleToolResult(data.params);
        break;

      case "ui/teardown":
        teardown();
        break;

      default:
        // Unknown method - ignore
        break;
    }
  }

  function handleToolResult(params) {
    if (!params) return;

    var result = params.result;

    if (!result || typeof result !== "object") return;

    // result is a key-value map where keys are output IDs
    var keys = Object.keys(result);
    for (var i = 0; i < keys.length; i++) {
      var outputId = keys[i];
      var value = result[outputId];

      // Look up the output element to determine its type
      var el = document.querySelector(
        '[data-shinymcp-output="' + outputId + '"]'
      );
      var outputType = el
        ? el.getAttribute("data-shinymcp-output-type") || "text"
        : "text";

      updateOutput(outputId, value, outputType);
    }
  }

  // ---------------------------------------------------------------------------
  // Size reporting via ResizeObserver
  // ---------------------------------------------------------------------------
  function setupResizeObserver() {
    if (typeof ResizeObserver === "undefined") return;

    resizeObserver = new ResizeObserver(function (entries) {
      if (tornDown) return;
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i];
        if (entry.target === document.body) {
          var rect = entry.contentRect;
          sendMessage("ui/resize", {
            width: Math.ceil(rect.width),
            height: Math.ceil(rect.height),
          });
          break;
        }
      }
    });

    resizeObserver.observe(document.body);
  }

  // ---------------------------------------------------------------------------
  // Teardown: clean up all listeners and observers
  // ---------------------------------------------------------------------------
  function teardown() {
    if (tornDown) return;
    tornDown = true;

    // Remove input listeners
    for (var i = 0; i < inputListeners.length; i++) {
      var entry = inputListeners[i];
      entry.element.removeEventListener(entry.event, onInputChanged);
    }
    inputListeners = [];

    // Disconnect resize observer
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
    }

    // Remove message listener
    if (messageHandler) {
      window.removeEventListener("message", messageHandler);
      messageHandler = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Initialization
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

    // Set up resize observer
    setupResizeObserver();

    // Notify host that UI is ready
    sendMessage("ui/ready", {
      appName: config.appName || "shinymcp-app",
      tools: config.tools || [],
      version: config.version || "0.0.1",
      inputs: collectAllInputs(),
    });
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
