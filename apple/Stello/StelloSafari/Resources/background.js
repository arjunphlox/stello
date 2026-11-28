// Stello Safari extension (test build). Passes folder requests to the native handler.
// Messages: { route: "direct" | "relay", cmd: "list" | "read" | "image", folder?, path? }
const send = (msg) => browser.runtime.sendNativeMessage("com.arjunphlox.Stello", msg);

browser.runtime.onMessage.addListener((msg, _sender, reply) => {
  if (!msg || msg.stelloFolder !== true) return false;
  const { stelloFolder, ...request } = msg;
  send(request).then(reply, (e) => reply({ error: String(e && e.message || e) }));
  return true;
});
