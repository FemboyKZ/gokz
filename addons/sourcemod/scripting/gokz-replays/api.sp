static GlobalForward H_OnReplaySaved;

// =====[ NATIVES ]=====

void CreateNatives()
{
	CreateNative("GOKZ_RP_GetPlaybackInfo", Native_RP_GetPlaybackInfo);
	CreateNative("GOKZ_RP_LoadJumpReplay", Native_RP_LoadJumpReplay);
	CreateNative("GOKZ_RP_UpdateReplayControlMenu", Native_RP_UpdateReplayControlMenu);
	CreateNative("GOKZ_RP_SaveJumpStatReplay", Native_RP_SaveJumpStatReplay);
	CreateNative("GOKZ_RP_GetClientFromBot", Native_RP_GetClientFromBot);
	CreateNative("GOKZ_RP_GetBotSlotFromClient", Native_RP_GetBotSlotFromClient);
	CreateNative("GOKZ_RP_SetBotIsAuto", Native_RP_SetBotIsAuto);
	CreateNative("GOKZ_RP_Pause", Native_RP_Pause);
	CreateNative("GOKZ_RP_Resume", Native_RP_Resume);
	CreateNative("GOKZ_RP_SkipToTick", Native_RP_SkipToTick);
	CreateNative("GOKZ_RP_GetTickCount", Native_RP_GetTickCount);
	CreateNative("GOKZ_RP_GetTickData", Native_RP_GetTickData);
}

public int Native_RP_GetPlaybackInfo(Handle plugin, int numParams)
{
	HUDInfo info;
	GetPlaybackState(GetNativeCell(1), info);
	SetNativeArray(2, info, sizeof(HUDInfo));
	return 1;
}

public int Native_RP_LoadJumpReplay(Handle plugin, int numParams)
{
	int len;
	GetNativeStringLength(2, len);
	char[] path = new char[len + 1];
	GetNativeString(2, path, len + 1);
	bool isAuto = numParams >= 3 && GetNativeCell(3);
	return LoadReplayBot(GetNativeCell(1), path, isAuto);
}

public int Native_RP_GetClientFromBot(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return -1;
	}
	return GetClientFromBot(bot);
}

public int Native_RP_GetBotSlotFromClient(Handle plugin, int numParams)
{
	return GetBotFromClient(GetNativeCell(1));
}

public int Native_RP_SetBotIsAuto(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return false;
	}
	SetBotIsAuto(bot, GetNativeCell(2));
	return true;
}

public int Native_RP_Pause(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return false;
	}
	PlaybackPause(bot);
	return true;
}

public int Native_RP_Resume(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return false;
	}
	PlaybackResume(bot);
	return true;
}

public int Native_RP_SkipToTick(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	int tick = GetNativeCell(2);
	if (bot < 0 || bot >= RP_MAX_BOTS || tick < 0 || tick >= GetPlaybackTickCount(bot))
	{
		return false;
	}
	if (!IsPlaybackReady(bot))
	{
		return false;
	}
	PlaybackSkipToTick(bot, tick);
	return true;
}

public int Native_RP_GetTickCount(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return 0;
	}
	return GetPlaybackTickCount(bot);
}

public int Native_RP_GetTickData(Handle plugin, int numParams)
{
	int bot = GetNativeCell(1);
	if (bot < 0 || bot >= RP_MAX_BOTS)
	{
		return false;
	}

	any output[RP_V2_TICK_DATA_BLOCKSIZE];
	if (!GetReplayTickData(bot, GetNativeCell(2), output))
	{
		return false;
	}

	SetNativeArray(3, output, RP_V2_TICK_DATA_BLOCKSIZE);
	return true;
}

public int Native_RP_UpdateReplayControlMenu(Handle plugin, int numParams)
{
	return view_as<int>(UpdateReplayControlMenu(GetNativeCell(1)));
}

public int Native_RP_SaveJumpStatReplay(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	char guid[64];
	GetNativeString(2, guid, sizeof(guid));
	int mode = GetNativeCell(3);
	int style = GetNativeCell(4);
	int jumptype = GetNativeCell(5);
	float distance = view_as<float>(GetNativeCell(6));
	int block = GetNativeCell(7);
	int strafes = GetNativeCell(8);
	float sync = view_as<float>(GetNativeCell(9));
	float pre = view_as<float>(GetNativeCell(10));
	float max = view_as<float>(GetNativeCell(11));
	int airtime = GetNativeCell(12);
	return view_as<int>(StartJumpStatReplaySave(client, guid, mode, style, jumptype, distance, block, strafes, sync, pre, max, airtime));
}


// =====[ FORWARDS ]=====

void CreateGlobalForwards()
{
	H_OnReplaySaved = new GlobalForward("GOKZ_RP_OnReplaySaved", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Float, Param_String, Param_Cell);
}

void Call_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath)
{
	Call_StartForward(H_OnReplaySaved);
	Call_PushCell(client);
	Call_PushCell(replayType);
	Call_PushString(map);
	Call_PushCell(course);
	Call_PushCell(timeType);
	Call_PushFloat(time);
	Call_PushString(filePath);
	// tempReplay, kept for signature compatibility with forks that store replays temporarily
	Call_PushCell(false);
	// The return value only matters to forks that delete temporary replays
	Action result;
	Call_Finish(result);
}
