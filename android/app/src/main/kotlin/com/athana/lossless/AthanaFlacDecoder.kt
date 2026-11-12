package com.athana.lossless

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.decoder.DecoderException
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.decoder.SimpleDecoder
import androidx.media3.decoder.SimpleDecoderOutputBuffer
import java.nio.ByteBuffer

// The decoder fills these arrays with its own buffers when it starts, so what is put in here is only a placeholder.
private fun newInputs(): Array<DecoderInputBuffer> = Array(8) { DecoderInputBuffer(DecoderInputBuffer.BUFFER_REPLACEMENT_MODE_NORMAL) }

@OptIn(UnstableApi::class)
private fun newOutputs(): Array<SimpleDecoderOutputBuffer> = Array(8) { SimpleDecoderOutputBuffer { } }

/**
 * Plays FLAC with Athana's own decoder ([AthanaFlac]) instead of Android's built-in one.
 * ExoPlayer still finds the frames and handles the queue, seeking and buffering; every frame it hands over is
 * turned into PCM here, sample for sample.
 */
@OptIn(UnstableApi::class)
class AthanaFlacDecoder(val info: AthanaFlac.Info) :
    SimpleDecoder<DecoderInputBuffer, SimpleDecoderOutputBuffer, DecoderException>(
        newInputs(),
        newOutputs()
    ) {

    private val flac = AthanaFlac(info.bitsPerSample, info.sampleRate)
    private val outBytes = info.outBytes()
    private var frame = ByteArray(32 * 1024)
    // room for the biggest possible frame: 65535 samples of every channel
    private val scratch: ByteBuffer = ByteBuffer.allocate(65535 * info.channels * outBytes)
    private var failedInARow = 0

    init {
        setInitialInputBufferSize(maxOf(info.maxBlock * info.channels * outBytes, 32 * 1024))
        AthanaEngine.active.incrementAndGet()
        Log.i("Athana", "Own FLAC decoder started: " + info.bitsPerSample + " bit, " + info.channels + " ch, " + info.sampleRate + " Hz")
    }

    override fun getName(): String = "AthanaFlacDecoder"

    override fun createInputBuffer(): DecoderInputBuffer = DecoderInputBuffer(DecoderInputBuffer.BUFFER_REPLACEMENT_MODE_NORMAL)

    override fun createOutputBuffer(): SimpleDecoderOutputBuffer = SimpleDecoderOutputBuffer { buffer -> releaseOutputBuffer(buffer) }

    override fun createUnexpectedDecodeException(error: Throwable): DecoderException = DecoderException("Unexpected FLAC decode error", error)

    override fun decode(inputBuffer: DecoderInputBuffer, outputBuffer: SimpleDecoderOutputBuffer, reset: Boolean): DecoderException? {
        val data = inputBuffer.data ?: return DecoderException("The FLAC frame has no data")
        val n = data.remaining()
        if (frame.size < n) frame = ByteArray(n * 2)
        data.get(frame, 0, n)
        scratch.clear()
        var bytes = 0
        try {
            bytes = flac.decodeFrame(frame, 0, n, scratch, outBytes)
            if (flac.lastChannels != info.channels) throw java.io.IOException("channel count changed")
            failedInARow = 0
        } catch (e: Throwable) {
            // A damaged frame becomes a short silence, so one bad spot does not stop the song. Many in a row is a real fault.
            Log.e("Athana", "FLAC frame could not be decoded", e)
            if (++failedInARow > 20) return DecoderException("Athana's FLAC decoder could not read this file", e)
            scratch.clear()
            val silence = (if (info.minBlock > 0) info.minBlock else 4096) * info.channels * outBytes
            bytes = minOf(silence, scratch.capacity())
            java.util.Arrays.fill(scratch.array(), 0, bytes, 0)
            scratch.position(bytes)
        }
        scratch.flip()
        val out = outputBuffer.init(inputBuffer.timeUs, bytes)
        out.put(scratch)
        out.flip()
        return null
    }

    override fun release() {
        super.release()
        AthanaEngine.active.decrementAndGet()
    }
}
