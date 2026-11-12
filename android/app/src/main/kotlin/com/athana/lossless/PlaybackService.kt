package com.athana.lossless

import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.view.KeyEvent
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Keeps playback alive in the background and shows the media notification / lock-screen controls.
 * Button presses are sent to the Athana page (so its queue, shuffle and repeat rules decide what happens next).
 */
class PlaybackService : MediaSessionService() {
    private var session: MediaSession? = null
    private val ui = Handler(Looper.getMainLooper())
    private var presses = 0
    private val decide = Runnable {
        val n = presses
        presses = 0
        val acts = PlayerHolder.headset
        val act = acts[(n.coerceIn(1, 3)) - 1]
        doAction(act)
    }

    /** One of: playpause, next, prev, skipback, skipfwd, off. */
    private fun doAction(act: String) {
        val raw = PlayerHolder.get(this)
        val r = PlayerHolder.remote
        when (act) {
            "playpause" -> if (r != null) r("toggle") else raw.playWhenReady = !raw.playWhenReady
            "next" -> r?.invoke("next")
            "prev" -> r?.invoke("prev")
            "skipback" -> r?.invoke("skipback")
            "skipfwd" -> r?.invoke("skipfwd")
        }
    }

    override fun onCreate() {
        super.onCreate()
        val raw = PlayerHolder.get(this)
        val facade = object : ForwardingPlayer(raw) {
            override fun getAvailableCommands(): Player.Commands =
                super.getAvailableCommands().buildUpon()
                    .add(Player.COMMAND_SEEK_TO_NEXT)
                    .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                    .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                    .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                    .build()

            override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)

            // Always show the title, artist and cover that Athana sent, never tags that ExoPlayer read from the file.
            override fun getMediaMetadata(): MediaMetadata = currentMediaItem?.mediaMetadata ?: super.getMediaMetadata()

            private fun forward(name: String, fallback: () -> Unit) {
                val r = PlayerHolder.remote
                if (r != null) r(name) else fallback()
            }

            override fun play() = forward("play") { super.play() }
            override fun pause() = forward("pause") { super.pause() }
            override fun seekToNext() = forward("next") { }
            override fun seekToNextMediaItem() = forward("next") { }
            override fun seekToPrevious() = forward("prev") { }
            override fun seekToPreviousMediaItem() = forward("prev") { }
            override fun seekTo(positionMs: Long) = forward("seek:$positionMs") { super.seekTo(positionMs) }
            override fun seekTo(mediaItemIndex: Int, positionMs: Long) =
                forward("seek:$positionMs") { super.seekTo(mediaItemIndex, positionMs) }
        }
        session = MediaSession.Builder(this, facade)
            .setCallback(object : MediaSession.Callback {
                // Wired headphones and in-ear monitors send one button. Count quick presses so
                // 1, 2 and 3 presses can do what the listener chose.
                @Suppress("DEPRECATION")
                override fun onMediaButtonEvent(session: MediaSession, controllerInfo: MediaSession.ControllerInfo, intent: Intent): Boolean {
                    val ev = intent.getParcelableExtra<KeyEvent>(Intent.EXTRA_KEY_EVENT) ?: return false
                    if (ev.keyCode != KeyEvent.KEYCODE_HEADSETHOOK && ev.keyCode != KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE) return false
                    if (ev.action == KeyEvent.ACTION_DOWN && ev.repeatCount == 0) {
                        presses++
                        ui.removeCallbacks(decide)
                        if (presses >= 3) ui.post(decide) else ui.postDelayed(decide, 380)
                    }
                    return true
                }
            })
            .build()
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        // The app was swiped away: the page that drives the queue is gone, so stop instead of playing one last song.
        PlayerHolder.get(this).let { it.pause(); it.stop(); it.clearMediaItems() }
        // Release the session first, then the player: the next time Athana opens, a fresh player reads the engine switches again.
        session?.run { release() }
        session = null
        PlayerHolder.release()
        stopSelf()
    }

    override fun onDestroy() {
        ui.removeCallbacks(decide)
        session?.run { release() }
        session = null
        super.onDestroy()
    }
}
