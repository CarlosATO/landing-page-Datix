"use client";
import { useState } from "react";
import { CheckCircle2 } from "lucide-react";

const TABS_DATA = {
  Logística: {
    leftTitle: "Control Logístico",
    leftItems: ["Bodegas activas", "Avance vs presupuesto", "Herramientas asignadas", "Stock por obra", "Documentos auditables"],
    tableTitle: "Kardex General",
    tableHeaders: ["Ítem", "SKU", "Bodega", "Estado", "Qty"],
    rows: [
      { item: "Rotomartillo Pro", sku: "ROT-001", col3: "P-01-A", estado: "ASIGNADO", qty: "12", estadoClass: "text-indigo-600 bg-indigo-50" },
      { item: "Cemento Portland 25Kg", sku: "CEM-004", col3: "C-02-B", estado: "DISPONIBLE", qty: "450", estadoClass: "text-emerald-600 bg-emerald-50" },
      { item: 'Esmeril Angular 7"', sku: "ESM-012", col3: "P-01-A", estado: "ASIGNADO", qty: "4", estadoClass: "text-indigo-600 bg-indigo-50" },
      { item: 'Disco Diamante 14"', sku: "DIS-020", col3: "B-Cent", estado: "CRÍTICO", qty: "1", estadoClass: "text-red-600 bg-red-50" },
    ],
    alerts: [
      { name: "Cemento Dig 25kg", qty: "< 10 unidades" },
      { name: "Cable Eléctrico 6mm", qty: "< 5 unidades" },
      { name: "Hormigón H-20", qty: "Sin Stock" },
    ],
    alertsTitle: "Stock Crítico",
  },
  Construcción: {
    leftTitle: "Control de Obras",
    leftItems: ["Obras en ejecución", "Avance físico vs teórico", "Pagos a subcontratistas", "Cubicaciones aprobadas", "Alertas de sobrepago"],
    tableTitle: "Estado de Subcontratos",
    tableHeaders: ["Subcontrato", "Especialidad", "% Cubicado", "% Físico", "Estado Pago"],
    rows: [
      { item: "Torres & Cia Ltda.", sku: "SC-001", col3: "70%", estado: "APROBADO", qty: "65%", estadoClass: "text-emerald-600 bg-emerald-50" },
      { item: "Hormigones del Sur", sku: "SC-002", col3: "55%", estado: "EN REVISIÓN", qty: "58%", estadoClass: "text-amber-600 bg-amber-50" },
      { item: "Eléctrica Montoya", sku: "SC-003", col3: "30%", estado: "BLOQUEADO", qty: "42%", estadoClass: "text-red-600 bg-red-50" },
      { item: "Moldajes Express", sku: "SC-004", col3: "90%", estado: "APROBADO", qty: "88%", estadoClass: "text-emerald-600 bg-emerald-50" },
    ],
    alerts: [
      { name: "Eléctrica Montoya", qty: "Excede cubicación" },
      { name: "Hormigones del Sur", qty: "Pago en revisión" },
    ],
    alertsTitle: "Alertas Obra",
  },
  Adquisiciones: {
    leftTitle: "Órdenes de Compra",
    leftItems: ["OC emitidas este mes", "Pendientes de aprobación", "Recepciones en bodega", "Proveedores activos", "Presupuesto disponible"],
    tableTitle: "Órdenes de Compra Recientes",
    tableHeaders: ["OC N°", "Proveedor", "Monto", "Estado", "F. Entrega"],
    rows: [
      { item: "OC-2024-081", sku: "Distribuidora Norte", col3: "$2.340.000", estado: "RECEPCIONADA", qty: "12/05", estadoClass: "text-emerald-600 bg-emerald-50" },
      { item: "OC-2024-082", sku: "Fierros Central", col3: "$890.000", estado: "EN TRÁNSITO", qty: "18/05", estadoClass: "text-indigo-600 bg-indigo-50" },
      { item: "OC-2024-083", sku: "Cementos Bío-Bío", col3: "$4.120.000", estado: "PENDIENTE", qty: "22/05", estadoClass: "text-amber-600 bg-amber-50" },
      { item: "OC-2024-084", sku: "Ferretería Unión", col3: "$560.000", estado: "RECEPCIONADA", qty: "10/05", estadoClass: "text-emerald-600 bg-emerald-50" },
    ],
    alerts: [
      { name: "OC-2024-083", qty: "Sin aprobar hace 3 días" },
      { name: "Fierros Central", qty: "Entrega vence en 2 días" },
    ],
    alertsTitle: "Alertas OC",
  },
  Trazabilidad: {
    leftTitle: "Registro de Auditoría",
    leftItems: ["Eventos hoy", "Usuarios activos", "Módulos trazados", "Rechazos automáticos", "Logs exportados"],
    tableTitle: "Eventos Recientes",
    tableHeaders: ["Timestamp", "Usuario", "Acción", "Módulo", "Resultado"],
    rows: [
      { item: "14:32:01", sku: "jperez", col3: "DESPACHO", estado: "LOGÍSTICA", qty: "OK", estadoClass: "text-emerald-600 bg-emerald-50" },
      { item: "14:32:09", sku: "agarcia", col3: "PAGO SC", estado: "CONSTRUCCIÓN", qty: "RECHAZADO", estadoClass: "text-red-600 bg-red-50" },
      { item: "14:45:22", sku: "msoto", col3: "APROBÓ OC", estado: "ADQUISICIONES", qty: "OK", estadoClass: "text-emerald-600 bg-emerald-50" },
      { item: "15:01:17", sku: "jperez", col3: "RETIRO HERR.", estado: "LOGÍSTICA", qty: "OK", estadoClass: "text-emerald-600 bg-emerald-50" },
    ],
    alerts: [
      { name: "agarcia (14:32)", qty: "Pago bloqueado por RLS" },
      { name: "Sistema", qty: "2 rollbacks automáticos" },
    ],
    alertsTitle: "Eventos Críticos",
  },
};

export default function DashboardMockup() {
  const [active, setActive] = useState("Logística");
  const data = TABS_DATA[active];

  return (
    <div className="bg-white rounded-2xl border border-slate-200 shadow-xl overflow-hidden">
      {/* Tabs */}
      <div className="flex items-center gap-1 border-b border-slate-200 px-4 pt-4 bg-slate-50/70">
        {Object.keys(TABS_DATA).map((tab) => (
          <button
            key={tab}
            onClick={() => setActive(tab)}
            className={`px-5 py-2.5 text-xs font-bold rounded-t-lg transition-all ${
              active === tab
                ? "bg-violet-600 text-white shadow-sm"
                : "text-slate-500 hover:text-slate-700 hover:bg-white/80"
            }`}
          >
            {tab}
          </button>
        ))}
      </div>

      {/* Body */}
      <div className="flex gap-0 divide-x divide-slate-100">
        {/* Left list */}
        <div className="w-48 flex-shrink-0 p-5 space-y-1 bg-slate-50/40">
          <p className="text-[9px] font-extrabold text-slate-400 uppercase tracking-widest mb-3">{data.leftTitle}</p>
          {data.leftItems.map((item, i) => (
            <div key={i} className="flex items-center gap-2 text-[11px] text-slate-600 font-medium py-1">
              <CheckCircle2 size={11} className="text-violet-500 flex-shrink-0" /> {item}
            </div>
          ))}
        </div>

        {/* Center table */}
        <div className="flex-1 overflow-auto p-5">
          <div className="flex justify-between items-center mb-4">
            <p className="text-sm font-bold text-slate-800">{data.tableTitle}</p>
            <span className="text-[11px] text-violet-600 font-bold cursor-pointer hover:underline">Ver todo →</span>
          </div>
          <table className="w-full text-[10px]">
            <thead>
              <tr className="text-slate-400 font-semibold border-b border-slate-100">
                {data.tableHeaders.map((h, i) => (
                  <th key={i} className={`pb-2 ${i === data.tableHeaders.length - 1 ? "text-right" : "text-left"} font-bold pr-3`}>{h}</th>
                ))}
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-50">
              {data.rows.map((row, i) => (
                <tr key={i} className="hover:bg-violet-50/30 transition-colors">
                  <td className="py-2.5 font-semibold text-slate-700 pr-3 whitespace-nowrap">{row.item}</td>
                  <td className="py-2.5 text-slate-400 pr-3 whitespace-nowrap">{row.sku}</td>
                  <td className="py-2.5 text-slate-500 font-mono pr-3 whitespace-nowrap">{row.col3}</td>
                  <td className="py-2.5 pr-3">
                    <span className={`px-2 py-0.5 rounded text-[9px] font-bold ${row.estadoClass}`}>{row.estado}</span>
                  </td>
                  <td className={`py-2.5 text-right font-mono font-bold ${row.estadoClass}`}>{row.qty}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Right alerts */}
        <div className="w-44 flex-shrink-0 p-5">
          <p className="text-[9px] font-extrabold text-slate-400 uppercase tracking-widest mb-3">{data.alertsTitle}</p>
          <div className="space-y-2.5">
            {data.alerts.map((item, i) => (
              <div key={i} className="bg-red-50 border border-red-100 rounded-xl p-3">
                <p className="text-[10px] font-bold text-red-700 leading-tight">{item.name}</p>
                <p className="text-[9px] text-red-400 mt-1 font-medium">{item.qty}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
