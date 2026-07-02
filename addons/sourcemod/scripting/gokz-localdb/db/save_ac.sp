/*
	Folds the anti-cheat strafe features of every measured jump into the player's running aggregates (AnticheatStats table).
*/



public void OnLanding_SaveAcStats(Jump jump)
{
	if (!gB_ClientSetUp[jump.jumper])
	{
		return;
	}

	// Skip invalid
	if (jump.type == JumpType_Invalid || jump.type == JumpType_FullInvalid
		 || jump.type == JumpType_Fall || jump.type == JumpType_Other)
	{
		return;
	}

	// Too short to say anything
	if (jump.acUsableTicks < 16)
	{
		return;
	}

	// The always-stats path fires for ANY jump, including standstill hops and plain W-jumps.
	// No strafing means no signal, only baseline noise.
	if (jump.strafes < 2 || jump.acTurnTicks < 8)
	{
		return;
	}

	int steamid = GetSteamAccountID(jump.jumper);
	if (steamid == 0)
	{
		return;
	}

	int mode = GOKZ_GetCoreOption(jump.jumper, Option_Mode);

	// Metrics that need enough samples contribute only when valid
	bool hasK = jump.acKFit >= 0.0;
	float kRes = hasK ? jump.acKResidualRms : 0.0;
	bool hasLenStd = jump.strafes >= 3;
	float lenStd = hasLenStd ? jump.acStrafeLenStd : 0.0;
	bool hasPeak = jump.acTurnTicks > 0;
	bool hasSharp = jump.acFlipAccelSamples > 0;
	float sharp = hasSharp ? jump.acFlipSharpness : 0.0;

	// Pooled flip-lag sums, rebuilt from the per-jump mean/std over the matched flips.
	// Constant nonzero lag (macro with a fixed offset) shows as near-zero pooled variance even when the zero-lag count looks human.
	float lagSum = jump.acFlipLagMean * float(jump.acFlipMatched);
	float lagSqSum = (jump.acFlipLagStd * jump.acFlipLagStd
		 + jump.acFlipLagMean * jump.acFlipLagMean) * float(jump.acFlipMatched);

	char query[2048];
	FormatEx(query, sizeof(query),
		g_DBType == DatabaseType_SQLite ? sqlite_acstats_upsert : mysql_acstats_upsert,
		steamid, mode, jump.type,
		jump.acUsableTicks, jump.acTurnTicks, jump.acTurnBindTicks,
		jump.acCeilingTicks, jump.acMouseTicks, jump.acInjectedTicks,
		jump.acFlipMatched, jump.acFlipZeroLag,
		hasK ? 1 : 0, hasLenStd ? 1 : 0, hasPeak ? 1 : 0,
		jump.acFlipImpulses, jump.acFlipAccelSamples, hasSharp ? 1 : 0,
		jump.acEffMean, jump.acEffMean * jump.acEffMean,
		jump.acYawResidualRms, jump.acYawResidualRms * jump.acYawResidualRms,
		kRes, kRes * kRes,
		lenStd, lenStd * lenStd,
		lagSum, lagSqSum,
		hasPeak ? jump.acPeakDeltaYaw : 0.0,
		hasPeak ? jump.acPeakDeltaYaw * jump.acPeakDeltaYaw : 0.0,
		sharp, sharp * sharp);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_Low);
}
