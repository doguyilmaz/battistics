import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

export default defineConfig({
  site: "https://battistics.apps.doguyilmaz.com",
  trailingSlash: "always",
  integrations: [
    starlight({
      title: "Battistics",
      description: "Battery statistics and Keep Awake for the Mac.",
      logo: { src: "./src/assets/icons/original.png", alt: "" },
      favicon: "/favicon.png",
      head: [
        { tag: "link", attrs: { rel: "apple-touch-icon", href: "/apple-touch-icon.png" } },
        { tag: "link", attrs: { rel: "preload", href: "/fonts/bricolage-latin.woff2", as: "font", type: "font/woff2", crossorigin: "" } },
        { tag: "script", attrs: { src: "/zoom.js", defer: true } },
      ],
      social: [{ icon: "github", label: "Battistics on GitHub", href: "https://github.com/doguyilmaz/battistics" }],
      editLink: { baseUrl: "https://github.com/doguyilmaz/battistics/edit/main/site/" },
      customCss: ["./src/styles/tokens.css", "./src/styles/docs.css"],
      sidebar: [
        { label: "Start", items: ["docs", "docs/install", "docs/menu-bar"] },
        { label: "Battery", items: ["docs/battery/readings", "docs/battery/history", "docs/battery/alerts", "docs/battery/accessories"] },
        { label: "Keep Awake", items: ["docs/keep-awake/modes", "docs/keep-awake/closed-lid", "docs/keep-awake/protection"] },
        { label: "iPhone", items: ["docs/iphone"] },
        { label: "Automation", items: ["docs/automation/terminal", "docs/automation/mcp"] },
        { label: "Help", items: ["docs/privacy", "docs/troubleshooting"] },
      ],
      credits: false,
    }),
  ],
});
