# SideStore RAM

> **Written by Claude.** The patches and the build in this repository were written entirely by
> Claude (Anthropic's AI), following all the instructions and ideas of
> the repository owner.
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

## Cómo se fabrica

GitHub Actions descarga el código oficial de SideStore en una versión fija, aplica los parches de `patches/`, compila, quita la carpeta `PlugIns` y publica `SideStoreRAM.ipa` en la release `latest`.

- `patches/sidestore.patch`: llama a la activación de RAM antes de descargar cada perfil.
- `patches/sidesign.patch`: añade la petición a Apple, conserva el entitlement al firmar y usa el mismo inicio de sesión por SMS que la última versión de iloader (pide a Apple la lista real de números de confianza y usa sus endpoints JSON).

## Instalación

Instalar `SideStoreRAM.ipa` con iloader. La renovación cada 7 días la hace SideStore como siempre.

## Licencia

SideStore y SideSign son AGPL-3.0; los parches siguen esa misma licencia.
