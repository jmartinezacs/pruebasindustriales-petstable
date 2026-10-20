# CLAUDE.md

Pruebas industriales · Pet's Table. UI en español; responder en español. Zona horaria `America/Mexico_City`.

- **Frontend:** JS vanilla (módulos ES) en `public/`; se empaqueta en un solo `index.html` con `tools/build-single.ps1`.
- **Backend:** Supabase `domumnsezocubigfqwry`. Todo objeto propio lleva el sufijo `_prubind`; no tocar objetos de otros sistemas (`med_*`, `brom_*`, etc.). Migraciones no destructivas en `supabase/migrations/`.
- **Repo:** `https://github.com/jmartinezacs/pruebasindustriales-petstable` (público, rama `main`). Vercel publica la raíz: `index.html` (generado, no editar a mano), `apple-touch-icon.png`, `version.json` y `vercel.json`; `.vercelignore` deja fuera las fuentes.
- **Publicar una versión:** 1) editar `public/`; 2) subir `APP_VERSION` en `public/js/config.js`; 3) `powershell -ExecutionPolicy Bypass -File tools\build-single.ps1`; 4) commit y push a `main`. La app avisa "Hay una nueva versión disponible" al cambiar `version.json`.
- **Git en Windows:** en una consola nueva refrescar `PATH`: `$env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User')`. La autenticación es con Git Credential Manager; nunca escribir credenciales.
- **Pruebas SQL:** `tests/sql/*.sql` se ejecutan completos con `execute_sql`; simulan usuarios con `request.jwt.claims` y todo se revierte.
- Nunca incluir la service_role key ni llaves `sb_secret_` en el navegador ni en el repo.
