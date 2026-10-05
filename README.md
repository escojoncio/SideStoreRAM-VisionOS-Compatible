# SideStore RAM

SideStore independiente (sin LiveContainer) para Vision Pro, con dos cambios:

- **Sin extensiones**: se elimina el widget, así que solo gasta **un App ID**.
- **Increased Memory Limit automático**: al instalar o renovar cualquier app, SideStore activa la misma capacidad que GetMoreRam en su App ID antes de pedir el perfil, y la mantiene al firmar aunque la app no la declare. Si Apple rechaza esa petición, la instalación continúa con normalidad.

## Cómo se fabrica

GitHub Actions descarga el código oficial de SideStore en una versión fija, aplica los parches de `patches/`, compila, quita la carpeta `PlugIns` y publica `SideStoreRAM.ipa` en la release `latest`.

- `patches/sidestore.patch`: llama a la activación de RAM antes de descargar cada perfil.
- `patches/sidesign.patch`: añade la petición a Apple y conserva el entitlement al firmar.

## Instalación

Instalar `SideStoreRAM.ipa` con iloader. La renovación cada 7 días la hace SideStore como siempre.

## Licencia

SideStore y SideSign son AGPL-3.0; los parches siguen esa misma licencia.
