// SPDX-License-Identifier: MIT
#ifndef RUNNER_PRINT_PAGE_H_
#define RUNNER_PRINT_PAGE_H_

#include <gtk/gtk.h>

// What became of one request to print.
enum ColorPrintResult {
  // The person confirmed the dialog and the page was handed to the system.
  COLOR_PRINT_SENT,
  // The person closed the dialog without printing, or only asked it for a
  // preview.
  COLOR_PRINT_CANCELLED,
  // The system refused; the error says why.
  COLOR_PRINT_FAILED,
};

// Hands one image to the printing of the system, on one page: as large as
// the page allows, centred, never distorted, the page turned the way the
// image is.
//
// |rgba| holds |width| x |height| pixels of four bytes (red, green, blue,
// alpha), rows from the top, and must stay valid during the call.
//
// With GTK_PRINT_OPERATION_ACTION_PRINT_DIALOG the dialog of the system
// opens, modal for |parent|, and nothing is printed unless the person
// confirms it there; the call returns when the dialog is closed and, if
// confirmed, the page handed over. With GTK_PRINT_OPERATION_ACTION_EXPORT
// the same page is written to |export_filename| as a PDF file, without any
// dialog or printer: this is how the page is checked.
ColorPrintResult color_print_image(GtkWindow* parent,
                                   const guint8* rgba,
                                   gint width,
                                   gint height,
                                   const gchar* job_name,
                                   GtkPrintOperationAction action,
                                   const gchar* export_filename,
                                   GError** error);

#endif  // RUNNER_PRINT_PAGE_H_
