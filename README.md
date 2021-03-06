# TF2M-feedbackround-plugin
Feedback round plugin developed for TF2Maps by PigPig.

## Cvars:
`fb2_version`
        -READ ONLY. PLUGIN VERSION.
        
`fb2_time` <default 120>
        -How long should a FB round lasts by default (In Seconds)
        
`fb2_triggertime` <default 300>
        -If the maps timeleft is less than this number in seconds, trigger last round fb.
        
 `fb2_mapcontrol` <default 1> <1/0> 
        -Can maps control when fb last round occurs?
        
`fb2_forceswitch` <default 1> <1/0> 
        -If host uses !fbnextround/!fbroundnow, should we switch maps after that round is over?

## Commands:
        
### Admin commands

`sm_fbround`
        - Toggle if FB rounds are enabled. 1 and 0 are accepted.

`sm_fbnextround`
        - Toggle if the next round will be a FB round. 1 and 0 are accepted.

`sm_fbroundnow`
        - Start a fbround ASAP.

`sm_fbend`
        - Force end an FB round

`sm_fbtimer <add/set> <time to add>`
        - Adds/Sets time of a fb round once it has started.
        Time is in minutes

`sm_fbopenalldoors`
        - Find all "Func_door"s, unlocks and opens them.

### Normal commands
`sm_fbtellents`
        - Returns the edict count to the player.

`fb_spawn(s)`
        - During a feedback round, the player can teleport to all unique spawn names.

`sm_fbrh`
        - Prints helpful commands to the caller.

`sm_fbmedic`
        -Prints the medic count on both teams

`sm_fbdrawline`
        -Prints the distance between the clients view and the wall they are looking at.

`sm_walkspeed <speed>`
        - Sets your walk speed during a FB Round.
        
        
### Entities 
###### These are case sensitive

`(info_target) TF2M_ForceLastRoundFeedback`
        - Maps with this entity will force their last round to be a FB round

`(logic_relay) TF2M_FeedbackRoundRelay`
        - Triggered at the beginning of FB rounds
