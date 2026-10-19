// PLAYGROUND
import { importObject } from "./playground_wasi_env.js";
import { EventType, setWasiInstance } from "./playground_wasi.js";
import {
  domNodeRegistry,
  beforeHooksHandlers,
  observeredSections,
  loadedSections,
  pureNodeRegistry,
  afterHooksHandlers,
  hooksMounted,
  hooksCtxCreated,
  hooksMountedCtx,
  hooksDestroyCtx,
  eventStorage,
} from "./playground_maps.js";
import {
  COMPONENT_TYPES,
  traverseUINodes,
  animateExit,
  resetTimers,
  traverse,
} from "./playground_traversal.js";
import { state } from "./playground_state.js";
import { styleRuleCache, styleClassCache } from "./playground_wasi_styling.js";
import { parseWasmError } from "./playground_formatter.js";
// import { initCacheModule } from "./cachebindings.js";

export let wasmInstance;
export let activeNodeIds = new Set();
export let rootNodeId = "root";
export let layoutInfo;
export let UINodelayoutInfo;

let tree_node;

let layoutInfoPtr;
let uiNodeLayoutInfoPtr;

window.addEventListener("popstate", async function (event) {
  const path = window.location.pathname;
  rerenderRoute(path);
  requestAnimationFrame(() => {
    wasmInstance.onPopStateCallback();
  });
});

window.addEventListener("load", async () => {
  const url = new URL(window.location.href);
  for (const [key, handler] of beforeHooksHandlers.entries()) {
    console.log("beforeHooksHandlers", key);
    if (url.pathname === "/docs") {
      console.log("fkjasldfkjas;lfkjasf;l");
    }
  }
});

export let text_data;

window.addEventListener("message", async (e) => {
  console.log("Message", e);
  if (e.data.type === "load-wasm") {
    try {
      const instance = await loadWasm(e.data.bytes, importObject);
      const exports = instance.exports;
      wasmInstance = exports;
      setWasiInstance(wasmInstance);
      text_data = {};
      init(); // this calls setupLayoutInfo + setupWasiInstance
      window.parent.postMessage({ type: "playground-loaded" }, "*");
    } catch (err) {
      console.error("Playground WASM error:", err);
      window.parent.postMessage(
        { type: "playground-error", error: err.message },
        "*",
      );
    }
  }
});

window.parent.postMessage({ type: "playground-ready" }, "*");

async function loadWasm(source, imports) {
  let bytes;
  if (source instanceof ArrayBuffer) {
    bytes = source;
  } else {
    const response = await fetch(source);
    bytes = await response.arrayBuffer();
  }
  const { instance } = await WebAssembly.instantiate(bytes, imports);
  return instance;
}

export const encodeString = (string) => {
  const buffer = new TextEncoder().encode(string);
  const pointer = wasmInstance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    wasmInstance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  wasmInstance.setRouteRenderTree(pointer);
};

export const rerenderRoute = (navigatedPath) => {
  const route = navigatedPath === "/" ? "/root" : `/root${navigatedPath}`;

  currentPath = window.location.pathname;
  currentPath = "/";

  for (const [key, handler] of afterHooksHandlers.entries()) {
    const pathEnd = key.indexOf("-");
    const path = key.substring(0, pathEnd);

    // Check if currentPath starts with the hook path
    if (currentPath === path || currentPath.startsWith(path + "/")) {
      handler();
    }
  }

  for (const [key, handler] of beforeHooksHandlers.entries()) {
    const pathEnd = key.indexOf("-");
    const path = key.substring(0, pathEnd);

    // Check if currentPath starts with the hook path
    if (navigatedPath === path || navigatedPath.startsWith(path + "/")) {
      handler();
    }
  }

  const buffer = new TextEncoder().encode(route);
  const pointer = wasmInstance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    wasmInstance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  const success = wasmInstance.callRouteRenderCycle(pointer);
  if (!success) {
    console.error("Failed to call route render cycle");
  }

  const count = wasmInstance.removalCount();

  for (let i = 0; i < count; i++) {
    const ptr = wasmInstance.getRemovalIdPtr(i);
    const len = wasmInstance.getRemovalIdLen(i);
    const id = readWasmString(ptr, len);

    const elements = document.querySelectorAll(`[id="${id}"]`);
    if (elements.length === 1) {
      animateExit(elements[0], i).catch((e) =>
        console.error("Error destroying node:", e),
      );
    }
  }
  wasmInstance.clearRemovalQueueRetainingCapacity();

  const has_dirty = wasmInstance.hasDirty();
  // We need to fix this
  // root.innerHTML = "";
  // wasmInstance.clearRemovedNodesretainingCapacity();
  // clearCSS();
  // styleRuleCache.clear();
  //
  // loadTheme();
  // const global_style_ptr = wasmInstance.getGlobalVariablesPtr();
  // const global_style_len = wasmInstance.getGlobalVariablesLen();
  // if (global_style_ptr !== 0) {
  //   const global_css = readWasmString(global_style_ptr, global_style_len);
  //   injectCSS(global_css);
  // }
  //
  // const css = readWasmString(wasmInstance.getCSS(), wasmInstance.getCSSLen());
  // injectCSS(css);
  // console.log("css", css);
  // let index = 0;
  // for (const rule of styleSheet.cssRules) {
  //   styleRuleCache.set(rule.selectorText, index);
  //   index += 1;
  // }
  if (has_dirty) {
    const rootUINode = wasmInstance.getRenderUINodeRootPtr();
    if (rootUINode === 0) {
      state.initial_render = false;
      wasmInstance.resetRerender();
      requestAnimationFrame(wasmInstance.cleanUp);
      return;
    }
    // this active set does not include the layouts
    activeNodeIds = new Set();
    // state.initial_render = true;
    traverseUINodes(root, rootUINode);

    callDestroyFncs();
    removeInactiveNodes();
    wasmInstance.markCurrentTreeNotDirty();
    wasmInstance.resetRerender();
    wasmInstance.registerAllListenerCallbacks();

    // handleIntersection();
    // requestAnimationFrame(wasmInstance.cleanUp);
    // wasmInstance.onEndCtxCallback();

    const hash = window.location.hash;
    if (hash) {
      const id = window.location.hash.substring(1, hash.length);
      const element = document.getElementById(id);
      if (element) {
        // Scroll the element into view with options
        element.scrollIntoView({
          // block: "center", // Vertically align to the center of the screen
        });
      }
    } else {
      // window.scrollTo({
      //   top: 0,
      //   behavior: "smooth", // or 'auto' for instant scroll
      // });
    }
    requestAnimationFrame(() => {
      hooksMounted.forEach((value, key) => {
        wasmInstance.hooksMountedCallback(key);
        hooksMounted.delete(key);
      });
      hooksMountedCtx.forEach((value, key) => {
        wasmInstance.hooksMountedCallbackCtx(key);
        hooksMountedCtx.delete(key);
      });
      // wasmInstance.onMountCtxCallback();
      hooksCtxCreated.forEach((value, key) => {
        wasmInstance.callOnCreateNode(key);
        hooksCtxCreated.delete(key);
      });
    });

    // wasmInstance.callAllMountedCallbacks();
    // console.log(pureNodeRegistry);
  } else {
    wasmInstance.resetRerender();
  }

  requestAnimationFrame(wasmInstance.onEndCallback);
  // wasmInstance.onEndCallback();
  // wasmInstance.onEndCtxCallback();
};

export const navToRoute = (string) => {
  const buffer = new TextEncoder().encode(string);
  const pointer = wasmInstance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    wasmInstance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  wasmInstance.setRouteRenderTree(pointer);
};

export const allocStringFrame = (string) => {
  const buffer = new TextEncoder().encode(string);
  const pointer = wasmInstance.allocUint8Frame(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    wasmInstance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  return pointer;
};

export const allocString = (string) => {
  const buffer = new TextEncoder().encode(string);
  const pointer = wasmInstance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    wasmInstance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  return pointer;
};

export let root;

function setupLayoutInfo() {
  // Set up listener for back/forward buttons
  // Get the memory layout information
  // So we grab the memory layout of each render command
  // layoutInfoPtr = wasmInstance.allocateLayoutInfo();

  // Corrected JavaScript code to read layout info
  uiNodeLayoutInfoPtr = wasmInstance.allocateUINodeLayoutInfo();

  UINodelayoutInfo = {
    // Corresponds directly to the corrected Zig struct order
    UINodeSize: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 0,
      4,
    ).getUint32(0, true),

    // --- Direct offsets in RenderCommand ---
    elemTypeOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 4,
      4,
    ).getUint32(0, true),
    textPtrOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 8,
      4,
    ).getUint32(0, true),
    hrefPtrOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 12,
      4,
    ).getUint32(0, true),
    idPtrOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 16,
      4,
    ).getUint32(0, true),
    indexOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 20,
      4,
    ).getUint32(0, true),
    classnamePtrOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 24,
      4,
    ).getUint32(0, true),

    hashOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 28,
      4,
    ).getUint32(0, true),
    styleChangedOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 32,
      4,
    ).getUint32(0, true),
    propsChangedOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 36,
      4,
    ).getUint32(0, true),
    dirtyOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 40,
      4,
    ).getUint32(0, true),
    hooksOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 44,
      4,
    ).getUint32(0, true),
    styleHashOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 48,
      4,
    ).getUint32(0, true),
    accessibilityOffset: new DataView(
      wasmInstance.memory.buffer,
      uiNodeLayoutInfoPtr + 52,
      4,
    ).getUint32(0, true),
  };
}

function getSystemTheme() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches
    ? "dark"
    : "light";
}

function loadTheme() {
  const savedTheme = localStorage.getItem("theme") || getSystemTheme();
  if (savedTheme === "dark") {
    document.documentElement.setAttribute("data-theme", "dark");
    try {
      wasmInstance.setTheme(1);
    } catch (e) {
      console.log("Error setting theme", e);
    }
  } else {
    const savedTheme = localStorage.getItem("theme");
    if (savedTheme === "dark") {
      document.documentElement.setAttribute("data-theme", "dark");
      wasmInstance.setTheme(1);
    }
  }
}

export const styleSheet = new CSSStyleSheet();
export let breadcrumbs = [];

export let currentPath;
function setupWasiInstance() {
  wasmInstance.init(); // Example UI function

  // new PerformanceMonitor();

  const rootContainer = document.getElementById("contents");

  // 1. Define all the events you want your framework to listen to globally
  const delegatedEvents = [
    "click",
    "dblclick",
    "input",
    "change",
    "keydown",
    "keyup",
    "submit",
    "focusin", // Bubbling version of focus
    "focusout", // Bubbling version of blur
  ];

  // 2. The single master function that handles EVERYTHING
  function handleGlobalEvent(event) {
    // Find the closest element that has an ID (so we can look it up in the registry)
    let targetElement = event.target.closest("[id]");

    if (event.type === "click" || event.type === "dbclick") {
      targetElement = event.target.closest("button");
    }

    if (!targetElement) return;

    if (targetElement.id === null || targetElement.id === undefined) {
      return;
    }

    const nodeInfo = domNodeRegistry.get(targetElement.id);
    if (!nodeInfo) return;

    const callback_id = nodeInfo.hash + EventType[event.type];
    eventStorage[callback_id] = event;

    const type = nodeInfo.elementType;

    // --- BUTTON LOGIC ---
    if (
      type === COMPONENT_TYPES.BUTTON_CTX ||
      type === COMPONENT_TYPES.BUTTON
    ) {
      if (event.type === "click" || event.type === "dbclick") {
        event.preventDefault();
        event.stopPropagation();
        try {
          wasmInstance.invokeErasedCallback(nodeInfo.hash);
        } catch (e) {
          handleWasmError(e, targetElement.id);
        }
      }
      return;
    }

    // --- INPUT LOGIC (Example for focus/blur) ---
    if (
      type === COMPONENT_TYPES.TEXT_FIELD ||
      type === COMPONENT_TYPES.TEXT_AREA
    ) {
      if (event.type === "focusin") {
        const callback_id = nodeInfo.hash + EventType["focus"];
        eventStorage[callback_id] = event;

        wasmInstance.dispatchNodeEvent(nodeInfo.node_ptr, EventType["focus"]);
      }
      if (event.type === "focusout") {
        const callback_id = nodeInfo.hash + EventType["blur"];
        eventStorage[callback_id] = event;

        wasmInstance.dispatchNodeEvent(nodeInfo.node_ptr, EventType["blur"]);
      }
      if (event.type === "input") {
        wasmInstance.dispatchNodeEvent(nodeInfo.node_ptr, EventType["input"]);
      }
      return;
    }

    if (type === COMPONENT_TYPES.FORM) {
      if (event.type === "submit") {
        const callback_id = nodeInfo.hash + EventType["submit"];
        eventStorage[callback_id] = event;

        wasmInstance.dispatchNodeEvent(nodeInfo.node_ptr, EventType["submit"]);
      }
      return;
    }

    if ("keydown" === event.type || "keyup" === event.type) {
      wasmInstance.dispatchNodeEvent(nodeInfo.hash, EventType[event.type]);
    }
  }

  // 3. Loop through the array and attach the master function to the root
  delegatedEvents.forEach((eventType) => {
    rootContainer.addEventListener(eventType, handleGlobalEvent);
  });

  // 4. (Bonus) Extracted your error handler so the main function isn't cluttered
  function handleWasmError(e, elementId) {
    if (e instanceof WebAssembly.RuntimeError) {
      const parsed = parseWasmError(e);
      const idPtr = allocStringFrame(JSON.stringify(parsed));

      const eventData = { id: elementId };
      console.log(eventData);

      const eventPtr = allocStringFrame(JSON.stringify(eventData));
      wasmInstance.recordState(idPtr, eventPtr);
    }
    throw e;
  }

  currentPath = window.location.pathname;
  currentPath = "/";

  for (const [key, handler] of beforeHooksHandlers.entries()) {
    const pathEnd = key.indexOf("-");
    const path = key.substring(0, pathEnd);

    // Check if currentPath starts with the hook path
    if (currentPath === path || currentPath.startsWith(path + "/")) {
      handler();
    }
  }

  loadTheme();

  if (currentPath === "/") {
    route_ptr = allocString("/root");
  } else {
    route_ptr = allocString(`/root${currentPath}`);
  }
  console.log("Rendering UI...");
  wasmInstance.renderUI(route_ptr);

  const global_style_ptr = wasmInstance.getGlobalVariablesPtr();
  const global_style_len = wasmInstance.getGlobalVariablesLen();
  if (global_style_ptr !== 0) {
    const global_css = readWasmString(global_style_ptr, global_style_len);
    injectCSS(global_css);
  }

  const css = readWasmString(wasmInstance.getCSS(), wasmInstance.getCSSLen());
  injectCSS(css);

  const animations_ptr = wasmInstance.getAnimationsPtr();
  if (animations_ptr > 0) {
    const animations_len = wasmInstance.getAnimationsLen();
    const animations_css = readWasmString(animations_ptr, animations_len);
    injectCSS(animations_css);
  }

  const edges_ptr = wasmInstance.getEdgesPtr();
  if (edges_ptr > 0) {
    const edges_len = wasmInstance.getEdgesLen();
    const edges_css = readWasmString(edges_ptr, edges_len);
    // console.log("edges_css", edges_css);
    injectCSS(edges_css);
  }

  const polygons_ptr = wasmInstance.getPolygonsPtr();
  if (polygons_ptr > 0) {
    const polygons_len = wasmInstance.getPolygonsLen();
    const polygons_css = readWasmString(polygons_ptr, polygons_len);
    injectCSS(polygons_css);
  }
  // const start = performance.now();
  activeNodeIds = new Set();
  const rootUINode = wasmInstance.getRenderUINodeRootPtr();
  traverseUINodes(root, rootUINode);
  state.initial_render = false;
  // callDestroyFncs();
  removeInactiveNodes();
  wasmInstance.markCurrentTreeNotDirty();
  wasmInstance.resetRerender();

  const hash = window.location.hash;
  if (hash) {
    const id = window.location.hash.substring(1, hash.length);
    const element = document.getElementById(id);
    if (element) {
      // Scroll the element into view with options
      element.scrollIntoView({
        // block: "center", // Vertically align to the center of the screen
      });
    }
  } else {
    // window.scrollTo({
    //   top: 0,
    //   behavior: "smooth", // or 'auto' for instant scroll
    // });
  }

  document.fonts.ready.then(() => {
    hooksMounted.forEach((value, key) => {
      wasmInstance.hooksMountedCallback(key);
      hooksMounted.delete(key);
    });
    hooksMountedCtx.forEach((value, key) => {
      wasmInstance.hooksMountedCallbackCtx(key);
      hooksMountedCtx.delete(key);
    });
    // wasmInstance.onMountCtxCallback();
    hooksCtxCreated.forEach((value, key) => {
      wasmInstance.callOnCreateNode(key);
      hooksCtxCreated.delete(key);
    });
  });

  requestAnimationFrame(() => {
    wasmInstance.onEndCallback();
    wasmInstance.onEndCtxCallback();
    wasmInstance.registerAllListenerCallbacks();
  });

  // After render completes
  // const memory = wasmInstance.memory;
  // const heapSizeKB = memory.buffer.byteLength / 1024;
  // console.log(`Components: ${10_000}, Heap: ${heapSizeKB}KB`);
}

function readAllRenderCommands(baseOffset, count) {
  const view = new DataView(wasmInstance.memory.buffer);
  // const mem = new Uint8Array(wasmInstance.memory.buffer);

  const commands = new Array(count);

  for (let i = 0; i < count; i++) {
    const offset = baseOffset + i * layoutInfo.renderCommandSize;

    let css = "";
    let keyFrames = "";
    let styleId = "";
    let id = "";
    let btnId = 0;
    let hoverCss = "";
    let focusCss = "";
    let focusWithinCss = "";
    let tooltipCss = "";
    let tooltipTitle = "";
    let exitAnimationId = null;

    const elemType = view.getUint8(offset + layoutInfo.elemTypeOffset);

    const nodePtr = view.getUint32(offset + layoutInfo.nodePtrOffset, true);
    const isDirty = wasmInstance.getDirtyValue(nodePtr);

    // For text, you need to handle the string slice differently
    const textPtr = view.getUint32(offset + layoutInfo.textPtrOffset, true);
    const textLen = view.getUint32(offset + layoutInfo.textPtrOffset + 4, true);

    const hrefPtr = view.getUint32(offset + layoutInfo.hrefPtrOffset, true);
    const hrefLen = view.getUint32(offset + layoutInfo.hrefPtrOffset + 4, true);
    const changedStyle = view.getUint8(
      offset + layoutInfo.styleChangedOffset,
      true,
    );
    // const hasChildren = view.getUint8(
    //   offset + layoutInfo.hasChildrenOffset,
    //   true,
    // );

    const idPtr = view.getUint32(offset + layoutInfo.idPtrOffset, true);
    const idLen = view.getUint32(offset + layoutInfo.idPtrOffset + 4, true);
    id = idPtr ? readWasmString(idPtr, idLen) : "";
    const hash = view.getUint32(offset + layoutInfo.hashOffset, true);
    const index = view.getUint32(offset + layoutInfo.indexOffset, true);

    let hooks = {};
    if (isDirty) {
      hooks = {
        createdId: view.getUint32(offset + layoutInfo.hooksOffset, true),
        mountedId: view.getUint32(offset + layoutInfo.hooksOffset + 4, true),
        updatedId: view.getUint32(offset + layoutInfo.hooksOffset + 8, true),
        destroyId: view.getUint32(offset + layoutInfo.hooksOffset + 12, true),
      };

      const classnamePtrOffset = layoutInfo.classnamePtrOffset;

      // 2. Read the actual pointer value from the RenderCommand struct.
      const classnamePtr = view.getUint32(offset + classnamePtrOffset, true);

      // 3. If the pointer is not null, read the length and then the string.
      if (classnamePtr) {
        // The length is ALWAYS 4 bytes after the pointer for a slice.
        const classnameLen = view.getUint32(
          offset + classnamePtrOffset + 4,
          true,
        );

        const classname = readWasmString(classnamePtr, classnameLen);
        styleId = classname;
      }
    }

    const stateType = view.getUint32(
      offset + layoutInfo.renderTypeOffset,
      true,
    );

    const props = {
      css,
      hoverCss,
      focusCss,
      focusWithinCss,
      btnId,
      keyFrames,
      tooltipCss,
      tooltipTitle,
      textPtr,
      textLen,
      hrefPtr,
      hrefLen,
      // hasChildren,
    };

    commands[i] = {
      elemType,
      props,
      id,
      index,
      hooks,
      nodePtr,
      exitAnimationId,
      styleId,
      hash,
      isDirty,
      stateType,
      changedStyle,
    };
  }

  return commands;
}

// function injectCSS(cssString) {
//   const sheet = new CSSStyleSheet();
//   sheet.replaceSync(cssString);
//   document.adoptedStyleSheets = [sheet, ...document.adoptedStyleSheets];
//   console.log(document.adoptedStyleSheets);
// }

// Create ONE global stylesheet
// const styleSheet = new CSSStyleSheet();
document.adoptedStyleSheets = [...document.adoptedStyleSheets, styleSheet];

function clearCSS() {
  styleSheet.replaceSync("");
  // document.adoptedStyleSheets = [];
}

export function injectCSS(cssString) {
  const existingRules = Array.from(styleSheet.cssRules)
    .map((rule) => rule.cssText)
    .join("\n");

  const finalCSS = `${existingRules}\n${cssString}`;

  styleSheet.replaceSync(finalCSS);
  rebuildCacheFromStylesheet();
}

export function rebuildCacheFromStylesheet() {
  styleRuleCache.clear();

  for (let i = 0; i < styleSheet.cssRules.length; i++) {
    const rule = styleSheet.cssRules[i];
    // CSSStyleRule has selectorText, other rule types (like @keyframes) don't
    if (rule.selectorText) {
      // Handle pseudo-selectors like .intr_123:hover
      // We want to cache as ".intr_123" not ".intr_123:hover"
      let selector = rule.selectorText;

      // If you want the full selector including :hover
      styleRuleCache.set(selector, i);

      // Or if you want to normalize (strip pseudo-selectors):
      // const baseSelector = selector.split(':')[0];
      // styleRuleCache.set(baseSelector, i);
    }
  }
}

const frag = document.createDocumentFragment();
export let U8;
export let U32;
async function init() {
  root = document.getElementById("contents");

  // Show a loading state or basic structure immediately
  // root.innerHTML = '<div class="loading">Loading...</div>';
  // document.body.appendChild(root);

  // requestAnimationFrame(() => {
  setupLayoutInfo();
  setupWasiInstance();

  // });
}

export function loadSection(element) {
  const id = element.id;
  // if it does not include the id then we have already loaded this section
  if (!observeredSections.has(id)) {
    return;
  }
  const section = observeredSections.get(id);
  wasmInstance.markUINodeTreeDirty(section.renderCmd.nodePtr);
  traverse(element, true, section.treeNodePtr, layoutInfo);
}
export function handleIntersection() {
  const options = {
    root: null,
    rootMargin: "0px", // Only 50px buffer at bottom
    threshold: 0.1,
  };
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting && !loadedSections.has(entry.target.id)) {
        console.log("Intersection", entry.target.id);
        loadedSections.add(entry.target.id);
        loadSection(entry.target);
      }
    });
  }, options);

  // Observe all <section> elements
  document.querySelectorAll("section").forEach((section) => {
    observer.observe(section);
  });
}

let route_ptr = null;

let renderTimeout = null;
const DEBOUNCE_DELAY = 8; // Can be 0 for next tick, or 16-50ms for smoother batching
//
export function requestRerender() {
  // if (renderTimeout) {
  //   clearTimeout(renderTimeout);
  // }

  // renderTimeout = setTimeout(() => {
  // renderTimeout = null;
  if (!state.isRenderScheduled) {
    state.isRenderScheduled = true;
    requestAnimationFrame(render);
  }
  // }, 0);
}

let dirty_count = 0;
let readtime = 0;
export async function render() {
  console.log("Rendering");
  let start = performance.now();
  dirty_count = 0;
  resetTimers();
  // Reset the flag since the scheduled render is now running.
  state.isRenderScheduled = false;

  const globalRerender = wasmInstance.shouldRerender();

  if (!globalRerender) {
    requestAnimationFrame(() => {
      wasmInstance.onEndCallback();
      wasmInstance.onEndCtxCallback();
    });
    return;
  }

  try {
    if (globalRerender) {
      currentPath = window.location.pathname;
      currentPath = "/";
      // const route_ptr = allocString(
      //   currentPath === "/" ? "/root" : `/root${currentPath}`,
      // );
      const route_ptr = allocString("/root");

      // const wasmstart = performance.now();
      wasmInstance.renderUI(route_ptr);
      // const wasmend = performance.now();
      // const wasmrenderTimeElement = document.getElementById("renderTime");
      // const wasmrenderTime = Math.round((wasmend - wasmstart) * 100) / 100;
      // wasmrenderTimeElement.textContent = wasmrenderTime;

      const has_dirty = wasmInstance.hasDirty();

      const count = wasmInstance.removalCount();

      for (let i = 0; i < count; i++) {
        const ptr = wasmInstance.getRemovalIdPtr(i);
        const len = wasmInstance.getRemovalIdLen(i);
        const id = readWasmString(ptr, len);

        const elements = document.querySelectorAll(`[id="${id}"]`);
        if (elements.length === 1) {
          animateExit(elements[0], i).catch((e) =>
            console.error("Error destroying node:", e),
          );
        }
      }

      if (document.getElementById("checkbox-row-0-col-0")) {
        console.log("REMOVING ---- Checkbox");
      }

      /* ───────── main removal loop ───────── */
      // for (let i = 0; i < count; i++) {
      //   const ptr = wasmInstance.getRemovedNode(i);
      //   const node_index = wasmInstance.getRemovedNodeIndex(i);
      //   const len = wasmInstance.getRemovedNodeLength(i);
      //   const id = readWasmString(ptr, len);
      //   console.log("Removing", id);
      //
      //   const elements = document.querySelectorAll(`[id="${id}"]`);
      //
      //   check: if (elements.length > 1) {
      //     // deduplicate logic
      //     for (let element of elements) {
      //       const target_child = element.parentElement.children[node_index];
      //       if (target_child && target_child.id === id) {
      //         // Added null check for safety
      //         domNodeRegistry.delete(id);
      //         element.remove();
      //         break check;
      //       }
      //     }
      //   } else if (elements.length === 1) {
      //     // FIX: REMOVED 'await'
      //     // We start the cleanup process but do not pause the render loop.
      //     // recurseDestroy will handle the animation and removal in the background.
      //     recurseDestroy(elements[0], false, i).catch((e) =>
      //       console.error("Error destroying node:", e),
      //     );
      //   }
      // }
      // wasmInstance.clearRemovedNodesretainingCapacity();
      wasmInstance.clearRemovalQueueRetainingCapacity();

      if (has_dirty) {
        // const start = performance.now();
        // const dirtyCount = wasmInstance.getDirtyNodeCount();
        // console.log("dirtyCount:", dirtyCount);
        // activeNodeIds = new Set();
        // const baseOffset = wasmInstance.getDirtyNode();
        // const dirtyRenderCmds = readAllRenderCommands(baseOffset, dirtyCount); // 6ms
        // document.getElementById("traversalTime").textContent =
        // performance.now() - start;
        //
        // for (let i = dirtyCount - 1; i >= 0; i--) {
        //   let element;
        //   const renderCmd = dirtyRenderCmds[i];
        //
        //   // --- Get the anchor (next sibling) using the REGISTRY ---
        //   // This logic is the same for new and updated nodes, so do it once.
        //   let anchor = null;
        //   const siblingPtr = wasmInstance.getNextSiblingPtr(renderCmd.nodePtr);
        //   if (siblingPtr > 0) {
        //     const siblingLen = wasmInstance.getNextSiblingLen(
        //       renderCmd.nodePtr,
        //     );
        //     const siblingId = readWasmString(siblingPtr, siblingLen);
        //
        //     // Use the FAST registry, not the SLOW DOM query
        //     anchor = domNodeRegistry.get(siblingId)?.domNode ?? null;
        //   }
        //
        //   const node = domNodeRegistry.get(renderCmd.id);
        //   if (node === undefined) {
        //     element = createElementByType(renderCmd);
        //     const parentIdPtr = wasmInstance.getNodeParentId(renderCmd.nodePtr);
        //     const parentIdLen = wasmInstance.getNodeParentIdLen(
        //       renderCmd.nodePtr,
        //     );
        //     const parentId = readWasmString(parentIdPtr, parentIdLen);
        //
        //     // Here, getElementById is probably fine, as the parent MUST exist in the DOM.
        //     // But for consistency, the registry is still better if parents are in it.
        //     const parent =
        //       domNodeRegistry.get(parentId)?.domNode ??
        //       document.getElementById(parentId);
        //
        //     if (!parent) continue; // Safety check
        //
        //     // Set up the element
        //     setupElement(element, renderCmd);
        //
        //     // Append to parent
        //     parent.insertBefore(element, anchor);
        //     if (renderCmd.elemType === COMPONENT_TYPES.HOOKS_CTX) {
        //       if (renderCmd.hooks.mountedId > 0) {
        //         wasmInstance.ctxHooksMountedCallback(renderCmd.hooks.mountedId);
        //       }
        //     } else if (renderCmd.elemType === COMPONENT_TYPES.HOOKS) {
        //       if (renderCmd.hooks.mountedId > 0) {
        //         const idPtr = allocString(renderCmd.id);
        //         wasmInstance.hooksMountedCallback(idPtr);
        //       }
        //       if (renderCmd.hooks.createdId > 0) {
        //         wasmInstance.hooksCreatedCallback(renderCmd.hooks.createdId);
        //       }
        //       if (renderCmd.hooks.updatedId > 0) {
        //         wasmInstance.hooksUpdatedCallback(renderCmd.hooks.updatedId);
        //       }
        //     }
        //   } else {
        //     element = node.domNode;
        //     updateElement(element, renderCmd);
        //
        //     // Check if move is needed
        //     if (element.nextSibling !== anchor) {
        //       // parent is simply element.parentElement, which is fast
        //       element.parentElement.insertBefore(element, anchor);
        //     }
        //   }
        // }
        //
        // // Added sections add the new elements, and styling
        // const addedCount = wasmInstance.getAddedNodeCount();
        // const addedOffset = wasmInstance.getAddedNode();
        // const addedRenderCmds = readAllRenderCommands(addedOffset, addedCount);
        // // const renderCmds = [];
        // // for (let i = 0; i < addedCount; i++) {
        // //   const ptr = wasmInstance.getAddedNode(i);
        // //   const renderCmd = readRenderCommand(ptr, layoutInfo);
        // //   renderCmds.push(renderCmd);
        // //   activeNodeIds.add(renderCmd.id);
        // // }
        //
        // if (addedCount > 0) {
        //   for (let i = addedCount - 1; i >= 0; i--) {
        //     const renderCmd = addedRenderCmds[i];
        //
        //     // --- Get the anchor (next sibling) using the REGISTRY ---
        //     // This logic is the same for new and updated nodes, so do it once.
        //     let anchor = null;
        //     const siblingPtr = wasmInstance.getNextSiblingPtr(
        //       renderCmd.nodePtr,
        //     );
        //     if (siblingPtr > 0) {
        //       const siblingLen = wasmInstance.getNextSiblingLen(
        //         renderCmd.nodePtr,
        //       );
        //       const siblingId = readWasmString(siblingPtr, siblingLen);
        //
        //       // Use the FAST registry, not the SLOW DOM query
        //       anchor = domNodeRegistry.get(siblingId)?.domNode ?? null;
        //     }
        //
        //     const parentIdPtr = wasmInstance.getNodeParentId(renderCmd.nodePtr);
        //     const parentIdLen = wasmInstance.getNodeParentIdLen(
        //       renderCmd.nodePtr,
        //     );
        //     const parentId = readWasmString(parentIdPtr, parentIdLen);
        //     const parent = document.getElementById(parentId);
        //
        //     const element = createElementByType(renderCmd);
        //
        //     if (!element) continue; // Skip if element creation failed
        //
        //     // Set up the element
        //     setupElement(element, renderCmd);
        //
        //     // Append to parent
        //     parent.insertBefore(element, anchor);
        //     if (renderCmd.elemType === COMPONENT_TYPES.HOOKS_CTX) {
        //       if (renderCmd.hooks.mountedId > 0) {
        //         wasmInstance.ctxHooksMountedCallback(renderCmd.hooks.mountedId);
        //       }
        //     } else if (renderCmd.elemType === COMPONENT_TYPES.HOOKS) {
        //       if (renderCmd.hooks.mountedId > 0) {
        //         const idPtr = allocString(renderCmd.id);
        //         wasmInstance.hooksMountedCallback(idPtr);
        //       }
        //       if (renderCmd.hooks.createdId > 0) {
        //         wasmInstance.hooksCreatedCallback(renderCmd.hooks.createdId);
        //       }
        //       if (renderCmd.hooks.updatedId > 0) {
        //         wasmInstance.hooksUpdatedCallback(renderCmd.hooks.updatedId);
        //       }
        //     }
        //   }
        // }

        // const start = performance.now();
        tree_node = wasmInstance.getRenderTreePtr();
        const rootUINode = wasmInstance.getRenderUINodeRootPtr();

        activeNodeIds = new Set();

        // const fragment = document.createDocumentFragment();
        const traversesstart = performance.now();
        root = document.getElementById("contents");
        traverseUINodes(root, rootUINode);
        const traverseTime = performance.now() - traversesstart;
        // After traversal

        // console.log("traverseUINodes:", traverseTime);
        // console.log("readUINode:", t1);
        // console.log("getUINodeNextSibling:", t2);
        // console.log("getElementById:", t3);
        // console.log("insertBefore:", t4);
        // console.log("setupElement:", t5);
        // console.log("createElementByType:", t6);
        // console.log("push:", t7);
        // console.log("cacheHits:", cacheHits);
        // console.log("cacheMisses:", cacheMisses);
        // console.log("dirty_count:", dirty_count);
        // console.log("readtime:", readtime);
        // console.log("tStyle:", tStyle);
        // console.log("tRegistry:", tRegistry);

        state.initial_render = false;
        callDestroyFncs();
        removeInactiveNodes();
        wasmInstance.markCurrentTreeNotDirty();
        wasmInstance.resetRerender();
        wasmInstance.registerAllListenerCallbacks();

        requestAnimationFrame(() => {
          hooksMounted.forEach((value, key) => {
            wasmInstance.hooksMountedCallback(key);
            hooksMounted.delete(key);
          });
          hooksMountedCtx.forEach((value, key) => {
            wasmInstance.hooksMountedCallbackCtx(key);
            hooksMountedCtx.delete(key);
          });
          // wasmInstance.onMountCtxCallback();
          hooksCtxCreated.forEach((value, key) => {
            wasmInstance.callOnCreateNode(key);
            hooksCtxCreated.delete(key);
          });
        });

        // requestAnimationFrame(wasmInstance.onEndCallback);

        // requestAnimationFrame(wasmInstance.cleanUp);
        // wasmInstance.onEndCallback();
      } else {
        // const count = wasmInstance.getRemovedNodeCount();
        // /* ───────── main removal loop ───────── */
        // for (let i = 0; i < count; i++) {
        //   const ptr = wasmInstance.getRemovedNode(i);
        //   const len = wasmInstance.getRemovedNodeLength(i);
        //   const id = readWasmString(ptr, len);
        //   // console.log(id);
        //
        //   const rec = domNodeRegistry.get(id);
        //   if (!rec) continue; // already gone
        //
        //   const el = rec.domNode;
        //   if (isLayout(el)) continue; // never delete a layout root itself
        //
        //   stripNonLayout(el); // delete everything *except* layouts
        //   wasmInstance.clearRemovedNodesretainingCapacity();
        // }
        //
        // wasmInstance.resetRerender();
      }
    } else {
      // This implies grainRerender is true
      console.log("Grain Rerender");
    }
    requestAnimationFrame(() => {
      requestAnimationFrame(() => {
        // const end = performance.now();
        // const renderTimeElement = document.getElementById("totalRenderTime");
        // const renderTime = Math.round((end - start) * 100) / 100;
        // renderTimeElement.textContent = renderTime;

        wasmInstance.onEndCallback();
        wasmInstance.onEndCtxCallback();
      });
    });
  } catch (error) {
    console.error("An error occurred during the render cycle:", error);
  }
}

// function renderLoop() {
//   const globalRerender = wasmInstance.shouldRerender();
//   const grainRerender = wasmInstance.grainRerender();
//   try {
//     if (globalRerender) {
//       console.log("attempting to rerender");
//       currentPath = window.location.pathname;
//       if (currentPath === "/") {
//         route_ptr = allocString("/root");
//       } else {
//         route_ptr = allocString(currentPath);
//       }
//       wasmInstance.renderUI(route_ptr);
//       tree_node = wasmInstance.getRenderTreePtr();
//       activeNodeIds = new Set();
//       traverse(root, tree_node, layoutInfo);
//       state.initial_render = false;
//       wasmInstance.pendingClassesToAdd();
//       wasmInstance.pendingClassesToRemove();
//       callDestroyFncs();
//       removeInactiveNodes();
//       wasmInstance.resetRerender();
//       requestAnimationFrame(wasmInstance.cleanUp);
//     } else if (grainRerender) {
//       console.log("Grain Rerender");
//       tree_node = wasmInstance.getRenderTreePtr();
//       activeNodeIds = new Set();
//       traverse(root, tree_node, layoutInfo);
//       wasmInstance.pendingClassesToAdd();
//       wasmInstance.pendingClassesToRemove();
//       callDestroyFncs();
//       removeInactiveNodes();
//       wasmInstance.resetGrainRerender();
//     }
//     requestAnimationFrame(renderLoop);
//   } catch (error) {
//     console.error("Render loop error:", error);
//     // Optionally, implement error recovery or loop stopping mechanism
//   }
// }

export function callDestroyFncs() {
  // Remove any nodes that aren't active in this render
  domNodeRegistry.forEach((node, nodeId) => {
    if (!activeNodeIds.has(nodeId)) {
      if (hooksDestroyCtx.get(node.hash)) {
        wasmInstance.hooksMountedCallbackCtx(node.hash);
        hooksDestroyCtx.delete(node.hash);
      }
    }
  });
}

function removeNodeWithExitAnimation(domNode, nodeId, animationName) {
  // Wait for animation to complete before removing from DOM
  domNode.addEventListener("animationend", function handler(e) {
    if (e.animationName === animationName) {
      // Only remove if it was the fadeOut animation that ended
      domNode.removeEventListener("animationend", handler);
      // domNode.classList.remove("fade-out");
      domNode.parentNode.removeChild(domNode);
      domNodeRegistry.delete(nodeId);
      pureNodeRegistry.delete(nodeId);
    }
  });
  return;
}

function getDepth(el) {
  let d = 0;
  while (el.parentElement) {
    d++;
    el = el.parentElement;
  }
  return d;
}

function removeAnimatedNodeTree(el) {
  for (const child of el.children) {
    toRemove = removeByIdSwap(toRemove, child.id);
    removeAnimatedNodeTree(child);
  }
}

const removeByIdSwap = (arr, idToRemove) => {
  const idx = arr.findIndex((item) => item.nodeId === idToRemove);
  if (idx !== -1) {
    // Move the last element into the “hole” and pop
    arr[idx] = arr[arr.length - 1];
    arr.pop();
  }
  return arr;
};

let toRemove = [];
export function removeInactiveNodes() {
  // Remove any nodes that aren't active in this render
  toRemove = [];
  // domNodeRegistry.forEach((node, nodeId) => {
  //   // Potentially removed
  //   // const doesExist = wasmInstance.checkPotentialNode(node.node_ptr);
  //   // if (doesExist) {
  //   //   // console.log("Checking potential node", nodeId);
  //   //   const contains = document.querySelector(`#${nodeId}`);
  //   //   if (contains) {
  //   //     toRemove.push({ node, nodeId });
  //   //     domNodeRegistry.delete(nodeId);
  //   //     pureNodeRegistry.delete(nodeId);
  //   //     const eventData = eventHandlers.get(nodeId);
  //   //     if (eventData !== undefined) {
  //   //       for (const [eventType, handler] of Object.entries(eventData)) {
  //   //         const el = node.domNode;
  //   //         el.removeEventListener(eventType, handler);
  //   //         eventHandlers.delete(nodeId);
  //   //       }
  //   //     }
  //   //   }
  //   // }
  // });

  // 3) schedule each’s exit animation
  toRemove.forEach(({ node, nodeId }) => {
    const el = node.domNode;
    const exitClass = node.exitAnimationId;
    if (exitClass) {
      removeAnimatedNodeTree(el);
      console.log(toRemove.length);
      // listen → add class → on end remove
      const onEnd = (e) => {
        if (e.animationName === exitClass) {
          el.removeEventListener("animationend", onEnd);
          el.remove();
        }
      };
      el.addEventListener("animationend", onEnd);
      el.classList.add(exitClass);
    } else {
      // no animation, just yank it
      if (node.elementType === COMPONENT_TYPES.HOOKS) {
        const idPtr = allocString(nodeId);
        wasmInstance.hooksRemoveMountedKey(idPtr);
      }
      el.remove();
      // domNodeRegistry.delete(nodeId);
    }
  });
}

// export function removeRouteSpecificNodes() {
//   const path = window.location.pathname;
//   const segments = path.split("/").filter(Boolean); // Remove empty strings
//   const parentPath = "/" + segments.slice(0, -1).join("/");
//   const fullLayoutPath = `layout-${parentPath}`;
//   // Remove any nodes that aren't active in this render
//   toRemove = [];
//   domNodeRegistry.forEach((node, nodeId) => {
//     if (nodeId !== fullLayoutPath) {
//       toRemove.push({ node, nodeId });
//       domNodeRegistry.delete(nodeId);
//       pureNodeRegistry.delete(nodeId);
//     }
//   });
//
//   // 3) schedule each’s exit animation
//   toRemove.forEach(({ node, nodeId }) => {
//     const el = node.domNode;
//     const exitClass = node.exitAnimationId;
//     if (exitClass) {
//       removeAnimatedNodeTree(el);
//       console.log(toRemove.length);
//       // listen → add class → on end remove
//       const onEnd = (e) => {
//         if (e.animationName === exitClass) {
//           el.removeEventListener("animationend", onEnd);
//           el.remove();
//         }
//       };
//       el.addEventListener("animationend", onEnd);
//       el.classList.add(exitClass);
//     } else {
//       // no animation, just yank it
//       el.remove();
//       // domNodeRegistry.delete(nodeId);
//     }
//   });
// }

// Function to read a RenderCommand from memory
// Essentially we are just reading out a giant memory file and using alignment
// and ptr to access the data then we convert the values to readable js values
export let view;
export function readRenderCommand(offset, layout) {
  const view = new DataView(
    wasmInstance.memory.buffer,
    offset,
    layoutInfo.renderCommandSize,
  );

  let css = "";
  let keyFrames = "";
  let styleId = "";
  let id = "";
  let btnId = 0;
  let hoverCss = "";
  let focusCss = "";
  let focusWithinCss = "";
  let tooltipCss = "";
  let tooltipTitle = "";
  let exitAnimationId = null;

  const elemType = view.getUint8(layoutInfo.elemTypeOffset);

  const nodePtr = view.getUint32(layoutInfo.nodePtrOffset, true);
  const isDirty = wasmInstance.getDirtyValue(nodePtr);

  // For text, you need to handle the string slice differently
  const textPtr = view.getUint32(layoutInfo.textPtrOffset, true);
  const textLen = view.getUint32(layoutInfo.textPtrOffset + 4, true);

  const hrefPtr = view.getUint32(layoutInfo.hrefPtrOffset, true);
  const hrefLen = view.getUint32(layoutInfo.hrefPtrOffset + 4, true);
  const hasChildren = view.getUint8(layoutInfo.hasChildrenOffset, true);

  const idPtr = view.getUint32(layoutInfo.idPtrOffset, true);
  const idLen = view.getUint32(layoutInfo.idPtrOffset + 4, true);
  id = idPtr ? readWasmString(idPtr, idLen) : "";
  const index = view.getUint32(layoutInfo.indexOffset, true);
  let hooks = {};
  let changedStyle = 0;
  let changedProps = 0;

  if (isDirty) {
    changedStyle = view.getUint8(layoutInfo.styleChangedOffset, true);
    changedProps = view.getUint8(layoutInfo.propsChangedOffset, true);
    hooks = {
      createdId: view.getUint32(layoutInfo.hooksOffset, true),
      mountedId: view.getUint32(layoutInfo.hooksOffset + 4, true),
      updatedId: view.getUint32(layoutInfo.hooksOffset + 8, true),
      destroyId: view.getUint32(layoutInfo.hooksOffset + 12, true),
    };

    // if (cssStylePtr !== 0) {
    // 1. Get the offset of the classname's POINTER from our new layout object.
    const classnamePtrOffset = layoutInfo.classnamePtrOffset;

    // 2. Read the actual pointer value from the RenderCommand struct.
    const classnamePtr = view.getUint32(classnamePtrOffset, true);

    // 3. If the pointer is not null, read the length and then the string.
    if (classnamePtr) {
      // The length is ALWAYS 4 bytes after the pointer for a slice.
      const classnameLen = view.getUint32(classnamePtrOffset + 4, true);

      const classname = readWasmString(classnamePtr, classnameLen);
      styleId = classname;
    }
    // }
    // if (wasmInstance.hasEctClasses(nodePtr)) {
    //   wasmInstance.addEctClasses(nodePtr);
    // }
  }

  const stateType = view.getUint32(layoutInfo.renderTypeOffset, true);

  const props = {
    css,
    hoverCss,
    focusCss,
    focusWithinCss,
    btnId,
    keyFrames,
    textPtr,
    textLen,
    tooltipCss,
    tooltipTitle,
    hasChildren,
    hrefPtr,
    hrefLen,
  };

  return {
    elemType,
    props,
    id,
    index,
    hooks,
    nodePtr,
    exitAnimationId,
    styleId,
    isDirty,
    stateType,
    changedStyle,
    changedProps,
    // ... other fields
  };
}
let memoryView = null;
let memoryBuffer = null;
function getMemoryView() {
  // Only recreate if buffer changed (after memory growth)
  if (memoryBuffer !== wasmInstance.memory.buffer) {
    memoryBuffer = wasmInstance.memory.buffer;
    memoryView = new DataView(memoryBuffer);
  }
  return memoryView;
}

export function readUINode(offset) {
  const view = getMemoryView();

  const isDirty = view.getUint8(offset + UINodelayoutInfo.dirtyOffset);

  // Fast path for non-dirty nodes
  if (!isDirty) {
    const hash = Number(
      view.getUint32(offset + UINodelayoutInfo.hashOffset, true),
    );
    const idPtr = view.getUint32(offset + UINodelayoutInfo.idPtrOffset, true);
    const idLen = view.getUint32(
      offset + UINodelayoutInfo.idPtrOffset + 4,
      true,
    );
    const id = idPtr ? readWasmString(idPtr, idLen) : "";
    // const id = Number(
    //   view.getUint32(offset + UINodelayoutInfo.hashOffset, true),
    // );
    // const hash = id;
    return {
      id,
      isDirty: false,
      // Minimal fields - rest undefined/default
      elemType: 0,
      index: 0,
      textPtr: 0,
      textLen: 0,
      hrefPtr: 0,
      hrefLen: 0,
      offset,
      styleId: "",
      changedStyle: 0,
      changedProps: 0,
      hooks: {},
      hash,
    };
  }

  dirty_count += 1;

  // Full read for dirty nodes
  const elemType = view.getUint8(offset + UINodelayoutInfo.elemTypeOffset);
  const index = view.getUint32(offset + UINodelayoutInfo.indexOffset, true);
  const idPtr = view.getUint32(offset + UINodelayoutInfo.idPtrOffset, true);
  const idLen = view.getUint32(offset + UINodelayoutInfo.idPtrOffset + 4, true);
  const id = idPtr ? readWasmString(idPtr, idLen) : "";
  const hash = Number(
    view.getUint32(offset + UINodelayoutInfo.hashOffset, true),
  );
  // const hash = id;
  // readtime += performance.now() - start;

  let textPtr = 0,
    textLen = 0;
  let hrefPtr = 0,
    hrefLen = 0;
  let hooks = {};

  if (
    elemType === COMPONENT_TYPES.TEXT ||
    elemType === COMPONENT_TYPES.LABEL ||
    elemType === COMPONENT_TYPES.HEADING ||
    elemType === COMPONENT_TYPES.ALLOC_TEXT ||
    elemType === COMPONENT_TYPES.HEADER ||
    elemType === COMPONENT_TYPES.TEXT_AREA ||
    elemType === COMPONENT_TYPES.TEXT_FIELD ||
    elemType === COMPONENT_TYPES.CODE ||
    elemType === COMPONENT_TYPES.SVG ||
    elemType === COMPONENT_TYPES.HTML_TEXT ||
    elemType === COMPONENT_TYPES.TEXT_AREA
  ) {
    textPtr = view.getUint32(offset + UINodelayoutInfo.textPtrOffset, true);
    textLen = view.getUint32(offset + UINodelayoutInfo.textPtrOffset + 4, true);
  }

  if (
    elemType === COMPONENT_TYPES.LINK ||
    elemType === COMPONENT_TYPES.REDIRECT_LINK ||
    elemType === COMPONENT_TYPES.EMBEDLINK ||
    elemType === COMPONENT_TYPES.EMBEDICON ||
    elemType === COMPONENT_TYPES.IMAGE ||
    elemType === COMPONENT_TYPES.GRAPHIC ||
    elemType === COMPONENT_TYPES.ICON
  ) {
    hrefPtr = view.getUint32(offset + UINodelayoutInfo.hrefPtrOffset, true);
    hrefLen = view.getUint32(offset + UINodelayoutInfo.hrefPtrOffset + 4, true);
  }

  if (
    elemType === COMPONENT_TYPES.HOOKS ||
    elemType === COMPONENT_TYPES.HOOKS_CTX
  ) {
    hooks = {
      createdId: view.getUint32(offset + UINodelayoutInfo.hooksOffset, true),
      mountedId: view.getUint32(
        offset + UINodelayoutInfo.hooksOffset + 4,
        true,
      ),
      updatedId: view.getUint32(
        offset + UINodelayoutInfo.hooksOffset + 8,
        true,
      ),
      destroyId: view.getUint32(
        offset + UINodelayoutInfo.hooksOffset + 12,
        true,
      ),
    };
  }

  const style_hash = view.getUint32(
    offset + UINodelayoutInfo.styleHashOffset,
    true,
  );

  const accessibility = view.getUint8(
    offset + UINodelayoutInfo.accessibilityOffset,
    true,
  );

  // In hot path
  let styleId = "";
  if (style_hash) {
    styleId = styleClassCache[style_hash]; // Direct property access
    if (styleId === undefined) {
      const classnamePtr = view.getUint32(
        offset + UINodelayoutInfo.classnamePtrOffset,
        true,
      );
      if (classnamePtr) {
        const classnameLen = view.getUint32(
          offset + UINodelayoutInfo.classnamePtrOffset + 4,
          true,
        );
        styleId = readWasmString(classnamePtr, classnameLen);
        styleClassCache[style_hash] = styleId;
      }
    }
  }

  return {
    id,
    elemType,
    index,
    textPtr,
    textLen,
    hrefPtr,
    hrefLen,
    offset,
    styleId,
    isDirty: true,
    changedStyle: view.getUint8(offset + UINodelayoutInfo.styleChangedOffset),
    changedProps: view.getUint8(offset + UINodelayoutInfo.propsChangedOffset),
    hooks,
    hash,
    accessibility,
  };
}
// ✅ Faster: Reuse decoder (2-3x faster)
const textDecoder = new TextDecoder();

export function readWasmString(ptr, len) {
  if (len === 0) return "";
  const bytes = new Uint8Array(wasmInstance.memory.buffer, ptr, len);
  return textDecoder.decode(bytes);
}
// export function readWasmString(ptr, len) {
//   const bytes = new Uint8Array(wasmInstance.memory.buffer, ptr, len);
//   return new TextDecoder().decode(bytes);
// }

// Check if memory is growing over time
// Get total WASM memory size

function getWasmMemoryUsage() {
  const memory = wasmInstance.memory;
  return memory.buffer.byteLength;
}

// Monitor memory growth
let lastMemorySize = 0;
export function checkMemoryGrowth() {
  const currentSize = getWasmMemoryUsage();
  const pages = currentSize / (64 * 1024); // WASM pages are 64KB

  console.log(`Total memory: ${currentSize / 1024 / 1024} MB (${pages} pages)`);

  if (currentSize > lastMemorySize) {
    console.log(`Memory grew by ${(currentSize - lastMemorySize) / 1024} KB`);
  }
  lastMemorySize = currentSize;
  return pages;
}
