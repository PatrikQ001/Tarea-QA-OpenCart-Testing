# Deploy OpenCart 4.1 en Railway

Despliegue de la tienda OpenCart completa (PHP 8.2 + Apache + MySQL) usando Docker.

## Qué hace el setup

- `Dockerfile` — imagen `php:8.2-apache` con extensiones `mysqli, gd, curl, zip, mbstring, intl`, sirviendo `upload/` como webroot.
- `docker/entrypoint.sh` — en cada arranque:
  1. Configura Apache para escuchar en `$PORT` (Railway lo inyecta).
  2. Genera `config.php` y `admin/config.php` desde variables de entorno.
  3. Espera a MySQL.
  4. Corre `install/cli_install.php` **solo si** las tablas `oc_` no existen (idempotente; no borra datos en redeploys).
  5. Elimina `install/`.
- `railway.json` — le dice a Railway que use el `Dockerfile`.
- `.dockerignore` — recorta el contexto de build (excluye `opencart/`, `tests/`, `docs/`, etc.).

## Pasos

1. **Crear proyecto en Railway** → New Project → Deploy from GitHub repo → elegir `PatrikQ001/Tarea-QA-OpenCart-Testing`.
2. **Agregar MySQL**: dentro del proyecto, `+ New` → Database → **Add MySQL**. Railway expone `MYSQLHOST`, `MYSQLPORT`, `MYSQLUSER`, `MYSQLPASSWORD`, `MYSQLDATABASE`.
3. **Referenciar las vars de MySQL en el servicio web**: en el servicio de la app → Variables → `Add Reference` → seleccionar las 5 variables `MYSQL*` del servicio MySQL. (O usar `${{MySQL.MYSQLHOST}}`, etc.)
4. **Variables del admin** (opcional, tienen defaults):
   - `OC_ADMIN_USER` (default `admin`)
   - `OC_ADMIN_EMAIL` (default `admin@example.com`)
   - `OC_ADMIN_PASSWORD` (default `admin123`) — **cámbiala**.
5. **Generar dominio**: servicio web → Settings → Networking → **Generate Domain**. Railway setea `RAILWAY_PUBLIC_DOMAIN`, que el entrypoint usa como `HTTP_SERVER`.
6. **Deploy**. El primer arranque instala la BD (catálogo demo incluido).

- Tienda: `https://<tu-dominio>/`
- Admin: `https://<tu-dominio>/admin/`

## Importante

- **Filesystem efímero**: imágenes subidas, sesiones y cache se pierden en cada redeploy. Para persistir, agregá un **Volume** en Railway montado en `/var/www/html/system/storage` (y opcionalmente `/var/www/html/image`).
- **Seguridad**: cambiá `OC_ADMIN_PASSWORD` y el email. El `install/` se borra solo tras instalar.
- **Redeploy seguro**: el instalador no corre si ya hay tablas `oc_`, así que no pierdes el catálogo configurado.

## Probar local (docker-compose, opcional)

Si querés verlo local antes, se puede levantar con un `mysql` y este mismo `Dockerfile` apuntando `MYSQLHOST=mysql`. Pedímelo y agrego un `docker-compose.yml`.
