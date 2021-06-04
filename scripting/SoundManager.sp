#include <sourcemod>
#include <clientprefs>
#include <dhooks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "Sound Manager",
	author = "Haze",
	description = "",
	version = "1.0",
	url = ""
}

#define Mute_Soundscapes				(1 << 0)
#define Mute_AmbientSounds				(1 << 1)
#define Mute_GunSounds					(1 << 2)
#define Mute_TriggerSounds				(1 << 3)
#define Mute_AllPackets					(1 << 4)
#define Debug							(1 << 5)

// Player settings
int gI_Settings[MAXPLAYERS+1];

// Debug
int gI_LastSoundscape[MAXPLAYERS+1];

// Cookie
Handle gH_SettingsCookie = null;

// Dhooks
Handle gH_AcceptInput = null;
Handle gH_GetPlayerSlot = null;

// Other
bool gB_ShouldHookShotgunShot = false;
ArrayList gA_PlayEverywhereAmbients = null;

// Late Load
bool gB_LateLoad = false;

//-----------------------FORWARDS-------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_LateLoad = late;
}

public void OnPluginStart()
{
	// Commands
	RegConsoleCmd("sm_snd", Command_Sounds);
	RegConsoleCmd("sm_sound", Command_Sounds);
	RegConsoleCmd("sm_sounds", Command_Sounds);
	RegConsoleCmd("sm_music", Command_Sounds);
	RegConsoleCmd("sm_stopmusic", Command_Sounds);
	RegConsoleCmd("sm_stopsounds", Command_Sounds);

	// Cookie
	gH_SettingsCookie = RegClientCookie("sound_settings", "Sound Manager Settings", CookieAccess_Protected);

	// ArrayList for ambient_generic's with spawnflags & 1 (play everywhere [1]) 
	gA_PlayEverywhereAmbients = new ArrayList(ByteCountToCells(4));

	// Hook round_start
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	// Dhooks
	HookSoundScapes();
	HookAcceptInput();
	HookSendSound();

	// Sound Hook
	AddTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);

	// Late Load
	if(gB_LateLoad)
	{
		int entity = -1;
		while((entity = FindEntityByClassname(entity, "point_clientcommand")) != -1)
		{
			DHookEntity(gH_AcceptInput, false, entity);
		}

		Event_RoundStart(null, "", false);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i))
			{
				continue;
			}

			if(AreClientCookiesCached(i))
			{
				OnClientCookiesCached(i);
			}
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "point_clientcommand"))
	{
		DHookEntity(gH_AcceptInput, false, entity);
	}
}

public void OnClientDisconnect_Post(int client)
{
	gI_Settings[client] = 0;
	CheckShotgunShotHook();
}

public void OnClientCookiesCached(int client)
{
	gI_LastSoundscape[client] = -1;

	char sCookie[16];
	GetClientCookie(client, gH_SettingsCookie, sCookie, 16);

	if(strlen(sCookie) == 0)
	{
		gI_Settings[client] = 0;
	}
	else
	{
		gI_Settings[client] = StringToInt(sCookie);
	}

	if((gI_Settings[client] & Mute_GunSounds) && gB_ShouldHookShotgunShot == false)
	{
		gB_ShouldHookShotgunShot = true;
	}

	if(gI_Settings[client] & Mute_AmbientSounds)
	{
		CreateTimer(1.0, ConnectMuteAmbientTimer, GetClientSerial(client));
	}
}
//-------------------------------------------------------------

//-------------------------SOUNDSCAPES-------------------------
void HookSoundScapes()
{
	Handle hGameData = LoadGameConfigFile("SoundManager.games");
	if(!hGameData)
	{
		delete hGameData;
		SetFailState("Failed to load SoundManager gamedata.");
	}

	Handle hFunction = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity); 
	DHookSetFromConf(hFunction, hGameData, SDKConf_Signature, "CEnvSoundscape::UpdateForPlayer");
	DHookAddParam(hFunction, HookParamType_ObjectPtr);

	delete hGameData;

	if(!DHookEnableDetour(hFunction, false, DHook_UpdateForPlayer))
	{
		SetFailState("Couldn't enable CEnvSoundscape::UpdateForPlayer detour.");
	}
}

//void CEnvSoundscape::UpdateForPlayer( ss_update_t &update )
public MRESReturn DHook_UpdateForPlayer(int pThis, Handle hParams)
{
	if(!IsValidEdict(pThis))
	{
		return MRES_Ignored;
	}

	int client = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_CBaseEntityPtr);

	MRESReturn ret = MRES_Ignored;

	if(gI_Settings[client] & Mute_Soundscapes)
	{
		SetEntProp(client, Prop_Data, "soundscapeIndex", 138);

		if((gI_Settings[client] & Debug) && gI_LastSoundscape[client] != 138 && GetEntProp(client, Prop_Data, "soundscapeIndex") == 138)
		{
			PrintToChat(client, "[Debug] Soundscape Blocked (%d)", pThis);
		}

		ret = MRES_Supercede;
	}
	else
	{
		DHookSetParamObjectPtrVar(hParams, 1, 4, ObjectValueType_CBaseEntityPtr, 0);
	}

	gI_LastSoundscape[client] = GetEntProp(client, Prop_Data, "soundscapeIndex");
	return ret;
}
//---------------------------------------------------------------

//------------------------TRIGGER OUTPUTS------------------------
void HookAcceptInput()
{
	Handle hGameData = LoadGameConfigFile("SoundManager.games");
	if(!hGameData)
	{
		delete hGameData;
		SetFailState("Failed to load SoundManager gamedata.");
	}

	int offset = GameConfGetOffset(hGameData, "AcceptInput");
	
	delete hGameData;
	
	if(offset == 0) 
	{
		SetFailState("Failed to load \"AcceptInput\", invalid offset.");
	}

	gH_AcceptInput = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, DHook_AcceptInput);
	DHookAddParam(gH_AcceptInput, HookParamType_CharPtr);
	DHookAddParam(gH_AcceptInput, HookParamType_CBaseEntity);
	DHookAddParam(gH_AcceptInput, HookParamType_CBaseEntity);
	DHookAddParam(gH_AcceptInput, HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP);
	DHookAddParam(gH_AcceptInput, HookParamType_Int);
}

// virtual bool AcceptInput( const char *szInputName, CBaseEntity *pActivator, CBaseEntity *pCaller, variant_t Value, int outputID );
public MRESReturn DHook_AcceptInput(int pThis, Handle hReturn, Handle hParams)
{
	if(DHookIsNullParam(hParams, 2) || DHookIsNullParam(hParams, 3))
	{
		return MRES_Ignored;
	}

	int client = DHookGetParam(hParams, 2);

	if(!IsValidClient(client))
	{
		return MRES_Ignored;
	}

	if(gI_Settings[client] & Mute_TriggerSounds == 0)
	{
		return MRES_Ignored;
	}

	char sParameter[128];
	DHookGetParamObjectPtrString(hParams, 4, 0, ObjectValueType_String, sParameter, 128);

	if(StrContains(sParameter, "play") != -1)
	{
		if(gI_Settings[client] & Debug)
		{
			PrintToChat(client, "[Debug] Output Blocked (%s)", sParameter);
		}

		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}

	return MRES_Ignored;
}
//-----------------------------------------------------

//----------------AMBIENT/NORMAL SOUNDS----------------
void HookSendSound()
{
	Handle hGameData = LoadGameConfigFile("SoundManager.games");
	if(!hGameData)
	{
		delete hGameData;
		SetFailState("Failed to load SoundManager gamedata.");
	}

	Handle hFunction = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address); 
	DHookSetFromConf(hFunction, hGameData, SDKConf_Signature, "CGameClient::SendSound");
	DHookAddParam(hFunction, HookParamType_ObjectPtr);
	DHookAddParam(hFunction, HookParamType_Bool);

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseClient::GetPlayerSlot");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);

	delete hGameData;

	if (!(gH_GetPlayerSlot = EndPrepSDKCall()))
	{
		SetFailState("Could not initialize call to CBaseClient::GetPlayerSlot.");
	}

	if(!DHookEnableDetour(hFunction, false, DHook_SendSound))
	{
		SetFailState("Couldn't enable CGameClient::SendSound detour.");
	}
}

//void CGameClient::SendSound( SoundInfo_t &sound, bool isReliable )
public MRESReturn DHook_SendSound(Address pThis, Handle hParams)
{
	Address pIClient = pThis + view_as<Address>(4);
	int client = view_as<int>(SDKCall(gH_GetPlayerSlot, pIClient)) + 1;
	if(!IsValidClient(client))
	{
		return MRES_Ignored;
	}

	if(DHookGetParamObjectPtrVar(hParams, 1, 40, ObjectValueType_Float) == 0.0)
	{
		return MRES_Ignored;
	}
	bool bIsAmbient = DHookGetParamObjectPtrVar(hParams, 1, 85, ObjectValueType_Bool);

	MRESReturn ret = MRES_Ignored;

	if(bIsAmbient)
	{
		if(gI_Settings[client] & Mute_AmbientSounds)
		{
			if(gI_Settings[client] & Debug)
			{
				PrintToChat(client, "[Debug] Ambient Blocked");
			}
			ret = MRES_Supercede;
		}
	}
	else
	{
		if(gI_Settings[client] & Mute_AllPackets)
		{
			if(gI_Settings[client] & Debug)
			{
				PrintToChat(client, "[Debug] Sound Blocked");
			}
			ret = MRES_Supercede;
		}
	}
	return ret;
}
//-----------------------------------------------------

//------------------------MENU-------------------------
public Action Command_Sounds(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_Sounds);
	menu.SetTitle("Sound Manager\n \n");

	char sDisplay[64];
	char sInfo[16];
	
	FormatEx(sDisplay, 64, "Soundscapes: [%s]", gI_Settings[client] & Mute_Soundscapes ? "Muted" : "On");
	IntToString(Mute_Soundscapes, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);

	FormatEx(sDisplay, 64, "Ambient Sounds: [%s]", gI_Settings[client] & Mute_AmbientSounds ? "Muted" : "On");
	IntToString(Mute_AmbientSounds, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);

	FormatEx(sDisplay, 64, "Trigger Sounds: [%s]\n ", gI_Settings[client] & Mute_TriggerSounds ? "Muted" : "On");
	IntToString(Mute_TriggerSounds, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);

	FormatEx(sDisplay, 64, "Gun Sounds: [%s]\n ", gI_Settings[client] & Mute_GunSounds ? "Muted" : "On");
	IntToString(Mute_GunSounds, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);

	FormatEx(sDisplay, 64, "Block all sound packets: [%s]", gI_Settings[client] & Mute_AllPackets ? "Yes" : "No");
	IntToString(Mute_AllPackets, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);

	if(CheckCommandAccess(client, "soundmanager_debug", ADMFLAG_RCON))
	{
		FormatEx(sDisplay, 64, "Debug Prints: [%s]", gI_Settings[client] & Debug ? "Yes" : "No");
		IntToString(Debug, sInfo, 16);
		menu.AddItem(sInfo, sDisplay);
	}

	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int MenuHandler_Sounds(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int iOption = StringToInt(sInfo);
		gI_Settings[param1] ^= iOption;

		if(iOption == Mute_GunSounds)
		{
			CheckShotgunShotHook();
		}

		char sCookie[16];
		IntToString(gI_Settings[param1], sCookie, 16);
		SetClientCookie(param1, gH_SettingsCookie, sCookie);

		Command_Sounds(param1, 0);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}
//----------------------------------------------------

//-----------------------EVENTS-----------------------
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	gA_PlayEverywhereAmbients.Clear();

	int entity = INVALID_ENT_REFERENCE;

	while((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
	{
		if(GetEntProp(entity, Prop_Data, "m_spawnflags") == 1)
		{
			gA_PlayEverywhereAmbients.Push(EntIndexToEntRef(entity));
		}
	}
}
//----------------------------------------------------

// Credits to GoD-Tony for everything related to stopping gun sounds
public Action CSS_Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gB_ShouldHookShotgunShot)
	{
		return Plugin_Continue;
	}

	// Check which clients need to be excluded.
	int newClients[MAXPLAYERS+1];
	int count = 0;

	for(int i = 0; i < numClients; i++)
	{
		int iClient = Players[i];

		// player not muting gun sounds
		if(gI_Settings[iClient] & Mute_GunSounds == 0)
		{
			newClients[count] = iClient;
			count++;
		}
	}

	// No clients were excluded.
	if(count == numClients)
	{
		return Plugin_Continue;
	}
	// All clients were excluded and there is no need to broadcast.
	else if(count == 0)
	{
		return Plugin_Stop;
	}

	// Re-broadcast to clients that still need it.
	float vTemp[3];
	TE_Start("Shotgun Shot");
	TE_ReadVector("m_vecOrigin", vTemp);
	TE_WriteVector("m_vecOrigin", vTemp);
	TE_WriteFloat("m_vecAngles[0]", TE_ReadFloat("m_vecAngles[0]"));
	TE_WriteFloat("m_vecAngles[1]", TE_ReadFloat("m_vecAngles[1]"));
	TE_WriteNum("m_iWeaponID", TE_ReadNum("m_iWeaponID"));
	TE_WriteNum("m_iMode", TE_ReadNum("m_iMode"));
	TE_WriteNum("m_iSeed", TE_ReadNum("m_iSeed"));
	TE_WriteNum("m_iPlayer", TE_ReadNum("m_iPlayer"));
	TE_WriteFloat("m_fInaccuracy", TE_ReadFloat("m_fInaccuracy"));
	TE_WriteFloat("m_fSpread", TE_ReadFloat("m_fSpread"));
	TE_Send(newClients, count, delay);

	return Plugin_Stop;
}

public Action ConnectMuteAmbientTimer(Handle hTimer, any data)
{
	int client = GetClientFromSerial(data);

	if(!IsValidClient(client))
	{
		return;
	}

	for(int i = 0; i < gA_PlayEverywhereAmbients.Length; i++)
	{
		int entity = EntRefToEntIndex(gA_PlayEverywhereAmbients.Get(i));

		if(entity != INVALID_ENT_REFERENCE)
		{
			char sSound[PLATFORM_MAX_PATH];
			GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, PLATFORM_MAX_PATH);
			EmitSoundToClient(client, sSound, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);

			if(gI_Settings[client] & Debug)
			{
				PrintToChat(client, "[Debug] Ambient Blocked (%s)", sSound);
			}
		}
	}
}

void CheckShotgunShotHook()
{
	bool bShouldHook = false;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
		{
			continue;
		}

		if(gI_Settings[i] & Mute_GunSounds)
		{
			bShouldHook = true;
			break;
		}
	}

	// Fake (un)hook because toggling actual hooks will cause server instability.
	gB_ShouldHookShotgunShot = bShouldHook;
}

bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}