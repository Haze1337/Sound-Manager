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
	version = "1.0.1",
	url = ""
}

#define Mute_Soundscapes				(1 << 0)
#define Mute_AmbientSounds				(1 << 1)
#define Mute_GunSounds					(1 << 2)
#define Mute_TriggerSounds				(1 << 3)
#define Mute_NormalSounds				(1 << 4)
#define Debug							(1 << 5)
#define Mute_HurtSounds					(1 << 6)

// Engine
EngineVersion gEV_Type = Engine_Unknown;

// Player settings
int gI_Settings[MAXPLAYERS+1];
bool gB_AlreadyMuted[MAXPLAYERS+1];

// Debug
int gI_LastSoundscape[MAXPLAYERS+1];

// Cookie
Handle gH_SettingsCookie = null;

// Dhooks
Handle gH_AcceptInput = null;
Handle gH_GetPlayerSlot = null;

// Other
int gI_SilentSoundScape = 0;
int gI_AmbientOffset = 0;
bool gB_ShouldHookShotgunShot = false;
ArrayList gA_LoopingAmbients = null;
bool gB_EntitiesFound = false;

// Late Load
bool gB_LateLoad = false;

//-----------------------FORWARDS-------------------------
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_LateLoad = late;
}

// CSS: 138: port.LightHum2
// CSGO: 199: port.LightHum2
public void OnPluginStart()
{
	gEV_Type = GetEngineVersion();
	if(gEV_Type == Engine_CSS)
	{
		gI_SilentSoundScape = 138;
		gI_AmbientOffset = 85;
	}
	else if(gEV_Type == Engine_CSGO)
	{
		gI_SilentSoundScape = 199;
		gI_AmbientOffset = 89;
	}
	else
	{
		SetFailState("This plugin is only supported for CSS and CSGO.");
	}

	// Commands
	RegConsoleCmd("sm_snd", Command_Sounds);
	RegConsoleCmd("sm_sound", Command_Sounds);
	RegConsoleCmd("sm_sounds", Command_Sounds);
	RegConsoleCmd("sm_music", Command_Sounds);
	RegConsoleCmd("sm_stopmusic", Command_Sounds);
	RegConsoleCmd("sm_stopsounds", Command_Sounds);

	// Cookie
	gH_SettingsCookie = RegClientCookie("sound_settings", "Sound Manager Settings", CookieAccess_Protected);

	gA_LoopingAmbients = new ArrayList(ByteCountToCells(4));

	// Hook round_start
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);

	// Dhooks
	LoadDhooks();

	// Sound Hook
	AddTempEntHook("Shotgun Shot", Hook_ShotgunShot);
	AddNormalSoundHook(NormalSoundHook);

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
	gB_AlreadyMuted[client] = false;
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
}

public Action OnPlayerRunCmd(int client)
{
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	if(gI_Settings[client] & Mute_AmbientSounds == 0)
	{
		return Plugin_Continue;
	}

	if(gB_AlreadyMuted[client])
	{
		return Plugin_Continue;
	}

	if(!gB_EntitiesFound)
	{
		return Plugin_Continue;
	}

	for(int i = 0; i < gA_LoopingAmbients.Length; i++)
	{
		int entity = EntRefToEntIndex(gA_LoopingAmbients.Get(i));

		if(entity != INVALID_ENT_REFERENCE)
		{
			char sSound[PLATFORM_MAX_PATH];
			GetEntPropString(entity, Prop_Data, "m_iszSound", sSound, PLATFORM_MAX_PATH);
			EmitSoundToClient(client, sSound, entity, SNDCHAN_STATIC, SNDLEVEL_NONE, SND_STOP, 0.0, SNDPITCH_NORMAL, _, _, _, true);

			if(gI_Settings[client] & Debug)
			{
				PrintToChat(client, "[Debug] Ambient Muted (%s)", sSound);
			}
		}
	}

	gB_AlreadyMuted[client] = true;
	
	return Plugin_Continue;
}
//-------------------------------------------------------------

void LoadDhooks()
{
	Handle hGameData = LoadGameConfigFile("SoundManager.games");
	if(!hGameData)
	{
		SetFailState("Failed to load SoundManager gamedata.");
	}

	HookSoundscapes(hGameData);
	HookAcceptInput(hGameData);
	HookSendSound(hGameData);

	delete hGameData;
}

//-------------------------SOUNDSCAPES-------------------------
void HookSoundscapes(Handle hGameData)
{
	Handle hFunction = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity); 
	DHookSetFromConf(hFunction, hGameData, SDKConf_Signature, "CEnvSoundscape::UpdateForPlayer");
	DHookAddParam(hFunction, HookParamType_ObjectPtr);

	if(!DHookEnableDetour(hFunction, false, DHook_UpdateForPlayer))
	{
		SetFailState("Couldn't enable CEnvSoundscape::UpdateForPlayer detour.");
	}
}

/* struct ss_update_t
{
    CBasePlayer       *pPlayer;             Offset: 0  | Size: 4
    CEnvSoundscape    pCurrentSoundscape;   Offset: 4  | Size: 4
    Vector            playerPosition;       Offset: 8  | Size: 12
    float             currentDistance;      Offset: 20 | Size: 4
    int               traceCount;           Offset: 24 | Size: 4
    bool              bInRange;             Offset: 28 | Size: 4
};
*/

//void CEnvSoundscape::UpdateForPlayer( ss_update_t &update )
public MRESReturn DHook_UpdateForPlayer(int pThis, Handle hParams)
{
	int client = DHookGetParamObjectPtrVar(hParams, 1, 0, ObjectValueType_CBaseEntityPtr);

	MRESReturn ret = MRES_Ignored;

	if(gI_Settings[client] & Mute_Soundscapes)
	{
		SetEntProp(client, Prop_Data, "soundscapeIndex", gI_SilentSoundScape);

		if((gI_Settings[client] & Debug)
			&& gI_LastSoundscape[client] != gI_SilentSoundScape
			&& GetEntProp(client, Prop_Data, "soundscapeIndex") == gI_SilentSoundScape)
		{
			PrintToChat(client, "[Debug] Soundscape Blocked");
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
void HookAcceptInput(Handle hGameData)
{
	int offset = GameConfGetOffset(hGameData, "AcceptInput");

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
	if(DHookIsNullParam(hParams, 2))
	{
		return MRES_Ignored;
	}

	int client = DHookGetParam(hParams, 2);

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
void HookSendSound(Handle hGameData)
{
	Handle hFunction = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Address); 
	DHookSetFromConf(hFunction, hGameData, SDKConf_Signature, "CGameClient::SendSound");
	DHookAddParam(hFunction, HookParamType_ObjectPtr);
	DHookAddParam(hFunction, HookParamType_Bool);

	if(!DHookEnableDetour(hFunction, false, DHook_SendSound))
	{
		SetFailState("Couldn't enable CGameClient::SendSound detour.");
	}

	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseClient::GetPlayerSlot");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	gH_GetPlayerSlot = EndPrepSDKCall();

	if(gH_GetPlayerSlot == null)
	{
		SetFailState("Could not initialize call to CBaseClient::GetPlayerSlot.");
	}
}

// CSS:
/* struct SoundInfo_t
{
    int             nSequenceNumber;   Offset: 0  | Size: 4
    int             nEntityIndex;      Offset: 4  | Size: 4
    int             nChannel;          Offset: 8  | Size: 4
    const char      *pszName;          Offset: 12 | Size: 4
    Vector          vOrigin;           Offset: 16 | Size: 12
    Vector          vDirection;        Offset: 28 | Size: 12
    float           fVolume;           Offset: 40 | Size: 4
    soundlevel_t    Soundlevel;        Offset: 44 | Size: 4
    bool            bLooping;          Offset: 48 | Size: 1
    int             nPitch;            Offset: 52 | Size: 4
    int             nSpecialDSP;       Offset: 56 | Size: 4
    Vector          vListenerOrigin;   Offset: 60 | Size: 12
    int             nFlags;            Offset: 72 | Size: 4
    int             nSoundNum;         Offset: 76 | Size: 4
    float           fDelay;            Offset: 80 | Size: 4
    bool            bIsSentence;       Offset: 84 | Size: 1
    bool            bIsAmbient;        Offset: 85 | Size: 1
    int             nSpeakerEntity;    Offset: 88 | Size: 4
};*/

// CSGO:
/* struct SoundInfo_t
{
    Vector          vOrigin;           Offset: 0   | Size: 12
    Vector          vDirection         Offset: 12  | Size: 12
    Vector          vListenerOrigin;   Offset: 24  | Size: 12
    const char      *pszName;          Offset: 36  | Size: 4
    float           fVolume;           Offset: 40  | Size: 4
    float           fDelay;            Offset: 44  | Size: 4
    float           fTickTime;         Offset: 48  | Size: 4
    int             nSequenceNumber;   Offset: 52  | Size: 4
    int             nEntityIndex;      Offset: 56  | Size: 4
    int             nChannel;          Offset: 60  | Size: 4
    int             nPitch;            Offset: 64  | Size: 4
    int             nFlags;            Offset: 68  | Size: 4
    unsigned int    nSoundNum;         Offset: 72  | Size: 4
    int             nSpeakerEntity;    Offset: 76  | Size: 4
    int             nRandomSeed;       Offset: 80  | Size: 4
    soundlevel_t    Soundlevel;        Offset: 84  | Size: 4
    bool            bIsSentence;       Offset: 88  | Size: 1
    bool            bIsAmbient;        Offset: 89  | Size: 1
    bool            bLooping;          Offset: 90  | Size: 1
};*/

// void CGameClient::SendSound( SoundInfo_t &sound, bool isReliable )
public MRESReturn DHook_SendSound(Address pThis, Handle hParams)
{
	if(DHookGetParamObjectPtrVar(hParams, 1, 40, ObjectValueType_Float) == 0.0)
	{
		return MRES_Ignored;
	}

	Address pIClient = pThis + view_as<Address>(4);
	int client = view_as<int>(SDKCall(gH_GetPlayerSlot, pIClient)) + 1;

	if(!IsValidClient(client))
	{
		return MRES_Ignored;
	}

	bool bIsAmbient = DHookGetParamObjectPtrVar(hParams, 1, gI_AmbientOffset, ObjectValueType_Bool);

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
		if(gI_Settings[client] & Mute_NormalSounds)
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
	menu.SetTitle("Sound Manager\n ");

	if(gEV_Type == Engine_CSGO)
	{
		menu.AddItem("stopactive", "Stop Active Sounds\n ");
	}

	AddSettingItemToMenu(menu, client, "Soundscapes", Mute_Soundscapes);
	AddSettingItemToMenu(menu, client, "Ambient Sounds", Mute_AmbientSounds);
	AddSettingItemToMenu(menu, client, "Normal Sounds", Mute_NormalSounds);
	AddSettingItemToMenu(menu, client, "Trigger Sounds", Mute_TriggerSounds, true);
	AddSettingItemToMenu(menu, client, "Gun Sounds", Mute_GunSounds);
	AddSettingItemToMenu(menu, client, "Hurt Sounds", Mute_HurtSounds, true);

	if(CheckCommandAccess(client, "soundmanager_debug", ADMFLAG_RCON))
	{
		AddSettingItemToMenu(menu, client, "Debug Prints", Debug);
	}

	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

void AddSettingItemToMenu(Menu menu, int client, const char[] setting_name, int setting_id, bool new_line = false)
{
	char sDisplay[64];
	char sInfo[16];

	FormatEx(sDisplay, 64, "%s: [%s]", setting_name, gI_Settings[client] & setting_id ? "Muted" : "On");
	if(new_line)
	{
		StrCat(sDisplay, 64, "\n ");
	}
	IntToString(setting_id, sInfo, 16);
	menu.AddItem(sInfo, sDisplay);
}

public int MenuHandler_Sounds(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(gEV_Type == Engine_CSGO)
		{
			if(StrEqual(sInfo, "stopactive"))
			{
				ClientCommand(param1, "playgamesound Music.StopAllExceptMusic");
				ClientCommand(param1, "playgamesound Music.StopAllMusic");
				Command_Sounds(param1, 0);
				return 0;
			}
		}

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
	gB_EntitiesFound = false;
	gA_LoopingAmbients.Clear();

	int entity = INVALID_ENT_REFERENCE;

	while((entity = FindEntityByClassname(entity, "ambient_generic")) != INVALID_ENT_REFERENCE)
	{
		if(GetEntProp(entity, Prop_Data, "m_fLooping") == 1)
		{
			gA_LoopingAmbients.Push(EntIndexToEntRef(entity));
		}
	}
	gB_EntitiesFound = true;
}
//----------------------------------------------------

// Credits to GoD-Tony for everything related to stopping gun sounds
public Action Hook_ShotgunShot(const char[] te_name, const int[] Players, int numClients, float delay)
{
	if(!gB_ShouldHookShotgunShot)
	{
		return Plugin_Continue;
	}

	// Check which clients need to be excluded.
	int newClients[MAXPLAYERS+1];
	int count = FilterClientsWithSettingOn(Mute_GunSounds, numClients, Players, newClients);

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

public Action NormalSoundHook(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(StrEqual(sample, "player/damage1.wav")
		|| StrEqual(sample, "player/damage2.wav")
		|| StrEqual(sample, "player/damage3.wav"))
	{
		int newClients[MAXPLAYERS];
		int count = FilterClientsWithSettingOn(Mute_HurtSounds, numClients, clients, newClients);

		if(count != numClients)
		{
			clients = newClients;
			numClients = count;
			return Plugin_Changed;
		}
	}

	return Plugin_Continue;
}

// returns count of players with enabled sound
int FilterClientsWithSettingOn(int setting_id, int numClients, const int[] input_players, int[] output_players)
{
	int count = 0;

	for(int i = 0; i < numClients; i++)
	{
		int iClient = input_players[i];

		// player not muting gun sounds
		if(gI_Settings[iClient] & setting_id == 0)
		{
			output_players[count] = iClient;
			count++;
		}
	}

	return count;
}

bool IsValidClient(int client)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client));
}
