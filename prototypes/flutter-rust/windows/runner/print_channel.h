// SPDX-License-Identifier: MIT
#ifndef RUNNER_PRINT_CHANNEL_H_
#define RUNNER_PRINT_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <functional>
#include <memory>

// Answers the "org.edupaint/print" channel of Color: "printImage" opens the
// print dialog of Windows over the window that |owner| gives at that
// moment. The engine keeps the handler for as long as it lives, or until
// SetMethodCallHandler(nullptr) is called on the returned channel.
// See lib/studio_printer.dart for the other side.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreatePrintChannel(flutter::BinaryMessenger* messenger,
                   std::function<HWND()> owner);

// True while the print dialog of Windows is open: the window must not be
// closed under it.
bool PrintDialogIsOpen();

#endif  // RUNNER_PRINT_CHANNEL_H_
