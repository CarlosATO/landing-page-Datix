# Guia de estilos Datix (Landing + Auth + Portal)

Este documento define los estilos visuales oficiales del proyecto para mantener consistencia en toda la experiencia.

## 1. Principios de diseno

- Mantener identidad violeta Datix sin romper legibilidad.
- Priorizar contraste alto en CTA, textos clave y formularios.
- Conservar una estetica limpia, profesional y moderna.
- Evitar cambios bruscos de tema entre landing, auth y portal.

## 2. Tipografia

- Fuente principal: `Inter`.
- Jerarquia:
  - Titulos principales: `font-extrabold`, tracking ajustado y tamano grande.
  - Subtitulos y texto de apoyo: tonos neutros medios (`text-slate-500` a `text-slate-700`).
  - Labels e inputs: legibles y con foco visible.

Referencia: `src/app/globals.css`.

## 3. Paleta oficial

Tokens definidos en `src/app/globals.css`:

- `--color-brand-deep: #FAFBFC`
- `--color-brand-dark: #F3F4F8`
- `--color-brand-bg: #EEE9F8`
- `--color-brand-primary: #E8DFF5`
- `--color-brand-navbar: #FFFFFF`
- `--color-brand-accent: #8E63D9`
- `--color-brand-vivid: #7C3AED`
- `--color-brand-light: #6D28D9`
- `--color-brand-glow: #A855F7`
- `--color-brand-danger: #EF4444`

Superficies:

- `--color-surface-light: #F8F6FC`
- `--color-surface-muted: #EDE8F5`

## 4. Contraste y accesibilidad

- Objetivo minimo para texto normal: contraste equivalente a WCAG AA.
- No usar texto blanco (`text-white` o `text-white/60`) sobre fondos muy claros.
- CTA primarios deben usar tonos profundos (`brand-accent` y `brand-vivid`) con texto blanco.
- Enlaces secundarios deben tener estado hover claro y visible.
- Focus states obligatorios en formularios (`ring` y `border` visibles).

## 5. Landing (pagina principal)

Archivo principal: `src/app/page.js`.

### Navbar

- Fondo: blanco con blur, limpio y profesional.
- Boton `Acceder`: estilo secundario con borde visible, texto oscuro y hover suave.
- Boton `Probar Gratis`: gradiente violeta oscuro para contraste alto.

### CTA

- CTA primarios: gradientes de `brand-accent` a `brand-vivid`.
- CTA secundarios: fondo blanco, borde visible, texto oscuro.

### Fondos

- Usar gradientes y radial overlays en gama violeta suave.
- Evitar fondos planos sin textura si afectan la profundidad visual.

## 6. Auth (Login y Registro)

Archivos:

- `src/app/login/page.js`
- `src/app/register/page.js`

### Layout split-screen

- Panel de formulario en fondo blanco.
- Panel de branding en degradado claro violeta para continuidad con landing.
- Logos con filtro violeta corporativo (no invertir a blanco en fondos claros).

### Formularios

- Inputs: `border-slate-200`, fondo claro, foco con `brand-accent`/`brand-vivid`.
- Labels legibles en `text-slate-700`.
- Mensajes de error en rojo con caja y borde sutil.

### Botones

- Primario submit: `from-brand-accent` a `to-brand-vivid`.
- Evitar `from-brand-primary` en botones con texto blanco por bajo contraste.

### Texto de branding lateral

- Titulo en `text-slate-900` + acento `gradient-text`.
- Parrafos y bullets en `text-slate-700`.

## 7. Portal

Archivo principal: `src/app/portal/page.js`.

### Estilo general

- Base visual oscura para area operativa.
- Fondo principal del contenedor: violeta oscuro.
- Navbar superior: tono violeta corporativo estable.

### Componentes de portal

- Controles de navegacion compactos y funcionales.
- Estados activos visibles (`bg-white/20` o equivalente).
- Inputs sobre fondo oscuro con placeholders legibles.
- Evitar combinaciones con opacidad extrema que oculten contenido.

## 8. Animaciones

Definidas en `src/app/globals.css`:

- `fadeInUp`, `fadeInDown`, `fadeInLeft`, `fadeInRight`
- `float`, `float-slow`
- `pulse-glow`, `scale-in`, `gradient-shift`
- Utilidades `reveal`, `reveal-left`, `reveal-right`

Regla:

- Animaciones deben apoyar jerarquia visual, no distraer.
- Mantener duraciones suaves y consistentes.

## 9. Reglas para futuros cambios (agentes y equipo)

- No cambiar paleta base sin aprobacion explicita.
- No introducir temas nuevos que rompan continuidad de marca.
- Todo cambio en botones/inputs debe validar contraste visual.
- Si se toca landing, revisar tambien login/registro para coherencia.
- Si se toca portal, respetar su modo operativo oscuro y claridad funcional.

## 10. Checklist rapido antes de subir cambios de UI

- CTAs principales se leen a primera vista.
- Labels e inputs son legibles en desktop y mobile.
- Hover/focus visibles en botones y enlaces.
- No hay texto claro sobre fondo claro.
- La paleta se mantiene dentro de los tokens definidos.
