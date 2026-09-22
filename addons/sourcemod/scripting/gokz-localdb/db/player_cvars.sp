/*
	Tracks client input cvars over time (PlayerCvars table).
	A row is inserted only when a value changes.
	Replies are spoofable, so one disagreeing with the per-jump kFit is itself a signal.
*/

// Randomized per cycle so query timing can't be predicted
#define CVAR_TRACK_INTERVAL_MIN 60.0
#define CVAR_TRACK_INTERVAL_MAX 180.0
#define CVAR_VALUE_MAX 32

#define CVAR_TAKEOFF_THROTTLE 10.0

static const char g_TrackedCvars[][] =
{
	"sensitivity",
	"m_yaw",
	"m_pitch",
	"m_rawinput",
	"m_customaccel",
	"m_customaccel_scale",
	"m_customaccel_exponent",
	"m_customaccel_max",
	"m_mousespeed",
	"m_mouseaccel1",
	"m_mouseaccel2",
	// Scale mouse x/y into sidemove/forwardmove under +strafe
	"m_side",
	"m_forward"
};

static char lastCvarValue[MAXPLAYERS + 1][sizeof(g_TrackedCvars)][CVAR_VALUE_MAX];
static Handle cvarTimer[MAXPLAYERS + 1];
static float lastQueryTime[MAXPLAYERS + 1];

void StartCvarTracking(int client)
{
	if (IsFakeClient(client))
	{
		return;
	}

	for (int i = 0; i < sizeof(g_TrackedCvars); i++)
	{
		lastCvarValue[client][i][0] = '\0';
	}

	QueryTrackedCvars(client);
	ScheduleNextPoll(client);
}

void StopCvarTracking(int client)
{
	delete cvarTimer[client];
}

static void ScheduleNextPoll(int client)
{
	delete cvarTimer[client];
	cvarTimer[client] = CreateTimer(
		GetRandomFloat(CVAR_TRACK_INTERVAL_MIN, CVAR_TRACK_INTERVAL_MAX),
		Timer_QueryCvars, GetClientUserId(client));
}

public Action Timer_QueryCvars(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);
	if (client == 0)
	{
		return Plugin_Stop;
	}
	// Timer already freed itself, don't let ScheduleNextPoll delete it
	cvarTimer[client] = null;
	QueryTrackedCvars(client);
	ScheduleNextPoll(client);
	return Plugin_Stop;
}

static void QueryTrackedCvars(int client)
{
	lastQueryTime[client] = GetGameTime();
	for (int i = 0; i < sizeof(g_TrackedCvars); i++)
	{
		QueryClientConVar(client, g_TrackedCvars[i], OnCvarQueried, GetClientUserId(client));
	}
}

void RequeryCvarsOnTakeoff(int client)
{
	if (IsFakeClient(client) || cvarTimer[client] == null)
	{
		return;
	}
	if (GetGameTime() - lastQueryTime[client] < CVAR_TAKEOFF_THROTTLE)
	{
		return;
	}
	QueryTrackedCvars(client);
}

public void OnCvarQueried(QueryCookie cookie, int client, ConVarQueryResult result,
	const char[] cvarName, const char[] cvarValue, any userid)
{
	if (GetClientOfUserId(userid) != client)
	{
		return;
	}

	int index = -1;
	for (int i = 0; i < sizeof(g_TrackedCvars); i++)
	{
		if (StrEqual(cvarName, g_TrackedCvars[i]))
		{
			index = i;
			break;
		}
	}
	if (index == -1)
	{
		return;
	}

	// Stock clients have all these cvars, so a failed reply means something blocks queries
	char value[CVAR_VALUE_MAX];
	if (result == ConVarQuery_Okay)
	{
		strcopy(value, sizeof(value), cvarValue);
	}
	else
	{
		FormatEx(value, sizeof(value), "<queryfail:%d>", result);
	}

	if (StrEqual(value, lastCvarValue[client][index]))
	{
		return;
	}
	strcopy(lastCvarValue[client][index], CVAR_VALUE_MAX, value);

	int steamid = GetSteamAccountID(client);
	if (steamid == 0 || gH_DB == null)
	{
		return;
	}

	// Cached copy is already capped to the column length
	char safeName[2 * CVAR_VALUE_MAX + 1];
	char safeValue[2 * CVAR_VALUE_MAX + 1];
	SQL_EscapeString(gH_DB, cvarName, safeName, sizeof(safeName));
	SQL_EscapeString(gH_DB, lastCvarValue[client][index], safeValue, sizeof(safeValue));

	char query[512];
	FormatEx(query, sizeof(query), sql_playercvars_insert, steamid, safeName, safeValue);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_Low);
}
