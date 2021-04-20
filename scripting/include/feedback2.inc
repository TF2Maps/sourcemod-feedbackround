native FB2_IsFbRoundActive();
/**
 * Is feedback next round triggered
 *
 * @return		true: Next Round is a test round
 *				false: Next round is not a test round
 */
native FB2_ForceNextRoundTest();
/**
 * Is Feedback mode set to on end map force fb round.
 *
 * @return		true: Last rounds will be FB Rounds
 *				false: Last rounds will NOT be FB Rounds
 */
native FB2_EndMapFeedbackModeActive();
/**
 * Stop what you are doing, force a FB round to start.
 *
 * @return		Returns 1 on pass, -1 on failure.
 */
native FB2_ForceCancelRound_StartFBRound();
