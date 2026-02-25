"use client";

import React from "react";
import {
  Store,
  Truck,
  MapPin,
  Users,
  CheckCircle2,
  ArrowRight,
} from "lucide-react";
import Link from "next/link";

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-slate-50 font-sans text-slate-900 selection:bg-blue-200">
      {/* 1. Navbar */}
      <header className="fixed top-0 left-0 right-0 z-50 border-b border-white/10 bg-white/80 backdrop-blur-md dark:border-slate-800 dark:bg-slate-950/80">
        <div className="mx-auto flex h-20 max-w-7xl items-center justify-between px-6 lg:px-8">
          <div className="flex items-center gap-2">
            <span className="text-3xl font-black tracking-tighter text-blue-700 dark:text-blue-500">
              Datix
            </span>
          </div>

          <nav className="hidden gap-8 font-medium text-slate-600 dark:text-slate-300 md:flex lg:mx-auto">
            <Link
              href="#aplicaciones"
              className="transition-colors hover:text-blue-600"
            >
              Aplicaciones
            </Link>
            <Link
              href="#precios"
              className="transition-colors hover:text-blue-600"
            >
              Precios
            </Link>
            <Link
              href="#soporte"
              className="transition-colors hover:text-blue-600"
            >
              Soporte
            </Link>
          </nav>

          <div className="flex items-center gap-4">
            <Link
              href="#"
              className="hidden rounded-full border border-slate-300 px-5 py-2.5 text-sm font-semibold text-slate-700 transition-colors hover:bg-slate-50 dark:border-slate-600 dark:text-slate-300 dark:hover:bg-slate-800 sm:block"
            >
              Iniciar Sesión
            </Link>
            <Link
              href="#"
              className="rounded-full bg-blue-600 px-5 py-2.5 text-sm font-semibold text-white shadow-sm transition-all hover:scale-105 hover:bg-blue-500 active:scale-95"
            >
              Crear Cuenta Gratis
            </Link>
          </div>
        </div>
      </header>

      {/* 2. Hero Section (Visión Ecosistema) */}
      <section className="relative overflow-hidden bg-slate-50 pb-24 pt-32 sm:pb-32 sm:pt-40 lg:pb-40">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,_var(--tw-gradient-stops))] from-blue-100 via-slate-50 to-white"></div>
        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-8">
            <div className="text-center lg:text-left">
              <h1 className="mb-8 text-4xl font-extrabold leading-tight tracking-tight text-slate-900 sm:text-5xl lg:text-6xl">
                Todas las aplicaciones que tu negocio necesita, en un solo lugar.
              </h1>
              <p className="mx-auto mt-6 max-w-xl text-lg leading-relaxed tracking-wide text-slate-600 sm:text-xl lg:mx-0">
                Desde el punto de venta de tu almacén hasta el control de tu flota de
                camiones. Elige las aplicaciones que necesitas, conéctalas entre sí y
                paga solo por lo que usas.
              </p>
              <div className="mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row lg:justify-start">
                <Link
                  href="#aplicaciones"
                  className="w-full rounded-full bg-blue-600 px-8 py-4 text-lg font-semibold text-white shadow-lg shadow-blue-600/20 transition-all duration-300 hover:-translate-y-1 hover:bg-blue-500 hover:shadow-xl hover:shadow-blue-600/30 md:w-auto"
                >
                  Ver Aplicaciones
                </Link>
                <Link
                  href="#"
                  className="flex w-full items-center justify-center gap-2 rounded-full border border-slate-200 bg-white px-8 py-4 text-lg font-semibold text-slate-700 shadow-sm transition-all duration-300 hover:bg-slate-50 md:w-auto"
                >
                  Hablar con un Asesor
                </Link>
              </div>
              <p className="mt-6 text-sm font-medium text-slate-500">
                Sin contratos forzosos. Cancela cuando quieras.
              </p>
            </div>

            {/* Imagen Principal del Hero */}
            <div className="relative mx-auto w-full max-w-lg lg:max-w-none">
              <div className="flex aspect-[4/3] w-full flex-col items-center justify-center rounded-3xl border border-slate-200 bg-white p-8 text-center text-slate-500 shadow-2xl xl:aspect-[4/3]">
                <span className="font-medium text-slate-600">
                  Espacio para Imagen Principal
                </span>
                <span className="mt-2 text-sm text-slate-400">
                  (Ej: Dashboard de Apps o Módulos)
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 3. Sección "App Store" (Catálogo en Zig-Zag) */}
      <section id="aplicaciones" className="bg-white py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="mx-auto mb-20 max-w-3xl text-center">
            <h2 className="mb-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-5xl">
              Construye tu ERP a medida
            </h2>
            <p className="text-lg text-slate-600">
              Selecciona las herramientas que resuelven tus problemas de hoy, y
              agrega más a medida que creces.
            </p>
          </div>

          <div className="flex flex-col gap-24 sm:gap-32">
            {/* Módulo 1 (Izquierda: Imagen, Derecha: Texto) */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="flex aspect-video w-full items-center justify-center rounded-3xl bg-slate-100 shadow-inner">
                <span className="text-sm font-medium text-slate-400 sm:text-base">
                  Foto: Datix POS & Almacén
                </span>
              </div>
              <div className="flex flex-col justify-center">
                <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-blue-100 text-blue-600">
                  <Store className="h-8 w-8" />
                </div>
                <div className="mb-2">
                  <span className="inline-flex items-center rounded-full bg-green-50 px-3 py-1 text-xs font-semibold text-green-700 ring-1 ring-inset ring-green-600/20">
                    Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                  Datix POS & Almacén
                </h3>
                <p className="text-lg leading-relaxed text-slate-600">
                  Punto de venta súper rápido, con soporte para múltiples métodos
                  de pago. Incluye motor FEFO para rotación inteligente de lotes,
                  alertas de stock y módulo de fiados para tus clientes más
                  frecuentes.
                </p>
                <ul className="mt-8 space-y-4 text-slate-600">
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-blue-500" />
                    Agiliza las ventas en caja
                  </li>
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-blue-500" />
                    Controla el inventario por lotes
                  </li>
                </ul>
              </div>
            </div>

            {/* Módulo 2 (Derecha: Imagen, Izquierda: Texto) */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="order-last flex flex-col justify-center lg:order-first">
                <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-purple-100 text-purple-600">
                  <Truck className="h-8 w-8" />
                </div>
                <div className="mb-2">
                  <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 ring-1 ring-inset ring-slate-500/20">
                    Próximamente
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                  Datix Logística
                </h3>
                <p className="text-lg leading-relaxed text-slate-600">
                  Gestión avanzada para tus bodegas centrales. Optimiza las
                  rutas de picking dentro del almacén, controla reabastecimientos,
                  gestiona transferencias entre sucursales y audita mermas.
                </p>
                <ul className="mt-8 space-y-4 text-slate-600">
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-purple-500" />
                    Multi-bodega y ubicaciones dinámicas
                  </li>
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-purple-500" />
                    Picking con lector de códigos o app móvil
                  </li>
                </ul>
              </div>
              <div className="flex aspect-video w-full items-center justify-center rounded-3xl bg-slate-100 shadow-inner">
                <span className="text-sm font-medium text-slate-400 sm:text-base">
                  Foto: Datix Logística
                </span>
              </div>
            </div>

            {/* Módulo 3 (Izquierda: Imagen, Derecha: Texto) */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="flex aspect-video w-full items-center justify-center rounded-3xl bg-slate-100 shadow-inner">
                <span className="text-sm font-medium text-slate-400 sm:text-base">
                  Foto: Datix Flotas
                </span>
              </div>
              <div className="flex flex-col justify-center">
                <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-teal-100 text-teal-600">
                  <MapPin className="h-8 w-8" />
                </div>
                <div className="mb-2">
                  <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 ring-1 ring-inset ring-slate-500/20">
                    Próximamente
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                  Datix Flotas
                </h3>
                <p className="text-lg leading-relaxed text-slate-600">
                  Mantén tus camiones y vehículos comerciales siempre funcionando.
                  Programa mantenimientos preventivos, controla los gastos de
                  combustible, y realiza un seguimiento detallado del uso de cada
                  unidad móvil.
                </p>
                <ul className="mt-8 space-y-4 text-slate-600">
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-teal-500" />
                    Alertas de mantenimientos y revisiones técnicas
                  </li>
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-teal-500" />
                    Historial de gastos por vehículo
                  </li>
                </ul>
              </div>
            </div>

            {/* Módulo 4 (Derecha: Imagen, Izquierda: Texto) */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="order-last flex flex-col justify-center lg:order-first">
                <div className="mb-6 inline-flex h-16 w-16 items-center justify-center rounded-2xl bg-orange-100 text-orange-600">
                  <Users className="h-8 w-8" />
                </div>
                <div className="mb-2">
                  <span className="inline-flex items-center rounded-full bg-slate-100 px-3 py-1 text-xs font-semibold text-slate-600 ring-1 ring-inset ring-slate-500/20">
                    Próximamente
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                  Datix RRHH
                </h3>
                <p className="text-lg leading-relaxed text-slate-600">
                  Tu equipo es lo más importante. Centraliza los datos de tus empleados,
                  gestiona la asistencia, organiza los turnos de manera inteligente y
                  automatiza el cálculo y emisión de las liquidaciones de sueldo a fin de mes.
                </p>
                <ul className="mt-8 space-y-4 text-slate-600">
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-orange-500" />
                    Reloj control y gestión de asistencias
                  </li>
                  <li className="flex items-center gap-3">
                    <CheckCircle2 className="h-5 w-5 text-orange-500" />
                    Emisión automática de liquidaciones de sueldo
                  </li>
                </ul>
              </div>
              <div className="flex aspect-video w-full items-center justify-center rounded-3xl bg-slate-100 shadow-inner">
                <span className="text-sm font-medium text-slate-400 sm:text-base">
                  Foto: Datix RRHH
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* 4. Pricing (Modelo Modular) */}
      <section id="precios" className="relative overflow-hidden bg-slate-50 py-24 sm:py-32">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="text-3xl font-bold tracking-tight text-slate-900 sm:text-5xl">
              Paga solo por lo que usas.
            </h2>
            <p className="mt-6 text-lg leading-8 text-slate-600">
              Olvídate de pagar fortunas por sistemas complejos donde no usas ni la
              mitad de las funciones. Nuestro modelo modular es simple y transparente.
            </p>
          </div>

          <div className="mx-auto mt-16 max-w-5xl">
            <div className="grid grid-cols-1 gap-8 md:grid-cols-3">
              {/* Step 1 */}
              <div className="relative rounded-3xl bg-white p-8 shadow-md ring-1 ring-slate-200">
                <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-blue-600 text-lg font-bold text-white">
                  1
                </div>
                <h3 className="mb-2 text-xl font-bold text-slate-900">
                  Crea tu cuenta base
                </h3>
                <p className="text-slate-600">
                  Regístrate gratis. Tu cuenta central incluye gestión básica de
                  usuarios y configuración de tu empresa.
                </p>
              </div>

              {/* Step 2 */}
              <div className="relative rounded-3xl bg-white p-8 shadow-md ring-1 ring-slate-200">
                <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-blue-600 text-lg font-bold text-white">
                  2
                </div>
                <h3 className="mb-2 text-xl font-bold text-slate-900">
                  Enciende las apps
                </h3>
                <p className="text-slate-600">
                  Ve a la App Store y activa solo los módulos que necesitas hoy. ¿Solo
                  Caja? Perfecto.
                </p>
                <ArrowRight className="absolute -right-6 top-1/2 hidden h-8 w-8 -translate-y-1/2 text-slate-300 md:block" />
                <ArrowRight className="absolute -left-6 top-1/2 hidden h-8 w-8 -translate-y-1/2 text-slate-300 md:block" />
              </div>

              {/* Step 3 */}
              <div className="relative rounded-3xl bg-white p-8 shadow-md ring-1 ring-slate-200">
                <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-full bg-blue-600 text-lg font-bold text-white">
                  3
                </div>
                <h3 className="mb-2 text-xl font-bold text-slate-900">
                  Ahorra al combinar
                </h3>
                <p className="text-slate-600">
                  A medida que tu negocio crece y añades más aplicaciones, el precio
                  unitario por aplicación baja.
                </p>
              </div>
            </div>

            <div className="mt-16 flex justify-center">
              <Link
                href="#"
                className="rounded-full bg-blue-600 px-8 py-4 text-lg font-semibold text-white shadow-lg transition-all hover:-translate-y-1 hover:bg-blue-500"
              >
                Calcula tu tarifa ahora
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* 5. Footer */}
      <footer className="border-t border-slate-200 bg-white">
        <div className="mx-auto max-w-7xl px-6 py-12 md:flex md:items-center md:justify-between lg:px-8">
          <div className="mt-8 flex flex-col items-center gap-4 text-sm text-slate-500 md:order-1 md:mt-0 md:flex-row">
            <span className="text-lg font-bold tracking-widest text-slate-900">
              DATIX
            </span>
            <span className="hidden text-slate-300 md:inline-block">|</span>
            <Link href="#" className="transition-colors hover:text-blue-600">
              Términos y Condiciones
            </Link>
            <Link href="#" className="transition-colors hover:text-blue-600">
              Política de Privacidad
            </Link>
            <p className="mt-4 md:ml-4 md:mt-0">
              &copy; 2026 Datix SpA. Todos los derechos reservados.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
