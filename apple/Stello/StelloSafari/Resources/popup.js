document.getElementById("open").addEventListener("click", async () => {
  await browser.tabs.create({ url: browser.runtime.getURL("test.html") });
  window.close();
});
