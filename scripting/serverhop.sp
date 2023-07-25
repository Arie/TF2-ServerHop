#pragma semicolon 1
#pragma newdecls required
#include <sourcemod>

#define PLUGIN_VERSION "1.0.2"
#define PLUGIN_DESCRIPTION "Provides server info with join option"
#define MAX_SERVERS 10
#define MAX_STR_LEN 160
#define MAX_INFO_LEN 200

#define A2S_INFO "\xFF\xFF\xFF\xFF\x54Source Engine Query"
#define A2S_SIZE 25

#define MAX_STR_LEN 160

int
	g_iServerCount,
	g_iServerPort[MAX_SERVERS];
char
	g_sServerName[MAX_SERVERS][MAX_STR_LEN],
	g_sServerAddress[MAX_SERVERS][MAX_STR_LEN],
	g_sAddress[MAXPLAYERS+1][MAX_STR_LEN],
	g_sServer[MAXPLAYERS+1][MAX_INFO_LEN];
bool
	g_bConnectedFromFavorites[MAXPLAYERS+1],
	g_bLateLoad;
ConVar
	g_cvarHopTrigger,
	g_cvarBroadcastHops;

public Plugin myinfo = {
	name = "Server Hop",
	author = "[GRAVE] rig0r, JoinedSenses",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "https://github.com/JoinedSenses/TF2-ServerHop"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	if (GetEngineVersion() == Engine_CSGO) {
		strcopy(error, err_max, "ServerHop is incompatible with this game");
		return APLRes_SilentFailure;
	}

	g_bLateLoad = late;
	return APLRes_Success;
}

public void OnPluginStart() {
	LoadTranslations("serverhop.phrases");

	CreateConVar("sm_serverhop_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD).SetString(PLUGIN_VERSION);
  // convar setup
	g_cvarHopTrigger = CreateConVar(
		"sm_hop_trigger",
		"!sdr",
		"What players have to type in chat to activate the plugin (besides !hop)"
	);
	g_cvarBroadcastHops = CreateConVar(
		"sm_hop_broadcasthops",
		"1",
		"Set to 1 if you want a broadcast message when a player hops to another server"
	);

	AutoExecConfig(true, "plugin.serverhop");

	RegConsoleCmd("say", Command_Say);
	RegConsoleCmd("say_team", Command_Say);
	RegConsoleCmd("sm_hop", Command_Hop, "Hop servers.");
	RegConsoleCmd("sm_servers", Command_Servers, "Hop servers.");

	char path[MAX_STR_LEN];

	BuildPath(Path_SM, path, sizeof(path), "configs/serverhop.cfg");
	KeyValues kv = new KeyValues("Servers");

	if (!kv.ImportFromFile(path)) {
		LogToGame("Error loading server list");
		SetFailState("Unable to import server list from file.");
	}

	int i;
	kv.Rewind();
	if (!kv.GotoFirstSubKey()) {
		SetFailState("Unable to find first server in file.");
	}

	do {
		kv.GetSectionName(g_sServerName[i], MAX_STR_LEN);
		kv.GetString("address", g_sServerAddress[i], MAX_STR_LEN);
		g_iServerPort[i] = kv.GetNum("port", 27015);
	} while (++i < MAX_SERVERS && kv.GotoNextKey());

	if (i == MAX_SERVERS && kv.GotoNextKey()) {
		LogError("You have exceeded the cap for max servers of %i. To add more, edit the value of MAX_SERVERS and recompile.", MAX_SERVERS);
	}

	delete kv;

	g_iServerCount = i;

	if (g_bLateLoad) {
		char clientConnectMethod[64];
		for (int client = 1; client <= MaxClients; client++) {
			if (IsClientInGame(client) && !IsFakeClient(client)) {
				GetClientInfo(client, "cl_connectmethod", clientConnectMethod, sizeof(clientConnectMethod));

				if (!StrEqual(clientConnectMethod, "serverbrowser_internet")) {
					g_bConnectedFromFavorites[client] = true;
				}
			}
		}
	}
}

public Action Command_Hop(int client, int args) {
	ServerMenu(client);
	return Plugin_Handled;
}

public Action Command_Servers(int client, int args) {
	ServerMenu(client);
	return Plugin_Handled;
}

public Action Command_Say(int client, int args) {
	char text[MAX_STR_LEN];
	int startidx = 0;

	if (!GetCmdArgString(text, sizeof(text))) {
		return Plugin_Continue;
	}

	int last = strlen(text) - 1;
	if (text[last] == '\"') {
		text[last] = '\0';
		startidx = 1;
	}

	char trigger[MAX_STR_LEN];
	g_cvarHopTrigger.GetString(trigger, sizeof(trigger));

	if (strcmp(text[startidx], trigger, false) == 0 || strcmp(text[startidx], "!hop", false) == 0) {
		ServerMenu(client);
	}

	return Plugin_Continue;
}


public void OnClientPutInServer(int client) {
	char clientConnectMethod[64];
	GetClientInfo(client, "cl_connectmethod", clientConnectMethod, sizeof(clientConnectMethod));
	if (!StrEqual(clientConnectMethod, "serverbrowser_internet")) {
		g_bConnectedFromFavorites[client] = true;
	}
}

public void OnClientDisconnect(int client) {
	g_bConnectedFromFavorites[client] = false;
}

public Action ServerMenu(int client) {
	char serverNumStr[MAX_STR_LEN];
	char menuTitle[MAX_STR_LEN];

	Menu menu = new Menu(Menu_Handler, MENU_ACTIONS_DEFAULT);
	Format(menuTitle, sizeof(menuTitle), "%T", "SelectServer", client);
	menu.SetTitle(menuTitle);

	for (int i = 0; i < g_iServerCount; i++) {
		if (strlen(g_sServerName[i]) > 0) {
			IntToString(i, serverNumStr, sizeof(serverNumStr));
			menu.AddItem(serverNumStr, g_sServerName[i]);
		}
	}
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int Menu_Handler(Menu menu, MenuAction action, int param1, int param2) {
	if (action == MenuAction_Select) {
		char infobuf[MAX_STR_LEN];

		menu.GetItem(param2, infobuf, sizeof(infobuf));
		int serverNum = StringToInt(infobuf);
		char menuTitle[MAX_STR_LEN];
		Format(menuTitle, sizeof(menuTitle), "%T", "AboutToJoinServer", param1);
		Format(g_sAddress[param1], MAX_STR_LEN, "%s:%i", g_sServerAddress[serverNum], g_iServerPort[serverNum]);
		g_sServer[param1] = g_sServerName[serverNum];

		if (!g_bConnectedFromFavorites[param1]) {
			PrintToChat(param1, "\x01[\x03ServerHop\x01] Due to Valve game change, clients must connect via favorites to be redirected by server.");
			PrintToChat(param1, "\x01[\x03ServerHop\x01] %s:\x03 %s", g_sServer[param1], g_sAddress[param1]);
			return;
		}

		Panel panel = new Panel();
		panel.SetTitle(menuTitle);
		panel.DrawText(g_sServerName[serverNum]);
		panel.DrawText("Is this correct?");
		panel.CurrentKey = 3;
		panel.DrawItem("Accept");
		panel.DrawItem("Decline");
		panel.Send(param1, MenuConfirmHandler, 15);

		delete panel;
	}
	else if (action == MenuAction_End) {
		delete menu;
	}
}

public int MenuConfirmHandler(Menu menu, MenuAction action, int param1, int param2) {
	if (param2 == 3) {
		ClientCommand(param1, "redirect %s", g_sAddress[param1]);
		// broadcast to all
		if (g_cvarBroadcastHops.BoolValue) {
			char clientName[MAX_NAME_LENGTH];
			GetClientName(param1, clientName, sizeof(clientName));
			PrintToChatAll("\x01[\x03hop\x01] %t", "HopNotification", clientName, g_sServer[param1]);
		}
	}
	g_sAddress[param1][0] = '\0';
	g_sServer[param1][0] = '\0';
}
