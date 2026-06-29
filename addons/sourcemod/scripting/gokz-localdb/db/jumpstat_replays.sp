/*
	Archive of EVERY valid jumpstat as a replay.
*/



static ConVar gCV_JSReplays_Enable;
static ConVar gCV_JSReplays_Max;
static ConVar gCV_JSReplays_CleanupBatch;

void JSReplays_OnPluginStart()
{
	gCV_JSReplays_Enable = CreateConVar("gokz_js_replays", "1",
		"Archive every valid jumpstat as a replay (separate from PB replays).",
		_, true, 0.0, true, 1.0);
	gCV_JSReplays_Max = CreateConVar("gokz_js_replays_max", "30",
		"Max stored jumpstat replays per player per mode per jump type. Lowest distance pruned on map end.",
		_, true, 1.0);
	gCV_JSReplays_CleanupBatch = CreateConVar("gokz_js_replays_cleanup_batch", "500",
		"Max jumpstat replays pruned per map end (keeps cleanup non-blocking). 0 disables cleanup.",
		_, true, 0.0);
	AutoExecConfig(true, "gokz-localdb");
}

void JSReplays_OnLanding(Jump jump)
{
	if (gCV_JSReplays_Enable == null || !gCV_JSReplays_Enable.BoolValue || gH_DB == null)
	{
		return;
	}

	int client = jump.jumper;
	if (!gB_ClientSetUp[client] || IsFakeClient(client))
	{
		return;
	}

	// gokz-replays must be loaded to write the file.
	if (GetFeatureStatus(FeatureType_Native, "GOKZ_RP_SaveJumpStatReplay") != FeatureStatus_Available)
	{
		return;
	}

	// Same validity filter as OnLanding_SaveJumpstat: no invalid/fall/other,
	// no negative offset (except ladder jumps), within distance bounds.
	if (jump.type == JumpType_Invalid || jump.type == JumpType_FullInvalid
		 || jump.type == JumpType_Fall || jump.type == JumpType_Other
		 || jump.type != JumpType_LadderJump && jump.offset < -JS_OFFSET_EPSILON
		 || jump.distance > JS_MAX_JUMP_DISTANCE
		 || jump.type == JumpType_LadderJump && jump.distance < JS_MIN_LAJ_BLOCK_DISTANCE
		 || jump.type != JumpType_LadderJump && jump.distance < JS_MIN_BLOCK_DISTANCE)
	{
		return;
	}

	int steamid = GetSteamAccountID(client);
	if (steamid == 0)
	{
		return;
	}

	int mode = GOKZ_GetCoreOption(client, Option_Mode);
	int style = GOKZ_GetCoreOption(client, Option_Style);
	int airtime = RoundToNearest(jump.duration * GetTickInterval() * GOKZ_DB_JS_AIRTIME_PRECISION);

	// Unique filename. Same scheme as the run GUID.
	gI_RunCounter++;
	char guid[GOKZ_DB_TIME_GUID_MAX];
	FormatEx(guid, sizeof(guid), "%x-%x-%x-%x-%x",
		steamid, GetTime(), GetSysTickCount(), GetURandomInt(), gI_RunCounter);

	// Schedule the replay write (gokz-replays writes it after the post-jump breather).
	if (!GOKZ_RP_SaveJumpStatReplay(client, guid, mode, style, jump.type, jump.distance,
			jump.block, jump.strafes, jump.sync, jump.preSpeed, jump.maxSpeed, airtime))
	{
		return;
	}

	// Store the row now; the path is deterministic from the guid.
	char replayPath[160];
	FormatEx(replayPath, sizeof(replayPath), "_jumpstats/%s.replay", guid);

	char query[1024];
	FormatEx(query, sizeof(query), sql_jumpstatreplays_insert,
		steamid,
		jump.type,
		mode,
		RoundToNearest(jump.distance * GOKZ_DB_JS_DISTANCE_PRECISION),
		jump.block > 0,
		jump.block,
		jump.strafes,
		RoundToNearest(jump.sync * GOKZ_DB_JS_SYNC_PRECISION),
		RoundToNearest(jump.preSpeed * GOKZ_DB_JS_PRE_PRECISION),
		RoundToNearest(jump.maxSpeed * GOKZ_DB_JS_MAX_PRECISION),
		airtime,
		replayPath);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_Low);
}

void JSReplays_OnMapEnd()
{
	if (gCV_JSReplays_Enable == null || !gCV_JSReplays_Enable.BoolValue || gH_DB == null)
	{
		return;
	}

	int batch = gCV_JSReplays_CleanupBatch.IntValue;
	if (batch <= 0)
	{
		return;
	}

	char query[1024];
	FormatEx(query, sizeof(query), sql_jumpstatreplays_cleanup_select, gCV_JSReplays_Max.IntValue, batch);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, DB_TxnSuccess_JSReplaysCleanup, DB_TxnFailure_Generic, _, DBPrio_Low);
}

public void DB_TxnSuccess_JSReplaysCleanup(Handle db, any data, int numQueries, Handle[] results, any[] queryData)
{
	Handle rs = results[0];
	if (SQL_GetRowCount(rs) == 0)
	{
		return;
	}

	char ids[8192];
	char idbuf[16];
	char relpath[160];
	char fullpath[PLATFORM_MAX_PATH];
	int count = 0;

	while (SQL_FetchRow(rs))
	{
		int replayID = SQL_FetchInt(rs, 0);
		SQL_FetchString(rs, 1, relpath, sizeof(relpath));

		// Delete the replay file. RP_DIRECTORY is the gokz-replays data dir;
		// ReplayPath is stored relative to it (e.g. "_jumpstats/<guid>.replay").
		BuildPath(Path_SM, fullpath, sizeof(fullpath), "%s/%s", RP_DIRECTORY, relpath);
		if (FileExists(fullpath))
		{
			DeleteFile(fullpath);
		}

		if (count > 0)
		{
			StrCat(ids, sizeof(ids), ",");
		}
		IntToString(replayID, idbuf, sizeof(idbuf));
		StrCat(ids, sizeof(ids), idbuf);
		count++;
	}

	if (count == 0)
	{
		return;
	}

	char query[8192 + 64];
	FormatEx(query, sizeof(query), sql_jumpstatreplays_delete_ids, ids);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_Low);
}
