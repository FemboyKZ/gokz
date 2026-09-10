/*
	Hooks between specifically named trigger_multiples and GOKZ.
*/



static Regex RE_BonusStartZone;
static Regex RE_BonusEndZone;
static bool touchedGroundSinceTouchingStartZone[MAXPLAYERS + 1];
static int startZoneTouchCount[MAXPLAYERS + 1];



// =====[ PUBLIC ]=====

bool IsTouchingStartZone(int client)
{
	return startZoneTouchCount[client] > 0;
}



// =====[ EVENTS ]=====

void OnClientPutInServer_MapZones(int client)
{
	// EndTouch may not reach us for a disconnecting client, so don't inherit their count.
	startZoneTouchCount[client] = 0;
}

void OnPluginStart_MapZones()
{
	RE_BonusStartZone = CompileRegex(GOKZ_BONUS_START_ZONE_NAME_REGEX);
	RE_BonusEndZone = CompileRegex(GOKZ_BONUS_END_ZONE_NAME_REGEX);
}

void OnStartTouchGround_MapZones(int client)
{
	touchedGroundSinceTouchingStartZone[client] = true;
}

void OnEntitySpawned_MapZones(int entity)
{
	char buffer[32];

	GetEntityClassname(entity, buffer, sizeof(buffer));
	if (!StrEqual("trigger_multiple", buffer, false))
	{
		return;
	}

	if (GetEntityName(entity, buffer, sizeof(buffer)) == 0)
	{
		return;
	}

	int course = 0;
	if (StrEqual(GOKZ_START_ZONE_NAME, buffer, false))
	{
		HookSingleEntityOutput(entity, "OnStartTouch", OnStartZoneStartTouch);
		HookSingleEntityOutput(entity, "OnEndTouch", OnStartZoneEndTouch);
		RegisterCourseStart(course);
	}
	else if (StrEqual(GOKZ_END_ZONE_NAME, buffer, false))
	{
		HookSingleEntityOutput(entity, "OnStartTouch", OnEndZoneStartTouch);
		RegisterCourseEnd(course);
	}
	else if ((course = GetStartZoneBonusNumber(entity)) != -1)
	{
		HookSingleEntityOutput(entity, "OnStartTouch", OnBonusStartZoneStartTouch);
		HookSingleEntityOutput(entity, "OnEndTouch", OnBonusStartZoneEndTouch);
		RegisterCourseStart(course);
	}
	else if ((course = GetEndZoneBonusNumber(entity)) != -1)
	{
		HookSingleEntityOutput(entity, "OnStartTouch", OnBonusEndZoneStartTouch);
		RegisterCourseEnd(course);
	}
}

public void OnStartZoneStartTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	startZoneTouchCount[activator]++;
	ProcessStartZoneStartTouch(activator, 0);
}

public void OnStartZoneEndTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	DecrementStartZoneTouchCount(activator);
	ProcessStartZoneEndTouch(activator, 0);
}

public void OnEndZoneStartTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	ProcessEndZoneStartTouch(activator, 0);
}

public void OnBonusStartZoneStartTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	startZoneTouchCount[activator]++;
	int course = GetStartZoneBonusNumber(caller);
	if (!GOKZ_IsValidCourse(course, true))
	{
		return;
	}

	ProcessStartZoneStartTouch(activator, course);
}

public void OnBonusStartZoneEndTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	DecrementStartZoneTouchCount(activator);
	int course = GetStartZoneBonusNumber(caller);
	if (!GOKZ_IsValidCourse(course, true))
	{
		return;
	}

	ProcessStartZoneEndTouch(activator, course);
}

public void OnBonusEndZoneStartTouch(const char[] name, int caller, int activator, float delay)
{
	if (!IsValidEntity(caller) || !IsValidClient(activator))
	{
		return;
	}

	int course = GetEndZoneBonusNumber(caller);
	if (!GOKZ_IsValidCourse(course, true))
	{
		return;
	}

	ProcessEndZoneStartTouch(activator, course);
}



// =====[ PRIVATE ]=====

static void DecrementStartZoneTouchCount(int client)
{
	if (startZoneTouchCount[client] > 0)
	{
		startZoneTouchCount[client]--;
	}
}

static void ProcessStartZoneStartTouch(int client, int course)
{
	touchedGroundSinceTouchingStartZone[client] = Movement_GetOnGround(client);

	GOKZ_StopTimer(client, false);
	SetCurrentCourse(client, course);

	OnStartZoneStartTouch_Teleports(client, course);
}

static void ProcessStartZoneEndTouch(int client, int course)
{
	if (!touchedGroundSinceTouchingStartZone[client])
	{
		return;
	}

	GOKZ_StartTimer(client, course, true);
	GOKZ_ResetVirtualButtonPosition(client, true);
}

static void ProcessEndZoneStartTouch(int client, int course)
{
	GOKZ_EndTimer(client, course);
	GOKZ_ResetVirtualButtonPosition(client, false);
}

static int GetStartZoneBonusNumber(int entity)
{
	return GOKZ_MatchIntFromEntityName(entity, RE_BonusStartZone, 1);
}

static int GetEndZoneBonusNumber(int entity)
{
	return GOKZ_MatchIntFromEntityName(entity, RE_BonusEndZone, 1);
} 