# Real macOS RGBA16 regression fixture

`macos-release-rgba16.png` is a byte-for-byte copy of the release Color export
`reports/flutter/color-0.5.0-fixed/Color-couleurs-2x.png`.

- Dimensions: 2400 × 1600.
- PNG IHDR: RGBA, 16 bits per channel, noninterlaced.
- SHA-256: `eb7737b0aad4fa9b9c873dd63a3b704b161aab24db7df5a69f8574538b9298c3`.
- File size: 91715 bytes.
- The source contains sBIT and no ICC/sRGB chunk.

This file reproduced an import rejection in the native macOS application.
It is intentionally separate from the synthetic-fixture generator manifest.
The test checks normalization to explicitly tagged sRGB8 and exact normalized
pixels after reopening. It does not demonstrate that the headless test renderer
uses the same GPU snapshot format: the macOS application still needs runtime
qualification of P3/alpha and its raster-rendered/raster-png diagnostic events.
