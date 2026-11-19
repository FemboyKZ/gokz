
public Action Command_Lead(int client, int args)
{
    if (!IsClientInGame(client) || IsFakeClient(client))
        return Plugin_Handled;

    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Ghost)
    {
        GOKZ_PlayErrorSound(client);
        GOKZ_PrintToChat(client, true, "You're already using !ghost. Use !ghost again to stop first.");
        return Plugin_Handled;
    }    

    // Toggle OFF
    if (g_Session[client].Active())
    {
        StopLead(client);
        GOKZ_PrintToChat(client, true, "Lead stopped.");
        return Plugin_Handled;
    }

    // Distances, remembered per player
    int stopDist, startDist;
    LoadLeadDistances(client, stopDist, startDist);

    if (args == 1)
    {
        GOKZ_PlayErrorSound(client);
        GOKZ_PrintToChat(client, true, "Usage: !lead [stop distance] [start distance]");
        return Plugin_Handled;
    }
    if (args >= 2)
    {
        char a1[16], a2[16];
        GetCmdArg(1, a1, sizeof(a1));
        GetCmdArg(2, a2, sizeof(a2));
        stopDist  = StringToInt(a1);
        startDist = StringToInt(a2);

        if (startDist <= 10 || startDist >= 500 || stopDist <= 300 || stopDist >= 1000 || stopDist <= startDist)
        {
            GOKZ_PlayErrorSound(client);
            GOKZ_PrintToChat(client, true, "Invalid distances. Use: 300 < stopDist < 1000, 10 < startDist < 500, and stopDist > startDist.");
            return Plugin_Handled;
        }

        SaveLeadDistances(client, stopDist, startDist);
    }

    // Replay path
    char bestPath[PLATFORM_MAX_PATH];
    int foundMode = -1;
    if (!FindBestReplayFilePath(bestPath, sizeof(bestPath), client, foundMode))
    {
        GOKZ_PrintToChat(client, true, "No replay found for this map.");
        return Plugin_Handled;
    }

    WarnIfOtherMode(client, foundMode);

    // Spawn (returns BOT SLOT)
    int botSlot = GOKZ_RP_LoadJumpReplay(client, bestPath, true);
    if (botSlot < 0)
    {
        GOKZ_PrintToChat(client, true, "Failed to create replay bot. Try again.");
        return Plugin_Handled;
    }

    // Prime session
    g_Session[client].Reset();
    g_Session[client].user      = client;
    g_Session[client].botSlot   = botSlot;
    g_Session[client].stopDist  = stopDist;
    g_Session[client].startDist = startDist;

    g_Session[client].mode = LeadMode_Lead;

    CreateTimer(LEAD_ATTACH_INTERVAL, Timer_AttachLead,
        MakeAttachPack(GetClientUserId(client), NewSessionToken(client), 0),
        TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
    return Plugin_Handled;
}

public Action Timer_AttachLead(Handle timer, any data)
{
    DataPack pack = view_as<DataPack>(data);
    pack.Reset();
    int userId = pack.ReadCell();
    int token = pack.ReadCell();
    int attempt = pack.ReadCell();

    int user = GetClientOfUserId(userId);
    if (!user || !IsClientInGame(user) || IsFakeClient(user))
        return Plugin_Stop;

    // The session this timer was started for has since been torn down or replaced
    if (g_SessionToken[user] != token)
        return Plugin_Stop;

    if (!g_Session[user].Active() || g_Session[user].mode != LeadMode_Lead)
        return Plugin_Stop;

    int botClient = GOKZ_RP_GetClientFromBot(g_Session[user].botSlot);
    if (botClient <= 0 || !IsClientInGame(botClient) || !IsFakeClient(botClient))
    {
        // bot_add is asynchronous and can take well over a tick under load
        if (attempt < LEAD_ATTACH_MAX_ATTEMPTS)
        {
            CreateTimer(LEAD_ATTACH_INTERVAL, Timer_AttachLead, MakeAttachPack(userId, token, attempt + 1),
                TIMER_FLAG_NO_MAPCHANGE | TIMER_DATA_HNDL_CLOSE);
            return Plugin_Stop;
        }

        GOKZ_PrintToChat(user, true, "Replay bot not ready.");
        StopLead(user);
        return Plugin_Stop;
    }

    BindSessionBot(user, botClient);
    g_Session[user].trail = true;
    GetClientAbsOrigin(botClient, g_Session[user].lastPos);

    StartLeadFromNearestPoint(user, g_Session[user].botSlot);

    g_Session[user].timer = CreateTimer(0.2, Timer_LeadTick, GetClientUserId(user),
        TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);

    GOKZ_PrintToChat(user, true, "Lead started (stop {teamcolor}%d{default}, start {teamcolor}%d{default}). Use !lead again to stop.",
        g_Session[user].stopDist, g_Session[user].startDist);
    return Plugin_Stop;
}

public void GOKZ_OnTimerEnd_Post(int client, int course, float time, int teleportsUsed)
{
    // Nothing left to guide once the run is done
    if (g_Session[client].Active() && g_Session[client].mode == LeadMode_Lead)
    {
        StopLead(client);
        GOKZ_PrintToChat(client, true, "Lead stopped, run finished.");
    }
}

public Action Timer_LeadTick(Handle timer, any data)
{
    int user = GetClientOfUserId(data);
    if (!user || !IsClientInGame(user))
        return Plugin_Stop;

    if (!g_Session[user].Active())
    {
        // The handle dies with this callback, so don't leave it for StopTimer()
        g_Session[user].timer = null;
        return Plugin_Stop;
    }

    int bot = g_Session[user].botClient;
    if (bot <= 0 || !IsClientInGame(bot) || !IsPlayerAlive(user) || !IsPlayerAlive(bot))
        return Plugin_Continue;

    float u[3], b[3];
    GetClientAbsOrigin(user, u);
    GetClientAbsOrigin(bot,  b);
    float dist = GetVectorDistance(u, b);

    if (dist > float(g_Session[user].stopDist))
        GOKZ_RP_Pause(g_Session[user].botSlot);
    else if (dist < float(g_Session[user].startDist))
        GOKZ_RP_Resume(g_Session[user].botSlot);

    return Plugin_Continue;
}

static void StartLeadFromNearestPoint(int user, int botSlot)
{
    int total = GOKZ_RP_GetTickCount(botSlot);
    if (total <= 0)
    {
        GOKZ_PrintToChat(user, true, "No valid tick found.");
        return;
    }

    // Trim the run padding, unless the replay is shorter than the padding itself
    int start = LEAD_TICK_MARGIN;
    int end   = total - LEAD_TICK_MARGIN;
    if (end <= start)
    {
        start = 0;
        end   = total;
    }

    float vecUser[3];
    GetClientAbsOrigin(user, vecUser);

    float best = -1.0;
    int   bestTick = -1;

    float vecBot[3];
    for (int t = start; t < end; t += LEAD_TICK_STEP)
    {
        if (!GetReplayTickOrigin(botSlot, t, vecBot))
            continue;

        float d = GetVectorDistance(vecUser, vecBot);
        if (bestTick == -1 || d < best)
        {
            best = d;
            bestTick = t;
        }
    }

    if (bestTick != -1)
    {
        GOKZ_RP_SkipToTick(botSlot, bestTick);
        GOKZ_RP_Resume(botSlot);
        GOKZ_PrintToChat(user, true, "Resuming from tick {teamcolor}%d{default} (%.1f units).", bestTick, best);
    }
    else
    {
        GOKZ_PrintToChat(user, true, "No valid tick found.");
    }
}
