/*
	Folds the anti-cheat strafe features of every measured jump into the player's running aggregates (AnticheatStats table).
*/

// Speed gain (max - pre) that keeps a low-turning jump anyway
#define AC_MIN_KEEP_GAIN 10.0

// Matches MIN_STAT_SAMPLES in the web extractor
#define AC_MIN_STAT_SAMPLES 3

// Aborted flights are partial, so stricter gates. Seconds, not ticks, for tickrate independence.
#define AC_ABORT_MIN_AIRTIME 0.375
#define AC_ABORT_MIN_STRAFES 3



public void OnLanding_SaveAcStats(Jump jump)
{
	SaveAcJump(jump, jump.type);
}

// Teleport already invalidated jump.type, originalType carries the real one
public void OnJumpAborted_SaveAcStats(Jump jump)
{
	if (float(jump.acUsableTicks) * GetTickInterval() < AC_ABORT_MIN_AIRTIME)
	{
		return;
	}
	if (jump.strafes < AC_ABORT_MIN_STRAFES
		 && jump.maxSpeed - jump.preSpeed < AC_MIN_KEEP_GAIN)
	{
		return;
	}

	SaveAcJump(jump, jump.originalType);
}

static void SaveAcJump(Jump jump, int jumpType)
{
	if (!gB_ClientSetUp[jump.jumper])
	{
		return;
	}

	// Skip invalid
	if (jumpType == JumpType_Invalid || jumpType == JumpType_FullInvalid
		 || jumpType == JumpType_Fall || jumpType == JumpType_Other)
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
	// Real speed gain keeps it anyway: keyboard-only strafing gains without turning.
	if ((jump.strafes < 2 || jump.acTurnTicks < 8)
		 && jump.maxSpeed - jump.preSpeed < AC_MIN_KEEP_GAIN)
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
	bool hasYawRes = jump.acYawResidualRms >= 0.0;
	float yawRes = hasYawRes ? jump.acYawResidualRms : 0.0;
	bool hasK = jump.acKFit >= 0.0;
	float kRes = hasK ? jump.acKResidualRms : 0.0;
	float kFitVal = hasK ? jump.acKFit : 0.0;
	bool hasKPitch = jump.acPitchSamples >= 8;
	float kPitchVal = hasKPitch ? jump.acKPitchFit : 0.0;
	// Needs 3+ interior strafes, fewer reads as sigma ~0 (the macro signature)
	bool hasLenStd = jump.strafes >= 5;
	float lenStd = hasLenStd ? jump.acStrafeLenStd : 0.0;
	// TurnTicks is the ceiling-fraction denominator, so it drops out with peak
	bool hasPeak = jump.acPeakDeltaYaw >= 0.0;
	int ceilTurnTicks = hasPeak ? jump.acTurnTicks : 0;
	bool hasSharp = jump.acFlipAccelSamples >= AC_MIN_STAT_SAMPLES;
	float sharp = hasSharp ? jump.acFlipSharpness : 0.0;

	// Pooled flip-lag sums, rebuilt from the per-jump mean/std over the matched flips.
	// Constant nonzero lag (macro with a fixed offset) shows as near-zero pooled variance even when the zero-lag count looks human.
	float lagSum = jump.acFlipLagMean * float(jump.acFlipMatched);
	float lagSqSum = (jump.acFlipLagStd * jump.acFlipLagStd
		 + jump.acFlipLagMean * jump.acFlipLagMean) * float(jump.acFlipMatched);

	// Upsert template alone is ~3.5k chars
	char query[8192];
	FormatEx(query, sizeof(query),
		g_DBType == DatabaseType_SQLite ? sqlite_acstats_upsert : mysql_acstats_upsert,
		steamid, mode, jumpType,
		jump.acUsableTicks, ceilTurnTicks, jump.acTurnBindTicks,
		jump.acCeilingTicks, jump.acSpinTicks, jump.acMouseTicks,
		jump.acYawlessMouseTicks, jump.acMouseYDeadTicks,
		jump.acPitchFrozenTicks, jump.acCmdGapTicks,
		jump.acSidemoveGhostTicks, jump.acSidemoveNullTicks,
		jump.acSidemoveMismatchTicks, jump.acRollTicks, jump.acInjectedTicks,
		jump.acFlipMatched, jump.acFlipZeroLag,
		hasYawRes ? 1 : 0,
		hasK ? 1 : 0, hasKPitch ? 1 : 0, hasLenStd ? 1 : 0, hasPeak ? 1 : 0,
		jump.acFlipImpulses, jump.acFlipAccelSamples, hasSharp ? 1 : 0,
		jump.acEffMean, jump.acEffMean * jump.acEffMean,
		yawRes, yawRes * yawRes,
		kRes, kRes * kRes,
		kFitVal, kFitVal * kFitVal,
		kPitchVal, kPitchVal * kPitchVal,
		lenStd, lenStd * lenStd,
		lagSum, lagSqSum,
		hasPeak ? jump.acPeakDeltaYaw : 0.0,
		hasPeak ? jump.acPeakDeltaYaw * jump.acPeakDeltaYaw : 0.0,
		sharp, sharp * sharp);

	Transaction txn = SQL_CreateTransaction();
	txn.AddQuery(query);
	SQL_ExecuteTransaction(gH_DB, txn, _, DB_TxnFailure_Generic, _, DBPrio_Low);
}
