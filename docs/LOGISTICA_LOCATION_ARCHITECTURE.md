# Logistica Location Architecture

## Model

- `code` sigue siendo el identificador visual principal.
- `name` sigue siendo el nombre operativo.
- Los componentes físicos se guardan separados para poder consultar, filtrar y evolucionar la bodega sin depender solo de texto libre.

## Simple Location

- Usa solo `code` y `name`.
- Puede incluir metadatos opcionales de estructura física.
- Útil para patios, contenedores, ubicaciones especiales o registros manuales.

## Structured Location

- Usa componentes explícitos:
  - `aisle_code`
  - `column_number`
  - `level_number` opcional
  - `division_code` opcional
- Ejemplos:
  - `PAS-A-C01`
  - `PAS-A-C01-N01`
  - `PAS-A-C01-N01-D01`
  - `PATIO-A`
  - `CONT-01`

## Why Separate Fields

- Permite búsquedas y filtros por pasillo, columna, nivel y división.
- Facilita crear mapas de bodega y vistas por layout físico.
- Evita depender de parsing frágil sobre el string `code`.
- Mantiene compatibilidad con ubicaciones manuales simples.

## Bulk Creation

- El modo recomendado es estructurado.
- Si no hay niveles, se crean ubicaciones solo por columna.
- Si no hay divisiones, cada nivel es una ubicación completa.
- `strict_mode` evita creación parcial cuando existe un duplicado.
