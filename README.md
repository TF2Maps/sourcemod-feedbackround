# TF2M-feedbackround-plugin
Feedback round plugin developed for TF2Maps by PigPig.

## Commands:

### Admin commands

`sm_fbround`
        - Toggle if FB rounds are enabled. 1 and 0 are accepted.

`sm_fbnextround`
        - Toggle if the next round will be a FB round. 1 and 0 are accepted.

`sm_fbround_forceend`
        - Force end an FB round

`sm_fbtimer <add/set> <time to add>`
        - Adds/Sets time of a fb round once it has started.
        Time is in minutes

`sm_fbopenalldoors`
        - Find all "Func_door"s, unlocks and opens them.

### Normie commands
`sm_fbtellents`
        - Returns the edict count to the player.

`fb_spawn(s)`
        - During a feedback round, the player can teleport to all unique spawn names.
