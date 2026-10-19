/**
 * Integration helper for wasm error parsing with DWARF source maps
 * 
 * This shows how to integrate the WasmSourceMapper with your application.
 */

import { WasmSourceMapper } from './wasm-dwarf-parser.js';

// Store the mapper globally or in your app state
let wasmMapper = null;

/**
 * Initialize the mapper when loading your wasm module
 */
export async function loadWasmWithSourceMap(wasmUrl, imports = {}) {
  const response = await fetch(wasmUrl);
  const bytes = await response.arrayBuffer();
  
  // Create the source mapper
  wasmMapper = new WasmSourceMapper(bytes);
  
  // Instantiate the wasm module
  const { instance, module } = await WebAssembly.instantiateStreaming(
    fetch(wasmUrl),  // Re-fetch for streaming (or reuse bytes)
    imports
  );
  
  // Alternative if you want to reuse the bytes:
  // const module = await WebAssembly.compile(bytes);
  // const instance = await WebAssembly.instantiate(module, imports);
  
  return { instance, module, mapper: wasmMapper };
}

/**
 * Your original parseWasmStack function, but now it works!
 */
export function parseWasmStack(err, mapper = wasmMapper) {
  // If we have a mapper, use it for accurate source locations
  if (mapper) {
    return mapper.enhanceError(err);
  }
  
  // Fallback: parse raw wasm stack (without source mapping)
  const stack = err.stack || "";
  const lines = stack.split("\n");

  const frames = lines
    .filter((line) => line.includes("wasm-function"))
    .map((line) => {
      const funcMatch = line.match(/at\s+(?:[\w.]+\.)?(\w+)/);
      const wasmMatch = line.match(/wasm-function\[(\d+)\]:0x([0-9a-f]+)/i);

      return {
        func: funcMatch ? funcMatch[1] : "unknown",
        file: "unknown",
        line: 0,
        wasmOffset: wasmMatch ? parseInt(wasmMatch[2], 16) : 0,
        wasmFuncIndex: wasmMatch ? parseInt(wasmMatch[1], 10) : 0,
      };
    });

  return { name: err.name, message: err.message, frames };
}

/**
 * Format a parsed stack trace for display
 */
export function formatStack(parsed) {
  let result = `${parsed.name}: ${parsed.message}\n`;
  
  for (const frame of parsed.frames) {
    if (frame.file !== 'unknown') {
      result += `    at ${frame.func} (${frame.file}:${frame.line})\n`;
    } else {
      result += `    at ${frame.func} (wasm:0x${frame.wasmOffset.toString(16)})\n`;
    }
  }
  
  return result;
}

// ============================================================
// FULL EXAMPLE USAGE
// ============================================================

/*
// In your main app code:

import { loadWasmWithSourceMap, parseWasmStack, formatStack } from './wasm-debug-helper.js';

async function init() {
  const { instance, mapper } = await loadWasmWithSourceMap('/web/vapor.wasm', {
    // your imports...
  });
  
  // Store for global error handling
  window.wasmMapper = mapper;
  
  // Set up global error handler
  window.addEventListener('error', (event) => {
    if (event.error && event.error.stack?.includes('wasm')) {
      const parsed = parseWasmStack(event.error, mapper);
      console.log('WASM Error:');
      console.log(formatStack(parsed));
      
      // Or display in UI
      showErrorOverlay(parsed);
    }
  });
  
  // Also catch unhandled promise rejections
  window.addEventListener('unhandledrejection', (event) => {
    if (event.reason?.stack?.includes('wasm')) {
      const parsed = parseWasmStack(event.reason, mapper);
      console.log('WASM Unhandled Rejection:');
      console.log(formatStack(parsed));
    }
  });
  
  // Use the wasm instance
  try {
    instance.exports.renderUI();
  } catch (err) {
    const parsed = parseWasmStack(err, mapper);
    console.log(formatStack(parsed));
    // Output will look like:
    // RuntimeError: unreachable
    //     at returnError (main.zig:707)
    //     at callNestedLayouts (Vapor.zig:532)
    //     at renderCycle (Vapor.zig:696)
  }
}

init();
*/

// ============================================================
// DEBUGGING TIP: Check if your wasm has debug info
// ============================================================

export function checkDebugInfo(wasmBytes) {
  const bytes = new Uint8Array(wasmBytes);
  let pos = 8; // Skip magic + version
  
  const sections = [];
  
  while (pos < bytes.length) {
    const sectionId = bytes[pos++];
    
    // Read LEB128 size
    let size = 0;
    let shift = 0;
    while (true) {
      const byte = bytes[pos++];
      size |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) break;
      shift += 7;
    }
    
    if (sectionId === 0) {
      // Custom section - read name
      let nameLen = 0;
      shift = 0;
      while (true) {
        const byte = bytes[pos];
        nameLen |= (byte & 0x7f) << shift;
        pos++;
        if ((byte & 0x80) === 0) break;
        shift += 7;
      }
      
      const nameBytes = bytes.slice(pos, pos + nameLen);
      const name = new TextDecoder().decode(nameBytes);
      
      sections.push({
        type: 'custom',
        name,
        size: size - nameLen - 1 // Approximate data size
      });
      
      pos += size - (pos - (pos - nameLen));
    } else {
      sections.push({
        type: sectionId,
        size
      });
      pos += size;
    }
  }
  
  const debugSections = sections.filter(s => 
    s.type === 'custom' && s.name.startsWith('.debug')
  );
  
  console.log('WASM Debug Sections Found:');
  if (debugSections.length === 0) {
    console.log('  ❌ No debug sections found!');
    console.log('  Make sure you compile with debug flags (-g)');
  } else {
    for (const section of debugSections) {
      console.log(`  ✓ ${section.name} (${section.size} bytes)`);
    }
  }
  
  return debugSections;
}
