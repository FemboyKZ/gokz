/*
	Track player's jump inputs and whether they hit perfect
	bunnyhops for a number of their recent bunnyhops.
*/



// =====[ PUBLIC ]=====

void PrintBhopCheckToChat(int client, int target)
{
	GOKZ_PrintToChat(client, true, 
		"{lime}%N {grey}[{lime}%d%%%% {grey}%t | {lime}%.2f {grey}%t]", 
		target, 
		RoundFloat(GOKZ_AC_GetPerfRatio(target, 20) * 100.0), 
		"Perfs", 
		GOKZ_AC_GetAverageJumpInputs(target, 20), 
		"Average");
	GOKZ_PrintToChat(client, false, 
		" {grey}%t - %s", 
		"Pattern", 
		GenerateScrollPattern(target, 20));
}

void PrintBhopCheckToConsole(int client, int target)
{
	PrintToConsole(client, 
		"%N [%d%% %t | %.2f %t]\n %t - %s", 
		target, 
		RoundFloat(GOKZ_AC_GetPerfRatio(target, 20) * 100.0), 
		"Perfs", 
		GOKZ_AC_GetAverageJumpInputs(target, 20), 
		"Average", 
		"Pattern", 
		GenerateScrollPattern(target, 20, false));
}

// Generate 'scroll pattern'
char[] GenerateScrollPattern(int client, int sampleSize = AC_MAX_BHOP_SAMPLES, bool colours = true)
{
	char report[512];
	int maxIndex = IntMin(gI_BhopCount[client], sampleSize);
	bool[] perfs = new bool[maxIndex];
	GOKZ_AC_GetHitPerf(client, perfs, maxIndex);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputs(client, jumpInputs, maxIndex);
	
	for (int i = 0; i < maxIndex; i++)
	{
		if (colours)
		{
			Format(report, sizeof(report), "%s%s%d ", 
				report, 
				perfs[i] ? "{green}" : "{default}", 
				jumpInputs[i]);
		}
		else
		{
			Format(report, sizeof(report), "%s%d%s ", 
				report, 
				jumpInputs[i], 
				perfs[i] ? "*" : "");
		}
	}
	
	TrimString(report);
	
	return report;
}

// Generate 'scroll pattern' report showing pre and post inputs instead
char[] GenerateScrollPatternEx(int client, int sampleSize = AC_MAX_BHOP_SAMPLES)
{
	char report[512];
	int maxIndex = IntMin(gI_BhopCount[client], sampleSize);
	bool[] perfs = new bool[maxIndex];
	GOKZ_AC_GetHitPerf(client, perfs, maxIndex);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputs(client, jumpInputs, maxIndex);
	int[] preJumpInputs = new int[maxIndex];
	GOKZ_AC_GetPreJumpInputs(client, preJumpInputs, maxIndex);
	int[] postJumpInputs = new int[maxIndex];
	GOKZ_AC_GetPostJumpInputs(client, postJumpInputs, maxIndex);
	
	for (int i = 0; i < maxIndex; i++)
	{
		Format(report, sizeof(report), "%s(%d%s%d)", 
			report, 
			preJumpInputs[i], 
			perfs[i] ? "*" : " ", 
			postJumpInputs[i]);
	}
	
	TrimString(report);
	
	return report;
}



// =====[ EVENTS ]=====

void OnClientPutInServer_BhopTracking(int client)
{
	ResetBhopStats(client);
}

void OnJumpValidated_RecordJumpbug(int client, int cmdnum)
{
	if (gCV_sv_autobunnyhopping.BoolValue)
	{
		return;
	}
	
	// If a bhop was already recorded on this tick, update it to be a jumpbug
	// This is fine because a jumpbug IS a bhop, just a special type
	bool alreadyRecorded = (gI_BhopLastRecordedBhopCmdnum[client] == cmdnum);
	
	if (alreadyRecorded)
	{
		// A bhop was already recorded this tick - just update the perf status
		// Use the stored pending index to avoid recalculation
		// The pre/post jump inputs are already correct from the bhop recording
		int pendingIdx = gI_BhopPendingIndex[client];
		if (pendingIdx >= 0 && pendingIdx < AC_MAX_BHOP_SAMPLES)
		{
			gB_BhopHitPerf[client][pendingIdx] = Movement_GetHitPerf(client);
		}
		// gB_BhopPostJumpInputsPending is already true from the bhop recording,
		// so the index will be advanced when post-inputs are collected
	}
	else
	{
		// New jumpbug (not preceded by a bhop recording), record it normally
		int nextIndex = NextIndex(gI_BhopIndex[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndex[client] = nextIndex;
			RecordJump(client, nextIndex, cmdnum);
			// RecordJump sets gB_BhopPostJumpInputsPending[client] = true,
			// so the index will be advanced when post-inputs are collected
		}
	}
	
	// Clear bind exception since we successfully recorded the jumpbug
	gB_BindExceptionPending[client] = false;
}

void OnPlayerRunCmdPost_BhopTracking(int client, int buttons, int cmdnum)
{
	if (gCV_sv_autobunnyhopping.BoolValue)
	{
		return;
	}
	
	// Record buttons BEFORE checking for bhop
	RecordButtons(client, buttons);
	
	// If bhop was last tick, then record the pre bhop inputs.
	// Require sufficient time since the last RECORDED bhop to avoid pre and post bhop input overlap.
	// Must wait at least AC_MAX_BUTTON_SAMPLES * 2 ticks to prevent overlap:
	// - Previous jump's post-inputs: cmdnum to cmdnum + AC_MAX_BUTTON_SAMPLES
	// - Current jump's pre-inputs: cmdnum - AC_MAX_BUTTON_SAMPLES to cmdnum
	// - These ranges don't overlap when jumps are AC_MAX_BUTTON_SAMPLES * 2 ticks apart
	bool hitBhop = HitBhop(client, cmdnum);
	
	// Check if enough time has passed since last recorded jump to avoid input overlap
	bool enoughTimePassed = (gI_BhopLastRecordedBhopCmdnum[client] == 0 || 
		cmdnum >= gI_BhopLastRecordedBhopCmdnum[client] + (AC_MAX_BUTTON_SAMPLES * 2));
	
	// Track if we recorded a jump this tick (for bind exception prevention)
	bool recordedJump = false;
	
	// Bhops require valid landing and enough time passed
	if (hitBhop && enoughTimePassed && gB_LastLandingWasValid[client])
	{
		int nextIndex = NextIndex(gI_BhopIndex[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndex[client] = nextIndex;
			RecordJump(client, nextIndex, cmdnum);
			recordedJump = true;
		}
	}
	// Note: Jumpbugs are also recorded via the GOKZ_OnJumpValidated forward
	// If a jumpbug occurs on the same tick as a bhop, the forward will overwrite the bhop data
	
	// Bind exception - only trigger if we haven't already recorded a jump this tick
	// Also skip if this is a jumpbug tick (jumpbugs are handled by the forward)
	// Also skip if we're still waiting for post-inputs from a previous jump (to prevent double-recording)
	if (gB_BindExceptionPending[client] && cmdnum > Movement_GetLandingCmdNum(client) + AC_MAX_BHOP_GROUND_TICKS
		&& !recordedJump && !gB_JumpbugThisTick[client] && !gB_BhopPostJumpInputsPending[client])
	{
		int nextIndex = NextIndex(gI_BhopIndex[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing and using
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndex[client] = nextIndex;
			gB_BhopHitPerf[client][nextIndex] = false;
			gI_BhopPreJumpInputs[client][nextIndex] = -1; // Special value for binded jumps
			gI_BhopLastRecordedBhopCmdnum[client] = cmdnum;
			gB_BhopPostJumpInputsPending[client] = true;
			gB_BindExceptionPending[client] = false;
			gB_BindExceptionPostPending[client] = true;
		}
	}
	
	// Record post bhop inputs once enough ticks have passed
	if (gB_BhopPostJumpInputsPending[client] && cmdnum == gI_BhopLastRecordedBhopCmdnum[client] + AC_MAX_BUTTON_SAMPLES)
	{
		// Use the stored pending index to finalize the recording
		int pendingIdx = gI_BhopPendingIndex[client];
		if (pendingIdx >= 0 && pendingIdx < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPostJumpInputs[client][pendingIdx] = CountJumpInputs(client);
			gI_BhopIndex[client] = pendingIdx;
			gI_BhopCount[client]++;
			CheckForBhopMacro(client);
		}
		gB_BhopPostJumpInputsPending[client] = false;
		gB_BindExceptionPostPending[client] = false;
	}
	
	// Record last jump takeoff time
	if (JustJumped(client, cmdnum))
	{
		gI_BhopLastTakeoffCmdnum[client] = cmdnum;
		gB_BindExceptionPending[client] = false;
		if (gB_BindExceptionPostPending[client])
		{
			gB_BhopPostJumpInputsPending[client] = false;
			gB_BindExceptionPostPending[client] = false;
		}
	}
	
	if (JustLanded(client, cmdnum))
	{
		// These conditions exist to reduce false positives.
		
		// Telehopping is when the player bunnyhops out of a teleport that has a
		// destination very close to the ground. This will, more than usual,
		// result in a perfect bunnyhop. This is alleviated by checking if the
		// player's origin was affected by a teleport last tick.
		
		// When a player is pressing up against a slope but not ascending it (e.g.
		// palm trees on kz_adv_cursedjourney), they will switch between on ground
		// and off ground frequently, which means that if they manage to jump, the
		// jump will be recorded as a perfect bunnyhop. To ignore this, we check
		// the jump is more than 1 tick duration.
		
		gB_LastLandingWasValid[client] = cmdnum - gI_LastOriginTeleportCmdNum[client] > 1
		 && cmdnum - Movement_GetTakeoffCmdNum(client) > 1;
		
		// You can still crouch-bind VNL jumps and some people just don't know that
		// it doesn't work with the other modes in GOKZ. This can cause false positives
		// if the player uses the bind for bhops and mostly presses it too early or
		// exactly on time rather than too late. This is supposed to reduce those by
		// detecting jumps where you don't get a bhop and have exactly one jump input
		// before landing and none after landing. We require the one input to be right
		// before the jump to make it a lot harder to fake a binded jump when doing
		// a regular longjump.
		// Only check for bind exception if we have enough button samples AND this wasn't a jumpbug
		// (jumpbugs naturally have 1 input before the jump, so they shouldn't trigger bind exception)
		bool wasJumpbug = Movement_GetJumpbugged(client);
		gB_BindExceptionPending[client] = !wasJumpbug && gI_ButtonCount[client] >= AC_MAX_BUTTON_SAMPLES 
			&& (CountJumpInputs(client, AC_BINDEXCEPTION_SAMPLES) == 1 && CountJumpInputs(client, AC_MAX_BUTTON_SAMPLES) == 1);
		gB_BindExceptionPostPending[client] = false;
	}
}



// =====[ PRIVATE ]=====

static void RecordJump(int client, int nextIndex, int cmdnum)
{
	gB_BhopHitPerf[client][nextIndex] = Movement_GetHitPerf(client);
	int preInputs = CountJumpInputs(client);
	
	// If we have no jump inputs but there's a bind exception pending, 
	// this might be a false positive - clear the exception and use 0 instead of -1
	if (preInputs == 0 && gB_BindExceptionPending[client])
	{
		gB_BindExceptionPending[client] = false;
	}
	
	gI_BhopPreJumpInputs[client][nextIndex] = preInputs;
	gI_BhopLastRecordedBhopCmdnum[client] = cmdnum;
	gB_BhopPostJumpInputsPending[client] = true;
	gB_BindExceptionPending[client] = false;
	gB_BindExceptionPostPending[client] = false;
}

static void CheckForBhopMacro(int client)
{
	if (GOKZ_AC_GetPerfCount(client, 19) == 19)
	{
		SuspectPlayer(client, ACReason_BhopHack, "High perf ratio", GenerateBhopBanStats(client, 19));
	}
	else if (GOKZ_AC_GetPerfCount(client, 30) >= 28)
	{
		SuspectPlayer(client, ACReason_BhopHack, "High perf ratio", GenerateBhopBanStats(client, 30));
	}
	else if (GOKZ_AC_GetPerfCount(client, 20) >= 16 && GOKZ_AC_GetAverageJumpInputs(client, 20) <= 2.0 + EPSILON)
	{
		SuspectPlayer(client, ACReason_BhopHack, "1's or 2's scroll pattern", GenerateBhopBanStats(client, 20));
	}
	else if (gI_BhopCount[client] >= 20 && GOKZ_AC_GetPerfCount(client, 20) >= 8
		 && GOKZ_AC_GetAverageJumpInputs(client, 20) >= 19.0 - EPSILON)
	{
		SuspectPlayer(client, ACReason_BhopMacro, "High scroll pattern", GenerateBhopBanStats(client, 20));
	}
	else if (GOKZ_AC_GetPerfCount(client, 30) >= 10 && CheckForRepeatingJumpInputsCount(client, 25, 30) >= 14)
	{
		SuspectPlayer(client, ACReason_BhopMacro, "Repeating scroll pattern", GenerateBhopBanStats(client, 30));
	}
}

static char[] GenerateBhopBanStats(int client, int sampleSize)
{
	char stats[512];
	FormatEx(stats, sizeof(stats), 
		"Perfs: %d/%d, Average: %.2f, Scroll pattern: %s", 
		GOKZ_AC_GetPerfCount(client, sampleSize), 
		IntMin(gI_BhopCount[client], sampleSize), 
		GOKZ_AC_GetAverageJumpInputs(client, sampleSize), 
		GenerateScrollPatternEx(client, sampleSize));
	return stats;
}

/**
 * Returns -1, or the repeating input count if there if there is 
 * an input count that repeats for more than the provided ratio.
 *
 * @param client		Client index.
 * @param threshold		Minimum frequency to be considered 'repeating'.
 * @param sampleSize	Maximum recent bhop samples to include in calculation.
 * @return				The repeating input, or else -1.
 */
static int CheckForRepeatingJumpInputsCount(int client, int threshold, int sampleSize = AC_MAX_BHOP_SAMPLES)
{
	int maxIndex = IntMin(gI_BhopCount[client], sampleSize);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputs(client, jumpInputs, maxIndex);
	int maxJumpInputs = AC_MAX_BUTTON_SAMPLES + 1;
	int[] jumpInputsFrequency = new int[maxJumpInputs];
	
	// Count up all the in jump patterns
	for (int i = 0; i < maxIndex; i++)
	{
		// -1 is a binded jump, those are excluded
		if (jumpInputs[i] != -1)
		{
			jumpInputsFrequency[jumpInputs[i]]++;
		}
	}
	
	// Returns i if the given number of the sample size has the same jump input count
	for (int i = 1; i < maxJumpInputs; i++)
	{
		if (jumpInputsFrequency[i] >= threshold)
		{
			return i;
		}
	}
	
	return -1; // -1 if no repeating jump input found
}

// Reset the tracked bhop stats of the client
static void ResetBhopStats(int client)
{
	gI_ButtonCount[client] = 0;
	gI_ButtonsIndex[client] = 0;
	gI_BhopCount[client] = 0;
	gI_BhopIndex[client] = 0;
	gI_BhopPendingIndex[client] = 0;
	gI_BhopLastTakeoffCmdnum[client] = 0;
	gI_BhopLastRecordedBhopCmdnum[client] = 0;
	gB_BhopPostJumpInputsPending[client] = false;
	gB_LastLandingWasValid[client] = false;
	gB_BindExceptionPending[client] = false;
	gB_BindExceptionPostPending[client] = false;
}

// Returns true if ther was a jump last tick and was within a number of ticks after landing
static bool HitBhop(int client, int cmdnum)
{
	return JustJumped(client, cmdnum) && Movement_GetTakeoffCmdNum(client) - Movement_GetLandingCmdNum(client) <= AC_MAX_BHOP_GROUND_TICKS;
}

static bool JustJumped(int client, int cmdnum)
{
	return Movement_GetJumped(client) && Movement_GetTakeoffCmdNum(client) == cmdnum;
}

static bool JustLanded(int client, int cmdnum)
{
	return Movement_GetLandingCmdNum(client) == cmdnum;
}

// Records current button inputs
static void RecordButtons(int client, int buttons)
{
	gI_ButtonsIndex[client] = NextIndex(gI_ButtonsIndex[client], AC_MAX_BUTTON_SAMPLES);
	gI_Buttons[client][gI_ButtonsIndex[client]] = buttons;
	gI_ButtonCount[client]++;
}

// Counts the number of times buttons went from !IN_JUMP to IN_JUMP
static int CountJumpInputs(int client, int sampleSize = AC_MAX_BUTTON_SAMPLES)
{
	int[] recentButtons = new int[sampleSize];
	SortByRecent(gI_Buttons[client], AC_MAX_BUTTON_SAMPLES, recentButtons, sampleSize, gI_ButtonsIndex[client]);
	int maxIndex = IntMin(gI_ButtonCount[client], sampleSize);
	int jumps = 0;
	
	for (int i = 0; i < maxIndex - 1; i++)
	{
		// If buttons went from !IN_JUMP to IN_JUMP
		if (!(recentButtons[i + 1] & IN_JUMP) && recentButtons[i] & IN_JUMP)
		{
			jumps++;
		}
	}
	return jumps;
} 