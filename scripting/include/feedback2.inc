/** Double-include prevention */
#if defined _FB2_included
  #endinput
#endif
#define _FB2_included

//TrueFalse states
enum
{
    BoolValue_Null = -1,
    BoolValue_False,
    BoolValue_True,
}

#define FBFLAG_DEFAULTVALUE  			0
#define FBFLAG_FORCELASTROUND           (1<<1)      //Used when a flag is set for last round.

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
/**
 * Force last round fb round.
 *
 * @return		Returns true or false of what you have set.
 */
native FB2_ForceFbRoundLastRound(bool StartFbRound);

