#include "settings_window.h"
#include "debug_stats.h"
#include "gpu.h"
#include "media_core.h"
#include "layout.h"

extern const char *wallify_settings_path(void);
extern void wallify_open_inspector(void);
extern void wallify_menu_play_pause(void);
extern void wallify_menu_previous(void);
extern void wallify_menu_next(void);
extern void wallify_pointer(double x, double y, int kind);
extern void wallify_set_window_visible(int visible);
extern void wallify_media_key_event(int key_code);
extern void *wallify_copy_idle_texture(int texture_id);
extern void *wallify_idle_surface(void);
extern int wallify_width(void);
extern int wallify_height(void);
extern void widget_debug_window_show(void);
extern void wallify_context_menu_selected(int tag);
extern void wallify_artwork_downloaded(bool available);
