import { readWasmString, wasmInstance } from "./wasi_obj.js";
import { env, requireWasm } from "./wasi.js";
import { fileBindings } from "./additionals.js";
// import { cacheEnv } from "./cachebindings.js";

export const importObject = {
  wasi_snapshot_preview1: {
    // === Process ===
    proc_exit: (code) => {
      // console.error("Exiting with code:", code);
    },
    proc_raise: () => 0,
    sched_yield: () => 0,

    // === Clock ===
    clock_res_get: () => 0,
    clock_time_get: (clockId, precision, resultPtr) => {
      const now = BigInt(Date.now()) * 1000000n;
      const view = new DataView(wasmInstance.memory.buffer);
      view.setBigUint64(resultPtr, now, true);
      return 0;
    },

    // === Random ===
    random_get: (bufPtr, bufLen) => {
      const randomBuffer = new Uint8Array(
        wasmInstance.memory.buffer,
        bufPtr,
        bufLen,
      );
      crypto.getRandomValues(randomBuffer);
      return 0;
    },

    // === Args & Environment ===
    args_get: () => 0,
    args_sizes_get: (argc_ptr, argv_buf_size_ptr) => {
      const view = new DataView(wasmInstance.memory.buffer);
      view.setUint32(argc_ptr, 0, true);
      view.setUint32(argv_buf_size_ptr, 0, true);
      return 0;
    },
    environ_get: () => 0,
    environ_sizes_get: (count_ptr, buf_size_ptr) => {
      const view = new DataView(wasmInstance.memory.buffer);
      view.setUint32(count_ptr, 0, true);
      view.setUint32(buf_size_ptr, 0, true);
      return 0;
    },

    // === File Descriptor Operations ===
    fd_advise: () => 0,
    fd_allocate: () => 0,
    fd_close: () => 0,
    fd_datasync: () => 0,
    fd_fdstat_get: (fd, buf_ptr) => {
      const view = new DataView(wasmInstance.memory.buffer);
      // filetype = regular file (4)
      view.setUint8(buf_ptr, 4);
      // fdflags = 0
      view.setUint16(buf_ptr + 2, 0, true);
      // rights_base
      view.setBigUint64(buf_ptr + 8, 0n, true);
      // rights_inheriting
      view.setBigUint64(buf_ptr + 16, 0n, true);
      return 0;
    },
    fd_fdstat_set_flags: () => 0,
    fd_fdstat_set_rights: () => 0,
    fd_filestat_get: (fd, buf_ptr) => {
      return 0;
    },
    fd_filestat_set_size: () => 0,
    fd_filestat_set_times: () => 0,
    fd_pread: () => 0,
    fd_prestat_get: (fd, buf_ptr) => {
      return 8; // EBADF - no preopened dirs
    },
    fd_prestat_dir_name: () => 8, // EBADF
    fd_pwrite: () => 0,
    fd_read: () => 0,
    fd_readdir: () => 0,
    fd_renumber: () => 0,
    fd_seek: () => 0,
    fd_sync: () => 0,
    fd_tell: () => 0,
    fd_write: (fd, iovs_ptr, iovs_len, nwritten_ptr) => {
      // Optional: wire up stdout/stderr to console
      return 0;
    },

    // === Path Operations ===
    path_create_directory: () => 0,
    path_filestat_get: () => 0,
    path_filestat_set_times: () => 0,
    path_link: () => 0,
    path_open: () => {
      console.warn("path_open() called but not implemented in browser");
      return 0;
    },
    path_readlink: () => 0,
    path_remove_directory: () => 0,
    path_rename: () => 0,
    path_symlink: () => 0,
    path_unlink_file: () => 0,

    // === Polling ===
    poll_oneoff: (inSubscriptionsPtr, outEventsPtr, nSubscriptions, neventsPtr) => {
      const CLOCK_TIMEOUT_OFFSET = 24;
      const view = new DataView(wasmInstance.memory.buffer);
      const timeoutNanoSeconds = view.getBigUint64(
        inSubscriptionsPtr + CLOCK_TIMEOUT_OFFSET,
        true,
      );
      const timeoutMillis = Number(timeoutNanoSeconds / 1000000n);
      console.log("Timeout duration (ms):", timeoutMillis);
      new Promise((resolve) => {
        console.log("Starting", timeoutMillis);
        setTimeout(() => {
          console.log(`setTimeout resolved after ${timeoutMillis}ms`);
          promiseResolved = true;
          resolve(0);
        }, timeoutMillis);
      });
      return 0;
    },

    // === Socket (often unused but sometimes imported) ===
    sock_accept: () => 0,
    sock_recv: () => 0,
    sock_send: () => 0,
    sock_shutdown: () => 0,
  },
  env: {
    ...env,
    ...fileBindings,
  },
};
