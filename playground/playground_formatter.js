export function formatWasmError(error) {
  const lines = error.stack?.split("\n") || [];

  const frames = [];
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("at ")) continue;

    // Parse "at functionName (location)" or "at location"
    const match =
      trimmed.match(/^at\s+(.+?)\s+\((.+)\)$/) ||
      trimmed.match(/^at\s+()(.+)$/);
    if (!match) continue;

    let [, funcName, location] = match;

    // Extract source file info from the function/location
    const zigFileMatch =
      funcName.match(/(\w+\.zig):(\d+)/) || location.match(/(\w+\.zig):(\d+)/);
    const jsFileMatch = location.match(/([^/]+\.js):(\d+):(\d+)/);
    const wasmMatch = location.match(/wasm:\/\/wasm/);

    // Clean up function name
    funcName = funcName
      .replace(/^vapor\.wasm\./, "")
      .replace(/\(function '(.+?)'\)/, "")
      .replace(/\.API\./, ".")
      .trim();

    // Determine frame type
    let type = "js";
    if (zigFileMatch) type = "zig";
    else if (wasmMatch) type = "wasm";

    frames.push({
      funcName,
      location,
      type,
      zigFile: zigFileMatch,
      jsFile: jsFileMatch,
    });
  }

  // Style config
  const styles = {
    header: "color: #ff6b6b; font-size: 14px; font-weight: bold;",
    zig: "color: #f7a84c; font-weight: bold;",
    zigDim: "color: #a0724a;",
    wasm: "color: #888; font-style: italic;",
    js: "color: #69a3f7;",
    jsDim: "color: #4a6fa0;",
    separator: "color: #555;",
    label:
      "background: #3a1a1a; color: #ff6b6b; padding: 1px 5px; border-radius: 3px; font-size: 10px;",
    zigLabel:
      "background: #3a2a1a; color: #f7a84c; padding: 1px 5px; border-radius: 3px; font-size: 10px;",
    jsLabel:
      "background: #1a2a3a; color: #69a3f7; padding: 1px 5px; border-radius: 3px; font-size: 10px;",
  };

  // Header
  console.log(
    "%c⚡ WASM PANIC %c %c" + error.message,
    styles.label,
    "",
    styles.header,
  );
  console.log("%c" + "─".repeat(60), styles.separator);

  // Frames
  for (let i = 0; i < frames.length; i++) {
    const f = frames[i];
    const num = String(i).padStart(2, " ");

    if (f.type === "zig" && f.zigFile) {
      const [, file, line] = f.zigFile;
      console.log(
        `%c${num} %cZIG %c ${f.funcName} %c${file}:${line}`,
        styles.separator,
        styles.zigLabel,
        styles.zig,
        styles.zigDim,
      );
    } else if (f.type === "wasm") {
      console.log(
        `%c${num} %c    %c ${f.funcName}`,
        styles.separator,
        "",
        styles.wasm,
      );
    } else {
      const loc = f.jsFile ? `${f.jsFile[1]}:${f.jsFile[2]}` : "";
      console.log(
        `%c${num} %c JS %c ${f.funcName} %c${loc}`,
        styles.separator,
        styles.jsLabel,
        styles.js,
        styles.jsDim,
      );
    }
  }

  console.log("%c" + "─".repeat(60), styles.separator);
}

export function parseWasmError(error) {
  const stack = error.stack || "";

  const stackLines = stack
    .split("\n")
    .filter((line) => line.trim().startsWith("at "))
    .map((line) => {
      const trimmed = line.trim();

      // Wasm format: "at vapor.wasm.main.sample (wasm://wasm/vapor.wasm-010eabae:wasm-function[325]:0x2ce79)"
      const wasmMatch = trimmed.match(
        /^at\s+(?:vapor\.wasm\.)?(.+?)\s+\(wasm:\/\/wasm\/[^:]+:wasm-function\[(\d+)]:0x([0-9a-f]+)\)$/,
      );
      if (wasmMatch) {
        return {
          function: wasmMatch[1],
          wasmFunctionIndex: parseInt(wasmMatch[2]),
          wasmOffset: "0x" + wasmMatch[3],
          type: "wasm",
        };
      }

      // JS format: "at HTMLDivElement.<anonymous> (http://localhost:5173/web/wasi_obj.js:695:22)"
      const jsMatch = trimmed.match(/^at\s+(.+?)\s+\((.+?):(\d+):(\d+)\)$/);
      if (jsMatch) {
        return {
          function: jsMatch[1],
          file: jsMatch[2],
          line: parseInt(jsMatch[3]),
          column: parseInt(jsMatch[4]),
          type: "js",
        };
      }

      return { raw: trimmed, type: "unknown" };
    });

  // Filter out internal panic/abort machinery
  const internalFunctions = [
    "posix.abort",
    "debug.defaultPanic",
    "debug.FullPanic",
  ];
  const userStack = stackLines.filter(
    (s) => !internalFunctions.some((fn) => s.function?.includes(fn)),
  );

  const crashSite =
    userStack.find((s) => s.type === "wasm") || userStack[0] || null;

  return {
    type: error.constructor?.name || "RuntimeError",
    message: error.message || "unreachable",
    isWasmTrap: error instanceof WebAssembly.RuntimeError,
    crashSite,
    userStack,
    fullStack: stackLines,
  };
}
