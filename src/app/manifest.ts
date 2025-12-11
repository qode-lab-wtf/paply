import { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "paply",
    short_name: "paply",
    description: "Sprachtranskription mit Groq Whisper und Claude Haiku Polish",
    start_url: "/dashboard",
    display: "standalone",
    background_color: "#F5F5F7",
    theme_color: "#4CAF50",
    icons: [
      { src: "/favicon.ico", sizes: "32x32", type: "image/x-icon" },
      { src: "/paply-icon.svg", sizes: "192x192", type: "image/svg+xml" },
    ],
  };
}

