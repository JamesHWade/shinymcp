// shinymcp-bridge.js
// MCP Apps postMessage/JSON-RPC bridge for shinymcp
// Implements the official MCP Apps postMessage protocol (SEP-1865).
// No external dependencies required.
(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // Utility: CSS.escape polyfill for ES5 environments
  // ---------------------------------------------------------------------------
  var cssEscape =
    typeof CSS !== "undefined" && typeof CSS.escape === "function"
      ? function (str) {
          return CSS.escape(str);
        }
      : function (str) {
          return str.replace(/([!"#$%&'()*+,./:;<=>?@[\\\]^`{|}~])/g, "\\$1");
        };

  // ---------------------------------------------------------------------------
  // State
  // ---------------------------------------------------------------------------
  var config = {};
  var inputCache = {}; // argName -> element, built from config.toolArgs
  var inputListeners = [];
  var messageHandler = null;
  var tornDown = false;
  var nextId = 1;
  var pendingRequests = {};
  var hostContext = null;
  var callToolTimer = null;

  // ---------------------------------------------------------------------------
  // Utility: read the value of a form element
  // ---------------------------------------------------------------------------
  function getInputValue(el) {
    if (!el) return null;
    var tag = el.tagName.toLowerCase();
    var type = (el.getAttribute("type") || "").toLowerCase();

    // Radio-group container: div or fieldset wrapping radio inputs
    if (
      (tag === "div" || tag === "fieldset") &&
      el.querySelector('input[type="radio"]')
    ) {
      var selectedRadio = el.querySelector('input[type="radio"]:checked');
      return selectedRadio ? selectedRadio.value : null;
    }

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
  // Auto-detect: resolve form elements by tool argument names
  // ---------------------------------------------------------------------------

  // Deduplicated list of all argument names across all tools
  function getAllArgNames() {
    if (!config.toolArgs || typeof config.toolArgs !== "object") return [];
    var seen = {};
    var result = [];
    var tools = Object.keys(config.toolArgs);
    for (var i = 0; i < tools.length; i++) {
      var args = config.toolArgs[tools[i]];
      if (!Array.isArray(args)) continue;
      for (var j = 0; j < args.length; j++) {
        if (!seen[args[j]]) {
          seen[args[j]] = true;
          result.push(args[j]);
        }
      }
    }
    return result;
  }

  // Find the DOM element for a given argument name, with priority:
  // 1. Explicit data-shinymcp-input attribute
  // 2. Standard form elements by id (input, select, textarea, button)
  // 3. Container with id holding radio inputs
  function resolveInputElement(argName) {
    var escaped = cssEscape(argName);

    // Priority 1: explicit attribute
    var explicit = document.querySelector(
      '[data-shinymcp-input="' + escaped + '"]'
    );
    if (explicit) return explicit;

    // Priority 2: standard form elements by id
    var selectors = [
      'select#' + escaped,
      'input#' + escaped,
      'textarea#' + escaped,
      'button#' + escaped,
    ];
    for (var i = 0; i < selectors.length; i++) {
      var el = document.querySelector(selectors[i]);
      if (el) return el;
    }

    // Priority 3: container with id holding radio inputs
    var container = document.getElementById(argName);
    if (
      container &&
      container.querySelector('input[type="radio"]')
    ) {
      return container;
    }

    return null;
  }

  // Build the argName -> element cache from config.toolArgs
  function buildInputCache() {
    inputCache = {};
    var argNames = getAllArgNames();
    for (var i = 0; i < argNames.length; i++) {
      var el = resolveInputElement(argNames[i]);
      if (el) {
        inputCache[argNames[i]] = el;
      } else {
        console.warn(
          "[shinymcp-bridge] No DOM element found for tool argument '" +
            argNames[i] +
            "'. Use mcp_input() to explicitly mark it, or ensure an " +
            "element with id='" +
            argNames[i] +
            "' exists."
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Utility: collect all current input values
  // ---------------------------------------------------------------------------
  function collectAllInputs() {
    var inputs = {};

    // Collect from auto-detected cache first
    var cacheKeys = Object.keys(inputCache);
    for (var i = 0; i < cacheKeys.length; i++) {
      inputs[cacheKeys[i]] = getInputValue(inputCache[cacheKeys[i]]);
    }

    // Fall back to explicit data-shinymcp-input scan (backward compat + extras)
    var elements = document.querySelectorAll("[data-shinymcp-input]");
    for (var j = 0; j < elements.length; j++) {
      var el = elements[j];
      var id = el.getAttribute("data-shinymcp-input");
      if (id && !(id in inputs)) {
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
  // Server tool calling
  // ---------------------------------------------------------------------------

  // Build reverse lookup: input arg name -> list of tool names that use it
  function buildArgToToolsMap() {
    var map = {};
    if (!config.toolArgs || typeof config.toolArgs !== "object") return map;
    var tools = Object.keys(config.toolArgs);
    for (var i = 0; i < tools.length; i++) {
      var args = config.toolArgs[tools[i]];
      if (!Array.isArray(args)) continue;
      for (var j = 0; j < args.length; j++) {
        if (!map[args[j]]) {
          map[args[j]] = [];
        }
        map[args[j]].push(tools[i]);
      }
    }
    return map;
  }

  var argToToolsMap = {};
  var pendingChangedInputs = [];

  // Find which tools are affected by a set of changed input names.
  // If changedInputNames is null, returns all tools (used for initial call).
  function findAffectedTools(changedInputNames) {
    if (!config.toolArgs || typeof config.toolArgs !== "object") {
      // Legacy fallback: no toolArgs config means call all tools with all inputs.
      // Prior to multi-tool support, only config.tools[0] was called.
      // Apps generated by shinymcp always include toolArgs, so this path is
      // only hit by hand-written configs or very old generated HTML.
      return config.tools || [];
    }
    if (!changedInputNames) {
      return Object.keys(config.toolArgs);
    }
    var seen = {};
    var result = [];
    for (var i = 0; i < changedInputNames.length; i++) {
      var tools = argToToolsMap[changedInputNames[i]];
      if (!tools) continue;
      for (var j = 0; j < tools.length; j++) {
        if (!seen[tools[j]]) {
          seen[tools[j]] = true;
          result.push(tools[j]);
        }
      }
    }
    return result;
  }

  // Collect only the input values relevant to a specific tool
  function collectToolInputs(toolName, allInputs) {
    if (!config.toolArgs || !config.toolArgs[toolName]) return allInputs;
    var argNames = config.toolArgs[toolName];
    var result = {};
    for (var i = 0; i < argNames.length; i++) {
      if (argNames[i] in allInputs) {
        result[argNames[i]] = allInputs[argNames[i]];
      }
    }
    return result;
  }

  function callServerTools(inputs, changedInputNames) {
    if (!config.tools || config.tools.length === 0) return;

    var toolNames = findAffectedTools(changedInputNames);
    if (changedInputNames && toolNames.length === 0) {
      console.warn(
        "[shinymcp-bridge] Input change for '" +
          changedInputNames.join(", ") +
          "' did not map to any tool. Check toolArgs configuration."
      );
    }
    for (var i = 0; i < toolNames.length; i++) {
      callSingleTool(toolNames[i], collectToolInputs(toolNames[i], inputs));
    }
  }

  function callSingleTool(toolName, args) {
    var promise = sendRequest("tools/call", {
      name: toolName,
      arguments: args,
    });

    if (promise) {
      promise.then(function (result) {
        handleToolResult(result);
      })["catch"](function (err) {
        console.error(
          "[shinymcp-bridge] Tool call failed for '" + toolName + "':",
          err
        );
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Input change handling
  // ---------------------------------------------------------------------------
  function onInputChanged(event) {
    // Check if the changed element is a tracked input (cached or explicit)
    var changedArgName = null;
    var el = event.target.closest("[data-shinymcp-input]");
    if (el) {
      changedArgName = el.getAttribute("data-shinymcp-input");
    } else {
      // Check if target (or its ancestor) is a form element inside a cached element
      var targetTag = event.target.tagName.toLowerCase();
      var isFormEl =
        targetTag === "input" ||
        targetTag === "select" ||
        targetTag === "textarea" ||
        targetTag === "button";
      if (!isFormEl) return;

      var cacheKeys = Object.keys(inputCache);
      for (var i = 0; i < cacheKeys.length; i++) {
        if (inputCache[cacheKeys[i]].contains(event.target)) {
          changedArgName = cacheKeys[i];
          break;
        }
      }
      if (!changedArgName) return;
    }

    var inputs = collectAllInputs();

    // Update model context with current input values
    sendNotification("ui/update-model-context", {
      structuredContent: inputs,
    });

    // Accumulate changed input names across debounce intervals so rapid
    // changes to inputs in different tool groups all trigger their tools.
    if (changedArgName && pendingChangedInputs.indexOf(changedArgName) === -1) {
      pendingChangedInputs.push(changedArgName);
    }
    if (callToolTimer) clearTimeout(callToolTimer);
    callToolTimer = setTimeout(function () {
      var toSend = pendingChangedInputs.length > 0 ? pendingChangedInputs : null;
      pendingChangedInputs = [];
      callServerTools(inputs, toSend);
    }, 250);
  }

  function attachListenerToElement(el) {
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
    } else if (
      (tag === "div" || tag === "fieldset") &&
      el.querySelector('input[type="radio"]')
    ) {
      // Radio-group container: listen for change events bubbling up
      events.push("change");
    } else {
      events.push("change");
      events.push("input");
    }

    for (var j = 0; j < events.length; j++) {
      el.addEventListener(events[j], onInputChanged);
      inputListeners.push({ element: el, event: events[j] });
    }
  }

  function attachInputListeners() {
    var bound = [];

    function isBound(el) {
      for (var k = 0; k < bound.length; k++) {
        if (bound[k] === el) return true;
      }
      return false;
    }

    // Bind cached (auto-detected) elements
    var cacheKeys = Object.keys(inputCache);
    for (var i = 0; i < cacheKeys.length; i++) {
      var el = inputCache[cacheKeys[i]];
      if (!isBound(el)) {
        attachListenerToElement(el);
        bound.push(el);
      }
    }

    // Bind explicit data-shinymcp-input elements (backward compat)
    var elements = document.querySelectorAll("[data-shinymcp-input]");
    for (var j = 0; j < elements.length; j++) {
      if (!isBound(elements[j])) {
        attachListenerToElement(elements[j]);
        bound.push(elements[j]);
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

      // Try cache first, then explicit attribute
      var el = inputCache[inputId] ||
        document.querySelector('[data-shinymcp-input="' + inputId + '"]');
      if (!el) continue;

      var tag = el.tagName.toLowerCase();
      var type = (el.getAttribute("type") || "").toLowerCase();

      // Radio-group container
      if (
        (tag === "div" || tag === "fieldset") &&
        el.querySelector('input[type="radio"]')
      ) {
        var radios = el.querySelectorAll('input[type="radio"]');
        for (var j = 0; j < radios.length; j++) {
          radios[j].checked = radios[j].value === String(value);
        }
      } else if (type === "checkbox") {
        el.checked = !!value;
      } else if (tag === "select" || tag === "input" || tag === "textarea") {
        el.value = value;
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

    // Build auto-detect cache and arg->tool reverse lookup, then attach listeners
    buildInputCache();
    argToToolsMap = buildArgToToolsMap();
    attachInputListeners();

    // Send ui/initialize request per MCP Apps spec
    // Fields must match McpUiInitializeRequestSchema exactly:
    // appInfo (not clientInfo), appCapabilities, protocolVersion
    var initPromise = sendRequest("ui/initialize", {
      protocolVersion: "2025-06-18",
      appInfo: {
        name: config.appName || "shinymcp-app",
        version: config.version || "0.0.1",
      },
      appCapabilities: {},
    });

    // Handle initialize response
    if (initPromise) {
      initPromise.then(function (result) {
        hostContext = result.hostContext || null;

        // Send initialized notification
        sendNotification("ui/notifications/initialized", {});

        // Set up auto-resize notifications (like the official SDK)
        setupAutoResize();

        // Call all server tools with initial input values so outputs are populated
        callServerTools(collectAllInputs(), null);
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Auto-resize: notify host of content size changes
  // ---------------------------------------------------------------------------
  function setupAutoResize() {
    if (typeof ResizeObserver === "undefined") return;

    var lastWidth = 0;
    var lastHeight = 0;
    var scheduled = false;

    function sendBodySizeChanged() {
      if (scheduled) return;
      scheduled = true;
      requestAnimationFrame(function () {
        scheduled = false;
        var html = document.documentElement;

        // Measure actual content size
        var origW = html.style.width;
        var origH = html.style.height;
        html.style.width = "fit-content";
        html.style.height = "fit-content";
        var rect = html.getBoundingClientRect();
        html.style.width = origW;
        html.style.height = origH;

        var scrollbarWidth = window.innerWidth - html.clientWidth;
        var width = Math.ceil(rect.width + scrollbarWidth);
        var height = Math.ceil(rect.height);

        if (width !== lastWidth || height !== lastHeight) {
          lastWidth = width;
          lastHeight = height;
          sendNotification("ui/notifications/size-changed", {
            width: width,
            height: height,
          });
        }
      });
    }

    sendBodySizeChanged();

    var observer = new ResizeObserver(sendBodySizeChanged);
    observer.observe(document.documentElement);
    observer.observe(document.body);
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
