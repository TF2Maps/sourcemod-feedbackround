//#define DEBUG
/*
	TF2 Feedback plugin:
		Commands:
			fb_round_enable : Enable or disable FB round automation [TRUE/FALSE][1/0][YES/NO]
			sm_fb_nextround : Force FB round after this round [TRUE/FALSE][1/0][YES/NO]
			sm_fb_round_forceend : Enforce the death of an fb round. Automatically switch to the nextmap.
			sm_fb_time : 
					>add : add time in seconds
					>set : set time in seconds
		Cvars:
			fb2_timer : How long these rounds should be by default. (DEFAULT: 2 MINUTES)
			fb2_triggertime : How long till map end should we trigger last round fb round.
			fb2_mapcontrol : Can maps call FB rounds on last round?
			
			
			
	TODOs:
		-Look into why spawnpoints are not showing up in !fb_spawn
		
		-Fix 5CP midgame FB rounds running into timelimit ends.
		-Look into having FB rounds always in tournament mode.
		-----------------------------------------------
		//Over engineering: 
			Otherwise useless shit.
		-Add Drawline command 
			Return value to user of how long a sightline is			
			
		-Info_Targets mappers can place for spacific playtests
			Read these targets and run commands.
				ex: Force scramble after every round if an info_target is named "TF2M_FORCESCRAMBLE"
					This is just streamlining things, last priority.
		
		-----------------------------------------------
			
*/



#pragma semicolon 1

/* Defines */
#define PLUGIN_AUTHOR "PigPig"
#define PLUGIN_VERSION "0.0.15"


#include <sourcemod>
#include <morecolors>
#include <tf2_stocks>
#include <sdkhooks>
#include <clientprefs>

#define REQUIRE_PLUGIN
#include <feedback2>
#undef REQUIRE_PLUGIN

//#include <sdktools>
//#include <tf2>

//Sounds
#define SOUND_HINTSOUND "/ui/hint.wav"
#define SOUND_WARNSOUND "/ui/system_message_alert.wav"
#define SOUND_QUACK "ambient/bumper_car_quack1.wav"


#define WALKSPEED_MIN 200.0
#define WALKSPEED_MAX 512.0

#define BUILDING_SENTRY 2
#define BUILDING_DISPENSER 0
#define BUILDING_TELEPORTER 1

//#define EndRoundDraw


/*
	--------------------------------------------------------------------------------
	  _____       _ _   _       _ _          _   _             
	 |_   _|     (_) | (_)     | (_)        | | (_)            
	   | |  _ __  _| |_ _  __ _| |_ ______ _| |_ _  ___  _ __  
	   | | | '_ \| | __| |/ _` | | |_  / _` | __| |/ _ \| '_ \ 
	  _| |_| | | | | |_| | (_| | | |/ / (_| | |_| | (_) | | | |
	 |_____|_| |_|_|\__|_|\__,_|_|_/___\__,_|\__|_|\___/|_| |_|                                                                  
	--------------------------------------------------------------------------------
	Description: In the beginning God created the heaven and the earth.                
*/
public Plugin myinfo = 
{
	name = "Feedback 2.0",
	author = PLUGIN_AUTHOR,
	description = "",
	version = PLUGIN_VERSION,
	url = "None, Sorry."
};
public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
	/* Natives */
	//If in the future anyone else comes in to write a plugin that has to navigate around this one, these should help
	CreateNative("FB2_IsFbRoundActive", Native_IsFbRoundActive);
	CreateNative("FB2_ForceNextRoundTest", Native_ForceNextRoundTest);
	CreateNative("FB2_EndMapFeedbackModeActive", Native_EndMapFeedBackModeActive);
	CreateNative("FB2_ForceCancelRound_StartFBRound", Native_ForceCancelRoundStartFBRound);
	CreateNative("FB2_ForceFbRoundLastRound", Native_ForceFbRoundLastRound);	
	
	RegPluginLibrary("feedback2");
	return APLRes_Success;
}
static const String:SplashText[][] = {
	"TF2 REQUIRES 3D GLASSES TO PLAY",
	"Hopfully something actually changed...", 
	"Ugh... Again??", 
	"Déjà vu!",
	"Now with 15% less sugar, and 50% more salt."
};

//Bools
new bool:IsTestModeTriggered = false; //IS THE INGAME TESTMODE READY TO ACTIVATE NEXT ROUND?
new bool:IsTestModeActive = false;//When the next round starts.
new bool:ForceNextRoundTest = false; //Next win. Enter test mode, If enough time is left, play next round normally.
new bool:FeedbackModeActive = false;//After the last round has ended, if no time is left, enter test mode.
new bool:ForceFBRoundStarted = false;//Failsafe: Stop recalls from happening, incase sourcemod stuffs us.
new bool:ShowFeedbackRoundHud = false;
new EndOfRoundFlags = FBFLAG_DEFAULTVALUE;
new bool:IsMapLoaded = false;//Might come in use later on.

//HUD stuff
new Handle:feedbackHUD;
new Handle:fbTimer;

//Ints
int FeedbackTimer = -1; //This timer usually is -1, if not it is liekley a fb round. (Except fb rounds clock to -5)

/*			CVARS			*/
enum 
{
	FB_CVAR_ALLOTED_TIME,
	FB_CVAR_DOWNTIME_FORCEFB,
	FB_CVAR_DOWNTIME_FORCEFB_ARENA,
	FB_CVAR_ALLOWMAP_SETTINGS,
	Version
}
ConVar cvarList[Version + 1];

/* Forward spawn teleport arrays */
ArrayList SpawnPointNames;
ArrayList SpawnPointEntIDs;

TFCond AppliedUber = TFCond:51;

//-1 is default
int MapTimeStorage = -1;
int AlltalkBuffer = -1;

enum CollisionGroup
{
	COLLISION_GROUP_NONE  = 0,
	COLLISION_GROUP_DEBRIS,            // Collides with nothing but world and static stuff
	COLLISION_GROUP_DEBRIS_TRIGGER, // Same as debris, but hits triggers
	COLLISION_GROUP_INTERACTIVE_DEBRIS,    // Collides with everything except other interactive debris or debris
	COLLISION_GROUP_INTERACTIVE,    // Collides with everything except interactive debris or debris
	COLLISION_GROUP_PLAYER,
	COLLISION_GROUP_BREAKABLE_GLASS,
	COLLISION_GROUP_VEHICLE,
	COLLISION_GROUP_PLAYER_MOVEMENT,  // For HL2, same as Collision_Group_Player
										
	COLLISION_GROUP_NPC,            // Generic NPC group
	COLLISION_GROUP_IN_VEHICLE,        // for any entity inside a vehicle
	COLLISION_GROUP_WEAPON,            // for any weapons that need collision detection
	COLLISION_GROUP_VEHICLE_CLIP,    // vehicle clip brush to restrict vehicle movement
	COLLISION_GROUP_PROJECTILE,        // Projectiles!
	COLLISION_GROUP_DOOR_BLOCKER,    // Blocks entities not permitted to get near moving doors
	COLLISION_GROUP_PASSABLE_DOOR,    // Doors that the player shouldn't collide with
	COLLISION_GROUP_DISSOLVING,        // Things that are dissolving are in this group
	COLLISION_GROUP_PUSHAWAY,        // Nonsolid on client and server, pushaway in player code

	COLLISION_GROUP_NPC_ACTOR,        // Used so NPCs in scripts ignore the player.
}

/* Cookies */
new Handle:clFbRoundWalkSpeed = INVALID_HANDLE;
new Float:FbRoundWalkSpeed[MAXPLAYERS + 1] = 0.0;

public void OnPluginStart()
{
	//COMMENT OUT DEBUG AT THE TOP OF THE DOC TO AVOID THIS
	#if defined DEBUG
	PrintToServer("Feedback Debugmode");
	FeedbackModeActive = true;
	/* Inform the users. */
	CPrintToChatAll("{gold}[Feedback 2.0 Loaded]{default} ~ Version %s - %s", PLUGIN_VERSION, SplashText[GetRandomInt(0,sizeof(SplashText) - 1)]);//Starting plugin
	#endif
	PrintToServer("[Feedback 2.0 Loaded] ~ Version %s - %s", PLUGIN_VERSION, SplashText[GetRandomInt(0,sizeof(SplashText) - 1)]);
	
	//Round ends
	HookEvent("teamplay_round_win", Event_Round_End, EventHookMode_Pre);
	HookEvent("teamplay_round_stalemate", Event_Round_End, EventHookMode_Pre);
	HookEvent("arena_win_panel", Event_Round_End, EventHookMode_Pre);//Arena mode. (oh god...)
	
	HookEvent("teamplay_round_active", Event_Teamplay_RoundActive);//When we can walk
	
	//Round start
	HookEvent("teamplay_round_start", Event_Round_Start);
	//Death and respawning
	HookEvent("player_spawn", Event_Player_Spawn);
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	
	//OnBuild
	//TODO: Find a clean way to disable players collisions with buildings.
	//Buildings have "SolidToPlayer" input and "m_SolidToPlayers" propdata, but they dont respond at all.
	//HookEvent("player_builtobject", Event_Object_Built);
	

	
	//Create hud sync
	feedbackHUD = CreateHudSynchronizer();
	
	//Commands
	RegAdminCmd("sm_fbround", Command_FB_Round_Enabled, ADMFLAG_KICK, "Enable or disable FB rounds [TRUE/FALSE][1/0][YES/NO]");
	RegAdminCmd("sm_fbnextround", Command_Fb_Next_RoundToggle, ADMFLAG_KICK, "Force FB round after this round [TRUE/FALSE][1/0][YES/NO]");
	
	
	RegAdminCmd("sm_fbround_forceend", Command_Fb_Cancel_Round, ADMFLAG_KICK, "Enforce the death of an fb round");
	RegAdminCmd("sm_fbend", Command_Fb_Cancel_Round, ADMFLAG_KICK, "Enforce the death of an fb round");
	RegAdminCmd("sm_fbtimer", Command_Fb_AddTime, ADMFLAG_KICK, "<Add/Set> <Time in minutes> (ONLY CAN BE USED MID FB ROUND!!!)");
	
	
	RegAdminCmd("sm_fbopenalldoors", Command_Fb_OpenDoors, ADMFLAG_KICK, "Forces all doors to unlock and open.");
	RegConsoleCmd("sm_fbtellents", Command_ReturnEdicts,"Returns edict number.");
	RegConsoleCmd("sm_fbspawn", Menu_SpawnTest, "Jump to a spawn point on the map.");
	RegConsoleCmd("sm_fbspawns", Menu_SpawnTest, "Jump to a spawn point on the map.");
	RegConsoleCmd("sm_fbrh", Command_FBround_Help, "Tellme tellme.");
	RegConsoleCmd("sm_walkspeed", Command_walkspeed, "Change your walk speed during a fb round (HU)");
	
	#if defined DEBUG
	RegConsoleCmd("sm_fbquack", Command_FBQuack, "The characteristic harsh sound made by a duck");
	#endif
	
	cvarList[Version] = CreateConVar("fb2_version", PLUGIN_VERSION, "FB2 Version. DO NOT CHANGE THIS!!! READ ONLY!!!!", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_CHEAT);
	cvarList[FB_CVAR_ALLOTED_TIME] = CreateConVar("fb2_time", "120" , "How Long should the timer last? (In seconds)", FCVAR_NOTIFY, true, 30.0, true, 1200.0);//Min / Max (30 seconds / 20 minutes)
	cvarList[FB_CVAR_DOWNTIME_FORCEFB_ARENA] = CreateConVar("fb2_triggertime_arena", "60" , "How many seconds left should we trigger an expected map end FOR ARENA MODE", FCVAR_NOTIFY, true, 30.0, true, 1200.0);//Min / Max (30 seconds / 20 minutes)
	cvarList[FB_CVAR_DOWNTIME_FORCEFB] = CreateConVar("fb2_triggertime", "300" , "How many seconds left should we trigger an expected map end.", FCVAR_NOTIFY, true, 30.0, true, 1200.0);//Min / Max (30 seconds / 20 minutes)
	cvarList[FB_CVAR_ALLOWMAP_SETTINGS] = CreateConVar("fb2_mapcontrol", "1" , "How much control do we give maps over our plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);//false,true.
	
	//instantiate arrays
	SpawnPointNames = new ArrayList(512);
	SpawnPointEntIDs = new ArrayList(512);
	
	PopulateSpawnList();
	
	
	clFbRoundWalkSpeed = RegClientCookie("fb_PlayerWalkSpeed", "The players walk speed during fb rounds.", CookieAccess_Protected);
	
}
public OnConfigsExecuted()
{
	//Precache
	PrecacheSound(SOUND_WARNSOUND,true);
	PrecacheSound(SOUND_HINTSOUND,true);
	PrecacheSound(SOUND_QUACK,true);
	SetCVAR_SILENT("mp_tournament_allow_non_admin_restart", 0);//Just in case.
}
/*
	Natives.
*/
public Native_IsFbRoundActive(Handle:plugin, numParams)
{
    return IsTestModeActive;
}
public Native_ForceFbRoundLastRound(Handle:plugin, numParams)
{
	bool isFbRoundLastRound = GetNativeCell(1);
	if(isFbRoundLastRound)
		EndOfRoundFlags = EndOfRoundFlags | FBFLAG_FORCELASTROUND;//Set true
	else
		EndOfRoundFlags = EndOfRoundFlags &~ FBFLAG_FORCELASTROUND;//Set false
	
	return isFbRoundLastRound;
}
public Native_ForceNextRoundTest(Handle:plugin, numParams)
{
    return ForceNextRoundTest;
}
public Native_EndMapFeedBackModeActive(Handle:plugin, numParams)
{
	bool fbEndOfMap = FeedbackModeActive;
	if(!fbEndOfMap)//if false, check if map wants the round.
	{
		fbEndOfMap = GetMapForceFeedbackLastRound();
	}
	return fbEndOfMap;
}
public Native_ForceCancelRoundStartFBRound(Handle:plugin, numParams)
{
	ForceStartFBRound();
	return 1;
}
/*
	Use: Stop everything and force a FB round.
*/
void ForceStartFBRound()
{
	if(IsFBRoundBlocked())
		return;

	if(!ForceFBRoundStarted)//if not started.
	{
		PauseRTV(true);//Pause RTV.
		ResetRTV();//Reset rtv,
		//Allert players.
		CPrintToChatAll("{gold}[Feedback]{default} ~ Round canceled! Feedback round started.");
		ForceNextRoundTest = true;//Enable next round FB.
		ServerCommand("mp_restartgame 1");
		ForceFBRoundStarted = true;
	}
}
bool IsFBRoundBlocked()
{
	/*
	if(IsArenaMode())
		return true;
		*/
		
	return false;
}
bool IsArenaMode()
{
	bool tfArenaFound = false;
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_logic_arena")) != -1)
	{
		tfArenaFound = true;
		break;
	}
	return tfArenaFound;
}
void PauseRTV(bool isPaused)
{
	if(isPaused)
	{
		ServerCommand("sm_pausertv true");
	}
	else
	{
		ServerCommand("sm_pausertv false");
	}
}
void ResetRTV()
{
	ServerCommand("sm_resetrtv");
}
/*
	Use: On player spawn
*/
public Action:Event_Player_Spawn(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(!IsTestModeActive)//If not in test mode, do nothing.
		return;
		
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(IsValidClient(client))
	{
		SetPlayerFBMode(client,true);
	}	
}
/*
	Use: Switch a players state in and out of FB mode.
*/
void SetPlayerFBMode(client, bool fbmode)
{
	if(fbmode)
	{
		TF2_AddCondition(client, AppliedUber, 10000000000.0);//Add uber for a long time
		SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);//Remove collisions
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER);
	}
	else
	{
		TF2_RemoveCondition(client,AppliedUber);
		SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_PLAYER);//Add back collisions
		SetEntProp(client, Prop_Data, "m_CollisionGroup", COLLISION_GROUP_PLAYER);
	}
}
/*
	Use: Force a player to respawn
*/
public Action ForceRespawnPlayer(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);//Get client so we can call him later.
	TF2_RespawnPlayer(client);
}
/*
	Use: On player death
*/
public Action:Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{

	if(!IsTestModeActive)//If not test mode. Do nothing.
	return Plugin_Continue;
	
	new client = GetClientOfUserId(GetEventInt(event, "userid"));//GetClient
	
	if (!IsValidClient(client))//They are valid past this point
		return Plugin_Continue; 
		
	CreateTimer(0.1,ForceRespawnPlayer, GetClientSerial(client));//We have to delay or they spawn ghosted
	
	return Plugin_Continue; 
}
/*
	Use: When someone readys a team for mp_tournament
		We block them here.
*/
public Action OnClientCommand(int client, int args)
{
	char cmd[256];
	GetCmdArg(0, cmd, sizeof(cmd)); //Get command name
	//Block team ready / team name change
	if (StrEqual(cmd, "tournament_readystate") || StrEqual(cmd, "tournament_teamname"))
	{
		return Plugin_Handled;
	}
	return Plugin_Continue;
}
/*
	Use: Post tournament timer
*/
public Action ResetTimeLimit(Handle timer, any serial)
{
	SetCVAR_SILENT("mp_tournament",0);//Our map change hit has been tanked, switch back
	ServerCommand("mp_tournament_restart");//Kill tournament mode.
	ServerCommand("mp_waitingforplayers_cancel 1");//Kill waiting for players post tournament mode
}
/*
	Use: On map start.
*/
public OnMapStart()
{
	IsMapLoaded = true;
}
/*
	Use: On map end, Reset everything.
*/
public void OnMapEnd()
{
	IsMapLoaded = false;
	IsTestModeTriggered = false;
	IsTestModeActive = false;
	ForceNextRoundTest = false;
	ForceFBRoundStarted = false;
	//Reset these to -1.
	FeedbackTimer = -1;
	MapTimeStorage = -1;
	CleanUpTimer();//Just in case.
	ClearSpawnPointsArray();
	SetCVAR_SILENT("mp_tournament",0);
	//Re-ACTIVATE RTV!!!
	PauseRTV(false);
	ResetAlltalk();
	EndOfRoundFlags = FBFLAG_DEFAULTVALUE;
}
/*
	Use: Resets alltalk
*/
void ResetAlltalk()
{
	if(AlltalkBuffer != -1)//We found a cvar change.
	{
		SetCVAR_SILENT("sv_alltalk",AlltalkBuffer);
		AlltalkBuffer = -1;
	}
}
/*
	Use: Reset the respawnpoints array
		lazy and dont want to write this everywhere.
*/
void ClearSpawnPointsArray()
{
	if(SpawnPointNames != null)
		ClearArray(SpawnPointNames);
	if(SpawnPointEntIDs != null)
		ClearArray(SpawnPointEntIDs);
}
/*
	Use: Get map time end quickly
		Why is this 2 lines when it can just be one!!!11!11
*/
int GetMapTimeLeftInt()
{
	int timeleft; 
	GetMapTimeLeft(timeleft);
	return timeleft;
}
/*
	Use: Get if the map has an info_target with the name of 'TF2M_ForceLastRoundFeedback'
		This allows mappers to splurge for fb rounds without saying a word, at the cost of 0 edicts?
		Im pretty sure info target isn't a networked entity...
*/
bool GetMapForceFeedbackLastRound()
{
	if(cvarList[FB_CVAR_ALLOWMAP_SETTINGS].IntValue <= 0)
		return false;//Stop, we are false.
	
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "info_target")) != -1)
	{
		decl String:entName[50];
		GetEntPropString(ent, Prop_Data, "m_iName", entName, sizeof(entName));//Get ent name.
		if(StrEqual(entName, "TF2M_ForceLastRoundFeedback",true))//true, we care about caps.
			return true;//break
	}
	return false;
}


public Action:Event_Teamplay_RoundActive(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(IsTestModeActive)
	{
		ShowFeedbackRoundHud = true;
		for(int iClient = 0; iClient <= MaxClients; iClient++)
		{
			if(IsValidClient(iClient))
				SetPlayerFBMode(iClient,true);
		}
	}
}

/*
	Use: When a round is won or stalemated
		Check how many seconds are left on this map.
		If the time is less than 25 seconds, enter feedback mode
		We do this because a round can be won 15 seconds before map change,
		Then the time limit hits in after round forcing us to switch.
*/
public Action:Event_Round_End(Handle:event,const String:name[],bool:dontBroadcast)
{
	if(!GetMapForceFeedbackLastRound())//if we dont find a map forced round,
	{
		if(!FeedbackModeActive && !ForceNextRoundTest)//If FB mode is not active, and next round test is not active
			return;
	}
	
	if(GetMapTimeLeftInt() <= ReturnExpectedDowntime() || ForceNextRoundTest)//25 seconds left or next round is a forced test.
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ Feedback round triggered");//Tell users in chat it has been triggered
		ShowFeedbackRoundHud = false;
		//Pause RTVing, Reset players RTVs
		PauseRTV(true);
		ResetRTV();
		
		IsTestModeTriggered = true;//Set test mode true
		
		if(GetMapTimeLeftInt() <= ReturnExpectedDowntime())//if we need to block the hit, do so.
		{
			SetCVAR_SILENT("mp_tournament",1);//Run config stuff
			ServerCommand("mp_tournament_restart");//Restart tourney
		}
	}
}
/*
	Use: Get the time required to trigger last round FB mode.
*/
int ReturnExpectedDowntime()
{
	if(IsArenaMode())
	return cvarList[FB_CVAR_DOWNTIME_FORCEFB_ARENA].IntValue;//Arena mode set to 60 seconds till switchmap.

	return cvarList[FB_CVAR_DOWNTIME_FORCEFB].IntValue + 25;
}
/*
	Use: On Entity created:
		Get pipes and destroy them.
*/
public OnEntityCreated(entity, const String:classname[])
{		
	if(!IsTestModeTriggered)//only run during fb round.
		return;
		//TODO: Test if this causes lag on fbround demos
	if(StrEqual(classname, "tf_projectile_pipe"))
	{
		SDKHook(entity, SDKHook_SpawnPost, Pipe_Spawned_post);
	}
	/*
	if(StrEqual(classname, "obj_sentrygun"))
	{
		AcceptEntityInput(entity,"Kill");
	}
	*/
}
/*
	Use: With the removal of tpose, we add jarate jumping.
		Bet you didn't know someone could love you this much.
		-pigpig
*/
public OnEntityDestroyed(entity)
{
	if(!IsTestModeTriggered)//only run during fb round.
		return;

	decl String:classname[64];
	if(IsValidEntity(entity))
		GetEntityClassname(entity, classname, sizeof(classname));
	if(StrEqual(classname, "tf_projectile_jar",false) || StrEqual(classname, "tf_projectile_jar_milk",false) || StrEqual(classname, "tf_projectile_jar_gas",false))//Someone said to remove jarate throwing during FB rounds, its 2am, why not right?
	{
		if(!IsMapLoaded)
			return;
		/*
			Get distance vector
			Normalize
			Scale by knockback value
		*/
		new thrower = GetEntPropEnt(entity, Prop_Data, "m_hThrower");
		if(IsValidClient(thrower) && IsPlayerAlive(thrower))//apply kb
		{
			//Get values
			new Float:curVec[3];new Float:cl_location[3];new Float:JarLocation[3];
			GetEntPropVector(entity, Prop_Send, "m_vecOrigin", JarLocation);	
			GetEntPropVector(thrower, Prop_Data, "m_vecVelocity", curVec);//If we want to add to their velocity rather than set it.
			GetClientAbsOrigin(thrower, cl_location);
			
			// 3D Distance
			for(int axi = 0; axi < 3; axi++)
				cl_location[axi] -= JarLocation[axi];
			// 1D Distance
			new Float:Distance = GetVectorLength(cl_location);
			//le hard coded values xdddd111
			if(Distance < 240.0)//if our 1d distance is close enough
			{
				//Normalize vector.
				NormalizeVector(cl_location,cl_location);

				//Scale the vector to our desired value.
				ScaleVector(cl_location, 600.0);
				
				if(StrEqual(classname, "tf_projectile_jar_gas",false))//make gas jumps super fat
					ScaleVector(cl_location, 3.0);
				
				if(cl_location[2] < 280.0)//Set their y axis to up.
					cl_location[2] = 280.0;
				
				//Add to velocity
				for(int axi = 0; axi < 3; axi++)
					cl_location[axi] += curVec[axi];
				//EXECUTE
				TeleportEntity(thrower, NULL_VECTOR, NULL_VECTOR, cl_location);
			}
		}
	}
}
/*
	Use: Get pipe 1 tick after spawned.
		We cannot get the owner of the pipe because valve has not set them yet.
		So we wait.
		
		We do this implementation so players can still cannonjump, this just blocks them from knocking people around.
*/
public void Pipe_Spawned_post(int Pipe)
{
	if(IsValidEntity(Pipe))
	{
		new Owner = GetEntPropEnt(Pipe, Prop_Data,"m_hOwnerEntity");
		if(IsValidClient(Owner))//I mean you COULD shoot and instantly disconnect to spawn the loose cannon.
		{
			new Primary = GetPlayerWeaponSlot(Owner, TFWeaponSlot_Primary);
			decl String:cname[64];
			GetEntityClassname(Primary, cname, 64);
			if(StrContains(cname, "tf_weapon_cannon", false) != -1)//if their primary is loose cannon.
			{
				AcceptEntityInput(Pipe,"Kill");
			}
		}
	}
}
/*
	Use: Chance a cvar silently 
*/
public SetCVAR_SILENT(String:CVAR_NAME[], int INTSET)
{
	new flags, Handle:cvar = FindConVar(CVAR_NAME);
	flags = GetConVarFlags(cvar);
	flags &= ~FCVAR_NOTIFY;
	SetConVarFlags(cvar, flags);
	CloseHandle(cvar);
	
	SetConVarInt(FindConVar(CVAR_NAME),INTSET);
}
void FbMapOverrideListings()
{
	if(cvarList[FB_CVAR_ALLOWMAP_SETTINGS].IntValue <= 0)
		return;

	decl String:OverrideString[256];
	decl String:ModString[256] = "";
	if(GetMapForceFeedbackLastRound())//If we find a end of round fb node. Add to list.
		Format(ModString, sizeof(ModString), "%s \n {gold}>{default}End map Map FB round",ModString);
		
	Format(OverrideString, sizeof(OverrideString), "------------------------ \n{gold}[Feedback]{default} ~ Map applies these attributes: %s",ModString);

	if(!StrEqual(ModString, ""))//if there are mods.
		CPrintToChatAll(OverrideString);//Tell everyone about test mode.
}
/*
	Use: Round start
*/
public Action:Event_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	/* General */
	if(MapTimeStorage != -1)//if there is a map time stored.
	{
		int MapTimeDistance = MapTimeStorage - GetMapTimeLeftInt();
		//This only adds time or subtracts. We read our new time and how far it is from what we want, then set accordingly.
		ExtendMapTimeLimit(MapTimeDistance);//This prints "mp_timelimit" in chat, Why?
		MapTimeStorage = -1;
	}

	/* FB round setups */
	if(IsFBRoundBlocked())
		return;
	FbMapOverrideListings();
	/* Warn players of imminent fb round */
	
	if(ForceNextRoundTest)
	{
		ShowFeedbackRoundHud = false;
		IsTestModeTriggered = true;
		ForceNextRoundTest = false;//Expire next round test.
		ForceFBRoundStarted = false;//We are no longer forcing fb round, its natural now.
	}
	if(ForceNextRoundTest || FeedbackModeActive)		//Tell people that FB rounds are a  thing.
	{
		if(!IsTestModeTriggered)
			CPrintToChatAll("\n{gold}[Feedback]{default} ~ Feedback rounds are active!");//Tell everyone about test mode.
	}


	if(!IsTestModeTriggered)//If not test mode, run normally
	{
		return;
	}
		
	//Alltalk handle
	
	AlltalkBuffer = GetConVarInt(FindConVar("sv_alltalk"));
	SetCVAR_SILENT("sv_alltalk",1);
		
	//Enable RTV again.
	//It should be reset by now.
	PauseRTV(false);
	
	IsTestModeActive = true;
	CreateTimer(1.0,ResetTimeLimit);//Remove tournament
	
	CPrintToChatAll("------------------------ \n{gold}[Feedback]{default} ~ Feedback round started: !sm_fbrh for more info\n\n {gold}>{default}You cannot kill anyone\n {gold}>{default}Leave as much feedback as possible.\n\n ------------------------");//Tell everyone about test mode.
	
	
	//Set timer
	FeedbackTimer = cvarList[FB_CVAR_ALLOTED_TIME].IntValue;//Read the cvar and set the timer to the cvartime.
	
	/* 				Ent stuff				 */
	//Create spawn list.
	PopulateSpawnList();
	
	
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
	{
		AcceptEntityInput(ent, "unlock");
		AcceptEntityInput(ent, "Open");
	}
	ent = -1;//Open all areaportals, Untested of course.
	while ((ent = FindEntityByClassname(ent, "func_areaportal")) != -1)
	{
		AcceptEntityInput(ent, "Open");
	}
	/*			GAMEMODE CHECKS				*/	
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_gamerules")) != -1)
	{
		/*
			We delay by 1 second here, every one of these maps SetStalemateOnTimelimit at the start of the round, so we need to be slower.
			
		*/
		
		new String:addoutput[64];
		Format(addoutput, 64, "OnUser1 !self:SetStalemateOnTimelimit:0.0:1:1");//On user 1, disable stalemate on map end.
		SetVariantString(addoutput);//SM setup
		AcceptEntityInput(ent, "AddOutput");//Sm setup of previous command
		AcceptEntityInput(ent, "FireUser1");//Swing
	}
	
	//Dampen respawnroom visualizers.
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "func_respawnroomvisualizer")) != -1)
	{
		
		SetVariantBool(false);
		AcceptEntityInput(ent, "SetSolid");
		/*
		//Tried "m_iSolidity" and "m_bSolid".
		//both give errors. So here we are overriding user1...
		//I Don't want to kill them because i want enemies to think "Oh, i usually wouldnt be able to enter this door."
		new String:addoutput[64];
		Format(addoutput, 64, "OnUser1 !self:SetSolid:0:1:1");//On user 1 setsolid 0
		SetVariantString(addoutput);//SM setup
		AcceptEntityInput(ent, "AddOutput");//Sm setup of previous command
		AcceptEntityInput(ent, "FireUser1");//Swing
		*/
	}
	//Allow players through enemy doors, and to trigger enemy filtered triggers.
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "filter_activator_tfteam")) != -1)
	{
		AcceptEntityInput(ent,"Kill");
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "tf_logic_player_destruction")) != -1)//Find and kill the pass logic
	{
		AcceptEntityInput(ent,"Kill");
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "team_round_timer")) != -1)//Pause round timers.
	{
		AcceptEntityInput(ent,"Pause");
		SetVariantString("0");
		AcceptEntityInput(ent,"ShowInHUD");
	}
	
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "trigger_capture_area")) != -1)//Kill all control points.
	{
		//We kill the capture zones insead of just disabling them incase the capture zone has an input to re-enable.
		AcceptEntityInput(ent,"Kill");
	}
	
	
	
	
	
	/* Force respawn everyone, Under the force next round condition: Players will not spawn properly! This is a bodge to get around that xdd */
	for(int ic = 0; ic < MaxClients; ic++)
	{
		if(IsValidClient(ic))
		{
			TF2_RespawnPlayer(ic);
			SetHudTextParams(-1.0, -0.5, 10.0, 255, 157, 0, 255); //Hud settings
			ShowSyncHudText(ic, feedbackHUD, "| FEEDBACK ROUND TRIGGERED | \n > | You cannot deal damage | Leave as much feedback as possible | <");//client, channel, text
		}
	}
	
	CleanUpTimer();//Incase it was already running. Clean it up before a new cycle.
	fbTimer = CreateTimer(1.0, CountdownTimer, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);//DONT CARRY OVER MAP CHANGE! Oh and repeat.
}
/*
	Use: Countdown timer logic
		Every second we count down and apply anything we need to be constantly true.
		Like resupplying players!!!
*/
public Action CountdownTimer(Handle timer, any serial)
{
	/*Hud Stuff*/
	for(int iClient = 0; iClient < MaxClients; iClient++)
	{
		if(IsValidClient(iClient))
		{
			TF2_RegeneratePlayer(iClient);//Resupply player (Updates items and metal)
			if(FeedbackTimer >= 0 && FeedbackTimer <= 1200)//If the timer is negative, dont draw. If the timer is over 20 minutes, asume its ment to last forever and dont draw.
				UpdateHud(iClient);
		}
	}
	/* Sentry stun stuff */
	new ent = -1;//Stun all sentry guns
	while ((ent = FindEntityByClassname(ent, "obj_sentrygun")) != -1)
	{
		SetEntProp(ent, Prop_Send, "m_bDisabled", 1);
	}
	
	/*Timer stuff*/
	if(FeedbackTimer == 30)
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ 30 seconds remaining!");//Tell users time is near an end
		EmitSoundToAll(SOUND_WARNSOUND, _, _, SNDLEVEL_DRYER, _, SNDVOL_NORMAL, _, _, _, _, _, _); 
	}
	if(FeedbackTimer < 10 && FeedbackTimer >= 0)//Hint the last 10 seconds.
	{
		EmitSoundToAll(SOUND_HINTSOUND, _, _, SNDLEVEL_DRYER, _, SNDVOL_NORMAL, _, _, _, _, _, _); 
	}
	
	
	if(FeedbackTimer == 0)
	{
		if(GetMapTimeLeftInt() <= ReturnExpectedDowntime() || EndOfRoundFlags & FBFLAG_FORCELASTROUND)//time expired, nextmap.
		{
			new String:mapString[256] = "cp_dustbowl";//If no nextmap, dustbowl
			GetNextMap(mapString, sizeof(mapString));
			CPrintToChatAll("{gold}[Feedback]{default} ~ Switching levels to %s, Thank you!", mapString);//Tell users time has expired
		}
		else//Map time didn't expire, continue the round.
		{
			CPrintToChatAll("{gold}[Feedback]{default} ~ Continuing map, Thank you!");//Tell users time has expired
		}
	}
	if(FeedbackTimer <= -5)//Give people 5 seconds of "OH FUCK IM TYPING ADD TIME"
	{
		FeedbackTimerExpired();
	}
	else//More than -5, Stop multiple timer ends.
		FeedbackTimer -= 1;//Take away one from the timer
}
/*
	Use: On timer expired, To simplify above and allow for more modular design.
*/
void FeedbackTimerExpired()
{
	ResetAlltalk();
	if(GetMapTimeLeftInt() <= ReturnExpectedDowntime() || EndOfRoundFlags & FBFLAG_FORCELASTROUND)//load next map.
	{
		new String:mapString[256] = "cp_dustbowl";//If no nextmap, dustbowl
		GetNextMap(mapString, sizeof(mapString));
		ForceChangeLevel(mapString, "Feedback time ran out");
		//PrintToServer("CALLED CHANGE LEVEL: FEEDBACK PLUGIN");
		//ServerCommand("changelevel %s",mapString);
	}
	else
	{
		CPrintToChatAll("{gold}[Feedback]{default} ~ FB Round ended");//Tell users time has expired
		//Uncomment EndRoundDraw if you want the end of a feedback round that has occured midgame to end in a draw.
		#if defined EndRoundDraw
			new entRoundWin = CreateEntityByName("game_round_win");
			DispatchKeyValue(entRoundWin, "force_map_reset", "1");
			DispatchSpawn(entRoundWin);
			SetVariantInt(0);//Spectate wins! Wait, Noone wins.
			AcceptEntityInput(entRoundWin, "SetTeam");
			AcceptEntityInput(entRoundWin, "RoundWin");
		#else
			MapTimeStorage = GetMapTimeLeftInt();//Log the map time left.
			ServerCommand("mp_restartgame 1");//Reload map
		#endif
	}
	//Remove conditions
	for(int iClient = 0; iClient < MaxClients; iClient++)
	{
		if(IsValidClient(iClient))
		{
			SetPlayerFBMode(iClient, false);
		}
	}
	IsTestModeTriggered = false;
	IsTestModeActive = false;
	CleanUpTimer();
}
/*
	Use: Clean up timer
*/
void CleanUpTimer()
{
	/* clean up handle.*/
	if (fbTimer != null)
	{
		KillTimer(fbTimer);
		fbTimer = null;
	}
}
/*
	Use: Countdown timer hud
*/
void UpdateHud(client)
{
	if(!IsValidClient(client) || !IsPlayerAlive(client) || !ShowFeedbackRoundHud)
		return;//if they are not real or alive, dont draw for them.
		//One thing to note is players connecting can be told to draw hud. so checking if they are alive is important.
		//Can cause error if i remember correctly.
	SetHudTextParams(-1.0, 0.80, 1.25, 198, 145, 65, 255); //Vsh hud location
	ShowSyncHudText(client, feedbackHUD, "| Time left %s |", ConvertFromMicrowaveTime(FeedbackTimer));//Current time is below, Super suspect thing i wrote like 2 years ago lol.
}
public OnGameFrame()
{
	//Quick and dirty implementation
	if(IsTestModeActive)
	{
		for(int iClient = 0; iClient <= MaxClients; iClient++)
		{
			if(IsValidClient(iClient) && FbRoundWalkSpeed[iClient] > WALKSPEED_MIN)//if a walk speed is loaded
			{
				SetEntPropFloat(iClient, Prop_Send, "m_flMaxspeed", FbRoundWalkSpeed[iClient]);
			}
		}
	}
}
public Action:OnPlayerRunCmd(client, &buttons, &impulse, Float:vel[3], Float:angles[3], &weapon)
{
	if(!IsTestModeActive)
		return Plugin_Continue;
		
	if(IsValidClient(client) && buttons & IN_ATTACK2)
	{
		if(TF2_GetPlayerClass(client) == TFClass_Pyro)//Block them from airblasting.
		{		
			new ActiveItem = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
			if(IsValidEntity(ActiveItem))
			{
				decl String:cname[64];
				GetEntityClassname(ActiveItem, cname, 64);
				if(StrEqual(cname, "tf_weapon_flamethrower", false) || StrEqual(cname, "tf_weapon_rocketlauncher_fireball", false))//if their primary is loose cannon.
				{
					buttons &= ~IN_ATTACK2;
					return Plugin_Continue;
				}
			}
		}
	}
	
	return Plugin_Continue;
}
public OnClientCookiesCached(client)
{
	//Load cookie
	decl String: sCookieValue[128];
	GetClientCookie(client, clFbRoundWalkSpeed, sCookieValue, 128);
	FbRoundWalkSpeed[client] = StringToFloat(sCookieValue);
}
public OnClientDisconnect(int client)
{
	FbRoundWalkSpeed[client] = 0.0;

	if(GetClientCount(false) <= 0)//False means count connecting players.
	{
		FeedbackModeActive = false;
		ForceNextRoundTest = false;
	}
}
/*
	Use: Countdown timer from microwave seconds to human seconds.
		There has to be a way to do this normally in SM. Just too lazy to look rn.
*/
/*
String:ConvertFromMicrowaveTime()
{
	int minutes = 0;
	int seconds = FeedbackTimer;
	
	minutes = seconds / 60;
	if(minutes > 0)
		seconds -= (minutes * 60);
		
	new String:secondsString[32] = "Failed";
	
	Format(secondsString,strlen(secondsString), "0%i", seconds);
	if(seconds >= 10)
		Format(secondsString,strlen(secondsString), "%i", seconds);
		
	new String:time[512];
	Format(time, 512, "%i:%s",minutes, secondsString);
	return time;
}
*/
String:ConvertFromMicrowaveTime(int tSeconds)
{
	//Get seconds
	int minutes = tSeconds / 60;
	int seconds = tSeconds % 60;
	//Create string
	/*
		This is so whe don't get something like 1:1 Where there is 1 minute 1 seconds left, Instead we want to get 1:01
	*/
	new String:secondsString[32] = "Failed";
	
	Format(secondsString,strlen(secondsString), "0%i", seconds);
	if(seconds >= 10)
		Format(secondsString,strlen(secondsString), "%i", seconds);

	new String:time[512];
	Format(time, 512, "%i:%s",minutes, secondsString);
	return time;
}


/*
	Use: Check if a player is really connected
*/
bool:IsValidClient(iClient)
{
	if (iClient < 1 || iClient > MaxClients)
		return false;
	if (!IsClientConnected(iClient))
		return false;
	return IsClientInGame(iClient);
}
/*
	--------------------------------------------------------------------------------
	   _____                                          _     
	  / ____|                                        | |    
	 | |     ___  _ __ ___  _ __ ___   __ _ _ __   __| |___ 
	 | |    / _ \| '_ ` _ \| '_ ` _ \ / _` | '_ \ / _` / __|
	 | |___| (_) | | | | | | | | | | | (_| | | | | (_| \__ \
	  \_____\___/|_| |_| |_|_| |_| |_|\__,_|_| |_|\__,_|___/                 
	--------------------------------------------------------------------------------
	Description: All player commands land here   

		Notes: I see no reason to comment commands
			Because its a really good idea with how complex commands can get
			Its just not fun to do so.
*/
/*
	Use: Return strings as "1, 0, -1" based off the input
*/
int Convert_String_True_False(String:StringName[])
{
	if(StrEqual(StringName,"false",false) || StrEqual(StringName,"no",false) || StrEqual(StringName,"0",false))//if false
		return BoolValue_False;
	else if(StrEqual(StringName,"true",false) || StrEqual(StringName,"yes",false) || StrEqual(StringName,"1",false))//if true
		return BoolValue_True;
	else //If not any of these. its null.
		return BoolValue_Null;
}
/*
	Use: Adds [Feedback] | To you | before every line.
	Prints to server
	I could have used RespondToClients()
	This is just a diffrent way of getting there.
*/
void RespondToAdminCMD(client, String:StringText[])
{
	//Holy lazy
	PrintToConsole(client, StringText);//Respond to console
	if(IsValidClient(client))
		CPrintToChat(client, "{gold}[Feedback]{default} | To you | %s", StringText);//Respond to ingame client
}
public Action:Command_Fb_Next_RoundToggle(int client, int args)
{
	LogAction(client,-1,"%N Called FB Nextround",client);
	if (args < 1)
	{
		//Flip the bool.
		ForceNextRoundTest = !ForceNextRoundTest;
		
		if(ForceNextRoundTest)//return to player
		{
			RespondToAdminCMD(client, "Lining up next round to be FB Round.");
		}
		else
		{
			RespondToAdminCMD(client, "Scrapped queued test round.");
		}
		
		return Plugin_Handled;
	}
	
	//Get arguement
	char test_arg[32];
	GetCmdArg(1, test_arg, sizeof(test_arg));
	int output = Convert_String_True_False(test_arg);//Convert that arguement to simplify
	
	//Sourcemod auto breaks
	switch(output)
	{
		case BoolValue_Null: // They didnt use (true,false,1,0,yes,no)
		{
			RespondToAdminCMD(client, "Usage: fb_round [TRUE/FALSE][1/0][YES/NO]");
		}
		case BoolValue_True:
		{
			if(!ForceNextRoundTest)
			{
				RespondToAdminCMD(client, "Lining up next round to be FB Round.");
				ForceNextRoundTest = true;
			}
			else
				RespondToAdminCMD(client, "Next round is already queued up to be an FB round.");
			
		}
		case BoolValue_False:
		{
			if(ForceNextRoundTest)
			{
				RespondToAdminCMD(client, "Scrapped queued test round.");
				ForceNextRoundTest = false;
			}
			else
				RespondToAdminCMD(client, "There is no FB round queued for after this round.");
		}
	}
	return Plugin_Handled;
}
public Action:Command_FB_Round_Enabled(int client, int args)
{
	//We should probbably call this later, then say "Toggled on/off"
	LogAction(client,-1,"%N Called FB Round toggle",client);

	if (args < 1)//CALLED TOGGLE
	{
		//Flip the bool.
		FeedbackModeActive = !FeedbackModeActive;
		
		if(FeedbackModeActive)//return to player
		{
			RespondToAdminCMD(client, "Enabled! All last game rounds past this point will be fb rounds.");
		}
		else
		{
			RespondToAdminCMD(client, "Disabled! All last game rounds past this point will NOT be fb rounds. Repeat will NOT be!");
		}
		
		return Plugin_Handled;
	}
	
	//Get arguement
	char test_arg[32];
	GetCmdArg(1, test_arg, sizeof(test_arg));
	int output = Convert_String_True_False(test_arg);//Convert that arguement to simplify
	
	//Sourcemod auto breaks
	switch(output)
	{
		case BoolValue_Null: // They didnt use (true,false,1,0,yes,no)
		{
			RespondToAdminCMD(client, "Usage: sm_fb_round_enable [TRUE/FALSE][1/0][YES/NO]");
		}
		case BoolValue_True:
		{
			if(!FeedbackModeActive)
			{
				RespondToAdminCMD(client, "Enabled! All last game rounds past this point will be fb rounds.");
				FeedbackModeActive = true;
			}
			else
				RespondToAdminCMD(client, "Last round FB rounds are already enabled.");
			
		}
		case BoolValue_False:
		{
			if(FeedbackModeActive)
			{
				RespondToAdminCMD(client, "Disabled! All last game rounds past this point will NOT be fb rounds. Repeat will NOT be!");
				FeedbackModeActive = false;
			}
			else
				RespondToAdminCMD(client, "Last round FB rounds are already disabled.");
		}
	}
	return Plugin_Handled;
}
public Action:Command_Fb_AddTime(int client, int args)
{
	if (args < 2)// client didnt give enough arguements.
	{
		RespondToAdminCMD(client, "Usage: sm_fb_addtime <number>");
		return Plugin_Handled;
	}
	if(!IsTestModeTriggered)
	{
		RespondToAdminCMD(client, "You can only use this command while an FB round is active.");
		return Plugin_Handled;
	}
	
	LogAction(client,-1,"%N Changed the FBRound timer.",client);
	
	/*		Get ARGS me m8ty		*/	
	//get classification
	char test_arg_class[32];
	GetCmdArg(1, test_arg_class, sizeof(test_arg_class));
	//get time
	char test_arg[32];
	GetCmdArg(2, test_arg, sizeof(test_arg));
	int time = StringToInt(test_arg);
	time *= 60;//Scale to minutes.

	switch(time)//egg
	{
		case 69, 420:
		{
			RespondToAdminCMD(client, "le funny numbre xdd111");
		}
		default:
		{
			if(time <= 0)//adding no time at all, or generally doing nothing
			{
				RespondToAdminCMD(client, "This command only accepts positive numbers. To force end a round use sm_fbround_forceend");
				return Plugin_Handled;//Stop here.
			}
		}
	}
	decl String:TimeCommand[256];
	
	if(StrEqual(test_arg_class, "set",false))
	{
		FeedbackTimer = time;
		Format(TimeCommand, sizeof(TimeCommand), "Time set to %i minutes.", time / 60);
	}
	else if (StrEqual(test_arg_class, "add",false))
	{
		FeedbackTimer += time;
		Format(TimeCommand, sizeof(TimeCommand), "Added %i minutes.", time / 60);
	}
	RespondToAdminCMD(client,TimeCommand);
	
	return Plugin_Handled;
}
public Action:Command_Fb_Cancel_Round(int client, int args)
{
	LogAction(client,-1,"%N Skipped the FB round.",client);
	if(IsTestModeTriggered)
	{
		RespondToAdminCMD(client, "Skipping FB round.");
		FeedbackTimer = -4;
	}
	else
	{
		RespondToAdminCMD(client, "There is no active FB round.");
	}
}
public Action:Command_ReturnEdicts(int client, int args)
{
	LogAction(client,-1,"%N Asked for edicts.",client);
	CReplyToCommand(client, "{gold}[Feedback]{default} There are %i edicts on the level.", GetEntityCount());
}
public Action:Command_Fb_OpenDoors(int client, int args)
{
	LogAction(client,-1,"%N Opened all doors.",client);
	int DoorsOpened = 0;
	new ent = -1;//Open all doors.
	while ((ent = FindEntityByClassname(ent, "func_door")) != -1)
	{
		DoorsOpened++;
		AcceptEntityInput(ent, "unlock");
		AcceptEntityInput(ent, "Open");
	}
	CReplyToCommand(client, "{gold}[Feedback]{default} Opened %i door(s)",DoorsOpened);
}

/* Forward spawn / multistage teleport command */
public int MenuHandler1(Menu menu, MenuAction action, int param1, int param2)
{
    /* If an option was selected, tell the client about the item. */
    if (action == MenuAction_Select)
    {
		char info[32];
		menu.GetItem(param2, info, sizeof(info));
		//PrintToConsole(param1, "You selected spawn: %d (found? %d info: %s)", param2, found, info);

		//PARAM 1 IS CLIENT!!!

		new SpawnEntity = StringToInt(info);

		float vPos[3], vAng[3];
		GetEntPropVector(SpawnEntity, Prop_Send, "m_vecOrigin", vPos);
		GetEntPropVector(SpawnEntity, Prop_Send, "m_angRotation", vAng);

		TeleportEntity(param1, vPos, vAng, NULL_VECTOR);
		
    }
    /* If the menu has ended, destroy it */
    if (action == MenuAction_End)
    {
        delete menu;
    }
}
/* Change FB round walk speed */
public Action Command_walkspeed(int client, int args)
{
	if (args < 1)// client didnt give enough arguements.
	{
		RespondToAdminCMD(client, "Usage: sm_walkspeed <number>");
		return Plugin_Handled;
	}
	char arg1[32];
	GetCmdArg(1, arg1, sizeof(arg1));
	float clSpeed = StringToFloat(arg1);
	if(clSpeed == 0.0)//Error
	{
		RespondToAdminCMD(client, "Usage: sm_walkspeed <number>");
	}
	else if(clSpeed < WALKSPEED_MIN)
	{
		CReplyToCommand(client, "{gold}[Feedback]{default} Please pick a number higher than %0.1f", WALKSPEED_MIN);
	}
	else if(clSpeed > WALKSPEED_MAX)
	{
		CReplyToCommand(client, "{gold}[Feedback]{default} Please pick a number lower than %0.1f", WALKSPEED_MAX);
	}
	else if(IsValidClient(client))
	{
		CReplyToCommand(client, "{gold}[Feedback]{default} Set speed to %0.1f", clSpeed);
		//Convert float to string, set string.
		decl String:sCookieValue[16];
		FloatToString(clSpeed, sCookieValue, sizeof(sCookieValue));
		SetClientCookie(client,  clFbRoundWalkSpeed, sCookieValue);
		FbRoundWalkSpeed[client] = clSpeed;
	}
	return Plugin_Handled;
}
/* FBHelp command */
public Action Command_FBround_Help(int client, int args)
{
	if(IsValidClient(client))
	{
		CPrintToChat(client, "---------{gold}[Feedback Help]{default}---------\n {gold}Commands{default} : \n >fbspawn | Teleport to a list of unique spawn locations. \n >fbtellents | Print map edict count. \n >walkspeed | Set your walking speed between %i and %i.",RoundFloat(WALKSPEED_MIN), RoundFloat(WALKSPEED_MAX));
	}
}
/* Debug command */
public Action Command_FBQuack(int client, int args)
{
	if(IsValidClient(client))
	{
		EmitSoundToAll(SOUND_QUACK,client, SNDCHAN_AUTO, SNDLEVEL_LIBRARY,SND_NOFLAGS,1.0, 100);
	}
	return Plugin_Handled;
}
/* FBMenu command */
public Action Menu_SpawnTest(int client, int args)
{
	LogAction(client,-1,"%N Asked for spawnpoints",client);
	if(IsTestModeTriggered)
	{
		//ONLY FOR DEBUGGING. THE ARRAY SHOULD BE CREATED ON PLUGIN START / Map spawn
		#if defined DEBUG
			PopulateSpawnList();
		#endif
		
		ShowClientTPPage(client);//Load page
	}
	else
	{
		CReplyToCommand(client, "{gold}[Feedback]{default} Nice try. But you can only jump spawns on feedback rounds.");
	}

	return Plugin_Handled;
}
void ShowClientTPPage(client)
{	
	Menu menu = new Menu(MenuHandler1);
	menu.SetTitle("Teleport to spawnpoint :");
	for(int ItemCount = 0;ItemCount <= GetArraySize(SpawnPointNames) - 1; ItemCount++)
	{	
		decl String:TextString[128] = "Oops! Looks like something went wrong.";
		SpawnPointNames.GetString(ItemCount, TextString, sizeof(TextString));
		decl String:InfoString[6] = "Oops!";
		SpawnPointEntIDs.GetString(ItemCount, InfoString, sizeof(InfoString));
		
		menu.AddItem(InfoString, TextString);//INFO : TEXT
	}
	
	menu.ExitButton = false;
	menu.Display(client, MENU_TIME_FOREVER);
} 
/*
	Use: Create the spawn point array.
*/
void PopulateSpawnList()
{
	ClearSpawnPointsArray();
	
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "info_player_teamspawn")) != -1)
	{
		bool AddThisString = false;
		
		decl String:strName[50];
		GetEntPropString(ent, Prop_Data, "m_iName", strName, sizeof(strName));//Get ent name.
		
		if(GetArraySize(SpawnPointNames) == 0)//We start the array.
		{
			AddThisString = true;
		}
		else//All other not 1st cases.
		{
			if(FindStringInArray(SpawnPointNames, strName) == -1)//We found no similar string. add a new one
			{
				AddThisString = true;
			}
			
		}
		if(AddThisString)
		{
			if(StrEqual(strName, "",false))//if the spawn has no name, its probs a valve added debug spawn or something.
				continue;
				
			PushArrayString(SpawnPointNames,strName);
			//Why cant i just .tostring() :/
			decl String:entstring[50];
			IntToString(ent,entstring,sizeof(entstring));
			PushArrayString(SpawnPointEntIDs, entstring);
		}
	}
}
