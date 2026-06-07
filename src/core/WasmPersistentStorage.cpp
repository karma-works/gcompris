/* GCompris - WasmPersistentStorage.cpp
 *
 * SPDX-FileCopyrightText: 2026 GCompris contributors
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

#include "WasmPersistentStorage.h"

#ifdef Q_OS_WASM
#include <emscripten.h>
#endif

namespace WasmPersistentStorage
{

void sync()
{
#ifdef Q_OS_WASM
    EM_ASM({
        if (typeof FS !== "undefined" && FS.syncfs) {
            Module.gcomprisPersistentSyncRequested = true;
            if (Module.gcomprisPersistentSyncRunning)
                return;

            const runSync = () => {
                if (!Module.gcomprisPersistentSyncRequested) {
                    Module.gcomprisPersistentSyncRunning = false;
                    return;
                }

                Module.gcomprisPersistentSyncRequested = false;
                Module.gcomprisPersistentSyncRunning = true;
                FS.syncfs(false, err => {
                    if (err)
                        console.error("GCompris persistent filesystem sync failed", err);
                    runSync();
                });
            };
            runSync();
        }
    });
#endif
}

}
