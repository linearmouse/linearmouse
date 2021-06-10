const favicon = document.createElement("link");
favicon.rel = "icon";
favicon.type = "image/svg+xml";
const updateFavicon = () => {
  if (matchMedia && matchMedia("(prefers-color-scheme: dark)").matches) {
    favicon.href = "favicon-dark.svg";
  } else {
    favicon.href = "favicon.svg";
  }
  document.head.append(favicon);
};
updateFavicon();
matchMedia("(prefers-color-scheme: dark)").addEventListener("change", () => void updateFavicon());
