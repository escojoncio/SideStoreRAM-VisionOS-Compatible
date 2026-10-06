# SideStore RAM

> **Written by Claude.** The patches and the build in this repository were written by Claude
> (Anthropic's AI), building on the great work of the projects credited below; the owner of this
> repository contributed ideas on how some things could be adapted.
>
> **Based on / thanks to:** [SideStore](https://github.com/SideStore/SideStore) and the SideStore
> team - this is their app with two patches on top -, [GetMoreRam](https://github.com/hugeBlack/GetMoreRam)
> by [hugeBlack](https://github.com/hugeBlack), whose idea of asking Apple for the Increased Memory
> Limit capability is what the patches do on every install, and
> [iloader](https://github.com/nab138/iloader) by [nab138](https://github.com/nab138), whose SMS
> sign-in the patches follow. Thank you for your work!


SideStore independiente (sin LiveContainer) para Vision Pro, con dos cambios:

- **Sin extensiones**: se elimina el widget, así que solo gasta **un App ID**.
- **Increased Memory Limit automático**: al instalar o renovar cualquier app, SideStore activa la misma capacidad que GetMoreRam en su App ID antes de pedir el perfil, y la mantiene al firmar aunque la app no la declare. Si Apple rechaza esa petición, la instalación continúa con normalidad.
- **Una sola App ID para la misma app en iPhone y Vision Pro**: si la App ID se usó antes desde otro dispositivo (por ejemplo StikDebug instalado en el iPhone con SideStore), el perfil que Apple tenía para ella no incluye el Vision Pro y la instalación fallaba con 0xe8008015. Ahora SideStore borra ese perfil y pide uno nuevo que sí lo incluye.

## Cómo se fabrica

GitHub Actions descarga el código oficial de SideStore en una versión fija, aplica los parches de `patches/`, compila, quita la carpeta `PlugIns` y publica `SideStoreRAM.ipa` en la release `latest`. Solo compila cuando se pide: a mano (*Actions › Run workflow*) o con `[build]` en el mensaje del commit.

- `patches/sidestore.patch`: llama a la activación de RAM antes de descargar cada perfil, y renueva el perfil si no incluye este dispositivo.
- `patches/sidesign.patch`: añade la petición a Apple, conserva el entitlement al firmar y usa el mismo inicio de sesión por SMS que la última versión de iloader (pide a Apple la lista real de números de confianza y usa sus endpoints JSON).

## Instalación

Instalar `SideStoreRAM.ipa` con iloader. La renovación cada 7 días la hace SideStore como siempre.

## Licencia

SideStore y SideSign son AGPL-3.0; los parches siguen esa misma licencia.
