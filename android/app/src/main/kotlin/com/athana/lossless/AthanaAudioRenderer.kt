package com.athana.lossless

import android.os.Handler
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.decoder.CryptoConfig
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DecoderAudioRenderer

/**
 * The part of ExoPlayer that turns FLAC into sound, using Athana's own decoder. When it says a song is not for it
 * (not FLAC, more than 24 bits, no stream information), ExoPlayer's normal renderer plays the song instead.
 */
@OptIn(UnstableApi::class)
class AthanaAudioRenderer(eventHandler: Handler?, eventListener: AudioRendererEventListener?, audioSink: AudioSink) :
    DecoderAudioRenderer<AthanaFlacDecoder>(eventHandler, eventListener, audioSink) {

    override fun getName(): String = "AthanaAudioRenderer"

    private fun infoOf(format: Format): AthanaFlac.Info? {
        val init = format.initializationData
        if (init.isEmpty()) return null
        return AthanaFlac.parseStreamInfo(init[0])
    }

    private fun encodingOf(info: AthanaFlac.Info): Int = when (info.outBytes()) {
        2 -> C.ENCODING_PCM_16BIT
        3 -> C.ENCODING_PCM_24BIT
        else -> C.ENCODING_PCM_32BIT
    }

    override fun supportsFormatInternal(format: Format): Int {
        if (AthanaEngine.tripped) {
            AthanaEngine.flacNote = "it was switched off automatically after repeated errors"
            return C.FORMAT_UNSUPPORTED_TYPE
        }
        if (format.sampleMimeType != MimeTypes.AUDIO_FLAC) {
            AthanaEngine.flacNote = "this song is not a FLAC file"
            return C.FORMAT_UNSUPPORTED_TYPE
        }
        if (format.cryptoType != C.CRYPTO_TYPE_NONE) return C.FORMAT_UNSUPPORTED_DRM
        val info = infoOf(format)
        if (info == null) {
            AthanaEngine.flacNote = "the file gave no stream information"
            Log.i("Athana", "Own FLAC decoder: not used, the file gave no stream information (initializationData has " + format.initializationData.size + " items)")
            return C.FORMAT_UNSUPPORTED_SUBTYPE
        }
        if (info.bitsPerSample > 24 || info.channels > 8) {
            AthanaEngine.flacNote = "it has " + info.bitsPerSample + " bits and " + info.channels + " channels, more than the decoder takes"
            Log.i("Athana", "Own FLAC decoder: not used, " + info.bitsPerSample + " bit and " + info.channels + " channels is outside what it takes")
            return C.FORMAT_UNSUPPORTED_SUBTYPE
        }
        if (!sinkSupportsFormat(Util.getPcmFormat(encodingOf(info), info.channels, info.sampleRate))) {
            AthanaEngine.flacNote = "the audio output does not accept " + info.bitsPerSample + " bit at " + info.sampleRate + " Hz"
            Log.i("Athana", "Own FLAC decoder: not used, the audio output does not accept " + info.bitsPerSample + " bit PCM at " + info.sampleRate + " Hz")
            return C.FORMAT_UNSUPPORTED_SUBTYPE
        }
        AthanaEngine.flacNote = ""
        Log.i("Athana", "Own FLAC decoder: offered for " + info.bitsPerSample + " bit, " + info.channels + " ch, " + info.sampleRate + " Hz")
        return C.FORMAT_HANDLED
    }

    override fun createDecoder(format: Format, cryptoConfig: CryptoConfig?): AthanaFlacDecoder =
        AthanaFlacDecoder(infoOf(format) ?: throw androidx.media3.decoder.DecoderException("No FLAC stream information"))

    override fun getOutputFormat(decoder: AthanaFlacDecoder): Format =
        Util.getPcmFormat(encodingOf(decoder.info), decoder.info.channels, decoder.info.sampleRate)
}
