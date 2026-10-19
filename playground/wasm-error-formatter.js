/**
 * Pretty error formatter for wasm errors with DWARF source mapping
 */

export function formatErrorPretty(enhanced) {
  // Styled console output
  const styles = {
    title: "color: #ff6b6b; font-weight: bold; font-size: 14px;",
    message: "color: #ffa502; font-size: 12px;",
    funcName: "color: #70a1ff; font-weight: bold;",
    location: "color: #7bed9f;",
    dim: "color: #747d8c;",
    reset: "",
  };

  // Build the styled output
  console.log(
    `%c⚠ ${enhanced.name}%c: ${enhanced.message}`,
    styles.title,
    styles.message,
  );

  console.groupCollapsed(
    "%c📍 Stack Trace (click to expand)",
    "color: #a4b0be; font-weight: bold;",
  );

  for (const frame of enhanced.frames) {
    const loc =
      frame.file !== "unknown"
        ? `${frame.file}:${frame.line}:${frame.column}`
        : `wasm:0x${frame.wasmOffset.toString(16)}`;

    console.log(
      `  %c${frame.func}%c at %c${loc}`,
      styles.funcName,
      styles.dim,
      styles.location,
    );
  }

  console.groupEnd();
}

/**
 * Format as a nice visual box in the console
 */
export function formatErrorBox(enhanced) {
  const lines = [];
  const maxWidth = 60;

  lines.push("┌" + "─".repeat(maxWidth) + "┐");
  lines.push("│ " + `⚠ WASM ERROR`.padEnd(maxWidth - 1) + "│");
  lines.push("├" + "─".repeat(maxWidth) + "┤");

  // Error name and message
  const errLine = `${enhanced.name}: ${enhanced.message}`;
  const wrappedErr = wrapText(errLine, maxWidth - 2);
  for (const line of wrappedErr) {
    lines.push("│ " + line.padEnd(maxWidth - 1) + "│");
  }

  lines.push("├" + "─".repeat(maxWidth) + "┤");

  // Stack frames
  for (let i = 0; i < enhanced.frames.length; i++) {
    const frame = enhanced.frames[i];
    const loc =
      frame.file !== "unknown"
        ? `${frame.file}:${frame.line}`
        : `wasm:0x${frame.wasmOffset.toString(16)}`;

    const frameLine = `${i === 0 ? "→" : " "} ${frame.func}`;
    const locLine = `    at ${loc}`;

    lines.push(
      "│ " + frameLine.slice(0, maxWidth - 1).padEnd(maxWidth - 1) + "│",
    );
    lines.push(
      "│ " + locLine.slice(0, maxWidth - 1).padEnd(maxWidth - 1) + "│",
    );
  }

  lines.push("└" + "─".repeat(maxWidth) + "┘");

  console.log(
    "%c" + lines.join("\n"),
    "font-family: monospace; color: #ff6b6b;",
  );
}

/**
 * Show error as an overlay on the page
 */
export function showErrorOverlay(enhanced) {
  // Remove existing overlay if any
  const existing = document.getElementById("wasm-error-overlay");
  if (existing) existing.remove();

  const overlay = document.createElement("div");
  overlay.id = "wasm-error-overlay";
  overlay.innerHTML = `
    <style>
      #wasm-error-overlay {
        position: fixed;
        bottom: 20px;
        right: 20px;
        max-width: 500px;
        max-height: 400px;
        background: #1a1a2e;
        border: 2px solid #ff6b6b;
        border-radius: 8px;
        font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
        font-size: 12px;
        color: #eee;
        z-index: 999999;
        box-shadow: 0 4px 20px rgba(0,0,0,0.5);
        overflow: hidden;
      }
      #wasm-error-overlay .header {
        background: #ff6b6b;
        color: #1a1a2e;
        padding: 8px 12px;
        font-weight: bold;
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      #wasm-error-overlay .close {
        cursor: pointer;
        font-size: 18px;
        line-height: 1;
      }
      #wasm-error-overlay .close:hover {
        color: #fff;
      }
      #wasm-error-overlay .content {
        padding: 12px;
        overflow-y: auto;
        max-height: 340px;
      }
      #wasm-error-overlay .message {
        color: #ffa502;
        margin-bottom: 12px;
        word-break: break-word;
      }
      #wasm-error-overlay .frame {
        margin: 8px 0;
        padding: 6px 8px;
        background: #16213e;
        border-radius: 4px;
        border-left: 3px solid #70a1ff;
      }
      #wasm-error-overlay .frame.first {
        border-left-color: #ff6b6b;
      }
      #wasm-error-overlay .func {
        color: #70a1ff;
        font-weight: bold;
      }
      #wasm-error-overlay .location {
        color: #7bed9f;
        font-size: 11px;
        margin-top: 2px;
      }
    </style>
    <div class="header">
      <span>⚠ ${enhanced.name}</span>
      <span class="close" onclick="this.closest('#wasm-error-overlay').remove()">×</span>
    </div>
    <div class="content">
      <div class="message">${escapeHtml(enhanced.message)}</div>
      ${enhanced.frames
      .map((frame, i) => {
        const loc =
          frame.file !== "unknown"
            ? `${frame.file}:${frame.line}:${frame.column}`
            : `wasm:0x${frame.wasmOffset.toString(16)}`;
        return `
          <div class="frame ${i === 0 ? "first" : ""}">
            <div class="func">${escapeHtml(frame.func)}</div>
            <div class="location">${escapeHtml(loc)}</div>
          </div>
        `;
      })
      .join("")}
    </div>
  `;

  document.body.appendChild(overlay);

  // Auto-remove after 30 seconds (optional)
  // setTimeout(() => overlay.remove(), 30000);
}

/**
 * Suppress Chrome's default error and show only yours
 */
export function setupCleanErrorHandling(mapper) {
  // For unhandled promise rejections
  window.addEventListener("unhandledrejection", (e) => {
    const err = e.reason;
    if (!err?.stack?.includes("wasm")) return;

    e.preventDefault();

    console.log("Unhandled rejection:", err.stack);
    // Check if C++ DevTools has enhanced the stack (contains .zig: patterns)
    if (err.stack.match(/\w+\.zig:\d+/)) {
      console.log("Enhanced stack detected!");
      // Use the enhanced stack directly - it's already good!
      formatEnhancedStack(err);
    } else if (mapper) {
      // Fallback to our parser
      // const enhanced = mapper.enhanceError(err);
      // formatErrorPretty(enhanced);
    }
  });

  // For regular errors
  window.addEventListener("error", (e) => {
    if (!mapper) return;
    if (!e.error?.stack?.includes("wasm")) return;

    // Prevent Chrome's default logging
    e.preventDefault();

    const enhanced = mapper.enhanceError(e.error);
    formatErrorPretty(enhanced);
    showErrorOverlay(enhanced);
  });
}

function formatEnhancedStack(err) {
  const lines = err.stack.split("\n");

  console.log(
    `%c⚠ ${err.name}%c: ${err.message}`,
    "color: #ff6b6b; font-weight: bold;",
    "color: #ffa502;",
  );

  console.groupCollapsed(
    "%c📍 Stack Trace",
    "color: #a4b0be; font-weight: bold;",
  );

  for (const line of lines.slice(1)) {
    // Parse: "at funcName (file.zig:123:45)" or "at funcName (file.zig:123)"
    const match = line.match(/at\s+([^\(]+)\s*\(([^:]+):(\d+)(?::(\d+))?\)/);
    if (match) {
      const [, func, file, lineNum, col] = match;
      const loc = col ? `${file}:${lineNum}:${col}` : `${file}:${lineNum}`;
      console.log(
        `  %c${func.trim()}%c at %c${loc}`,
        "color: #70a1ff; font-weight: bold;",
        "color: #747d8c;",
        "color: #7bed9f;",
      );
    }
  }

  console.groupEnd();
}

// Helper functions
function wrapText(text, maxWidth) {
  const words = text.split(" ");
  const lines = [];
  let currentLine = "";

  for (const word of words) {
    if ((currentLine + " " + word).trim().length <= maxWidth) {
      currentLine = (currentLine + " " + word).trim();
    } else {
      if (currentLine) lines.push(currentLine);
      currentLine = word;
    }
  }
  if (currentLine) lines.push(currentLine);
  return lines;
}

function escapeHtml(str) {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}
