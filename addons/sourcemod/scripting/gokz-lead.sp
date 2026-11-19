#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#include <gokz/core>
#include <gokz/replays>

#undef REQUIRE_PLUGIN
#include <gokz/localranks>
#define REQUIRE_PLUGIN

#include "gokz-lead/lead_session.sp"
#include "gokz-lead/utils.sp"
#include "gokz-lead/lead.sp"
#include "gokz-lead/ghost.sp"

public Plugin myinfo =
{
    name        = "GOKZ Replay Bot Lead",
    author      = "Cinyan10, (dots mod)",
    description = "Per-user lead bots with distance pause/resume.",
    version     = "1.1.1",
    url         = "https://axekz.com/"
};

public void OnPluginStart()
{
    RegConsoleCmd("sm_ghost", Command_Ghost);
    RegConsoleCmd("sm_lead", Command_Lead);
    for (int i = 1; i <= MaxClients; i++)
        g_Session[i].Reset();
}

public void OnMapStart()
{
    g_BeamIndex = PrecacheModel("materials/sprites/purplelaser1.vmt", true);
    for (int i = 1; i <= MaxClients; i++)
    {
        g_Session[i].Reset();
        g_BotOwner[i] = 0;
        g_BeamTick[i] = 0;
    }
}

public void GOKZ_OnOptionsMenuReady(TopMenu topMenu)
{
    RegisterLeadOptions();
}

public void OnClientDisconnect_Post(int client)
{
    if (client <= 0) return;

    g_BeamTick[client] = 0;

    // If a user with an active session leaves, stop their lead.
    if (client <= MaxClients && g_Session[client].Active())
    {
        StopLead(client);
        return;
    }

    // If a replay bot used by someone disconnected (likely auto-kicked),
    // just clean that user's session without kicking/SetBotIsAuto again.
    int owner = FindOwnerByBotClient(client);
    g_BotOwner[client] = 0;
    if (owner > 0)
    {
        g_SessionToken[owner]++;
        g_Session[owner].StopTimer();

        // zero out bot references; leave other fields intact
        g_Session[owner].botClient = 0;
        g_Session[owner].botSlot   = -1;
        g_Session[owner].trail     = false;
    }
}


// Draw beam
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3],
    int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
    if (!IsClientInGame(client) || !IsFakeClient(client) || !IsPlayerAlive(client))
        return Plugin_Continue;

    int owner = FindOwnerByBotClient(client);
    if (owner <= 0 || !g_Session[owner].trail)
        return Plugin_Continue;

    // A beam every tick with a 4s life leaves hundreds of them alive at once
    if (++g_BeamTick[client] < LEAD_BEAM_TICK_INTERVAL)
        return Plugin_Continue;
    g_BeamTick[client] = 0;

    float v1[3], v2[3];
    GetClientAbsOrigin(client, v1);
    CopyVec(g_Session[owner].lastPos, v2);

    TE_SetupBeamPoints(v1, v2, g_BeamIndex, 0, 0, 0, LEAD_BEAM_LIFE, 10.0, 10.0, 10, 0.0, {42, 165, 247, 255}, 0);
    TE_SendToClient(owner);

    CopyVec(v1, g_Session[owner].lastPos);
    return Plugin_Continue;
}
