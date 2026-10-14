/* The C interfaces the editor uses, which the build translates into one Zig module: SDL3, Dear
 * ImGui through Dear Bindings with its SDL3 and SDL_GPU backends, the few internal calls the
 * editor makes, and the text editor's shim. */
#include <SDL3/SDL.h>

#include "dcimgui.h"
#include "dcimgui_impl_sdl3.h"
#include "dcimgui_impl_sdlgpu3.h"

#include "extras.h"
#include "shim.h"
