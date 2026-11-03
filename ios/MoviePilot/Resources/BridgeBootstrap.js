(() => {
  "use strict";
  if (window.top !== window || window.MoviePilotNative) return;
  const handler = window.webkit?.messageHandlers?.moviepilotChrome;
  if (!handler) return;
  // Keep the existing wallpaper renderer alive beneath the native directory. The
  // active-chrome guard also restores HTML content if negotiation falls back.
  function postMessage(message) {
    if (message.type === "navigation.state" && document.documentElement) {
      document.documentElement.dataset.nativeContent =
        ["menu", "search"].includes(message.payload?.chrome?.content) ? message.payload.chrome.content : "web";
    }
    handler.postMessage(message);
  }
  // Hide the replaced HTML directory and the floating assistant entry/pet; global
  // wallpaper and Sheet layers keep their original rendering, timers, theme
  // treatment and viewport. The assistant layers live outside
  // .layout-page-content, so they would otherwise stay visible beneath the
  // native directory while UIKit intercepts every tap.
  function installMenuBackdropStyle() {
    const style = document.createElement("style");
    style.textContent = `
      html[data-native-chrome="active"]:is([data-native-content="menu"], [data-native-content="search"]):not([data-native-sheet]) .layout-page-content {
        visibility: hidden !important;
        pointer-events: none !important;
      }
      /* 助手入口与形象经 Teleport 挂在 body 上，不属于被替换的正文；原生目录会拦截全部
         触控，继续显示只会成为看得到却点不到的浮层，因此与系统 Sheet 一致地整层移除。 */
      html[data-native-chrome="active"]:is([data-native-content="menu"], [data-native-content="search"]):not([data-native-sheet]) :is(.agent-assistant-fab, .agent-pet-stage-layer) {
        display: none !important;
      }
    `;
    document.documentElement.appendChild(style);
  }
  if (document.documentElement) installMenuBackdropStyle();
  else document.addEventListener("DOMContentLoaded", installMenuBackdropStyle, { once: true });
  Object.defineProperty(window, "MoviePilotNative", {
    value: Object.freeze({
      transportVersion: 1,
      panelsVersion: 1,
      searchPageVersion: 1,
      panelFeedsVersion: 1,
      sheetsVersion: 1,
      progressSheetsVersion: 1,
      confirmationsVersion: 1,
      navigationPreviewVersion: 1,
      readonlyCacheVersion: 1,
      cardMenusVersion: 1,
      standaloneMenusVersion: 1,
      /*__MOVIEPILOT_WIDGETS_CAPABILITY__*/
      notificationInstallation: "__MOVIEPILOT_INSTALLATION__",
      postMessage,
      authenticationRequired: () => window.webkit.messageHandlers.moviepilotAuthentication.postMessage({version: 1, type: "required"}),
    }),
    configurable: false,
    writable: false,
  });
})();
