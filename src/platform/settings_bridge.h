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
extern void wallify_execute_media_command(unsigned int command);
extern void wallify_execute_media_seek(double target);

#include "widget_state.h"

extern void widget_debug_window_hide(void);

extern void wallify_clear_artwork(void);
extern void wallify_extract_color(void);
extern void widget_start_drag(int left, int top, double width);
extern WallifyPanelSnap widget_nearby_panel_snap(int left, int top, double x, double y, double width, double height);
extern void widget_show_snap_outline(double x, double y, double width, double height);
extern void widget_hide_snap_outline(void);
extern void widget_set_snap_debug(double mix, double width, double height, bool dragging);
