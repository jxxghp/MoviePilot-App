/* MoviePilot language bootstrap v1 */
(() => {
  "use strict";
  const settings = /*__MOVIEPILOT_LANGUAGE__*/;
  const supported = ["zh-CN", "zh-TW", "en-US"];
  const handler = window.webkit?.messageHandlers?.moviepilotLanguage;
  if (window.top !== window || location.origin !== new URL(settings.origin).origin || !handler) return;
  let previous;
  // Only an explicit native selection replaces an existing instance preference.
  // A failed write leaves the native pending selection available for the next load.
  try {
    const saved = localStorage.getItem("MP_LOCALE");
    const selected = supported.includes(settings.selected) ? settings.selected : undefined;
    const locale = selected ?? (supported.includes(saved) ? saved : settings.fallback);
    if (supported.includes(locale)) localStorage.setItem("MP_LOCALE", locale);
  } catch { return; }

  // Vue writes MP_LOCALE before html.lang. Never report an unrelated initial HTML
  // attribute or an unpersisted value as confirmation of the user's selection.
  function report(fromHTML) {
    try {
      const saved = localStorage.getItem("MP_LOCALE");
      if (!supported.includes(saved) || (fromHTML && document.documentElement.lang !== saved) || saved === previous) return;
      previous = saved;
      handler.postMessage({ version: 1, type: "changed", locale: saved });
    } catch { /* Storage disabled: preserve the pending native preference. */ }
  }
  function observe() {
    if (!document.documentElement) return;
    new MutationObserver(() => report(true)).observe(document.documentElement, {
      attributes: true, attributeFilter: ["lang"],
    });
    report(false);
  }
  if (document.documentElement) observe();
  else document.addEventListener("DOMContentLoaded", observe, { once: true });
})();
