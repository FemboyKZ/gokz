// =====[ NATIVES ]=====

void CreateNatives()
{
	CreateNative("GOKZ_RP_GetPlaybackInfo", Native_RP_GetPlaybackInfo);
	CreateNative("GOKZ_RP_LoadJumpReplay", Native_RP_LoadJumpReplay);
	CreateNative("GOKZ_RP_UpdateReplayControlMenu", Native_RP_UpdateReplayControlMenu);
	CreateNative("GOKZ_RP_SaveJumpStatReplay", Native_RP_SaveJumpStatReplay);
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
	int botClient = LoadReplayBot(GetNativeCell(1), path);
	return botClient;
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
