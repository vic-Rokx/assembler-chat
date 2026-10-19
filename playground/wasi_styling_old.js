/**
 * Create an element based on its type
 * @param {Object} renderCmd - The render command
 * @returns {HTMLElement} - The created element
 */
export function createElementByType(uinode) {
  let element;
  let text;
  let label;
  let route = currentPath === "/" ? "/root" : `/root${currentPath}`;

  switch (uinode.elemType) {
    case COMPONENT_TYPES.TEXT:
      element = document.createElement("p");
      text =
        getTextData(route, uinode.id) ??
        readWasmString(uinode.textPtr, uinode.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.TEXT_GRADIENT:
      element = document.createElement("p");
      element.style.background =
        "-webkit-linear-gradient(45deg, #E04F67, #C72C4A, #4800FF)";
      element.style["-webkit-background-clip"] = "text";
      element.style["-webkit-text-fill-color"] = "transparent";
      element.textContent = uinode.text;
      break;

    case COMPONENT_TYPES.TEXT_AREA:
      const textareaPtr =
        wasmInstance.getTextFieldParams(uinode.nodePtr) >>> 0;
      element = document.createElement("textarea");
      element.lang = "json";
      if (textareaPtr) {
        const fieldCount = wasmInstance.getTextFieldCount(uinode.nodePtr);
        const reader = new DynamicStructReader(
          wasmInstance,
          wasmInstance.memory,
        );
        const fieldStruct = reader.readStruct(
          uinode.nodePtr,
          textareaPtr,
          fieldCount,
          "getTextFieldDescriptor",
        );
        element.value =
          fieldStruct.value !== null ? String(fieldStruct.value) : "";
        element.value =
          fieldStruct.default !== null ? String(fieldStruct.default) : "";
      }
      // text = readWasmString(uinode.textPtr, uinode.textLen);
      // element.textContent = text;
      break;

    case COMPONENT_TYPES.HTML_TEXT:
      element = document.createElement("p");
      text =
        getTextData(route, uinode.id) ??
        readWasmString(uinode.textPtr, uinode.textLen);
      element.innerHTML = text;
      break;

    case COMPONENT_TYPES.CODE:
      element = document.createElement("code");
      text = readWasmString(uinode.textPtr, uinode.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.SPAN:
      element = document.createElement("span");
      text = readWasmString(uinode.textPtr, uinode.textLen);
      element.innerText = text;
      break;

    case COMPONENT_TYPES.JSON_EDITOR:
      element = document.createElement("textarea");
      text = readWasmString(uinode.textPtr, uinode.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.ALLOC_TEXT:
      element = document.createElement("p");
      text = readWasmString(uinode.textPtr, uinode.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.IMAGE:
      element = document.createElement("img");
      const alt = wasmInstance.getAlt(uinode.nodePtr);
      if (alt >>> 0) {
        const length = wasmInstance.getAltLen();
        const altText = readWasmString(alt, length);
        element.setAttribute("alt", altText);
      }
      const src = readWasmString(
        uinode.hrefPtr,
        uinode.hrefLen,
      );
      element.setAttribute("src", src);
      break;

    case COMPONENT_TYPES.LAZY_IMAGE:
      element = document.createElement("img");
      element.src = readWasmString(
        uinode.hrefPtr,
        uinode.hrefLen,
      );
      element.loading = "lazy";
      break;

    case COMPONENT_TYPES.PRE_IMAGE:
      element = document.createElement("img");
      element.src = readWasmString(
        uinode.hrefPtr,
        uinode.hrefLen,
      );
      element.setAttribute("fetchpriority", "high");
      break;

    case COMPONENT_TYPES.INTERSECTION:
      element = document.createElement("section");
      break;

    case COMPONENT_TYPES.FLEXBOX:
    case COMPONENT_TYPES.BOX:
    case COMPONENT_TYPES.BLOCK:
    case COMPONENT_TYPES.DRAGGABLE:
    case COMPONENT_TYPES.GRADIENT:
    case COMPONENT_TYPES.GRAPHIC:
      element = document.createElement("div");
      if (uinode.elemType === COMPONENT_TYPES.GRADIENT) {
        element.style.background =
          "-webkit-linear-gradient(45deg, #8886f2, #e04597, #ee6994)";
      } else if (uinode.elemType === COMPONENT_TYPES.GRAPHIC) {
        const href = readWasmString(
          uinode.hrefPtr,
          uinode.hrefLen,
        );
        fetch(href)
          .then((res) => res.text())
          .then((text) => {
            element.innerHTML = text.replace(/^\s+|\s+$/g, "");
          })
          .catch((err) => {
            // console.error("Fetch failed:", err);
          });
      }
      break;

    case COMPONENT_TYPES.TEXT_FIELD:
      element = document.createElement("input");
      text = readWasmString(uinode.textPtr, uinode.textLen);
      const field_ptr = wasmInstance.getFieldName(uinode.nodePtr) >>> 0;
      if (field_ptr) {
        const field_len = wasmInstance.getFieldNameLen();
        const field = readWasmString(field_ptr, field_len);
        element.name = field;
      }
      const instansePtr = wasmInstance.getTextFieldParams(uinode.nodePtr);
      if (instansePtr) {
        const fieldCount = wasmInstance.getTextFieldCount(uinode.nodePtr);
        const reader = new DynamicStructReader(
          wasmInstance,
          wasmInstance.memory,
        );
        const fieldStruct = reader.readStruct(
          uinode.nodePtr,
          instansePtr,
          fieldCount,
          "getTextFieldDescriptor",
        );
        element.value =
          fieldStruct.default !== null ? String(fieldStruct.default) : "";
        switch (fieldStruct.type) {
          case 0:
            element.type = "number";
            break;
          case 1:
            element.type = "number";
            break;
          case 2:
            element.type = "text";
            break;
          case 3:
            element.type = "checkbox";
            break;
          case 4:
            element.type = "radio";
            break;
          case 5:
            element.type = "password";
            break;
          case 6:
            element.type = "email";
            break;
          case 7:
            element.type = "file";
            break;
          case 8:
            element.type = "tel";
            break;
        }
      }
      break;

    case COMPONENT_TYPES.BUTTON:
    case COMPONENT_TYPES.BUTTON_CYCLE:
      element = document.createElement("button");
      element.type = "button";
      label = wasmInstance.getAriaLabel(uinode.nodePtr);
      if (label) {
        const length = wasmInstance.getAriaLabelLen();
        element.ariaLabel = readWasmString(label, length);
      }
      element.addEventListener("click", async (event) => {
        state.currentDepthNode = uinode.id;
        event.preventDefault();
        event.stopPropagation();
        const idPtr = allocString(uinode.id);
        if (uinode.elemType === COMPONENT_TYPES.BUTTON_CYCLE) {
          wasmInstance.buttonCycleCallback(idPtr);
        } else {
          wasmInstance.buttonCallback(idPtr);
        }
      });
      break;

    case COMPONENT_TYPES.BUTTON_CTX:
      element = document.createElement("button");
      element.type = "button";
      label = wasmInstance.getAriaLabel(uinode.nodePtr);
      if (label) {
        const length = wasmInstance.getAriaLabelLen();
        element.ariaLabel = readWasmString(label, length);
      }
      element.addEventListener("click", (event) => {
        event.preventDefault();
        event.stopPropagation();
        const idPtr = allocString(uinode.id);
        wasmInstance.ctxButtonCallback(idPtr);
      });
      break;

    case COMPONENT_TYPES.SUBMIT_BUTTON:
      element = document.createElement("button");
      element.type = "submit";
      break;

    case COMPONENT_TYPES.HEADER:
      element = document.createElement("h1"); // Will be replaced by HEADING
      text = readWasmString(uinode.textPtr, uinode.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.SVG:
      const svgString =
        getTextData(route, uinode.id) ??
        readWasmString(uinode.textPtr, uinode.textLen);
      const cleanSvg = svgString.replace(/^\s+|\s+$/g, "");
      const parser = new DOMParser();
      const doc = parser.parseFromString(cleanSvg, "image/svg+xml");
      element = doc.documentElement;
      break;

    case COMPONENT_TYPES.LINK:
      element = document.createElement("a");
      element = createLinkElement(element, uinode);
      break;

    case COMPONENT_TYPES.REDIRECT_LINK:
      element = document.createElement("a");
      const aria_label = wasmInstance.getAriaLabel(uinode.nodePtr);
      if (aria_label) {
        const length = wasmInstance.getAriaLabelLen();
        element.ariaLabel = readWasmString(aria_label, length);
      }

      element.href =
        uinode.hrefLen > 0
          ? readWasmString(uinode.hrefPtr, uinode.hrefLen)
          : "";
      break;

    case COMPONENT_TYPES.EMBEDLINK:
    case COMPONENT_TYPES.EMBEDICON:
      element = document.createElement("link");
      element.rel =
        uinode.elemType === COMPONENT_TYPES.EMBEDLINK
          ? "stylesheet"
          : "icon";
      element.crossorigin = "anonymous";
      element.href = readWasmString(
        uinode.hrefPtr,
        renderCmd.props.hrefLen,
      );
      break;

    case COMPONENT_TYPES.ICON:
      element = document.createElement("i");
      break;

    case COMPONENT_TYPES.LIST:
      element = document.createElement("ul");
      break;

    case COMPONENT_TYPES.LISTITEM:
      element = document.createElement("li");
      break;

    case COMPONENT_TYPES.SELECT:
      element = document.createElement("select");
      break;

    case COMPONENT_TYPES.SELECT_ITEM:
      element = document.createElement("option");
      break;

    case COMPONENT_TYPES.LABEL:
      element = document.createElement("label");
      // element.htmlFor = readWasmString(
      //   renderCmd.props.hrefPtr,
      //   renderCmd.props.hrefLen,
      // );
      text = readWasmString(renderCmd.props.textPtr, renderCmd.props.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.FORM:
      element = document.createElement("form");
      element.action = "";
      break;

    case COMPONENT_TYPES.TABLE:
      element = document.createElement("table");
      break;

    case COMPONENT_TYPES.TABLE_ROW:
      element = document.createElement("tr");
      break;

    case COMPONENT_TYPES.TABLE_CELL:
      element = document.createElement("td");
      break;

    case COMPONENT_TYPES.TABLE_HEADER:
      element = document.createElement("th");
      break;

    case COMPONENT_TYPES.TABLE_BODY:
      element = document.createElement("tbody");
      break;

    case COMPONENT_TYPES.CANVAS:
      element = document.createElement("canvas");
      break;

    case COMPONENT_TYPES.HEADING:
      const level = wasmInstance.getHeadingLevel(renderCmd.nodePtr); // Use template literal to create h1-h6, defaulting to h1
      element = document.createElement(
        `h${level > 0 && level < 7 ? level : 1}`,
      );
      text = readWasmString(renderCmd.props.textPtr, renderCmd.props.textLen);
      element.textContent = text;
      break;

    case COMPONENT_TYPES.VIDEO:
      console.log("Video");
      element = document.createElement("video");
      const offset = wasmInstance.getVideo(renderCmd.nodePtr);
      console.log("Offset", offset);
      if (offset === 0) break; // Use break, not return
      const videoView = new DataView(wasmInstance.memory.buffer, offset);
      const srcPtr = videoView.getUint32(0, true);
      if (srcPtr) {
        const srcLen = videoView.getUint32(4, true);
        element.src = readWasmString(srcPtr, srcLen);
      }
      console.log("Src", element.src);
      element.autoplay = videoView.getUint8(8) === 1;
      break;

    case COMPONENT_TYPES.NOOP:
      break;

    default:
      element = document.createElement("div");
      break;
  }

  if (element) {
    element.id = renderCmd.id;
  }
  return element;
}
