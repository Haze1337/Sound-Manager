#include <sourcemod>
#include <clientprefs>

#undef REQUIRE_EXTENSIONS
#include <dhooks>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "Sound Manager",
	author = "Haze",
	description = "",
	version = "1.0",
	url = ""
}

#define Mute_SoundScapes				(1 << 0)
#define Mute_AmbientSounds				(1 << 1)
#define Mute_GunSounds					(1 << 2)
#define Mute_TriggerSounds				(1 << 3)
#define Mute_AllPackets					(1 << 4)
#define Debug							(1 << 5)

//Player settings
int gI_Settings[MAXPLAYERS+1];

//Debug
int gI_LastSoundScape[MAXPLAYERS+1];

//Cookie
Handle gH_SettingsCookie = null;

//Dhooks
Handle gH_AcceptInput = null;

//For Sounds
bool gB_ShouldHookStotgunShot = false;
ArrayList gA_PlayEverywhereAmbients = null;
ArrayList gA_AmbientEntities = null;

//Late Load
bool gB_LateLoad = false;

//-----------------------FORWARDS-------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_LateLoad = late;
}

public void OnPluginStart()
{
	//Commands
	RegConsoleCmd("sm_snd", Command_Sounds, "");
	RegConsoleCmd("sm_sound", Command_Sounds, "");
	RegConsoleCmd("sm_sounds", Command_Sounds, "");
	RegConsoleCmd("sm_music", Command_Sounds, "");
	RegConsoleCmd("sm_stopmusic", Command_Sounds, "");
	RegConsoleCmd("sm_stopsounds", Command_Sounds, "");
	
	//Cookie
	gH_SettingsCookie = RegClientCookie("sounds_setting", "Sound Manager Settings", CookieAccess_Protected);
	
	//ArrayList for ambient_generic's with spawnflags & 1 (play everywhere [1]) 
	gA_PlayEverywhereAmbients = new ArrayList(ByteCountToCells(4));
	
	//ArrayList for ambient_generic's
	gA_AmbientEntities = new ArrayList(ByteCountToCells(4));
	
	//Hook round_start
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
	
	//Dhooks
	HookSoundScapes();
	HookAcceptInput();
	
	//Sound Hooks
	AddNormalSoundHook(SoundHook_Normal);
	AddAmbientSoundHook(SoundHook_Ambient);
	AddTempEntHook("Shotgun Shot", CSS_Hook_ShotgunShot);
	
	//Late Load
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
			if(IsValidClient(i))
			{
				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
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
	CheckHooks();
}

public void OnClientCookiesCached(int client)
{
	gI_LastSoundScape[client] = -1;

	char sCookie[16];
	GetClientCookie(client, gH_SettingsCookie, sCookie, sizeof(sCookie));
	
	if(strlen(sCookie) == 0)
	{
		gI_Settings[client] = 0;
	}
	else
	{
		gI_Settings[client] = StringToInt(sCookie);
	}
	
	if((gI_Settings[client] & Mute_GunSounds) && gB_ShouldHookStotgunShot == false)
	{
		gB_ShouldHookStotgunShot = true;
	}
	
	if(gI_Settings[client] & Mute_AmbientSounds)
	{
		CreateTimer(1.0, Connect_MuteAmbient, GetClientSerial(client));
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
		SetFailState("Couldn't enable UpdateForPlayer detour.");
	}
}

//ss_update_t is a struct consisting of 3 int types, a vector, a float, and a bool 3*4+12+4+1 = 29
/*struct ss_update_t
{
	CBasePlayer 	*pPlayer;
	CEnvSoundscape	*pCurrentSoundscape;
	Vector			playerPosition;
	float			currentDistance;
	int				traceCount; 
	bool			bInRange;
};*/

/*
	pPlayer: 			0  | 	Size: 4
	pCurrentSoundscape: 4  | 	Size: 4
	playerPosition: 	8  | 	Size: 12
	currentDistance: 	20 | 	Size: 4
	traceCount: 		24 | 	Size: 4
	bInRange: 			28 | 	Size: 1
*/

//void CEnvSoundscape::UpdateForPlayer( ss_update_t &update )
public MRESReturn DHook_UpdateForPlayer(int pThis, Handle hParams)
{
	if(IsValidEdict(pThis))
	{
		int client = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_CBaseEntityPtr);

		DHookSetParamObjectPtrVar(hParams, 1, 4, ObjectValueType_CBaseEntityPtr, 0);
		
		if(gI_Settings[client] & Mute_SoundScapes)
		{
			SetEntProp(client, Prop_Data, "soundscapeIndex", 138);
			
			if((gI_Settings[client] & Debug) && gI_LastSoundScape[client] != 138 && GetEntProp(client, Prop_Data, "soundscapeIndex") == 138)
			{
				PrintToChat(client, "[Debug] SoundScape Blocked (%d)", pThis);
			}
			
			gI_LastSoundScape[client] = GetEntProp(client, Prop_Data, "soundscapeIndex");
			return MRES_Supercede;
		}
		else
		{
			gI_LastSoundScape[client] = GetEntProp(client, Prop_Data, "soundscapeIndex");
			return MRES_ChangedHandled;
		}
	}
	return MRES_Ignored;
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
	if(offset == 0) 
	{
		SetFailState("Failed to load \"AcceptInput\", invalid offset.");
	}

	delete hGameData;

	gH_AcceptInput = DHookCreate(offset, HookType_Entity, ReturnType_Bool, ThisPointer_CBaseEntity, DHook_AcceptInput);
	DHookAddParam(gH_AcceptInput, HookParamType_CharPtr);
	DHookAddParam(gH_AcceptInput, HookParamType_CBaseEntity);
	DHookAddParam(gH_AcceptInput, HookParamType_CBaseEntity);
	DHookAddParam(gH_AcceptInput, HookParamType_Object, 20, DHookPass_ByVal|DHookPass_ODTOR|DHookPass_OCTOR|DHookPass_OASSIGNOP); //varaint_t is a union of 12 (float[3]) plus two int type params 12 + 8 = 20
	DHookAddParam(gH_AcceptInput, HookParamType_Int);
}

// virtual bool AcceptInput( const char *szInputName, CBaseEntity *pActivator, CBaseEntity *pCaller, variant_t Value, int outputID );
public MRESReturn DHook_AcceptInput(int pThis, Handle hReturn, Handle hParams)
{
	if(!DHookIsNullParam(hParams, 2) && !DHookIsNullParam(hParams, 3))
	{
		char sParameter[128];
		DHookGetParamObjectPtrString(hParams, 4, 0, ObjectValueType_String, sParameter, sizeof(sParameter));

		if(StrContains(sParameter, "play ") != -1)
		{
			int client = DHookGetParam(hParams, 2);
			if(gI_Settings[client] & Mute_TriggerSounds)
			{
				if(gI_Settings[client] & Debug)
				{
					PrintToChat(client, "[Debug] Output Blocked (%s)", sParameter);
				}
				DHookSetReturn(hReturn, false);
				return MRES_Supercede;
			}
		}
		//PrintToChatAll("Activator: \x04%d\x01 \x04%s\x01", client, sParameter);
	}

	return MRES_Ignored;
}
//-----------------------------------------------------

//------------------------MENU-------------------------
public Action Command_Sounds(int client, int args)
{
	Menu menu = new Menu(MenuHandler_Sounds);
	menu.SetTitle("Sound Manager");

	char sDisplay[64];
	FormatEx(sDisplay, sizeof(sDisplay), "Soundscapes: [%s]", gI_Settings[client] & Mute_SoundScapes ? "Muted" : "On");
	menu.AddItem("soundscapes", sDisplay);
	
	FormatEx(sDisplay, sizeof(sDisplay), "Ambient Sounds: [%s]", gI_Settings[client] & Mute_AmbientSounds ? "Muted" : "On");
	menu.AddItem("ambient", sDisplay);
	
	FormatEx(sDisplay, sizeof(sDisplay), "Gun Sounds: [%s]", gI_Settings[client] & Mute_GunSounds ? "Muted" : "On");
	menu.AddItem("gun", sDisplay);
	
	FormatEx(sDisplay, sizeof(sDisplay), "Trigger Sounds: [%s]", gI_Settings[client] & Mute_TriggerSounds ? "Muted" : "On");
	menu.AddItem("trigger", sDisplay);
	
	if(CheckCommandAccess(client, "soundmanager_debug", ADMFLAG_RCON))
	{
		FormatEx(sDisplay, sizeof(sDisplay), "Debug Prints: [%s]", gI_Settings[client] & Debug ? "Yes" : "No");
		menu.AddItem("debug", sDisplay);
	}
	
	FormatEx(sDisplay, sizeof(sDisplay), "Block All sound packets: [%s]", gI_Settings[client] & Mute_AllPackets ? "Yes" : "No");
	menu.AddItem("all", sDisplay);
	
	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

public int MenuHandler_Sounds(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "soundscapes"))
		{
			gI_Settings[param1] ^= Mute_SoundScapes;
		}
		else if(StrEqual(sInfo, "ambient"))
		{
			gI_Settings[param1] ^= Mute_AmbientSounds;
		}
		else if(StrEqual(sInfo, "gun"))
		{
			gI_Settings[param1] ^= Mute_GunSounds;
			CheckHooks();
		}
		else if(StrEqual(sInfo, "trigger"))
		{
			gI_Settings[param1] ^= Mute_TriggerSounds;
		}		
		else if(StrEqual(sInfo, "debug"))
		{
			gI_Settings[param1] ^= Debug;
		}
		else if(StrEqual(sInfo, "all"))
		{
			gI_Settings[param1] ^= Mute_AllPackets;
		}
		
		char sCookie[16];
		IntToString(gI_Settings[param1], sCookie, 16);
		SetClientCookie(param1, gH_SettingsCookie, sCookie);
		
		Command_Sounds(param1, 0);
	}

	else if(action == MenuAction_Cancel)
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
	gA_AmbientEntities.Clear();
	
	// Find all ambient sounds played by the map.
	char sSound[PLATFORM_MAX_PATH];
	int entity = INVALID_ENT_REFERENCE;
	
	while((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
	{
		int spawnflags = GetEntProp(entity, Prop_Data, "m_spawnflags");
		if(spawnflags == 1)
		{
			//PrintToServer("ambient_generic (%d): %d", entity, spawnflags);
			gA_PlayEverywhereAmbients.Push(EntIndexToEntRef(entity));
		}
		
		GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
		
		int len = strlen(sSound);
		if(len > 4 && (StrEqual(sSound[len-3], "mp3") || StrEqual(sSound[len-3], "wav")))
		{
			gA_AmbientEntities.Push(EntIndexToEntRef(entity));
		}
	}
}
//----------------------------------------------------

//--------------------CALLBACKS-----------------------
// Credits to GoD-Tony for everything related to stopping gun sounds
public Action CSS_Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gB_ShouldHookStotgunShot)
	{
		return Plugin_Continue;
	}
	
	// Check which clients need to be excluded.
	int newTotal = 0;
	int[] newClients = new int[MaxClients];
	
	for(int i = 0; i < numClients; i++)
	{
		int client = Players[i];
		
		if(!(gI_Settings[client] & Mute_GunSounds))
		{
			newClients[newTotal++] = client;
		}
	}
	
	// No clients were excluded.
	if(newTotal == numClients)
	{
		return Plugin_Continue;
	}
	// All clients were excluded and there is no need to broadcast.
	else if(newTotal == 0)
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
	TE_Send(newClients, newTotal, delay);
	
	return Plugin_Stop;
}

public Action Connect_MuteAmbient(Handle hTimer, any data)
{
	int client = GetClientFromSerial(data);
	
	if(IsValidClient(client))
	{
		char sSound[128];
		
		for(int i = 0; i < gA_PlayEverywhereAmbients.Length; i++)
		{
			int entity = EntRefToEntIndex(gA_PlayEverywhereAmbients.Get(i));
			
			if(entity != INVALID_ENT_REFERENCE)
			{
				GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
				EmitSoundToClient(client, sSound, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
				
				if(gI_Settings[client] & Debug)
				{
					PrintToChat(client, "[Debug] Ambient Blocked (%s)", sSound);
				}
			}
		}
	}
}

public Action Timer_MuteAmbient(Handle hTimer, any data)
{
	int entity = EntRefToEntIndex(data);
	
	if(entity != INVALID_ENT_REFERENCE)
	{
		char sSound[128];
		
		for(int client = 1; client <= MaxClients; client++)
		{
			if(IsValidClient(client))
			{
				if(gI_Settings[client] & Mute_AmbientSounds)
				{
					GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, sizeof(sSound));
					EmitSoundToClient(client, sSound, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);
					
					if(gI_Settings[client] & Debug)
					{
						PrintToChat(client, "[Debug] Ambient Blocked (%s)", sSound);
					}
				}
			}
		}
	}
}

public Action SoundHook_Ambient(char sample[PLATFORM_MAX_PATH], int &entity, float &volume, int &level, int &pitch, float pos[3], int &flags, float &delay)
{
	if(volume == 0.0)
	{
		return Plugin_Continue;
	}
	
	CreateTimer(0.1, Timer_MuteAmbient, EntIndexToEntRef(entity));

	return Plugin_Continue;
}
 
public Action SoundHook_Normal(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(volume == 0.0)
	{
		return Plugin_Continue;
	}
	
	if(IsValidEntity(entity) && IsValidEdict(entity))
	{
		char sClassname[64];
		GetEntityClassname(entity, sClassname, sizeof(sClassname));
		if(StrEqual(sClassname, "ambient_generic"))
		{
			return Plugin_Continue;
		}

		for(int i = 0; i < numClients; i++)
		{
			if(gI_Settings[clients[i]] & Mute_AllPackets)
			{
				if(gI_Settings[clients[i]] & Debug)
				{
					PrintToChat(clients[i], "[Debug] Sound Blocked (%s)", sample);
				}
				// Remove the client from the array.
				for(int j = i; j < numClients-1; j++)
				{
					clients[j] = clients[j+1];
				}
				numClients--;
				i--;
			}
		}
		
		return (numClients > 0) ? Plugin_Changed : Plugin_Stop;
	}
	
	return Plugin_Continue;
}
//----------------------------------------------------

void CheckHooks()
{
	bool bShouldHook = false;
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			if(gI_Settings[i] & Mute_GunSounds)
			{
				bShouldHook = true;
				break;
			}
		}
	}
	
	// Fake (un)hook because toggling actual hooks will cause server instability.
	gB_ShouldHookStotgunShot = bShouldHook;
}

bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}