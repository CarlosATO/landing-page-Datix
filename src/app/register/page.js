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
    Store,
    Truck,
    Users,
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
        moduloInicial: "pos"
    });

    // Estados de UI
    const [loading, setLoading] = useState(false);
    const [error, setError] = useState("");
    const [success, setSuccess] = useState(false);

    const handleChange = (e) => {
        const { name, value } = e.target;
        setFormData(prev => ({ ...prev, [name]: value }));
    };

    const handleModuleSelect = (modulo) => {
        setFormData(prev => ({ ...prev, moduloInicial: modulo }));
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
                        modulo_inicial: formData.moduloInicial
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
        <div className="flex min-h-screen bg-white font-sans text-slate-900 selection:bg-blue-200">

            {/* 1. Lado Izquierdo (Branding / Marketing) */}
            <div className="relative hidden w-1/2 flex-col justify-between overflow-hidden bg-slate-950 p-12 lg:flex xl:p-20">
                {/* Fondo Decorativo */}
                <div className="absolute inset-0 bg-[radial-gradient(circle_at_bottom_left,_var(--tw-gradient-stops))] from-blue-900/40 via-slate-950 to-slate-950"></div>

                {/* Logo */}
                <div className="relative z-10">
                    <Link href="/">
                        <img src="/imagen/logo_datix.png" alt="Datix Logo" className="h-32 w-auto brightness-0 invert" />
                    </Link>
                </div>

                {/* Texto Inspirador & Beneficios */}
                <div className="relative z-10 mt-auto">
                    <h2 className="mb-8 text-4xl font-bold leading-tight text-white xl:text-5xl">
                        El primer paso para escalar tu negocio de forma inteligente.
                    </h2>

                    <div className="space-y-5 text-lg text-slate-300">
                        <div className="flex items-center gap-3">
                            <CheckCircle2 className="h-6 w-6 text-green-500" />
                            <span>Sin tarjeta de crédito.</span>
                        </div>
                        <div className="flex items-center gap-3">
                            <CheckCircle2 className="h-6 w-6 text-green-500" />
                            <span>Cancela cuando quieras, sin amarras.</span>
                        </div>
                        <div className="flex items-center gap-3">
                            <CheckCircle2 className="h-6 w-6 text-green-500" />
                            <span>Soporte local en Chile y Latinoamérica.</span>
                        </div>
                        <div className="flex items-center gap-3">
                            <CheckCircle2 className="h-6 w-6 text-green-500" />
                            <span>Paga solo por lo que usas, crece a tu ritmo.</span>
                        </div>
                    </div>
                </div>
            </div>

            {/* 2. Lado Derecho (Formulario de Registro) */}
            <div className="flex w-full items-center justify-center p-8 lg:w-1/2">
                <div className="w-full max-w-md">

                    {/* Header en Móvil */}
                    <div className="mb-8 text-center lg:hidden">
                        <Link href="/">
                            <img src="/imagen/logo_datix.png" alt="Datix Logo" className="h-16 w-auto mx-auto dark:brightness-0 dark:invert" />
                        </Link>
                    </div>

                    {/* Títulos */}
                    <div className="mb-10 text-center lg:text-left">
                        <h1 className="text-3xl font-bold tracking-tight text-slate-900 sm:text-4xl">
                            Crea tu Ecosistema
                        </h1>
                        <p className="mt-3 text-slate-500">
                            Comienza tus 14 días de prueba gratis. Sin compromisos.
                        </p>
                    </div>

                    {/* Formulario / Mensaje de Éxito */}
                    {success ? (
                        <div className="flex flex-col items-center justify-center space-y-4 rounded-3xl border border-slate-100 bg-slate-50 p-10 text-center shadow-lg">
                            <CheckCircle2 className="h-16 w-16 text-green-500" />
                            <h2 className="text-2xl font-bold bg-gradient-to-r from-blue-700 to-indigo-700 bg-clip-text text-transparent">¡Registro casi listo!</h2>
                            <p className="text-slate-600">
                                ¡Revisa tu bandeja de entrada! Te hemos enviado un enlace para confirmar tu correo y activar tu cuenta.
                            </p>
                            <Link href="/login" className="mt-6 w-full rounded-xl bg-slate-900 px-4 py-3 text-sm font-semibold text-white shadow-md transition-all hover:bg-slate-800 hover:shadow-lg active:scale-[0.98]">
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
                                            className="block w-full rounded-xl border border-slate-300 bg-white py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-colors placeholder:text-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
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
                                            className="block w-full rounded-xl border border-slate-300 bg-white py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-colors placeholder:text-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
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
                                            name="password"
                                            value={formData.password}
                                            onChange={handleChange}
                                            required
                                            className="block w-full rounded-xl border border-slate-300 bg-white py-3 pl-11 pr-3 text-slate-900 shadow-sm transition-colors placeholder:text-slate-400 focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
                                            placeholder="••••••••"
                                        />
                                    </div>
                                </div>
                            </div>

                            {/* Selector de Módulo Inicial */}
                            <div className="mt-8">
                                <label className="mb-3 block text-sm font-medium text-slate-700">
                                    ¿Qué módulo te interesa probar primero?
                                </label>
                                <div className="grid grid-cols-3 gap-3">

                                    {/* Opción POS */}
                                    <button
                                        type="button"
                                        onClick={() => handleModuleSelect('pos')}
                                        className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-3 text-sm font-medium transition-all ${formData.moduloInicial === 'pos'
                                            ? 'border-blue-600 bg-blue-50 text-blue-700 ring-1 ring-blue-600'
                                            : 'border-slate-200 bg-white text-slate-600 hover:border-slate-300 hover:bg-slate-50'
                                            }`}
                                    >
                                        <Store className={`h-6 w-6 ${formData.moduloInicial === 'pos' ? 'text-blue-600' : 'text-slate-400'}`} />
                                        Punto de Venta
                                    </button>

                                    {/* Opción Logística */}
                                    <button
                                        type="button"
                                        onClick={() => handleModuleSelect('logistica')}
                                        className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-3 text-sm font-medium transition-all ${formData.moduloInicial === 'logistica'
                                            ? 'border-purple-600 bg-purple-50 text-purple-700 ring-1 ring-purple-600'
                                            : 'border-slate-200 bg-white text-slate-600 hover:border-slate-300 hover:bg-slate-50'
                                            }`}
                                    >
                                        <Truck className={`h-6 w-6 ${formData.moduloInicial === 'logistica' ? 'text-purple-600' : 'text-slate-400'}`} />
                                        Logística
                                    </button>

                                    {/* Opción RRHH */}
                                    <button
                                        type="button"
                                        onClick={() => handleModuleSelect('rrhh')}
                                        className={`flex flex-col items-center justify-center gap-2 rounded-xl border p-3 text-sm font-medium transition-all ${formData.moduloInicial === 'rrhh'
                                            ? 'border-orange-600 bg-orange-50 text-orange-700 ring-1 ring-orange-600'
                                            : 'border-slate-200 bg-white text-slate-600 hover:border-slate-300 hover:bg-slate-50'
                                            }`}
                                    >
                                        <Users className={`h-6 w-6 ${formData.moduloInicial === 'rrhh' ? 'text-orange-600' : 'text-slate-400'}`} />
                                        RRHH
                                    </button>

                                </div>
                            </div>

                            {/* Error estético */}
                            {error && (
                                <div className="flex items-center gap-3 rounded-xl bg-red-50 p-4 text-sm text-red-600 ring-1 ring-inset ring-red-600/20">
                                    <AlertCircle className="h-5 w-5 flex-shrink-0" />
                                    <p>{error}</p>
                                </div>
                            )}

                            {/* Botón Submit */}
                            <div className="pt-4">
                                <button
                                    type="submit"
                                    disabled={loading}
                                    className="w-full rounded-xl bg-blue-600 px-4 py-3.5 text-center text-sm font-semibold text-white shadow-md transition-all hover:bg-blue-500 hover:shadow-lg active:scale-[0.98] disabled:cursor-not-allowed disabled:opacity-70"
                                >
                                    {loading ? "Creando ecosistema..." : "Crear mi cuenta"}
                                </button>
                            </div>

                            {/* Enlace Login */}
                            <div className="text-center">
                                <p className="text-sm text-slate-600">
                                    ¿Ya tienes cuenta?{" "}
                                    <Link href="/login" className="font-semibold text-blue-600 hover:text-blue-500">
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
