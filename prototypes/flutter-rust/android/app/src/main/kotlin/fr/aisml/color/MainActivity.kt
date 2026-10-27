// SPDX-License-Identifier: MIT
package fr.aisml.color

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PageRange
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.print.PrintDocumentInfo
import android.print.PrintJob
import android.print.PrintManager
import android.print.pdf.PrintedPdfDocument
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/**
 * The window of Color on Android. Two things that only the system can do are
 * done here, in Kotlin: printing the picture of the sheet, and putting a copy
 * of a file where the person chooses. The other side of the two channels is
 * lib/studio_printer.dart and lib/studio_files.dart. Everything else — the
 * drawing, the files of Color, the sounds — is Dart and Rust.
 */
class MainActivity : FlutterActivity() {
    private val work = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pendingCopy: PendingCopy? = null
    private var printing = false

    /** A copy waiting for the place the person chooses in the system's panel. */
    private class PendingCopy(val source: File, val result: MethodChannel.Result)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "org.edupaint/print").setMethodCallHandler { call, result ->
            if (call.method != "printImage") {
                result.notImplemented()
            } else {
                printImage(
                    call.argument<Int>("width"),
                    call.argument<Int>("height"),
                    call.argument<String>("name"),
                    call.argument<ByteArray>("rgba"),
                    result,
                )
            }
        }
        MethodChannel(messenger, "org.edupaint/files").setMethodCallHandler { call, result ->
            if (call.method != "saveAs") {
                result.notImplemented()
            } else {
                saveAs(
                    call.argument<String>("path"),
                    call.argument<String>("name"),
                    call.argument<String>("mime"),
                    result,
                )
            }
        }
    }

    // « Imprimer » : the print panel of Android, one page, the drawing as
    // large as the paper allows, never distorted. Nothing is printed unless
    // the person confirms it there; « Enregistrer au format PDF » counts as
    // printed, as it does on the Mac.
    private fun printImage(
        width: Int?,
        height: Int?,
        name: String?,
        rgba: ByteArray?,
        result: MethodChannel.Result,
    ) {
        if (printing) {
            result.error("PRINT_BUSY", "Une impression est déjà en préparation.", null)
            return
        }
        if (width == null || height == null || name == null || rgba == null ||
            width <= 0 || height <= 0 || width > 8192 || height > 8192 ||
            rgba.size != width * height * 4
        ) {
            result.error("INVALID_ARGUMENT", "Une image, sa taille et son nom sont nécessaires.", null)
            return
        }
        val bitmap = try {
            // Opaque pixels: the fourth byte of each is not read elsewhere,
            // and is made opaque here.
            for (index in 3 until rgba.size step 4) rgba[index] = 0xFF.toByte()
            Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
                copyPixelsFromBuffer(ByteBuffer.wrap(rgba))
            }
        } catch (error: Throwable) {
            result.error("PRINT_FAILED", "L’image du dessin n’a pas pu être préparée.", error.message)
            return
        }
        val manager = getSystemService(Context.PRINT_SERVICE) as? PrintManager
        if (manager == null) {
            bitmap.recycle()
            result.error("PRINT_FAILED", "Le service d’impression est indisponible.", null)
            return
        }
        val landscape = width > height
        val attributes = PrintAttributes.Builder()
            .setMediaSize(
                if (landscape) PrintAttributes.MediaSize.ISO_A4.asLandscape()
                else PrintAttributes.MediaSize.ISO_A4.asPortrait(),
            )
            .setColorMode(PrintAttributes.COLOR_MODE_COLOR)
            .build()
        printing = true
        var job: PrintJob? = null
        var answered = false
        val adapter = SheetPrintAdapter(this, bitmap, name) {
            // The panel is closed and the job left the adapter: confirmed or
            // given up. The answer is given once.
            if (!answered) {
                answered = true
                printing = false
                val printed = job?.let { !it.isCancelled && !it.isFailed } ?: false
                result.success(if (printed) "printed" else "cancelled")
            }
            bitmap.recycle()
        }
        try {
            job = manager.print(name, adapter, attributes)
        } catch (error: Exception) {
            printing = false
            answered = true
            bitmap.recycle()
            result.error("PRINT_FAILED", "Le service d’impression a refusé le dessin.", error.message)
        }
    }

    // « Enregistrer sous » and « Exporter » : the panel of Android where the
    // person chooses a place — a folder of the device, a cloud — and a name.
    // The file waits in Color's own cache; it is copied there, then Dart takes
    // it back out of the cache.
    private fun saveAs(path: String?, name: String?, mime: String?, result: MethodChannel.Result) {
        if (pendingCopy != null) {
            result.error("SAVE_BUSY", "Un panneau est déjà ouvert.", null)
            return
        }
        val source = path?.let { File(it) }
        if (source == null || name == null || !source.isFile) {
            result.error("INVALID_ARGUMENT", "Un fichier et son nom sont nécessaires.", null)
            return
        }
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = mime ?: "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, name)
        }
        pendingCopy = PendingCopy(source, result)
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, COPY_REQUEST)
        } catch (error: Exception) {
            pendingCopy = null
            result.error("SAVE_FAILED", "Aucune application ne peut recevoir ce fichier.", error.message)
        }
    }

    @Deprecated("FlutterActivity is no ComponentActivity: the Activity Result API is not offered.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != COPY_REQUEST) return
        val pending = pendingCopy ?: return
        pendingCopy = null
        val target = data?.data
        if (resultCode != Activity.RESULT_OK || target == null) {
            pending.result.success(null)
            return
        }
        work.execute {
            try {
                val output = contentResolver.openOutputStream(target, "wt")
                    ?: throw IllegalStateException("La destination n’a pas pu être ouverte.")
                output.use { stream -> FileInputStream(pending.source).use { it.copyTo(stream) } }
                val shown = displayName(target) ?: pending.source.name
                main.post { pending.result.success(shown) }
            } catch (error: Exception) {
                main.post {
                    pending.result.error("SAVE_FAILED", "La copie n’a pas pu être écrite.", error.message)
                }
            }
        }
    }

    private fun displayName(uri: Uri): String? = try {
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        }
    } catch (_: Exception) {
        null
    }

    override fun onDestroy() {
        work.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val COPY_REQUEST = 4207
    }
}

/**
 * One page: the drawing inside margins of at least a centimetre and a half,
 * as large as they allow, centred, never distorted, at the full resolution of
 * the picture.
 */
private class SheetPrintAdapter(
    private val context: Context,
    private val bitmap: Bitmap,
    private val name: String,
    private val finished: () -> Unit,
) : PrintDocumentAdapter() {
    private var attributes: PrintAttributes? = null

    override fun onLayout(
        oldAttributes: PrintAttributes?,
        newAttributes: PrintAttributes,
        cancellationSignal: CancellationSignal?,
        callback: LayoutResultCallback,
        extras: Bundle?,
    ) {
        if (cancellationSignal?.isCanceled == true) {
            callback.onLayoutCancelled()
            return
        }
        attributes = newAttributes
        val info = PrintDocumentInfo.Builder("$name.pdf")
            .setContentType(PrintDocumentInfo.CONTENT_TYPE_PHOTO)
            .setPageCount(1)
            .build()
        callback.onLayoutFinished(info, newAttributes != oldAttributes)
    }

    override fun onWrite(
        pages: Array<out PageRange>?,
        destination: ParcelFileDescriptor,
        cancellationSignal: CancellationSignal?,
        callback: WriteResultCallback,
    ) {
        val chosen = attributes
        if (chosen == null) {
            callback.onWriteFailed("La page n’a pas été préparée.")
            return
        }
        val document = PrintedPdfDocument(context, chosen)
        try {
            val page = document.startPage(0)
            val info = page.info
            val reach = info.contentRect
            // Points of a PDF: 1/72 of an inch; 43 points, a centimetre and a
            // half, from every edge of the paper, or the printer's own margin.
            val least = 43f
            val left = maxOf(reach.left.toFloat(), least)
            val top = maxOf(reach.top.toFloat(), least)
            val right = minOf(reach.right.toFloat(), info.pageWidth - least)
            val bottom = minOf(reach.bottom.toFloat(), info.pageHeight - least)
            val roomWidth = right - left
            val roomHeight = bottom - top
            if (roomWidth > 0 && roomHeight > 0) {
                val scale = minOf(roomWidth / bitmap.width, roomHeight / bitmap.height)
                val drawnWidth = bitmap.width * scale
                val drawnHeight = bitmap.height * scale
                val x = left + (roomWidth - drawnWidth) / 2
                val y = top + (roomHeight - drawnHeight) / 2
                page.canvas.drawBitmap(
                    bitmap,
                    null,
                    RectF(x, y, x + drawnWidth, y + drawnHeight),
                    Paint(Paint.FILTER_BITMAP_FLAG),
                )
            }
            document.finishPage(page)
            if (cancellationSignal?.isCanceled == true) {
                callback.onWriteCancelled()
                return
            }
            FileOutputStream(destination.fileDescriptor).use { document.writeTo(it) }
            callback.onWriteFinished(arrayOf(PageRange.ALL_PAGES))
        } catch (error: Exception) {
            callback.onWriteFailed(error.message)
        } finally {
            document.close()
        }
    }

    override fun onFinish() = finished()
}
