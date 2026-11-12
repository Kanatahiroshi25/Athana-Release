package com.athana.lossless

import android.content.Context
import android.os.Build
import android.util.Log
import java.util.concurrent.atomic.AtomicInteger

/**
 * Switches and status for Athana's own audio code (the FLAC decoder and the audio output). The switches are read once,
 * when the player is created, so a change takes effect the next time Athana is opened.
 */
object AthanaEngine {
    private const val FILE = "athana_native"
    private const val KEY = "ownFlac"
    private const val KEY_OUT = "ownOut"
    private const val KEY_BP = "bitPerfect"
    private const val KEY_GUARD = "guardTripped"

    /** How many of Athana's own decoders are running right now (0 or 1 while a FLAC song plays). */
    val active = AtomicInteger(0)

    /** What Athana's own audio output is delivering right now, for example "24-bit". Empty when the standard output is used. */
    @Volatile var outDesc: String = ""

    /** What the switches were when the player started (they are only read then), and why a part is not used for the current song. */
    @Volatile var startedFlac = false
    @Volatile var startedOut = false
    @Volatile var flacNote = ""
    @Volatile var outNote = ""
    @Volatile var bpNote = ""

    /** True while Android's bit-perfect mixer is in use for the current song (the sound reaches a USB DAC with no mixing or resampling). */
    @Volatile var bitPerfect: Boolean = false

    /**
     * The safety net. When Athana's own code keeps failing (three errors in one session, or a crash inside it), it switches
     * itself off for good and the standard Android code takes over, so music never stops working because of it.
     * [tripped] takes effect at once; the saved switches stay off until the person turns them on again.
     */
    @Volatile var tripped = false
    @Volatile private var errors = 0

    fun trip(ctx: Context, why: String) {
        tripped = true
        Log.w("Athana", "Own audio code switched off automatically: $why")
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY, false).putBoolean(KEY_OUT, false).putBoolean(KEY_BP, false).putBoolean(KEY_GUARD, true).commit()
    }

    /** One error that came from Athana's own code. A single bad file is not enough; the third one in a session switches it off. */
    fun failure(ctx: Context, why: String) {
        errors++
        Log.w("Athana", "Own audio code error $errors: $why")
        if (errors >= 3 && !tripped) trip(ctx, why)
    }

    fun guardTripped(ctx: Context): Boolean = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_GUARD, false)

    fun clearGuard(ctx: Context) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_GUARD, false).apply()
    }

    // Both are on from the start (the output only on Android 12 and later, where 24-bit goes to the phone as it is).
    fun enabled(ctx: Context): Boolean = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY, true)

    fun setEnabled(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY, on).apply()
    }

    fun bitPerfectEnabled(ctx: Context): Boolean = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_BP, false)

    fun setBitPerfectEnabled(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_BP, on).apply()
    }

    fun outEnabled(ctx: Context): Boolean = ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).getBoolean(KEY_OUT, Build.VERSION.SDK_INT >= 31)

    fun setOutEnabled(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(FILE, Context.MODE_PRIVATE).edit().putBoolean(KEY_OUT, on).apply()
    }
}
