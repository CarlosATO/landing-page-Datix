# Cost Center Architecture

Los centros de costo son la unidad financiera transversal de Datix.

## Por qué no son solo proyectos

- Un proyecto representa una obra o iniciativa operacional.
- Un centro de costo puede representar proyecto, oficina, administración, bodega central, mantención, operación general u otro foco financiero.
- Hay costos que no deben imputarse a un proyecto específico.

## Regla base

- Todo movimiento logístico, compra, recepción, transferencia, salida, ajuste o consumo debe tener `cost_center_id`.
- No se deben generar movimientos huérfanos.
- `null` solo queda como compatibilidad histórica temporal.
- La recepción manual de Logística ya exige `cost_center_id` y lo persiste en `stock_movements` y `stock_balances`.

## Entidad transversal

- `public.cost_centers` es la referencia financiera común.
- `public.projects` sigue existiendo como entidad operacional.
- Un proyecto puede enlazarse a un centro de costo para trazabilidad financiera.

## Consumo por módulo

- Logística: stock movements, stock balances, futuras salidas y recepciones.
- Adquisiciones: órdenes de compra y recepciones.
- Construcción: imputación de obra, faenas y consumos.
- Reportería: costo por centro, por obra, por oficina, por operación general.

## Ejemplos reales

- Obra: `PROYECTO EDIFICIO SUR`
- Oficina: `OFICINA CENTRAL`
- Gastos administrativos: `ADMINISTRACION`
- Bodega central: `STOCK GENERAL`
- Operación general: `OPERACION GENERAL`
- Mantención: `MANTENCION FLOTAS`

## Preparación futura

- Las futuras OC deberán incluir `cost_center_id`.
- Las futuras recepciones deberán incluir `cost_center_id`.
- Los futuros consumos deberán incluir `cost_center_id`.
- Kardex deberá poder filtrar por centro de costo.
- La reportería financiera futura dependerá de esta arquitectura.
