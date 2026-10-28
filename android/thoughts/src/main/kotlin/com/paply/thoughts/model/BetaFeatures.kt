package com.paply.thoughts.model

/** Shared preference semantics only; Android owns its preference/UI adapters. */
object BetaFeatures {
    const val thoughtsKey = "paply.beta.thoughts"
    const val thoughtsOffArgument = "-PaplyBetaOff"
    const val thoughtsOffMessage =
        "Gedanken sind Beta – in den Einstellungen unter Beta einschalten."

    fun thoughtsEnabled(defaults: Map<String, Any?>?) =
        defaults?.get(thoughtsKey) as? Boolean ?: true

    fun thoughtsAtLaunch(
        defaults: Map<String, Any?>?,
        arguments: List<String>,
        debug: Boolean = false,
    ) = if (debug && thoughtsOffArgument in arguments) false else thoughtsEnabled(defaults)
}

class ThoughtStartGate {
    @Volatile
    var aborted = false
        private set

    fun begin() {
        aborted = false
    }

    fun abort() {
        aborted = true
    }

    fun allows(betaOn: Boolean) = betaOn && !aborted
}

/**
 * Wire identity shared with Part B's TaskReminderPlan. No notification scheduling in the JVM core.
 */
object TaskReminderID {
    fun identifier(thoughtID: String, taskID: String) = "task/$thoughtID/$taskID"
}
