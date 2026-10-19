/**
 * Additional WASM-JavaScript Bindings
 * Matching the extern declarations from the Zig side
 */

import { eventStorage } from "./playground_maps.js";
import { WasmObjectBuilder, wasmInstance } from "./playground_wasi.js";
import { readWasmString, allocString } from "./playground_obj.js";

// ============================================================================
// Storage for handles and state
// ============================================================================

const fileInputCallbacks = new Map();
const websocketHandles = new Map();
const canvasContexts = new Map();
const audioElements = new Map();
const resizeObservers = new Map();
const mutationObservers = new Map();
const fetchAbortControllers = new Map();
const idbDatabases = new Map();
const animationFrameCallbacks = new Map();

let nextWebsocketHandle = 1;
let nextCanvasHandle = 1;
let nextAudioHandle = 1;
let nextResizeObserverHandle = 1;
let nextMutationObserverHandle = 1;
let nextFetchHandle = 1;
let nextIdbHandle = 1;

function requireWasm() {
  if (!wasmInstance) {
    console.error("WASM instance not initialized");
    return false;
  }
  return true;
}

// ============================================================================
// FILE HANDLING
// ============================================================================

export const fileBindings = {
  triggerFileInputWasm: (idPtr, idLen) => {
    if (!requireWasm()) return;
    const id = readWasmString(idPtr, idLen);
    const input = document.getElementById(id);
    if (input) {
      input.click();
    }
  },

  getFileCountWasm: (eventId) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.target?.files) return 0;
    return event.target.files.length;
  },

  getFileInfoWasm: (eventId, fileIndex) => {
    const id = eventId >>> 0;
    const event = eventStorage[id];

    const file = event.target.files[fileIndex];
    const info = {
      name: file.name,
      size: file.size,
      type: file.type,
      // lastModified: file.lastModified,
    };
    const builder = new WasmObjectBuilder(wasmInstance, wasmInstance.memory);
    const handle = builder.passObject(info);
    return handle;
  },

  readFileAsTextWasm: (eventId, fileIndex, callbackId) => {
    const id = eventId >>> 0;
    const callback = callbackId >>> 0;
    const event = eventStorage[id];
    const file = event?.target?.files?.[fileIndex];
    if (!file) {
      // wasmInstance.resumeCallback(callbackId, allocString(""));
      return null;
    }

    const reader = new FileReader();
    reader.onload = () => {
      if (!requireWasm()) return;
      const fileData = {
        contents: reader.result,
      };
      const builder = new WasmObjectBuilder(wasmInstance, wasmInstance.memory);
      const handle = builder.passObject(fileData);
      wasmInstance.readObject(callback, handle);
    };
    reader.onerror = () => {
      // wasmInstance.resumeCallback(callbackId, allocString(""));
    };
    reader.readAsText(file);
  },

  readFileAsBase64Wasm: (eventId, fileIndex, callbackId) => {
    const event = window._eventStorage?.[eventId];
    const file = event?.target?.files?.[fileIndex];
    if (!file) {
      wasmInstance.resumeCallback(callbackId, allocString(""));
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      // Remove data URL prefix to get just base64
      const base64 = reader.result.split(",")[1] || "";
      const ptr = allocString(base64);
      wasmInstance.resumeCallback(callbackId, ptr);
    };
    reader.onerror = () => {
      wasmInstance.resumeCallback(callbackId, allocString(""));
    };
    reader.readAsDataURL(file);
  },

  readFileAsArrayBufferWasm: (eventId, fileIndex, callbackId) => {
    const event = window._eventStorage?.[eventId];
    const file = event?.target?.files?.[fileIndex];
    if (!file) {
      wasmInstance.resumeCallback(callbackId, 0);
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      const buffer = new Uint8Array(reader.result);
      const ptr = wasmInstance.allocate(buffer.length);
      new Uint8Array(wasmInstance.memory.buffer, ptr, buffer.length).set(
        buffer,
      );
      wasmInstance.resumeCallback(callbackId, ptr);
    };
    reader.onerror = () => {
      wasmInstance.resumeCallback(callbackId, 0);
    };
    reader.readAsArrayBuffer(file);
  },

  downloadFileWasm: (namePtr, nameLen, dataPtr, dataLen, mimePtr, mimeLen) => {
    if (!requireWasm()) return;
    const name = readWasmString(namePtr, nameLen);
    const data = readWasmString(dataPtr, dataLen);
    const mime = readWasmString(mimePtr, mimeLen);

    const blob = new Blob([data], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
    URL.revokeObjectURL(url);
  },

  downloadBinaryFileWasm: (
    namePtr,
    nameLen,
    dataPtr,
    dataLen,
    mimePtr,
    mimeLen,
  ) => {
    if (!requireWasm()) return;
    const name = readWasmString(namePtr, nameLen);
    const mime = readWasmString(mimePtr, mimeLen);
    const data = new Uint8Array(wasmInstance.memory.buffer, dataPtr, dataLen);

    const blob = new Blob([data], { type: mime });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = name;
    a.click();
    URL.revokeObjectURL(url);
  },

  // 1. Create a Blob URL (e.g., "blob:http://localhost/...")
  // Returns a pointer to the string that you can use as an <img> src
  createObjectURLWasm: (eventId, fileIndex) => {
    if (!requireWasm()) return 0;

    // Normalize event ID and lookup
    const id = eventId >>> 0;
    const event = eventStorage[id];
    const file = event?.target?.files?.[fileIndex];

    if (!file) return 0; // Return null pointer if file not found

    const url = URL.createObjectURL(file);

    // Allocates the string in WASM memory and returns the pointer.
    // NOTE: This assumes `allocString` is available in your scope
    // (as implied by your usage in readFileAsBase64Wasm)
    return allocString(url);
  },

  // 2. Revoke the Blob URL to free up browser memory
  // Should be called when the image is unloaded or component is destroyed
  revokeObjectURLWasm: (urlPtr, urlLen) => {
    if (!requireWasm()) return;

    const url = readWasmString(urlPtr, urlLen);
    if (url) {
      URL.revokeObjectURL(url);
    }
  },
  /**
   * Reads a file and returns the full Data URL string (e.g., "data:image/png;base64,...").
   * Useful for directly setting an <img> src attribute without needing to modify the string in WASM.
   * * @param eventId The stored event ID.
   * @param fileIndex Index of the file in the event's file list.
   * @param callbackId The WASM callback ID to resume execution.
   */
  readFileAsDataURLWasm: (eventId, fileIndex, callbackId) => {
    if (!requireWasm()) return;
    const event = eventStorage[eventId];
    const file = event?.target?.files?.[fileIndex];

    if (!file) {
      wasmInstance.resumeCallback(callbackId, allocString(""));
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      if (!requireWasm()) return;
      // reader.result contains the full Data URL string
      const dataURL = reader.result;
      const ptr = allocString(dataURL);
      wasmInstance.resumeCallback(callbackId, ptr);
    };
    reader.onerror = () => {
      // Error handling: return an empty string or null pointer
      wasmInstance.resumeCallback(callbackId, allocString(""));
    };
    reader.readAsDataURL(file); // Reads file and returns full Data URL string
  },

  /**
   * Reads a file and provides a progress update callback during reading.
   * * @param eventId The stored event ID.
   * @param fileIndex Index of the file.
   * @param onloadCallbackId Callback for when the file is finished reading.
   * @param onprogressCallbackId Callback for progress updates (called multiple times).
   */
  readFileWithProgressWasm: (
    eventId,
    fileIndex,
    onloadCallbackId,
    onprogressCallbackId,
  ) => {
    if (!requireWasm()) return;
    const event = eventStorage[eventId];
    const file = event?.target?.files?.[fileIndex];

    if (!file) {
      wasmInstance.resumeCallback(onloadCallbackId, 0);
      return;
    }

    const reader = new FileReader();

    // 1. onload event (Same as readFileAsArrayBufferWasm, returning the data)
    reader.onload = () => {
      if (!requireWasm()) return;
      const buffer = new Uint8Array(reader.result);
      const ptr = wasmInstance.allocate(buffer.length);
      new Uint8Array(wasmInstance.memory.buffer, ptr, buffer.length).set(
        buffer,
      );
      // Resume WASM execution with the allocated data pointer
      wasmInstance.resumeCallback(onloadCallbackId, ptr);
    };

    // 2. onprogress event
    reader.onprogress = (e) => {
      if (!requireWasm() || !e.lengthComputable) return;

      // Pass a data object containing total, loaded, and percentage
      const progressInfo = {
        loaded: e.loaded,
        total: e.total,
        percent: Math.round((e.loaded / e.total) * 100),
      };

      const builder = new WasmObjectBuilder(wasmInstance, wasmInstance.memory);
      const handle = builder.passObject(progressInfo);

      // This assumes your WASM side can handle a separate, non-resuming callback (readObject)
      wasmInstance.readObject(onprogressCallbackId, handle);
    };

    reader.onerror = () => {
      // Resume onload callback with error/null data
      wasmInstance.resumeCallback(onloadCallbackId, 0);
    };

    // We use readAsArrayBuffer since the progress logic is typically used for large binary files
    reader.readAsArrayBuffer(file);
  },
};

// ============================================================================
// DRAG & DROP
// ============================================================================

export const dragDropBindings = {
  getDragDataWasm: (eventId, formatPtr, formatLen) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.dataTransfer) return allocString("");

    const format = readWasmString(formatPtr, formatLen);
    const data = event.dataTransfer.getData(format);
    return allocString(data);
  },

  setDragDataWasm: (eventId, formatPtr, formatLen, dataPtr, dataLen) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.dataTransfer) return;

    const format = readWasmString(formatPtr, formatLen);
    const data = readWasmString(dataPtr, dataLen);
    event.dataTransfer.setData(format, data);
  },

  setDragEffectWasm: (eventId, effect) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.dataTransfer) return;

    const effects = ["none", "copy", "move", "link"];
    event.dataTransfer.dropEffect = effects[effect] || "none";
  },

  setDragEffectAllowedWasm: (eventId, effect) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.dataTransfer) return;

    const effects = [
      "none",
      "copy",
      "move",
      "link",
      "copyMove",
      "copyLink",
      "linkMove",
      "all",
    ];
    event.dataTransfer.effectAllowed = effects[effect] || "none";
  },

  getDroppedFilesCountWasm: (eventId) => {
    const event = window._eventStorage?.[eventId];
    if (!event?.dataTransfer?.files) return 0;
    return event.dataTransfer.files.length;
  },

  getDroppedFileInfoWasm: (eventId, fileIndex) => {
    const event = window._eventStorage?.[eventId];
    const file = event?.dataTransfer?.files?.[fileIndex];
    if (!file) return allocString("{}");

    const info = {
      name: file.name,
      size: file.size,
      type: file.type,
      lastModified: file.lastModified,
    };
    return allocString(JSON.stringify(info));
  },

  readDroppedFileAsTextWasm: (eventId, fileIndex, callbackId) => {
    const event = window._eventStorage?.[eventId];
    const file = event?.dataTransfer?.files?.[fileIndex];
    if (!file) {
      wasmInstance.resumeCallback(callbackId, allocString(""));
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      const ptr = allocString(reader.result);
      wasmInstance.resumeCallback(callbackId, ptr);
    };
    reader.onerror = () => {
      wasmInstance.resumeCallback(callbackId, allocString(""));
    };
    reader.readAsText(file);
  },

  readDroppedFileAsBase64Wasm: (eventId, fileIndex, callbackId) => {
    const event = window._eventStorage?.[eventId];
    const file = event?.dataTransfer?.files?.[fileIndex];
    if (!file) {
      wasmInstance.resumeCallback(callbackId, allocString(""));
      return;
    }

    const reader = new FileReader();
    reader.onload = () => {
      const base64 = reader.result.split(",")[1] || "";
      const ptr = allocString(base64);
      wasmInstance.resumeCallback(callbackId, ptr);
    };
    reader.onerror = () => {
      wasmInstance.resumeCallback(callbackId, allocString(""));
    };
    reader.readAsDataURL(file);
  },
};

// ============================================================================
// WEBSOCKET
// ============================================================================

export const websocketBindings = {
  websocketConnectWasm: (
    urlPtr,
    urlLen,
    openCallbackId,
    messageCallbackId,
    closeCallbackId,
    errorCallbackId,
  ) => {
    if (!requireWasm()) return 0;

    const url = readWasmString(urlPtr, urlLen);
    const handle = nextWebsocketHandle++;

    try {
      const ws = new WebSocket(url);

      ws.onopen = () => {
        wasmInstance.callbackCtx(openCallbackId, handle);
      };

      ws.onmessage = (event) => {
        const ptr = allocString(event.data);
        wasmInstance.callbackCtx(messageCallbackId, ptr);
      };

      ws.onclose = (event) => {
        const info = {
          code: event.code,
          reason: event.reason,
          wasClean: event.wasClean,
        };
        const ptr = allocString(JSON.stringify(info));
        wasmInstance.callbackCtx(closeCallbackId, ptr);
        websocketHandles.delete(handle);
      };

      ws.onerror = () => {
        wasmInstance.callbackCtx(errorCallbackId, handle);
      };

      websocketHandles.set(handle, ws);
      return handle;
    } catch (e) {
      console.error("WebSocket connection failed:", e);
      return 0;
    }
  },

  websocketSendWasm: (handle, dataPtr, dataLen) => {
    const ws = websocketHandles.get(handle);
    if (!ws || ws.readyState !== WebSocket.OPEN) return 0;

    const data = readWasmString(dataPtr, dataLen);
    try {
      ws.send(data);
      return 1;
    } catch (e) {
      return 0;
    }
  },

  websocketSendBinaryWasm: (handle, dataPtr, dataLen) => {
    const ws = websocketHandles.get(handle);
    if (!ws || ws.readyState !== WebSocket.OPEN) return 0;

    const data = new Uint8Array(wasmInstance.memory.buffer, dataPtr, dataLen);
    try {
      ws.send(data);
      return 1;
    } catch (e) {
      return 0;
    }
  },

  websocketCloseWasm: (handle, code, reasonPtr, reasonLen) => {
    const ws = websocketHandles.get(handle);
    if (!ws) return;

    const reason = readWasmString(reasonPtr, reasonLen);
    ws.close(code, reason);
  },

  websocketStateWasm: (handle) => {
    const ws = websocketHandles.get(handle);
    if (!ws) return -1;
    return ws.readyState;
  },

  websocketBufferedAmountWasm: (handle) => {
    const ws = websocketHandles.get(handle);
    if (!ws) return 0;
    return ws.bufferedAmount;
  },
};

// ============================================================================
// SESSION STORAGE
// ============================================================================

export const sessionStorageBindings = {
  setSessionStorageStringWasm: (keyPtr, keyLen, valuePtr, valueLen) => {
    const key = readWasmString(keyPtr, keyLen);
    const value = readWasmString(valuePtr, valueLen);
    sessionStorage.setItem(key, value);
  },

  getSessionStorageStringWasm: (keyPtr, keyLen) => {
    const key = readWasmString(keyPtr, keyLen);
    const value = sessionStorage.getItem(key);
    return allocString(value || "");
  },

  setSessionStorageNumberWasm: (keyPtr, keyLen, value) => {
    const key = readWasmString(keyPtr, keyLen);
    sessionStorage.setItem(key, value.toString());
  },

  getSessionStorageNumberWasm: (keyPtr, keyLen) => {
    const key = readWasmString(keyPtr, keyLen);
    const value = sessionStorage.getItem(key);
    return value ? parseFloat(value) : 0;
  },

  removeSessionStorageWasm: (keyPtr, keyLen) => {
    const key = readWasmString(keyPtr, keyLen);
    sessionStorage.removeItem(key);
  },

  clearSessionStorageWasm: () => {
    sessionStorage.clear();
  },

  sessionStorageLengthWasm: () => {
    return sessionStorage.length;
  },

  sessionStorageKeyWasm: (index) => {
    const key = sessionStorage.key(index);
    return allocString(key || "");
  },
};

// ============================================================================
// CANVAS 2D
// ============================================================================

export const canvasBindings = {
  getCanvas2dContextWasm: (idPtr, idLen) => {
    const id = readWasmString(idPtr, idLen);
    const canvas = document.getElementById(id);
    if (!canvas) return 0;

    const ctx = canvas.getContext("2d");
    if (!ctx) return 0;

    const handle = nextCanvasHandle++;
    canvasContexts.set(handle, ctx);
    return handle;
  },

  canvasSetFillStyleWasm: (handle, colorPtr, colorLen) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.fillStyle = readWasmString(colorPtr, colorLen);
  },

  canvasSetStrokeStyleWasm: (handle, colorPtr, colorLen) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.strokeStyle = readWasmString(colorPtr, colorLen);
  },

  canvasSetLineWidthWasm: (handle, width) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.lineWidth = width;
  },

  canvasSetLineCapWasm: (handle, cap) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const caps = ["butt", "round", "square"];
    ctx.lineCap = caps[cap] || "butt";
  },

  canvasSetLineJoinWasm: (handle, join) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const joins = ["miter", "round", "bevel"];
    ctx.lineJoin = joins[join] || "miter";
  },

  canvasFillRectWasm: (handle, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.fillRect(x, y, w, h);
  },

  canvasStrokeRectWasm: (handle, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.strokeRect(x, y, w, h);
  },

  canvasClearRectWasm: (handle, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.clearRect(x, y, w, h);
  },

  canvasBeginPathWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.beginPath();
  },

  canvasClosePathWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.closePath();
  },

  canvasMoveToWasm: (handle, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.moveTo(x, y);
  },

  canvasLineToWasm: (handle, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.lineTo(x, y);
  },

  canvasArcWasm: (
    handle,
    x,
    y,
    radius,
    startAngle,
    endAngle,
    counterclockwise,
  ) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.arc(x, y, radius, startAngle, endAngle, counterclockwise);
  },

  canvasArcToWasm: (handle, x1, y1, x2, y2, radius) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.arcTo(x1, y1, x2, y2, radius);
  },

  canvasBezierCurveToWasm: (handle, cp1x, cp1y, cp2x, cp2y, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, x, y);
  },

  canvasQuadraticCurveToWasm: (handle, cpx, cpy, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.quadraticCurveTo(cpx, cpy, x, y);
  },

  canvasFillWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.fill();
  },

  canvasStrokeWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.stroke();
  },

  canvasClipWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.clip();
  },

  canvasRectWasm: (handle, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.rect(x, y, w, h);
  },

  canvasEllipseWasm: (
    handle,
    x,
    y,
    radiusX,
    radiusY,
    rotation,
    startAngle,
    endAngle,
    counterclockwise,
  ) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.ellipse(
      x,
      y,
      radiusX,
      radiusY,
      rotation,
      startAngle,
      endAngle,
      counterclockwise,
    );
  },

  canvasFillTextWasm: (handle, textPtr, textLen, x, y, maxWidth) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const text = readWasmString(textPtr, textLen);
    if (maxWidth > 0) {
      ctx.fillText(text, x, y, maxWidth);
    } else {
      ctx.fillText(text, x, y);
    }
  },

  canvasStrokeTextWasm: (handle, textPtr, textLen, x, y, maxWidth) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const text = readWasmString(textPtr, textLen);
    if (maxWidth > 0) {
      ctx.strokeText(text, x, y, maxWidth);
    } else {
      ctx.strokeText(text, x, y);
    }
  },

  canvasSetFontWasm: (handle, fontPtr, fontLen) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.font = readWasmString(fontPtr, fontLen);
  },

  canvasSetTextAlignWasm: (handle, align) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const aligns = ["start", "end", "left", "right", "center"];
    ctx.textAlign = aligns[align] || "start";
  },

  canvasSetTextBaselineWasm: (handle, baseline) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const baselines = [
      "alphabetic",
      "top",
      "hanging",
      "middle",
      "ideographic",
      "bottom",
    ];
    ctx.textBaseline = baselines[baseline] || "alphabetic";
  },

  canvasMeasureTextWasm: (handle, textPtr, textLen) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return 0;
    const text = readWasmString(textPtr, textLen);
    return ctx.measureText(text).width;
  },

  canvasDrawImageWasm: (handle, imgIdPtr, imgIdLen, dx, dy) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const imgId = readWasmString(imgIdPtr, imgIdLen);
    const img = document.getElementById(imgId);
    if (img) {
      ctx.drawImage(img, dx, dy);
    }
  },

  canvasDrawImageScaledWasm: (handle, imgIdPtr, imgIdLen, dx, dy, dw, dh) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const imgId = readWasmString(imgIdPtr, imgIdLen);
    const img = document.getElementById(imgId);
    if (img) {
      ctx.drawImage(img, dx, dy, dw, dh);
    }
  },

  canvasDrawImageSlicedWasm: (
    handle,
    imgIdPtr,
    imgIdLen,
    sx,
    sy,
    sw,
    sh,
    dx,
    dy,
    dw,
    dh,
  ) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const imgId = readWasmString(imgIdPtr, imgIdLen);
    const img = document.getElementById(imgId);
    if (img) {
      ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
    }
  },

  canvasSaveWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.save();
  },

  canvasRestoreWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.restore();
  },

  canvasTranslateWasm: (handle, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.translate(x, y);
  },

  canvasRotateWasm: (handle, angle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.rotate(angle);
  },

  canvasScaleWasm: (handle, x, y) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.scale(x, y);
  },

  canvasSetTransformWasm: (handle, a, b, c, d, e, f) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.setTransform(a, b, c, d, e, f);
  },

  canvasResetTransformWasm: (handle) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.resetTransform();
  },

  canvasSetGlobalAlphaWasm: (handle, alpha) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.globalAlpha = alpha;
  },

  canvasSetGlobalCompositeOperationWasm: (handle, op) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    const ops = [
      "source-over",
      "source-in",
      "source-out",
      "source-atop",
      "destination-over",
      "destination-in",
      "destination-out",
      "destination-atop",
      "lighter",
      "copy",
      "xor",
      "multiply",
      "screen",
      "overlay",
      "darken",
      "lighten",
      "color-dodge",
      "color-burn",
      "hard-light",
      "soft-light",
      "difference",
      "exclusion",
      "hue",
      "saturation",
      "color",
      "luminosity",
    ];
    ctx.globalCompositeOperation = ops[op] || "source-over";
  },

  canvasToDataUrlWasm: (idPtr, idLen, typePtr, typeLen, quality) => {
    const id = readWasmString(idPtr, idLen);
    const type = readWasmString(typePtr, typeLen);
    const canvas = document.getElementById(id);
    if (!canvas) return allocString("");
    return allocString(canvas.toDataURL(type || "image/png", quality));
  },

  canvasGetImageDataWasm: (handle, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return 0;

    const imageData = ctx.getImageData(x, y, w, h);
    const ptr = wasmInstance.allocate(imageData.data.length);
    new Uint8Array(wasmInstance.memory.buffer, ptr, imageData.data.length).set(
      imageData.data,
    );
    return ptr;
  },

  canvasPutImageDataWasm: (handle, dataPtr, dataLen, x, y, w, h) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;

    const data = new Uint8ClampedArray(
      wasmInstance.memory.buffer,
      dataPtr,
      dataLen,
    );
    const imageData = new ImageData(data, w, h);
    ctx.putImageData(imageData, x, y);
  },

  canvasSetShadowWasm: (handle, colorPtr, colorLen, blur, offsetX, offsetY) => {
    const ctx = canvasContexts.get(handle);
    if (!ctx) return;
    ctx.shadowColor = readWasmString(colorPtr, colorLen);
    ctx.shadowBlur = blur;
    ctx.shadowOffsetX = offsetX;
    ctx.shadowOffsetY = offsetY;
  },

  destroyCanvasContextWasm: (handle) => {
    canvasContexts.delete(handle);
  },
};

// ============================================================================
// AUDIO
// ============================================================================

export const audioBindings = {
  createAudioElementWasm: (srcPtr, srcLen) => {
    const src = readWasmString(srcPtr, srcLen);
    const audio = new Audio(src);
    const handle = nextAudioHandle++;
    audioElements.set(handle, audio);
    return handle;
  },

  audioPlayWasm: (handle) => {
    const audio = audioElements.get(handle);
    if (audio) audio.play();
  },

  audioPauseWasm: (handle) => {
    const audio = audioElements.get(handle);
    if (audio) audio.pause();
  },

  audioStopWasm: (handle) => {
    const audio = audioElements.get(handle);
    if (audio) {
      audio.pause();
      audio.currentTime = 0;
    }
  },

  audioSetVolumeWasm: (handle, volume) => {
    const audio = audioElements.get(handle);
    if (audio) audio.volume = Math.max(0, Math.min(1, volume));
  },

  audioGetVolumeWasm: (handle) => {
    const audio = audioElements.get(handle);
    return audio ? audio.volume : 0;
  },

  audioSetMutedWasm: (handle, muted) => {
    const audio = audioElements.get(handle);
    if (audio) audio.muted = muted;
  },

  audioGetMutedWasm: (handle) => {
    const audio = audioElements.get(handle);
    return audio?.muted ? 1 : 0;
  },

  audioSetLoopWasm: (handle, loop) => {
    const audio = audioElements.get(handle);
    if (audio) audio.loop = loop;
  },

  audioSetCurrentTimeWasm: (handle, time) => {
    const audio = audioElements.get(handle);
    if (audio) audio.currentTime = time;
  },

  audioGetCurrentTimeWasm: (handle) => {
    const audio = audioElements.get(handle);
    return audio ? audio.currentTime : 0;
  },

  audioGetDurationWasm: (handle) => {
    const audio = audioElements.get(handle);
    return audio ? audio.duration : 0;
  },

  audioGetReadyStateWasm: (handle) => {
    const audio = audioElements.get(handle);
    return audio ? audio.readyState : 0;
  },

  audioSetPlaybackRateWasm: (handle, rate) => {
    const audio = audioElements.get(handle);
    if (audio) audio.playbackRate = rate;
  },

  audioOnEndedWasm: (handle, callbackId) => {
    const audio = audioElements.get(handle);
    if (audio) {
      audio.onended = () => wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  audioOnErrorWasm: (handle, callbackId) => {
    const audio = audioElements.get(handle);
    if (audio) {
      audio.onerror = () => wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  audioOnCanPlayWasm: (handle, callbackId) => {
    const audio = audioElements.get(handle);
    if (audio) {
      audio.oncanplay = () => wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  destroyAudioElementWasm: (handle) => {
    const audio = audioElements.get(handle);
    if (audio) {
      audio.pause();
      audio.src = "";
      audioElements.delete(handle);
    }
  },
};

// ============================================================================
// GEOLOCATION
// ============================================================================

export const geolocationBindings = {
  geolocationAvailableWasm: () => {
    return "geolocation" in navigator ? 1 : 0;
  },

  getCurrentPositionWasm: (
    callbackId,
    errorCallbackId,
    enableHighAccuracy,
    timeout,
    maximumAge,
  ) => {
    if (!("geolocation" in navigator)) {
      wasmInstance.callbackCtx(
        errorCallbackId,
        allocString(
          JSON.stringify({ code: 0, message: "Geolocation not supported" }),
        ),
      );
      return;
    }

    navigator.geolocation.getCurrentPosition(
      (position) => {
        const data = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          altitude: position.coords.altitude,
          altitudeAccuracy: position.coords.altitudeAccuracy,
          heading: position.coords.heading,
          speed: position.coords.speed,
          timestamp: position.timestamp,
        };
        wasmInstance.callbackCtx(callbackId, allocString(JSON.stringify(data)));
      },
      (error) => {
        const data = { code: error.code, message: error.message };
        wasmInstance.callbackCtx(
          errorCallbackId,
          allocString(JSON.stringify(data)),
        );
      },
      {
        enableHighAccuracy: enableHighAccuracy,
        timeout: timeout,
        maximumAge: maximumAge,
      },
    );
  },

  watchPositionWasm: (
    callbackId,
    errorCallbackId,
    enableHighAccuracy,
    timeout,
    maximumAge,
  ) => {
    if (!("geolocation" in navigator)) return -1;

    return navigator.geolocation.watchPosition(
      (position) => {
        const data = {
          latitude: position.coords.latitude,
          longitude: position.coords.longitude,
          accuracy: position.coords.accuracy,
          altitude: position.coords.altitude,
          altitudeAccuracy: position.coords.altitudeAccuracy,
          heading: position.coords.heading,
          speed: position.coords.speed,
          timestamp: position.timestamp,
        };
        wasmInstance.callbackCtx(callbackId, allocString(JSON.stringify(data)));
      },
      (error) => {
        const data = { code: error.code, message: error.message };
        wasmInstance.callbackCtx(
          errorCallbackId,
          allocString(JSON.stringify(data)),
        );
      },
      {
        enableHighAccuracy: enableHighAccuracy,
        timeout: timeout,
        maximumAge: maximumAge,
      },
    );
  },

  clearWatchPositionWasm: (watchId) => {
    navigator.geolocation.clearWatch(watchId);
  },
};

// ============================================================================
// NOTIFICATIONS
// ============================================================================

export const notificationBindings = {
  notificationPermissionWasm: () => {
    if (!("Notification" in window)) return -1;
    switch (Notification.permission) {
      case "denied":
        return 0;
      case "granted":
        return 1;
      default:
        return 2;
    }
  },

  requestNotificationPermissionWasm: (callbackId) => {
    if (!("Notification" in window)) {
      wasmInstance.callbackCtx(callbackId, -1);
      return;
    }

    Notification.requestPermission().then((permission) => {
      let result;
      switch (permission) {
        case "denied":
          result = 0;
          break;
        case "granted":
          result = 1;
          break;
        default:
          result = 2;
      }
      wasmInstance.callbackCtx(callbackId, result);
    });
  },

  showNotificationWasm: (
    titlePtr,
    titleLen,
    bodyPtr,
    bodyLen,
    iconPtr,
    iconLen,
    tagPtr,
    tagLen,
  ) => {
    if (!("Notification" in window) || Notification.permission !== "granted")
      return 0;

    const title = readWasmString(titlePtr, titleLen);
    const options = {
      body: readWasmString(bodyPtr, bodyLen),
      icon: readWasmString(iconPtr, iconLen),
      tag: readWasmString(tagPtr, tagLen),
    };

    try {
      new Notification(title, options);
      return 1;
    } catch (e) {
      return 0;
    }
  },
};

// ============================================================================
// FULLSCREEN
// ============================================================================

export const fullscreenBindings = {
  requestFullscreenWasm: (idPtr, idLen) => {
    const id = readWasmString(idPtr, idLen);
    const element = document.getElementById(id);
    if (!element) return 0;

    try {
      const fn =
        element.requestFullscreen ||
        element.webkitRequestFullscreen ||
        element.mozRequestFullScreen;
      if (fn) {
        fn.call(element);
        return 1;
      }
    } catch (e) {
      console.error("Fullscreen request failed:", e);
    }
    return 0;
  },

  exitFullscreenWasm: () => {
    try {
      const fn =
        document.exitFullscreen ||
        document.webkitExitFullscreen ||
        document.mozCancelFullScreen;
      if (fn) {
        fn.call(document);
        return 1;
      }
    } catch (e) {
      console.error("Exit fullscreen failed:", e);
    }
    return 0;
  },

  isFullscreenWasm: () => {
    return document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement
      ? 1
      : 0;
  },

  getFullscreenElementIdWasm: () => {
    const el =
      document.fullscreenElement ||
      document.webkitFullscreenElement ||
      document.mozFullScreenElement;
    return allocString(el?.id || "");
  },

  onFullscreenChangeWasm: (callbackId) => {
    document.addEventListener("fullscreenchange", () => {
      wasmInstance.callbackCtx(
        callbackId,
        fullscreenBindings.isFullscreenWasm(),
      );
    });
  },
};

// ============================================================================
// TEXT SELECTION
// ============================================================================

export const selectionBindings = {
  getSelectionTextWasm: () => {
    const selection = window.getSelection();
    return allocString(selection?.toString() || "");
  },

  getSelectionRangeWasm: (idPtr, idLen) => {
    const id = readWasmString(idPtr, idLen);
    const element = document.getElementById(id);

    const ptr = wasmInstance.allocate(8);
    const view = new Uint32Array(wasmInstance.memory.buffer, ptr, 2);

    if (element && "selectionStart" in element) {
      view[0] = element.selectionStart;
      view[1] = element.selectionEnd;
    } else {
      view[0] = 0;
      view[1] = 0;
    }
    return ptr;
  },

  setSelectionRangeWasm: (idPtr, idLen, start, end, direction) => {
    const id = readWasmString(idPtr, idLen);
    const element = document.getElementById(id);
    if (element && "setSelectionRange" in element) {
      const dirs = ["none", "forward", "backward"];
      element.setSelectionRange(start, end, dirs[direction] || "none");
    }
  },

  selectAllWasm: (idPtr, idLen) => {
    const id = readWasmString(idPtr, idLen);
    const element = document.getElementById(id);
    if (element && "select" in element) {
      element.select();
    }
  },
};

// ============================================================================
// RESIZE OBSERVER
// ============================================================================

export const resizeObserverBindings = {
  createResizeObserverWasm: (callbackId) => {
    const handle = nextResizeObserverHandle++;

    const observer = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const data = {
          id: entry.target.id,
          width: entry.contentRect.width,
          height: entry.contentRect.height,
          x: entry.contentRect.x,
          y: entry.contentRect.y,
        };
        wasmInstance.callbackCtx(callbackId, allocString(JSON.stringify(data)));
      }
    });

    resizeObservers.set(handle, observer);
    return handle;
  },

  observeResizeWasm: (handle, elementPtr, elementLen) => {
    const observer = resizeObservers.get(handle);
    if (!observer) return 0;

    const id = readWasmString(elementPtr, elementLen);
    const element = document.getElementById(id);
    if (!element) return 0;

    observer.observe(element);
    return 1;
  },

  unobserveResizeWasm: (handle, elementPtr, elementLen) => {
    const observer = resizeObservers.get(handle);
    if (!observer) return;

    const id = readWasmString(elementPtr, elementLen);
    const element = document.getElementById(id);
    if (element) {
      observer.unobserve(element);
    }
  },

  disconnectResizeObserverWasm: (handle) => {
    const observer = resizeObservers.get(handle);
    if (observer) {
      observer.disconnect();
    }
  },

  destroyResizeObserverWasm: (handle) => {
    const observer = resizeObservers.get(handle);
    if (observer) {
      observer.disconnect();
      resizeObservers.delete(handle);
    }
  },
};

// ============================================================================
// MUTATION OBSERVER
// ============================================================================

export const mutationObserverBindings = {
  createMutationObserverWasm: (callbackId) => {
    const handle = nextMutationObserverHandle++;

    const observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        const data = {
          type: mutation.type,
          targetId: mutation.target.id,
          attributeName: mutation.attributeName,
          oldValue: mutation.oldValue,
          addedNodesCount: mutation.addedNodes.length,
          removedNodesCount: mutation.removedNodes.length,
        };
        wasmInstance.callbackCtx(callbackId, allocString(JSON.stringify(data)));
      }
    });

    mutationObservers.set(handle, observer);
    return handle;
  },

  observeMutationWasm: (
    handle,
    elementPtr,
    elementLen,
    childList,
    attributes,
    characterData,
    subtree,
    attributeOldValue,
    characterDataOldValue,
  ) => {
    const observer = mutationObservers.get(handle);
    if (!observer) return 0;

    const id = readWasmString(elementPtr, elementLen);
    const element = document.getElementById(id);
    if (!element) return 0;

    observer.observe(element, {
      childList,
      attributes,
      characterData,
      subtree,
      attributeOldValue,
      characterDataOldValue,
    });
    return 1;
  },

  disconnectMutationObserverWasm: (handle) => {
    const observer = mutationObservers.get(handle);
    if (observer) {
      observer.disconnect();
    }
  },

  destroyMutationObserverWasm: (handle) => {
    const observer = mutationObservers.get(handle);
    if (observer) {
      observer.disconnect();
      mutationObservers.delete(handle);
    }
  },
};

// ============================================================================
// FETCH ENHANCEMENTS
// ============================================================================

export const fetchBindings = {
  fetchWithAbortWasm: (urlPtr, urlLen, callbackId, httpPtr, httpLen) => {
    const url = readWasmString(urlPtr, urlLen);
    const httpConfig = readWasmString(httpPtr, httpLen);
    const config = JSON.parse(httpConfig || "{}");

    const handle = nextFetchHandle++;
    const controller = new AbortController();
    fetchAbortControllers.set(handle, controller);

    config.signal = controller.signal;

    fetch(url, config)
      .then(async (res) => {
        const body = await res.text();
        const response = {
          ok: res.ok,
          status: res.status,
          statusText: res.statusText,
          body,
        };
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ ok: response })),
        );
      })
      .catch((err) => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ err: { message: err.message } })),
        );
      })
      .finally(() => {
        fetchAbortControllers.delete(handle);
      });

    return handle;
  },

  abortFetchWasm: (handle) => {
    const controller = fetchAbortControllers.get(handle);
    if (controller) {
      controller.abort();
      fetchAbortControllers.delete(handle);
      return 1;
    }
    return 0;
  },

  fetchWithProgressWasm: (
    urlPtr,
    urlLen,
    callbackId,
    progressCallbackId,
    httpPtr,
    httpLen,
  ) => {
    const url = readWasmString(urlPtr, urlLen);
    const httpConfig = readWasmString(httpPtr, httpLen);
    const config = JSON.parse(httpConfig || "{}");

    fetch(url, config)
      .then(async (res) => {
        const reader = res.body.getReader();
        const contentLength = +res.headers.get("Content-Length") || 0;
        let receivedLength = 0;
        const chunks = [];

        while (true) {
          const { done, value } = await reader.read();
          if (done) break;

          chunks.push(value);
          receivedLength += value.length;

          const progress = { loaded: receivedLength, total: contentLength };
          wasmInstance.callbackCtx(
            progressCallbackId,
            allocString(JSON.stringify(progress)),
          );
        }

        const allChunks = new Uint8Array(receivedLength);
        let position = 0;
        for (const chunk of chunks) {
          allChunks.set(chunk, position);
          position += chunk.length;
        }

        const body = new TextDecoder().decode(allChunks);
        const response = {
          ok: res.ok,
          status: res.status,
          statusText: res.statusText,
          body,
        };
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ ok: response })),
        );
      })
      .catch((err) => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ err: { message: err.message } })),
        );
      });
  },

  fetchJsonWasm: (urlPtr, urlLen, callbackId, httpPtr, httpLen) => {
    const url = readWasmString(urlPtr, urlLen);
    const httpConfig = readWasmString(httpPtr, httpLen);
    const config = JSON.parse(httpConfig || "{}");

    fetch(url, config)
      .then((res) => res.json())
      .then((data) => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ ok: data })),
        );
      })
      .catch((err) => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ err: { message: err.message } })),
        );
      });
  },
};

// ============================================================================
// PERFORMANCE TIMING
// ============================================================================

export const performanceBindings = {
  performanceMarkWasm: (namePtr, nameLen) => {
    const name = readWasmString(namePtr, nameLen);
    performance.mark(name);
  },

  performanceMeasureWasm: (
    namePtr,
    nameLen,
    startMarkPtr,
    startMarkLen,
    endMarkPtr,
    endMarkLen,
  ) => {
    const name = readWasmString(namePtr, nameLen);
    const startMark = readWasmString(startMarkPtr, startMarkLen);
    const endMark = readWasmString(endMarkPtr, endMarkLen);

    try {
      performance.measure(name, startMark, endMark);
      return 1;
    } catch (e) {
      return 0;
    }
  },

  performanceGetEntriesByNameWasm: (namePtr, nameLen) => {
    const name = readWasmString(namePtr, nameLen);
    const entries = performance.getEntriesByName(name);
    return allocString(JSON.stringify(entries));
  },

  performanceClearMarksWasm: (namePtr, nameLen) => {
    const name = readWasmString(namePtr, nameLen);
    if (name) {
      performance.clearMarks(name);
    } else {
      performance.clearMarks();
    }
  },

  performanceClearMeasuresWasm: (namePtr, nameLen) => {
    const name = readWasmString(namePtr, nameLen);
    if (name) {
      performance.clearMeasures(name);
    } else {
      performance.clearMeasures();
    }
  },

  performanceNowWasm: () => {
    return performance.now();
  },
};

// ============================================================================
// INDEXED DB
// ============================================================================

export const indexedDBBindings = {
  idbOpenWasm: (namePtr, nameLen, version, callbackId, errorCallbackId) => {
    const name = readWasmString(namePtr, nameLen);

    const request = indexedDB.open(name, version);

    request.onerror = () => {
      wasmInstance.callbackCtx(
        errorCallbackId,
        allocString(request.error?.message || "Unknown error"),
      );
    };

    request.onsuccess = () => {
      const handle = nextIdbHandle++;
      idbDatabases.set(handle, request.result);
      wasmInstance.callbackCtx(callbackId, handle);
    };

    request.onupgradeneeded = (event) => {
      // Store the database for object store creation during upgrade
      const handle = nextIdbHandle++;
      idbDatabases.set(handle, request.result);
    };
  },

  idbCloseWasm: (handle) => {
    const db = idbDatabases.get(handle);
    if (db) {
      db.close();
      idbDatabases.delete(handle);
    }
  },

  idbCreateObjectStoreWasm: (
    handle,
    namePtr,
    nameLen,
    keyPathPtr,
    keyPathLen,
    autoIncrement,
  ) => {
    const db = idbDatabases.get(handle);
    if (!db) return 0;

    const name = readWasmString(namePtr, nameLen);
    const keyPath = readWasmString(keyPathPtr, keyPathLen);

    try {
      db.createObjectStore(name, {
        keyPath: keyPath || undefined,
        autoIncrement,
      });
      return 1;
    } catch (e) {
      console.error("Create object store failed:", e);
      return 0;
    }
  },

  idbDeleteObjectStoreWasm: (handle, namePtr, nameLen) => {
    const db = idbDatabases.get(handle);
    if (!db) return 0;

    const name = readWasmString(namePtr, nameLen);

    try {
      db.deleteObjectStore(name);
      return 1;
    } catch (e) {
      return 0;
    }
  },

  idbPutWasm: (
    handle,
    storeNamePtr,
    storeNameLen,
    keyPtr,
    keyLen,
    valuePtr,
    valueLen,
    callbackId,
  ) => {
    const db = idbDatabases.get(handle);
    if (!db) {
      wasmInstance.callbackCtx(callbackId, 0);
      return;
    }

    const storeName = readWasmString(storeNamePtr, storeNameLen);
    const key = readWasmString(keyPtr, keyLen);
    const value = readWasmString(valuePtr, valueLen);

    try {
      const transaction = db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.put(JSON.parse(value), key);

      request.onsuccess = () => wasmInstance.callbackCtx(callbackId, 1);
      request.onerror = () => wasmInstance.callbackCtx(callbackId, 0);
    } catch (e) {
      wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  idbGetWasm: (
    handle,
    storeNamePtr,
    storeNameLen,
    keyPtr,
    keyLen,
    callbackId,
  ) => {
    const db = idbDatabases.get(handle);
    if (!db) {
      wasmInstance.callbackCtx(callbackId, allocString("null"));
      return;
    }

    const storeName = readWasmString(storeNamePtr, storeNameLen);
    const key = readWasmString(keyPtr, keyLen);

    try {
      const transaction = db.transaction(storeName, "readonly");
      const store = transaction.objectStore(storeName);
      const request = store.get(key);

      request.onsuccess = () => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify(request.result)),
        );
      };
      request.onerror = () => {
        wasmInstance.callbackCtx(callbackId, allocString("null"));
      };
    } catch (e) {
      wasmInstance.callbackCtx(callbackId, allocString("null"));
    }
  },

  idbDeleteWasm: (
    handle,
    storeNamePtr,
    storeNameLen,
    keyPtr,
    keyLen,
    callbackId,
  ) => {
    const db = idbDatabases.get(handle);
    if (!db) {
      wasmInstance.callbackCtx(callbackId, 0);
      return;
    }

    const storeName = readWasmString(storeNamePtr, storeNameLen);
    const key = readWasmString(keyPtr, keyLen);

    try {
      const transaction = db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.delete(key);

      request.onsuccess = () => wasmInstance.callbackCtx(callbackId, 1);
      request.onerror = () => wasmInstance.callbackCtx(callbackId, 0);
    } catch (e) {
      wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  idbGetAllWasm: (handle, storeNamePtr, storeNameLen, callbackId) => {
    const db = idbDatabases.get(handle);
    if (!db) {
      wasmInstance.callbackCtx(callbackId, allocString("[]"));
      return;
    }

    const storeName = readWasmString(storeNamePtr, storeNameLen);

    try {
      const transaction = db.transaction(storeName, "readonly");
      const store = transaction.objectStore(storeName);
      const request = store.getAll();

      request.onsuccess = () => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify(request.result)),
        );
      };
      request.onerror = () => {
        wasmInstance.callbackCtx(callbackId, allocString("[]"));
      };
    } catch (e) {
      wasmInstance.callbackCtx(callbackId, allocString("[]"));
    }
  },

  idbClearStoreWasm: (handle, storeNamePtr, storeNameLen, callbackId) => {
    const db = idbDatabases.get(handle);
    if (!db) {
      wasmInstance.callbackCtx(callbackId, 0);
      return;
    }

    const storeName = readWasmString(storeNamePtr, storeNameLen);

    try {
      const transaction = db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      const request = store.clear();

      request.onsuccess = () => wasmInstance.callbackCtx(callbackId, 1);
      request.onerror = () => wasmInstance.callbackCtx(callbackId, 0);
    } catch (e) {
      wasmInstance.callbackCtx(callbackId, 0);
    }
  },

  idbDeleteDatabaseWasm: (namePtr, nameLen, callbackId) => {
    const name = readWasmString(namePtr, nameLen);

    const request = indexedDB.deleteDatabase(name);
    request.onsuccess = () => wasmInstance.callbackCtx(callbackId, 1);
    request.onerror = () => wasmInstance.callbackCtx(callbackId, 0);
  },
};

// ============================================================================
// ANIMATION FRAME
// ============================================================================

export const animationBindings = {
  requestAnimationFrameWasm: (callbackId) => {
    const frameId = requestAnimationFrame((timestamp) => {
      animationFrameCallbacks.delete(frameId);
      // Pass timestamp as float to WASM
      wasmInstance.callbackCtx(callbackId, timestamp);
    });
    animationFrameCallbacks.set(frameId, callbackId);
    return frameId;
  },

  cancelAnimationFrameWasm: (frameId) => {
    cancelAnimationFrame(frameId);
    animationFrameCallbacks.delete(frameId);
  },
};

// ============================================================================
// POINTER LOCK
// ============================================================================

export const pointerLockBindings = {
  requestPointerLockWasm: (idPtr, idLen) => {
    const id = readWasmString(idPtr, idLen);
    const element = document.getElementById(id);
    if (!element) return 0;

    try {
      element.requestPointerLock();
      return 1;
    } catch (e) {
      return 0;
    }
  },

  exitPointerLockWasm: () => {
    document.exitPointerLock();
  },

  isPointerLockedWasm: () => {
    return document.pointerLockElement ? 1 : 0;
  },

  onPointerLockChangeWasm: (callbackId) => {
    document.addEventListener("pointerlockchange", () => {
      wasmInstance.callbackCtx(callbackId, document.pointerLockElement ? 1 : 0);
    });
  },
};

// ============================================================================
// VIBRATION (Mobile)
// ============================================================================

export const vibrationBindings = {
  vibrateWasm: (duration) => {
    if (!("vibrate" in navigator)) return 0;
    return navigator.vibrate(duration) ? 1 : 0;
  },

  vibratePatternWasm: (patternPtr, patternLen) => {
    if (!("vibrate" in navigator)) return 0;

    const pattern = new Uint32Array(
      wasmInstance.memory.buffer,
      patternPtr,
      patternLen,
    );
    return navigator.vibrate(Array.from(pattern)) ? 1 : 0;
  },

  vibrateCancelWasm: () => {
    if ("vibrate" in navigator) {
      navigator.vibrate(0);
    }
  },
};

// ============================================================================
// SCREEN ORIENTATION
// ============================================================================

export const orientationBindings = {
  getScreenOrientationWasm: () => {
    if (!screen.orientation) return allocString("unknown");
    return allocString(screen.orientation.type);
  },

  getScreenOrientationAngleWasm: () => {
    if (!screen.orientation) return 0;
    return screen.orientation.angle;
  },

  lockScreenOrientationWasm: (orientationPtr, orientationLen, callbackId) => {
    const orientation = readWasmString(orientationPtr, orientationLen);

    if (!screen.orientation?.lock) {
      wasmInstance.callbackCtx(callbackId, 0);
      return;
    }

    screen.orientation
      .lock(orientation)
      .then(() => wasmInstance.callbackCtx(callbackId, 1))
      .catch(() => wasmInstance.callbackCtx(callbackId, 0));
  },

  unlockScreenOrientationWasm: () => {
    if (screen.orientation?.unlock) {
      screen.orientation.unlock();
    }
  },

  onOrientationChangeWasm: (callbackId) => {
    if (screen.orientation) {
      screen.orientation.addEventListener("change", () => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(screen.orientation.type),
        );
      });
    }
  },
};

// ============================================================================
// BATTERY STATUS
// ============================================================================

export const batteryBindings = {
  getBatteryStatusWasm: (callbackId) => {
    if (!("getBattery" in navigator)) {
      wasmInstance.callbackCtx(
        callbackId,
        allocString(JSON.stringify({ error: "Not supported" })),
      );
      return;
    }

    navigator
      .getBattery()
      .then((battery) => {
        const status = {
          charging: battery.charging,
          chargingTime: battery.chargingTime,
          dischargingTime: battery.dischargingTime,
          level: battery.level,
        };
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify(status)),
        );
      })
      .catch((err) => {
        wasmInstance.callbackCtx(
          callbackId,
          allocString(JSON.stringify({ error: err.message })),
        );
      });
  },
};

// ============================================================================
// SHARE API
// ============================================================================

export const shareBindings = {
  canShareWasm: () => {
    return "share" in navigator ? 1 : 0;
  },

  shareWasm: (
    titlePtr,
    titleLen,
    textPtr,
    textLen,
    urlPtr,
    urlLen,
    callbackId,
  ) => {
    if (!("share" in navigator)) {
      wasmInstance.callbackCtx(callbackId, 0);
      return;
    }

    const data = {
      title: readWasmString(titlePtr, titleLen),
      text: readWasmString(textPtr, textLen),
      url: readWasmString(urlPtr, urlLen),
    };

    navigator
      .share(data)
      .then(() => wasmInstance.callbackCtx(callbackId, 1))
      .catch(() => wasmInstance.callbackCtx(callbackId, 0));
  },
};

// ============================================================================
// COMBINED EXPORT
// ============================================================================

export const additionalEnv = {
  ...fileBindings,
  ...dragDropBindings,
  ...websocketBindings,
  ...sessionStorageBindings,
  ...canvasBindings,
  ...audioBindings,
  ...geolocationBindings,
  ...notificationBindings,
  ...fullscreenBindings,
  ...selectionBindings,
  ...resizeObserverBindings,
  ...mutationObserverBindings,
  ...fetchBindings,
  ...performanceBindings,
  ...indexedDBBindings,
  ...animationBindings,
  ...pointerLockBindings,
  ...vibrationBindings,
  ...orientationBindings,
  ...batteryBindings,
  ...shareBindings,
};
