// SPDX-License-Identifier: MIT
#include "print_channel.h"

#include <gtk/gtk.h>

#include "print_page.h"

namespace {

const char kChannelName[] = "org.edupaint/print";
const char kChannelKey[] = "color-print-channel";

// The same bounds as lib/print_render.dart, with room to spare.
const gint64 kMaximumDimension = 8192;

// One dialog at a time: it runs the main loop, where another call could
// arrive.
gboolean dialog_open = FALSE;

// The answers go through the three functions below: fl_method_call_respond,
// in the pinned engine, frees the error that it hands back.
void answer_error(FlMethodCall* call, const gchar* code, const gchar* message) {
  fl_method_call_respond_error(call, code, message, nullptr, nullptr);
}

void print_image(FlView* view, FlMethodCall* call) {
  FlValue* arguments = fl_method_call_get_args(call);
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    answer_error(call, "INVALID_ARGUMENT", "Une image est nécessaire.");
    return;
  }
  FlValue* rgba = fl_value_lookup_string(arguments, "rgba");
  FlValue* width = fl_value_lookup_string(arguments, "width");
  FlValue* height = fl_value_lookup_string(arguments, "height");
  FlValue* name = fl_value_lookup_string(arguments, "name");
  if (rgba == nullptr || fl_value_get_type(rgba) != FL_VALUE_TYPE_UINT8_LIST ||
      width == nullptr || fl_value_get_type(width) != FL_VALUE_TYPE_INT ||
      height == nullptr || fl_value_get_type(height) != FL_VALUE_TYPE_INT ||
      name == nullptr || fl_value_get_type(name) != FL_VALUE_TYPE_STRING) {
    answer_error(call, "INVALID_ARGUMENT",
                 "Une image, sa taille et son nom sont nécessaires.");
    return;
  }
  const gint64 wide = fl_value_get_int(width);
  const gint64 high = fl_value_get_int(height);
  if (wide < 1 || high < 1 || wide > kMaximumDimension ||
      high > kMaximumDimension ||
      fl_value_get_length(rgba) != static_cast<gsize>(wide * high * 4)) {
    answer_error(call, "INVALID_ARGUMENT",
                 "L’image à imprimer n’a pas la taille annoncée.");
    return;
  }
  if (dialog_open) {
    answer_error(call, "PRINT_BUSY",
                 "La fenêtre d’impression est déjà ouverte.");
    return;
  }

  GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(view));
  GtkWindow* parent = GTK_IS_WINDOW(toplevel) ? GTK_WINDOW(toplevel) : nullptr;
  g_autoptr(GError) error = nullptr;
  dialog_open = TRUE;
  // The arguments belong to the call, which waits for this answer.
  const ColorPrintResult result = color_print_image(
      parent, fl_value_get_uint8_list(rgba), static_cast<gint>(wide),
      static_cast<gint>(high), fl_value_get_string(name),
      GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG, nullptr, &error);
  dialog_open = FALSE;
  if (result == COLOR_PRINT_FAILED) {
    answer_error(call, "PRINT_FAILED",
                 error != nullptr ? error->message
                                  : "Le système a refusé l’impression.");
    return;
  }
  // The response keeps its own reference to the value.
  g_autoptr(FlValue) answer = fl_value_new_string(
      result == COLOR_PRINT_SENT ? "printed" : "cancelled");
  fl_method_call_respond_success(call, answer, nullptr);
}

void method_call_cb(FlMethodChannel* channel,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  if (g_strcmp0(fl_method_call_get_name(method_call), "printImage") == 0) {
    print_image(FL_VIEW(user_data), method_call);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

}  // namespace

void color_print_channel_register(FlView* view) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), kChannelName,
      FL_METHOD_CODEC(codec));
  // The view outlives the handler: it owns the channel.
  fl_method_channel_set_method_call_handler(channel, method_call_cb, view,
                                            nullptr);
  g_object_set_data_full(G_OBJECT(view), kChannelKey, channel, g_object_unref);
}
