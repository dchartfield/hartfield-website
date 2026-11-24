// Small progressive enhancements. Every page works without this file.
(function () {
  // Current year in the footer copyright line.
  var year = String(new Date().getFullYear());
  document.querySelectorAll("[data-year]").forEach(function (el) {
    el.textContent = year;
  });

  // Mark the current page in the header nav.
  var here = location.pathname.split("/").pop() || "index.html";
  document.querySelectorAll(".site-nav a").forEach(function (a) {
    var target = a.getAttribute("href").split("#")[0] || "index.html";
    if (target === here && a.getAttribute("href").indexOf("#") === -1) {
      a.setAttribute("aria-current", "page");
    }
  });

  // The opt-in example on sms.html is illustrative only; never submit it.
  document.querySelectorAll("form[data-example]").forEach(function (form) {
    form.addEventListener("submit", function (e) { e.preventDefault(); });
  });
})();
