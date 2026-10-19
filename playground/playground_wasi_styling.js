import {
  wasmInstance,
  styleSheet,
  readWasmString,
  rebuildCacheFromStylesheet,
} from "./playground_obj.js";

export const styleRuleCache = new Map(); // Track rule indices for fast updates
export const styleClassCache = {}; // Track rule indices for fast updates
export function addKeyframesToStylesheet(keyframesCSS) {
  // // Get or create stylesheet
  // const styleSheet =
  //   document.styleSheets[0] ||
  //   document.head.appendChild(document.createElement("style")).sheet;
  //
  // // Insert keyframes rule into the stylesheet
  // styleSheet.insertRule(keyframesCSS, styleSheet.cssRules.length);
}

export function batchRemoveTombStones() {
  // console.log("batchRemoveTombStones");
  const tombstoneCount = wasmInstance.getTombstoneCount();
  if (tombstoneCount === 0) return;

  // Collect classNames to remove
  const toRemove = new Set();
  for (let i = 0; i < tombstoneCount; i++) {
    const ptr = wasmInstance.getTombstoneClassNamePtr(i);
    if (ptr === 0) continue;
    const len = wasmInstance.getTombstoneClassNameLength(i);
    const className = `.${readWasmString(ptr, len)}`;
    toRemove.add(className);
  }

  // Collect all rules we want to keep
  const rulesToKeep = [];
  for (let i = 0; i < styleSheet.cssRules.length; i++) {
    const rule = styleSheet.cssRules[i];
    const selector = rule.selectorText;
    // Check base selector (without :hover etc) against toRemove
    const baseSelector = selector ? selector.split(":")[0] : null;

    if (!selector || !toRemove.has(baseSelector)) {
      rulesToKeep.push(rule.cssText);
    }
  }

  // Rebuild stylesheet
  styleSheet.replaceSync(rulesToKeep.join("\n"));

  // Rebuild cache
  rebuildCacheFromStylesheet();

  wasmInstance.clearTombstones();
}

export let cacheHits = 0;
export let cacheMisses = 0;

const processedStyleIds = new Set();
// Function to add or update a component's style
export function updateComponentStyle(
  nodePtr,
  specified_className,
  styleString,
  element,
) {
  if (specified_className.length === 0) {
    element.setAttribute("class", "");
    return;
  }

  // Fast path: if we've seen this exact styleId combo before, just set class and return
  if (processedStyleIds.has(specified_className)) {
    element.setAttribute("class", specified_className);
    return specified_className;
  }

  let className = specified_className;

  const style_slice = className.split(" ");

  while (true) {
    className = style_slice.pop();

    if (className === undefined) {
      break;
    }
    if (className.length === 0) continue;

    if (!styleRuleCache.has(`.${className}`)) {
      cacheMisses++;
      if (className.startsWith("vis_")) {
        const ptr = wasmInstance.getVisualStyle(nodePtr, 3);
        const len = wasmInstance.getVisualLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("pos_")) {
        const ptr = wasmInstance.getPositionStyle(nodePtr, 3);
        const len = wasmInstance.getPositionLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("lay_")) {
        const ptr = wasmInstance.getLayoutStyle(nodePtr, 3);
        const len = wasmInstance.getLayoutLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("intr_")) {
        const ptr = wasmInstance.getVisualStyle(nodePtr, 0);
        const len = wasmInstance.getVisualLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className}:hover { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("mapa_")) {
        const ptr = wasmInstance.getMapaStyle(nodePtr, 0);
        const len = wasmInstance.getMapaLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("anim_")) {
        const ptr = wasmInstance.getAnimationStyle(nodePtr, 0);
        const len = wasmInstance.getAnimationLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (className.startsWith("tran_")) {
        const ptr = wasmInstance.getTransformsStyle(nodePtr, 0);
        const len = wasmInstance.getTransformsLen();
        const css = readWasmString(ptr, len);
        const newIndex = styleSheet.cssRules.length;
        styleSheet.insertRule(`.${className} { ${css} }`, newIndex);
        styleRuleCache.set(`.${className}`, newIndex);
      } else if (specified_className.length > 0) {
        const ruleIndex = styleRuleCache.get(`.${className}`);
        if (ruleIndex === undefined) {
          const cssStylePtr = wasmInstance.getStyle(nodePtr);
          if (cssStylePtr !== 0) {
            const cssStyleLen = wasmInstance.getStyleLen();
            styleString = readWasmString(cssStylePtr, cssStyleLen);
          }

          const newIndex = styleSheet.cssRules.length;
          styleSheet.insertRule(`.${className} { ${styleString} }`, newIndex);
          styleRuleCache.set(`.${className}`, newIndex);
        } else {
          // styleSheet.deleteRule(ruleIndex);
          // styleSheet.insertRule(`.${className} { ${styleString} }`, ruleIndex);
        }

        const inherited_ptr = wasmInstance.getInheritedStyle(nodePtr);
        if (inherited_ptr !== 0) {
          const inherited_len = wasmInstance.getInheritedLen();
          const ruleString = readWasmString(inherited_ptr, inherited_len);
          const braceIndex = ruleString.indexOf("{");
          const selector = ruleString.slice(0, braceIndex).trim();

          // Now you can check the cache
          const newIndex = styleSheet.cssRules.length;
          if (!styleRuleCache.has(selector)) {
            styleSheet.insertRule(ruleString, newIndex);
            styleRuleCache.set(selector, newIndex);
          }
        }

        const intr_ptr = wasmInstance.getVisualStyle(nodePtr, 0);
        const intr_len = wasmInstance.getVisualLen();
        const intr_css = readWasmString(intr_ptr, intr_len);

        const intr_index = styleRuleCache.get(`.${className}:hover`);
        if (intr_index === undefined) {
          const new_intr_newIndex = styleSheet.cssRules.length;
          styleSheet.insertRule(
            `.${className}:hover { ${intr_css} }`,
            new_intr_newIndex,
          );
          styleRuleCache.set(`.${className}:hover`, new_intr_newIndex);
        } else {
          styleSheet.deleteRule(intr_index);
          styleSheet.insertRule(
            `.${className}:hover { ${intr_css} }`,
            intr_index,
          );
        }
      }
    } else if (element.localName !== "i" && specified_className.length > 0) {
      cacheHits++;
      const hasVisual = className.startsWith("vis_");
      const hasPosition = className.startsWith("pos_");
      const hasLayout = className.startsWith("lay_");
      const hasInteractive = className.startsWith("intr_");
      const hasMapa = className.startsWith("mapa_");
      const hasAnimation = className.startsWith("anim_");
      const hasTransform = className.startsWith("tran_");
      const hasAny =
        hasVisual ||
        hasPosition ||
        hasLayout ||
        hasInteractive ||
        hasMapa ||
        hasAnimation ||
        hasTransform;
      // This means we have named class set by the user
      if (!hasAny) {
        const ruleIndex = styleRuleCache.get(`.${className}`);
        const cssStylePtr = wasmInstance.getStyle(nodePtr);

        if (cssStylePtr !== 0) {
          const cssStyleLen = wasmInstance.getStyleLen();
          styleString = readWasmString(cssStylePtr, cssStyleLen);
        }
        if (ruleIndex === undefined) {
          const newIndex = styleSheet.cssRules.length;
          styleSheet.insertRule(`.${className} { ${styleString} }`, newIndex);
        } else {
          styleSheet.deleteRule(ruleIndex);
          styleSheet.insertRule(`.${className} { ${styleString} }`, ruleIndex);
        }
      }
      // This breaks the markdown
    }
  }
  // Here we check if the user specfied a class name
  // Apply class to element

  processedStyleIds.add(specified_className);
  element.setAttribute("class", specified_className);
  return specified_className;
}

// Function to add or update a component's style
export function setRuleStyle(specified_className, element) {
  let className = "";
  if (specified_className.length > 0) {
    className = specified_className;
  }
  if (element.localName === "svg") {
    // Add new rule
    // const newIndex = styleSheet.cssRules.length;
    // styleSheet.insertRule(`.${className} { ${styleString} }`, newIndex);
    // styleRuleCache.set(className, newIndex);

    // 2. Conditionally hide the scrollbar in WebKit if showScrollBar() === 0
    // if (wasmInstance.showScrollBar(nodePtr) === 0) {
    //   const webkitRule = `.${className}::-webkit-scrollbar {  display: none; }`;
    //   styleSheet.insertRule(webkitRule, styleSheet.cssRules.length);
    // }
    // element.className = className;
    element.setAttribute("class", className);
    // element.classList.add(className);
    return;
  }
  // Here we check if the user specfied a class name
  if (styleRuleCache.has(className)) {
    // Update existing rule
    // const ruleIndex = styleRuleCache.get(className);
    // To ensure proper update, delete and re-insert
    // styleSheet.deleteRule(ruleIndex);
    // styleSheet.insertRule(`.${className} { ${styleString} }`, ruleIndex);
    element.className = className;
  } else if (
    specified_className.length > 0 &&
    styleRuleCache.has(specified_className)
  ) {
    className = specified_className;
    element.className = className;
    // Update existing rule
    // const ruleIndex = styleRuleCache.get(className);
    // styleSheet.deleteRule(ruleIndex);
    // styleSheet.insertRule(`.${className} { ${styleString} }`, ruleIndex);
    // Here we check if the user specfied a class name
  } else if (
    element.className.length === 0 &&
    specified_className.length === 0
  ) {
    // Add new rule
    // const newIndex = styleSheet.cssRules.length;
    // styleSheet.insertRule(`.${className} { ${styleString} }`, newIndex);
    // styleRuleCache.set(className, newIndex);

    // 2. Conditionally hide the scrollbar in WebKit if showScrollBar() === 0
    // if (wasmInstance.showScrollBar(nodePtr) === 0) {
    //   const webkitRule = `.${className}::-webkit-scrollbar {  display: none; }`;
    //   styleSheet.insertRule(webkitRule, styleSheet.cssRules.length);
    // }
    element.className = className;
  } else if (specified_className.length > 0 && element.localName !== "i") {
    if (specified_className.includes("-gk")) {
      specified_className = `${specified_className}`;
    } else {
      className = specified_className;
    }
    // element.class = className;
    // element.style = styleString;
    // const newIndex = styleSheet.cssRules.length;
    // styleSheet.insertRule(`.${className} { ${styleString} }`, newIndex);
    // styleRuleCache.set(className, newIndex);
    element.className = specified_className;
  } else {
    // This is for icons
    className = element.className;
    // element.style = styleString;
    // const newIndex = styleSheet.cssRules.length;
    // styleSheet.insertRule(
    //   `.${className.split(" ").pop()} { ${styleString} }`,
    //   newIndex,
    // );
    // styleRuleCache.set(className, newIndex);
  }

  // Apply class to element

  return className;
}

export function checkMarkStyling(id, element, styleId, checkmarkstyle) {
  if (styleId.length > 0) {
    styleId = "." + styleId;
  }
  // const className = `check-mark-${Math.random().toString(36).substr(2, 9)}`;
  const className = `${id}`;
  // const className = `hover-${element.id}`;

  // Check if we already have this class
  if (styleRuleCache.has(className)) {
    // Update existing rule
    // const ruleIndex = styleRuleCache.get(className);
    // styleSheet.deleteRule(ruleIndex);
    // styleSheet.insertRule(
    //   `.${className} { ${checkmarkstyle} }`,
    //   ruleIndex,
    // );
  } else {
    try {
      // const checkmarkCSS = `.${className}:checked::after {${checkmarkstyle}}`;

      const checkedStyle = `.${className}:checked {${checkmarkstyle}}`;
      const checkedAfter = `.${className}:checked::after {
                                        content: '';
                                        position: absolute;
                                        top: 50%;
                                        left: 50%;
                                        transform: translate(-50%, -50%);
                                        width: 10px;
                                        height: 10px;
                                        border-radius: 50%;
                                        ${checkmarkstyle}
                                    }`;

      // 4. Insert the rule
      styleSheet.insertRule(checkedStyle, styleSheet.cssRules.length);
      styleSheet.insertRule(checkedAfter, styleSheet.cssRules.length);
      // 5. Apply the class to your element
      // styleRuleCache.set(className, newIndex);
      element.classList.add(className);
    } catch (error) {
      console.error("Failed to add CSS rule:", error);
      console.log("Attempted CSS:", checkedStyle);
    }
  }
}

export function applyTooltipClass(element, styleId, tooltipStyles) {
  // Determine the correct selector
  let selectorAfter = `.${styleId}::after`;
  let selectorHoverAfter = `.${styleId}:hover::after`;

  // Check if we already have this class
  if (styleRuleCache.has(selectorAfter)) {
    // Update existing rule
    const ruleIndex = styleRuleCache.get(selectorAfter);
    const hoverCSS = `${selectorAfter} { ${tooltipStyles} }`;
    styleSheet.deleteRule(ruleIndex);
    styleSheet.insertRule(hoverCSS, ruleIndex);
  } else {
    // Define and insert the hover rule
    const tooltipCSS = `${selectorAfter} { ${tooltipStyles} }`;
    const tooltipCSSHover = `${selectorHoverAfter} { opacity: 1; transition-delay: 0.5s; }`;
    const newIndex = styleSheet.cssRules.length;
    styleSheet.insertRule(tooltipCSS, newIndex);
    styleRuleCache.set(selectorAfter, newIndex);
    styleSheet.insertRule(tooltipCSSHover, newIndex);
    styleRuleCache.set(selectorHoverAfter, newIndex + 1);
  }
}

export function applyHoverClass(element, styleId, hoverStyles) {
  const styleName = `hover-${element.id}`;

  // Determine the correct selector
  let selector;
  if (
    styleId.length > 0 &&
    !styleId.includes("-gk") &&
    !styleId.includes("common-")
  ) {
    // If styleId is provided, we need to target the element with this class
    // when the parent is hovered
    selector = `.${element.className}:hover ${styleId.startsWith(".") ? styleId : "." + styleId}`;
  } else {
    // If no styleId, apply hover directly to the element
    if (element.localName === "i") {
      selector = `.${element.className.split(" ").pop()}:hover`;
    } else if (element.localName === "svg") {
      const svgClassName = element.classList.item(0);
      const parts = svgClassName.split(" ");
      const className = parts[0];
      selector = `.${className}:hover`;
    } else {
      const parts = element.className.split(" ");
      const className = parts[0];
      selector = `.${className}:hover`;
    }
  }

  // Check if we already have this class
  if (styleRuleCache.has(styleName)) {
    // Update existing rule
    const ruleIndex = styleRuleCache.get(styleName);
    const hoverCSS = `${selector} { ${hoverStyles} }`;
    styleSheet.deleteRule(ruleIndex);
    styleSheet.insertRule(hoverCSS, ruleIndex);
  } else {
    // Define and insert the hover rule
    const hoverCSS = `${selector} { ${hoverStyles} }`;
    const newIndex = styleSheet.cssRules.length;
    styleSheet.insertRule(hoverCSS, newIndex);
    // Cache the rule
    styleRuleCache.set(styleName, newIndex);
  }
}

export function applyFocusClass(element, styleId, focusStyles) {
  const styleName = `focus-${element.id}`;

  // Determine the correct selector
  let selector;
  if (styleId.length > 0) {
    // If styleId is provided, we need to target the element with this class
    // when the parent is hovered
    selector = `.${element.className}:focus-within ${styleId.startsWith(".") ? styleId : "." + styleId}`;
  } else {
    // If no styleId, apply hover directly to the element
    if (element.localName === "i") {
      selector = `.${element.className.split(" ").pop()}:focus-within`;
    } else {
      selector = `.${element.className}:focus-within`;
    }
  }

  // Check if we already have this class
  if (styleRuleCache.has(styleName)) {
    // Update existing rule
    const ruleIndex = styleRuleCache.get(styleName);
    const focusCSS = `${selector} { ${focusStyles} }`;
    styleSheet.deleteRule(ruleIndex);
    styleSheet.insertRule(focusCSS, ruleIndex);
  } else {
    // Define and insert the hover rule
    const focusCSS = `${selector} { ${focusStyles} }`;
    const newIndex = styleSheet.cssRules.length;
    styleSheet.insertRule(focusCSS, newIndex);
    // Cache the rule
    styleRuleCache.set(styleName, newIndex);
  }
}

export function applyFocusWithinClass(element, styleId, focusWithinStyles) {
  const styleName = `focus-within-${element.id}`;

  // Determine the correct selector
  let selector;
  if (styleId.length > 0) {
    // If styleId is provided, we need to target the element with this class
    // when the parent is hovered
    selector = `.${element.className}:focus-within ${styleId.startsWith(".") ? styleId : "." + styleId}`;
  } else {
    // If no styleId, apply hover directly to the element
    if (element.localName === "i") {
      selector = `.${element.className.split(" ").pop()}:focus-within`;
    } else {
      selector = `.${element.className}:focus-within`;
    }
  }

  // Check if we already have this class
  if (styleRuleCache.has(styleName)) {
    // Update existing rule
    const ruleIndex = styleRuleCache.get(styleName);
    const focuseWithinCss = `${selector} { ${focusWithinStyles} }`;
    styleSheet.deleteRule(ruleIndex);
    styleSheet.insertRule(focuseWithinCss, ruleIndex);
  } else {
    // Define and insert the hover rule
    const focuseWithinCss = `${selector} { ${focusWithinStyles} }`;
    const newIndex = styleSheet.cssRules.length;
    styleSheet.insertRule(focuseWithinCss, newIndex);
    // Cache the rule
    styleRuleCache.set(styleName, newIndex);
  }
}
