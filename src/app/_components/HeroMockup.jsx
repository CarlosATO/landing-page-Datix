"use client";
import { AlertTriangle, TrendingDown, Package, Building2, Wrench, Lock } from "lucide-react";

export default function HeroMockup() {
  return (
    <div className="relative w-full">
      {/* Glow */}
      <div className="absolute -inset-4 bg-gradient-to-tr from-violet-400/20 via-indigo-300/10 to-cyan-300/10 blur-3xl rounded-3xl pointer-events-none" />
      {/* Browser frame */}
      <div className="relative rounded-2xl border border-slate-200 bg-white shadow-[0_32px_64px_-16px_rgba(109,40,217,0.18)] overflow-hidden">
        {/* Browser bar */}
        <div className="flex items-center gap-2 px-4 py-3 bg-slate-50 border-b border-slate-200">
          <div className="flex gap-1.5">
            <span className="w-3 h-3 rounded-full bg-red-400" />
            <span className="w-3 h-3 rounded-full bg-amber-400" />
            <span className="w-3 h-3 rounded-full bg-emerald-400" />
          </div>
          <div className="flex-1 mx-3">
            <div className="bg-white border border-slate-200 rounded-md px-3 py-1 text-[10px] text-slate-400 font-mono flex items-center gap-2">
              <Lock size={9} className="text-emerald-500" /> datix.app/dashboard
            </div>
          </div>
        </div>
        {/* App chrome */}
        <div className="flex h-[340px]">
          {/* Sidebar */}
          <div className="w-32 bg-slate-900 flex-shrink-0 p-3 space-y-1">
            <div className="text-[9px] font-bold text-slate-500 uppercase tracking-widest px-2 mb-3">Datix</div>
            {["Inicio","Logística","Construcción","Adquisiciones","Auditoría"].map((item, i) => (
              <div key={i} className={`px-2 py-1.5 rounded-md text-[10px] font-medium ${i === 0 ? 'bg-violet-600 text-white' : 'text-slate-400 hover:text-slate-200'}`}>{item}</div>
            ))}
          </div>
          {/* Main content */}
          <div className="flex-1 bg-slate-50 p-4 overflow-hidden">
            <div className="text-[11px] font-bold text-slate-500 mb-3">Resumen Operacional</div>
            {/* KPIs */}
            <div className="grid grid-cols-3 gap-2 mb-3">
              {[
                { label: "Costo Activo", value: "$45.334", delta: "-8%", color: "text-emerald-600" },
                { label: "Stock Crítico", value: "3", delta: "Req. OC", color: "text-amber-600" },
                { label: "Herramientas", value: "18", delta: "Activas", color: "text-indigo-600" },
              ].map((kpi, i) => (
                <div key={i} className="bg-white rounded-lg border border-slate-200 p-2.5 shadow-sm">
                  <div className="text-[9px] text-slate-500 font-medium">{kpi.label}</div>
                  <div className="text-sm font-extrabold text-slate-900 mt-0.5">{kpi.value}</div>
                  <div className={`text-[9px] font-bold mt-0.5 ${kpi.color}`}>{kpi.delta}</div>
                </div>
              ))}
            </div>
            {/* Table */}
            <div className="bg-white rounded-lg border border-slate-200 shadow-sm overflow-hidden">
              <div className="px-3 py-2 border-b border-slate-100 flex justify-between items-center">
                <span className="text-[10px] font-bold text-slate-700">Trazabilidad Reciente</span>
                <span className="text-[9px] text-violet-600 font-bold">Ver Kardex →</span>
              </div>
              <table className="w-full text-[9px]">
                <thead className="bg-slate-50">
                  <tr className="text-slate-400 font-semibold">
                    <th className="px-3 py-1.5 text-left">Activo</th>
                    <th className="px-3 py-1.5 text-left">Estado</th>
                    <th className="px-3 py-1.5 text-left">Bodega</th>
                    <th className="px-3 py-1.5 text-right">Qty</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-50">
                  {[
                    { name: "Rotomartillo X2", status: "ASIGNADO", sc: "badge-indigo", bodega: "P-01", qty: "-1" },
                    { name: "Cemento 25kg", status: "RECEPCIÓN", sc: "badge-teal", bodega: "C-04", qty: "+500" },
                    { name: "Pago Subcontrato", status: "RECHAZADO", sc: "badge-red", bodega: "—", qty: "BLOCKED" },
                  ].map((row, i) => (
                    <tr key={i} className="hover:bg-slate-50/60">
                      <td className="px-3 py-2 font-semibold text-slate-700">{row.name}</td>
                      <td className="px-3 py-2">
                        <span className={`px-1.5 py-0.5 rounded text-[8px] font-bold ${
                          row.sc === "badge-indigo" ? "bg-indigo-100 text-indigo-700"
                          : row.sc === "badge-teal" ? "bg-teal-100 text-teal-700"
                          : "bg-red-100 text-red-700"
                        }`}>{row.status}</span>
                      </td>
                      <td className="px-3 py-2 text-slate-500 font-mono">{row.bodega}</td>
                      <td className={`px-3 py-2 text-right font-mono font-bold ${
                        row.qty.startsWith('+') ? 'text-emerald-600'
                        : row.qty === 'BLOCKED' ? 'text-red-500'
                        : 'text-slate-700'
                      }`}>{row.qty}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
      {/* Floating audit card */}
      <div className="absolute -bottom-5 -right-5 bg-white rounded-xl border border-slate-200 shadow-xl p-3 flex items-center gap-3 hidden sm:flex">
        <div className="h-9 w-9 rounded-full bg-emerald-100 flex items-center justify-center">
          <svg className="h-4 w-4 text-emerald-600" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        </div>
        <div>
          <p className="text-[9px] font-bold text-slate-400 uppercase tracking-wider">Auditoría Total</p>
          <p className="text-[11px] font-extrabold text-slate-900">Transacción Segura</p>
        </div>
      </div>
    </div>
  );
}
