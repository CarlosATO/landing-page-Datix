"use client";

import React from "react";
import {
    LayoutGrid,
    CreditCard,
    Settings,
    LogOut,
    Store,
    FileText,
    ExternalLink,
} from "lucide-react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, useEffect } from "react";
import { createClient } from "@supabase/supabase-js";

// Inicialización de Supabase
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "https://placeholder-url.supabase.co";
const supabaseKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "placeholder-key";
const supabase = createClient(supabaseUrl, supabaseKey);

export default function PortalDashboard() {
    const router = useRouter();
    const [isBillingLoading, setIsBillingLoading] = useState(false);
    const [companyId, setCompanyId] = useState(null);
    const [loadingData, setLoadingData] = useState(true);

    // Cargar Usuario y Empresa
    useEffect(() => {
        const fetchUserData = async () => {
            setLoadingData(true);
            try {
                const { data: { session }, error: sessionError } = await supabase.auth.getSession();

                if (sessionError || !session) {
                    console.error("No hay sesión activa.", sessionError);
                    router.push('/login');
                    return;
                }

                const userId = session.user.id;

                // Buscar a qué empresa pertenece
                const { data: linkData, error: linkError } = await supabase
                    .from("company_users")
                    .select("company_id")
                    .eq("user_id", userId)
                    .single();

                if (!linkError && linkData) {
                    setCompanyId(linkData.company_id);
                }
            } catch (err) {
                console.error("Error al cargar datos:", err);
            } finally {
                setLoadingData(false);
            }
        };

        fetchUserData();
    }, [router]);

    const handleSubscribe = async () => {
        if (!companyId) {
            alert("No se pudo detectar tu Empresa. Por favor, recarga la página.");
            return;
        }

        setIsBillingLoading(true);
        try {
            const response = await fetch('/api/stripe/checkout', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ companyId: companyId })
            });
            const data = await response.json();

            if (data.url) {
                window.location.href = data.url;
            } else {
                console.error("No se recibió URL de Stripe", data);
                setIsBillingLoading(false);
            }
        } catch (error) {
            console.error("Error iniciando pago:", error);
            setIsBillingLoading(false);
        }
    };

    return (
        <div className="flex min-h-screen bg-slate-50 font-sans text-slate-900">
            {/* Sidebar */}
            <aside className="fixed inset-y-0 left-0 z-50 flex w-64 flex-col bg-white shadow-md">
                <div className="flex h-20 items-center justify-center border-b border-slate-100">
                    <span className="text-2xl font-black tracking-tighter text-blue-800">
                        Datix Hub
                    </span>
                </div>

                <nav className="flex flex-1 flex-col justify-between p-4">
                    <div className="space-y-2">
                        <Link
                            href="/portal"
                            className="flex items-center gap-3 rounded-xl bg-blue-50 px-4 py-3 font-semibold text-blue-700 transition-colors"
                        >
                            <LayoutGrid className="h-5 w-5" />
                            Mis Aplicaciones
                        </Link>
                        <Link
                            href="#"
                            className="flex items-center gap-3 rounded-xl px-4 py-3 font-medium text-slate-600 transition-colors hover:bg-slate-50 hover:text-slate-900"
                        >
                            <CreditCard className="h-5 w-5" />
                            Suscripción y Pagos
                        </Link>
                        <Link
                            href="#"
                            className="flex items-center gap-3 rounded-xl px-4 py-3 font-medium text-slate-600 transition-colors hover:bg-slate-50 hover:text-slate-900"
                        >
                            <Settings className="h-5 w-5" />
                            Configuración
                        </Link>
                    </div>

                    <div>
                        <Link
                            href="/"
                            className="flex w-full items-center gap-3 rounded-xl px-4 py-3 font-medium text-slate-600 transition-colors hover:bg-red-50 hover:text-red-600"
                        >
                            <LogOut className="h-5 w-5" />
                            Cerrar Sesión
                        </Link>
                    </div>
                </nav>
            </aside>

            {/* Main Content */}
            <main className="ml-64 flex-1 p-8 sm:p-12">
                <div className="mx-auto max-w-5xl">
                    {/* Header */}
                    <div className="mb-10">
                        <h1 className="text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                            Bienvenido a tu Ecosistema
                        </h1>
                        <p className="mt-2 text-lg text-slate-600">
                            Gestiona tus herramientas empresariales y abre tus módulos contratados.
                        </p>
                    </div>

                    {/* Grid de Aplicaciones */}
                    <div className="grid grid-cols-1 gap-6 md:grid-cols-2">
                        {/* Tarjeta 1 (App Contratada - POS) */}
                        <div className="relative flex flex-col overflow-hidden rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200 transition-shadow hover:shadow-md">
                            <div className="absolute left-0 top-0 h-1 w-full bg-green-500"></div>
                            <div className="mb-4 flex items-center justify-between">
                                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-slate-100 text-slate-700">
                                    <Store className="h-6 w-6" />
                                </div>
                                <span className="inline-flex items-center rounded-full bg-green-50 px-2.5 py-1 text-xs font-medium text-green-700 ring-1 ring-inset ring-green-600/20">
                                    Estado: Activo
                                </span>
                            </div>
                            <h3 className="mb-2 text-xl font-bold text-slate-900">
                                Datix POS & Almacén
                            </h3>
                            <p className="mb-6 text-sm text-slate-600">
                                Punto de venta, control de inventario FEFO y finanzas.
                            </p>
                            <div className="mt-auto">
                                <a
                                    href="http://localhost:5173"
                                    target="_blank"
                                    rel="noopener noreferrer"
                                    className="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-blue-500"
                                >
                                    🚀 Abrir Sistema <ExternalLink className="h-4 w-4" />
                                </a>
                            </div>
                        </div>

                        {/* Tarjeta 2 (Sugerencia de Venta Cruzada) */}
                        <div className="relative flex flex-col overflow-hidden rounded-2xl bg-slate-50/50 p-6 shadow-sm ring-1 ring-slate-200 transition-shadow hover:shadow-md">
                            <div className="mb-4 flex items-center justify-between">
                                <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-slate-200 text-slate-500">
                                    <FileText className="h-6 w-6" />
                                </div>
                                <span className="inline-flex items-center rounded-full bg-slate-100 px-2.5 py-1 text-xs font-medium text-slate-600 ring-1 ring-inset ring-slate-500/20">
                                    No contratado
                                </span>
                            </div>
                            <h3 className="mb-2 text-xl font-bold text-slate-500">
                                Datix Facturación SII
                            </h3>
                            <p className="mb-6 text-sm text-slate-500">
                                Emite boletas electrónicas automáticamente con cada venta.
                            </p>
                            <div className="mt-auto">
                                <Link
                                    href="#"
                                    className="flex w-full items-center justify-center rounded-xl border border-slate-300 bg-white px-4 py-3 text-sm font-semibold text-slate-600 shadow-sm transition-colors hover:bg-slate-50 hover:text-slate-900"
                                >
                                    Ver planes e integrar
                                </Link>
                            </div>
                        </div>
                    </div>

                    {/* Sección Resumen de Suscripción */}
                    <div className="mt-12 flex flex-col items-center justify-between gap-4 rounded-2xl bg-white p-6 shadow-sm ring-1 ring-slate-200 sm:flex-row sm:p-8">
                        <div>
                            <h3 className="text-lg font-bold text-slate-900">
                                Suscripción Actual
                            </h3>
                            <p className="mt-1 text-slate-600">
                                Plan Base - Renovación: 15 de Marzo, 2026.
                            </p>
                        </div>
                        <button
                            onClick={handleSubscribe}
                            disabled={isBillingLoading || loadingData || !companyId}
                            className="rounded-xl border border-slate-200 bg-white px-5 py-2.5 text-sm font-semibold text-slate-700 shadow-sm transition-colors hover:bg-slate-50 disabled:cursor-not-allowed disabled:opacity-70"
                        >
                            {isBillingLoading ? "Redirigiendo..." : "Gestionar Pago"}
                        </button>
                    </div>
                </div>
            </main>
        </div>
    );
}
