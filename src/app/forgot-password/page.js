"use client";

import React, { useState } from "react";
import Link from "next/link";
import { Mail, ArrowRight, AlertCircle, CheckCircle2, ChevronLeft } from "lucide-react";
import { createBrowserClient } from "@supabase/ssr";

const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";
const supabase = createBrowserClient(supabaseUrl, supabaseKey);

export default function ForgotPasswordPage() {
    const [email, setEmail] = useState("");
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState(false);

    const handleReset = async (e) => {
        e.preventDefault();
        setLoading(true);
        setError("");

        try {
            const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
                redirectTo: `${window.location.origin}/reset-password`,
            });

            if (resetError) throw resetError;
            setSuccess(true);
        } catch (err) {
            console.error("Error en reset password:", err);
            let msg = err.message || "Ocurrió un error al intentar enviar el correo de recuperación.";
            
            // Traducción de errores comunes
            if (msg.includes("rate limit exceeded")) {
                msg = "Has intentado enviar demasiados correos en poco tiempo. Por favor, espera un par de minutos e intenta de nuevo.";
            } else if (msg.includes("User not found")) {
                msg = "No encontramos ninguna cuenta vinculada a este correo electrónico.";
            }
            
            setError(msg);
        } finally {
            setLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen font-sans text-slate-900 selection:bg-brand-vivid/30">
            {/* Lado Izquierdo (Formulario) */}
            <div className="flex w-full items-center justify-center bg-white p-8 lg:w-1/2">
                <div className="w-full max-w-md animate-fade-in-up">
                    <div className="mb-8">
                        <Link href="/login" className="inline-flex items-center gap-2 text-sm font-medium text-slate-500 hover:text-brand-accent transition-colors">
                            <ChevronLeft className="h-4 w-4" />
                            Volver al inicio de sesión
                        </Link>
                    </div>

                    <div className="mb-10 text-center lg:text-left">
                        <h1 className="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">
                            ¿Olvidaste tu contraseña?
                        </h1>
                        <p className="mt-3 text-slate-500">
                            No te preocupes. Ingresa tu correo y te enviaremos un enlace para que crees una nueva.
                        </p>
                    </div>

                    {success ? (
                        <div className="rounded-2xl bg-green-50 p-8 text-center ring-1 ring-inset ring-green-600/20 animate-scale-in">
                            <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-green-100 text-green-600">
                                <CheckCircle2 className="h-6 w-6" />
                            </div>
                            <h2 className="text-xl font-bold text-green-900">Correo enviado</h2>
                            <p className="mt-2 text-sm text-green-700">
                                Hemos enviado instrucciones para recuperar tu contraseña a <span className="font-bold">{email}</span>. 
                                Revisa tu bandeja de entrada y spam.
                            </p>
                            <Link href="/login" className="mt-6 inline-block text-sm font-bold text-green-700 hover:text-green-600 transition-colors">
                                Volver al login
                            </Link>
                        </div>
                    ) : (
                        <form onSubmit={handleReset} className="space-y-6">
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
                                {loading ? "Enviando..." : (
                                    <>
                                        Enviar Instrucciones <ArrowRight className="h-4 w-4" />
                                    </>
                                )}
                            </button>
                        </form>
                    )}
                </div>
            </div>

            {/* Lado Derecho (Branding) */}
            <div className="relative hidden w-1/2 flex-col justify-center overflow-hidden bg-brand-deep p-12 lg:flex xl:p-20">
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_top_right,rgba(142,67,217,0.15),transparent_60%)]"></div>
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_bottom_left,rgba(76,48,115,0.2),transparent_60%)]"></div>
                <div className="absolute inset-0 bg-[linear-gradient(rgba(255,255,255,0.02)_1px,transparent_1px),linear-gradient(90deg,rgba(255,255,255,0.02)_1px,transparent_1px)] bg-[size:48px_48px]"></div>

                <div className="relative z-10 flex flex-col items-center justify-center text-center">
                    <Link href="/">
                        <img
                            src="/imagen/logo_datix.png"
                            alt="Datix Logo"
                            className="h-28 w-auto brightness-0 invert drop-shadow-[0_0_20px_rgba(142,67,217,0.5)] transition-all hover:scale-105"
                        />
                    </Link>
                    <h2 className="mt-8 text-3xl font-extrabold leading-tight text-white xl:text-4xl">
                        Recupera tu acceso.
                    </h2>
                    <p className="mt-4 text-lg text-white/50 max-w-md">
                        En unos segundos podrás volver a gestionar tu negocio con normalidad.
                    </p>
                </div>
            </div>
        </div>
    );
}
