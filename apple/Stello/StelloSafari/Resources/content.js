// Lets the Stello web page ask for folder files:
// window.postMessage({ stelloFolderRequest: id, route, cmd, folder, path }, location.origin)
// and listen for { stelloFolderReply: id, ...result }.
window.addEventListener("message", (event) => {
  if (event.source !== window || !event.data || event.data.stelloFolderRequest == null) return;
  const { stelloFolderRequest: id, ...request } = event.data;
  browser.runtime.sendMessage({ stelloFolder: true, ...request }).then(
    (result) => window.postMessage({ stelloFolderReply: id, ...result }, location.origin),
    (e) => window.postMessage({ stelloFolderReply: id, error: String(e && e.message || e) }, location.origin),
  );
});
document.documentElement.dataset.stelloExtension = "0.1";
