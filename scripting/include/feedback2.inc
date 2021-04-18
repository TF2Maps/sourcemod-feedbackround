/**
 * If we want to pause RTV
 *
 * @param 		If we should pause or not.
 * @return		Returns nothing    
 */
native RTVNative_PauseRTV(bool:startPause);
/**
 * If we want to reset the RTV count
 *
 * @return		Returns nothing. 
 */
native RTVNative_ResetRTV();
/**
 * Is feedback round active?
 *
 * @return		true: Active 
 *				false: Not Active
 */
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
