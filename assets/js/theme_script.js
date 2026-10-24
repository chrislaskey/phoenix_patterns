// Sets the daisyUI theme on <html> before the first paint and switches it on
// the `phx:set-theme` events the theme toggle dispatches. The choice is kept
// in localStorage under `phx:theme`, and "system" follows the OS setting.
//
// Not bundled into app.js: it has to run before the page paints, so it's
// written inline instead. Phoenix inlines it in root.html.heex through
// `App.Web.Layouts.theme_script/1`, and the desktop app inlines it with a
// Vite plugin (../../../tauri/vite.config.js). A change here reaches both.
(() => {
  const systemTheme = () => matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";

  const setTheme = (theme) => {
    if (theme === "system") {
      localStorage.removeItem("phx:theme");
      document.documentElement.setAttribute("data-theme", systemTheme());
      document.documentElement.setAttribute("data-theme-source", "system");
    } else {
      localStorage.setItem("phx:theme", theme);
      document.documentElement.setAttribute("data-theme", theme);
      document.documentElement.setAttribute("data-theme-source", "user");
    }
  };
  if (!document.documentElement.hasAttribute("data-theme")) {
    setTheme(localStorage.getItem("phx:theme") || "system");
  }
  window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));
  window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));

  matchMedia("(prefers-color-scheme: dark)").addEventListener("change", (e) => {
    if (document.documentElement.getAttribute("data-theme-source") === "system") {
      document.documentElement.setAttribute("data-theme", systemTheme());
    }
  });
})();
