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

    // 🔥 NUEVA ARQUITECTURA: Procesamiento de Hash para SSO desde los módulos
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
            <div className="flex min-h-screen items-center justify-center bg-white p-8">
                <div className="text-center">
                    <div className="h-10 w-10 animate-spin rounded-full border-4 border-blue-600 border-t-transparent mx-auto mb-4"></div>
                    <p className="text-slate-500 font-medium">Sincronizando tu sesión...</p>
                </div>
            </div>
        );
    }

    return (
        <div className="flex min-h-screen font-sans text-slate-900 selection:bg-blue-200">

            {/* Lado Izquierdo (Formulario de Login) */}
            <div className="flex w-full items-center justify-center bg-white p-8 lg:w-1/2">
                <div className="w-full max-w-md">

                    {/* Header en Móvil */}
                    <div className="mb-8 text-center lg:hidden">
                        <Link href="/" className="text-3xl font-black tracking-tighter text-blue-700">
                            Datix
                        </Link>
                    </div>

                    <div className="mb-10 text-center lg:text-left">
                        <h1 className="text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
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
                                        className="block w-full rounded-xl border border-slate-300 bg-white py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-colors placeholder:text-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
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
                                        className="block w-full rounded-xl border border-slate-300 bg-white py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-colors placeholder:text-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                                        placeholder="••••••••"
                                    />
                                </div>
                            </div>
                        </div>

                        {/* Enlace Olvidó Contraseña */}
                        <div className="flex justify-end">
                            <Link href="#" className="text-sm font-medium text-blue-600 hover:text-blue-500">
                                ¿Olvidaste tu contraseña?
                            </Link>
                        </div>

                        {/* Manejo de Error */}
                        {error && (
                            <div className="flex items-center gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-600 ring-1 ring-inset ring-red-600/20">
                                <AlertCircle className="h-5 w-5 flex-shrink-0" />
                                <p>{error}</p>
                            </div>
                        )}

                        {/* Botón Submit */}
                        <div className="pt-2">
                            <button
                                type="submit"
                                disabled={loading}
                                className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3.5 text-center text-sm font-semibold text-white shadow-md transition-all hover:bg-blue-500 hover:shadow-lg active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-70"
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
                                <Link href="/register" className="font-semibold text-blue-600 hover:text-blue-500">
                                    Regístrate aquí
                                </Link>
                            </p>
                        </div>
                    </form>
                </div>
            </div>

            {/* Lado Derecho (Branding / Marketing) */}
            <div className="relative hidden w-1/2 flex-col justify-center overflow-hidden bg-slate-900 p-12 lg:flex xl:p-20">
                {/* Fondo Decorativo Sutil */}
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,_var(--tw-gradient-stops))] from-blue-800/20 via-slate-900 to-slate-950"></div>

                {/* Contenido Centro */}
                <div className="relative z-10 flex flex-col items-center justify-center text-center">
                    <Link href="/" className="mb-8 text-5xl font-black tracking-tighter text-white">
                        Datix
                    </Link>
                    <h2 className="text-3xl font-bold leading-tight text-white xl:text-4xl">
                        Bienvenido de vuelta a tu Ecosistema.
                    </h2>
                    <p className="mt-4 text-lg text-slate-400">
                        Todas las herramientas que tu negocio necesita, siempre seguras y sincronizadas.
                    </p>
                </div>
            </div>

        </div>
    );
}
