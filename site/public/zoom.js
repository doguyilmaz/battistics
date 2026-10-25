// Click any picture in the docs to see it full size; Escape or a click closes it.
(() => {
  const dialog = document.createElement("dialog");
  dialog.className = "zoom";
  dialog.innerHTML = '<img alt=""><p></p>';
  document.addEventListener("DOMContentLoaded", () => document.body.append(dialog));
  document.addEventListener("click", (event) => {
    const image = event.target.closest(".sl-markdown-content img");
    if (image) {
      dialog.querySelector("img").src = image.currentSrc || image.src;
      dialog.querySelector("p").textContent = image.alt;
      dialog.showModal();
    } else if (event.target === dialog || event.target.closest("dialog.zoom")) {
      dialog.close();
    }
  });
})();
