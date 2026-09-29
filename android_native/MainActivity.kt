package com.pdfmateapp.pdfmate

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.tom_roush.pdfbox.android.PDFBoxResourceLoader
import com.tom_roush.pdfbox.cos.COSDictionary
import com.tom_roush.pdfbox.cos.COSName
import com.tom_roush.pdfbox.io.MemoryUsageSetting
import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.PDPageContentStream
import com.tom_roush.pdfbox.pdmodel.font.PDType0Font
import com.tom_roush.pdfbox.pdmodel.graphics.state.RenderingMode
import com.tom_roush.pdfbox.text.PDFTextStripper
import com.tom_roush.pdfbox.util.Matrix
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.*

/** A single worker keeps PDF parsing/writing off Android's UI thread. */
class MainActivity : FlutterActivity() {
    private val pdfWorker = Executors.newSingleThreadExecutor()
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        PDFBoxResourceLoader.init(applicationContext)
        MethodChannel(engine.dartExecutor.binaryMessenger, "pdfmate/unicode_overlay")
            .setMethodCallHandler { call, result ->
                if (call.method != "append") { result.notImplemented(); return@setMethodCallHandler }
                val source = call.argument<String>("source")
                val output = call.argument<String>("output")
                val manifest = call.argument<String>("manifest")
                val password = call.argument<String>("password") ?: ""
                if (source == null || output == null || manifest == null) {
                    result.error("ARGUMENT", "Missing document paths", null)
                    return@setMethodCallHandler
                }
                pdfWorker.execute {
                    try {
                        appendOverlay(File(source), File(output), File(manifest), password)
                        Handler(Looper.getMainLooper()).post { result.success(null) }
                    } catch (error: Exception) {
                        Handler(Looper.getMainLooper()).post {
                            result.error("OCR_OVERLAY", error.message ?: "Could not add OCR layer", null)
                        }
                    }
                }
            }
    }

    override fun onDestroy() {
        pdfWorker.shutdown()
        super.onDestroy()
    }

    private fun appendOverlay(source: File, output: File, manifest: File, password: String) {
        require(source.canonicalPath != output.canonicalPath) { "Output must be a new copy" }
        val scratch = File(cacheDir, "pdfmate_overlay_${System.nanoTime()}")
        check(scratch.mkdirs()) { "Cannot create PDF scratch directory" }
        try {
            val memory = MemoryUsageSetting.setupMixed(32L * 1024 * 1024).setTempDir(scratch)
            PDDocument.load(source, password, memory).use { doc ->
                // Certified documents can forbid content changes even in a new revision.
                val permissions = doc.documentCatalog.cosObject.getCOSDictionary(COSName.PERMS)
                require(permissions?.getDictionaryObject(COSName.DOCMDP) == null) {
                    "This certified PDF forbids an OCR content update. Extract text instead."
                }
                val font = assets.open("flutter_assets/assets/fonts/NotoSansDevanagariOCR.ttf").use {
                    PDType0Font.load(doc, it, false)
                }
                val changed = HashSet<COSDictionary>()
                manifest.useLines { lines -> lines.forEach { raw ->
                    val item = JSONObject(raw)
                    val index = item.getInt("page")
                    require(index in 0 until doc.numberOfPages) { "Invalid OCR page index" }
                    val page = doc.getPage(index)
                    val crop = page.cropBox
                    val rotation = ((page.rotation % 360) + 360) % 360
                    val words = item.getJSONArray("words")
                    if (words.length() == 0) return@forEach
                    PDPageContentStream(doc, page, PDPageContentStream.AppendMode.APPEND, true, true).use { stream ->
                        // Map upright rendered coordinates back through page /Rotate and CropBox.
                        val view = when (rotation) {
                            0 -> Matrix(1f, 0f, 0f, 1f, crop.lowerLeftX, crop.lowerLeftY)
                            90 -> Matrix(0f, 1f, -1f, 0f, crop.upperRightX, crop.lowerLeftY)
                            180 -> Matrix(-1f, 0f, 0f, -1f, crop.upperRightX, crop.upperRightY)
                            270 -> Matrix(0f, -1f, 1f, 0f, crop.lowerLeftX, crop.upperRightY)
                            else -> throw IllegalArgumentException("Unsupported page rotation: $rotation")
                        }
                        stream.transform(view)
                        val viewHeight = if (rotation == 90 || rotation == 270) crop.width else crop.height
                        for (i in 0 until words.length()) {
                            val word = words.getJSONObject(i)
                            val text = word.getString("text")
                            val x = word.getDouble("x").toFloat()
                            val baseline = word.getDouble("y").toFloat()
                            val width = word.getDouble("width").toFloat()
                            val height = word.getDouble("height").toFloat()
                            require(width > 0 && height > 0 && width.isFinite() && height.isFinite()) { "Invalid OCR bounds" }
                            val size = max(1f, height * .82f)
                            val textWidth = font.getStringWidth(text) / 1000f * size
                            require(textWidth > 0) { "Font cannot encode OCR text" }
                            val angle = -word.optDouble("angle", 0.0) * PI / 180.0
                            require(x.isFinite() && baseline.isFinite() && angle.isFinite()) { "Invalid OCR coordinates" }
                            stream.beginText()
                            stream.setFont(font, size)
                            stream.setRenderingMode(RenderingMode.NEITHER)
                            stream.setHorizontalScaling(width / textWidth * 100f)
                            stream.setTextMatrix(Matrix(cos(angle).toFloat(), sin(angle).toFloat(),
                                -sin(angle).toFloat(), cos(angle).toFloat(), x, viewHeight - baseline))
                            stream.showText(text)
                            stream.endText()
                        }
                    }
                    changed.add(page.cosObject)
                    changed.add(page.resources.cosObject)
                } }
                FileOutputStream(output).use { doc.saveIncremental(it, changed) }
            }
            // Validate extraction one page at a time without retaining the entire OCR corpus.
            PDDocument.load(output, password, MemoryUsageSetting.setupMixed(32L * 1024 * 1024).setTempDir(scratch)).use { verified ->
                val stripper = PDFTextStripper()
                manifest.useLines { lines -> lines.forEach { raw ->
                    val item = JSONObject(raw)
                    val page = item.getInt("page") + 1
                    stripper.startPage = page
                    stripper.endPage = page
                    val extracted = stripper.getText(verified).replace(Regex("\\s+"), "")
                    val words = item.getJSONArray("words")
                    for (i in 0 until words.length()) {
                        val token = words.getJSONObject(i).getString("text").replace(Regex("\\s+"), "")
                        check(extracted.contains(token)) { "OCR text verification failed on page $page" }
                    }
                } }
            }
        } catch (error: Exception) {
            output.delete()
            throw error
        } finally { scratch.deleteRecursively() }
    }
}
