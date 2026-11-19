import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "CloudScale Lab",
  description: "Load Balancing and Auto-scaling Demonstrator on AWS",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
