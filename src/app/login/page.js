"use client";

import React, { useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";
import { Mail, Lock, ArrowRight, AlertCircle } from "lucide-react";

// Inicializa el cliente de Supabase (fuera del componente para evitar re-creación)
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

export default function LoginPage() {
    const router = useRouter();

    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [isProcessingHash, setIsProcessingHash] = useState(false);
    const hasProcessedHash = React.useRef(false);

    //  NUEVA ARQUITECTURA: Procesamiento de Hash para SSO desde los módulos
    React.useEffect(() => {
        const processHash = async () => {
            if (hasProcessedHash.current) return;
            if (typeof window !== 'undefined' && window.location.hash.includes('access_token')) {
                hasProcessedHash.current = true;
                setIsProcessingHash(true);
                try {
                    const hash = window.location.hash.substring(1);
                    const params = new URLSearchParams(hash);
                    const access_token = params.get('access_token');
                    const refresh_token = params.get('refresh_token');

                    if (access_token && refresh_token) {
                        // Limpiamos el hash para que no se vea feo
                        window.history.replaceState(null, '', window.location.pathname);

                        const { error: sessionError } = await supabase.auth.setSession({
                            access_token,
                            refresh_token
                        });

                        if (sessionError) throw sessionError;

                        // No refrescamos manualmente aquí para evitar 429 (Rate Limit)
                        router.push('/portal');
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
            const { data, error: signInError } = await supabase.auth.signInWithPassword({
                email: email,
                password: password,
            });

            if (signInError) {
                // Traducir error común
                let errorMessage = signInError.message;
                if (errorMessage.includes("Invalid login credentials")) {
                    errorMessage = "Correo electrónico o contraseña incorrectos.";
                }
                throw new Error(errorMessage);
            }

            // Si es exitoso, refrescamos la sesión para obtener el company_id inyectado por el Trigger
            await supabase.auth.refreshSession();
            router.push('/portal');

        } catch (err) {
            console.error("Error al iniciar sesión:", err);
            setError(err.message || "Ocurrió un error inesperado al intentar ingresar.");
        } finally {
            setLoading(false);
        }
    };

    if (loading || isProcessingHash) {
        return (
            <div className="flex min-h-screen items-center justify-center bg-brand-deep">
                <div className="text-center">
                    <div className="h-10 w-10 animate-spin rounded-full border-4 border-brand-vivid border-t-transparent mx-auto mb-4"></div>
                    <p className="text-white/60 font-medium">Sincronizando tu sesión...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="flex min-h-screen font-sans text-slate-900 selection:bg-brand-vivid/30">

            {/* Lado Izquierdo (Formulario de Login) */}
            <div className="flex w-full items-center justify-center bg-white p-8 lg:w-1/2">
                <div className="w-full max-w-md animate-fade-in-up">

                    {/* Header en Móvil */}
                    <div className="mb-8 text-center lg:hidden">
                        <Link href="/">
                            <img src="/imagen/logo_datix.png" alt="Datix Logo" className="h-16 w-auto mx-auto" />
                        </Link>
                    </div>

                    <div className="mb-10 text-center lg:text-left">
                        <h1 className="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
                            Iniciar Sesión
                        </h1>
                        <p className="mt-3 text-slate-500">
                            Ingresa a tu portal para gestionar tu negocio.
                        </p>
                    </div>

                    <form onSubmit={handleLogin} className="space-y-6">
                        <div className="space-y-4">
                            {/* Input Email */}
                            <div>
                                <label className="mb-1 block text-sm font-medium text-slate-700">Correo Electrónico</label>
                                <div className="relative">
                                    <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                        <Mail className="h-5 w-5" />
                                    </div>
                                    <input
                                        type="email"
                                        value={email}
                                        onChange={(e) => setEmail(e.target.value)}
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
                                        value={password}
                                        onChange={(e) => setPassword(e.target.value)}
                                        required
                                        className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                        placeholder="••••••••"
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Enlace Olvidó Contraseña */}
                        <div className="flex justify-end">
                            <Link href="/forgot-password" className="text-sm font-medium text-brand-accent hover:text-brand-vivid transition-colors">
                                ¿Olvidaste tu contraseña?
                            </Link>
                        </div>

                        {/* Manejo de Error */}
                        {error && (
                            <div className="flex items-center gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-600 ring-1 ring-inset ring-red-600/20 animate-fade-in-up">
                                <AlertCircle className="h-5 w-5 flex-shrink-0" />
                                <p>{error}</p>
                            </div>
                        )}

                        {/* Botón Submit */}
                        <div className="pt-2">
                            <button
                                type="submit"
                                disabled={loading}
                                className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-brand-accent to-brand-vivid px-4 py-3.5 text-center text-sm font-bold text-white shadow-lg shadow-violet-900/25 transition-all hover:shadow-xl hover:shadow-violet-900/35 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-70"
                            >
                                {loading ? "Verificando..." : (
                                    <>
                                        Ingresar al Portal <ArrowRight className="h-4 w-4" />
                                    </>
                                )}
                            </button>
                        </div>

                        {/* Enlace Registro */}
                        <div className="text-center pt-2">
                            <p className="text-sm text-slate-600">
                                ¿Aún no tienes cuenta?{" "}
                                <Link href="/register" className="font-semibold text-brand-accent hover:text-brand-vivid transition-colors">
                                    Regístrate aquí
                                </Link>
                            </p>
                        </div>
                    </form>
                </div>
            </div>

            {/* Lado Derecho (Branding / Marketing) */}
            <div className="relative hidden w-1/2 flex-col justify-center overflow-hidden bg-[linear-gradient(140deg,#F8F6FC_0%,#EEE9F8_52%,#E8DFF5_100%)] p-12 lg:flex xl:p-20">
                {/* Background Effects */}
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(142,67,217,0.2),transparent_60%)]"></div>
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_bottom_left,rgba(76,48,115,0.22),transparent_60%)]"></div>

                {/* Floating orbs */}
                <div className="absolute top-20 right-20 h-48 w-48 rounded-full bg-brand-vivid/[0.08] blur-3xl animate-float"></div>
                <div className="absolute bottom-20 left-10 h-64 w-64 rounded-full bg-brand-accent/[0.06] blur-3xl animate-float-slow"></div>

                {/* Grid pattern */}
                <div className="absolute inset-0 bg-[linear-gradient(rgba(124,58,237,0.08)_1px,transparent_1px),linear-gradient(90deg,rgba(124,58,237,0.08)_1px,transparent_1px)] bg-[size:48px_48px]"></div>

                {/* Contenido Centro */}
                <div className="relative z-10 flex flex-col items-center justify-center text-center">
                    <Link href="/">
                        <img
                            src="/imagen/logo_datix.png"
                            alt="Datix Logo"
                            className="h-28 w-auto drop-shadow-[0_6px_20px_rgba(124,58,237,0.28)] transition-all hover:scale-105"
                            style={{
                                filter:
                                    "brightness(0) saturate(100%) invert(31%) sepia(60%) saturate(1200%) hue-rotate(240deg) brightness(94%) contrast(106%)",
                            }}
                        />
                    </Link>
                    <h2 className="mt-8 text-3xl font-extrabold leading-tight text-slate-900 xl:text-4xl">
                        Bienvenido de vuelta a tu{" "}
                        <span className="gradient-text">Ecosistema.</span>
                    </h2>
                    <p className="mt-4 max-w-md text-lg text-slate-700">
                        Todas las herramientas que tu negocio necesita, siempre seguras y sincronizadas.
                    </p>
                </div>
            </div>

        </div>
    );
}
