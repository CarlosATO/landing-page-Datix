# CONTEXTO MAESTRO DEL PROYECTO: SAAS DATIX (CONSTRUCCIÓN Y LOGÍSTICA)

## 1. IDENTIDAD Y OBJETIVO DEL NEGOCIO
El usuario (Carlos) es un Arquitecto de Software y Gerente de Operaciones con más de 20 años de experiencia en logística, cadena de suministro y control de obras (ex-SOMYL). 
El objetivo es construir "Datix": un SaaS B2B "High-Ticket" orientado a Constructoras, Contratistas (ej. Fibra Óptica) y Empresas Logísticas. 
El software resuelve problemas financieros graves: pérdida/robo de herramientas, descontrol de materiales y sobrepagos a subcontratistas por avances no reales.

## 2. EL PIVOTE ESTRATÉGICO (EL "POR QUÉ")
Originalmente, el sistema se estaba construyendo como un POS para Farmacias y Almacenes. Sin embargo, se decidió pivotar hacia la Construcción por las siguientes razones de negocio:
- **Cero fricción legal:** El software de farmacias requiere integraciones complejas con el gobierno (ISP, recetas retenidas, CENABAST) y el SII. El control interno de obras no requiere nada de esto para funcionar como MVP.
- **Mayor Margen (High-Ticket):** A una farmacia se le cobra barato por volumen. A una constructora se le puede cobrar una mensualidad alta ($100k - $500k CLP) porque el sistema les ahorra millones de pesos en pérdidas operativas desde el mes 1.
- **Ventaja Injusta:** El usuario ya desarrolló e implementó con éxito estos algoritmos operacionales en el mundo real durante su carrera.

## 3. REGLA SOBRE CÓDIGO LEGADO (FARMACIA Y POS)
- **ESTRICTAMENTE PROHIBIDO BORRAR CÓDIGO DE FARMACIAS O ADQUISICIONES ANTIGUO.**
- El código antiguo es técnicamente excelente (motor FEFO, trazabilidad de lotes) y se reciclará. 
- En la base de datos (Supabase), se utilizará una arquitectura basada en **Esquemas (Schemas) de PostgreSQL** para evitar choques. 
- El código de Farmacia vivirá en su propio esquema (`farmacia.*`) y los nuevos módulos en esquemas separados (`logistica.*`, `construccion.*`).
- En el frontend (React/Next.js), los módulos de farmacia simplemente se ocultarán de las rutas principales y de la Landing Page, pero los archivos físicos y componentes se mantendrán en el repositorio.

## 4. HOJA DE RUTA DE DESARROLLO (LOS NUEVOS MÓDULOS)
El desarrollo se ejecutará en fases para salir a producción rápido sin construir un "Mini-ERP" inmanejable:

- **Fase 1: Módulo Logística y Pañol (MVP Inmediato)**
  - *Función:* Control de inventario de herramientas (devolubles) e insumos (consumibles). 
  - *Ingreso:* Recepción manual mediante Guía de Despacho (desacoplado de Órdenes de Compra por ahora).
  - *Salida:* Asignación de activos a RUT de trabajadores/subcontratistas (Trazabilidad total).
  
- **Fase 2: Módulo Construcción (El "Candado Financiero")**
  - *Función:* Seguimiento del proyecto en terreno.
  - *Core:* Algoritmo que cruza "Cubicaciones Teóricas vs. Avance Real" para evitar sobrepagos a subcontratistas.

- **Fase 3: Módulo Adquisiciones**
  - *Función:* Emisión de Órdenes de Compra y control presupuestario.
  - *Integración:* Al activarse, permite a la bodega (Fase 1) autocompletar ingresos llamando al número de Orden de Compra.

## 5. REFACTORIZACIÓN DE LA LANDING PAGE
La Landing Page actual (`page.js` en Next.js) debe ser modificada bajo estas directrices:
- **Mantener:** Todo el enrutamiento de Supabase Auth (`/login`, `/register`).
- **Eliminar Visualmente:** Cualquier mención a "POS", "Ventas", "Farmacias", "Clientes" o "Cajas".
- **Nuevo Mensaje Core:** "Control Operativo y Trazabilidad Total para Constructoras y Contratistas."
- **Argumento de Venta:** Usar la Filosofía Técnica del creador para vender "Grado Empresarial" (Transacciones seguras, auditoría estricta, cero descuadres de base de datos).

## 6. FILOSOFÍA DE CONSTRUCCIÓN (REGLAS TÉCNICAS INQUEBRANTABLES)
Cualquier agente de IA que asista en este proyecto DEBE respetar la "Filosofía Profesional de Construcción de Software" del usuario:
1. **El Frontend NO es la fuente de verdad:** React es una pantalla tonta que muestra datos y consume APIs. La base de datos protege y el backend decide.
2. **Cero Lógica Crítica en UI:** Prohibido hacer múltiples inserciones desde React (ej. insertar movimiento y luego actualizar stock). Todo se hace llamando a una RPC/Backend que ejecuta una transacción única (Commit o Rollback).
3. **Cero Cambios Manuales en Supabase:** Prohibido sugerir crear tablas, columnas o funciones directamente en el dashboard visual de Supabase. Todo cambio debe escribirse como un archivo SQL en `supabase/migrations/`.
4. **Auditoría Obligatoria:** Toda operación crítica debe registrar quién, qué, cuándo, desde dónde y por qué.
5. **Aislamiento Multi-Tenant:** Toda consulta y política RLS debe asegurar que los datos entre la Empresa A y la Empresa B jamás se crucen.