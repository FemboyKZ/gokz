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
	FormatEx(query, sizeof(query),
		"SELECT t.TimeGUID FROM Times t \
		INNER JOIN MapCourses mc ON mc.MapCourseID = t.MapCourseID \
		WHERE t.SteamID32 = %d AND mc.MapID = %d AND mc.Course = %d AND t.Mode = %d \
		AND t.TimeGUID IS NOT NULL AND t.TimeGUID <> '' \
		AND t.TimeID NOT IN ( \
			SELECT TimeID FROM ( \
				SELECT t2.TimeID FROM Times t2 \
				INNER JOIN MapCourses mc2 ON mc2.MapCourseID = t2.MapCourseID \
				WHERE t2.SteamID32 = %d AND mc2.MapID = %d AND mc2.Course = %d AND t2.Mode = %d \
				ORDER BY t2.RunTime ASC LIMIT %d \
			) AS keep_nub \
		) \
		AND t.TimeID NOT IN ( \
			SELECT TimeID FROM ( \
				SELECT t3.TimeID FROM Times t3 \
				INNER JOIN MapCourses mc3 ON mc3.MapCourseID = t3.MapCourseID \
				WHERE t3.SteamID32 = %d AND mc3.MapID = %d AND mc3.Course = %d AND t3.Mode = %d AND t3.Teleports = 0 \
				ORDER BY t3.RunTime ASC LIMIT %d \
			) AS keep_pro \
		)",
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
		if (FileExists(replayPath))
		{
			DeleteFile(replayPath);
		}
	}
}
