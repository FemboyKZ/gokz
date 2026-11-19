#define LEAD_ATTACH_INTERVAL 0.2
#define LEAD_ATTACH_MAX_ATTEMPTS 15
#define LEAD_BEAM_TICK_INTERVAL 4
#define LEAD_BEAM_LIFE 1.0
// Pre and post run padding
#define LEAD_TICK_MARGIN 256
#define LEAD_TICK_STEP 16

// Command bounds are exclusive, so option ranges sit one inside them
#define LEAD_OPTION_STOP "GOKZ_LEAD_StopDistance"
#define LEAD_OPTION_START "GOKZ_LEAD_StartDistance"
#define LEAD_STOP_DEFAULT 500
#define LEAD_STOP_MIN 301
#define LEAD_STOP_MAX 999
#define LEAD_START_DEFAULT 200
#define LEAD_START_MIN 11
#define LEAD_START_MAX 499

LeadSession g_Session[MAXPLAYERS + 1];
int g_BeamIndex = -1;
int g_BeamTick[MAXPLAYERS + 1];
int g_BotOwner[MAXPLAYERS + 1];
int g_SessionToken[MAXPLAYERS + 1];
// GOKZ_OnOptionsMenuReady never fires for a late loaded plugin
bool g_OptionsRegistered;

enum LeadMode
{
    LeadMode_None = 0,
    LeadMode_Lead,
    LeadMode_Ghost
}

enum struct LeadSession
{
    int   user;
    int   botSlot;
    int   botClient;
    Handle timer;
    int   stopDist;
    int   startDist;
    float lastPos[3];
    bool  trail;
    LeadMode mode;

    // Does not stop the timer, since it is also used where the timer is already dead.
    // Call StopTimer() first when tearing a live session down.
    void Reset()
    {
        this.user      = 0;
        this.botSlot   = -1;
        this.botClient = 0;
        this.timer     = null;
        this.stopDist  = 500;
        this.startDist = 200;
        this.lastPos[0] = this.lastPos[1] = this.lastPos[2] = 0.0;
        this.trail     = false;
        this.mode      = LeadMode_None;
    }

    void StopTimer()
    {
        if (this.timer != null)
            KillTimer(this.timer);
        this.timer = null;
    }

    bool Active() { return this.botSlot >= 0; }
}

stock void BindSessionBot(int user, int botClient)
{
    g_Session[user].botClient = botClient;
    g_BotOwner[botClient] = user;
}

stock void RegisterLeadOptions()
{
    GOKZ_RegisterOption(LEAD_OPTION_STOP, "Distance at which your lead bot stops to wait",
        OptionType_Int, LEAD_STOP_DEFAULT, LEAD_STOP_MIN, LEAD_STOP_MAX);
    GOKZ_RegisterOption(LEAD_OPTION_START, "Distance at which your lead bot sets off again",
        OptionType_Int, LEAD_START_DEFAULT, LEAD_START_MIN, LEAD_START_MAX);
    g_OptionsRegistered = true;
}

// Defaults if the options never registered or the stored pair is inconsistent
stock void LoadLeadDistances(int client, int &stopDist, int &startDist)
{
    stopDist = LEAD_STOP_DEFAULT;
    startDist = LEAD_START_DEFAULT;

    if (!g_OptionsRegistered)
    {
        return;
    }

    int stop = GOKZ_GetOption(client, LEAD_OPTION_STOP);
    int start = GOKZ_GetOption(client, LEAD_OPTION_START);

    if (stop >= LEAD_STOP_MIN && stop <= LEAD_STOP_MAX
        && start >= LEAD_START_MIN && start <= LEAD_START_MAX
        && stop > start)
    {
        stopDist = stop;
        startDist = start;
    }
}

stock void SaveLeadDistances(int client, int stopDist, int startDist)
{
    if (!g_OptionsRegistered)
    {
        return;
    }

    GOKZ_SetOption(client, LEAD_OPTION_STOP, stopDist);
    GOKZ_SetOption(client, LEAD_OPTION_START, startDist);
}

stock void WarnIfOtherMode(int client, int foundMode)
{
    int mode = GOKZ_GetCoreOption(client, Option_Mode);
    if (foundMode < 0 || foundMode == mode)
    {
        return;
    }

    GOKZ_PrintToChat(client, true, "No {teamcolor}%s{default} replay on this map, using {teamcolor}%s{default}.",
        gC_ModeNamesShort[mode], gC_ModeNamesShort[foundMode]);
}

stock int NewSessionToken(int user)
{
    return ++g_SessionToken[user];
}

stock void StopLead(int user)
{
    g_SessionToken[user]++;
    g_Session[user].StopTimer();

    if (g_Session[user].botClient > 0)
        g_BotOwner[g_Session[user].botClient] = 0;

    if (g_Session[user].botSlot >= 0)
    {
        GOKZ_RP_SetBotIsAuto(g_Session[user].botSlot, false);
        GOKZ_RP_KickBot(g_Session[user].botSlot);
    }

    g_Session[user].Reset();
}

stock DataPack MakeAttachPack(int userId, int token, int attempt)
{
    DataPack pack = new DataPack();
    pack.WriteCell(userId);
    pack.WriteCell(token);
    pack.WriteCell(attempt);
    return pack;
}

stock int FindOwnerByBotClient(int botClient)
{
    if (botClient <= 0 || botClient > MaxClients)
        return 0;

    // Validated against the session so a stale entry can never resolve
    int owner = g_BotOwner[botClient];
    if (owner <= 0 || !g_Session[owner].Active() || g_Session[owner].botClient != botClient)
        return 0;

    return owner;
}
