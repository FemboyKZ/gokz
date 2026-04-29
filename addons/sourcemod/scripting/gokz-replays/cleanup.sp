/*
	Run replay file cleanup.

	After a time is inserted into the database, prune run replay files for that
	(player, map, course, mode) group so that only the top-N nub times
	and the top-N pro (0 teleport) times have their .replay file kept on disk.

	Inspired by the per-group cap used by cs2kz-metamod's replay watcher
	(github.com/KZGlobalTeam/cs2kz-metamod/blob/master/src/kz/replays/watcher.cpp)
*/



static ConVar gCV_MaxReplaysPerGroup;
static ConVar gCV_MaxProReplaysPerGroup;
static ConVar gCV_CleanupDryRun;



// =====[ EVENTS ]=====

void OnPluginStart_Cleanup()
{
	AutoExecConfig_SetFile("gokz-replays", "sourcemod/gokz");
	AutoExecConfig_SetCreateFile(true);

	gCV_MaxReplaysPerGroup = AutoExecConfig_CreateConVar("gokz_max_replays_per_group", "3",
		"Maximum number of run replay files kept per (player, map, course, mode). Older/slower replays are deleted from disk.",
		_, true, 2.0);
	gCV_MaxProReplaysPerGroup = AutoExecConfig_CreateConVar("gokz_max_pro_replays_per_group", "3",
		"Maximum number of pro (no-teleport) run replay files kept per (player, map, course, mode). Older/slower replays are deleted from disk.",
		_, true, 2.0);
	gCV_CleanupDryRun = AutoExecConfig_CreateConVar("gokz_replay_cleanup_dryrun", "0",
		"If 1, replay cleanup logs the .replay files it would delete instead of deleting them. Use to verify the prune query before enabling deletion.",
		_, true, 0.0, true, 1.0);

	AutoExecConfig_ExecuteFile();
	AutoExecConfig_CleanFile();
}

void OnTimeInserted_Cleanup(int steamID, int mapID, int course, int mode)
{
	if (!gB_GOKZLocalDB)
	{
		return;
	}

	Database db = GOKZ_DB_GetDatabase();
	if (db == null)
	{
		return;
	}

	int maxNub = gCV_MaxReplaysPerGroup.IntValue;
	int maxPro = gCV_MaxProReplaysPerGroup.IntValue;

	char query[2048];
	FormatEx(query, sizeof(query), sql_cleanup_select_prunable,
		steamID, mapID, course, mode,
		steamID, mapID, course, mode, maxNub,
		steamID, mapID, course, mode, maxPro);

	db.Query(SQL_DeleteOldReplaysCallback, query, _, DBPrio_Low);
}



// =====[ SQL CALLBACKS ]=====

public void SQL_DeleteOldReplaysCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null)
	{
		LogError("Replay cleanup query failed: %s", error);
		return;
	}

	bool dryRun = gCV_CleanupDryRun.BoolValue;

	char guid[GOKZ_DB_TIME_GUID_MAX];
	char replayPath[PLATFORM_MAX_PATH];
	while (results.FetchRow())
	{
		results.FetchString(0, guid, sizeof(guid));
		if (guid[0] == 0)
		{
			continue;
		}
		GOKZ_RP_FormatRunReplayPath(replayPath, sizeof(replayPath), guid);
		if (!FileExists(replayPath))
		{
			continue;
		}
		if (dryRun)
		{
			LogMessage("[gokz-replays cleanup dryrun] would delete %s", replayPath);
		}
		else
		{
			DeleteFile(replayPath);
		}
	}
}
