//EDITED FOR FEEDBACK2 PLUGIN.
//0.0.3
/**
 * vim: set ts=4 :
 * =============================================================================
 * SourceMod Rock The Vote Plugin
 * Creates a map vote when the required number of players have requested one.
 *
 * SourceMod (C)2004-2008 AlliedModders LLC.  All rights reserved.
 * =============================================================================
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * As a special exception, AlliedModders LLC gives you permission to link the
 * code of this program (as well as its derivative works) to "Half-Life 2," the
 * "Source Engine," the "SourcePawn JIT," and any Game MODs that run on software
 * by the Valve Corporation.  You must obey the GNU General Public License in
 * all respects for all other code used.  Additionally, AlliedModders LLC grants
 * this exception to all derivative works.  AlliedModders LLC defines further
 * exceptions, found in LICENSE.txt (as of this writing, version JULY-31-2007),
 * or <http://www.sourcemod.net/license.php>.
 *
 * Version: $Id$
 */

#include <sourcemod>
#include <mapchooser>

#undef REQUIRE_PLUGIN
#tryinclude <feedback2>

#include <nextmap>

#pragma semicolon 1

public Plugin myinfo =
{
	name = "Rock The Vote",
	author = "AlliedModders LLC",
	description = "Provides RTV Map Voting",
	version = SOURCEMOD_VERSION,
	url = "http://www.sourcemod.net/"
};


ConVar g_Cvar_Needed;
ConVar g_Cvar_MinPlayers;
ConVar g_Cvar_InitialDelay;
ConVar g_Cvar_Interval;
ConVar g_Cvar_ChangeTime;
ConVar g_Cvar_RTVPostVoteAction;

bool g_CanRTV = false;		// True if RTV loaded maps and is active.
bool g_RTVAllowed = false;	// True if RTV is available to players. Used to delay rtv votes.
int g_Voters = 0;				// Total voters connected. Doesn't include fake clients.
int g_Votes = 0;				// Total number of "say rtv" votes
int g_VotesNeeded = 0;			// Necessary votes before map vote begins. (voters * percent_needed)
bool g_Voted[MAXPLAYERS+1] = {false, ...};

bool g_InChange = false;
bool g_RTVPaused = false;
bool g_IsFbPluginLoaded = false;

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("rockthevote.phrases");
	
	g_Cvar_Needed = CreateConVar("sm_rtv_needed", "0.60", "Percentage of players needed to rockthevote (Def 60%)", 0, true, 0.05, true, 1.0);
	g_Cvar_MinPlayers = CreateConVar("sm_rtv_minplayers", "0", "Number of players required before RTV will be enabled.", 0, true, 0.0, true, float(MAXPLAYERS));
	g_Cvar_InitialDelay = CreateConVar("sm_rtv_initialdelay", "30.0", "Time (in seconds) before first RTV can be held", 0, true, 0.00);
	g_Cvar_Interval = CreateConVar("sm_rtv_interval", "240.0", "Time (in seconds) after a failed RTV before another can be held", 0, true, 0.00);
	g_Cvar_ChangeTime = CreateConVar("sm_rtv_changetime", "0", "When to change the map after a succesful RTV: 0 - Instant, 1 - RoundEnd, 2 - MapEnd", _, true, 0.0, true, 2.0);
	g_Cvar_RTVPostVoteAction = CreateConVar("sm_rtv_postvoteaction", "0", "What to do with RTV's after a mapvote has completed. 0 - Allow, success = instant change, 1 - Deny", _, true, 0.0, true, 1.0);
	
	RegConsoleCmd("sm_rtv", Command_RTV);
	
	AutoExecConfig(true, "rtv");
	
	RegAdminCmd("sm_pausertv", Command_PauseRTV, ADMFLAG_KICK, "Pauses RTV");
	RegAdminCmd("sm_resetrtv", Command_ResetRTV, ADMFLAG_KICK, "Resets RTV");

}

/* FEEDBACK TUMOR MODE ACTIVATED! */
public OnAllPluginsLoaded()
{
    g_IsFbPluginLoaded = LibraryExists("feedback2");
}
public OnLibraryAdded(const String:name[])
{
    SetPluginDetection(name, true);
}

public OnLibraryRemoved(const String:name[])
{
    SetPluginDetection(name, false);
}
SetPluginDetection(const String:name[], bool:bBool)
{
    if (StrEqual(name, "feedback2"))
    {
		if(bBool)//True
			PrintToServer("RTV PLUGIN: Detected FB plugin loading.");
		else
			PrintToServer("RTV PLUGIN: Detected FB plugin unloading.");
			
		g_IsFbPluginLoaded = bBool;
    }
}

public Action:Command_PauseRTV(int client, int args)
{
	if (args < 1)
	{
		PrintToServer("RTV pause needs more args");
	}
	char test_arg[32];
	GetCmdArg(1, test_arg, sizeof(test_arg));
	int output = Convert_String_True_False(test_arg);//Convert that arguement to simplify
	bool isPaused = false;
	if(output == BoolValue_True)
	isPaused = true;
	
	PauseRTV(isPaused);
}
public Action:Command_ResetRTV(int client, int args)
{
	ResetRTV();
}
int Convert_String_True_False(String:StringName[])
{
	if(StrEqual(StringName,"false",false) || StrEqual(StringName,"no",false) || StrEqual(StringName,"0",false))//if false
		return BoolValue_False;
	else if(StrEqual(StringName,"true",false) || StrEqual(StringName,"yes",false) || StrEqual(StringName,"1",false))//if true
		return BoolValue_True;
	else //If not any of these. its null.
		return BoolValue_Null;
}
public PauseRTV(bool:isPaused)
{
	g_RTVPaused = isPaused;
}


public void OnMapStart()
{
	g_Voters = 0;
	g_Votes = 0;
	g_VotesNeeded = 0;
	g_InChange = false;
	
	/* Handle late load */
	for (int i=1; i<=MaxClients; i++)
	{
		if (IsClientConnected(i))
		{
			OnClientConnected(i);	
		}	
	}
}

public void OnMapEnd()
{
	g_CanRTV = false;	
	g_RTVAllowed = false;
}

public void OnConfigsExecuted()
{	
	g_CanRTV = true;
	g_RTVAllowed = false;
	CreateTimer(g_Cvar_InitialDelay.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientConnected(int client)
{
	if(IsFakeClient(client))
		return;
	
	g_Voted[client] = false;

	g_Voters++;
	g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	
	return;
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client))
		return;
	
	if(g_Voted[client])
	{
		g_Votes--;
	}
	
	g_Voters--;
	
	g_VotesNeeded = RoundToCeil(float(g_Voters) * g_Cvar_Needed.FloatValue);
	
	if (!g_CanRTV)
	{
		return;	
	}
	
	if (g_Votes && 
		g_Voters && 
		g_Votes >= g_VotesNeeded && 
		g_RTVAllowed ) 
	{
		if (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished())
		{
			return;
		}
		
		StartRTV();
	}	
}

public void OnClientSayCommand_Post(int client, const char[] command, const char[] sArgs)
{
	if (!g_CanRTV || !client)
	{
		return;
	}
	
	if (strcmp(sArgs, "rtv", false) == 0 || strcmp(sArgs, "rockthevote", false) == 0)
	{
		ReplySource old = SetCmdReplySource(SM_REPLY_TO_CHAT);
		
		AttemptRTV(client);
		
		SetCmdReplySource(old);
	}
}

public Action Command_RTV(int client, int args)
{
	if (!g_CanRTV || !client)
	{
		return Plugin_Handled;
	}
	
	AttemptRTV(client);
	
	return Plugin_Handled;
}

void AttemptRTV(int client)
{
	if (!g_RTVAllowed  || (g_Cvar_RTVPostVoteAction.IntValue == 1 && HasEndOfMapVoteFinished()) || g_RTVPaused)
	{
		ReplyToCommand(client, "[SM] %t", "RTV Not Allowed");
		return;
	}
		
	if (!CanMapChooserStartVote())
	{
		ReplyToCommand(client, "[SM] %t", "RTV Started");
		return;
	}
	
	if (GetClientCount(true) < g_Cvar_MinPlayers.IntValue)
	{
		ReplyToCommand(client, "[SM] %t", "Minimal Players Not Met");
		return;			
	}
	
	if (g_Voted[client])
	{
		ReplyToCommand(client, "[SM] %t", "Already Voted", g_Votes, g_VotesNeeded);
		return;
	}	
	
	char name[MAX_NAME_LENGTH];
	GetClientName(client, name, sizeof(name));
	
	g_Votes++;
	g_Voted[client] = true;
	
	PrintToChatAll("[SM] %t", "RTV Requested", name, g_Votes, g_VotesNeeded);
	
	if (g_Votes >= g_VotesNeeded)
	{
		StartRTV();
	}	
}

public Action Timer_DelayRTV(Handle timer)
{
	g_RTVAllowed = true;
}

void StartRTV()
{
	/* FB round block */
	if(g_IsFbPluginLoaded)
	{
		if(!FB2_IsFbRoundActive())//FB ROUND IS NOT ACTIVE, ENTER.
		{
			if(FB2_ForceNextRoundTest() || FB2_EndMapFeedbackModeActive())//If FB mode is set for end of map/ end of round. ENTER!
			{
				//Run over to the FB plugin.
				FB2_ForceFbRoundLastRound(true);//Force last round.
				FB2_ForceCancelRound_StartFBRound();
				return;
			}
		}
	}
	if (g_InChange)
	{
		return;	
	}
	
	if (EndOfMapVoteEnabled() && HasEndOfMapVoteFinished())
	{
		/* Change right now then */
		char map[PLATFORM_MAX_PATH];
		if (GetNextMap(map, sizeof(map)))
		{
			GetMapDisplayName(map, map, sizeof(map));
			
			PrintToChatAll("[SM] %t", "Changing Maps", map);
			CreateTimer(5.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
			g_InChange = true;
			
			ResetRTV();
			
			g_RTVAllowed = false;
		}
		return;	
	}
	
	if (CanMapChooserStartVote())
	{
		MapChange when = view_as<MapChange>(g_Cvar_ChangeTime.IntValue);
		InitiateMapChooserVote(when);
		
		ResetRTV();
		
		g_RTVAllowed = false;
		CreateTimer(g_Cvar_Interval.FloatValue, Timer_DelayRTV, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

void ResetRTV()
{
	g_Votes = 0;
			
	for (int i=1; i<=MAXPLAYERS; i++)
	{
		g_Voted[i] = false;
	}
}

public Action Timer_ChangeMap(Handle hTimer)
{
	g_InChange = false;
	
	LogMessage("RTV changing map manually");
	
	char map[PLATFORM_MAX_PATH];
	if (GetNextMap(map, sizeof(map)))
	{	
		ForceChangeLevel(map, "RTV after mapvote");
	}
	
	return Plugin_Stop;
}
