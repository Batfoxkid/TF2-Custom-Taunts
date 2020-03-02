#pragma semicolon 1

#include <sourcemod>
#include <tf2_stocks>
#include <tf2attributes>
#include <tf2items>

#pragma newdecls required

#define PLUGIN_VERSION "0.1.0"

#define FAR_FUTURE		100000000.0
#define MAX_SOUND_LENGTH	80
#define MAX_MODEL_LENGTH	128
#define MAX_MATERIAL_LENGTH	128
#define MAX_ENTITY_LENGTH	48
#define MAX_EFFECT_LENGTH	48
#define MAX_ATTACHMENT_LENGTH	48
#define MAX_ICON_LENGTH		48
#define MAX_INFO_LENGTH		128
#define HEX_OR_DEC_LENGTH	12
#define MAX_ATTRIBUTE_LENGTH	256
#define MAX_CONDITION_LENGTH	256
#define MAX_CLASSNAME_LENGTH	64
#define MAX_PLUGIN_LENGTH	64
#define MAX_ITEM_LENGTH		48
#define MAX_DESC_LENGTH		256
#define MAX_TITLE_LENGTH	192
#define MAX_NUM_LENGTH		5
#define VOID_ARG		-1

#define MAXTF2PLAYERS	36
#define TAUNT		Client[client].Taunt
#define MODELS		Taunt[Taunts].Models
#define SOUNDS		Models[Taunts][Taunt[Taunts].Models].Sounds

#define CONFIG_PATH	"configs/customtaunts.cfg"

#define MAXNAME		64
#define MAXTAUNTS	64
#define MAXSOUNDS	12
#define MAXMODELS	12

enum struct SoundEnum
{
	char Replace[PLATFORM_MAX_PATH];
	char New[PLATFORM_MAX_PATH];
}

enum struct ModelEnum
{
	char Replace[PLATFORM_MAX_PATH];
	char Sound[PLATFORM_MAX_PATH];
	char New[PLATFORM_MAX_PATH];
	float Duration;
	float Speed;
	int Sounds;
	int Index;
	TFClassType Class;
}

enum struct TauntEnum
{
	char Name[MAXNAME];
	int Models;
	int Admin;
}

enum struct ClientEnum
{
	float EndAt;
	int Taunt;
	int Model;
}

SoundEnum Sound[MAXTAUNTS][MAXMODELS][MAXSOUNDS];
ModelEnum Models[MAXTAUNTS][MAXMODELS];
TauntEnum Taunt[MAXTAUNTS];
ClientEnum Client[MAXTF2PLAYERS];
Handle SDKPlayTaunt;
int Taunts;
bool Enabled;

public Plugin myinfo =
{
	name		=	"TF2: Custom Taunts",
	author		=	"Batfoxkid",
	description	=	"Custom taunts for players to use",
	version		=	PLUGIN_VERSION
};

// SourceMod Events

public void OnPluginStart()
{
	GameData gameData = new GameData("tf2.tauntem");
	if(gameData == INVALID_HANDLE)
		SetFailState("Failed to find gamedata/tf2.tauntem.txt.");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	SDKPlayTaunt = EndPrepSDKCall();
	if(SDKPlayTaunt == INVALID_HANDLE)
		SetFailState("Failed to create call: CTFPlayer::PlayTauntSceneFromItem.");

	delete gameData;

	AddNormalSoundHook(HookSound);

	RegConsoleCmd("sm_taunt", CommandMenu, "Open a menu of taunts");
	RegConsoleCmd("sm_taunts", CommandList, "View a list of taunt ids");
	HookEvent("post_inventory_application", OnPlayerSpawn, EventHookMode_Pre);
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Pre);

	LoadTranslations("common.phrases");

	for(int i; i<MAXTF2PLAYERS; i++)
	{
		Client[i].Taunt = -1;
	}
}

public void OnConfigsExecuted()
{
	char buffer[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, buffer, PLATFORM_MAX_PATH, CONFIG_PATH);
	if(!FileExists(buffer))
		SetFailState("Failed to find %s.", CONFIG_PATH);

	KeyValues kv = new KeyValues("customtaunts");
	if(!kv.ImportFromFile(buffer))
		SetFailState("Failed to import %s.", CONFIG_PATH);

	Taunts = 0;
	if(!kv.GotoFirstSubKey())
		SetFailState("Incorrect format on %s.", CONFIG_PATH);

	do
	{
		kv.GetSectionName(Taunt[Taunts].Name, MAXNAME);
		kv.GetString("admin", buffer, PLATFORM_MAX_PATH);
		Taunt[Taunts].Admin = buffer[0] ? ReadFlagString(buffer) : 0;
		if(!kv.GotoFirstSubKey())
		{
			LogError("Taunt '%s' has no models listed.", Taunt[Taunts].Name);
			continue;
		}

		MODELS = 0;
		do
		{
			kv.GetSectionName(Models[Taunts][MODELS].Replace, PLATFORM_MAX_PATH);
			Models[Taunts][MODELS].Index = kv.GetNum("index");
			if(!Models[Taunts][MODELS].Index)
			{
				LogError("Taunt '%s' with model '%s' has an invalid index.", Taunt[Taunts].Name, Models[Taunts][MODELS].Replace);
				continue;
			}

			bool all = StrEqual(Models[Taunts][MODELS].Replace, "any", false);
			if(!all)
			{
				Models[Taunts][MODELS].Class = TF2_GetClass(Models[Taunts][MODELS].Replace);
				if(Models[Taunts][MODELS].Class != TFClass_Unknown)
					all = true;
			}

			if(!all)
			{
				kv.GetString("model", Models[Taunts][MODELS].New, PLATFORM_MAX_PATH);
				if(!Models[Taunts][MODELS].New[0])
				{
				}
				else if(StrEqual(Models[Taunts][MODELS].New, Models[Taunts][MODELS].Replace, false))
				{
					Models[Taunts][MODELS].New[0] = 0;
				}
				else if(FileExists(Models[Taunts][MODELS].New, true))
				{
					PrecacheModel(Models[Taunts][MODELS].New, true);
				}
				else
				{
					LogError("Taunt '%s' with model '%s' does not exist.", Taunt[Taunts].Name, Models[Taunts][MODELS].Replace);
					Models[Taunts][MODELS].New[0] = 0;
				}
			}
			else
			{
				Models[Taunts][MODELS].Replace[0] = 0;
				Models[Taunts][MODELS].New[0] = 0;
			}

			kv.GetString("sound", Models[Taunts][MODELS].Sound, PLATFORM_MAX_PATH);
			FormatEx(buffer, PLATFORM_MAX_PATH, "sound/%s", Models[Taunts][MODELS].Sound);
			if(!Models[Taunts][MODELS].Sound[0])
			{
			}
			else if(FileExists(buffer, true))
			{
				PrecacheSound(Models[Taunts][MODELS].New, true);
			}
			else
			{
				LogError("Taunt '%s' with sound '%s' does not exist.", Taunt[Taunts].Name, Models[Taunts][MODELS].Sound);
				Models[Taunts][MODELS].Sound[0] = 0;
			}

			Models[Taunts][MODELS].Speed = kv.GetFloat("speed", 1.0);
			Models[Taunts][MODELS].Duration = kv.GetFloat("duration");

			SOUNDS = 0;
			if(!kv.GotoFirstSubKey())
			{
				MODELS++;
				continue;
			}

			do
			{
				kv.GetSectionName(Sound[Taunts][MODELS][SOUNDS].Replace, PLATFORM_MAX_PATH);
				kv.GetString("sound", Sound[Taunts][MODELS][SOUNDS].New, PLATFORM_MAX_PATH, "vo/null.mp3");
				SOUNDS++;
			} while(SOUNDS<MAXSOUNDS && kv.GotoNextKey());
			MODELS++;
			kv.GoBack();
		} while(MODELS<MAXMODELS && kv.GotoNextKey());
		kv.GoBack();

		if(!MODELS)
		{
			LogError("Taunt '%s' has no models correctly setup.", Taunt[Taunts].Name);
			continue;
		}

		Taunts++;
	} while(Taunts<MAXTAUNTS && kv.GotoNextKey());

	delete kv;

	if(!Taunts)
		SetFailState("Incorrect format on %s.", CONFIG_PATH);
}

public void OnPluginEnd()
{
	for(int i=1; i<=MaxClients; i++)
	{
		if(IsValidClient(i))
			EndTaunt(i, true);
	}
}

// Game Events

public void OnClientPostAdminCheck(int client)
{
	Client[client].EndAt = 0.0;
	Client[client].Taunt = -1;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(condition == TFCond_Taunting)
		EndTaunt(client, false);
}

public Action OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(IsValidClient(client))
		EndTaunt(client, true);

	return Plugin_Continue;
}

public Action OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if(IsValidClient(client))
		EndTaunt(client, false);

	return Plugin_Continue;
}

public void OnGameFrame()
{
	if(!Enabled)
		return;

	float gameTime = GetGameTime();
	Enabled = false;
	for(int client=1; client<=MaxClients; client++)
	{
		if(!IsValidClient(client) || !Client[client].EndAt)
			continue;

		Enabled = true;
		if(Client[client].EndAt < gameTime)
			EndTaunt(client, true);
	}
}

public Action HookSound(int clients[MAXPLAYERS], int &numClients, char sound[PLATFORM_MAX_PATH], int &client, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(!IsValidClient(client) || !TF2_IsPlayerInCondition(client, TFCond_Taunting) || Client[client].Taunt<0 || Client[client].Model<0)
		return Plugin_Continue;

	for(int i; i<Models[Client[client].Taunt][Client[client].Model].Sounds; i++)
	{
		if(StrContains(Sound[Client[client].Taunt][Client[client].Model][i].Replace, sound, false))
			continue;

		if(!Sound[Client[client].Taunt][Client[client].Model][i].New[0])
			return Plugin_Stop;

		strcopy(sound, PLATFORM_MAX_PATH, Sound[Client[client].Taunt][Client[client].Model][i].New);
		return Plugin_Changed;
	}
	return Plugin_Continue;
}

// Taunt Events

void EndTaunt(int client, bool remove)
{
	Client[client].EndAt = 0.0;
	TF2Attrib_SetByDefIndex(client, 201, 1.0);
	if(remove && IsPlayerAlive(client))
		TF2_RemoveCondition(client, TFCond_Taunting);

	if(Client[client].Taunt < 0)
		return;

	if(Client[client].Model < 0)
	{
		Client[client].Taunt = -1;
		return;
	}

	if(Models[Client[client].Taunt][Client[client].Model].Sound[0])
		StopSound(client, SNDCHAN_AUTO, Models[Client[client].Taunt][Client[client].Model].Sound);

	if(!Models[Client[client].Taunt][Client[client].Model].Replace[0])
	{
		Client[client].Taunt = -1;
		return;
	}

	SetVariantString(Models[Client[client].Taunt][Client[client].Model].Replace);
	AcceptEntityInput(client, "SetCustomModel");
	SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
	Client[client].Taunt = -1;
}

bool StartTaunt(int client, int taunt, int model)
{
	static Handle item;
	if(item == INVALID_HANDLE)
	{
		item = TF2Items_CreateItem(OVERRIDE_ALL|PRESERVE_ATTRIBUTES|FORCE_GENERATION);
		TF2Items_SetClassname(item, "tf_wearable_vm");
		TF2Items_SetQuality(item, 6);
		TF2Items_SetLevel(item, 1);
	}

	TF2Items_SetItemIndex(item, Models[taunt][model].Index);
	int entity = TF2Items_GiveNamedItem(client, item);
	if(!IsValidEntity(entity))
	{
		LogError("Couldn't create entity for taunt");
		return false;
	}

	int offset = GetEntSendPropOffs(entity, "m_Item", true);
	if(offset <= 0)
	{
		LogError("Couldn't find m_Item for taunt item");
		return false;
	}

	Address address = GetEntityAddress(entity);
	if(address == Address_Null)
	{
		LogError("Couldn't find entity address for taunt item");
		return false;
	}

	if(Models[taunt][model].Duration > 0)
	{
		TF2Attrib_SetByDefIndex(client, 201, 0.01);	// Extends the taunt's lifetime
	}
	else
	{
		TF2Attrib_SetByDefIndex(client, 201, Models[taunt][model].Speed);
	}

	address += view_as<Address>(offset);
	if(!SDKCall(SDKPlayTaunt, client, address))
	{
		AcceptEntityInput(entity, "Kill");
		TF2Attrib_SetByDefIndex(client, 201, 1.0);
		return true;
	}
	AcceptEntityInput(entity, "Kill");

	if(Models[taunt][model].New[0])
	{
		SetVariantString(Models[taunt][model].New);
		AcceptEntityInput(client, "SetCustomModel");
		SetEntProp(client, Prop_Send, "m_bUseClassAnimations", 1);
	}

	if(Models[taunt][model].Sound[0])
		EmitSoundToAll(Models[taunt][model].Sound, client);

	if(Models[taunt][model].Duration > 0)
		TF2Attrib_SetByDefIndex(client, 201, Models[taunt][model].Speed);

	Client[client].Taunt = taunt;
	Client[client].Model = model;

	Client[client].EndAt = Models[taunt][model].Duration>0 ? Models[taunt][model].Duration+GetGameTime() : 0.0;
	Enabled = true;
	return false;
}

// Menu Events

public Action CommandMenu(int client, int args)
{
	static char buffer[MAX_TARGET_LENGTH];
	if(!args && client)
	{
		if(!IsPlayerAlive(client) || TF2_IsPlayerInCondition(client, TFCond_Taunting))
			return Plugin_Handled;

		Menu menu = new Menu(CommandMenuH);
		menu.SetTitle("Taunt Menu\n ");

		for(int i; i<Taunts; i++)
		{
			if(!CheckTauntAccess(client, i) || CheckTauntModel(client, i)==-1)
				continue;

			IntToString(i, buffer, sizeof(buffer));
			menu.AddItem(buffer, Taunt[i].Name);
		}

		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
		return Plugin_Handled;
	}

	if(client && !CheckCommandAccess(client, "customtaunts_targetting", ADMFLAG_CHEATS))
	{
		if(args != 1)
		{
			ReplyToCommand(client, "[SM] Usage: sm_taunt <tauntid>");
			return Plugin_Handled;
		}

		GetCmdArg(1, buffer, sizeof(buffer));
		int taunt = StringToInt(buffer);
		if((!taunt && !StrEqual(buffer, "0")))
		{
			for(int i; i<Taunts; i++)
			{
				if(StrContains(buffer, Taunt[i].Name, false))
					continue;

				taunt = i;
				break;
			}
		}

		if(!CheckTauntAccess(client, taunt))
		{
			ReplyToCommand(client, "[SM] Invalid Taunt ID");
			return Plugin_Handled;
		}

		int model = CheckTauntModel(client, taunt);
		if(model == -1)
		{
			ReplyToCommand(client, "[SM] Invalid Class or Model");
			return Plugin_Handled;
		}

		StartTaunt(client, taunt, model);
		return Plugin_Handled;
	}

	if(args != 2)
	{
		ReplyToCommand(client, "[SM] Usage: sm_taunt <client> <tauntid>");
		return Plugin_Handled;
	}

	GetCmdArg(2, buffer, sizeof(buffer));
	int taunt = StringToInt(buffer);
	if((!taunt && !StrEqual(buffer, "0")))
	{
		for(int i; i<Taunts; i++)
		{
			if(StrContains(buffer, Taunt[i].Name, false))
				continue;

			taunt = i;
			break;
		}
	}

	if(!CheckTauntAccess(client, taunt))
	{
		ReplyToCommand(client, "[SM] Invalid Taunt ID");
		return Plugin_Handled;
	}

	GetCmdArg(1, buffer, sizeof(buffer));
	static char targetName[MAX_TARGET_LENGTH];
	int targets[MAXTF2PLAYERS], matches;
	bool tn_is_ml;

	if((matches=ProcessTargetString(buffer, client, targets, sizeof(targets), COMMAND_FILTER_ALIVE, targetName, sizeof(targetName), tn_is_ml)) < 1)
	{
		ReplyToTargetError(client, matches);
		return Plugin_Handled;
	}

	for(int target; target<matches; target++)
	{
		if(IsClientSourceTV(targets[target]) || IsClientReplay(targets[target]))
			continue;

		int model = CheckTauntModel(targets[target], taunt);
		if(model != -1)
			StartTaunt(targets[target], taunt, model);
	}
				
	if(tn_is_ml)
	{
		ShowActivity2(client, "[SM] ", "Forced taunt on %t", targetName);
	}
	else
	{
		ShowActivity2(client, "[SM] ", "Forced taunt on %s", targetName);
	}
	return Plugin_Handled;
}

public int CommandMenuH(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			static char buffer[8];
			menu.GetItem(choice, buffer, sizeof(buffer));
			int taunt = StringToInt(buffer);
			if(!CheckTauntAccess(client, taunt))
			{
				ReplyToCommand(client, "[SM] You no longer have access to this taunt");
				return;
			}

			int model = CheckTauntModel(client, taunt);
			if(model == -1)
			{
				ReplyToCommand(client, "[SM] You no longer use this taunt");
				return;
			}

			if(StartTaunt(client, taunt, model))
				CommandMenu(client, 0);
		}
	}
}

public Action CommandList(int client, int args)
{
	for(int i; i<Taunts; i++)
	{
		if(CheckTauntAccess(client, i))
			PrintToConsole(client, "%i - %s", i, Taunt[i].Name);
	}

	if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
		ReplyToCommand(client, "[SM] %t", "See console for output");
}

// Stocks

stock bool CheckTauntAccess(int client, int taunt)
{
	if(taunt<0 || taunt>=MAXTAUNTS)
		return false;

	if(Taunt[taunt].Admin && !CheckCommandAccess(client, "customtaunts_all", Taunt[taunt].Admin, true))
		return false;

	return true;
}

stock int CheckTauntModel(int client, int taunt)
{
	static char model[PLATFORM_MAX_PATH];
	GetClientModel(client, model, PLATFORM_MAX_PATH);
	TFClassType class = TF2_GetPlayerClass(client);
	for(int i; i<Taunt[taunt].Models; i++)
	{
		if(Models[taunt][i].Class != TFClass_Unknown)
		{
			if(Models[taunt][i].Class == class)
				return i;

			continue;
		}

		if(!Models[taunt][i].Replace[0])
			return i;

		if(StrEqual(Models[taunt][i].Replace, model, false))
			return i;
	}
	return -1;
}

stock bool IsValidClient(int client)
{
	if(client<=0 || client>MaxClients)
		return false;

	if(!IsClientInGame(client))
		return false;

	if(GetEntProp(client, Prop_Send, "m_bIsCoaching"))
		return false;

	if(IsClientSourceTV(client) || IsClientReplay(client))
		return false;

	return true;
}

#file "TF2: Custom Taunts"