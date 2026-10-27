// SPDX-License-Identifier: MIT
#ifndef RUNNER_PRINT_CHANNEL_H_
#define RUNNER_PRINT_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// Answers the « org.edupaint/print » channel of Color for the life of
// |view|: « printImage » opens the print dialog of the system over the
// window of the view. See lib/studio_printer.dart for the other side.
void color_print_channel_register(FlView* view);

#endif  // RUNNER_PRINT_CHANNEL_H_
