# LiveMoreRAM

LiveContainer + SideStore que activa automáticamente **Increased Memory Limit** (la capacidad que da GetMoreRam) en el App ID de cada app que instalas o renuevas desde SideStore.

## Qué cambia

Solo un archivo nuevo: `src/SideStoreSupport/LMRMemoryCapability.m`.

Justo antes de que SideStore pida a Apple el perfil de aprovisionamiento de una app, envía la misma petición que GetMoreRam (`INCREASED_MEMORY_LIMIT` en el App ID). El perfil que llega ya incluye `com.apple.developer.kernel.increased-memory-limit`.

- Si esa petición falla, la instalación continúa exactamente como antes.
- Los registros aparecen en la consola con el prefijo `[LiveMoreRAM]`.

## Cómo se fabrica el IPA

1. GitHub Actions compila el proyecto de `src/` (misma versión que el IPA original).
2. Toma el IPA original de `base/` y sustituye **solo** el binario de `SideStoreSupport.framework`.
3. `scripts/compare.py` comprueba que todo lo demás es idéntico byte a byte (IDs, versiones, SideStore, extensiones). Si algo difiere, la compilación falla.
4. El resultado se publica en la release `latest` como `LiveMoreRAM.ipa`.

Como los IDs son los mismos, se instala encima del LiveContainer+SideStore actual conservando los datos.

## Limitación

SideStore solo incluye el entitlement en la firma si la propia app lo declara. Las apps que lo declaran (LiveContainer, emuladores, juegos pesados) reciben la RAM extra automáticamente. Las que no lo declaran no cambian, igual que con GetMoreRam.

## Volver atrás

Reinstalar `base/LiveContainer_SideStore.ipa`.

## Licencia

El código de `src/` mantiene su licencia original (AGPL-3.0, ver `src/LICENSE`).
