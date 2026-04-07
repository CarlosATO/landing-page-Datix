"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import {
    Building2,
    User,
    Mail,
    Lock,
    CheckCircle2,
    AlertCircle
} from "lucide-react";

// Inicializa el cliente de Supabase (fuera del componente para evitar re-creación)
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

export default function RegisterPage() {
    const router = useRouter();

    // Estados del formulario
    const [formData, setFormData] = useState({
        empresa: "",
        nombre: "",
        email: "",
        password: "",
    });

    // Estados de UI
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState(false);

    const handleChange = (e) => {
        const { name, value } = e.target;
        setFormData(prev => ({ ...prev, [name]: value }));
    };



    const handleSubmit = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError("");

        try {
            // Paso 1: Crear Usuario Auth en Supabase
            const { data: authData, error: authError } = await supabase.auth.signUp({
                email: formData.email,
                password: formData.password,
                options: {
                    data: {
                        full_name: formData.nombre,
                        empresa_nombre: formData.empresa,
                        modulo_inicial: "pos" // Asegura que los triggers de DB funcionen
                    }
                }
            });

            if (authError) throw new Error(authError.message);
            if (!authData.user) throw new Error("Error desconocido al crear usuario");

            // Si se requiere confirmación de correo electrónico, la sesión será null.
            if (!authData.session) {
                setSuccess(true);
            } else {
                router.push("/portal");
            }

        } catch (err) {
            console.error("Error en el registro:", err);

            // Traducir los errores más comunes de Supabase al español
            let errorMessage = err.message || "Ocurrió un error inesperado al intentar registrarte.";
            if (errorMessage.includes("User already registered")) {
                errorMessage = "Este correo electrónico ya se encuentra registrado. Por favor, inicia sesión.";
            } else if (errorMessage.includes("Password")) {
                errorMessage = "La contraseña debe tener al menos 6 caracteres.";
            }

            setError(errorMessage);
        } finally {
            setLoading(false);
        }
    };



    return (
        <div className="flex min-h-screen font-sans text-white selection:bg-brand-vivid/30">

            {/* 1. Lado Izquierdo (Branding / Marketing) */}
            <div className="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-brand-deep p-12 lg:flex xl:p-20">
                {/* Background Effects */}
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_bottom_left,rgba(142,67,217,0.15),transparent_60%)]"></div>
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(76,48,115,0.2),transparent_60%)]"></div>

                {/* Floating orbs */}
                <div className="absolute top-32 right-20 h-64 w-64 rounded-full bg-brand-vivid/[0.07] blur-3xl animate-float"></div>
                <div className="absolute bottom-20 left-10 h-48 w-48 rounded-full bg-brand-accent/[0.06] blur-3xl animate-float-slow"></div>

                {/* Grid pattern */}
                <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:48px_48px]"></div>

                {/* Logo */}
                <div className="relative z-10">
                    <Link href="/">
                        <img
                            src="/imagen/logo_datix.png"
                            alt="Datix Logo"
                            className="h-28 w-auto brightness-0 invert drop-shadow-[0_0_20px_rgba(142,67,217,0.5)] transition-all hover:scale-105"
                        />
                    </Link>
                </div>

                {/* Texto Inspirador & Beneficios */}
                <div className="relative z-10 mt-auto">
                    <h2 className="mb-8 text-4xl font-extrabold leading-tight xl:text-5xl">
                        El primer paso para{" "}
                        <span className="gradient-text">escalar tu negocio</span>{" "}
                        de forma inteligente.
                    </h2>

                    <div className="space-y-5 text-lg text-white/60">
                        {[
                            "Sin tarjeta de crédito.",
                            "Cancela cuando quieras, sin amarras.",
                            "Soporte local en Chile y Latinoamérica.",
                            "Paga solo por lo que usas, crece a tu ritmo.",
                        ].map((item, i) => (
                            <div key={i} className="flex items-center gap-3">
                                <CheckCircle2 className="h-6 w-6 text-green-400 flex-shrink-0" />
                                <span>{item}</span>
                            </div>
                        ))}
                    </div>
                </div>
            </div>

            {/* 2. Lado Derecho (Formulario de Registro) */}
            <div className="flex w-full items-center justify-center bg-white p-8 lg:w-1/2">
                <div className="w-full max-w-md animate-fade-in-up">

                    {/* Header en Móvil */}
                    <div className="mb-8 text-center lg:hidden">
                        <Link href="/">
                            <img src="/imagen/logo_datix.png" alt="Datix Logo" className="h-16 w-auto mx-auto" />
                        </Link>
                    </div>

                    {/* Títulos */}
                    <div className="mb-10 text-center lg:text-left">
                        <h1 className="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
                            Crea tu Ecosistema
                        </h1>
                        <p className="mt-3 text-slate-500">
                            Comienza tus 14 días de prueba gratis. Sin compromisos.
                        </p>
                    </div>

                    {/* Formulario / Mensaje de Éxito */}
                    {success ? (
                        <div className="flex flex-col items-center justify-center space-y-4 rounded-3xl border border-slate-100 bg-surface-light p-10 text-center shadow-lg animate-scale-in">
                            <CheckCircle2 className="h-16 w-16 text-green-500" />
                            <h2 className="text-2xl font-extrabold gradient-text">¡Registro casi listo!</h2>
                            <p className="text-slate-600">
                                ¡Revisa tu bandeja de entrada! Te hemos enviado un enlace para confirmar tu correo y activar tu cuenta.
                            </p>
                            <Link href="/login" className="mt-6 w-full rounded-xl bg-gradient-to-r from-brand-primary to-brand-vivid px-4 py-3.5 text-sm font-bold text-white shadow-lg shadow-brand-vivid/20 transition-all hover:shadow-xl active:scale-[0.98]">
                                Ir a Iniciar Sesión
                            </Link>
                        </div>
                    ) : (
                        <form onSubmit={handleSubmit} className="space-y-6">

                            <div className="space-y-4">
                                {/* Input Empresa */}
                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Nombre de tu Empresa / Local</label>
                                    <div className="relative">
                                        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                            <Building2 className="h-5 w-5" />
                                        </div>
                                        <input
                                            type="text"
                                            name="empresa"
                                            value={formData.empresa}
                                            onChange={handleChange}
                                            required
                                            className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                            placeholder="Ej: Minimarket Los Andes"
                                        />
                                    </div>
                                </div>

                                {/* Input Nombre */}
                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Tu Nombre y Apellido</label>
                                    <div className="relative">
                                        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                            <User className="h-5 w-5" />
                                        </div>
                                        <input
                                            type="text"
                                            name="nombre"
                                            value={formData.nombre}
                                            onChange={handleChange}
                                            required
                                            className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                            placeholder="Ej: Juan Pérez"
                                        />
                                    </div>
                                </div>

                                {/* Input Email */}
                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Correo Electrónico</label>
                                    <div className="relative">
                                        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                            <Mail className="h-5 w-5" />
                                        </div>
                                        <input
                                            type="email"
                                            name="email"
                                            value={formData.email}
                                            onChange={handleChange}
                                            required
                                            className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                            placeholder="tu@email.com"
                                        />
                                    </div>
                                </div>

                                {/* Input Contraseña */}
                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Contraseña</label>
                                    <div className="relative">
                                        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                            <Lock className="h-5 w-5" />
                                        </div>
                                        <input
                                            type="password"
                                            name="password"
                                            value={formData.password}
                                            onChange={handleChange}
                                            required
                                            className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                            placeholder="••••••••"
                                        />
                                    </div>
                                </div>
                            </div>



                            {/* Error estético */}
                            {error && (
                                <div className="flex items-center gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-600 ring-1 ring-inset ring-red-600/20 animate-fade-in-up">
                                    <AlertCircle className="h-5 w-5 flex-shrink-0" />
                                    <p>{error}</p>
                                </div>
                            )}

                            {/* Botón Submit */}
                            <div className="pt-4">
                                <button
                                    type="submit"
                                    disabled={loading}
                                    className="w-full rounded-xl bg-gradient-to-r from-brand-primary to-brand-vivid px-4 py-3.5 text-center text-sm font-bold text-white shadow-lg shadow-brand-vivid/20 transition-all hover:shadow-xl hover:shadow-brand-vivid/30 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-70"
                                >
                                    {loading ? "Creando ecosistema..." : "Crear mi cuenta"}
                                </button>
                            </div>

                            {/* Enlace Login */}
                            <div className="text-center">
                                <p className="text-sm text-slate-600">
                                    ¿Ya tienes cuenta?{" "}
                                    <Link href="/login" className="font-semibold text-brand-accent hover:text-brand-vivid transition-colors">
                                        Inicia sesión aquí
                                    </Link>
                                </p>
                            </div>

                        </form>
                    )}

                </div>
            </div>
            {/* 3. Final del Layout */}
        </div>
    );
}
