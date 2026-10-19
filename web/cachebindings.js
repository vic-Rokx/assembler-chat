import { wasmInstance } from "./wasi_obj.js";

// ============ host.js (the glue) ============
let cacheModule = undefined;

export async function initCacheModule() {
  const response = await fetch("/cache.wasm"); // cache-bust
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {
    env: {},
  });
  cacheModule = instance;
  console.log("Cache Module loaded", instance);
}

// IndexedDB WASM Bindings
// Helper function assumed to exist
// function readWasmString(wasmInstance, ptr, len) { ... }
// function writeWasmString(wasmInstance, str) { ... } // Returns {ptr, len}

let db = null;
let currentTransaction = null;
let upgradeTransaction = null; // Track upgrade transaction
let pendingResults = new Map();

let resultIdCounter = 0;
let pendingSchemaOps = [];
let upgradeResolve = null;

const indexedDBBindings = {
  // ============ DATABASE OPERATIONS ============

  indexDbOpenWasm: (namePtr, nameLen, version) => {
    const name = readWasmString(wasmInstance, namePtr, nameLen);
    return new Promise((resolve) => {
      const request = window.indexedDB.open(name, version);

      request.onerror = (event) => {
        console.error("IndexedDB open error:", event.target.error);
        resolve(-1);
      };

      request.onupgradeneeded = (event) => {
        db = event.target.result;
        upgradeTransaction = event.target.transaction;

        // Execute any pending schema operations
        for (const op of pendingSchemaOps) {
          try {
            op();
          } catch (e) {
            console.error("Schema operation error:", e);
          }
        }
        pendingSchemaOps = [];

        if (upgradeResolve) {
          upgradeResolve();
          upgradeResolve = null;
        }
      };

      request.onsuccess = (event) => {
        db = event.target.result;
        upgradeTransaction = null;
        db.onerror = (event) => {
          console.error(`Database error: ${event.target.error?.message}`);
        };
        resolve(0);
      };
    });
  },

  // Open with schema definition callback
  // The WASM side should call schema operations after this, then call indexDbOpenCommitWasm
  indexDbOpenWithUpgradeWasm: (namePtr, nameLen, version) => {
    const name = readWasmString(wasmInstance, namePtr, nameLen);

    return new Promise((resolve) => {
      const request = window.indexedDB.open(name, version);

      request.onerror = (event) => {
        console.error("IndexedDB open error:", event.target.error);
        resolve(-1);
      };

      request.onupgradeneeded = (event) => {
        db = event.target.result;
        upgradeTransaction = event.target.transaction;
        // Signal that upgrade is happening - WASM can now create stores
        resolve(1); // 1 = upgrade needed
      };

      request.onsuccess = (event) => {
        db = event.target.result;
        upgradeTransaction = null;
        resolve(0); // 0 = opened successfully, no upgrade needed
      };
    });
  },

  // Queue a store creation for the next database open/upgrade
  indexDbQueueCreateObjectStoreWasm: (
    storeNamePtr,
    storeNameLen,
    keyPathPtr,
    keyPathLen,
    autoIncrement,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const keyPath =
      keyPathLen > 0
        ? readWasmString(wasmInstance, keyPathPtr, keyPathLen)
        : null;

    pendingSchemaOps.push(() => {
      const options = {};
      if (keyPath) options.keyPath = keyPath;
      if (autoIncrement === 1) options.autoIncrement = true;

      if (!db.objectStoreNames.contains(storeName)) {
        db.createObjectStore(storeName, options);
      }
    });

    return 0;
  },

  indexDbCloseWasm: () => {
    if (db) {
      db.close();
      db = null;
      return 0;
    }
    return -1;
  },

  indexDbDeleteDatabaseWasm: (namePtr, nameLen) => {
    const name = readWasmString(wasmInstance, namePtr, nameLen);
    return new Promise((resolve) => {
      const request = window.indexedDB.deleteDatabase(name);
      request.onsuccess = () => resolve(0);
      request.onerror = () => resolve(-1);
    });
  },

  // ============ OBJECT STORE OPERATIONS ============

  // Can only be called during version upgrade
  indexDbCreateObjectStoreWasm: (
    storeNamePtr,
    storeNameLen,
    keyPathPtr,
    keyPathLen,
    autoIncrement,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const keyPath =
      keyPathLen > 0
        ? readWasmString(wasmInstance, keyPathPtr, keyPathLen)
        : null;

    // Check if we're in an upgrade transaction
    if (!upgradeTransaction) {
      console.error(
        "createObjectStore can only be called during version upgrade",
      );
      return -2; // Special error code for "not in upgrade"
    }

    try {
      const options = {};
      if (keyPath) options.keyPath = keyPath;
      if (autoIncrement === 1) options.autoIncrement = true;

      db.createObjectStore(storeName, options);
      return 0;
    } catch (e) {
      console.error("Create object store error:", e);
      return -1;
    }
  },

  indexDbDeleteObjectStoreWasm: (storeNamePtr, storeNameLen) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    try {
      db.deleteObjectStore(storeName);
      return 0;
    } catch (e) {
      console.error("Delete object store error:", e);
      return -1;
    }
  },

  // ============ INDEX OPERATIONS ============

  indexDbCreateIndexWasm: (
    storeNamePtr,
    storeNameLen,
    indexNamePtr,
    indexNameLen,
    keyPathPtr,
    keyPathLen,
    unique,
    multiEntry,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const indexName = readWasmString(wasmInstance, indexNamePtr, indexNameLen);
    const keyPath = readWasmString(wasmInstance, keyPathPtr, keyPathLen);

    try {
      const transaction = db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      store.createIndex(indexName, keyPath, {
        unique: unique === 1,
        multiEntry: multiEntry === 1,
      });
      return 0;
    } catch (e) {
      console.error("Create index error:", e);
      return -1;
    }
  },

  indexDbDeleteIndexWasm: (
    storeNamePtr,
    storeNameLen,
    indexNamePtr,
    indexNameLen,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const indexName = readWasmString(wasmInstance, indexNamePtr, indexNameLen);

    try {
      const transaction = db.transaction(storeName, "readwrite");
      const store = transaction.objectStore(storeName);
      store.deleteIndex(indexName);
      return 0;
    } catch (e) {
      console.error("Delete index error:", e);
      return -1;
    }
  },

  // ============ TRANSACTION OPERATIONS ============

  indexDbBeginTransactionWasm: (storeNamePtr, storeNameLen, mode) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const modeStr = mode === 0 ? "readonly" : "readwrite";

    try {
      currentTransaction = db.transaction(storeName, modeStr);
      return 0;
    } catch (e) {
      console.error("Begin transaction error:", e);
      return -1;
    }
  },

  indexDbCommitTransactionWasm: () => {
    if (currentTransaction) {
      try {
        currentTransaction.commit();
        currentTransaction = null;
        return 0;
      } catch (e) {
        console.error("Commit error:", e);
        return -1;
      }
    }
    return -1;
  },

  indexDbAbortTransactionWasm: () => {
    if (currentTransaction) {
      try {
        currentTransaction.abort();
        currentTransaction = null;
        return 0;
      } catch (e) {
        console.error("Abort error:", e);
        return -1;
      }
    }
    return -1;
  },

  // ============ CRUD OPERATIONS ============

  indexDbPutWasm: (
    storeNamePtr,
    storeNameLen,
    keyPtr,
    keyLen,
    valuePtr,
    valueLen,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const key = readWasmString(wasmInstance, keyPtr, keyLen);
    const value = readWasmString(wasmInstance, valuePtr, valueLen);

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readwrite");
        const store = transaction.objectStore(storeName);
        const data = JSON.parse(value);

        const request = store.put(data, key || undefined);
        request.onsuccess = () => resolve(0);
        request.onerror = () => {
          const ptr = allocString(
            wasmInstance,
            request.error?.message || "Unknown error",
          );
          wasmInstance.addError(ptr);
          resolve(-1);
        };
      } catch (e) {
        console.error("Put error:", e);
        const ptr = allocString(wasmInstance, e.message || "Unknown error");
        wasmInstance.addError(ptr);
        resolve(-1);
      }
    });
  },

  indexDbAddWasm: (storeNamePtr, storeNameLen, valuePtr, valueLen) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const value = readWasmString(wasmInstance, valuePtr, valueLen);

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readwrite");
        const store = transaction.objectStore(storeName);
        const data = JSON.parse(value);

        const request = store.add(data);
        request.onsuccess = () => resolve(0);
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Add error:", e);
        resolve(-1);
      }
    });
  },

  indexDbGetWasm: (storeNamePtr, storeNameLen, keyPtr, keyLen, resultIdPtr) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const key = readWasmString(wasmInstance, keyPtr, keyLen);
    const resultId = resultIdCounter++;

    // Write result ID back to WASM memory
    new Uint32Array(wasmInstance.memory.buffer, resultIdPtr, 1)[0] = resultId;

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);

        const request = store.get(key);
        request.onsuccess = () => {
          console.log("Get success", request.result);
          const data = JSON.stringify(request.result);
          const ptr = allocString(wasmInstance, data);
          wasmInstance.updateResponse(ptr);
          pendingResults.set(resultId, request.result);
          resolve(0);
        };
        request.onerror = () => {
          const ptr = allocString(
            wasmInstance,
            request.error?.message || "Unknown error",
          );
          wasmInstance.addError(ptr);
          resolve(-1);
        };
      } catch (e) {
        console.error("Get error:", e);
        const ptr = allocString(wasmInstance, e.message);
        wasmInstance.addError(ptr);
        resolve(-1);
      }
    });
  },

  indexDbGetResultWasm: (resultId, bufferPtr, bufferLen) => {
    const result = pendingResults.get(resultId);
    if (result === undefined) return -1;

    const json = JSON.stringify(result);
    const encoder = new TextEncoder();
    const bytes = encoder.encode(json);

    if (bytes.length > bufferLen) return -2; // Buffer too small

    const memory = new Uint8Array(
      wasmInstance.exports.memory.buffer,
      bufferPtr,
      bufferLen,
    );
    memory.set(bytes);

    pendingResults.delete(resultId);
    return bytes.length;
  },

  indexDbGetAllWasm: (storeNamePtr, storeNameLen, resultIdPtr) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const resultId = resultIdCounter++;

    new Uint32Array(wasmInstance.memory.buffer, resultIdPtr, 1)[0] = resultId;

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);

        const request = store.getAll();
        request.onsuccess = () => {
          pendingResults.set(resultId, request.result);
          console.log("GetAll", request.result);
          const data = JSON.stringify(request.result);
          const ptr = allocString(wasmInstance, data);
          wasmInstance.returnAll(ptr);
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("GetAll error:", e);
        resolve(-1);
      }
    });
  },

  indexDbDeleteWasm: (storeNamePtr, storeNameLen, keyPtr, keyLen) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const key = readWasmString(wasmInstance, keyPtr, keyLen);

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readwrite");
        const store = transaction.objectStore(storeName);

        const request = store.delete(key);
        request.onsuccess = () => resolve(0);
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Delete error:", e);
        resolve(-1);
      }
    });
  },

  indexDbClearWasm: (storeNamePtr, storeNameLen) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readwrite");
        const store = transaction.objectStore(storeName);

        const request = store.clear();
        request.onsuccess = () => resolve(0);
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Clear error:", e);
        resolve(-1);
      }
    });
  },

  indexDbCountWasm: (storeNamePtr, storeNameLen, countPtr) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);

        const request = store.count();
        request.onsuccess = () => {
          new Uint32Array(wasmInstance.exports.memory.buffer, countPtr, 1)[0] =
            request.result;
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Count error:", e);
        resolve(-1);
      }
    });
  },

  // ============ INDEX QUERY OPERATIONS ============

  indexDbGetByIndexWasm: (
    storeNamePtr,
    storeNameLen,
    indexNamePtr,
    indexNameLen,
    keyPtr,
    keyLen,
    resultIdPtr,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const indexName = readWasmString(wasmInstance, indexNamePtr, indexNameLen);
    const key = readWasmString(wasmInstance, keyPtr, keyLen);
    const resultId = resultIdCounter++;

    new Uint32Array(wasmInstance.exports.memory.buffer, resultIdPtr, 1)[0] =
      resultId;

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);
        const index = store.index(indexName);

        const request = index.get(key);
        request.onsuccess = () => {
          pendingResults.set(resultId, request.result);
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Get by index error:", e);
        resolve(-1);
      }
    });
  },

  indexDbGetAllByIndexWasm: (
    storeNamePtr,
    storeNameLen,
    indexNamePtr,
    indexNameLen,
    keyPtr,
    keyLen,
    resultIdPtr,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const indexName = readWasmString(wasmInstance, indexNamePtr, indexNameLen);
    const key =
      keyLen > 0 ? readWasmString(wasmInstance, keyPtr, keyLen) : null;
    const resultId = resultIdCounter++;

    new Uint32Array(wasmInstance.exports.memory.buffer, resultIdPtr, 1)[0] =
      resultId;

    return new Promise((resolve) => {
      try {
        const transaction =
          currentTransaction || db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);
        const index = store.index(indexName);

        const request = key ? index.getAll(key) : index.getAll();
        request.onsuccess = () => {
          pendingResults.set(resultId, request.result);
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Get all by index error:", e);
        resolve(-1);
      }
    });
  },

  // ============ CURSOR OPERATIONS ============

  indexDbOpenCursorWasm: (
    storeNamePtr,
    storeNameLen,
    direction,
    cursorIdPtr,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const directionStr = direction === 0 ? "next" : "prev";
    const cursorId = resultIdCounter++;

    new Uint32Array(wasmInstance.exports.memory.buffer, cursorIdPtr, 1)[0] =
      cursorId;

    return new Promise((resolve) => {
      try {
        const transaction = db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);

        const request = store.openCursor(null, directionStr);
        request.onsuccess = (event) => {
          pendingResults.set(cursorId, event.target.result);
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Open cursor error:", e);
        resolve(-1);
      }
    });
  },

  indexDbCursorContinueWasm: (cursorId) => {
    const cursor = pendingResults.get(cursorId);
    if (!cursor) return -1;

    return new Promise((resolve) => {
      cursor.continue();
      cursor.request.onsuccess = (event) => {
        pendingResults.set(cursorId, event.target.result);
        resolve(event.target.result ? 0 : 1); // 1 = end of cursor
      };
    });
  },

  indexDbCursorGetValueWasm: (cursorId, bufferPtr, bufferLen) => {
    const cursor = pendingResults.get(cursorId);
    if (!cursor) return -1;

    const json = JSON.stringify(cursor.value);
    const encoder = new TextEncoder();
    const bytes = encoder.encode(json);

    if (bytes.length > bufferLen) return -2;

    const memory = new Uint8Array(
      wasmInstance.exports.memory.buffer,
      bufferPtr,
      bufferLen,
    );
    memory.set(bytes);

    return bytes.length;
  },

  indexDbCursorGetKeyWasm: (cursorId, bufferPtr, bufferLen) => {
    const cursor = pendingResults.get(cursorId);
    if (!cursor) return -1;

    const keyStr = String(cursor.key);
    const encoder = new TextEncoder();
    const bytes = encoder.encode(keyStr);

    if (bytes.length > bufferLen) return -2;

    const memory = new Uint8Array(
      wasmInstance.exports.memory.buffer,
      bufferPtr,
      bufferLen,
    );
    memory.set(bytes);

    return bytes.length;
  },

  // ============ RANGE QUERY OPERATIONS ============

  indexDbGetRangeWasm: (
    storeNamePtr,
    storeNameLen,
    lowerPtr,
    lowerLen,
    upperPtr,
    upperLen,
    lowerOpen,
    upperOpen,
    resultIdPtr,
  ) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    const lower =
      lowerLen > 0 ? readWasmString(wasmInstance, lowerPtr, lowerLen) : null;
    const upper =
      upperLen > 0 ? readWasmString(wasmInstance, upperPtr, upperLen) : null;
    const resultId = resultIdCounter++;

    new Uint32Array(wasmInstance.exports.memory.buffer, resultIdPtr, 1)[0] =
      resultId;

    return new Promise((resolve) => {
      try {
        const transaction = db.transaction(storeName, "readonly");
        const store = transaction.objectStore(storeName);

        let range;
        if (lower && upper) {
          range = IDBKeyRange.bound(
            lower,
            upper,
            lowerOpen === 1,
            upperOpen === 1,
          );
        } else if (lower) {
          range = IDBKeyRange.lowerBound(lower, lowerOpen === 1);
        } else if (upper) {
          range = IDBKeyRange.upperBound(upper, upperOpen === 1);
        }

        const request = store.getAll(range);
        request.onsuccess = () => {
          pendingResults.set(resultId, request.result);
          resolve(0);
        };
        request.onerror = () => resolve(-1);
      } catch (e) {
        console.error("Get range error:", e);
        resolve(-1);
      }
    });
  },

  // ============ UTILITY OPERATIONS ============

  indexDbFreeResultWasm: (resultId) => {
    return pendingResults.delete(resultId) ? 0 : -1;
  },

  indexDbObjectStoreExistsWasm: (storeNamePtr, storeNameLen) => {
    const storeName = readWasmString(wasmInstance, storeNamePtr, storeNameLen);
    return db && db.objectStoreNames.contains(storeName) ? 1 : 0;
  },

  indexDbGetVersionWasm: () => {
    return db ? db.version : -1;
  },
};

const cacheBindings = {
  db_getWasm: async (filePtr, fileLen, keyPtr, keyLen, outPtr, outMax) => {
    const cache = cacheModule.exports;
    // Read key from sync module's memory
    const key = readWasmString(wasmInstance, keyPtr, keyLen);
    const filename = readWasmString(wasmInstance, filePtr, fileLen);

    // Allocate in cache module, copy key there
    // const cacheKeyPtr = cache.alloc(keyLen);
    // const cacheMem = new Uint8Array(cache.memory.buffer);
    // cacheMem.set(key, cacheKeyPtr);
    const cacheKeyPtr = allocString(cache, key);

    // Allocate output buffer in cache module
    const cacheOutPtr = cache.allocUint8(outMax);

    // Call cache_get
    const result = cache.cache_get(cacheKeyPtr, keyLen, cacheOutPtr, outMax);
    console.log("Cache get result", result, cacheOutPtr);

    // If successful, copy result back to sync module
    if (result > 0) {
      const value = readWasmString(cache, cacheOutPtr, result);

      // Create/get a file
      const root = await navigator.storage.getDirectory();
      const fileHandle = await root.getFileHandle(filename, {
        create: true,
      });
      // Read from it
      const file = await fileHandle.getFile();
      const contents = await file.text();
      console.log(contents); // Free (cache_set dupes internally)

      const buffer = new TextEncoder().encode(value);
      const slice = new Uint8Array(
        wasmInstance.memory.buffer, // memory exported from Zig
        outPtr,
        buffer.length + 1,
      );
      // syncMem.set(value, outPtr);
      slice.set(buffer);
      // const pointer = instance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
    }

    // Free cache module allocations
    cache.dealloc(cacheKeyPtr, keyLen);
    cache.dealloc(cacheOutPtr, outMax);

    return result;
  },

  db_setWasm: async (filePtr, fileLen, keyPtr, keyLen, valPtr, valLen) => {
    const cache = cacheModule.exports;

    // Read from sync module
    const key = readWasmString(wasmInstance, keyPtr, keyLen);
    const val = readWasmString(wasmInstance, valPtr, valLen);
    const file = readWasmString(wasmInstance, filePtr, fileLen);

    // Allocate and copy to cache module
    // const cacheMem = new Uint8Array(cache.memory.buffer);
    const cacheKeyPtr = allocString(cache, key);
    const cacheValPtr = allocString(cache, val);

    // Call cache_set
    const result = cache.cache_set(cacheKeyPtr, keyLen, cacheValPtr, valLen);

    const root = await navigator.storage.getDirectory();

    // Create/get a file
    const fileHandle = await root.getFileHandle(file, {
      create: true,
    });
    // Write to it
    const writable = await fileHandle.createWritable();
    await writable.write(val);
    await writable.close();
    //
    // // Read from it
    // const file = await fileHandle.getFile();
    // const contents = await file.text();
    // console.log(contents); // Free (cache_set dupes internally)

    cache.dealloc(cacheKeyPtr, keyLen);
    cache.dealloc(cacheValPtr, valLen);

    return result;
  },

  db_clearWasm: async () => {
    const root = await navigator.storage.getDirectory();

    // Remove all entries
    for await (const [name, handle] of root.entries()) {
      await root.removeEntry(name, { recursive: true });
    }
  },

  db_openWasm: async (filenamePtr, filenameLen) => {
    const filename = readWasmString(wasmInstance, filenamePtr, filenameLen);
    const root = await navigator.storage.getDirectory();
    const handle = root.getFileHandle(filename, { create: true });
    return handle;
  },
  ...indexedDBBindings,
};

export const cacheEnv = {
  ...cacheBindings,
};

const allocString = (instance, string) => {
  const buffer = new TextEncoder().encode(string);
  const pointer = instance.allocUint8(buffer.length + 1); // ask Zig to allocate memory
  const slice = new Uint8Array(
    instance.memory.buffer, // memory exported from Zig
    pointer,
    buffer.length + 1,
  );
  slice.set(buffer);
  slice[buffer.length] = 0; // null byte to null-terminate the string
  return pointer;
};

const textDecoder = new TextDecoder();
function readWasmString(instance, ptr, len) {
  const bytes = new Uint8Array(instance.memory.buffer, ptr, len);
  return textDecoder.decode(bytes);
}
