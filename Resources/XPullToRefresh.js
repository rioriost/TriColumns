(() => {
  "use strict";

  if (window.top !== window || !/(^|\.)x\.com$/i.test(location.hostname)) {
    return;
  }

  if (window.__triColumnsPullToRefreshInstalled) {
    return;
  }
  window.__triColumnsPullToRefreshInstalled = true;

  const pullThreshold = 72;
  const gestureResetDelay = 500;
  const triggerCooldown = 1200;
  const topTolerance = 2;
  const newPostsPattern = /^(see new posts|show [\d,]+ posts?|new posts|新しいポスト(?:を表示)?|[\d,]+件のポストを表示)$/i;

  let accumulatedPull = 0;
  let lastWheelTime = 0;
  let coolingDown = false;

  const isVisible = element => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 &&
      rect.bottom >= 0 && rect.top <= Math.min(innerHeight, 240) &&
      style.display !== "none" && style.visibility !== "hidden";
  };

  const isUnsafeToRefresh = () => {
    const active = document.activeElement;
    const editing = active && (
      active.isContentEditable ||
      active.matches("textarea, input:not([type='button']):not([type='submit']), select")
    );
    const hasFiles = Array.from(document.querySelectorAll("input[type='file']"))
      .some(input => input.files && input.files.length > 0);
    const hasVisibleDialog = Array.from(document.querySelectorAll("[role='dialog']"))
      .some(isVisible);
    const playingMedia = Array.from(document.querySelectorAll("audio, video"))
      .some(media => !media.paused && !media.ended);
    return editing || hasFiles || hasVisibleDialog || playingMedia;
  };

  const isAtTop = event => {
    const root = document.scrollingElement || document.documentElement;
    if ((root?.scrollTop || window.scrollY || 0) > topTolerance) {
      return false;
    }

    const nestedScroller = event.composedPath().find(node => {
      if (!(node instanceof HTMLElement) || node === document.body || node === root) {
        return false;
      }
      const style = getComputedStyle(node);
      return /(auto|scroll)/.test(style.overflowY) && node.scrollHeight > node.clientHeight + topTolerance;
    });
    return !nestedScroller || nestedScroller.scrollTop <= topTolerance;
  };

  const findNewPostsButton = () => Array.from(
    document.querySelectorAll("button, [role='button']")
  ).find(element => {
    const label = (element.getAttribute("aria-label") || element.innerText || element.textContent || "")
      .replace(/\s+/g, " ")
      .trim();
    return label.length <= 80 && newPostsPattern.test(label) && isVisible(element);
  });

  const normalizedDelta = event => {
    if (event.deltaMode === WheelEvent.DOM_DELTA_LINE) {
      return event.deltaY * 16;
    }
    if (event.deltaMode === WheelEvent.DOM_DELTA_PAGE) {
      return event.deltaY * innerHeight;
    }
    return event.deltaY;
  };

  addEventListener("wheel", event => {
    if (event.ctrlKey || coolingDown) {
      return;
    }

    if (!(event.target instanceof Element) || !event.target.closest("main")) {
      accumulatedPull = 0;
      return;
    }

    const delta = normalizedDelta(event);
    const now = performance.now();
    if (now - lastWheelTime > gestureResetDelay) {
      accumulatedPull = 0;
    }
    lastWheelTime = now;

    if (delta >= 0 || !isAtTop(event)) {
      accumulatedPull = 0;
      return;
    }

    accumulatedPull += -delta;
    if (accumulatedPull < pullThreshold) {
      return;
    }

    accumulatedPull = 0;
    if (isUnsafeToRefresh()) {
      return;
    }

    const button = findNewPostsButton();
    if (!button) {
      return;
    }

    coolingDown = true;
    requestAnimationFrame(() => button.click());
    setTimeout(() => coolingDown = false, triggerCooldown);
  }, { capture: true, passive: true });
})();
