#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>
#include <tf2items>
#include <tf2attributes>
#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION			"1"
#define PLUGIN_VERSION_REVISION	"custom"
#define PLUGIN_VERSION_FULL		PLUGIN_VERSION ... "." ... PLUGIN_VERSION_REVISION

#define FILE_TAUNTS		"configs/custom_taunts/taunts.cfg"

enum struct SoundEnum
{
	char Match[PLATFORM_MAX_PATH];
	char Replace[PLATFORM_MAX_PATH];

	void Setup(KeyValues kv)
	{
		kv.GetSectionName(this.Match, sizeof(this.Match));
		kv.GetString("sound", this.Replace, sizeof(this.Replace), "vo/null.mp3");
	}
}

enum struct ModelEnum
{
	char Match[PLATFORM_MAX_PATH];
	ArrayList Sounds;
	
	char Replace[PLATFORM_MAX_PATH];
	char Sound[PLATFORM_MAX_PATH];
	float SoundVolume;
	int SoundLevel;
	bool BlockSound;
	bool BlockMusic;
	bool HideWeapon;
	bool HideCosmetic;
	bool BodyModel;
	float Duration;
	float Speed;
	int Index;
	TFClassType Class;

	void Setup(KeyValues kv)
	{
		kv.GetSectionName(this.Match, sizeof(this.Match));
		ReplaceString(this.Match, sizeof(this.Match), "\\", "/");

		this.Index = kv.GetNum("index");

		bool all = StrEqual(this.Match, "any", false);
		if(!all)
		{
			this.Class = TF2_GetClass(this.Match);
			if(this.Class != TFClass_Unknown)
				all = true;
		}
		
		if(all)
		{
			this.Match[0] = 0;
			this.Replace[0] = 0;
		}
		else
		{
			kv.GetString("model", this.Replace, sizeof(this.Replace));
			if(this.Replace[0])
			{
				ReplaceString(this.Replace, sizeof(this.Replace), "\\", "/");

				if(StrEqual(this.Replace, this.Match, false))
				{
					this.Replace[0] = 0;
				}
				else if(FileExists(this.Replace, true))
				{
					PrecacheModel(this.Replace);
				}
				else
				{
					LogError("'%s' has missing model '%s'.", this.Match, this.Replace);
					this.Replace[0] = 0;
				}
			}
		}

		this.BlockSound = view_as<bool>(kv.GetNum("block_sound", kv.GetNum("existing_sound_block")));
		this.BlockMusic = view_as<bool>(kv.GetNum("block_music", kv.GetNum("existing_music_block")));
		this.HideWeapon = view_as<bool>(kv.GetNum("hide_weapon"));
		this.HideCosmetic = view_as<bool>(kv.GetNum("hide_hat"));
		this.BodyModel = view_as<bool>(kv.GetNum("bodymodel"));
		this.Speed = kv.GetFloat("speed", 1.0);
		this.Duration = kv.GetFloat("duration");

		kv.GetString("sound", this.Sound, sizeof(this.Sound));
		if(this.Sound[0])
		{
			PrecacheSound(this.Sound);
			this.SoundVolume = kv.GetFloat("volume", 1.0);
			this.SoundLevel = kv.GetNum("soundlevel", SNDLEVEL_NORMAL);
		}

		if(kv.GotoFirstSubKey())
		{
			SoundEnum sound;
			this.Sounds = new ArrayList(sizeof(SoundEnum));

			do
			{
				sound.Setup(kv);
				this.Sounds.PushArray(sound);
			}
			while(kv.GotoNextKey());
			kv.GoBack();
		}
		else
		{
			this.Sounds = null;
		}
	}
	void Delete()
	{
		delete this.Sounds;
	}
}

enum struct TauntEnum
{
	char Name[64];
	ArrayList Models;

	int Admin;
	
	bool Setup(KeyValues kv)
	{
		kv.GetString("admin", this.Name, sizeof(this.Name));
		this.Admin = this.Name[0] ? ReadFlagString(this.Name) : 0;

		kv.GetSectionName(this.Name, sizeof(this.Name));

		ModelEnum model;
		this.Models = new ArrayList(sizeof(ModelEnum));
		if(kv.GotoFirstSubKey())
		{
			do
			{
				model.Setup(kv);
				this.Models.PushArray(model);
			}
			while(kv.GotoNextKey());
			kv.GoBack();
		}

		if(this.Models.Length)
			return true;
		
		delete this.Models;
		LogError("'%s' has no model entries", this.Name);
		return false;
	}
	void Delete()
	{
		ModelEnum model;
		int length = this.Models.Length;
		for(int i; i < length; i++)
		{
			this.Models.GetArray(i, model);
			model.Delete();
		}

		delete this.Models;
	}
}

Handle SDKPlayTaunt;
Handle SDKEquipWearable;
ArrayList Taunts;
Handle TauntTimer[MAXPLAYERS+1];
int CurrentTaunt[MAXPLAYERS+1] = {-1, ...};
int CurrentModel[MAXPLAYERS+1];
bool LastAnims[MAXPLAYERS+1];
char LastModel[MAXPLAYERS+1][PLATFORM_MAX_PATH];
int WearableModel[MAXPLAYERS+1] = {-1, ...};
RenderFx LastRender[MAXPLAYERS+1];

public Plugin myinfo =
{
	name		=	"TF2: Custom Taunts",
	author		=	"Batfoxkid",
	description	=	"Custom taunts for players to use",
	version		=	PLUGIN_VERSION_FULL,
	url			=	"github.com/Batfoxkid/TF2-Custom-Taunts"
}

public void OnPluginStart()
{
	GameData gameData = new GameData("tf2.tauntem");
	if(gameData == INVALID_HANDLE)
		SetFailState("Could not find gamedata/tf2.tauntem.txt");

	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(gameData, SDKConf_Signature, "CTFPlayer::PlayTauntSceneFromItem");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	SDKPlayTaunt = EndPrepSDKCall();
	if(SDKPlayTaunt == INVALID_HANDLE)
		SetFailState("Could not find CTFPlayer::PlayTauntSceneFromItem.");

	delete gameData;

	gameData = new GameData("sm-tf2.games");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetVirtual(gameData.GetOffset("RemoveWearable") - 1);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	SDKEquipWearable = EndPrepSDKCall();
	if(!SDKEquipWearable)
		SetFailState("Could not find RemoveWearable");
	
	delete gameData;

	RegConsoleCmd("sm_taunt", CommandMenu, "Open a menu of taunts");
	RegConsoleCmd("sm_taunts", CommandList, "View a list of taunt ids");
	AddCommandListener(OnTaunt, "taunt");

	LoadTranslations("common.phrases");

	CreateConVar("customtaunts_version", PLUGIN_VERSION, "Custom Taunts Plugin Version", FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	AddNormalSoundHook(HookSound);
	HookUserMessage(GetUserMessageId("PlayerTauntSoundLoopStart"), HookTauntMessage, true);
}

public void OnConfigsExecuted()
{
	TauntEnum taunt;

	if(Taunts)
	{
		int length = Taunts.Length;
		for(int i; i < length; i++)
		{
			Taunts.GetArray(i, taunt);
			taunt.Delete();
		}

		delete Taunts;
	}

	Taunts = new ArrayList(sizeof(TauntEnum));

	char filepath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filepath, sizeof(filepath), FILE_TAUNTS);
	if(!FileExists(filepath))
	{
		BuildPath(Path_SM, filepath, sizeof(filepath), "configs/customtaunts.cfg");
		if(!FileExists(filepath))
			BuildPath(Path_SM, filepath, sizeof(filepath), "configs/taunts.cfg");
	}
	
	KeyValues kv = new KeyValues("customtaunts");
	kv.ImportFromFile(filepath);

	kv.GotoFirstSubKey();

	do
	{
		if(taunt.Setup(kv))
			Taunts.PushArray(taunt);
	}
	while(kv.GotoNextKey());

	delete kv;

	if(!Taunts.Length)
		SetFailState("'%s' has no taunt entries", filepath);
}

public void OnPluginEnd()
{
	for(int client = 1; client <= MaxClients; client++)
	{
		if(IsClientInGame(client))
		{
			TF2_RemoveCondition(client, TFCond_Taunting);
			EndTaunt(client);
		}
	}
}

public void OnClientDisconnect(int client)
{
	delete TauntTimer[client];
	CurrentTaunt[client] = -1;
}

public void TF2_OnConditionRemoved(int client, TFCond condition)
{
	if(condition == TFCond_Taunting)
		EndTaunt(client);
}

Action HookTauntMessage(UserMsg msg_id, BfRead msg, const int[] players, int playersNum, bool reliable, bool init)
{
	int client = msg.ReadByte();
	if(CurrentTaunt[client] != -1)
	{
		static TauntEnum taunt;
		Taunts.GetArray(CurrentTaunt[client], taunt);

		static ModelEnum model;
		taunt.Models.GetArray(CurrentModel[client], model);

		if(model.BlockMusic)
			return Plugin_Handled;
	}

	return Plugin_Continue;
}

Action HookSound(int clients[MAXPLAYERS], int &numClients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags, char soundEntry[PLATFORM_MAX_PATH], int &seed)
{
	if(entity < 1 || entity > MaxClients)
		return Plugin_Continue;

	if(CurrentTaunt[entity] != -1)
	{
		static TauntEnum taunt;
		Taunts.GetArray(CurrentTaunt[entity], taunt);

		static ModelEnum model;
		taunt.Models.GetArray(CurrentModel[entity], model);

		if(model.Sounds)
		{
			int length = model.Sounds.Length;
			for(int i; i < length; i++)
			{
				static SoundEnum sound;
				model.Sounds.GetArray(i, sound);

				if(StrContains(sample, sound.Match, false) == -1)
					continue;

				if(!sound.Replace[0])
					return Plugin_Stop;

				strcopy(sample, sizeof(sample), sound.Replace);
				return Plugin_Changed;
			}
		}

		if(model.BlockSound && !StrEqual(model.Sound, sample))
			return Plugin_Stop;
	}

	return Plugin_Continue;
}

int GetTaunt(int client, int index, ModelEnum model = {})
{
	TauntEnum taunt;
	Taunts.GetArray(index, taunt);

	char filepath[PLATFORM_MAX_PATH];
	GetClientModel(client, filepath, sizeof(filepath));
	ReplaceString(filepath, sizeof(filepath), "\\", "/");
	TFClassType class = TF2_GetPlayerClass(client);

	int length = taunt.Models.Length;
	for(int i; i < length; i++)
	{
		taunt.Models.GetArray(i, model);

		if(model.Class != TFClass_Unknown)
		{
			if(model.Class != class)
				continue;
		}
		else if(model.Match[0])
		{
			if(!StrEqual(model.Match, filepath, false))
				continue;
		}

		return i;
	}

	return -1;
}

bool StartTaunt(int client, int index)
{
	ModelEnum model;
	int modelIndex = GetTaunt(client, index, model);
	if(modelIndex == -1)
		return false;

	static Handle item;
	if(item == INVALID_HANDLE)
	{
		item = TF2Items_CreateItem(OVERRIDE_ALL|PRESERVE_ATTRIBUTES|FORCE_GENERATION);
		TF2Items_SetClassname(item, "tf_wearable_vm");
		TF2Items_SetQuality(item, 6);
		TF2Items_SetLevel(item, 1);
	}

	TF2Items_SetItemIndex(item, model.Index);
	int entity = TF2Items_GiveNamedItem(client, item);
	if(entity == -1)
		return false;
	
	TF2_RemoveCondition(client, TFCond_Taunting);
	EndTaunt(client);
	
	static int offset;
	if(!offset)
		offset = GetEntSendPropOffs(entity, "m_Item", true);
	
	if(offset < 1)
	{
		SetFailState("Could not find m_Item");
		return false;
	}
	
	Address address = GetEntityAddress(entity);
	if(address == Address_Null)
		return false;
	
	if(model.Duration > 0)
	{
		TF2Attrib_SetByDefIndex(client, 201, 0.01);
	}
	else
	{
		TF2Attrib_SetByDefIndex(client, 201, model.Speed);
	}
	
	address += view_as<Address>(offset);
	if(SDKCall(SDKPlayTaunt, client, address))
	{
		if(model.BodyModel)
		{
			char buffer[PLATFORM_MAX_PATH];
			GetClientModel(client, buffer, sizeof(buffer));
			if(buffer[0])
			{
				// Apply a fake playermodel
				int playermodel = CreateEntityByName("tf_wearable");
				if(playermodel != -1)
				{
					SetEntProp(playermodel, Prop_Send, "m_nModelIndex", PrecacheModel(buffer));
					SetEntProp(playermodel, Prop_Send, "m_fEffects", 129);
					SetEntProp(playermodel, Prop_Send, "m_iTeamNum", GetEntProp(client, Prop_Send, "m_iTeamNum"));
					SetEntProp(playermodel, Prop_Send, "m_nSkin", GetEntProp(client, Prop_Send, "m_nSkin"));
					SetEntProp(playermodel, Prop_Send, "m_usSolidFlags", 4);
					SetEntityCollisionGroup(playermodel, 11);
					SetEntProp(playermodel, Prop_Send, "m_bValidatedAttachedEntity", true);
					DispatchSpawn(playermodel);
					SetVariantString("!activator");
					ActivateEntity(playermodel);
					SDKCall(SDKEquipWearable, client, playermodel);
					WearableModel[client] = EntIndexToEntRef(playermodel);
				}
			}

			LastRender[client] = GetEntityRenderFx(client);
			SetEntityRenderFx(client, RENDERFX_FADE_FAST);
		}
		
		if(model.Replace[0])
		{
			// Replace the model, remember previous custom model
			LastAnims[client] = view_as<bool>(GetEntProp(client, Prop_Send, "m_bUseClassAnimations"));
			GetEntPropString(client, Prop_Send, "m_iszCustomModel", LastModel[client], sizeof(LastModel[]));

			SetVariantString(model.Replace);
			AcceptEntityInput(client, "SetCustomModelWithClassAnimations");
		}

		if(model.Sound[0])
			EmitSoundToAll(model.Sound, client, SNDCHAN_STATIC, model.SoundLevel, _, model.SoundVolume);

		if(model.Duration > 0)
		{
			TauntTimer[client] = CreateTimer(model.Duration, Timer_EndTaunt, client);
			TF2Attrib_SetByDefIndex(client, 201, model.Speed);
		}

		if(model.HideWeapon)
			ToggleWeapons(client, false);

		if(model.HideCosmetic)
			ToggleCosmetics(client, false);
		
		CurrentTaunt[client] = index;
		CurrentModel[client] = modelIndex;
	}
	else
	{
		TF2Attrib_SetByDefIndex(client, 201, 1.0);
	}

	AcceptEntityInput(entity, "Kill");
	return true;
}

Action Timer_EndTaunt(Handle timer, int client)
{
	TauntTimer[client] = null;
	TF2_RemoveCondition(client, TFCond_Taunting);
	return Plugin_Continue;
}

void EndTaunt(int client)
{
	delete TauntTimer[client];

	if(CurrentTaunt[client] != -1)
	{
		if(CurrentModel[client] != -1)
		{
			TauntEnum taunt;
			Taunts.GetArray(CurrentTaunt[client], taunt);

			ModelEnum model;
			taunt.Models.GetArray(CurrentModel[client], model);

			if(model.Sound[0])
				StopSound(client, SNDCHAN_STATIC, model.Sound);
			
			if(WearableModel[client] != -1)
			{
				// Remove fake playermodel
				int entity = EntRefToEntIndex(WearableModel[client]);
				if(entity != -1)
					TF2_RemoveWearable(client, entity);
				
				WearableModel[client] = -1;

				if(GetEntityRenderFx(client) == RENDERFX_FADE_FAST)
					SetEntityRenderFx(client, LastRender[client]);
			}
			
			if(model.Replace[0])
			{
				char buffer[PLATFORM_MAX_PATH];
				GetEntPropString(client, Prop_Send, "m_iszCustomModel", buffer, sizeof(buffer));
				if(StrEqual(buffer, model.Replace))
				{
					// Check if our custom model is the same
					// If it was changed, probably another plugin
					SetVariantString(LastModel[client]);
					AcceptEntityInput(client, "SetCustomModel");
					SetEntProp(client, Prop_Send, "m_bUseClassAnimations", LastAnims[client]);
				}
			}

			if(model.HideWeapon)
				ToggleWeapons(client, true);

			if(model.HideCosmetic)
				ToggleCosmetics(client, true);
			
			TF2Attrib_SetByDefIndex(client, 201, 1.0);
		}

		CurrentTaunt[client] = -1;
	}
}

bool CanAccessTaunt(int client, int index)
{
	TauntEnum taunt;
	Taunts.GetArray(index, taunt);

	if(taunt.Admin)
	{
		if(!CheckCommandAccess(client, "customtaunts_all", taunt.Admin, true))
			return false;
	}

	return true;
}

void ToggleWeapons(int client, bool toggle)
{
	static int max;
	if(!max)
		max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");

	for(int i; i < max; i++)
	{
		int weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if(weapon != -1)
		{
			SetEntityRenderMode(weapon, (toggle ? RENDER_NORMAL : RENDER_ENVIRONMENTAL));
			SetEntityRenderColor(weapon, 255, 255, 255, (toggle ? 255 : 5));
		}
	}
}

void ToggleCosmetics(int client, bool toggle)
{
	int entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_wearable")) != -1)
	{
		if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
		{
			SetEntityRenderMode(entity, (toggle ? RENDER_NORMAL : RENDER_ENVIRONMENTAL));
			SetEntityRenderColor(entity, 255, 255, 255, (toggle ? 255 : 0));
		}
	}

	entity = -1;
	while((entity = FindEntityByClassname(entity, "tf_powerup_bottle")) != -1)
	{
		if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
		{
			SetEntityRenderMode(entity, (toggle ? RENDER_NORMAL : RENDER_ENVIRONMENTAL));
			SetEntityRenderColor(entity, 255, 255, 255, (toggle ? 255 : 0));
		}
	}
}

Action OnTaunt(int client, const char[] command, int argc)
{
	if(IsPlayerAlive(client) && !TF2_IsPlayerInCondition(client, TFCond_Taunting))
	{
		int target = GetClientAimTarget(client, true);
		if(target != -1 && CurrentTaunt[target] != -1)
		{
			// Join in custom taunts if their infinite duration
			TauntEnum taunt;
			Taunts.GetArray(CurrentTaunt[target], taunt);

			int index = GetTaunt(client, CurrentTaunt[target]);
			if(index != -1)
			{
				ModelEnum model;
				taunt.Models.GetArray(index, model);
				if(model.Duration <= 0.0)
					StartTaunt(client, CurrentTaunt[target]);
			}
			
			return Plugin_Handled;
		}
	}
	return Plugin_Continue;
}

Action CommandMenu(int client, int args)
{
	char buffer[MAX_TARGET_LENGTH];
	
	switch(args)
	{
		case 0:
		{
			if(client)
			{
				Menu menu = new Menu(CommandMenuH);
				menu.SetTitle("Taunt Menu\n ");

				TauntEnum taunt;
				int length = Taunts.Length;
				for(int i; i < length; i++)
				{
					if(!CanAccessTaunt(client, i) || GetTaunt(client, i) == -1)
						continue;

					IntToString(i, buffer, sizeof(buffer));
					Taunts.GetArray(i, taunt);
					menu.AddItem(buffer, taunt.Name);
				}

				if(!menu.ItemCount)
					menu.AddItem("-1", "None", ITEMDRAW_DISABLED);

				menu.ExitButton = true;
				menu.Display(client, MENU_TIME_FOREVER);
				return Plugin_Handled;
			}
		}
		case 1:
		{
			if(client)
			{
				GetCmdArg(1, buffer, sizeof(buffer));
				int index = StringToInt(buffer);
				
				int length = Taunts.Length;
				if(index >= 0 && index < length && CanAccessTaunt(client, index) && GetTaunt(client, index) != -1)
				{
					if(IsPlayerAlive(client) && !TF2_IsPlayerInCondition(client, TFCond_Taunting))
						StartTaunt(client, index);
				}
				else
				{
					ReplyToCommand(client, "[SM] Invalid taunt for this class");
				}

				return Plugin_Handled;
			}
		}
		case 2:
		{
			if(client == 0 || CheckCommandAccess(client, "customtaunts_targetting", ADMFLAG_CHEATS))
			{
				GetCmdArg(1, buffer, sizeof(buffer));
				int index = StringToInt(buffer);

				int length = Taunts.Length;
				if(index >= 0 && index < length && CanAccessTaunt(client, index))
				{
					GetCmdArg(2, buffer, sizeof(buffer));
					char targetName[MAX_TARGET_LENGTH];
					int targets[MAXPLAYERS], matches;
					bool tn_is_ml;

					if((matches=ProcessTargetString(buffer, client, targets, sizeof(targets), COMMAND_FILTER_ALIVE, targetName, sizeof(targetName), tn_is_ml)) < 1)
					{
						ReplyToTargetError(client, matches);
						return Plugin_Handled;
					}

					bool failed = true;
					for(int target; target < matches; target++)
					{
						if(StartTaunt(targets[target], index))
							failed = false;
					}

					if(failed)
					{
						ReplyToCommand(client, "[SM] Invalid taunt for this class");
					}
					else if(tn_is_ml)
					{
						ShowActivity2(client, "[SM] ", "Forced taunt on %t", targetName);
					}
					else
					{
						ShowActivity2(client, "[SM] ", "Forced taunt on %s", targetName);
					}
				}
				else
				{
					ReplyToCommand(client, "[SM] Invalid taunt id");
				}
			}
			else
			{
				ReplyToCommand(client, "[SM] Usage: sm_taunt [tauntid]");
			}

			return Plugin_Handled;
		}
		default:
		{
			if(client != 0)
			{
				if(CheckCommandAccess(client, "customtaunts_targetting", ADMFLAG_CHEATS))
				{
					ReplyToCommand(client, "[SM] Usage: sm_taunt [tauntid] [target]");
				}
				else
				{
					ReplyToCommand(client, "[SM] Usage: sm_taunt [tauntid]");
				}
				return Plugin_Handled;
			}
		}
	}

	ReplyToCommand(client, "[SM] Usage: sm_taunt <tauntid> <target>");
	return Plugin_Handled;
}

int CommandMenuH(Menu menu, MenuAction action, int client, int choice)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Select:
		{
			char buffer[16];
			menu.GetItem(choice, buffer, sizeof(buffer));

			int index = StringToInt(buffer);
			FakeClientCommand(client, "sm_taunt %d", index);
		}
	}
	return 0;
}

Action CommandList(int client, int args)
{
	TauntEnum taunt;
	int length = Taunts.Length;
	for(int i; i < length; i++)
	{
		if(CanAccessTaunt(client, i))
		{
			Taunts.GetArray(i, taunt);
			PrintToConsole(client, "#%d - %s", i, taunt.Name);
		}
	}

	if(GetCmdReplySource() == SM_REPLY_TO_CHAT)
		ReplyToCommand(client, "[SM] %t", "See console for output");

	return Plugin_Handled;
}