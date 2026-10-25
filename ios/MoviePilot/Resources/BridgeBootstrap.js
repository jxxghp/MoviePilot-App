(() => {
  "use strict";
  if (window.top !== window || window.MoviePilotNative) return;
  const handler = window.webkit?.messageHandlers?.moviepilotChrome;
  if (!handler) return;
  Object.defineProperty(window, "MoviePilotNative", {
    value: Object.freeze({
      transportVersion: 1,
      panelsVersion: 1,
      panelFeedsVersion: 1,
      sheetsVersion: 1,
      progressSheetsVersion: 1,
      confirmationsVersion: 1,
      navigationPreviewVersion: 1,
      readonlyCacheVersion: 1,
      /*__MOVIEPILOT_WIDGETS_CAPABILITY__*/
      notificationInstallation: "__MOVIEPILOT_INSTALLATION__",
      postMessage: (message) => handler.postMessage(message),
      authenticationRequired: () => window.webkit.messageHandlers.moviepilotAuthentication.postMessage({version: 1, type: "required"}),
    }),
    configurable: false,
    writable: false,
  });
})();
