"use client";
import React, { useEffect } from "react";
import { Package, Building2, ShoppingCart, CheckCircle2, ShieldCheck, Eye, Activity } from "lucide-react";

const modules = [
  { name: "Adquisiciones", icon: ShoppingCart, color: "text-teal-600", bg: "bg-teal-50", border: "border-teal-200", desc: "OC, proveedores y presupuesto" },
  { name: "Logística y Pañol", icon: Package, color: "text-violet-600", bg: "bg-violet-50", border: "border-violet-200", desc: "Stock, bodegas y trazabilidad" },
  { name: "Construcción", icon: Building2, color: "text-amber-600", bg: "bg-amber-50", border: "border-amber-200", desc: "Avances y candado financiero" },
];

// Trazabilidad as a system feature badge
function TrazabilidadBadge() {
  return (
    <div className="mt-8 rounded-2xl border border-violet-100 bg-violet-50/60 p-5 flex items-start gap-4">
      <div className="h-10 w-10 rounded-xl bg-violet-100 flex items-center justify-center flex-shrink-0">
        <Eye className="h-5 w-5 text-violet-600" />
      </div>
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-sm font-extrabold text-slate-900">Trazabilidad Total</span>
          <span className="px-2 py-0.5 rounded-full bg-violet-600 text-white text-[9px] font-bold tracking-wide">INCLUIDO EN TODOS</span>
        </div>
        <p className="text-xs text-slate-500 font-medium">No es un módulo adicional — es la base de todo Datix. Cada acción, movimiento y decisión queda registrada con usuario, fecha y contexto. Auditoría perpetua e inmutable en todos los módulos.</p>
        <div className="flex flex-wrap gap-3 mt-3">
          {["Logs inmutables","Multi-empresa","Rollback automático","RLS por empresa"].map((f,i)=>(
            <span key={i} className="flex items-center gap-1 text-[10px] font-bold text-violet-700">
              <CheckCircle2 size={10} className="text-violet-500"/>{f}
            </span>
          ))}
        </div>
      </div>
    </div>
  );
}

export default function ModuleFlow() {
  return (
    <div className="space-y-6">
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 relative">
        {/* Connecting line */}
        <div className="hidden sm:block absolute top-[52px] left-[17%] right-[17%] h-0.5 bg-gradient-to-r from-teal-200 via-violet-200 to-amber-200 z-0" />
        {modules.map((mod, i) => (
          <div key={i} className="relative z-10 bg-white rounded-2xl border border-slate-200 shadow-md hover:shadow-xl transition-all hover:-translate-y-1 p-6 flex flex-col items-center text-center gap-3">
            <div className={`h-14 w-14 rounded-xl ${mod.bg} border ${mod.border} flex items-center justify-center`}>
              <mod.icon className={`h-7 w-7 ${mod.color}`} />
            </div>
            <h4 className="text-sm font-bold text-slate-900">{mod.name}</h4>
            <p className="text-[11px] text-slate-500 font-medium">{mod.desc}</p>
            <span className="absolute -top-2.5 -right-2.5 h-6 w-6 bg-white border border-slate-200 rounded-full shadow flex items-center justify-center">
              <CheckCircle2 size={13} className="text-emerald-500" />
            </span>
          </div>
        ))}
      </div>
      <TrazabilidadBadge />
    </div>
  );
}
