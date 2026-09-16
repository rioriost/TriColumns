(() => {
  "use strict";

  // Install at document start in every frame in WKContentWorld "TriColumnsSafety".
  // Dirty state belongs to this document and is deliberately never cleared by blur,
  // form reset, or SPA navigation. Only a new document gets a clean tracker.
  if (globalThis.__triColumnsRefreshSafety) {
    return;
  }

  let dirty = false;
  const observedRoots = new WeakSet();
  const nonEditingInputTypes = new Set(["button", "submit", "reset", "image", "hidden"]);
  const textInputTypes = new Set([
    "text", "search", "email", "url", "tel", "password", "number",
    "date", "datetime-local", "month", "week", "time"
  ]);

  const isEditor = element => element instanceof Element && (
    element.isContentEditable ||
    element.matches("textarea, select, [data-testid^='tweetTextarea_']") ||
    (element instanceof HTMLInputElement && !nonEditingInputTypes.has(element.type))
  );

  const recordEdit = event => {
    // The target alone can be a shadow host, not the control that was edited.
    if (event.composedPath().some(isEditor)) {
      dirty = true;
    }
  };

  const observeShadows = node => {
    if (node instanceof Element && node.shadowRoot) {
      observeRoot(node.shadowRoot);
    }
    if (node.querySelectorAll) {
      for (const element of node.querySelectorAll("*")) {
        if (element.shadowRoot) {
          observeRoot(element.shadowRoot);
        }
      }
    }
  };

  const observer = new MutationObserver(records => {
    for (const record of records) {
      for (const node of record.addedNodes) {
        observeShadows(node);
      }
    }
  });

  const observeRoot = root => {
    if (observedRoots.has(root)) {
      return;
    }
    observedRoots.add(root);
    root.addEventListener("input", recordEdit, true);
    root.addEventListener("change", recordEdit, true);
    observer.observe(root, { childList: true, subtree: true });
    observeShadows(root);
  };
  observeRoot(document);

  const hasText = element => (
    element.value || element.innerText || element.textContent || ""
  ).trim().length > 0;

  const isRenderedDialog = element => {
    const style = getComputedStyle(element);
    // Unlike the new-posts button gate, dialogs need not be near the viewport top.
    return style.display !== "none" &&
      style.visibility !== "hidden" && style.visibility !== "collapse" &&
      (style.display === "contents" || element.getClientRects().length > 0);
  };

  const isUnsafe = () => {
    try {
      if (dirty) {
        return true;
      }
      const roots = [document];
      for (let index = 0; index < roots.length; index += 1) {
        const root = roots[index];
        observeRoot(root);
        if (isEditor(root.activeElement)) {
          return true;
        }
        for (const element of root.querySelectorAll("*")) {
          // Even an apparently empty/same-origin frame may contain state not
          // observable here. Any iframe/frame blocks automatic refresh, including
          // cross-origin frames; no cross-origin messaging or DOM access is used.
          if (element.matches("iframe, frame")) {
            return true;
          }
          if (element.shadowRoot) {
            roots.push(element.shadowRoot);
          } else if (element.localName.includes("-") || element.hasAttribute("is")) {
            // Closed roots cannot be discovered reliably from an isolated world.
            // Opaque custom elements fail closed; ordinary React/HTML elements
            // (including X's normal div-based UI) do not trigger this policy.
            return true;
          }
          if ((element.isContentEditable ||
               element.matches("textarea, [data-testid^='tweetTextarea_']") ||
               (element instanceof HTMLInputElement && textInputTypes.has(element.type))) &&
              hasText(element)) {
            return true;
          }
          if (element instanceof HTMLInputElement &&
              element.type === "file" && element.files?.length > 0) {
            return true;
          }
          if ((element instanceof HTMLDialogElement && element.open) ||
              (element.matches("[role~='dialog'], [role~='alertdialog']") &&
               isRenderedDialog(element))) {
            return true;
          }
          if (element instanceof HTMLMediaElement && !element.paused && !element.ended) {
            return true;
          }
        }
      }
      return false;
    } catch {
      return true;
    }
  };

  const documentID = Array.from(
    crypto.getRandomValues(new Uint32Array(4)),
    value => value.toString(16).padStart(8, "0")
  ).join("");
  Object.defineProperty(globalThis, "__triColumnsRefreshSafety", {
    value: Object.freeze({ isUnsafe, documentID }),
    writable: false,
    configurable: false
  });
})();
