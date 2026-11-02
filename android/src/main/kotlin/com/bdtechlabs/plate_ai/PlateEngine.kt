package com.bdtechlabs.plate_ai

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterAssets
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.FloatBuffer
import java.util.concurrent.Executors
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.min

/**
 * On-phone plate reading (detector + reader, ONNX Runtime) on a background thread.
 *
 * Dart sends a camera frame's brightness (Y) plane; this crops the centre square, runs the detector,
 * crops the best plate, runs the reader and sends back only the reader's picks and probabilities.
 */
class PlateEngine(private val context: Context, private val flutterAssets: FlutterAssets) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val env = OrtEnvironment.getEnvironment()
    private var det: OrtSession? = null
    private var reader: OrtSession? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> worker.execute {
                try {
                    if (det == null) det = session("assets/models/plate_det.onnx")
                    if (reader == null) reader = session("assets/models/plate_reader.onnx")
                    main.post { result.success(true) }
                } catch (e: Exception) {
                    main.post { result.error("LOAD", e.toString(), null) }
                }
            }
            "read" -> {
                val bytes = call.argument<ByteArray>("bytes")!!
                val w = call.argument<Int>("width")!!
                val h = call.argument<Int>("height")!!
                val stride = call.argument<Int>("stride")!!
                val rot = call.argument<Int>("rotation")!!
                val detSize = call.argument<Int>("detSize")!!
                val rh = call.argument<Int>("readerH")!!
                val rw = call.argument<Int>("readerW")!!
                val heads = call.argument<List<Int>>("heads")!!
                worker.execute {
                    try {
                        check(det != null && reader != null) { "Call load() before read()" }
                        val out = read(Frame(bytes, w, h, stride, rot), detSize, rh, rw, heads)
                        main.post { result.success(out) }
                    } catch (e: Exception) { // includes a frame smaller than width/height/stride say
                        main.post { result.error("READ", e.toString(), null) }
                    }
                }
            }
            "close" -> worker.execute {
                closeSessions()
                main.post { result.success(true) }
            }
            else -> result.notImplemented()
        }
    }

    /** Frees the models; the engine can be loaded again afterwards. Runs on the worker, after any read. */
    private fun closeSessions() {
        det?.close()
        reader?.close()
        det = null
        reader = null
    }

    /** The Flutter engine is going away: free the models, then end the worker thread. */
    fun shutdown() {
        worker.execute { closeSessions() }
        worker.shutdown()
    }

    private fun session(asset: String): OrtSession {
        val key = flutterAssets.getAssetFilePathByName(asset, "plate_ai")
        val model = context.assets.open(key).use { it.readBytes() }
        val opts = OrtSession.SessionOptions().apply {
            setOptimizationLevel(OrtSession.SessionOptions.OptLevel.ALL_OPT)
            setIntraOpNumThreads(4) // the 4 big cores; more threads spill onto the slow ones
            setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
        }
        return env.createSession(model, opts)
    }

    /** Brightness plane with an upright view (rotation = sensor orientation, clockwise). */
    private class Frame(val b: ByteArray, val w: Int, val h: Int, val stride: Int, val rot: Int) {
        val uw = if (rot % 180 == 0) w else h
        val uh = if (rot % 180 == 0) h else w
        fun at(u0: Int, v0: Int): Int {
            val u = u0.coerceIn(0, uw - 1)
            val v = v0.coerceIn(0, uh - 1)
            val (x, y) = when (rot) {
                90 -> v to h - 1 - u
                180 -> w - 1 - u to h - 1 - v
                270 -> w - 1 - v to u
                else -> u to v
            }
            return b[y * stride + x].toInt() and 0xff
        }
    }

    private fun read(f: Frame, s: Int, rh: Int, rw: Int, heads: List<Int>): Map<String, Any>? {
        val t0 = System.nanoTime()
        // detector input: centre square, grey in all 3 channels, 0..1
        val side = min(f.uw, f.uh)
        val left = (f.uw - side) / 2
        val top = (f.uh - side) / 2
        val step = side.toFloat() / s
        val detIn = FloatArray(3 * s * s)
        for (y in 0 until s) {
            val v = top + floor((y + 0.5f) * step).toInt()
            for (x in 0 until s) {
                val g = f.at(left + floor((x + 0.5f) * step).toInt(), v) / 255f
                val i = y * s + x
                detIn[i] = g; detIn[s * s + i] = g; detIn[2 * s * s + i] = g
            }
        }
        val t1 = System.nanoTime()
        val p = OnnxTensor.createTensor(env, FloatBuffer.wrap(detIn), longArrayOf(1, 3, s.toLong(), s.toLong())).use { t ->
            det!!.run(mapOf(det!!.inputNames.first() to t)).use { r ->
                (r[0] as OnnxTensor).floatBuffer.let { buf -> FloatArray(buf.remaining()).also { buf.get(it) } }
            }
        }
        val t2 = System.nanoTime()
        // YOLO output (1, 5, N): best score
        val n = p.size / 5
        var best = -1
        var bestScore = 0.4f
        for (i in 0 until n) if (p[4 * n + i] > bestScore) { bestScore = p[4 * n + i]; best = i }
        if (best < 0) return mapOf("ms" to listOf(ms(t0, t1), ms(t1, t2), 0.0))
        val sc = side.toFloat() / s
        val cx = p[best] * sc + left
        val cy = p[n + best] * sc + top
        val bw = p[2 * n + best] * sc
        val bh = p[3 * n + best] * sc
        val box = floatArrayOf(cx - bw / 2, cy - bh / 2, cx + bw / 2, cy + bh / 2)

        // reader input: plate + 4% margin, bilinear, -1..1
        val mx = 0.04f * bw
        val my = 0.04f * bh
        val x0 = box[0] - mx
        val y0 = box[1] - my
        val sx = (bw + 2 * mx) / rw
        val sy = (bh + 2 * my) / rh
        val rIn = FloatArray(rh * rw)
        for (y in 0 until rh) {
            val fy = y0 + (y + 0.5f) * sy - 0.5f
            val v = floor(fy).toInt()
            val ty = fy - v
            for (x in 0 until rw) {
                val fx = x0 + (x + 0.5f) * sx - 0.5f
                val u = floor(fx).toInt()
                val tx = fx - u
                val g = (f.at(u, v) * (1 - tx) + f.at(u + 1, v) * tx) * (1 - ty) +
                    (f.at(u, v + 1) * (1 - tx) + f.at(u + 1, v + 1) * tx) * ty
                rIn[y * rw + x] = (g / 255f - 0.5f) / 0.5f
            }
        }
        val z = OnnxTensor.createTensor(env, FloatBuffer.wrap(rIn), longArrayOf(1, 1, rh.toLong(), rw.toLong())).use { t ->
            reader!!.run(mapOf("image" to t)).use { r ->
                (r[0] as OnnxTensor).floatBuffer.let { buf -> FloatArray(buf.remaining()).also { buf.get(it) } }
            }
        }
        val t3 = System.nanoTime()
        // per-part argmax + softmax probability
        val picks = ArrayList<Int>()
        val confs = ArrayList<Double>()
        var i = 0
        for (k in heads) {
            var arg = 0
            for (j in 1 until k) if (z[i + j] > z[i + arg]) arg = j
            var sum = 0.0
            for (j in 0 until k) sum += exp((z[i + j] - z[i + arg]).toDouble())
            picks.add(arg); confs.add(1 / sum)
            i += k
        }
        return mapOf(
            "picks" to picks, "confs" to confs,
            "box" to listOf(box[0] / f.uw, box[1] / f.uh, box[2] / f.uw, box[3] / f.uh).map { it.toDouble() },
            "ms" to listOf(ms(t0, t1), ms(t1, t2), ms(t2, t3)),
        )
    }

    private fun ms(a: Long, b: Long) = (b - a) / 1e6
}
