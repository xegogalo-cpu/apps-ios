# Apps de iPhone de Grupo XD

- `maxd/` — maXD (equipo), com.xdcuenca.maxd. Abre https://maxdec.netlify.app/?app=staff.
- `bodega/` — Bodega XD (clientes), com.xdcuenca.app. Abre https://xdecuador.com/?app=tienda.
- `comun/PushPuente.swift` — avisos push nativos (APNs). La página pide permiso con `webkit.messageHandlers.xdPush`
  y recibe el token en `window.__xdPushNativo`. maXD guarda el token (ver `_funciones/avisos-push.md`).

Subir una versión: GitHub → Actions → "Subir app de iPhone" → Run workflow → maxd o bodega.
Para una versión nueva de la tienda cambiar `MARKETING_VERSION` en `project.yml`.
