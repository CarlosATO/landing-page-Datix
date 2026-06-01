"use client";

import React, { useState } from "react";
import Link from "next/link";
import Image from "next/image";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import { Building2, User, Mail, Lock, Package, ShoppingCart, CheckCircle2, AlertCircle, ShieldCheck } from "lucide-react";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

// Módulos actualizados para Datix (sin POS/Farmacia)
const MODULE_CATALOG = [
  { id: "LOGISTICA", metadataValue: "logistica", name: "Logística y Pañol", description: "Control de herramientas, bodegas y stock.", icon: Package, availableNow: true },
  { id: "CONSTRUCCION", metadataValue: "construccion", name: "Construcción", description: "Avances de obra y candado financiero.", icon: Building2, availableNow: true },
  { id: "ADQUISICIONES", metadataValue: "adquisiciones", name: "Adquisiciones", description: "Órdenes de compra y proveedores.", icon: ShoppingCart, availableNow: true },
];

const toUpperValue = (v) => (v ?? "").toString().toUpperCase();
const toEmailValue = (v) => (v ?? "").toString().trim().toLowerCase();

export default function RegisterPage() {
  const router = useRouter();
  const [formData, setFormData] = useState({ empresa: "", nombre: "", email: "", password: "", trialModule: "LOGISTICA" });
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [success, setSuccess] = useState(false);
  const [resendLoading, setResendLoading] = useState(false);

  const selectedModule = MODULE_CATALOG.find((m) => m.id === formData.trialModule) || MODULE_CATALOG[0];

  const handleChange = (e) => {
    const { name, value } = e.target;
    setFormData(prev => {
      if (name === "email") return { ...prev, [name]: toEmailValue(value) };
      if (name === "password" || name === "trialModule") return { ...prev, [name]: value };
      return { ...prev, [name]: toUpperValue(value) };
    });
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      const selectedModuleKey = selectedModule?.metadataValue || "logistica";
      const { data: authData, error: authError } = await supabase.auth.signUp({
        email: toEmailValue(formData.email),
        password: formData.password,
        options: {
          emailRedirectTo: `${window.location.origin}/login`,
          data: {
            full_name: toUpperValue(formData.nombre),
            empresa_nombre: toUpperValue(formData.empresa),
            modulo_inicial: selectedModuleKey,
            selected_module: selectedModuleKey,
            module_key: selectedModuleKey,
          }
        }
      });

      if (process.env.NODE_ENV !== "production") {
        console.debug("[register] signUp response", {
          userId: authData?.user?.id || null,
          userEmail: authData?.user?.email || null,
          identities: authData?.user?.identities || null,
          session: authData?.session || null,
          error: authError?.message || null,
        });
      }

      if (authError) throw new Error(authError.message);
      if (!authData.user) throw new Error("Error desconocido al crear usuario");
      if (!authData.session) { setSuccess(true); } else { router.push("/portal"); }
    } catch (err) {
      let msg = err.message || "Ocurrió un error inesperado.";
      if (msg.includes("User already registered")) msg = "Este correo ya está registrado. Por favor inicia sesión.";
      else if (msg.includes("Password")) msg = "La contraseña debe tener al menos 6 caracteres.";
      else if (msg.includes("rate limit exceeded")) msg = "Demasiados intentos. Espera un momento e inténtalo de nuevo.";
      setError(msg);
    } finally {
      setLoading(false);
    }
  };

  const handleResendConfirmation = async () => {
    setResendLoading(true);
    setError("");

    try {
      const { error: resendError } = await supabase.auth.resend({
        type: "signup",
        email: toEmailValue(formData.email),
        options: {
          emailRedirectTo: `${window.location.origin}/login`,
        },
      });

      if (resendError) throw resendError;
      setSuccess(true);
    } catch (err) {
      setError(err.message || "No se pudo reenviar la confirmación.");
    } finally {
      setResendLoading(false);
    }
  };

  const inputClass = "w-full rounded-xl border border-slate-200 bg-slate-50 py-3.5 pl-11 pr-4 text-slate-900 font-medium placeholder:text-slate-400 focus:border-violet-500 focus:bg-white focus:outline-none focus:ring-2 focus:ring-violet-500/20 transition-all";

  return (
    <div className="flex min-h-screen font-sans bg-white">

      {/* ── LEFT: Branding Panel ── */}
      <div className="hidden lg:flex w-1/2 flex-col justify-center relative overflow-hidden bg-gradient-to-br from-violet-600 via-indigo-600 to-indigo-700 p-16">
        <div className="absolute inset-0 opacity-10" style={{backgroundImage:"radial-gradient(circle,white 1px,transparent 1px)",backgroundSize:"28px 28px"}}/>
        <div className="absolute top-0 left-0 w-96 h-96 bg-white/10 rounded-full blur-3xl -translate-y-1/2 -translate-x-1/2"/>
        <div className="absolute bottom-0 right-0 w-80 h-80 bg-indigo-400/30 rounded-full blur-3xl translate-y-1/3 translate-x-1/3"/>

        <div className="relative z-10">
          <Link href="/" className="flex items-center gap-2 mb-12">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-8 w-auto opacity-100 transition-all hover:scale-105" priority />
          </Link>

          <h2 className="text-4xl font-extrabold text-white leading-tight mb-4">
            El primer paso para escalar tu operación.
          </h2>
          <p className="text-violet-200 font-medium text-lg mb-12 leading-relaxed">
            Sin tarjeta de crédito. Sin compromisos. Empieza con el módulo que más necesitas hoy.
          </p>

          <div className="space-y-4">
            {[
              "Sin tarjeta de crédito requerida.",
              "Cancela cuando quieras.",
              "Soporte local en Chile y Latinoamérica.",
              "Paga solo por lo que usas.",
              "Auditoría total incluida en todos los planes.",
            ].map((item, i) => (
              <div key={i} className="flex items-center gap-3">
                <CheckCircle2 className="h-5 w-5 text-violet-300 flex-shrink-0" />
                <span className="text-violet-100 font-medium text-sm">{item}</span>
              </div>
            ))}
          </div>

          <div className="mt-10 flex items-center gap-2 text-violet-300 text-xs font-medium">
            <ShieldCheck className="h-4 w-4" />
            Aislamiento multi-empresa · Transacciones atómicas · Datos seguros
          </div>
        </div>
      </div>

      {/* ── RIGHT: Form ── */}
      <div className="flex w-full flex-col justify-center items-center p-8 lg:w-1/2 overflow-y-auto">
        <div className="w-full max-w-md py-10">

          {/* Logo mobile */}
          <Link href="/" className="flex items-center gap-2 mb-8 lg:hidden">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-7 w-auto brightness-0 opacity-90 transition-all" priority />
          </Link>

          {/* Logo desktop */}
          <Link href="/" className="hidden lg:flex items-center gap-2 mb-8">
            <Image src="/imagen/logo_datix.png" alt="Datix Logo" width={110} height={36} className="h-8 w-auto brightness-0 opacity-90 transition-all" priority />
          </Link>

          <div className="mb-7">
            <h1 className="text-3xl font-extrabold text-slate-900 tracking-tight mb-2">Crea tu cuenta</h1>
            <p className="text-slate-500 font-medium">14 días gratis. Sin compromisos.</p>
          </div>

          {success ? (
            <div className="flex flex-col items-center text-center gap-4 rounded-2xl border border-violet-100 bg-violet-50 p-10">
              <div className="h-16 w-16 rounded-2xl bg-violet-600 flex items-center justify-center shadow-lg">
                <CheckCircle2 className="h-8 w-8 text-white" />
              </div>
              <h2 className="text-2xl font-extrabold text-slate-900">¡Cuenta casi lista!</h2>
              <p className="text-slate-600 font-medium leading-relaxed">Revisa tu bandeja de entrada. Te enviamos un enlace para confirmar tu correo y activar tu cuenta.</p>
              <p className="text-xs text-slate-500">Si no llega en unos minutos, revisa spam o vuelve a pedir el correo desde esta misma pantalla.</p>
              <Link href="/login" className="mt-2 w-full rounded-xl bg-violet-600 py-4 text-sm font-bold text-white shadow-lg hover:bg-violet-700 transition-all text-center">
                Ir a Iniciar Sesión
              </Link>
            </div>
          ) : (
            <form onSubmit={handleSubmit} className="space-y-5">
              {/* Empresa */}
              <div>
                <label className="block text-sm font-bold text-slate-700 mb-1.5">Nombre de tu Empresa</label>
                <div className="relative">
                  <Building2 className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                  <input type="text" name="empresa" value={formData.empresa} onChange={handleChange} required placeholder="Ej: Constructora Los Andes" className={inputClass} />
                </div>
              </div>

              {/* Nombre */}
              <div>
                <label className="block text-sm font-bold text-slate-700 mb-1.5">Tu Nombre Completo</label>
                <div className="relative">
                  <User className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                  <input type="text" name="nombre" value={formData.nombre} onChange={handleChange} required placeholder="Ej: Juan Pérez" className={inputClass} />
                </div>
              </div>

              {/* Email */}
              <div>
                <label className="block text-sm font-bold text-slate-700 mb-1.5">Correo Electrónico</label>
                <div className="relative">
                  <Mail className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                  <input type="email" name="email" value={formData.email} onChange={handleChange} required placeholder="tu@empresa.com" className={inputClass} />
                </div>
              </div>

              {/* Password */}
              <div>
                <label className="block text-sm font-bold text-slate-700 mb-1.5">Contraseña</label>
                <div className="relative">
                  <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400 pointer-events-none" />
                  <input type="password" name="password" value={formData.password} onChange={handleChange} required placeholder="Mínimo 6 caracteres" className={inputClass} />
                </div>
              </div>

              {/* Module Selection */}
              <div>
                <label className="block text-sm font-bold text-slate-700 mb-2">Elige tu módulo de prueba</label>
                <div className="grid grid-cols-1 gap-2">
                  {MODULE_CATALOG.map((mod) => {
                    const Icon = mod.icon;
                    const selected = formData.trialModule === mod.id;
                    return (
                      <button
                        key={mod.id}
                        type="button"
                        onClick={() => setFormData(prev => ({ ...prev, trialModule: mod.id }))}
                        className={`w-full rounded-xl border p-3.5 text-left transition-all flex items-start gap-3 ${
                          selected
                            ? "border-violet-500 bg-violet-50 ring-2 ring-violet-500/20"
                            : "border-slate-200 bg-slate-50 hover:bg-slate-100 hover:border-slate-300"
                        }`}
                      >
                        <div className={`mt-0.5 rounded-lg p-2 flex-shrink-0 ${selected ? "bg-violet-600 text-white" : "bg-slate-200 text-slate-500"}`}>
                          <Icon className="h-4 w-4" />
                        </div>
                        <div>
                          <p className={`text-sm font-bold ${selected ? "text-violet-700" : "text-slate-700"}`}>{mod.name}</p>
                          <p className="text-xs text-slate-500 mt-0.5 font-medium">{mod.description}</p>
                        </div>
                        {selected && <CheckCircle2 className="h-4 w-4 text-violet-600 ml-auto flex-shrink-0 mt-0.5" />}
                      </button>
                    );
                  })}
                </div>
                <p className="text-[11px] text-slate-400 font-medium mt-2">Trazabilidad Total incluida como capacidad transversal, no como módulo independiente.</p>
              </div>

              {error && (
                <div className="flex items-center gap-3 rounded-xl bg-red-50 border border-red-100 p-4 text-sm text-red-600">
                  <AlertCircle className="h-5 w-5 flex-shrink-0" />
                  <p className="font-medium">{error}</p>
                </div>
              )}

              {error.includes("ya está registrado") && (
                <button
                  type="button"
                  onClick={handleResendConfirmation}
                  disabled={resendLoading}
                  className="w-full rounded-xl border border-violet-200 bg-violet-50 py-3 text-sm font-bold text-violet-700 hover:bg-violet-100 transition-all disabled:opacity-70"
                >
                  {resendLoading ? "Reenviando confirmación..." : "Reenviar correo de confirmación"}
                </button>
              )}

              <button
                type="submit"
                disabled={loading}
                className="w-full rounded-xl bg-violet-600 py-4 text-sm font-bold text-white shadow-lg shadow-violet-500/30 hover:bg-violet-700 hover:-translate-y-0.5 active:scale-[0.98] transition-all disabled:opacity-70 disabled:cursor-not-allowed"
              >
                {loading ? "Creando tu cuenta..." : "Crear mi cuenta gratis"}
              </button>

              <p className="text-center text-sm text-slate-500 font-medium">
                ¿Ya tienes cuenta?{" "}
                <Link href="/login" className="font-bold text-violet-600 hover:text-violet-700 transition-colors">
                  Inicia sesión aquí
                </Link>
              </p>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
