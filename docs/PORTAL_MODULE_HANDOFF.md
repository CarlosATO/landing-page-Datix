# Portal Module Handoff

Current development handoff between the portal and local module frontends uses `access_token` and `refresh_token` in the URL hash.

Scope:
- Development only.
- Applies to local module frontends such as `logistica_saas` and `construccion_saas`.

TODO técnico:
- No considerar este mecanismo como solución final de producción.
- En producción se debe migrar a cookie segura compartida o handoff server-side.
- No loguear tokens.
- No guardar tokens en logs.
- Limpiar el hash después de `supabase.auth.setSession(...)`.

Operational note:
- The portal passes the session hash only to bootstrap the local module app.
- The module must call `supabase.auth.setSession(...)` once, then clear `window.location.hash`.
- Tokens must remain managed by Supabase Auth client state, not manual persistence.
