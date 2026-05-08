package io.github.pstanar.pstotp.ui.components

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/**
 * QR code scanner using CameraX + ML Kit.
 * Shows a camera preview and calls onResult when a QR code containing
 * an otpauth:// URI is detected.
 */
@Composable
fun QrScanner(
    onResult: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var hasCameraPermission by remember {
        mutableStateOf(
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.CAMERA
            ) == PackageManager.PERMISSION_GRANTED
        )
    }
    // AtomicBoolean (not Compose state) so the analyzer thread and
    // ML Kit's main-thread success listener observe writes through
    // the same memory-ordered cell. compareAndSet on first match
    // also guarantees onResult fires at most once even when frames
    // F1 and F2 are both in flight when F1's match lands.
    val detected = remember { AtomicBoolean(false) }

    val permissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        hasCameraPermission = granted
    }

    LaunchedEffect(Unit) {
        if (!hasCameraPermission) {
            permissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    if (!hasCameraPermission) {
        Box(
            modifier = modifier
                .fillMaxWidth()
                .height(300.dp),
            contentAlignment = Alignment.Center,
        ) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Camera permission required", style = MaterialTheme.typography.bodyMedium)
                Spacer(modifier = Modifier.height(8.dp))
                Button(onClick = { permissionLauncher.launch(Manifest.permission.CAMERA) }) {
                    Text("Grant Permission")
                }
            }
        }
        return
    }

    // Hoist the disposable resources out of the factory lambda so
    // DisposableEffect can release them when the AndroidView leaves
    // composition (e.g. user switches tabs in AddAccountScreen).
    //
    // Race-resistance: the analyzer runs on the executor thread, the
    // success listener runs on main, and the cameraProviderFuture
    // listener fires whenever the future resolves. Any of those can
    // fire AFTER dispose. `disposed` is the single source of truth
    // every async path checks before doing anything that could touch
    // a torn-down resource (camera bind, scanner.process, onResult).
    val cameraProviderFuture = remember { ProcessCameraProvider.getInstance(context) }
    val executor = remember { Executors.newSingleThreadExecutor() }
    val scanner = remember { BarcodeScanning.getClient() }
    val disposed = remember { AtomicBoolean(false) }
    // Held so dispose can call clearAnalyzer() — created inside the
    // future's listener, so we can't capture it directly in the effect.
    val imageAnalysisRef = remember { AtomicReference<ImageAnalysis?>() }

    DisposableEffect(Unit) {
        onDispose {
            disposed.set(true)
            // clearAnalyzer first: tells CameraX to stop dispatching
            // frames to our executor. New analyzer invocations stop
            // here. In-flight ones still need the disposed-check guard
            // inside the analyzer body.
            runCatching { imageAnalysisRef.get()?.clearAnalyzer() }
            runCatching {
                // `isDone` guards against the case where the future
                // hadn't resolved yet (camera was never bound, so
                // there's nothing to unbind).
                if (cameraProviderFuture.isDone) cameraProviderFuture.get().unbindAll()
            }
            runCatching { scanner.close() }
            runCatching { executor.shutdown() }
        }
    }

    AndroidView(
        modifier = modifier.clipToBounds(),
        factory = { ctx ->
            val previewView = PreviewView(ctx).apply {
                scaleType = PreviewView.ScaleType.FILL_CENTER
                layoutParams = android.view.ViewGroup.LayoutParams(
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                    android.view.ViewGroup.LayoutParams.MATCH_PARENT,
                )
            }

            cameraProviderFuture.addListener({
                // Listener may fire AFTER unmount if the future
                // resolves late. Don't bind to a lifecycle that's gone.
                if (disposed.get()) return@addListener
                val cameraProvider = cameraProviderFuture.get()

                val preview = Preview.Builder().build().also {
                    it.surfaceProvider = previewView.surfaceProvider
                }

                val imageAnalysis = ImageAnalysis.Builder()
                    .setResolutionSelector(
                        ResolutionSelector.Builder()
                            .setResolutionStrategy(
                                ResolutionStrategy(
                                    android.util.Size(1280, 720),
                                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER,
                                )
                            )
                            .build()
                    )
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()

                imageAnalysisRef.set(imageAnalysis)

                imageAnalysis.setAnalyzer(executor) { imageProxy ->
                    @androidx.camera.core.ExperimentalGetImage
                    val mediaImage = imageProxy.image
                    if (disposed.get() || mediaImage == null || detected.get()) {
                        imageProxy.close()
                        return@setAnalyzer
                    }
                    val inputImage = InputImage.fromMediaImage(
                        mediaImage, imageProxy.imageInfo.rotationDegrees
                    )
                    // scanner.process can throw if the scanner has been
                    // closed by a dispose that landed between the
                    // disposed-check above and this call. runCatching
                    // absorbs that; the onFailure path closes the
                    // imageProxy so we don't leak frames.
                    runCatching {
                        scanner.process(inputImage)
                            .addOnSuccessListener { barcodes ->
                                if (disposed.get()) return@addOnSuccessListener
                                for (barcode in barcodes) {
                                    if (barcode.valueType == Barcode.TYPE_TEXT ||
                                        barcode.valueType == Barcode.TYPE_URL
                                    ) {
                                        val value = barcode.rawValue ?: continue
                                        if (value.startsWith("otpauth://")) {
                                            // First match wins — second
                                            // racing frame sees detected
                                            // already true and skips
                                            // onResult.
                                            if (detected.compareAndSet(false, true)) {
                                                onResult(value)
                                            }
                                            return@addOnSuccessListener
                                        }
                                    }
                                }
                            }
                            .addOnCompleteListener { imageProxy.close() }
                    }.onFailure { imageProxy.close() }
                }

                try {
                    cameraProvider.unbindAll()
                    cameraProvider.bindToLifecycle(
                        lifecycleOwner,
                        CameraSelector.DEFAULT_BACK_CAMERA,
                        preview,
                        imageAnalysis,
                    )
                } catch (_: Exception) {
                    // Camera binding failed
                }
            }, ContextCompat.getMainExecutor(ctx))

            previewView
        },
    )
}
