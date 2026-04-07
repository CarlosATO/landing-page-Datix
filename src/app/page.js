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

/* ──────────────── Mobile Nav ──────────────── */
function MobileMenu({ isOpen, onClose }) {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 z-[60] bg-brand-deep/95 backdrop-blur-xl flex flex-col items-center justify-center gap-8 animate-fade-in-up md:hidden">
      <button onClick={onClose} className="absolute top-6 right-6 text-white/70 hover:text-white">
        <X className="h-8 w-8" />
      </button>
      <Link href="#soluciones" onClick={onClose} className="text-2xl font-bold text-white hover:text-brand-light transition-colors">
        Soluciones
      </Link>
      <Link href="#precios" onClick={onClose} className="text-2xl font-bold text-white hover:text-brand-light transition-colors">
        Precios
      </Link>
      <Link href="#soporte" onClick={onClose} className="text-2xl font-bold text-white hover:text-brand-light transition-colors">
        Cercanía
      </Link>
      <div className="flex flex-col gap-4 mt-4 w-64">
        <Link href="/login" onClick={onClose} className="rounded-full border border-white/20 bg-white/5 px-6 py-3 text-center font-bold text-white hover:bg-white/10 transition-all">
          Iniciar Sesión
        </Link>
        <Link href="/register" onClick={onClose} className="rounded-full bg-brand-vivid px-6 py-3 text-center font-bold text-white shadow-lg shadow-brand-vivid/30 hover:bg-brand-accent transition-all">
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
    <div className="min-h-screen bg-brand-deep font-sans text-white selection:bg-brand-vivid/30">
      {/* ─── Mobile Menu ─── */}
      <MobileMenu isOpen={mobileOpen} onClose={() => setMobileOpen(false)} />

      {/* ═══════════════════════════════════════════════
          1.  NAVBAR
          ═══════════════════════════════════════════════ */}
      <header className="fixed top-0 left-0 right-0 z-50 border-b border-white/[0.06] bg-brand-deep/80 backdrop-blur-2xl transition-all duration-500">
        <div className="mx-auto flex h-20 max-w-7xl items-center justify-between px-6 lg:px-8">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 group">
            <img
              src="/imagen/logo_datix.png"
              alt="Datix Logo"
              className="h-14 w-auto brightness-0 invert drop-shadow-[0_0_12px_rgba(142,67,217,0.5)] transition-all duration-300 group-hover:drop-shadow-[0_0_20px_rgba(142,67,217,0.7)] group-hover:scale-105"
            />
          </Link>

          {/* Desktop Nav */}
          <nav className="hidden gap-10 font-semibold text-white/70 md:flex">
            <Link href="#soluciones" className="relative transition-all hover:text-white after:absolute after:bottom-[-4px] after:left-0 after:h-[2px] after:w-0 after:bg-brand-vivid after:transition-all after:duration-300 hover:after:w-full">
              Soluciones
            </Link>
            <Link href="#precios" className="relative transition-all hover:text-white after:absolute after:bottom-[-4px] after:left-0 after:h-[2px] after:w-0 after:bg-brand-vivid after:transition-all after:duration-300 hover:after:w-full">
              Precios
            </Link>
            <Link href="#soporte" className="relative transition-all hover:text-white after:absolute after:bottom-[-4px] after:left-0 after:h-[2px] after:w-0 after:bg-brand-vivid after:transition-all after:duration-300 hover:after:w-full">
              Cercanía
            </Link>
          </nav>

          {/* Desktop Buttons */}
          <div className="hidden items-center gap-3 md:flex">
            <Link
              href="/login"
              className="rounded-full border border-white/15 bg-white/5 px-5 py-2.5 text-sm font-semibold text-white transition-all hover:bg-white/10 hover:border-white/25 backdrop-blur-sm"
            >
              Iniciar Sesión
            </Link>
            <Link
              href="/register"
              className="rounded-full bg-gradient-to-r from-brand-accent to-brand-vivid px-5 py-2.5 text-sm font-bold text-white shadow-lg shadow-brand-vivid/25 transition-all hover:scale-105 hover:shadow-xl hover:shadow-brand-vivid/40 active:scale-95"
            >
              Crear Cuenta Gratis
            </Link>
          </div>

          {/* Mobile Hamburger */}
          <button className="md:hidden text-white/70 hover:text-white" onClick={() => setMobileOpen(true)}>
            <Menu className="h-7 w-7" />
          </button>
        </div>
      </header>

      {/* ═══════════════════════════════════════════════
          2.  HERO SECTION
          ═══════════════════════════════════════════════ */}
      <section className="relative overflow-hidden pt-32 pb-24 sm:pt-40 sm:pb-32 lg:pt-44 lg:pb-40">
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
                <h1 className="animate-fade-in-up text-4xl font-extrabold leading-[1.1] tracking-tight sm:text-5xl lg:text-[3.5rem] xl:text-6xl">
                Controla tu inventario, agiliza ventas y gestiona compras{" "}
                <span className="gradient-text-white">en un solo lugar.</span>
              </h1>

              <p className="animate-fade-in-up delay-200 animate-start-hidden mt-6 max-w-xl text-lg leading-relaxed text-white/60 sm:text-xl lg:mx-0 mx-auto">
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
                  className="flex w-full items-center justify-center gap-2 rounded-full border border-white/15 bg-white/5 px-8 py-4 text-lg font-semibold text-white/90 backdrop-blur-sm transition-all duration-300 hover:bg-white/10 hover:border-white/25 md:w-auto"
                >
                  Agendar una Demo
                </a>
              </div>

              <p className="animate-fade-in-up delay-600 animate-start-hidden mt-6 text-sm font-medium text-white/40">
                ✓ Sin tarjeta de crédito &nbsp; ✓ 14 días gratis &nbsp; ✓ Cancela cuando quieras
              </p>
            </div>

            {/* Right: Hero Dashboard Mockup */}
            <div className="relative mx-auto w-full max-w-lg lg:max-w-none animate-fade-in-right delay-300 animate-start-hidden">
              {/* Glow behind the dashboard */}
              <div className="absolute inset-0 -m-8 rounded-3xl bg-gradient-to-br from-brand-vivid/20 to-brand-accent/10 blur-2xl"></div>

              <div className="relative overflow-hidden rounded-2xl border border-white/10 shadow-2xl shadow-brand-vivid/10">
                {/* Browser-like top bar */}
                <div className="flex items-center gap-2 bg-white/[0.03] px-4 py-3 border-b border-white/[0.06]">
                  <div className="flex gap-1.5">
                    <div className="h-3 w-3 rounded-full bg-red-400/60"></div>
                    <div className="h-3 w-3 rounded-full bg-yellow-400/60"></div>
                    <div className="h-3 w-3 rounded-full bg-green-400/60"></div>
                  </div>
                  <div className="ml-3 flex-1 rounded-md bg-white/[0.05] px-3 py-1 text-xs text-white/30">
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
              <div className="absolute -bottom-4 -left-6 glass rounded-xl px-4 py-3 shadow-xl animate-float-slow hidden lg:flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-green-500/20">
                  <BarChart3 className="h-5 w-5 text-green-400" />
                </div>
                <div>
                  <p className="text-xs text-white/50">Ventas Hoy</p>
                  <p className="text-sm font-bold text-white">$1.250.000</p>
                </div>
              </div>

              <div className="absolute -top-3 -right-4 glass rounded-xl px-4 py-3 shadow-xl animate-float hidden lg:flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-brand-vivid/20">
                  <Clock className="h-5 w-5 text-brand-light" />
                </div>
                <div>
                  <p className="text-xs text-white/50">Tiempo Real</p>
                  <p className="text-sm font-bold text-white">Sincronizado</p>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          3.  SOCIAL PROOF STRIP
          ═══════════════════════════════════════════════ */}
      <section className="relative border-y border-white/[0.06] bg-white/[0.02] py-12">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="grid grid-cols-2 gap-8 text-center md:grid-cols-4">
            <div className="reveal">
              <p className="text-3xl font-extrabold text-white sm:text-4xl">
                <AnimatedCounter target={500} suffix="+" />
              </p>
              <p className="mt-1 text-sm font-medium text-white/50">Productos Gestionados</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "100ms" }}>
              <p className="text-3xl font-extrabold text-white sm:text-4xl">
                <AnimatedCounter target={99} suffix="%" />
              </p>
              <p className="mt-1 text-sm font-medium text-white/50">Uptime Garantizado</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "200ms" }}>
              <p className="text-3xl font-extrabold text-white sm:text-4xl">
                <AnimatedCounter target={3} />
              </p>
              <p className="mt-1 text-sm font-medium text-white/50">Módulos Disponibles</p>
            </div>
            <div className="reveal" style={{ transitionDelay: "300ms" }}>
              <p className="text-3xl font-extrabold text-white sm:text-4xl">
                <AnimatedCounter target={24} suffix="/7" />
              </p>
              <p className="mt-1 text-sm font-medium text-white/50">Soporte Directo</p>
            </div>
          </div>
        </div>
      </section>

      {/* ═══════════════════════════════════════════════
          4.  SOLUCIONES (MÓDULOS)
          ═══════════════════════════════════════════════ */}
      <section id="soluciones" className="relative py-24 sm:py-32">
        {/* Background */}
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(76,48,115,0.12),transparent_70%)]"></div>

        <div className="relative z-10 mx-auto max-w-7xl px-6 lg:px-8">
          {/* Section Header */}
          <div className="reveal mx-auto mb-20 max-w-3xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-brand-vivid/20 bg-brand-vivid/10 px-4 py-1.5 text-sm font-medium text-brand-light mb-6">
              <Store className="h-4 w-4" />
              <span>Ecosistema Modular</span>
            </div>
            <h2 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-5xl">
              Soluciones listas para usar
            </h2>
            <p className="text-lg text-white/60 leading-relaxed">
              No necesitas un sistema enorme. Activa solo lo que tu negocio requiere hoy.
            </p>
          </div>

          <div className="flex flex-col gap-28 sm:gap-36">

            {/* ── Module 1: POS & Almacén ── */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="reveal-left relative group">
                <div className="absolute inset-0 -m-4 rounded-3xl bg-gradient-to-br from-brand-vivid/10 to-transparent blur-xl transition-all duration-500 group-hover:from-brand-vivid/20"></div>
                <div className="relative overflow-hidden rounded-2xl border border-white/10 shadow-2xl transition-all duration-500 group-hover:border-white/20 group-hover:shadow-brand-vivid/10">
                  <img
                    src="/imagen/mockup_pos.png"
                    alt="Datix Punto de Venta - Interfaz de gestión de ventas e inventario"
                    className="w-full transition-transform duration-700 group-hover:scale-[1.02]"
                  />
                </div>
              </div>
              <div className="reveal-right flex flex-col justify-center">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-brand-vivid/15 ring-1 ring-brand-vivid/20">
                  <Store className="h-7 w-7 text-brand-light" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-green-500/10 px-3 py-1 text-xs font-semibold text-green-400 ring-1 ring-inset ring-green-500/20">
                    ● Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
                  Datix POS & Almacén
                </h3>
                <p className="text-lg leading-relaxed text-white/60">
                  Vende más rápido y controla tu inventario sin errores. Ideal para negocios que manejan stock crítico y necesitan agilidad.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Punto de venta intuitivo y veloz",
                    "Motor FEFO: Rotación inteligente por fecha de vencimiento",
                    "Alertas de stock bajo y módulo de fiados",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-white/70 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-brand-light flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            {/* ── Module 2: Adquisiciones ── */}
            <div className="grid grid-cols-1 items-center gap-12 lg:grid-cols-2 lg:gap-16">
              <div className="reveal-left order-last flex flex-col justify-center lg:order-first">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-purple-500/15 ring-1 ring-purple-500/20">
                  <ShoppingCart className="h-7 w-7 text-purple-400" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-green-500/10 px-3 py-1 text-xs font-semibold text-green-400 ring-1 ring-inset ring-green-500/20">
                    ● Disponible
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
                  Datix Adquisiciones
                </h3>
                <p className="text-lg leading-relaxed text-white/60">
                  Automatiza tus compras y mantén una relación impecable con tus proveedores. Nunca más te quedes sin stock.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Gestión centralizada de proveedores",
                    "Órdenes de compra automáticas al bajar el stock",
                    "Control riguroso de recepción de mercadería",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-white/70 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-purple-400 flex-shrink-0" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
              <div className="reveal-right relative group">
                <div className="absolute inset-0 -m-4 rounded-3xl bg-gradient-to-br from-purple-500/10 to-transparent blur-xl transition-all duration-500 group-hover:from-purple-500/20"></div>
                <div className="relative overflow-hidden rounded-2xl border border-white/10 shadow-2xl transition-all duration-500 group-hover:border-white/20 group-hover:shadow-purple-500/10">
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
                <div className="relative overflow-hidden rounded-2xl border border-white/10 shadow-2xl transition-all duration-500 group-hover:border-white/20 group-hover:shadow-teal-500/10">
                  <img
                    src="/imagen/mockup_farmacias.png"
                    alt="Datix Farmacias - Sistema de gestión farmacéutica con trazabilidad"
                    className="w-full transition-transform duration-700 group-hover:scale-[1.02]"
                  />
                </div>
              </div>
              <div className="reveal-right flex flex-col justify-center">
                <div className="mb-6 inline-flex h-14 w-14 items-center justify-center rounded-2xl bg-teal-500/15 ring-1 ring-teal-500/20">
                  <Pill className="h-7 w-7 text-teal-400" />
                </div>
                <div className="mb-3">
                  <span className="inline-flex items-center rounded-full bg-amber-500/10 px-3 py-1 text-xs font-semibold text-amber-400 ring-1 ring-inset ring-amber-500/20">
                    ◷ Próximamente
                  </span>
                </div>
                <h3 className="mb-4 text-3xl font-extrabold tracking-tight sm:text-4xl">
                  Datix Farmacias
                </h3>
                <p className="text-lg leading-relaxed text-white/60">
                  Especializado en cumplimiento normativo y seguridad. Diseñado para la trazabilidad total de medicamentos.
                </p>
                <ul className="mt-8 space-y-4">
                  {[
                    "Trazabilidad de lotes y fechas de vencimiento",
                    "Integración FEFO para evitar mermas por caducidad",
                    "Gestión de recetas y stock de medicamentos críticos",
                  ].map((item, i) => (
                    <li key={i} className="flex items-center gap-3 text-white/70 font-medium">
                      <CheckCircle2 className="h-5 w-5 text-teal-400 flex-shrink-0" />
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
                  <h3 className="text-xl font-bold">Módulo Individual</h3>
                  <p className="mt-4 text-white/50">
                    Perfecto si solo necesitas resolver un área específica de tu negocio hoy.
                  </p>
                  <ul className="mt-8 space-y-4 text-sm font-medium">
                    {[
                      "Almacén o Adquisiciones",
                      "Soporte directo vía WhatsApp",
                      "Implementación inicial guiada",
                    ].map((item, i) => (
                      <li key={i} className="flex items-center gap-3 text-white/70">
                        <CheckCircle2 className="h-5 w-5 text-brand-light flex-shrink-0" />
                        {item}
                      </li>
                    ))}
                  </ul>
                </div>
                <Link
                  href="/register"
                  className="mt-10 block w-full rounded-xl border border-white/15 bg-white/5 py-3.5 text-center text-sm font-bold text-white transition-all hover:bg-white/10 hover:border-white/25"
                >
                  Comenzar Prueba Gratis
                </Link>
              </div>

              {/* Plan Combo */}
              <div className="reveal relative rounded-3xl bg-gradient-to-b from-brand-primary/60 to-brand-deep border border-brand-vivid/30 p-10 shadow-xl shadow-brand-vivid/10 transition-all duration-300 hover:-translate-y-1 hover:shadow-2xl hover:shadow-brand-vivid/20 flex flex-col justify-between" style={{ transitionDelay: "100ms" }}>
                <div className="absolute -top-4 left-1/2 -translate-x-1/2 rounded-full bg-gradient-to-r from-brand-accent to-brand-vivid px-5 py-1.5 text-xs font-bold text-white uppercase tracking-widest shadow-lg shadow-brand-vivid/30">
                  Más Popular
                </div>
                <div>
                  <h3 className="text-xl font-bold">Combo Gestión</h3>
                  <p className="mt-4 text-white/50">
                    Conecta tus ventas con tus compras para un control total y ahorro garantizado.
                  </p>
                  <ul className="mt-8 space-y-4 text-sm font-medium">
                    {[
                      "Almacén + Adquisiciones (FullSync)",
                      "Alertas de compras sugeridas",
                      "Prioridad en soporte personalizado",
                      "Todas las futuras integraciones incluidas",
                    ].map((item, i) => (
                      <li key={i} className="flex items-center gap-3 text-white/70">
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
              <p className="text-sm font-medium text-white/40">
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
        <div className="absolute inset-0 bg-gradient-to-b from-brand-deep via-brand-primary/20 to-brand-deep"></div>
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,rgba(142,67,217,0.12),transparent_70%)]"></div>

        <div className="relative z-10 mx-auto max-w-3xl px-6 text-center">
          <div className="reveal">
            <h2 className="text-3xl font-extrabold tracking-tight sm:text-5xl">
              ¿Listo para ordenar tu negocio?
            </h2>
            <p className="mt-6 text-lg text-white/50 leading-relaxed">
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
      <footer className="border-t border-white/[0.06] bg-brand-deep py-16">
        <div className="mx-auto max-w-7xl px-6 lg:px-8">
          <div className="flex flex-col items-center gap-8 md:flex-row md:justify-between">
            {/* Logo + Links */}
            <div className="flex flex-col items-center gap-6 md:flex-row">
              <Link href="/">
                <img
                  src="/imagen/logo_datix.png"
                  alt="Datix Logo"
                  className="h-12 w-auto brightness-0 invert opacity-70 transition-all hover:opacity-100 hover:drop-shadow-[0_0_10px_rgba(142,67,217,0.4)]"
                />
              </Link>
              <div className="hidden h-6 w-px bg-white/10 md:block"></div>
              <div className="flex gap-6 text-sm text-white/40">
                <Link href="#" className="transition-colors hover:text-white/70">
                  Términos y Condiciones
                </Link>
                <Link href="#" className="transition-colors hover:text-white/70">
                  Política de Privacidad
                </Link>
              </div>
            </div>

            {/* Copyright */}
            <p className="text-sm text-white/30">
              &copy; {new Date().getFullYear()} Datix SpA. Todos los derechos reservados.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
