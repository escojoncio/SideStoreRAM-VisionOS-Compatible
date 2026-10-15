# Bitácora — SideStoreRAM-VisionOS-Compatible

SideStore independiente (sin LiveContainer) para Vision Pro (visionOS 27) con parches propios. Se instala con iLoader-VisionPro; se autorrenueva cada 7 días como SideStore normal.

## Estado tras la última build (commit `0a6c65b`, release `latest` → `SideStoreRAM.ipa`)
Funciona en el dispositivo:
- Sin extensiones (se elimina `PlugIns/`): consume una sola App ID.
- Increased Memory Limit automático en cada instalación/renovación (misma capacidad que GetMoreRam); si Apple lo rechaza, instala igual.
- Renovación del perfil cuando no incluye el UDID del dispositivo (error 0xe8008015 al reutilizar una App ID creada desde el iPhone, p. ej. StikDebug). Verificado: el usuario instaló StikDebug con éxito tras este cambio.
- Inicio de sesión por SMS igual que el iloader actual (lista real de números de confianza, endpoints JSON).

## Archivos
- `patches/sidestore.patch`: activa la RAM antes de descargar cada perfil; tras `downloadProvisioningProfile`, si `profile.deviceIDs` no contiene `fetchUDID()`, llama a `deleteProvisioningProfile(profileID:)` y vuelve a descargar.
- `patches/sidesign.patch`: petición de la capacidad a Apple, conserva el entitlement al firmar aunque la app no lo declare, login SMS.
- `.github/workflows/build.yml`: clona SideStore en el commit fijo `0dd743f`, aplica parches, compila (sdk xros), quita `PlugIns`, publica la release `latest`. Condición `if:` de `[build]` a nivel de job o *Run workflow*.
- `.github/workflows/xros-ddi.yml`: extracción del Developer Disk Image de xrOS (dispatch o cambios en el propio workflow). El DDI es privado: no publicarlo ni enlazarlo fuera del repo.

## Uso en el flujo de AstroVisionPro
- Los IPA de prueba de AstroVisionPro se reempaquetan con el bundle ID de LiveContainer y se instalan con este SideStore para no gastar App IDs nuevas.

## Actualización 2026-10-15 (pendiente de verificar en build)
- `SIDESTORE_COMMIT` → `12ff39c6` (SideSign `752d1ef`: arreglo 2FA HSC 409 "pushedCode").
- `patches/sidesign.patch` rebasado sobre `752d1ef`; el conflicto en `sendPhone2FACodeRequest` se resolvió con nuestra versión (412 = reto activo; -22979/-22981 continúan).

## Pendiente
- Actualizar `SIDESTORE_COMMIT` cuando SideStore publique cambios necesarios para visionOS y recompilar con `[build]`.
