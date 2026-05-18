"use client";
import React, { useEffect, useState } from "react";
import { ArrowRight, CheckCircle2, ShieldCheck, BarChart3, ChevronDown, Menu, X, Building2, Package, ShoppingCart, Database, Lock, TrendingDown, Eye, Wrench, Activity, AlertTriangle, Zap, Network, Terminal } from "lucide-react";
import Link from "next/link";
import Image from "next/image";
import HeroMockup from "./_components/HeroMockup";
import ModuleFlow from "./_components/ModuleFlow";
import DashboardMockup from "./_components/DashboardMockup";

function useReveal() {
  useEffect(() => {
    const io = new IntersectionObserver((entries) => {
      entries.forEach((e) => {
        if (e.isIntersecting) { e.target.style.opacity = "1"; e.target.style.transform = "translateY(0)"; }
      });
    }, { threshold: 0.1, rootMargin: "0px 0px -40px 0px" });
    document.querySelectorAll(".rv").forEach((el) => {
      el.style.opacity = "0"; el.style.transform = "translateY(24px)";
      el.style.transition = "opacity .65s cubic-bezier(.16,1,.3,1), transform .65s cubic-bezier(.16,1,.3,1)";
      io.observe(el);
    });
    return () => io.disconnect();
  }, []);
}

function Navbar() {
  const [scrolled, setScrolled] = useState(false);
  const [open, setOpen] = useState(false);
  useEffect(() => {
    const fn = () => setScrolled(window.scrollY > 20);
    window.addEventListener("scroll", fn);
    return () => window.removeEventListener("scroll", fn);
  }, []);
  return (
    <>
      {open && (
        <div className="fixed inset-0 z-[60] bg-white flex flex-col items-center justify-center gap-8 md:hidden">
          <button onClick={() => setOpen(false)} className="absolute top-6 right-6"><X className="h-7 w-7 text-slate-500" /></button>
          {["#modulos","#integracion","#seguridad","#resultados"].map((h, i) => (
            <Link key={i} href={h} onClick={() => setOpen(false)} className="text-xl font-bold text-slate-800 hover:text-violet-600 transition-colors capitalize">{h.replace("#","")}</Link>
          ))}
          <div className="flex flex-col w-60 gap-3 mt-4">
            <Link href="/login" onClick={() => setOpen(false)} className="border border-slate-300 rounded-full px-6 py-3 text-center font-semibold text-slate-700 hover:bg-slate-50">Ingresar</Link>
            <Link href="/register" onClick={() => setOpen(false)} className="bg-violet-600 rounded-full px-6 py-3 text-center font-bold text-white hover:bg-violet-700">Solicitar Acceso</Link>
          </div>
        </div>
      )}
      <header className={`fixed top-0 inset-x-0 z-50 transition-all duration-300 ${scrolled ? "bg-white/90 backdrop-blur-lg border-b border-slate-200 shadow-sm" : "bg-transparent"}`}>
        <div className="mx-auto max-w-7xl flex h-[68px] items-center justify-between px-6">
          <Link href="/" className="flex items-center gap-2 font-extrabold text-lg text-slate-900">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={100} height={32} className="h-7 w-auto brightness-0 opacity-90 transition-all" priority />
          </Link>
          <nav className="hidden md:flex gap-7 text-sm font-semibold text-slate-600">
            {[["Módulos","#modulos"],["Seguridad","#seguridad"],["Beneficios","#resultados"],["Recursos","#"]].map(([l,h],i)=>(
              <Link key={i} href={h} className="hover:text-violet-600 transition-colors flex items-center gap-1">{l}<ChevronDown className="h-3.5 w-3.5 opacity-50"/></Link>
            ))}
          </nav>
          <div className="hidden md:flex items-center gap-3">
            <Link href="/login" className="text-sm font-bold text-slate-600 hover:text-slate-900 px-4 py-2 transition-colors">Ingresar</Link>
            <Link href="/register" className="rounded-full bg-violet-600 px-5 py-2.5 text-sm font-bold text-white shadow-md shadow-violet-500/30 hover:bg-violet-700 hover:scale-105 active:scale-95 transition-all">Solicitar Acceso</Link>
          </div>
          <button className="md:hidden" onClick={() => setOpen(true)}><Menu className="h-6 w-6 text-slate-600" /></button>
        </div>
      </header>
    </>
  );
}

export default function LandingPage() {
  useReveal();
  return (
    <div className="min-h-screen bg-white font-sans text-slate-600 selection:bg-violet-100">
      <style dangerouslySetInnerHTML={{__html:`
        @keyframes floatY{0%,100%{transform:translateY(0)}50%{transform:translateY(-10px)}}
        @keyframes floatY2{0%,100%{transform:translateY(0)}50%{transform:translateY(10px)}}
        .float{animation:floatY 6s ease-in-out infinite}
        .float2{animation:floatY2 7s ease-in-out infinite}
        .bg-dots{background-image:radial-gradient(circle,#e2e8f0 1px,transparent 1px);background-size:28px 28px}
      `}}/>
      <Navbar />

      {/* ── HERO ── */}
      <section className="relative pt-28 pb-20 sm:pt-36 sm:pb-28 overflow-hidden bg-gradient-to-b from-violet-50/60 via-white to-white">
        <div className="absolute inset-0 bg-dots opacity-60 [mask-image:linear-gradient(to_bottom,white_40%,transparent)]" />
        <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[900px] h-[400px] bg-violet-400/10 blur-[120px] rounded-full pointer-events-none" />
        <div className="relative z-10 mx-auto max-w-7xl px-6">
          <div className="mb-5 text-[11px] font-bold text-slate-500 flex items-center gap-1.5">
            <span className="text-violet-600">←</span> SaaS Operacional para Empresas Reales
          </div>
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-14 items-center">
            <div>
              <h1 className="text-4xl sm:text-5xl lg:text-6xl font-extrabold leading-[1.1] tracking-tight text-slate-900 mb-6">
                Control total sobre tus <span className="text-violet-600">pérdidas operativas.</span>
              </h1>
              <p className="text-lg text-slate-600 font-medium leading-relaxed mb-10 max-w-lg">
                Plataforma de grado empresarial para el control logístico y de obras. Trazabilidad absoluta, presupuestos conectados y auditoría financiera para constructoras y contratistas.
              </p>
              <div className="flex flex-wrap gap-4">
                <Link href="/register" className="group flex items-center gap-2 rounded-full bg-violet-600 px-8 py-4 font-bold text-white shadow-xl shadow-violet-500/30 hover:bg-violet-700 hover:-translate-y-0.5 active:scale-95 transition-all">
                  Solicitar Acceso Gratuito <ArrowRight className="h-4 w-4 group-hover:translate-x-1 transition-transform" />
                </Link>
                <Link href="#modulos" className="flex items-center gap-2 rounded-full border border-slate-300 bg-white px-8 py-4 font-bold text-slate-700 shadow-sm hover:bg-slate-50 hover:border-violet-300 transition-all">
                  Explorar Módulos
                </Link>
              </div>
              <div className="mt-8 flex flex-wrap gap-6 text-sm text-slate-500 font-medium">
                {["Multiempresa","Datos Seguros","Auditoría Total","Escalable"].map((t,i)=>(
                  <span key={i} className="flex items-center gap-1.5"><CheckCircle2 className="h-4 w-4 text-violet-500"/>{t}</span>
                ))}
              </div>
            </div>
            <div className="float lg:pl-4 relative">
              <HeroMockup />
            </div>
          </div>
        </div>
      </section>

      {/* ── PROBLEMA ── */}
      <section className="py-20 bg-white border-y border-slate-100">
        <div className="mx-auto max-w-7xl px-6">
          <div className="rv text-center mb-14">
            <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 mb-3">Las fugas financieras son <span className="text-violet-600">silenciosas.</span></h2>
            <p className="text-slate-500 font-medium">Pequeñas fallas diarias que generan pérdidas críticas al final del proyecto.</p>
          </div>
          <div className="rv grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-6">
            {[
              { icon: Wrench, label: "Pérdida de herramientas" },
              { icon: Database, label: "Descontrol de materiales" },
              { icon: TrendingDown, label: "Stock poco confiable" },
              { icon: ShoppingCart, label: "Sobrepagos a subcontratistas" },
              { icon: Eye, label: "Ausencia de trazabilidad" },
              { icon: Network, label: "Falta de visibilidad entre áreas" },
            ].map(({icon: Icon, label}, i) => (
              <div key={i} className="flex flex-col items-center text-center gap-3 p-5 rounded-2xl hover:bg-violet-50 hover:border-violet-100 border border-transparent transition-all">
                <div className="h-12 w-12 rounded-xl bg-violet-100 flex items-center justify-center"><Icon className="h-6 w-6 text-violet-600"/></div>
                <p className="text-xs font-bold text-slate-700 leading-snug">{label}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── MÓDULOS ── */}
      <section id="modulos" className="py-24 bg-slate-50">
        <div className="mx-auto max-w-7xl px-6">
          <div className="rv text-center mb-6">
            <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 mb-4">
              Una plataforma modular que <span className="text-violet-600">crece contigo</span>
            </h2>
            <p className="text-slate-500 font-medium max-w-xl mx-auto">Empieza con un módulo para ordenar la operación hoy. Integra todos cuando la operación lo necesite.</p>
          </div>
          <div className="rv mb-6">
            <Link href="/register" className="inline-flex items-center gap-2 rounded-full bg-white border border-violet-200 text-violet-700 font-bold text-sm px-5 py-2 shadow-sm hover:bg-violet-50 transition-all">
              Ver cómo funciona →
            </Link>
          </div>
          <div className="rv">
            <ModuleFlow />
          </div>
          <p className="rv text-center text-xs text-slate-400 font-medium mt-8">● Empieza simple, escala en Datix</p>
        </div>
      </section>

      {/* ── INTEGRACIÓN / DASHBOARD ── */}
      <section id="integracion" className="py-24 bg-white">
        <div className="mx-auto max-w-7xl px-6">
          <div className="rv text-center mb-14">
            <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 mb-3">Tu operación, <span className="text-violet-600">100% integrada</span></h2>
            <p className="text-slate-500 font-medium">Cuando fluye la información de compras, logística y obras en tiempo real.</p>
          </div>
          <div className="rv">
            <DashboardMockup />
          </div>
        </div>
      </section>

      {/* ── SEGURIDAD ── */}
      <section id="seguridad" className="py-24 bg-slate-50 border-y border-slate-100">
        <div className="mx-auto max-w-7xl px-6">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
            <div className="rv">
              <div className="rounded-2xl overflow-hidden border border-slate-700/40 bg-[#0d0d10] shadow-2xl font-mono text-xs">
                <div className="flex items-center gap-2 px-4 py-3 bg-[#161618] border-b border-slate-800">
                  <span className="w-3 h-3 rounded-full bg-red-500"/><span className="w-3 h-3 rounded-full bg-amber-500"/><span className="w-3 h-3 rounded-full bg-emerald-500"/>
                  <span className="ml-3 text-slate-500 flex items-center gap-1.5"><Terminal size={11}/> Registro de Auditoría</span>
                </div>
                <div className="p-6 space-y-2 leading-relaxed">
                  {[
                    ["14:32:01","text-slate-400","00:14:32.001","ROTOMARTILLO X2","15.342.112-K","",  "ASIGNADO","text-indigo-400"],
                    ["14:32:04","text-slate-400","00:14:32.004","CEMENTO 25KG +500","RECEPCIÓN","C-04-B","","text-emerald-400"],
                    ["14:32:09","text-red-400",  "00:14:32.009","PAGO SUBCONTRATO","EXCEDE CUBICACIÓN","","RECHAZADO","text-red-400"],
                  ].map(([t,tc,ts,action,detail,loc,status,sc],i)=>(
                    <div key={i} className="grid grid-cols-[auto_1fr] gap-4 items-start border-b border-slate-800/60 pb-2">
                      <span className={`text-[10px] ${tc} whitespace-nowrap`}>[{t}]</span>
                      <div>
                        <span className="text-slate-300 font-semibold">{action}</span>
                        {detail && <span className="text-slate-500"> — {detail}</span>}
                        {status && <span className={`ml-2 px-1.5 py-0.5 rounded text-[9px] font-bold ${sc} bg-current/10`}>{status}</span>}
                      </div>
                    </div>
                  ))}
                  <p className="text-emerald-400 text-[10px] pt-1">datix@core ~ % <span className="animate-pulse">_</span></p>
                </div>
              </div>
            </div>
            <div className="rv">
              <div className="inline-flex items-center gap-2 rounded-full border border-violet-200 bg-violet-50 px-3 py-1 text-xs font-bold text-violet-700 mb-6">
                <Lock className="h-4 w-4" /> Seguridad y arquitectura de grado empresarial
              </div>
              <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 mb-6">Transacciones irrompibles.<br/><span className="text-slate-400">Cero descuadres.</span></h2>
              <ul className="space-y-4">
                {[
                  "Transacciones atómicas con rollback automático",
                  "Aislamiento multi-tenant a nivel de base de datos",
                  "Auditoría perpetua de cada operación",
                  "RLS + Políticas de seguridad a nivel perimetral",
                  "Disponibilidad, backups y monitoreo proactivo",
                ].map((item,i)=>(
                  <li key={i} className="flex items-center gap-3 text-slate-700 font-medium">
                    <CheckCircle2 className="h-5 w-5 text-violet-500 flex-shrink-0"/>{item}
                  </li>
                ))}
              </ul>
            </div>
          </div>
        </div>
      </section>

      {/* ── RESULTADOS ── */}
      <section id="resultados" className="py-24 bg-white">
        <div className="mx-auto max-w-7xl px-6">
          <div className="rv text-center mb-14">
            <h2 className="text-3xl sm:text-4xl font-extrabold text-slate-900 mb-3">Resultados que <span className="text-violet-600">impactan tu margen</span></h2>
            <p className="text-slate-500 font-medium">Más control, menos pérdidas. Mejores decisiones.</p>
          </div>
          <div className="rv grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-5 gap-6">
            {[
              { stat: "30%", label: "Menos pérdidas operativas" },
              { stat: "100%", label: "Stock auditable" },
              { stat: "20%+", label: "Ahorro en adquisiciones" },
              { icon: Building2, label: "Control por obra y empresa" },
              { icon: Eye, label: "Trazabilidad completa de movimientos y costos" },
            ].map((item,i)=>(
              <div key={i} className="flex flex-col items-center text-center gap-3 p-6 rounded-2xl bg-slate-50 border border-slate-100 hover:shadow-md hover:border-violet-100 transition-all">
                {item.stat ? (
                  <p className="text-3xl font-black text-violet-600">{item.stat}</p>
                ) : (
                  <div className="h-12 w-12 rounded-xl bg-violet-100 flex items-center justify-center">
                    <item.icon className="h-6 w-6 text-violet-600"/>
                  </div>
                )}
                <p className="text-xs font-bold text-slate-700 leading-snug">{item.label}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── CTA FINAL ── */}
      <section className="py-20 bg-gradient-to-r from-violet-600 to-indigo-600">
        <div className="mx-auto max-w-4xl px-6">
          <div className="rv flex flex-col md:flex-row items-center justify-between gap-8">
            <div className="text-white text-center md:text-left">
              <h2 className="text-2xl sm:text-3xl font-extrabold mb-2">Empieza con un módulo.<br/>Escala cuando tu operación lo necesite.</h2>
              <p className="text-violet-200 font-medium">Sin contratos largos, sin implementaciones complejas, sin letra chica.</p>
            </div>
            <div className="flex flex-col sm:flex-row gap-3 flex-shrink-0">
              <Link href="/register" className="rounded-full bg-white px-8 py-4 font-bold text-violet-700 shadow-xl hover:bg-violet-50 hover:scale-105 active:scale-95 transition-all whitespace-nowrap text-center">
                Solicitar Acceso Gratuito
              </Link>
              <Link href="#modulos" className="rounded-full border border-white/40 bg-white/10 px-8 py-4 font-bold text-white hover:bg-white/20 transition-all whitespace-nowrap text-center">
                Ver Módulos
              </Link>
            </div>
          </div>
        </div>
      </section>

      {/* ── FOOTER ── */}
      <footer className="border-t border-slate-200 bg-slate-50 py-14">
        <div className="mx-auto max-w-7xl px-6">
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-8 mb-10">
            <div>
              <div className="flex items-center gap-2 font-extrabold text-slate-900 mb-4">
                <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={80} height={24} className="h-5 w-auto brightness-0 opacity-80" />
              </div>
              <p className="text-xs text-slate-500 font-medium leading-relaxed">Plataforma modular de control operativo y trazabilidad para constructoras y logística.</p>
            </div>
            {[
              { title: "Producto", links: ["Módulos","Funciones","Seguridad","Precios"] },
              { title: "Recursos", links: ["Documentación","Blog","Casos de uso","Estado del sistema"] },
              { title: "Empresa", links: ["Acerca de","Contacto","Privacidad","Términos"] },
            ].map(({ title, links }, i) => (
              <div key={i}>
                <h4 className="text-xs font-extrabold text-slate-900 uppercase tracking-wider mb-4">{title}</h4>
                <ul className="space-y-2">
                  {links.map((l, j) => <li key={j}><Link href="#" className="text-sm text-slate-500 hover:text-violet-600 font-medium transition-colors">{l}</Link></li>)}
                </ul>
              </div>
            ))}
          </div>
          <div className="border-t border-slate-200 pt-8 flex flex-col sm:flex-row justify-between items-center gap-4">
            <p className="text-sm text-slate-500">&copy; {new Date().getFullYear()} Datix SpA. Todos los derechos reservados.</p>
            <div className="flex gap-4">
              {["LinkedIn","Twitter","GitHub"].map((s,i)=>(
                <Link key={i} href="#" className="text-xs font-bold text-slate-400 hover:text-violet-600 transition-colors">{s}</Link>
              ))}
            </div>
          </div>
        </div>
      </footer>
    </div>
  );
}
