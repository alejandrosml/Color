// SPDX-License-Identifier: MIT
#include "print_channel.h"

#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

#include "print_page.h"

namespace {

using flutter::EncodableMap;
using flutter::EncodableValue;

// The same bounds as lib/print_render.dart, with room to spare.
constexpr int64_t kMaximumDimension = 8192;

const EncodableValue* Find(const EncodableMap& map, const char* key) {
  const auto found = map.find(EncodableValue(std::string(key)));
  return found == map.end() ? nullptr : &found->second;
}

// A whole number of Dart arrives in 32 or 64 bits. (The names keep away
// from "small", which the headers of Windows define as a macro.)
bool WholeNumber(const EncodableValue* value, int64_t* number) {
  if (value == nullptr) {
    return false;
  }
  if (const int32_t* in_32_bits = std::get_if<int32_t>(value)) {
    *number = *in_32_bits;
    return true;
  }
  if (const int64_t* in_64_bits = std::get_if<int64_t>(value)) {
    *number = *in_64_bits;
    return true;
  }
  return false;
}

// One dialog at a time. The dialog of Windows runs its own loop of
// messages, where another call or a request to close the window could be
// handled while the first call is still on the stack.
bool dialog_is_open = false;

std::wstring Utf16FromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int size = static_cast<int>(text.size());
  const int length =
      ::MultiByteToWideChar(CP_UTF8, 0, text.data(), size, nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(length), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.data(), size, &wide[0], length);
  return wide;
}

void PrintFromCall(
    HWND owner,
    const flutter::MethodCall<EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  const EncodableMap* arguments = std::get_if<EncodableMap>(call.arguments());
  if (arguments == nullptr) {
    result->Error("INVALID_ARGUMENT",
                  "Une image, sa taille et son nom sont attendus.");
    return;
  }
  const std::vector<uint8_t>* rgba =
      std::get_if<std::vector<uint8_t>>(Find(*arguments, "rgba"));
  const std::string* name =
      std::get_if<std::string>(Find(*arguments, "name"));
  int64_t width = 0;
  int64_t height = 0;
  if (rgba == nullptr || name == nullptr ||
      !WholeNumber(Find(*arguments, "width"), &width) ||
      !WholeNumber(Find(*arguments, "height"), &height) || width < 1 ||
      height < 1 || width > kMaximumDimension || height > kMaximumDimension ||
      rgba->size() !=
          static_cast<size_t>(width) * static_cast<size_t>(height) * 4) {
    result->Error("INVALID_ARGUMENT", "Image de taille inattendue.");
    return;
  }
  if (dialog_is_open) {
    result->Error("PRINT_BUSY", "Une impression est en cours.");
    return;
  }
  DWORD error = 0;
  dialog_is_open = true;
  const PrintResult printed =
      PrintImage(owner, rgba->data(), static_cast<int>(width),
                 static_cast<int>(height), Utf16FromUtf8(*name), &error);
  dialog_is_open = false;
  switch (printed) {
    case PrintResult::kSent:
      result->Success(EncodableValue(std::string("printed")));
      break;
    case PrintResult::kCancelled:
      result->Success(EncodableValue(std::string("cancelled")));
      break;
    case PrintResult::kNoPrinter:
      result->Error("NO_PRINTER", "Windows ne trouve aucune imprimante.");
      break;
    case PrintResult::kFailed:
      result->Error("PRINT_FAILED", "Windows ne peut pas imprimer (code " +
                                        std::to_string(error) + ").");
      break;
  }
}

}  // namespace

bool PrintDialogIsOpen() {
  return dialog_is_open;
}

std::unique_ptr<flutter::MethodChannel<EncodableValue>> CreatePrintChannel(
    flutter::BinaryMessenger* messenger,
    std::function<HWND()> owner) {
  auto channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, "org.edupaint/print",
      &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window = std::move(owner)](
          const flutter::MethodCall<EncodableValue>& call,
          std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
        if (call.method_name() == "printImage") {
          PrintFromCall(window(), call, std::move(result));
        } else {
          result->NotImplemented();
        }
      });
  return channel;
}
