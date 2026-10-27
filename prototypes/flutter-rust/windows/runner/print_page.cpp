// SPDX-License-Identifier: MIT
#include "print_page.h"

#include <commdlg.h>
#include <winspool.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstdlib>
#include <cwchar>

namespace {

void SetError(DWORD* error_code, DWORD value) {
  if (error_code != nullptr) {
    *error_code = value;
  }
}

// True when Windows knows at least one printer, its own or a shared one.
bool AnyPrinter() {
  DWORD needed = 0;
  DWORD count = 0;
  // Asked without room for the answer: with a printer to describe, the call
  // fails for want of room; without any, it succeeds and writes nothing.
  if (::EnumPrintersW(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, nullptr,
                      4, nullptr, 0, &needed, &count)) {
    return false;
  }
  return ::GetLastError() == ERROR_INSUFFICIENT_BUFFER;
}

// One page on the device that the person chose.
PrintResult PrintOnDevice(HDC device,
                          const uint8_t* rgba,
                          int width,
                          int height,
                          const std::wstring& job_name,
                          DWORD* error_code) {
  PageGeometry page = {};
  page.area_width = ::GetDeviceCaps(device, HORZRES);
  page.area_height = ::GetDeviceCaps(device, VERTRES);
  page.paper_width = ::GetDeviceCaps(device, PHYSICALWIDTH);
  page.paper_height = ::GetDeviceCaps(device, PHYSICALHEIGHT);
  page.offset_x = ::GetDeviceCaps(device, PHYSICALOFFSETX);
  page.offset_y = ::GetDeviceCaps(device, PHYSICALOFFSETY);
  page.dpi_x = ::GetDeviceCaps(device, LOGPIXELSX);
  page.dpi_y = ::GetDeviceCaps(device, LOGPIXELSY);
  if (page.area_width < 1 || page.area_height < 1 || page.dpi_x < 1 ||
      page.dpi_y < 1) {
    SetError(error_code, ERROR_INVALID_PARAMETER);
    return PrintResult::kFailed;
  }
  const RECT place = PlaceOnPage(width, height, page);
  const std::vector<uint8_t> pixels = BottomUpBgr(rgba, width, height);

  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = height;
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 24;
  info.bmiHeader.biCompression = BI_RGB;

  DOCINFOW document = {};
  document.cbSize = sizeof(document);
  document.lpszDocName = job_name.c_str();
  if (::StartDocW(device, &document) <= 0) {
    // A printer that writes a file asks for its name here: giving up there
    // is giving up printing.
    const DWORD error = ::GetLastError();
    if (error == ERROR_CANCELLED || error == ERROR_PRINT_CANCELLED) {
      return PrintResult::kCancelled;
    }
    SetError(error_code, error);
    return PrintResult::kFailed;
  }
  bool drawn = ::StartPage(device) > 0;
  if (drawn) {
    ::SetStretchBltMode(device, HALFTONE);
    ::SetBrushOrgEx(device, 0, 0, nullptr);
    const int lines = ::StretchDIBits(
        device, place.left, place.top, place.right - place.left,
        place.bottom - place.top, 0, 0, width, height, pixels.data(), &info,
        DIB_RGB_COLORS, SRCCOPY);
    drawn = lines > 0;
    // The reason of a failure is read at once: the next call replaces it.
    const DWORD drawing_error = drawn ? 0 : ::GetLastError();
    if (::EndPage(device) <= 0) {
      SetError(error_code, drawn ? ::GetLastError() : drawing_error);
      drawn = false;
    } else if (!drawn) {
      SetError(error_code, drawing_error);
    }
  } else {
    SetError(error_code, ::GetLastError());
  }
  if (!drawn) {
    ::AbortDoc(device);
    return PrintResult::kFailed;
  }
  if (::EndDoc(device) <= 0) {
    SetError(error_code, ::GetLastError());
    return PrintResult::kFailed;
  }
  return PrintResult::kSent;
}

}  // namespace

RECT PlaceOnPage(int width, int height, const PageGeometry& page) {
  int origin_x = 0;
  int origin_y = 0;
  int room_width = page.area_width;
  int room_height = page.area_height;
  const int left = page.offset_x;
  const int top = page.offset_y;
  const int right = page.paper_width - page.offset_x - page.area_width;
  const int bottom = page.paper_height - page.offset_y - page.area_height;
  // A driver that describes its paper coherently: keep to the larger margin
  // on both sides. Otherwise the middle of the printable area will do.
  if (left >= 0 && top >= 0 && right >= 0 && bottom >= 0) {
    const int across = std::abs(left - right);
    const int down = std::abs(top - bottom);
    if (across < room_width && down < room_height) {
      origin_x = std::max(left, right) - left;
      origin_y = std::max(top, bottom) - top;
      room_width -= across;
      room_height -= down;
    }
  }
  // Compared in inches: the dots of a printer are not always square.
  const double room_wide = static_cast<double>(room_width) / page.dpi_x;
  const double room_high = static_cast<double>(room_height) / page.dpi_y;
  const double shape = static_cast<double>(width) / height;
  int placed_width = room_width;
  int placed_height = room_height;
  if (room_wide / room_high > shape) {
    placed_width = static_cast<int>(std::lround(room_high * shape * page.dpi_x));
  } else {
    placed_height =
        static_cast<int>(std::lround(room_wide / shape * page.dpi_y));
  }
  placed_width = std::min(std::max(placed_width, 1), room_width);
  placed_height = std::min(std::max(placed_height, 1), room_height);
  RECT place = {};
  place.left = origin_x + (room_width - placed_width) / 2;
  place.top = origin_y + (room_height - placed_height) / 2;
  place.right = place.left + placed_width;
  place.bottom = place.top + placed_height;
  return place;
}

std::vector<uint8_t> BottomUpBgr(const uint8_t* rgba, int width, int height) {
  const size_t wide = static_cast<size_t>(width);
  const size_t high = static_cast<size_t>(height);
  const size_t stride = (wide * 3 + 3) & ~static_cast<size_t>(3);
  std::vector<uint8_t> pixels(stride * high);
  for (size_t y = 0; y < high; ++y) {
    const uint8_t* from = rgba + (high - 1 - y) * wide * 4;
    uint8_t* to = pixels.data() + y * stride;
    for (size_t x = 0; x < wide; ++x) {
      to[x * 3] = from[x * 4 + 2];
      to[x * 3 + 1] = from[x * 4 + 1];
      to[x * 3 + 2] = from[x * 4];
    }
  }
  return pixels;
}

PrintResult PrintImage(HWND owner,
                       const uint8_t* rgba,
                       int width,
                       int height,
                       const std::wstring& job_name,
                       DWORD* error_code) {
  SetError(error_code, 0);
  if (rgba == nullptr || width < 1 || height < 1) {
    SetError(error_code, ERROR_INVALID_PARAMETER);
    return PrintResult::kFailed;
  }
  // Without a printer no dialog opens: Color explains it in its own words,
  // rather than Windows offering to install one.
  if (!AnyPrinter()) {
    return PrintResult::kNoPrinter;
  }

  const short wanted = static_cast<short>(
      width > height ? DMORIENT_LANDSCAPE : DMORIENT_PORTRAIT);
  // The printer whose page was turned before the dialog opened.
  std::wstring turned_printer;

  PRINTDLGW dialog = {};
  dialog.lStructSize = sizeof(dialog);
  // The settings of the printer that Windows proposes, asked without any
  // window, to turn its page the way the drawing is before the dialog
  // opens. The person can still decide otherwise there.
  dialog.Flags = PD_RETURNDEFAULT;
  if (::PrintDlgW(&dialog) && dialog.hDevMode != nullptr) {
    DEVMODEW* mode = static_cast<DEVMODEW*>(::GlobalLock(dialog.hDevMode));
    if (mode != nullptr) {
      if ((mode->dmFields & DM_ORIENTATION) != 0) {
        mode->dmOrientation = wanted;
        turned_printer.assign(mode->dmDeviceName,
                              ::wcsnlen(mode->dmDeviceName, CCHDEVICENAME));
      }
      ::GlobalUnlock(dialog.hDevMode);
    }
  } else {
    // No proposed printer is not yet no printer: the dialog will tell.
    if (dialog.hDevMode != nullptr) {
      ::GlobalFree(dialog.hDevMode);
    }
    if (dialog.hDevNames != nullptr) {
      ::GlobalFree(dialog.hDevNames);
    }
    dialog.hDevMode = nullptr;
    dialog.hDevNames = nullptr;
  }

  // One page, the whole drawing: no page numbers, no selection. Should the
  // printers have gone meanwhile, the dialog says nothing itself.
  dialog.hwndOwner = owner;
  dialog.Flags = PD_RETURNDC | PD_NOPAGENUMS | PD_NOSELECTION |
                 PD_HIDEPRINTTOFILE | PD_NOWARNING |
                 PD_USEDEVMODECOPIESANDCOLLATE;
  dialog.nCopies = 1;
  // The first call did not ask for a device: nothing says what it left here.
  dialog.hDC = nullptr;
  PrintResult result = PrintResult::kCancelled;
  if (::PrintDlgW(&dialog)) {
    if (dialog.hDC != nullptr) {
      // Another printer chosen in the dialog starts from its own settings:
      // its page is turned the way the drawing is, as the first one was.
      DEVMODEW* mode =
          dialog.hDevMode != nullptr
              ? static_cast<DEVMODEW*>(::GlobalLock(dialog.hDevMode))
              : nullptr;
      if (mode != nullptr) {
        const std::wstring chosen(
            mode->dmDeviceName, ::wcsnlen(mode->dmDeviceName, CCHDEVICENAME));
        if (chosen != turned_printer &&
            (mode->dmFields & DM_ORIENTATION) != 0 &&
            mode->dmOrientation != wanted) {
          mode->dmOrientation = wanted;
          ::ResetDCW(dialog.hDC, mode);
        }
        ::GlobalUnlock(dialog.hDevMode);
      }
      result =
          PrintOnDevice(dialog.hDC, rgba, width, height, job_name, error_code);
    } else {
      SetError(error_code, ERROR_INVALID_HANDLE);
      result = PrintResult::kFailed;
    }
  } else {
    // Zero is the person closing the dialog.
    const DWORD error = ::CommDlgExtendedError();
    if (error == PDERR_NODEFAULTPRN || error == PDERR_NODEVICES) {
      result = PrintResult::kNoPrinter;
    } else if (error != 0) {
      SetError(error_code, error);
      result = PrintResult::kFailed;
    }
  }
  if (dialog.hDC != nullptr) {
    ::DeleteDC(dialog.hDC);
  }
  if (dialog.hDevMode != nullptr) {
    ::GlobalFree(dialog.hDevMode);
  }
  if (dialog.hDevNames != nullptr) {
    ::GlobalFree(dialog.hDevNames);
  }
  return result;
}
