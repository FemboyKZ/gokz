#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#undef REQUIRE_PLUGIN
#include <gokz/localranks>
#define REQUIRE_PLUGIN

#include "gokz-lead/utils.sp"

ConVar gCV_Enable;
bool g_CurrentIsServerRecord = false;
int g_BotSlot = -1;
int g_BotClient = 0;

int g_StartRetries = 0;
#define AR_MAX_START_RETRIES 10
#define AR_RETRY_INTERVAL 3.0

public Plugin myinfo =
{
    name        = "GOKZ Auto Replay Bot",
    author      = "Cinyan10, (dots mod)",
    description = "Automatically loads a replay bot when the first human joins.",
    version     = "1.0.1",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    gCV_Enable = CreateConVar("gokz_autoreplay_enable", "1",
        "Whether a replay bot is loaded automatically and kept looping.",
        _, true, 0.0, true, 1.0);
    gCV_Enable.AddChangeHook(OnEnableChanged);
    AutoExecConfig(true, "gokz-autoreplay");

    CreateTimer(1.0, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnEnableChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
    if (convar.BoolValue)
    {
        g_StartRetries = 0;
        CreateTimer(0.5, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }
    else
    {
        StopOwnBot();
    }
}

public void OnMapStart()
{
    g_BotSlot = -1;
    g_BotClient = 0;
    g_CurrentIsServerRecord = false;
    g_StartRetries = 0;
}

static void ScheduleStartRetry()
{
    if (g_StartRetries >= AR_MAX_START_RETRIES)
    {
        return;
    }

    g_StartRetries++;
    CreateTimer(AR_RETRY_INTERVAL, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void OnClientPutInServer(int client) {
    if (!IsValidClient(client) || IsFakeClient(client))
        return;

    int humans = 0;
    for (int i = 1; i <= MaxClients; i++)
    {
        if (IsClientInGame(i) && !IsFakeClient(i))
            humans++;
    }

    if (humans == 1)
    {
        CreateTimer(1.0, Timer_KickBotsThenStartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }
}

public Action GOKZ_RP_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath, bool tempReplay)
{
    CreateTimer(2.0, Timer_CheckAndMaybeReloadReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Continue;
}

public Action Timer_KickBotsThenStartReplay(Handle timer, any data)
{
    if (!gCV_Enable.BoolValue)
    {
        return Plugin_Stop;
    }

    KickUnmanagedBots();
    StopOwnBot();
    CreateTimer(1.0, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_ReloadReplay(Handle timer, any data)
{
    StopOwnBot();
    CreateTimer(1.0, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    return Plugin_Stop;
}

public Action Timer_StartReplay(Handle timer, any data)
{
    StartReplayForCurrentMap();
    return Plugin_Stop;
}

// Only bots gokz-replays doesn't own, e.g. ones bot_quota added
static void KickUnmanagedBots()
{
    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsFakeClient(i) || IsClientSourceTV(i))
            continue;

        if (GOKZ_RP_GetBotSlotFromClient(i) >= 0)
            continue;

        // Never claimed, so its current name is still the profile name bot_kick matches
        char name[MAX_NAME_LENGTH];
        GetClientName(i, name, sizeof(name));
        ServerCommand("bot_kick \"%s\"", name);
    }
}

// True while the slot is still ours, including before bot_add has answered
static bool OwnBotAlive()
{
    if (g_BotSlot < 0)
        return false;

    int botClient = GOKZ_RP_GetClientFromBot(g_BotSlot);

    if (g_BotClient == 0)
    {
        if (botClient <= 0)
            return true;
        g_BotClient = botClient;
    }

    if (botClient != g_BotClient || !IsClientInGame(g_BotClient) || !IsFakeClient(g_BotClient))
    {
        g_BotSlot = -1;
        g_BotClient = 0;
        return false;
    }

    return true;
}

static void StopOwnBot()
{
    if (!OwnBotAlive())
    {
        g_BotSlot = -1;
        g_BotClient = 0;
        return;
    }

    // Dropping auto lets gokz-replays clean the bot up if the kick doesn't land
    GOKZ_RP_SetBotIsAuto(g_BotSlot, false);
    GOKZ_RP_KickBot(g_BotSlot);

    g_BotSlot = -1;
    g_BotClient = 0;
}

static void StartReplayForCurrentMap()
{
    if (!gCV_Enable.BoolValue)
    {
        return;
    }

    char bestPath[PLATFORM_MAX_PATH];

    int client = FindFirstHumanClient();
    if (client == 0)
    {
        LogMessage("[AutoReplay] No human client to own the replay load.");
        return;
    }

    bool foundServerRecord = FindBestServerRecordReplay(bestPath, sizeof(bestPath));
    bool found = foundServerRecord;

    if (!foundServerRecord)
    {
        LogMessage("[AutoReplay] No server-record replay found; falling back to any replay…");
        found = FindBestReplayFilePath(bestPath, sizeof(bestPath));
        if (!found)
        {
            LogMessage("[AutoReplay] No replay found at all for this map.");
            ScheduleStartRetry();
            return;
        }
    }

    int slot = GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    if (slot < 0)
    {
        LogMessage("[AutoReplay] Failed to load replay: %s", bestPath);
        ScheduleStartRetry();
        return;
    }

    g_StartRetries = 0;
    g_BotSlot = slot;
    g_BotClient = 0;
    g_CurrentIsServerRecord = foundServerRecord;
    LogMessage("[AutoReplay] Loaded replay: %s (serverRecord=%d)", bestPath, g_CurrentIsServerRecord);
}


public Action Timer_CheckAndMaybeReloadReplay(Handle timer, any data)
{
    if (!gCV_Enable.BoolValue)
    {
        return Plugin_Stop;
    }

    char bestPath[PLATFORM_MAX_PATH];

    // Prefer server-record; remember if we found one
    bool foundServerRecord = FindBestServerRecordReplay(bestPath, sizeof(bestPath));
    bool found = foundServerRecord;
    if (!found)
        found = FindBestReplayFilePath(bestPath, sizeof(bestPath));

    if (!found)
    {
        return Plugin_Stop;
    }

    if (!OwnBotAlive())
    {
        CreateTimer(0.1, Timer_StartReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    // Upgrade to server-record even if ticks are equal
    if (foundServerRecord && !g_CurrentIsServerRecord)
    {
        CreateTimer(0.5, Timer_ReloadReplay, _, TIMER_FLAG_NO_MAPCHANGE);
        return Plugin_Stop;
    }

    int bestTicks = -1;
    ReadReplayTickCount(bestPath, bestTicks);
    int currentTicks = GOKZ_RP_GetTickCount(g_BotSlot);

    // Otherwise reload only if strictly better
    if (bestTicks > 0 && (currentTicks <= 0 || bestTicks < currentTicks))
    {
        CreateTimer(0.5, Timer_ReloadReplay, _, TIMER_FLAG_NO_MAPCHANGE);
    }

    return Plugin_Stop;
}
