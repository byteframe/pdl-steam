#include <sdkhooks>
#include <sdktools>
#include <sourcemod>
#include <tf2>
#include <tf2_stocks>

#pragma semicolon 1

public Plugin:myinfo =
{
	name = "[TF2] pdl-tf2ach",
	author = "primarydataloop",
	description = "primarydataloop tf2 achievement server plugin",
	version = "0.33",
	url = "http://www.sourcemod.net"
}

// park client in connection phase if their tv_nochat variable is 4

public bool:OnClientConnect(c, String:rejectmsg[], maxlen)
{
	decl String:tvnochat[2];
	GetClientInfo(c, "tv_nochat", tvnochat, 2);
	if (strcmp(tvnochat, "4", false) == 0) {
		InactivateClient(c);
	}
	return true;
}

// apply various bot and player spawn effects and buffs

public Event_PlayerSpawn(Handle:event, const String:name[], bool:db)
{
	new c = GetClientOfUserId(GetEventInt(event, "userid"));
	new TFClassType:class = TF2_GetPlayerClass(c);
	if (IsFakeClient(c)) {
		TF2_AddCondition(c, TFCond_MarkedForDeath, 10.0);
		TF2_AddCondition(c, TFCond_TeleportedGlow, 10.0);
		if (class == TFClass_Spy) {
			TF2_DisguisePlayer(c, TFTeam_Blue, TFClass_Spy, 0);
			ServerCommand("sm_show_activity 0");
			ServerCommand("sm_beacon #%d", GetEventInt(event, "userid"));
			ServerCommand("sm_show_activity 13");
		}
	} else if (class == TFClass_Medic) {
		new slot2 = GetPlayerWeaponSlot(c, 1);
		SetEntPropFloat(slot2, Prop_Send, "m_flChargeLevel", 1.00);
	} else if (class == TFClass_Soldier) {
		SetEntPropFloat(c, Prop_Send, "m_flRageMeter", 100.0);
	}
}

// periodically manipulate the bots if human players are present

new bot_tick;
new Handle:bot_timer = INVALID_HANDLE;
new Handle:cvBotActive = INVALID_HANDLE;
new Handle:cvBotForceAttack = INVALID_HANDLE;
new Handle:cvBotJump = INVALID_HANDLE;
new Handle:cvBotMimic = INVALID_HANDLE;
new Handle:cvBotMimicYawOffset = INVALID_HANDLE;

public Cvar_BotActive(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	SetConVarString(cvBotForceAttack, newVal);
	SetConVarString(cvBotJump, newVal);
}

public OnClientPutInServer(c)
{
	decl String:ip[17];
	decl String:name[30];
	GetClientIP(c, ip, 16, true);
	GetClientName(c, name, 29);
	if (IsFakeClient(c)) {
		ServerCommand("sm_autorespawn #%d 1", GetClientUserId(c));
	} else if (!GetConVarBool(cvBotActive)) {
		SetConVarBool(cvBotActive, true);
	}
}

public OnClientDisconnect(c)
{
	if (GetConVarBool(cvBotActive)) {
		for (new i = 1; i <= MaxClients; i++) {
			if (IsClientConnected(i) && !IsFakeClient(i)
			&& GetClientUserId(i) != GetClientUserId(c)) {
				return;
			}
		}
		SetConVarBool(cvBotActive, false);
	}
}

public Action:Timer_BotMimic(Handle:timer)
{
	SetConVarBool(cvBotMimic, false);
}

public Cvar_BotMimic(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	if (strcmp(newVal, "1") == 0) {
		CreateTimer(0.0, Timer_BotMimic);
	}
}

public Action:Timer_ChangeBot(Handle:timer)
{
	if (GetConVarBool(cvBotActive)) {
		SetConVarBool(cvBotMimic, true);
		SetConVarInt(cvBotMimicYawOffset, GetRandomInt(0, 359));
		if (bot_tick == 6) {
			bot_tick = 0;
			ServerCommand("sm_show_activity 0");
			ServerCommand("sm_freeze Gimme 6");
			ServerCommand("sm_freeze Companies 6");
			ServerCommand("sm_show_activity 13");
		}	else {
			bot_tick++;
		}
		for (new c = 1; c <= MaxClients; c++) {
			if (IsClientConnected(c) && IsFakeClient(c)) {
				if ((GetEntityFlags(c) & FL_INWATER)) {
					for (new i = 0; i < 7; i++) {
						SlapPlayer(c, 10, false);
					}
					TF2_AddCondition(c, TFCond_Charging, 6.0);
				} else {
					SlapPlayer(c, 0, false);
					TF2_MakeBleed(c, c, 1.0);
					if (TF2_GetPlayerClass(c) == TFClass_Spy
					&& (bot_tick == 2 || bot_tick == 4)) {
						TF2_AddCondition(c, TFCond_Cloaked, 4.0);
					}
					if (GetRandomInt(0, 7) == 7) {
						FakeClientCommand(c, "voicemenu 2 %d", GetRandomInt(1, 7));
					}
					switch(GetRandomInt(0, 9)) {
						case 0: {
							TF2_AddCondition(c, TFCond_Jarated, 4.0);
						}	case 1: {
							TF2_AddCondition(c, TFCond_Milked, 4.0);
						}	case 2: {
							TF2_AddCondition(c, TFCond_DefenseBuffed, 4.0);
						}	case 3: {
							TF2_AddCondition(c, TFCond_HalloweenCritCandy, 4.0);
						}	case 4: {
							TF2_AddCondition(c, TFCond_Charging, 4.0);
						}	case 5: {
							TF2_AddCondition(c, TFCond_Dazed, 4.0);
						}	case 6: {
							TF2_AddCondition(c, TFCond_Ubercharged, 4.0);
						}	case 7: {
							TF2_StunPlayer(c, 4.0, 0.0, TF_STUNFLAGS_BIGBONK, 0);
						}	case 8: {
							TF2_StunPlayer(c, 4.0, 0.0, TF_STUNFLAGS_GHOSTSCARE, 0);
						}	case 9: {
							TF2_IgnitePlayer(c, c);
						}
					}
				}
			}
		}
	}
	return Plugin_Continue;
}

// spawn bosses in hard-coded locations, and respawn them on death

new const Float:horsemann_pos[3] = {515.0,1650.0,60.0};
new const Float:monoculus_pos[3] = {2975.0,-185.0,100.0};
new const Float:tank_pos[3] = {-1300.0,600.0,135.0};
new const Float:tank_ang[3] = {0.0,-90.0,0.0};
new const Float:merasmus_pos[3] = {-1140.0,-1000.0,85.0};

public Action:Timer_Horsemann(Handle:timer)
{
	new ent = CreateEntityByName("headless_hatman");
	DispatchSpawn(ent);
	TeleportEntity(ent, horsemann_pos, NULL_VECTOR, NULL_VECTOR);
}

public Event_PumpkinLordKilled(Handle:event, const String:name[], bool:db)
{
	CreateTimer(60.0, Timer_Horsemann);
}

public Event_EyeballBossKiller(Handle:event, const String:name[], bool:db)
{
	PrintCenterTextAll("My Eye!");
}

public Action:Timer_Monoculus(Handle:timer)
{
	new ent = CreateEntityByName("eyeball_boss");
	DispatchSpawn(ent);
	SetEntProp(ent, Prop_Data, "m_iMaxHealth", 24000);
	SetEntProp(ent, Prop_Data, "m_iHealth", 2400);
	TeleportEntity(ent, monoculus_pos, NULL_VECTOR, NULL_VECTOR);
}

public Event_EyeballBossKilled(Handle:event, const String:name[], bool:db)
{
	CreateTimer(60.0, Timer_Monoculus);
}

public Action:Timer_Merasmus(Handle:timer)
{
	new ent = CreateEntityByName("merasmus");
	DispatchSpawn(ent);
	SetEntProp(ent, Prop_Data, "m_iMaxHealth", 24000);
	SetEntProp(ent, Prop_Data, "m_iHealth", 2400);
	TeleportEntity(ent, merasmus_pos, NULL_VECTOR, NULL_VECTOR);
}

public Event_MerasmusRemoved(Handle:event, const String:name[], bool:db)
{
	CreateTimer(10.0, Timer_Merasmus);
}

public Action:Timer_Tank(Handle:timer)
{
	new ent = CreateEntityByName("tank_boss");
	DispatchSpawn(ent);
	TeleportEntity(ent, tank_pos, tank_ang, NULL_VECTOR);
}

public Event_TankDestroyedByPlayers(Handle:event, const String:name[], bool:db)
{
	CreateTimer(15.0, Timer_Tank);
}

// periodically fake a random item event for one of the bots

new const achievements[] = {115,116,125,164,165,166,169,170,189,242,243,244,245,
	278,279,294,295,296,297,298,302,332,333,334,343,423,429,430,431,438,471,473,
	536,537,581,582,583,584,668,673,711,712,713,725,727,751,756,756,762,870,871,
	940,941,953,954,975,994,1011,1899,5500};
new const crafts[] = {432,433,489,5000,5001,5002,5003,5004,5005,5006,5007,5008,
	5009,5010,5011,5012,5013,5014,5015,5016,5017,5018,5019};
new const genuines[] = {299,358,359,360,361,363,420,434,435,436,437,442,452,453,
	454,465,466,467,468,513,514,515,516,517,518,519,520,521,522,523,524,525,526,
	527,528,538,539,540,541,542,586,587,634,635,637,638,702,703,704,718,719,720,
	738,754,764,765,766,767,768,769,785,810,811,812,813,814,815,816,817,818,819,
	820,828,851,853,854,855,863,864,865,866,867,868,872,873,874,875,876,877,878,
	879,880,942,943,944,945,946,947,948,955,1008,1009,1010,1014,1015,1016};
new const haunteds[] = {266,267,543,544,545,546,547,548,549,550,551,552,553,554,
	555,556,557,558,559,560,561,562,563,564,565,566,567,568,569,869,917,918,919,
	920,921,922,924,925,926,927,929,930,931,932,934,935,936,937,938,939,5617,5618,
	5619,5620,5621,5622,5623,5624,5625};
new const stranges[] = {190,191,192,193,194,195,196,197,198,199,200,201,202,203,
	204,205,206,207,208,209,210,211,212,214,215,220,221,222,224,225,228,230,232,
	239,264,326,329,331,351,402,404,406,411,412,414,415,416,424,425,444,448,450,
	461,648,649,654,655,656,658,659,660,661,662,663,664,665,669,730,736,737,739,
	741,772,792,793,794,795,796,797,798,799,800,801,802,803,804,805,806,807,808,
	809,867,881,882,883,884,885,886,887,888,889,890,891,892,893,894,895,896,897,
	898,899,900,901,902,903,904,905,906,907,908,909,910,911,912,913,914,915,916,
	957,958,959,960,961,962,963,964,965,966,968,969,970,971,972,973,974,999,1000,
	1001,1002,1003,1004,1005,1006,1007};
new const uniques[] = {121,126,134,136,138,143,161,162,167,173,213,216,219,223,
	226,227,229,231,237,240,241,246,247,248,249,250,251,252,253,254,255,259,260,
	261,262,263,265,268,269,270,271,272,273,274,275,276,277,280,281,282,283,284,
	286,287,288,289,290,291,292,303,306,309,313,314,315,316,317,318,319,321,322,
	323,324,325,327,330,337,338,339,340,341,342,344,345,346,347,362,364,365,377,
	378,379,380,381,382,383,384,386,387,388,389,390,391,392,393,394,395,397,398,
	399,400,401,403,405,408,409,410,413,417,422,426,427,439,440,441,443,445,446,
	447,449,451,457,459,460,462,463,474,477,478,479,480,481,482,483,484,485,486,
	490,491,492,493,570,571,572,574,575,576,578,579,580,585,588,589,590,591,592,
	593,594,595,596,597,598,600,601,602,603,605,605,606,607,608,609,610,611,612,
	613,614,615,616,617,618,619,620,621,622,623,624,626,627,628,629,630,631,632,
	633,636,639,641,642,643,644,645,646,647,650,651,652,653,657,666,667,670,671,
	675,699,701,707,708,709,721,722,725,731,732,733,734,740,745,746,751,752,753,
	755,757,758,759,760,763,770,771,773,776,777,778,779,780,781,782,783,784,786,
	787,788,789,840,841,842,843,844,845,846,847,848,852,856,949,950,951,952,955,
	976,976,977,978,980,981,982,983,984,985,986,987,988,989,990,991,992,993,995,
	996,997,998,5021,5022,5026,5027,5028,5029,5030,5031,5032,5033,5034,5035,5036,
	5037,5038,5039,5040,5042,5043,5044,5046,5048,5050,5051,5052,5053,5054,5055,
	5056,5057,5060,5061,5062,5063,5064,5065,5066,5068,5070,5071,5076,5077,5604,
	5606,5999,6000,6001,6002,6003,6009,6010,6011,6012,6013,6015,6016,6018,6019,
	6020,6021,6022,6024,6025};
new const vintages[] = {35,36,37,38,39,40,41,42,43,44,45,46,47,48,49,50,51,52,
	53,54,55,56,57,58,59,60,61,94,95,96,97,98,99,100,101,102,103,104,105,106,107,
	108,109,110,111,117,118,120,127,128,129,130,131,132,133,135,137,139,140,141,
	142,144,145,146,147,148,150,151,152,153,154,155,158,159,160,163,171,172,174,
	175,177,178,179,180,181,182,183,184,185,304,305,307,308,310,311,312,335,336,
	348,349,354,355,356,357,470,743,775};
new const qualities[] = {6,6,6,6,6,6,6,6,6,6,1,2,3,4,5,7,6,6,6,6,6,6,6,6,6};
new Handle:fakeitem_timer = INVALID_HANDLE;

public Action:Timer_FakeItem(Handle:timer)
{
	new item, method, qual = qualities[GetRandomInt(0, sizeof(qualities)-1)];
	if (qual == 1) {
		item = achievements[GetRandomInt(0, sizeof(achievements)-1)];
		method = 8;
		qual = 6;
	} else if (qual == 2) {
		item = crafts[GetRandomInt(0, sizeof(crafts)-1)];
		method = 1;
		qual = 6;
	} else if (qual == 3) {
		item = genuines[GetRandomInt(0, sizeof(genuines)-1)];
		method = 2;
		qual = 1;
	} else if (qual == 4) {
		item = haunteds[GetRandomInt(0, sizeof(haunteds)-1)];
		if (GetRandomInt(0, 1) == 1) {
			method = 5;
		} else {
			method = 2;
		}
		qual = 13;
	} else if (qual == 5) {
		item = stranges[GetRandomInt(0, sizeof(stranges)-1)];
		if (GetRandomInt(0, 1) == 1) {
			method = 4;
		} else {
			method = 2;
		}
		qual = 11;
	} else if (qual == 6) {
		item = uniques[GetRandomInt(0, sizeof(uniques)-1)];
		if (GetRandomInt(0, 1) == 1) {
			method = 2;
		} else {
			method = 0;
		}
	} else if (qual == 7) {
		item = vintages[GetRandomInt(0, sizeof(vintages)-1)];
		method = 2;
		qual = 3;
	}
	new c;
	do {
		c = GetRandomInt(1, MaxClients);
	} while (!IsClientInGame(c) || !IsFakeClient(c) || IsClientReplay(c));
	ServerCommand("sm_fakeitem #%d %d %d %d", GetClientUserId(c), item, qual,
		method);
	return Plugin_Continue;
}

// find the location of the ground directly beneath a given position

new g_FilteredEntity = -1;

public bool:TraceFilter(ent, contentMask)
{
	return (ent != g_FilteredEntity);
}

Float:TraceToGround(Float:start_pos[3])
{
	decl Float:end_pos[3];
	start_pos[2] += 4;
	end_pos[0] = start_pos[0];
	end_pos[1] = start_pos[1];
	end_pos[2] = start_pos[2]-1024;
	new Handle:trace = TR_TraceRayFilterEx(start_pos, end_pos, MASK_SOLID,
		RayType_EndPoint, TraceFilter);
	TR_GetEndPosition(end_pos, trace);
	start_pos[2] += 4;
	CloseHandle(trace);
	return end_pos;
}

// spawn item pickups with varying models on player suicide

new pickup_cnt;
new String:ammo_models[][100] = {
	"models/items/ammopack_small_bday.mdl",
	"models/items/ammopack_medium_bday.mdl"
};
new String:medi_models[][100] = {
	"models/items/medkit_medium_bday.mdl",
	"models/items/medkit_small.mdl",
	"models/items/medkit_small_bday.mdl",
	"models/items/plate.mdl",
	"models/items/plate_steak.mdl",
	"models/props_halloween/halloween_medkit_large.mdl",
	"models/props_halloween/halloween_medkit_medium.mdl",
	"models/props_halloween/halloween_medkit_small.mdl",
	"models/props_medieval/medieval_meat.mdl"
};

public Event_PlayerDeath(Handle:event, const String:name[], bool:db)
{
	new u = GetEventInt(event, "userid");
	new c = GetClientOfUserId(u);
	new attacker = GetEventInt(event, "attacker");
	if ((attacker == 0 || u == attacker) && pickup_cnt < 100
	&& !(GetEntityFlags(c) & FL_INWATER)) {
		new ent = -1;
		if (GetRandomInt(0, 3) == 3) {
			ent = CreateEntityByName("item_ammopack_small");
			DispatchKeyValue(ent, "powerup_model",
				ammo_models[GetRandomInt(0, sizeof(ammo_models)-1)]);
		} else 	{
			ent = CreateEntityByName("item_healthkit_small");
			DispatchKeyValue(ent, "powerup_model",
				medi_models[GetRandomInt(0, sizeof(medi_models)-1)]);
		}
		DispatchKeyValue(ent, "OnPlayerTouch", "!self,Kill,,0,-1");
		DispatchSpawn(ent);
		SetEntProp(ent, Prop_Send, "m_iTeamNum", 0, 4);
		g_FilteredEntity = c;
		decl Float:pos[3];
		GetClientAbsOrigin(c, pos);
		TeleportEntity(ent, TraceToGround(pos), NULL_VECTOR, NULL_VECTOR);
		pickup_cnt++;
	}
}

public Event_ItemPickup(Handle:event, const String:name[], bool:db)
{
	decl String:item[40];
	GetEventString(event, "item", item, 40);
	if (strcmp(item, "medkit_small") == 0
	|| strcmp(item, "ammopack_small") == 0) {
		pickup_cnt--;
	}
}

// spawn pumpkin bombs at specific locations and respawn them on destruction

new pumpkin_pos[][2] = {{-1430,-999},{-850,-952},{-953,-435},{-970,37},
{-536,599},{-1523,-133},{-1510,2022},{-1515,1505},{-746,974},{-813,1346},
{-1515,367},{-443,2032},{-514,1682},{137,2025},{945,2034},{1131,1594},
{1170,1255},{1263,725},{1453,1362},{1589,2017},{2098,1908},{2128,1543},
{2371,887},{125,-931},{682,-675},{1104,-652},{1667,-487},{1686,17},{358,-356},
{2196,-867},{2529,-765},{2542,358}};

public Action:PumpkinTakeDamage(ent, &attacker, &inflictor, &Float:damage, &damagetype)
{
	SDKUnhook(ent, SDKHook_OnTakeDamage, PumpkinTakeDamage);
	new Float:pos[3];
	GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
	new Handle:pack;
	CreateDataTimer(16.0, Timer_Pumpkin, pack);
	WritePackFloat(pack, pos[0]);
	WritePackFloat(pack, pos[1]);
}

public Action:Timer_Pumpkin(Handle:timer, Handle:pack)
{
	new ent = CreateEntityByName("tf_pumpkin_bomb");
	DispatchSpawn(ent);
	decl Float:ang[3], Float:pos[3];
	ang[0] = 0.0;
	ang[1] = GetRandomFloat(0.0, 360.0);
	ang[2] = 0.0;
	ResetPack(pack);
	pos[0] = ReadPackFloat(pack);
	pos[1] = ReadPackFloat(pack);
	pos[2] = 100.0;
	TeleportEntity(ent, TraceToGround(pos), ang, NULL_VECTOR);
	SDKHook(ent, SDKHook_OnTakeDamage, PumpkinTakeDamage);
}

public Event_TeamplayRestartRound(Handle:event, const String:name[], bool:db)
{
	decl String:mapname[50];
	GetCurrentMap(mapname, sizeof(mapname));
	if (strcmp(mapname, "achievement_idle_alpine_v2", false) == 0) {
		for (new i = 0; i < sizeof(pumpkin_pos); i++) {
			new Handle:pack;
			CreateDataTimer(0.0, Timer_Pumpkin, pack);
			WritePackFloat(pack, float(pumpkin_pos[i][0]));
			WritePackFloat(pack, float(pumpkin_pos[i][1]));
		}
		bot_timer = CreateTimer(4.0, Timer_ChangeBot, _, TIMER_REPEAT);
		fakeitem_timer = CreateTimer(60.0, Timer_FakeItem, _, TIMER_REPEAT);
	}
}

// disable regeneration and spawn initial bosses

public Event_TeamplayRoundStart(Handle:event, const String:name[], bool:db)
{
	decl String:mapname[50];
	GetCurrentMap(mapname, sizeof(mapname));
	if (strcmp(mapname, "achievement_idle_alpine_v2", false) == 0) {
		new ent = -1;
		while ((ent = FindEntityByClassname(ent, "func_regenerate")) != -1) {
			AcceptEntityInput(ent, "Disable");
		}
		CreateTimer(0.0, Timer_Horsemann);
		CreateTimer(0.0, Timer_Monoculus);
		CreateTimer(0.0, Timer_Merasmus);
		CreateTimer(0.0, Timer_Tank);
	}
}

// precache resources, start bot timers, and count items

public OnMapStart()
{
	if (bot_timer != INVALID_HANDLE) {
		KillTimer(bot_timer);
	}
	if (fakeitem_timer != INVALID_HANDLE) {
		KillTimer(fakeitem_timer);
	}
	PrecacheModel("models/bots/headless_hatman.mdl");
	PrecacheModel("models/props_halloween/eyeball_projectile.mdl");
	PrecacheModel("models/props_halloween/halloween_demoeye.mdl");
	PrecacheModel("models/weapons/c_models/c_bigaxe/c_bigaxe.mdl");
	PrecacheSound("ui/halloween_boss_chosen_it.wav");
	PrecacheSound("ui/halloween_boss_defeated.wav");
	PrecacheSound("ui/halloween_boss_defeated_fx.wav");
	PrecacheSound("ui/halloween_boss_escape.wav");
	PrecacheSound("ui/halloween_boss_escape_sixty.wav");
	PrecacheSound("ui/halloween_boss_escape_ten.wav");
	PrecacheSound("ui/halloween_boss_player_becomes_it.wav");
	PrecacheSound("ui/halloween_boss_summon_rumble.wav");
	PrecacheSound("ui/halloween_boss_summoned.wav");
	PrecacheSound("ui/halloween_boss_summoned_fx.wav");
	PrecacheSound("ui/halloween_boss_tagged_other_it.wav");
	PrecacheSound("ui/halloween_boss_tagged_other_it.wav");
	PrecacheSound("vo/halloween_boss/knight_alert.wav");
	PrecacheSound("vo/halloween_boss/knight_alert01.wav");
	PrecacheSound("vo/halloween_boss/knight_alert02.wav");
	PrecacheSound("vo/halloween_boss/knight_attack01.wav");
	PrecacheSound("vo/halloween_boss/knight_attack02.wav");
	PrecacheSound("vo/halloween_boss/knight_attack03.wav");
	PrecacheSound("vo/halloween_boss/knight_attack04.wav");
	PrecacheSound("vo/halloween_boss/knight_death01.wav");
	PrecacheSound("vo/halloween_boss/knight_death02.wav");
	PrecacheSound("vo/halloween_boss/knight_dying.wav");
	PrecacheSound("vo/halloween_boss/knight_laugh01.wav");
	PrecacheSound("vo/halloween_boss/knight_laugh02.wav");
	PrecacheSound("vo/halloween_boss/knight_laugh03.wav");
	PrecacheSound("vo/halloween_boss/knight_laugh04.wav");
	PrecacheSound("vo/halloween_boss/knight_pain01.wav");
	PrecacheSound("vo/halloween_boss/knight_pain02.wav");
	PrecacheSound("vo/halloween_boss/knight_pain03.wav");
	PrecacheSound("vo/halloween_boss/knight_spawn.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball01.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball02.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball03.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball04.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball05.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball06.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball07.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball08.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball09.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball10.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball11.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_biglaugh01.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_boss_pain01.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_laugh01.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_laugh02.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_laugh03.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_mad01.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_mad02.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_mad03.wav");
	PrecacheSound("vo/halloween_eyeball/eyeball_teleport01.wav");
	PrecacheSound("weapons/halloween_boss/knight_axe_hit.wav");
	PrecacheSound("weapons/halloween_boss/knight_axe_miss.wav");
	PrecacheModel("models/bots/merasmus/merasmus.mdl", true);
	PrecacheModel("models/prop_lakeside_event/bomb_temp.mdl", true);
	PrecacheModel("models/prop_lakeside_event/bomb_temp_hat.mdl", true);
	PrecacheModel("models/bots/boss_bot/bomb_mechanism.mdl"); 
	PrecacheModel("models/bots/boss_bot/boss_tank.mdl");
	PrecacheModel("models/bots/boss_bot/boss_tank_damage1.mdl");
	PrecacheModel("models/bots/boss_bot/boss_tank_damage2.mdl");
	PrecacheModel("models/bots/boss_bot/boss_tank_damage3.mdl");
	PrecacheModel("models/bots/boss_bot/boss_tank_part1_destruction.mdl");
	PrecacheModel("models/bots/boss_bot/static_boss_tank.mdl");
	PrecacheModel("models/bots/boss_bot/tank_track.mdl");
	PrecacheModel("models/bots/boss_bot/tank_track_R.mdl");
	PrecacheModel("models/bots/boss_bot/tank_track_L.mdl");
	new ent = -1;
	while ((ent = FindEntityByClassname(ent, "item_ammopack_small")) != -1) {
		pickup_cnt++;
	}
	ent = -1;
	while ((ent = FindEntityByClassname(ent, "item_healthkit_small")) != -1) {
		pickup_cnt++;
	}
	for (new i =0; i < sizeof(ammo_models); i++) {
		PrecacheModel(ammo_models[i]);
	}
	for (new i =0; i < sizeof(medi_models); i++) {
		PrecacheModel(medi_models[i]);
	}
}

// initialize plugin and hook events

public OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	cvBotActive = CreateConVar("bot_active", "0", "bot_active",
		FCVAR_PLUGIN | FCVAR_ARCHIVE);
	HookConVarChange(cvBotActive, Cvar_BotActive);
	cvBotForceAttack = FindConVar("bot_forceattack");
	cvBotJump = FindConVar("bot_jump");
	SetConVarFlags(cvBotJump, GetConVarFlags(cvBotJump) & ~FCVAR_CHEAT);
	cvBotMimic = FindConVar("bot_mimic");
	HookConVarChange(cvBotMimic, Cvar_BotMimic);
	SetConVarBool(cvBotMimic, false);
	cvBotMimicYawOffset = FindConVar("bot_mimic_yaw_offset");
	HookEvent("pumpkin_lord_killed", Event_PumpkinLordKilled);
	HookEvent("eyeball_boss_killer", Event_EyeballBossKiller);
	HookEvent("eyeball_boss_killed", Event_EyeballBossKilled);
	HookEvent("merasmus_escaped", Event_MerasmusRemoved);
	HookEvent("merasmus_killed", Event_MerasmusRemoved);
	HookEvent("mvm_tank_destroyed_by_players", Event_TankDestroyedByPlayers);
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("item_pickup", Event_ItemPickup);
	HookEvent("teamplay_restart_round", Event_TeamplayRestartRound);
	HookEvent("teamplay_round_start", Event_TeamplayRoundStart);
	RegAdminCmd("pdltest", Test, ADMFLAG_SLAY, "pdltest");
}

// test command

public Action:Test(c, args)
{
	decl String:mapname[50];
	GetCurrentMap(mapname, sizeof(mapname));
	if (strcmp(mapname, "achievement_idle_alpine_v2", false) == 0) {
		PrintToChatAll("true");
	} else {
		PrintToChatAll("false");
	}
	return Plugin_Handled;
}
