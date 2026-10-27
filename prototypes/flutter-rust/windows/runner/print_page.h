// SPDX-License-Identifier: MIT
#ifndef RUNNER_PRINT_PAGE_H_
#define RUNNER_PRINT_PAGE_H_

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

// What became of one request to print.
enum class PrintResult {
  // The person confirmed the dialog and the page was handed to Windows.
  kSent,
  // The person closed the dialog without printing.
  kCancelled,
  // Windows knows no printer.
  kNoPrinter,
  // Windows refused: the error code says why.
  kFailed,
};

// The printable area of a page as a printer describes it, in its own dots.
struct PageGeometry {
  // The area that the printer can reach, where drawing starts at (0, 0).
  int area_width;
  int area_height;
  // The whole sheet of paper, and where the area starts on it.
  int paper_width;
  int paper_height;
  int offset_x;
  int offset_y;
  // Dots per inch across and down: they may differ.
  int dpi_x;
  int dpi_y;
};

// Where an image of |width| x |height| pixels goes on |page|: as large as
// the page allows, never distorted, in the middle of the paper. What the
// printer cannot reach is rarely the same on each side: the image keeps to
// the larger margin on both sides.
RECT PlaceOnPage(int width, int height, const PageGeometry& page);

// The pixels as GDI prints them on every driver: rows from the bottom,
// three bytes per pixel (blue, green, red), each row padded to four bytes.
// |rgba| holds |width| x |height| pixels of four bytes, rows from the top.
std::vector<uint8_t> BottomUpBgr(const uint8_t* rgba, int width, int height);

// Opens the print dialog of Windows over |owner| for one image on one page.
// Nothing is printed unless the person confirms it there. Returns when the
// dialog is closed and, if confirmed, the page handed to the spooler. Where
// Windows knows no printer, no dialog opens and the result is kNoPrinter.
// |error_code| receives the code of Windows when the result is kFailed.
PrintResult PrintImage(HWND owner,
                       const uint8_t* rgba,
                       int width,
                       int height,
                       const std::wstring& job_name,
                       DWORD* error_code);

#endif  // RUNNER_PRINT_PAGE_H_
