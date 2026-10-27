#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "print_channel.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Smallest content area of the window, in logical pixels.
static const gint kMinimumContentWidth = 680;
static const gint kMinimumContentHeight = 520;

// Gives the window the icon kept beside the program, for desktops that show
// one without a desktop entry. Where the entry is installed, the desktop
// uses the icon of the entry. A missing file leaves the default icon.
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", nullptr);
  if (executable == nullptr) {
    return;
  }
  g_autofree gchar* directory = g_path_get_dirname(executable);
  g_autofree gchar* icon =
      g_build_filename(directory, "data", "color-icon.png", nullptr);
  gtk_window_set_icon_from_file(window, icon, nullptr);
}

// --- Where the interface is, for assistive technologies ---------------------
//
// The accessible object of the Flutter view is an AtkPlug, embedded in a
// socket of this same process. Once the plug is embedded, the accessibility
// bridge of the system (at-spi2-core, impl_Embedded) answers every question
// about the place of the plug by asking its socket over D-Bus and waiting
// for the reply. Here the program would wait for itself: 25 seconds each
// time a screen reader asks where a button is, entirely frozen meanwhile,
// since the place of every element is computed from the place of the plug.
// The place of the view is known here: answer from the widget instead.
// Names, roles and actions are not concerned. See docs/LINUX-DESKTOP.md.
static GtkWidget* accessible_view = nullptr;
static gint (*view_children_count_before)(AtkObject* object) = nullptr;

static void view_extents(AtkComponent* component,
                         gint* x,
                         gint* y,
                         gint* width,
                         gint* height,
                         AtkCoordType coord_type) {
  gint left = 0, top = 0, wide = 0, high = 0;
  GtkWidget* widget = accessible_view;
  if (widget != nullptr && gtk_widget_get_realized(widget)) {
    GtkAllocation allocation;
    gtk_widget_get_allocation(widget, &allocation);
    wide = allocation.width;
    high = allocation.height;
    GtkWidget* toplevel = gtk_widget_get_toplevel(widget);
    gtk_widget_translate_coordinates(widget, toplevel, 0, 0, &left, &top);
    if (coord_type == ATK_XY_SCREEN) {
      gint origin_x = 0, origin_y = 0;
      gdk_window_get_origin(gtk_widget_get_window(toplevel), &origin_x,
                            &origin_y);
      left += origin_x;
      top += origin_y;
    }
  }
  if (x != nullptr) {
    *x = left;
  }
  if (y != nullptr) {
    *y = top;
  }
  if (width != nullptr) {
    *width = wide;
  }
  if (height != nullptr) {
    *height = high;
  }
}

static void view_position(AtkComponent* component,
                          gint* x,
                          gint* y,
                          AtkCoordType coord_type) {
  view_extents(component, x, y, nullptr, nullptr, coord_type);
}

static void view_size(AtkComponent* component, gint* width, gint* height) {
  view_extents(component, nullptr, nullptr, width, height, ATK_XY_WINDOW);
}

// The bridge installs its own answers when the plug is embedded, and counts
// the children of the plug right afterwards; a reader also counts them
// before it can know any element. Counting is therefore the moment to put
// the local answers back.
static gint view_children_count(AtkObject* object) {
  if (ATK_IS_COMPONENT(object)) {
    AtkComponentIface* iface = ATK_COMPONENT_GET_IFACE(object);
    if (iface->get_extents != view_extents) {
      iface->get_extents = view_extents;
      iface->get_position = view_position;
      iface->get_size = view_size;
    }
  }
  return view_children_count_before != nullptr
             ? view_children_count_before(object)
             : 0;
}

// Watches the accessible type of the Flutter view, and only that type. Does
// nothing when another version of the engine names things differently.
static void answer_view_place_locally(FlView* view) {
  if (accessible_view != nullptr) {
    return;
  }
  GType type = g_type_from_name("FlViewAccessible");
  if (type == 0 || !g_type_is_a(type, ATK_TYPE_PLUG)) {
    return;
  }
  // The class stays referenced for the life of the program.
  AtkObjectClass* klass = ATK_OBJECT_CLASS(g_type_class_ref(type));
  view_children_count_before = klass->get_n_children;
  klass->get_n_children = view_children_count;
  accessible_view = GTK_WIDGET(view);
  g_object_add_weak_pointer(G_OBJECT(view),
                            reinterpret_cast<gpointer*>(&accessible_view));
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  answer_view_place_locally(view);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  // One studio at a time. The recovery copy and the album belong to a single
  // process: a second launch joins the first one and shows its window,
  // instead of opening another studio on the same folders.
  GList* windows = gtk_application_get_windows(GTK_APPLICATION(application));
  if (windows != nullptr) {
    gtk_window_present(GTK_WINDOW(windows->data));
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Color");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Color");
  }

  gtk_window_set_default_size(window, 1280, 720);
  set_window_icon(window);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  // The studio keeps every tool within reach down to this size of content,
  // the smallest that its layout is tested with. A smaller window would hide
  // tools with no way to reach them. Title bar and borders come on top.
  gtk_widget_set_size_request(GTK_WIDGET(view), kMinimumContentWidth,
                              kMinimumContentHeight);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));
  answer_view_place_locally(view);

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  color_print_channel_register(view);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // No flag: the application is unique, which is GApplication's default (the
  // name of that default changed with GLib 2.74, hence the number). With a
  // session bus, a second launch reaches the first process and ends; without
  // one, GLib runs each launch on its own, as before.
  const GApplicationFlags flags = static_cast<GApplicationFlags>(0);
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}
