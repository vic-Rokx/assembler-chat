/**
 * Minimal DWARF .debug_line Parser for WebAssembly
 * 
 * This parses the .debug_line section from a wasm file to build a mapping
 * from wasm code offsets to source file:line locations.
 * 
 * Usage:
 *   const mapper = new WasmSourceMapper(wasmBytes);
 *   const location = mapper.lookup(0x1e1fd);
 *   // => { file: "main.zig", line: 707, column: 0 }
 */

class WasmSourceMapper {
  constructor(wasmBytes) {
    this.bytes = new Uint8Array(wasmBytes);
    this.pos = 0;
    this.lineInfo = []; // Array of { address, file, line, column }
    this.files = [];
    this.directories = [];
    
    this._parseWasm();
  }

  // ============================================================
  // WASM PARSING - Extract custom sections
  // ============================================================
  
  _parseWasm() {
    // Check wasm magic number: \0asm
    if (this.bytes[0] !== 0x00 || this.bytes[1] !== 0x61 ||
        this.bytes[2] !== 0x73 || this.bytes[3] !== 0x6d) {
      throw new Error('Not a valid wasm file');
    }
    
    // Skip magic (4 bytes) + version (4 bytes)
    this.pos = 8;
    
    while (this.pos < this.bytes.length) {
      const sectionId = this._readU8();
      const sectionSize = this._readLEB128U();
      const sectionEnd = this.pos + sectionSize;
      
      if (sectionId === 0) { // Custom section
        const nameLen = this._readLEB128U();
        const nameBytes = this.bytes.slice(this.pos, this.pos + nameLen);
        const name = new TextDecoder().decode(nameBytes);
        this.pos += nameLen;
        
        if (name === '.debug_line') {
          const dataLen = sectionEnd - this.pos;
          const debugLineData = this.bytes.slice(this.pos, sectionEnd);
          this._parseDebugLine(debugLineData);
        }
      }
      
      this.pos = sectionEnd;
    }
    
    // Sort by address for binary search
    this.lineInfo.sort((a, b) => a.address - b.address);
  }

  // ============================================================
  // LEB128 DECODING
  // ============================================================
  
  _readU8() {
    return this.bytes[this.pos++];
  }
  
  _readU8At(data, offset) {
    return data[offset];
  }
  
  _readLEB128U() {
    let result = 0;
    let shift = 0;
    while (true) {
      const byte = this.bytes[this.pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) break;
      shift += 7;
    }
    return result;
  }
  
  _readLEB128UFrom(data, offsetObj) {
    let result = 0;
    let shift = 0;
    while (true) {
      const byte = data[offsetObj.pos++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) === 0) break;
      shift += 7;
    }
    return result;
  }
  
  _readLEB128SFrom(data, offsetObj) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
      byte = data[offsetObj.pos++];
      result |= (byte & 0x7f) << shift;
      shift += 7;
    } while ((byte & 0x80) !== 0);
    
    // Sign extend if negative
    if (shift < 32 && (byte & 0x40) !== 0) {
      result |= (~0 << shift);
    }
    return result;
  }

  // ============================================================
  // DWARF .debug_line PARSING
  // ============================================================
  
  _parseDebugLine(data) {
    const ctx = { pos: 0 };
    
    while (ctx.pos < data.length) {
      this._parseLineNumberProgram(data, ctx);
    }
  }
  
  _parseLineNumberProgram(data, ctx) {
    const unitStart = ctx.pos;
    
    // Unit header
    let unitLength = this._read32(data, ctx);
    let is64bit = false;
    
    if (unitLength === 0xffffffff) {
      // 64-bit DWARF format
      unitLength = this._read64(data, ctx);
      is64bit = true;
    }
    
    const unitEnd = ctx.pos + unitLength;
    const version = this._read16(data, ctx);
    
    // DWARF 5 has address_size and segment_selector_size before header_length
    let addressSize = 4; // Default for wasm
    let segmentSelectorSize = 0;
    
    if (version >= 5) {
      addressSize = data[ctx.pos++];
      segmentSelectorSize = data[ctx.pos++];
    }
    
    const headerLength = is64bit ? this._read64(data, ctx) : this._read32(data, ctx);
    const programStart = ctx.pos + headerLength;
    
    // Line number program header
    const minInstructionLength = data[ctx.pos++];
    
    let maxOpsPerInstruction = 1;
    if (version >= 4) {
      maxOpsPerInstruction = data[ctx.pos++];
    }
    
    const defaultIsStmt = data[ctx.pos++];
    const lineBase = this._toSigned8(data[ctx.pos++]);
    const lineRange = data[ctx.pos++];
    const opcodeBase = data[ctx.pos++];
    
    // Standard opcode lengths
    const stdOpcodeLengths = [0]; // Index 0 unused
    for (let i = 1; i < opcodeBase; i++) {
      stdOpcodeLengths.push(data[ctx.pos++]);
    }
    
    // Parse directories and files based on DWARF version
    const directories = ['.']; // Index 0 is current directory
    const files = [{ name: '', dirIndex: 0 }]; // Index 0 unused in DWARF 4
    
    if (version < 5) {
      // DWARF 4: null-terminated strings
      // Directories
      while (data[ctx.pos] !== 0) {
        const dir = this._readString(data, ctx);
        directories.push(dir);
      }
      ctx.pos++; // Skip terminating 0
      
      // Files
      while (data[ctx.pos] !== 0) {
        const name = this._readString(data, ctx);
        const dirIndex = this._readLEB128UFrom(data, ctx);
        const modTime = this._readLEB128UFrom(data, ctx);
        const fileSize = this._readLEB128UFrom(data, ctx);
        files.push({ name, dirIndex });
      }
      ctx.pos++; // Skip terminating 0
    } else {
      // DWARF 5: entry format based
      const dirEntryFormatCount = data[ctx.pos++];
      const dirEntryFormat = [];
      for (let i = 0; i < dirEntryFormatCount; i++) {
        dirEntryFormat.push({
          contentType: this._readLEB128UFrom(data, ctx),
          form: this._readLEB128UFrom(data, ctx)
        });
      }
      
      const dirCount = this._readLEB128UFrom(data, ctx);
      for (let i = 0; i < dirCount; i++) {
        let dirName = '.';
        for (const entry of dirEntryFormat) {
          const value = this._readFormValue(data, ctx, entry.form, is64bit);
          if (entry.contentType === 0x01) { // DW_LNCT_path
            dirName = value;
          }
        }
        if (i === 0) {
          directories[0] = dirName;
        } else {
          directories.push(dirName);
        }
      }
      
      const fileEntryFormatCount = data[ctx.pos++];
      const fileEntryFormat = [];
      for (let i = 0; i < fileEntryFormatCount; i++) {
        fileEntryFormat.push({
          contentType: this._readLEB128UFrom(data, ctx),
          form: this._readLEB128UFrom(data, ctx)
        });
      }
      
      const fileCount = this._readLEB128UFrom(data, ctx);
      for (let i = 0; i < fileCount; i++) {
        let fileName = '';
        let dirIndex = 0;
        for (const entry of fileEntryFormat) {
          const value = this._readFormValue(data, ctx, entry.form, is64bit);
          if (entry.contentType === 0x01) { // DW_LNCT_path
            fileName = value;
          } else if (entry.contentType === 0x02) { // DW_LNCT_directory_index
            dirIndex = value;
          }
        }
        if (i === 0) {
          files[0] = { name: fileName, dirIndex };
        } else {
          files.push({ name: fileName, dirIndex });
        }
      }
    }
    
    // Store for later use
    this.directories = directories;
    this.files = files;
    
    // Move to program start
    ctx.pos = programStart;
    
    // Execute the line number program (state machine)
    this._executeLineProgram(data, ctx, unitEnd, {
      minInstructionLength,
      maxOpsPerInstruction,
      defaultIsStmt,
      lineBase,
      lineRange,
      opcodeBase,
      stdOpcodeLengths,
      files,
      directories
    });
    
    ctx.pos = unitEnd;
  }
  
  _executeLineProgram(data, ctx, unitEnd, header) {
    // Initial state machine registers
    let address = 0;
    let opIndex = 0;
    let file = 1;
    let line = 1;
    let column = 0;
    let isStmt = header.defaultIsStmt !== 0;
    let basicBlock = false;
    let endSequence = false;
    let prologueEnd = false;
    let epilogueBegin = false;
    let isa = 0;
    let discriminator = 0;
    
    const {
      minInstructionLength,
      maxOpsPerInstruction,
      lineBase,
      lineRange,
      opcodeBase,
      stdOpcodeLengths,
      files,
      directories
    } = header;
    
    while (ctx.pos < unitEnd) {
      const opcode = data[ctx.pos++];
      
      if (opcode === 0) {
        // Extended opcode
        const extLen = this._readLEB128UFrom(data, ctx);
        const extEnd = ctx.pos + extLen;
        const extOpcode = data[ctx.pos++];
        
        switch (extOpcode) {
          case 0x01: // DW_LNE_end_sequence
            endSequence = true;
            this._emitRow(address, file, line, column, files, directories);
            // Reset state
            address = 0;
            opIndex = 0;
            file = 1;
            line = 1;
            column = 0;
            isStmt = header.defaultIsStmt !== 0;
            basicBlock = false;
            endSequence = false;
            prologueEnd = false;
            epilogueBegin = false;
            isa = 0;
            discriminator = 0;
            break;
            
          case 0x02: // DW_LNE_set_address
            address = this._readAddress(data, ctx, extEnd - ctx.pos);
            opIndex = 0;
            break;
            
          case 0x03: // DW_LNE_define_file (DWARF 4)
            const fileName = this._readString(data, ctx);
            const dirIndex = this._readLEB128UFrom(data, ctx);
            this._readLEB128UFrom(data, ctx); // mod time
            this._readLEB128UFrom(data, ctx); // file size
            files.push({ name: fileName, dirIndex });
            break;
            
          case 0x04: // DW_LNE_set_discriminator
            discriminator = this._readLEB128UFrom(data, ctx);
            break;
            
          default:
            // Skip unknown extended opcodes
            break;
        }
        
        ctx.pos = extEnd;
        
      } else if (opcode < opcodeBase) {
        // Standard opcode
        switch (opcode) {
          case 0x01: // DW_LNS_copy
            this._emitRow(address, file, line, column, files, directories);
            discriminator = 0;
            basicBlock = false;
            prologueEnd = false;
            epilogueBegin = false;
            break;
            
          case 0x02: // DW_LNS_advance_pc
            const adv = this._readLEB128UFrom(data, ctx);
            address += minInstructionLength * ((opIndex + adv) / maxOpsPerInstruction) | 0;
            opIndex = (opIndex + adv) % maxOpsPerInstruction;
            break;
            
          case 0x03: // DW_LNS_advance_line
            line += this._readLEB128SFrom(data, ctx);
            break;
            
          case 0x04: // DW_LNS_set_file
            file = this._readLEB128UFrom(data, ctx);
            break;
            
          case 0x05: // DW_LNS_set_column
            column = this._readLEB128UFrom(data, ctx);
            break;
            
          case 0x06: // DW_LNS_negate_stmt
            isStmt = !isStmt;
            break;
            
          case 0x07: // DW_LNS_set_basic_block
            basicBlock = true;
            break;
            
          case 0x08: // DW_LNS_const_add_pc
            const adjustedOpcode = 255 - opcodeBase;
            const opAdvance = adjustedOpcode / lineRange | 0;
            address += minInstructionLength * ((opIndex + opAdvance) / maxOpsPerInstruction) | 0;
            opIndex = (opIndex + opAdvance) % maxOpsPerInstruction;
            break;
            
          case 0x09: // DW_LNS_fixed_advance_pc
            address += this._read16(data, ctx);
            opIndex = 0;
            break;
            
          case 0x0a: // DW_LNS_set_prologue_end
            prologueEnd = true;
            break;
            
          case 0x0b: // DW_LNS_set_epilogue_begin
            epilogueBegin = true;
            break;
            
          case 0x0c: // DW_LNS_set_isa
            isa = this._readLEB128UFrom(data, ctx);
            break;
            
          default:
            // Skip unknown standard opcodes based on their documented length
            for (let i = 0; i < stdOpcodeLengths[opcode]; i++) {
              this._readLEB128UFrom(data, ctx);
            }
            break;
        }
        
      } else {
        // Special opcode
        const adjustedOpcode = opcode - opcodeBase;
        const opAdvance = adjustedOpcode / lineRange | 0;
        const lineIncrement = lineBase + (adjustedOpcode % lineRange);
        
        address += minInstructionLength * ((opIndex + opAdvance) / maxOpsPerInstruction) | 0;
        opIndex = (opIndex + opAdvance) % maxOpsPerInstruction;
        line += lineIncrement;
        
        this._emitRow(address, file, line, column, files, directories);
        
        basicBlock = false;
        prologueEnd = false;
        epilogueBegin = false;
        discriminator = 0;
      }
    }
  }
  
  _emitRow(address, fileIndex, line, column, files, directories) {
    const fileEntry = files[fileIndex] || { name: 'unknown', dirIndex: 0 };
    const dir = directories[fileEntry.dirIndex] || '.';
    
    // Build full path
    let fullPath = fileEntry.name;
    if (dir && dir !== '.' && !fileEntry.name.startsWith('/')) {
      fullPath = dir + '/' + fileEntry.name;
    }
    
    // Extract just the filename for convenience
    const fileName = fileEntry.name.split('/').pop();
    
    this.lineInfo.push({
      address,
      file: fileName,
      fullPath,
      line,
      column
    });
  }

  // ============================================================
  // HELPER METHODS
  // ============================================================
  
  _read16(data, ctx) {
    const val = data[ctx.pos] | (data[ctx.pos + 1] << 8);
    ctx.pos += 2;
    return val;
  }
  
  _read32(data, ctx) {
    const val = data[ctx.pos] |
                (data[ctx.pos + 1] << 8) |
                (data[ctx.pos + 2] << 16) |
                (data[ctx.pos + 3] << 24);
    ctx.pos += 4;
    return val >>> 0; // Convert to unsigned
  }
  
  _read64(data, ctx) {
    // For simplicity, we'll assume values fit in 53 bits (JS safe integer)
    const low = this._read32(data, ctx);
    const high = this._read32(data, ctx);
    return low + high * 0x100000000;
  }
  
  _readAddress(data, ctx, size) {
    if (size === 4) {
      return this._read32(data, ctx);
    } else if (size === 8) {
      return this._read64(data, ctx);
    } else {
      // Variable size, read as many bytes as we have
      let val = 0;
      for (let i = 0; i < size; i++) {
        val |= data[ctx.pos++] << (i * 8);
      }
      return val >>> 0;
    }
  }
  
  _readString(data, ctx) {
    const start = ctx.pos;
    while (data[ctx.pos] !== 0) {
      ctx.pos++;
    }
    const str = new TextDecoder().decode(data.slice(start, ctx.pos));
    ctx.pos++; // Skip null terminator
    return str;
  }
  
  _readFormValue(data, ctx, form, is64bit) {
    // Handle common DWARF form types
    switch (form) {
      case 0x08: // DW_FORM_string
        return this._readString(data, ctx);
        
      case 0x0e: // DW_FORM_strp (offset into .debug_str)
        // We'd need .debug_str section - for now return placeholder
        const strpOffset = is64bit ? this._read64(data, ctx) : this._read32(data, ctx);
        return `<strp:${strpOffset}>`;
        
      case 0x1f: // DW_FORM_line_strp (DWARF 5, offset into .debug_line_str)
        const lineStrpOffset = is64bit ? this._read64(data, ctx) : this._read32(data, ctx);
        return `<line_strp:${lineStrpOffset}>`;
        
      case 0x0b: // DW_FORM_data1
        return data[ctx.pos++];
        
      case 0x05: // DW_FORM_data2
        return this._read16(data, ctx);
        
      case 0x06: // DW_FORM_data4
        return this._read32(data, ctx);
        
      case 0x0f: // DW_FORM_udata
        return this._readLEB128UFrom(data, ctx);
        
      default:
        console.warn(`Unknown DWARF form: 0x${form.toString(16)}`);
        return 0;
    }
  }
  
  _toSigned8(val) {
    return val > 127 ? val - 256 : val;
  }

  // ============================================================
  // PUBLIC API
  // ============================================================
  
  /**
   * Look up source location for a wasm code offset
   * @param {number} offset - The wasm code offset (e.g., 0x1e1fd)
   * @returns {{ file: string, fullPath: string, line: number, column: number } | null}
   */
  lookup(offset) {
    if (this.lineInfo.length === 0) {
      return null;
    }
    
    // Binary search for the largest address <= offset
    let low = 0;
    let high = this.lineInfo.length - 1;
    let result = null;
    
    while (low <= high) {
      const mid = (low + high) >>> 1;
      const entry = this.lineInfo[mid];
      
      if (entry.address <= offset) {
        result = entry;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    
    return result;
  }
  
  /**
   * Get all line info entries
   * @returns {Array<{ address: number, file: string, fullPath: string, line: number, column: number }>}
   */
  getAllLineInfo() {
    return this.lineInfo;
  }
  
  /**
   * Enhance a wasm error stack trace with source locations
   * @param {Error} error 
   * @returns {{ name: string, message: string, frames: Array }}
   */
  enhanceError(error) {
    const stack = error.stack || '';
    const lines = stack.split('\n');
    
    const frames = [];
    
    for (const line of lines) {
      // Match: wasm-function[123]:0x1abc
      const wasmMatch = line.match(/wasm-function\[(\d+)\]:0x([0-9a-f]+)/i);
      
      if (wasmMatch) {
        const funcIndex = parseInt(wasmMatch[1], 10);
        const offset = parseInt(wasmMatch[2], 16);
        const location = this.lookup(offset);
        
        // Try to extract function name from the line
        const funcNameMatch = line.match(/at\s+(?:[\w.]+\.)?(\w+)\s*\(/);
        const funcName = funcNameMatch ? funcNameMatch[1] : `wasm_func_${funcIndex}`;
        
        if (location) {
          frames.push({
            func: funcName,
            file: location.file,
            fullPath: location.fullPath,
            line: location.line,
            column: location.column,
            wasmOffset: offset,
            wasmFuncIndex: funcIndex
          });
        } else {
          frames.push({
            func: funcName,
            file: 'unknown',
            fullPath: 'unknown',
            line: 0,
            column: 0,
            wasmOffset: offset,
            wasmFuncIndex: funcIndex
          });
        }
      }
    }
    
    return {
      name: error.name,
      message: error.message,
      frames
    };
  }
  
  /**
   * Format an enhanced error as a readable string
   * @param {{ name: string, message: string, frames: Array }} enhanced 
   * @returns {string}
   */
  formatError(enhanced) {
    let result = `${enhanced.name}: ${enhanced.message}\n`;
    
    for (const frame of enhanced.frames) {
      result += `    at ${frame.func} (${frame.file}:${frame.line}:${frame.column})\n`;
    }
    
    return result;
  }
}

// ============================================================
// USAGE EXAMPLE
// ============================================================

/*
// In browser:
async function setupWasmDebugger(wasmUrl) {
  const response = await fetch(wasmUrl);
  const bytes = await response.arrayBuffer();
  
  // Create mapper
  const mapper = new WasmSourceMapper(bytes);
  
  // Now instantiate wasm
  const module = await WebAssembly.compile(bytes);
  const instance = await WebAssembly.instantiate(module, imports);
  
  // Later, when catching errors:
  try {
    instance.exports.someFunction();
  } catch (err) {
    const enhanced = mapper.enhanceError(err);
    console.log(mapper.formatError(enhanced));
    // Output:
    // RuntimeError: unreachable
    //     at returnError (main.zig:707:0)
    //     at callNestedLayouts (Vapor.zig:532:0)
    //     ...
  }
  
  return { instance, mapper };
}
*/

// Export for different environments
if (typeof module !== 'undefined' && module.exports) {
  module.exports = { WasmSourceMapper };
}

if (typeof window !== 'undefined') {
  window.WasmSourceMapper = WasmSourceMapper;
}

export { WasmSourceMapper };
