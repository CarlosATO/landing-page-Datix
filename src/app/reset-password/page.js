"use client";

import React, { useState, useEffect } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Lock, ArrowRight, AlertCircle, CheckCircle2 } from "lucide-react";
import { createBrowserClient } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

export default function ResetPasswordPage() {
    const router = useRouter();
    const [password, setPassword] = useState("");
    const [confirmPassword, setConfirmPassword] = useState("");
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState(false);
    const [verifying, setVerifying] = useState(true);

    useEffect(() => {
        const checkSession = async () => {
            const { data: { session } } = await supabase.auth.getSession();
            if (!session && !window.location.hash.includes('access_token')) {
                setError("El enlace de recuperación ha expirado o es inválido. Por favor, solicita uno nuevo.");
            }
            setVerifying(false);
        };
        checkSession();
    }, []);

    const handleUpdate = async (e) => {
        e.preventDefault();
        
        if (password !== confirmPassword) {
            setError("Las contraseñas no coinciden.");
            return;
        }

        if (password.length < 6) {
            setError("La contraseña debe tener al menos 6 caracteres.");
            return;
        }

        setLoading(true);
        setError("");

        try {
            const { error: updateError } = await supabase.auth.updateUser({
                password: password
            });

            if (updateError) throw updateError;
            
            setSuccess(true);
            setTimeout(() => {
                router.push("/login");
            }, 3000);
        } catch (err) {
            console.error("Error en reset password update:", err);
            let msg = err.message || "Ocurrió un error al intentar actualizar la contraseña.";
            if (msg.includes("session missing")) {
                msg = "La sesión de seguridad ha expirado. Por favor, vuelve a solicitar el enlace de recuperación.";
            }
            setError(msg);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen font-sans text-slate-900 selection:bg-brand-vivid/30 bg-slate-50">
            <div className="flex w-full flex-col items-center justify-center p-8">
                <div className="mb-10 text-center">
                    <img
                        src="/imagen/logo_datix.png"
                        alt="Datix Logo"
                        className="h-20 w-auto mx-auto mb-8 transition-all hover:scale-105"
                    />
                    <h1 className="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
                        Establecer nueva contraseña
                    </h1>
                    <p className="mt-3 text-slate-500">
                        Por favor ingresa tu nueva contraseña de acceso.
                    </p>
                </div>

                <div className="w-full max-w-md animate-fade-in-up">
                    {verifying ? (
                        <div className="text-center p-12">
                            <div className="h-8 w-8 animate-spin rounded-full border-4 border-brand-accent border-t-transparent mx-auto mb-4"></div>
                            <p className="text-slate-500">Verificando enlace de seguridad...</p>
                        </div>
                    ) : success ? (
                        <div className="rounded-3xl border border-slate-100 bg-white p-10 text-center shadow-xl animate-scale-in">
                            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-100 text-green-600">
                                <CheckCircle2 className="h-8 w-8" />
                            </div>
                            <h2 className="text-2xl font-bold text-slate-900">¡Contraseña actualizada!</h2>
                            <p className="mt-4 text-slate-500">
                                Tu contraseña ha sido cambiada exitosamente. Serás redirigido al inicio de sesión en unos segundos.
                            </p>
                            <Link href="/login" className="mt-8 block w-full rounded-xl bg-gradient-to-r from-brand-primary to-brand-vivid px-4 py-3.5 text-center text-sm font-bold text-white shadow-lg transition-all hover:shadow-xl active:scale-[0.98]">
                                Volver al inicio de sesión ahora
                            </Link>
                        </div>
                    ) : (
                        <div className="rounded-3xl border border-slate-100 bg-white p-10 shadow-xl">
                            <form onSubmit={handleUpdate} className="space-y-6">
                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Nueva Contraseña</label>
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

                                <div>
                                    <label className="mb-1 block text-sm font-medium text-slate-700">Confirmar Nueva Contraseña</label>
                                    <div className="relative">
                                        <div className="pointer-events-none absolute inset-y-0 left-0 flex items-center pl-3 text-slate-400">
                                            <Lock className="h-5 w-5" />
                                        </div>
                                        <input
                                            type="password"
                                            value={confirmPassword}
                                            onChange={(e) => setConfirmPassword(e.target.value)}
                                            required
                                            className="block w-full rounded-xl border border-slate-200 bg-slate-50/50 py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-all placeholder:text-slate-400 focus:border-brand-accent focus:bg-white focus:outline-none focus:ring-2 focus:ring-brand-vivid/20"
                                            placeholder="••••••••"
                                        />
                                    </div>
                                </div>

                                {error && (
                                    <div className="flex items-center gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-600 ring-1 ring-inset ring-red-600/20">
                                        <AlertCircle className="h-5 w-5 flex-shrink-0" />
                                        <p>{error}</p>
                                    </div>
                                )}

                                <button
                                    type="submit"
                                    disabled={loading}
                                    className="flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-brand-primary to-brand-vivid px-4 py-3.5 text-center text-sm font-bold text-white shadow-lg shadow-brand-vivid/20 transition-all hover:shadow-xl hover:shadow-brand-vivid/30 active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-70"
                                >
                                    {loading ? "Actualizando..." : (
                                        <>
                                            Cambiar Contraseña <ArrowRight className="h-4 w-4" />
                                        </>
                                    )}
                                </button>
                            </form>
                        </div>
                    )}
                    <div className="mt-8 text-center">
                        <p className="text-sm text-slate-500">
                            ¿Necesitas ayuda? <Link href="/" className="font-semibold text-brand-accent hover:text-brand-vivid transition-colors">Contáctanos</Link>
                        </p>
                    </div>
                </div>
            </div>
        </div>
    );
}
