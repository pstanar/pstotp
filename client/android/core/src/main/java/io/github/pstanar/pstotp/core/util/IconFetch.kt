package io.github.pstanar.pstotp.core.util

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.ByteArrayOutputStream
import java.util.concurrent.TimeUnit

object IconFetch {
    private const val ICON_SIZE = 64

    private val client by lazy {
        OkHttpClient.Builder()
            .connectTimeout(5, TimeUnit.SECONDS)
            .readTimeout(5, TimeUnit.SECONDS)
            .build()
    }

    fun isUrl(value: String?): Boolean =
        value != null && (value.startsWith("http://") || value.startsWith("https://"))

    suspend fun downloadAsDataUrl(url: String): String? = withContext(Dispatchers.IO) {
        try {
            val request = Request.Builder().url(url).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@use null
                val bytes = response.body?.bytes() ?: return@use null
                val original = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return@use null

                val scale = maxOf(
                    ICON_SIZE.toFloat() / original.width,
                    ICON_SIZE.toFloat() / original.height,
                )
                val scaledW = (original.width * scale).toInt()
                val scaledH = (original.height * scale).toInt()
                val scaled = Bitmap.createScaledBitmap(original, scaledW, scaledH, true)
                val x = ((scaledW - ICON_SIZE) / 2).coerceAtLeast(0)
                val y = ((scaledH - ICON_SIZE) / 2).coerceAtLeast(0)
                val cropped = Bitmap.createBitmap(
                    scaled,
                    x,
                    y,
                    minOf(ICON_SIZE, scaledW - x),
                    minOf(ICON_SIZE, scaledH - y),
                )

                val baos = ByteArrayOutputStream()
                cropped.compress(Bitmap.CompressFormat.PNG, 100, baos)
                val base64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)

                original.recycle()
                if (scaled !== original) scaled.recycle()
                if (cropped !== scaled) cropped.recycle()

                "data:image/png;base64,$base64"
            }
        } catch (_: Exception) {
            null
        }
    }
}
