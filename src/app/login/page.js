"use client";

import React, { useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import { Mail, Lock, ArrowRight, AlertCircle, CheckCircle2, ShieldCheck, Eye, Package, Building2 } from "lucide-react";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

const FEATURES = [
  { icon: Package, label: "Logística y Pañol", desc: "Control de herramientas y bodegas" },
  { icon: Building2, label: "Construcción", desc: "Avances reales vs cubicación teórica" },
  { icon: ShieldCheck, label: "Trazabilidad Total", desc: "Auditoría perpetua incluida en todo" },
];

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [isProcessingHash, setIsProcessingHash] = useState(false);
  const hasProcessedHash = React.useRef(false);

  React.useEffect(() => {
    const processHash = async () => {
      if (hasProcessedHash.current) return;
      if (typeof window !== "undefined" && window.location.hash.includes("access_token")) {
        hasProcessedHash.current = true;
        setIsProcessingHash(true);
        try {
          const hash = window.location.hash.substring(1);
          const params = new URLSearchParams(hash);
          const access_token = params.get("access_token");
          const refresh_token = params.get("refresh_token");
          if (access_token && refresh_token) {
            window.history.replaceState(null, "", window.location.pathname);
            const { error: sessionError } = await supabase.auth.setSession({ access_token, refresh_token });
            if (sessionError) throw sessionError;
            router.push("/portal");
          }
        } catch (err) {
          console.error("Error sincronizando sesión desde hash:", err);
          setIsProcessingHash(false);
        }
      }
    };
    processHash();
  }, [router]);

  const handleLogin = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const { data, error: signInError } = await supabase.auth.signInWithPassword({ email, password });
      if (signInError) {
        let msg = signInError.message;
        if (msg.includes("Invalid login credentials")) msg = "Correo electrónico o contraseña incorrectos.";
        throw new Error(msg);
      }
      await supabase.auth.refreshSession();
      router.push("/portal");
    } catch (err) {
      setError(err.message || "Ocurrió un error inesperado.");
    } finally {
      setLoading(false);
    }
  };

  if (loading || isProcessingHash) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-white">
        <div className="text-center">
          <div className="h-10 w-10 animate-spin rounded-full border-4 border-violet-600 border-t-transparent mx-auto mb-4"></div>
          <p className="text-slate-500 font-medium">Sincronizando tu sesión...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen font-sans bg-white">
      {/* ── LEFT: Form ── */}
      <div className="flex w-full flex-col justify-center items-center p-8 lg:w-1/2">
        <div className="w-full max-w-md">
          {/* Logo */}
          <Link href="/" className="flex items-center gap-2 mb-10">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-8 w-auto brightness-0 opacity-90 transition-all hover:opacity-100" priority />
          </Link>

          <div className="mb-8">
            <h1 className="text-3xl font-extrabold text-slate-900 tracking-tight mb-2">Bienvenido de vuelta</h1>
            <p className="text-slate-500 font-medium">Ingresa a tu plataforma operacional.</p>
          </div>

          <form onSubmit={handleLogin} className="space-y-5">
            <div>
              <label className="block text-sm font-bold text-slate-700 mb-1.5">Correo Electrónico</label>
              <div className="relative">
                <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  required
                  placeholder="tu@empresa.com"
                  className="w-full rounded-xl border border-slate-200 bg-slate-50 py-3.5 pl-11 pr-4 text-slate-900 font-medium placeholder:text-slate-400 focus:border-violet-500 focus:bg-white focus:outline-none focus:ring-2 focus:ring-violet-500/20 transition-all"
                />
              </div>
            </div>

            <div>
              <div className="flex justify-between items-center mb-1.5">
                <label className="block text-sm font-bold text-slate-700">Contraseña</label>
                <Link href="/forgot-password" className="text-xs font-bold text-violet-600 hover:text-violet-700 transition-colors">
                  ¿Olvidaste tu contraseña?
                </Link>
              </div>
              <div className="relative">
                <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                <input
                  type="password"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  required
                  placeholder="••••••••"
                  className="w-full rounded-xl border border-slate-200 bg-slate-50 py-3.5 pl-11 pr-4 text-slate-900 font-medium placeholder:text-slate-400 focus:border-violet-500 focus:bg-white focus:outline-none focus:ring-2 focus:ring-violet-500/20 transition-all"
                />
              </div>
            </div>

            {error && (
              <div className="flex items-center gap-3 rounded-xl bg-red-50 border border-red-100 p-4 text-sm text-red-600">
                <AlertCircle className="h-5 w-5 flex-shrink-0" />
                <p className="font-medium">{error}</p>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-violet-600 py-4 text-sm font-bold text-white shadow-lg shadow-violet-500/30 hover:bg-violet-700 hover:-translate-y-0.5 active:scale-[0.98] transition-all disabled:opacity-70 disabled:cursor-not-allowed"
            >
              {loading ? "Verificando..." : (<>Ingresar al Portal <ArrowRight className="h-4 w-4" /></>)}
            </button>

            <p className="text-center text-sm text-slate-500 font-medium">
              ¿Aún no tienes cuenta?{" "}
              <Link href="/register" className="font-bold text-violet-600 hover:text-violet-700 transition-colors">
                Regístrate aquí
              </Link>
            </p>
          </form>
        </div>
      </div>

      {/* ── RIGHT: Branding Panel ── */}
      <div className="hidden lg:flex w-1/2 flex-col justify-center relative overflow-hidden bg-gradient-to-br from-violet-600 via-indigo-600 to-indigo-700 p-16">
        {/* Background dots */}
        <div className="absolute inset-0 opacity-10" style={{backgroundImage:"radial-gradient(circle,white 1px,transparent 1px)",backgroundSize:"28px 28px"}}/>
        {/* Glow blobs */}
        <div className="absolute top-0 right-0 w-96 h-96 bg-white/10 rounded-full blur-3xl -translate-y-1/2 translate-x-1/2"/>
        <div className="absolute bottom-0 left-0 w-80 h-80 bg-indigo-400/30 rounded-full blur-3xl translate-y-1/3 -translate-x-1/3"/>

        <div className="relative z-10">
          <Link href="/" className="flex items-center gap-2 mb-12">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-8 w-auto opacity-100 transition-all hover:scale-105" priority />
          </Link>

          <h2 className="text-4xl font-extrabold text-white leading-tight mb-4">
            Control total.<br/>Trazabilidad real.
          </h2>
          <p className="text-violet-200 font-medium text-lg mb-12 leading-relaxed">
            La plataforma que protege el margen financiero de tu empresa desde la compra hasta la obra terminada.
          </p>

          <div className="space-y-5">
            {FEATURES.map(({ icon: Icon, label, desc }, i) => (
              <div key={i} className="flex items-start gap-4 bg-white/10 border border-white/20 rounded-xl p-4 backdrop-blur-sm">
                <div className="h-10 w-10 rounded-lg bg-white/20 flex items-center justify-center flex-shrink-0">
                  <Icon className="h-5 w-5 text-white" />
                </div>
                <div>
                  <p className="text-sm font-extrabold text-white">{label}</p>
                  <p className="text-xs text-violet-200 font-medium mt-0.5">{desc}</p>
                </div>
              </div>
            ))}
          </div>

          <div className="mt-10 flex items-center gap-2 text-violet-200 text-xs font-medium">
            <ShieldCheck className="h-4 w-4" />
            Auditoría perpetua · Aislamiento multi-empresa · Sin letra chica
          </div>
        </div>
      </div>
    </div>
  );
}
