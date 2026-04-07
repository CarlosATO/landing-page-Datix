import { Inter, Geist_Mono } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
  display: "swap",
});

const geistMono = Geist_Mono({
  variable: "--font-geist-mono",
  subsets: ["latin"],
});

export const metadata = {
  title: "Datix — De la información al éxito | ERP para Negocios Locales",
  description:
    "Controla tu inventario, agiliza tus ventas y gestiona tus compras en un solo lugar. Datix es el sistema ERP diseñado para negocios locales en Chile y Latinoamérica.",
  keywords: [
    "ERP",
    "punto de venta",
    "inventario",
    "gestión empresarial",
    "Chile",
    "SaaS",
    "Datix",
  ],
  openGraph: {
    title: "Datix — ERP para Negocios Locales",
    description:
      "Controla tu inventario, agiliza tus ventas y gestiona tus compras en un solo lugar.",
    type: "website",
  },
};

export default function RootLayout({ children }) {
  return (
    <html lang="es" suppressHydrationWarning>
      <body
        className={`${inter.variable} ${geistMono.variable} antialiased`}
        suppressHydrationWarning
      >
        {children}
      </body>
    </html>
  );
}
