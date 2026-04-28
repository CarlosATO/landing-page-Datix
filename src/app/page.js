"use client";

import React, { useEffect, useRef } from "react";
import {
  Store,
  ShoppingCart,
  Pill,
  CheckCircle2,
  ArrowRight,
  Headset,
  ShieldCheck,
  Zap,
  BarChart3,
  Clock,
  Star,
  ChevronRight,
  Menu,
  X,
} from "lucide-react";
import Link from "next/link";

/* ──────────────── Scroll Reveal Hook ──────────────── */
function useScrollReveal() {
  useEffect(() => {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("visible");
          }
        });
      },
      { threshold: 0.1, rootMargin: "0px 0px -60px 0px" }
    );

    document.querySelectorAll(".reveal, .reveal-left, .reveal-right").forEach((el) => {
      observer.observe(el);
    });

    return () => observer.disconnect();
  }, []);
}

/* ──────────────── Animated Counter ──────────────── */
function AnimatedCounter({ target, suffix = "", prefix = "" }) {
  const ref = useRef(null);
  const hasAnimated = useRef(false);

  useEffect(() => {
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting && !hasAnimated.current) {
          hasAnimated.current = true;
          let current = 0;
          const increment = Math.ceil(target / 60);
          const timer = setInterval(() => {
            current += increment;
            if (current >= target) {
              current = target;
              clearInterval(timer);
            }
            if (ref.current) ref.current.textContent = `${prefix}${current.toLocaleString()}${suffix}`;
          }, 20);
        }
      },
      { threshold: 0.5 }
    );

    if (ref.current) observer.observe(ref.current);
    return () => observer.disconnect();
  }, [target, suffix, prefix]);

  return <span ref={ref}>0</span>;
}

/* ──────────────── Solutions Dropdown ──────────────── */
function SolutionsDropdown() {
  const [isOpen, setIsOpen] = React.useState(false);

  const solutions = [
    {
      id: 'pos',
      name: 'POS & Almacén',
      icon: Store,
      description: 'Venta y gestión de inventario',
      status: 'available',
      iconBg: 'bg-brand-vivid/15',
      iconColor: 'text-brand-vivid'
    },
    {
      id: 'adquisiciones',
      name: 'Adquisiciones',
      icon: ShoppingCart,
      description: 'Gestión de compras y proveedores',
      status: 'available',
      iconBg: 'bg-purple-100',
      iconColor: 'text-purple-600'
    },
    {
      id: 'farmacias',
      name: 'Farmacias',
      icon: Pill,
      description: 'Gestión farmacéutica especializada',
      status: 'available',
      iconBg: 'bg-teal-100',
      iconColor: 'text-teal-600'
    }
  ];

  return (
    <div className="relative group">
      <button 
        onMouseEnter={() => setIsOpen(true)}
        onMouseLeave={() => setIsOpen(false)}
        className="relative transition-all hover:text-brand-vivid text-gray-700 font-semibold flex items-center gap-1"
      >
        Soluciones
        <ChevronRight className={`h-4 w-4 transition-transform duration-300 ${isOpen ? 'rotate-90' : ''}`} />
      </button>

      {isOpen && (
        <div 
          onMouseEnter={() => setIsOpen(true)}
          onMouseLeave={() => setIsOpen(false)}
          className="absolute left-0 top-full pt-3 z-50 w-72 animate-in fade-in slide-in-from-top-2 duration-200"
        >
          <div className="rounded-xl bg-white border border-gray-300 shadow-2xl shadow-black/10 overflow-hidden">
            <div className="p-3 space-y-1">
              {solutions.map((solution) => {
                const Icon = solution.icon;
                const isAvailable = solution.status === 'available';
                return (
                  <Link
                    key={solution.id}
                    href={isAvailable ? `#soluciones` : '#'}
                    className={`block p-3.5 rounded-lg transition-all duration-200 group/item ${
                      isAvailable 
                        ? 'hover:bg-brand-vivid/8 hover:border-brand-vivid/30' 
                        : 'opacity-75 cursor-default'
                    } border border-transparent`}
                  >
                    <div className="flex items-start gap-3">
                      <div className={`flex-shrink-0 p-2 rounded-lg ${solution.iconBg}`}>
                        <Icon className={`h-5 w-5 ${solution.iconColor}`} />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <h4 className="text-sm font-semibold text-gray-900 group-hover/item:text-brand-vivid transition-colors">
                            {solution.name}
                          </h4>
                          {!isAvailable && (
                            <span className="px-2 py-0.5 text-xs font-medium text-amber-600 bg-amber-100 rounded-full whitespace-nowrap">
                              Próx.
                            </span>
                          )}
                        </div>
                        <p className="text-xs text-gray-600 mt-1">{solution.description}</p>
                      </div>
                    </div>
                  </Link>
                );
              })}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/* ──────────────── Mobile Nav ──────────────── */
function MobileMenu({ isOpen, onClose }) {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-[60] bg-white flex flex-col items-center justify-center gap-8 animate-fade-in-up md:hidden">
      <button onClick={onClose} className="absolute top-6 right-6 text-gray-500 hover:text-gray-700">
        <X className="h-8 w-8" />
      </button>
      <Link href="#soluciones" onClick={onClose} className="text-2xl font-bold text-gray-900 hover:text-brand-vivid transition-colors">
        Soluciones
      </Link>
      <Link href="#precios" onClick={onClose} className="text-2xl font-bold text-gray-900 hover:text-brand-vivid transition-colors">
        Precios
      </Link>
      <Link href="#soporte" onClick={onClose} className="text-2xl font-bold text-gray-900 hover:text-brand-vivid transition-colors">
        Cercanía
      </Link>
      <div className="mt-4 flex w-64 flex-col gap-4">
        <Link
          href="/login"
          onClick={onClose}
          className="rounded-lg border border-slate-400 bg-white px-6 py-3 text-center font-semibold text-slate-900 shadow-sm transition-all hover:border-brand-vivid/60 hover:bg-slate-50"
        >
          Iniciar Sesión
        </Link>
        <Link
          href="/register"
          onClick={onClose}
          className="rounded-lg bg-gradient-to-r from-[#6D28D9] to-[#4C1D95] px-6 py-3 text-center font-semibold text-white shadow-lg shadow-violet-900/35 transition-all hover:shadow-xl hover:shadow-violet-900/45"
        >
          Crear Cuenta Gratis
        </Link>
      </div>
    </div>
  );
}

/* ══════════════════════════════════════════════════════════
   LANDING PAGE
   ══════════════════════════════════════════════════════════ */
export default function LandingPage() {
  const [mobileOpen, setMobileOpen] = React.useState(false);
  useScrollReveal();

  return (
    <div className="min-h-screen bg-white font-sans text-gray-900 selection:bg-brand-vivid/30">
      {/* ─── Mobile Menu ─── */}
      <MobileMenu isOpen={mobileOpen} onClose={() => setMobileOpen(false)} />

      {/* ═══════════════════════════════════════════════
          1.  NAVBAR (Minimalista & Profesional)
          ═══════════════════════════════════════════════ */}
      <header className="fixed top-0 left-0 right-0 z-50 border-b border-black/5 bg-white/95 backdrop-blur-xl shadow-sm transition-all duration-500">
        <div className="mx-auto flex h-20 max-w-7xl items-center justify-between px-6 lg:px-8">
          {/* Logo */}
          <Link href="/" className="group flex-shrink-0">
            <img
              src="/imagen/logo_datix.png"
              alt="Datix Logo"
              className="h-[68px] w-auto max-w-none opacity-100 transition-all duration-300 [image-rendering:-webkit-optimize-contrast] group-hover:scale-[1.02] group-hover:drop-shadow-[0_4px_10px_rgba(124,58,237,0.25)]"
              style={{
                filter:
                  "brightness(0) saturate(100%) invert(31%) sepia(60%) saturate(1200%) hue-rotate(240deg) brightness(94%) contrast(106%)",
              }}
            />
          </Link>

          {/* Desktop Nav */}
          <nav className="hidden md:flex gap-8 font-semibold">
            <SolutionsDropdown />
            <Link 
              href="#precios" 
              className="relative transition-all hover:text-brand-vivid text-gray-700 flex items-center gap-1"
            >
              Precios
              <span className="absolute bottom-[-4px] left-0 h-[2px] w-0 bg-brand-vivid transition-all duration-300 hover:w-full"></span>
            </Link>
            <Link 
              href="#soporte" 
              className="relative transition-all hover:text-brand-vivid text-gray-700 flex items-center gap-1"
            >
              Cercanía
              <span className="absolute bottom-[-4px] left-0 h-[2px] w-0 bg-brand-vivid transition-all duration-300 hover:w-full"></span>
            </Link>
          </nav>

          {/* Desktop Buttons */}
          <div className="hidden md:flex items-center gap-3 flex-shrink-0">
            <Link
              href="/login"
              className="rounded-lg border border-slate-300 bg-white px-4 py-2 text-sm font-semibold text-slate-900 shadow-sm transition-all duration-200 hover:border-brand-vivid/60 hover:bg-slate-50"
            >
              Acceder
            </Link>
            <Link
              href="/register"
              className="rounded-lg bg-gradient-to-r from-[#6D28D9] to-[#4C1D95] px-5 py-2.5 text-sm font-semibold text-white shadow-lg shadow-violet-900/30 transition-all duration-200 hover:scale-105 hover:shadow-xl hover:shadow-violet-900/45 active:scale-95"
            >
              Probar Gratis
            </Link>
          </div>

          {/* Mobile Hamburger */}
          <button className="md:hidden text-gray-700 hover:text-brand-vivid transition-colors flex-shrink-0" onClick={() => setMobileOpen(true)}>
            <Menu className="h-6 w-6" />
          </button>
        </div>
      </header>

      {/* ═══════════════════════════════════════════════
          2.  HERO SECTION
          ═══════════════════════════════════════════════ */}
      <section className="relative overflow-hidden pt-20 pb-16 sm:pt-28 sm:pb-24 lg:pt-32 lg:pb-32">
        {/* Background Effects */}
        <div className="absolute inset-0">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top_right,rgba(142,67,217,0.15),transparent_60%)]"></div>
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_bottom_left,rgba(76,48,115,0.2),transparent_60%)]"></div>
          {/* Floating orbs */}
          <div className="absolute top-20 left-[15%] h-72 w-72 rounded-full bg-brand-vivid/[0.07] blur-3xl animate-float"></div>
          <div className="absolute bottom-20 right-[10%] h-96 w-96 rounded-full bg-brand-accent/[0.06] blur-3xl animate-float-slow"></div>
          <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 h-[600px] w-[600px] rounded-full bg-brand-primary/[0.04] blur-3xl"></div>
        </div>

        {/* Grid pattern overlay */}
        <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:64px_64px]"></div>

        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          <div className="grid grid-cols-1 items-center gap-16 lg:grid-cols-2 lg:gap-12">
            {/* Left: Copy */}
            <div className="text-center lg:text-left">
                <h1 className="animate-fade-in-up text-4xl font-extrabold leading-[1.1] tracking-tight sm:text-5xl lg:text-[3.5rem] xl:text-6xl text-gray-900">
                Controla tu inventario, agiliza ventas y gestiona compras{" "}
                <span className="bg-gradient-to-r from-brand-vivid to-brand-accent bg-clip-text text-transparent">en un solo lugar.</span>
              </h1>

              <p className="animate-fade-in-up delay-200 animate-start-hidden mt-6 max-w-xl text-lg leading-relaxed text-gray-600 sm:text-xl lg:mx-0 mx-auto">
                Diseñado para negocios locales que necesitan orden inmediato.
                Fácil de usar, rápido de implementar y sin complicaciones técnicas.
              </p>

              <div className="animate-fade-in-up delay-400 animate-start-hidden mt-10 flex flex-col items-center justify-center gap-4 sm:flex-row lg:justify-start">
                <Link
                  href="/register"
                  className="group w-full rounded-full bg-gradient-to-r from-brand-accent to-brand-vivid px-8 py-4 text-lg font-bold text-white shadow-xl shadow-brand-vivid/25 transition-all duration-300 hover:shadow-2xl hover:shadow-brand-vivid/40 hover:scale-[1.03] active:scale-95 md:w-auto flex items-center justify-center gap-2"
                >
                  Comienza Gratis
                  <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-1" />
                </Link>
                <a
                  href="https://calendly.com/calegria1980/demostracion-datix-soluciones-empresariales"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="flex w-full items-center justify-center gap-2 rounded-lg border border-gray-300 bg-white px-8 py-4 text-lg font-semibold text-gray-700 transition-all duration-300 hover:bg-gray-50 hover:border-gray-400 md:w-auto"
                >
                  Agendar una Demo
                </a>
              </div>

              <p className="animate-fade-in-up delay-600 animate-start-hidden mt-6 text-sm font-medium text-gray-500">
                ✓ Sin tarjeta de crédito &nbsp; ✓ 14 días gratis &nbsp; ✓ Cancela cuando quieras
              </p>
            </div>

            {/* Right: Hero Dashboard Mockup */}
            <div className="relative mx-auto w-full max-w-lg lg:max-w-none animate-fade-in-right delay-300 animate-start-hidden">
              {/* Glow behind the dashboard */}
              <div className="absolute inset-0 -m-8 rounded-3xl bg-gradient-to-br from-brand-vivid/20 to-brand-accent/10 blur-2xl"></div>

              <div className="relative overflow-hidden rounded-2xl border border-gray-200 shadow-2xl shadow-gray-300/20">
                {/* Browser-like top bar */}
                <div className="flex items-center gap-2 bg-gray-100 px-4 py-3 border-b border-gray-200">
                  <div className="flex gap-1.5">
                    <div className="h-3 w-3 rounded-full bg-red-500"></div>
                    <div className="h-3 w-3 rounded-full bg-yellow-500"></div>
                    <div className="h-3 w-3 rounded-full bg-green-500"></div>
                  </div>
                  <div className="ml-3 flex-1 rounded-md bg-white px-3 py-1 text-xs text-gray-400">
                    app.datix.cl/dashboard
                  </div>
                </div>
                <img
                  src="/imagen/hero_dashboard.png"
                  alt="Panel de Gestión Datix - Dashboard de Ventas e Inventario"
                  className="w-full"
                />
              </div>

              {/* Decorative floating card */}
              <div className="absolute -bottom-4 -left-6 bg-white border border-gray-200 rounded-xl px-4 py-3 shadow-xl animate-float-slow hidden lg:flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-100">
                  <BarChart3 className="h-5 w-5 text-green-600" />
                </div>
                <div>
                  <p className="text-xs text-gray-500">Ventas Hoy</p>
                  <p className="text-sm font-bold text-gray-900">$1.250.000</p>
                </div>
              </div>

              <div className="absolute -top-3 -right-4 bg-white border border-gray-200 rounded-xl px-4 py-3 shadow-xl animate-float hidden lg:flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-vivid/20">
                  <Clock className="h-5 w-5 text-brand-vivid" />
                </div>
                <div>
                  <p className="text-xs text-gray-500">Tiempo Real</p>
                  <p className="text-sm font-bold text-gray-900">Sincronizado</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          3.  SOCIAL PROOF STRIP
          ═══════════════════════════════════════════════ */}
      <section className="relative border-y border-gray-200 bg-gray-50 py-12">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="grid grid-cols-2 gap-8 text-center md:grid-cols-4">
            <div className="reveal">
              <p className="text-3xl font-extrabold text-gray-900 sm:text-4xl">
                <AnimatedCounter target={500} suffix="+" />
              </p>
              <p className="mt-1 text-sm font-medium text-gray-600">Productos Gestionados</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "100ms" }}>
              <p className="text-3xl font-extrabold text-gray-900 sm:text-4xl">
                <AnimatedCounter target={99} suffix="%" />
              </p>
              <p className="mt-1 text-sm font-medium text-gray-600">Uptime Garantizado</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "200ms" }}>
              <p className="text-3xl font-extrabold text-gray-900 sm:text-4xl">
                <AnimatedCounter target={3} />
              </p>
              <p className="mt-1 text-sm font-medium text-gray-600">Módulos Disponibles</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "300ms" }}>
              <p className="text-3xl font-extrabold text-gray-900 sm:text-4xl">
                <AnimatedCounter target={24} suffix="/7" />
              </p>
              <p className="mt-1 text-sm font-medium text-gray-600">Soporte Directo</p>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          4.  SOLUCIONES (MÓDULOS)
          ═══════════════════════════════════════════════ */}
      <section id="soluciones" className="relative py-24 sm:py-32 bg-white">
        {/* Background */}
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(124,58,237,0.05),transparent_70%)]"></div>

        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          {/* Section Header */}
          <div className="reveal mx-auto mb-20 max-w-3xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-vivid/30 bg-brand-vivid/10 px-4 py-1.5 text-sm font-medium text-brand-vivid mb-6">
              <Store className="h-4 w-4" />
                <span>Ecosistema Modular</span>
            </div>
            <h2 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-5xl text-gray-900">
              Soluciones listas para usar
            </h2>
              <p className="text-lg text-gray-600 leading-relaxed">
                No necesitas un sistema enorme. Activa solo lo que tu negocio requiere hoy.
              </p>
          </div>

          <div className="flex flex-col gap-28 sm:gap-36">

            {/* ── Module 1: POS & Almacén ── */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="reveal-left relative group">
                <div className="absolute inset-0 -m-4 rounded-3xl bg-gradient-to-br from-brand-vivid/10 to-transparent blur-xl transition-all duration-500 group-hover:from-brand-vivid/20"></div>
                <div className="relative overflow-hidden rounded-2xl border border-gray-200 shadow-2xl transition-all duration-500 group-hover:border-gray-300 group-hover:shadow-gray-300/20">
                  <img
                    src="/imagen/mockup_pos.png"
                    alt="Datix Punto de Venta - Interfaz de gestión de ventas e inventario"
                    className="w-full transition-transform duration-700 group-hover:scale-[1.02]"
                  />
                </div>
              </div>
              <div className="reveal-right flex flex-col justify-center">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand-vivid/15 ring-1 ring-brand-vivid/20">
                  <Store className="h-7 w-7 text-brand-vivid" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-700 ring-1 ring-inset ring-green-300">
                    ● Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl text-gray-900">
                  Datix POS & Almacén
                </h3>
                <p className="text-lg leading-relaxed text-gray-600">
                  Vende más rápido y controla tu inventario sin errores. Ideal para negocios que manejan stock crítico y necesitan agilidad.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Punto de venta intuitivo y veloz",
                    "Motor FEFO: Rotación inteligente por fecha de vencimiento",
                    "Alertas de stock bajo y módulo de fiados",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-gray-700 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-brand-vivid flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            {/* ── Module 2: Adquisiciones ── */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="reveal-left order-last flex flex-col justify-center lg:order-first">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-purple-100 ring-1 ring-purple-200">
                  <ShoppingCart className="h-7 w-7 text-purple-600" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-700 ring-1 ring-inset ring-green-300">
                    ● Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl text-gray-900">
                  Datix Adquisiciones
                </h3>
                <p className="text-lg leading-relaxed text-gray-600">
                  Automatiza tus compras y mantén una relación impecable con tus proveedores. Nunca más te quedes sin stock.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Gestión centralizada de proveedores",
                    "Órdenes de compra automáticas al bajar el stock",
                    "Control riguroso de recepción de mercadería",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-gray-700 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-purple-600 flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="reveal-right relative group">
                <div className="absolute inset-0 -m-4 rounded-3xl bg-gradient-to-br from-purple-500/10 to-transparent blur-xl transition-all duration-500 group-hover:from-purple-500/20"></div>
                <div className="relative overflow-hidden rounded-2xl border border-gray-200 shadow-2xl transition-all duration-500 group-hover:border-gray-300 group-hover:shadow-purple-300/20">
                  <img
                    src="/imagen/mockup_adquisiciones.png"
                    alt="Datix Adquisiciones - Gestión de órdenes de compra y proveedores"
                    className="w-full transition-transform duration-700 group-hover:scale-[1.02]"
                  />
                </div>
              </div>
            </div>

            {/* ── Module 3: Farmacias ── */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="reveal-left relative group">
                <div className="absolute inset-0 -m-4 rounded-3xl bg-gradient-to-br from-teal-500/10 to-transparent blur-xl transition-all duration-500 group-hover:from-teal-500/20"></div>
                <div className="relative overflow-hidden rounded-2xl border border-gray-200 shadow-2xl transition-all duration-500 group-hover:border-gray-300 group-hover:shadow-teal-300/20">
                  <img
                    src="/imagen/mockup_farmacias.png"
                    alt="Datix Farmacias - Sistema de gestión farmacéutica con trazabilidad"
                    className="w-full transition-transform duration-700 group-hover:scale-[1.02]"
                  />
                </div>
              </div>
              <div className="reveal-right flex flex-col justify-center">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-teal-100 ring-1 ring-teal-200">
                  <Pill className="h-7 w-7 text-teal-600" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-green-100 px-3 py-1 text-xs font-semibold text-green-700 ring-1 ring-inset ring-green-300">
                    ● Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl text-gray-900">
                  Datix Farmacias
                </h3>
                <p className="text-lg leading-relaxed text-gray-600">
                  Especializado en cumplimiento normativo y seguridad. Diseñado para la trazabilidad total de medicamentos.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Trazabilidad de lotes y fechas de vencimiento",
                    "Integración FEFO para evitar mermas por caducidad",
                    "Gestión de recetas y stock de medicamentos críticos",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-gray-700 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-teal-600 flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>

          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          5.  CERCANÍA / CONFIANZA
          ═══════════════════════════════════════════════ */}
      <section id="soporte" className="relative py-24 overflow-hidden">
        {/* Gradient Separator */}
        <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-brand-vivid/30 to-transparent"></div>
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_bottom_right,rgba(142,67,217,0.08),transparent_60%)]"></div>

        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          <div className="grid grid-cols-1 gap-16 lg:grid-cols-2 lg:items-center">
            <div className="reveal">
              <div className="inline-flex items-center gap-2 rounded-full border border-brand-vivid/20 bg-brand-vivid/10 px-4 py-1.5 text-sm font-medium text-brand-light mb-6">
                <Headset className="h-4 w-4" />
                <span>Trato Personalizado</span>
              </div>
              <h2 className="text-3xl font-extrabold tracking-tight sm:text-4xl lg:text-5xl">
                No eres un número más,{" "}
                <span className="gradient-text">eres nuestro aliado.</span>
              </h2>
              <p className="mt-6 text-lg leading-relaxed text-white/50">
                Entendemos que digitalizar un negocio puede ser frustrante. Por eso, nos alejamos del soporte impersonal y te acompañamos desde el primer día.
              </p>
            </div>

            <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
              {[
                {
                  icon: <Headset className="h-7 w-7" />,
                  title: "Soporte Directo",
                  desc: "Habla directamente con los creadores del sistema. Sin intermediarios, sin esperas infinitas.",
                  color: "brand-vivid",
                },
                {
                  icon: <ShieldCheck className="h-7 w-7" />,
                  title: "Implementación Guiada",
                  desc: "Te ayudamos a configurar tus productos, proveedores y puntos de venta paso a paso.",
                  color: "brand-light",
                },
                {
                  icon: <Zap className="h-7 w-7" />,
                  title: "Actualizaciones Constantes",
                  desc: "Nuevas funciones cada mes, sin costo adicional. Tu sistema siempre mejora.",
                  color: "purple-400",
                },
                {
                  icon: <Star className="h-7 w-7" />,
                  title: "Hecho en Latinoamérica",
                  desc: "Pensado para las necesidades reales de los negocios locales de nuestra región.",
                  color: "teal-400",
                },
              ].map((card, i) => (
                <div
                  key={i}
                  className="reveal glass rounded-2xl p-7 transition-all duration-300 hover:bg-white/[0.08] hover:border-white/15 hover:-translate-y-1 hover:shadow-lg"
                  style={{ transitionDelay: `${i * 100}ms` }}
                >
                  <div className={`mb-4 text-${card.color}`}>{card.icon}</div>
                  <h3 className="text-lg font-bold mb-2">{card.title}</h3>
                  <p className="text-sm text-white/50 leading-relaxed">{card.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          6.  PRICING
          ═══════════════════════════════════════════════ */}
      <section id="precios" className="relative py-24 sm:py-32 overflow-hidden">
        {/* Separator */}
        <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-brand-vivid/30 to-transparent"></div>
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_top,rgba(76,48,115,0.15),transparent_60%)]"></div>

        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          <div className="reveal mx-auto max-w-2xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-vivid/20 bg-brand-vivid/10 px-4 py-1.5 text-sm font-medium text-brand-light mb-6">
              <Star className="h-4 w-4" />
              <span>Precios Transparentes</span>
            </div>
            <h2 className="text-3xl font-extrabold tracking-tight sm:text-5xl">
              Planes simples que crecen contigo.
            </h2>
            <p className="mt-6 text-lg leading-relaxed text-white/50">
              Paga solo una tarifa justa por los módulos que realmente usas. Sin contratos forzosos ni sorpresas en la factura.
            </p>
          </div>

          <div className="mx-auto mt-16 max-w-5xl">
            <div className="grid grid-cols-1 gap-8 md:grid-cols-2">

              {/* Plan Individual */}
              <div className="reveal glass rounded-3xl p-10 transition-all duration-300 hover:bg-white/[0.07] hover:-translate-y-1 hover:shadow-xl flex flex-col justify-between">
                <div>
                    <h3 className="text-xl font-bold text-gray-900">Módulo Individual</h3>
                    <p className="mt-4 text-gray-600">
                    Perfecto si solo necesitas resolver un área específica de tu negocio hoy.
                  </p>
                  <ul className="mt-8 space-y-4 text-sm font-medium">
                    {[
                      "Almacén o Adquisiciones",
                      "Soporte directo vía WhatsApp",
                      "Implementación inicial guiada",
                    ].map((item, i) => (
                        <li key={i} className="flex items-center gap-3 text-gray-700">
                          <CheckCircle2 className="h-5 w-5 text-brand-vivid flex-shrink-0" />
                        {item}
                      </li>
                    ))}
                  </ul>
                </div>
                <Link
                  href="/register"
                  className="mt-10 block w-full rounded-xl border border-gray-300 bg-white py-3.5 text-center text-sm font-bold text-gray-700 transition-all hover:bg-gray-50 hover:border-gray-400"
                >
                  Comenzar Prueba Gratis
                </Link>
              </div>

              {/* Plan Combo */}
                <div className="reveal relative rounded-3xl bg-gradient-to-br from-brand-vivid/10 to-brand-accent/5 border border-brand-vivid/30 p-10 shadow-xl shadow-brand-vivid/5 transition-all duration-300 hover:-translate-y-1 hover:shadow-2xl hover:shadow-brand-vivid/15 flex flex-col justify-between" style={{ transitionDelay: "100ms" }}>
                <div className="absolute -top-4 left-1/2 -translate-x-1/2 rounded-full bg-gradient-to-r from-brand-accent to-brand-vivid px-5 py-1.5 text-xs font-bold text-white uppercase tracking-widest shadow-lg shadow-brand-vivid/30">
                  Más Popular
                </div>
                <div>
                    <h3 className="text-xl font-bold text-gray-900">Combo Gestión</h3>
                    <p className="mt-4 text-gray-600">
                    Conecta tus ventas con tus compras para un control total y ahorro garantizado.
                  </p>
                  <ul className="mt-8 space-y-4 text-sm font-medium">
                    {[
                      "Almacén + Adquisiciones (FullSync)",
                      "Alertas de compras sugeridas",
                      "Prioridad en soporte personalizado",
                      "Todas las futuras integraciones incluidas",
                    ].map((item, i) => (
                        <li key={i} className="flex items-center gap-3 text-gray-700">
                        <CheckCircle2 className="h-5 w-5 text-brand-vivid flex-shrink-0" />
                        {item}
                      </li>
                    ))}
                  </ul>
                </div>
                <Link
                  href="/register"
                  className="mt-10 block w-full rounded-xl bg-gradient-to-r from-brand-accent to-brand-vivid py-3.5 text-center text-sm font-bold text-white shadow-lg shadow-brand-vivid/25 transition-all hover:shadow-xl hover:shadow-brand-vivid/40 active:scale-[0.98]"
                >
                  Comenzar Prueba Gratis
                </Link>
              </div>

            </div>

            <div className="reveal mt-16 flex flex-col items-center gap-4">
              <p className="text-sm font-medium text-gray-500">
                Usa el sistema completo por 14 días sin compromiso. Sin tarjeta de crédito.
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          7.  CTA FINAL
          ═══════════════════════════════════════════════ */}
      <section className="relative py-24 overflow-hidden">
          <div className="absolute inset-0 bg-gradient-to-b from-brand-vivid/5 via-transparent to-brand-accent/5"></div>
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(124,58,237,0.06),transparent_70%)]"></div>

        <div className="relative z-10 mx-auto max-w-3xl px-6 text-center">
          <div className="reveal">
              <h2 className="text-3xl font-extrabold tracking-tight sm:text-5xl text-gray-900">
              ¿Listo para ordenar tu negocio?
            </h2>
              <p className="mt-6 text-lg text-gray-600 leading-relaxed">
              Únete a los negocios que ya confían en Datix para gestionar su operación diaria con eficiencia y tranquilidad.
            </p>
            <div className="mt-10 flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
              <Link
                href="/register"
                className="group rounded-full bg-gradient-to-r from-brand-accent to-brand-vivid px-10 py-4 text-lg font-bold text-white shadow-xl shadow-brand-vivid/25 transition-all duration-300 hover:shadow-2xl hover:shadow-brand-vivid/40 hover:scale-105 active:scale-95 animate-pulse-glow flex items-center gap-2"
              >
                Comienza hoy mismo gratis
                <ChevronRight className="h-5 w-5 transition-transform group-hover:translate-x-1" />
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          8.  FOOTER
          ═══════════════════════════════════════════════ */}
        <footer className="border-t border-gray-200 bg-white py-16">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="flex flex-col items-center gap-8 md:flex-row md:justify-between">
            {/* Logo + Links */}
            <div className="flex flex-col items-center gap-6 md:flex-row">
              <Link href="/">
                <img
                  src="/imagen/logo_datix.png"
                  alt="Datix Logo"
                    className="h-12 w-auto opacity-70 transition-all hover:opacity-100"
                />
              </Link>
                <div className="hidden h-6 w-px bg-gray-200 md:block"></div>
                <div className="flex gap-6 text-sm text-gray-500">
                  <Link href="#" className="transition-colors hover:text-gray-700">
                  Términos y Condiciones
                </Link>
                  <Link href="#" className="transition-colors hover:text-gray-700">
                  Política de Privacidad
                </Link>
              </div>
            </div>

            {/* Copyright */}
              <p className="text-sm text-gray-400">
              &copy; {new Date().getFullYear()} Datix SpA. Todos los derechos reservados.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
