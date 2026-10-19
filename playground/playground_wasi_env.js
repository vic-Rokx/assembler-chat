import { readWasmString, wasmInstance } from "./playground_obj.js";
import { env, requireWasm } from "./playground_wasi.js";
import { fileBindings } from "./playground_additionals.js";

export const importObject = {
  wasi_snapshot_preview1: {
    proc_exit: (code) => {
      // console.error("Exiting with code:", code);
    },
    clock_time_get: (clockId, precision, resultPtr) => {
      // clock_time_get: (code) => {
      const now = BigInt(Date.now()) * 1000000n;
      const view = new DataView(wasmInstance.memory.buffer);
      view.setBigUint64(resultPtr, now, true);
      return 0;
    },
    path_open: () => {
      console.warn("path_open() called but not implemented in browser");
      return 0; // WASI return code for OK (or adjust as needed)
    },
    poll_oneoff: async (
      inSubscriptionsPtr,
      outEventsPtr,
      nSubscriptions,
      neventsPtr,
    ) => {
      // promiseResolved = false; // Reset before new call
      const CLOCK_TIMEOUT_OFFSET = 24; // Make sure this offset is correct
      const view = new DataView(wasmInstance.memory.buffer);

      // Read timeout from WASM memory
      const timeoutNanoSeconds = view.getBigUint64(
        inSubscriptionsPtr + CLOCK_TIMEOUT_OFFSET,
        true,
      );

      const timeoutMillis = Number(timeoutNanoSeconds / 1000000n);

      console.log("Timeout duration (ms):", timeoutMillis);
      // await sleep(2000);

      // if (is_in_timeout === false) {
      // is_in_timeout = true;
      new Promise((resolve) => {
        console.log("Starting", timeoutMillis);
        setTimeout(() => {
          console.log(`setTimeout resolved after ${timeoutMillis}ms`);
          promiseResolved = true; // Mark as resolved
          resolve(0); // Resolve with success code
        }, timeoutMillis);
      });
      return 0;
    },

    random_get: (bufPtr, bufLen) => {
      const randomBuffer = new Uint8Array(
        wasmInstance.memory.buffer,
        bufPtr,
        bufLen,
      );
      crypto.getRandomValues(randomBuffer);
      return 0;
    },
    fd_write: (fd, iovs_ptr, iovs_len, nwritten_ptr) => {
      // if (requireWasm() === false) return;
      // const memory = new Uint8Array(wasmInstance.memory.buffer);
      // let written = 0;
      //
      // for (let i = 0; i < iovs_len; i++) {
      //   const iov = new Uint32Array(memory.buffer, iovs_ptr + i * 8, 2);
      //   const ptr = iov[0];
      //   const len = iov[1];
      //   const str = readWasmString(ptr, len);
      //
      //   if (fd === 1) {
      //     // stdout
      //     console.log("[Zig stdout]", str);
      //   } else if (fd === 2) {
      //     // stderr
      //     console.log(str);
      //   } else {
      //     console.warn(`[Zig fd ${fd}]`, str);
      //   }
      //
      //   written += len;
      // }
      //
      // // Write the total bytes written back to memory
      // new Uint32Array(memory.buffer)[nwritten_ptr / 4] = written;
      // return 0; // Success
    }, // ADD THIS: Missing fd_filestat_get function
    fd_filestat_get: (fd, buf_ptr) => {
      return 0; // Success
    },

    // Other WASI stubs (minimal implementation)
    fd_close: () => 0,
    fd_pwrite: () => 0,
    fd_pread: () => 0,
    fd_seek: () => 0,
    fd_read: () => { },
    environ_sizes_get: () => 0,
    environ_get: () => 0,
  }, // Link WASI stubs
  env: {
    ...env,
    ...fileBindings,
    // ...cacheEnv,
  },
};
