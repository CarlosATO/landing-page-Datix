# Security Notes

- `SUPABASE_SERVICE_ROLE_KEY` must never be exposed to the browser.
- If a service role key was committed, leaked, or otherwise exposed, rotate it immediately in Supabase.
- Keep `.env`, `.env.local`, and `.env.*` out of version control.
