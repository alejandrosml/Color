// SPDX-License-Identifier: MIT
#include "print_page.h"

namespace {

struct PrintJob {
  GdkPixbuf* pixbuf;
  gint width;
  gint height;
  // The person asked the dialog for a preview: nothing is printed.
  gboolean previewed;
};

// Four margins of a sheet of paper, in points.
struct Margins {
  double left;
  double top;
  double right;
  double bottom;
};

// The margins of the paper as the person sees them once the page is turned:
// GTK keeps them for the paper as it enters the printer.
Margins turned(GtkPageOrientation orientation, const Margins& paper) {
  switch (orientation) {
    case GTK_PAGE_ORIENTATION_LANDSCAPE:
      return {paper.bottom, paper.left, paper.top, paper.right};
    case GTK_PAGE_ORIENTATION_REVERSE_PORTRAIT:
      return {paper.right, paper.bottom, paper.left, paper.top};
    case GTK_PAGE_ORIENTATION_REVERSE_LANDSCAPE:
      return {paper.top, paper.right, paper.bottom, paper.left};
    case GTK_PAGE_ORIENTATION_PORTRAIT:
    default:
      return paper;
  }
}

// The only page: the image as large as the paper and printer chosen in the
// dialog allow, never distorted, in the middle of the paper. The context
// starts at the corner of the area inside the margins of the page setup.
// What the printer cannot reach is rarely the same on each side, and may be
// more than those margins: the image keeps to the largest of them on both
// sides.
void draw_page_cb(GtkPrintOperation* operation,
                  GtkPrintContext* context,
                  gint page_number,
                  gpointer user_data) {
  const PrintJob* job = static_cast<const PrintJob*>(user_data);
  double room_width = gtk_print_context_get_width(context);
  double room_height = gtk_print_context_get_height(context);
  double origin_x = 0;
  double origin_y = 0;
  GtkPageSetup* setup = gtk_print_context_get_page_setup(context);
  if (setup != nullptr) {
    const GtkPageOrientation orientation =
        gtk_page_setup_get_orientation(setup);
    const Margins page = turned(
        orientation,
        {gtk_page_setup_get_left_margin(setup, GTK_UNIT_POINTS),
         gtk_page_setup_get_top_margin(setup, GTK_UNIT_POINTS),
         gtk_page_setup_get_right_margin(setup, GTK_UNIT_POINTS),
         gtk_page_setup_get_bottom_margin(setup, GTK_UNIT_POINTS)});
    Margins kept = page;
    double hard_top = 0, hard_bottom = 0, hard_left = 0, hard_right = 0;
    if (gtk_print_context_get_hard_margins(context, &hard_top, &hard_bottom,
                                           &hard_left, &hard_right)) {
      const Margins hard =
          turned(orientation, {hard_left, hard_top, hard_right, hard_bottom});
      kept = {MAX(page.left, hard.left), MAX(page.top, hard.top),
              MAX(page.right, hard.right), MAX(page.bottom, hard.bottom)};
    }
    const double side = MAX(kept.left, kept.right);
    const double level = MAX(kept.top, kept.bottom);
    const double across = room_width + page.left + page.right - 2 * side;
    const double down = room_height + page.top + page.bottom - 2 * level;
    if (across > 0 && down > 0) {
      origin_x = side - page.left;
      origin_y = level - page.top;
      room_width = across;
      room_height = down;
    }
  }
  if (room_width <= 0 || room_height <= 0) {
    return;
  }
  const double scale =
      MIN(room_width / job->width, room_height / job->height);
  cairo_t* cr = gtk_print_context_get_cairo_context(context);
  cairo_save(cr);
  cairo_translate(cr, origin_x + (room_width - job->width * scale) / 2.0,
                  origin_y + (room_height - job->height * scale) / 2.0);
  cairo_scale(cr, scale, scale);
  gdk_cairo_set_source_pixbuf(cr, job->pixbuf, 0, 0);
  cairo_rectangle(cr, 0, 0, job->width, job->height);
  cairo_fill(cr);
  cairo_restore(cr);
}

// The dialog of GTK always offers « Preview », and answers it as it answers
// « Print ». GTK shows its own preview; Color only remembers that the page
// was not sent to a printer.
gboolean preview_cb(GtkPrintOperation* operation,
                    GtkPrintOperationPreview* preview,
                    GtkPrintContext* context,
                    GtkWindow* parent,
                    gpointer user_data) {
  static_cast<PrintJob*>(user_data)->previewed = TRUE;
  return FALSE;
}

}  // namespace

ColorPrintResult color_print_image(GtkWindow* parent,
                                   const guint8* rgba,
                                   gint width,
                                   gint height,
                                   const gchar* job_name,
                                   GtkPrintOperationAction action,
                                   const gchar* export_filename,
                                   GError** error) {
  g_return_val_if_fail(rgba != nullptr && width > 0 && height > 0,
                       COLOR_PRINT_FAILED);
  g_autoptr(GdkPixbuf) pixbuf = gdk_pixbuf_new_from_data(
      rgba, GDK_COLORSPACE_RGB, TRUE, 8, width, height, width * 4, nullptr,
      nullptr);
  if (pixbuf == nullptr) {
    g_set_error_literal(error, GTK_PRINT_ERROR, GTK_PRINT_ERROR_GENERAL,
                        "L’image du dessin n’a pas pu être préparée.");
    return COLOR_PRINT_FAILED;
  }
  PrintJob job = {pixbuf, width, height, FALSE};

  g_autoptr(GtkPrintOperation) operation = gtk_print_operation_new();
  gtk_print_operation_set_n_pages(operation, 1);
  gtk_print_operation_set_unit(operation, GTK_UNIT_POINTS);
  if (job_name != nullptr && job_name[0] != '\0') {
    gtk_print_operation_set_job_name(operation, job_name);
  }
  // The page is turned the way the drawing is. The dialog shows the paper
  // and its direction, so that the person can decide otherwise.
  g_autoptr(GtkPageSetup) setup = gtk_page_setup_new();
  gtk_page_setup_set_orientation(setup, width > height
                                            ? GTK_PAGE_ORIENTATION_LANDSCAPE
                                            : GTK_PAGE_ORIENTATION_PORTRAIT);
  gtk_print_operation_set_default_page_setup(operation, setup);
  gtk_print_operation_set_embed_page_setup(operation, TRUE);
  if (export_filename != nullptr) {
    gtk_print_operation_set_export_filename(operation, export_filename);
  }
  g_signal_connect(operation, "draw-page", G_CALLBACK(draw_page_cb), &job);
  g_signal_connect(operation, "preview", G_CALLBACK(preview_cb), &job);

  // With the dialog, this runs the main loop until the dialog is closed and
  // the page handed over: the pixels and |job| outlive every drawing.
  switch (gtk_print_operation_run(operation, action, parent, error)) {
    case GTK_PRINT_OPERATION_RESULT_APPLY:
    case GTK_PRINT_OPERATION_RESULT_IN_PROGRESS:
      return job.previewed ? COLOR_PRINT_CANCELLED : COLOR_PRINT_SENT;
    case GTK_PRINT_OPERATION_RESULT_CANCEL:
      return COLOR_PRINT_CANCELLED;
    case GTK_PRINT_OPERATION_RESULT_ERROR:
    default:
      return COLOR_PRINT_FAILED;
  }
}
