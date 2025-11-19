/*
	Track player's jump inputs (V2 - Jumpbug-aware method)
	This version includes jumpbug detection and uses local/SBPP bans only.
	Does NOT send to Global API - use for experimental detection.
*/

// =====[ PUBLIC ]=====

void PrintBhopCheckToChat_V2(int client, int target)
{
	GOKZ_PrintToChat(client, true, 
		"{orchid}[FKZ AC] {lime}%N {grey}[{lime}%d%%%% {grey}%t | {lime}%.2f {grey}%t]", 
		target, 
		RoundFloat(GOKZ_AC_GetPerfCountV2(target, 20) * 100.0 / IntMin(gI_BhopCountV2[target], 20)), 
		"Perfs", 
		GOKZ_AC_GetAverageJumpInputsV2(target, 20), 
		"Average");
	GOKZ_PrintToChat(client, false, 
		" {grey}%t - %s", 
		"Pattern", 
		GenerateScrollPatternV2(target, 20));
}

void PrintBhopCheckToConsole_V2(int client, int target)
{
	PrintToConsole(client, 
		"[FKZ AC] %N [%d%% %t | %.2f %t]\n %t - %s", 
		target, 
		RoundFloat(GOKZ_AC_GetPerfCountV2(target, 20) * 100.0 / IntMin(gI_BhopCountV2[target], 20)), 
		"Perfs", 
		GOKZ_AC_GetAverageJumpInputsV2(target, 20), 
		"Average", 
		"Pattern", 
		GenerateScrollPatternV2(target, 20, false));
}

// Generate 'scroll pattern' for V2
char[] GenerateScrollPatternV2(int client, int sampleSize = AC_MAX_BHOP_SAMPLES, bool colours = true)
{
	char report[512];
	int maxIndex = IntMin(gI_BhopCountV2[client], sampleSize);
	bool[] perfs = new bool[maxIndex];
	GOKZ_AC_GetHitPerfV2(client, perfs, maxIndex);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputsV2(client, jumpInputs, maxIndex);
	
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
char[] GenerateScrollPatternExV2(int client, int sampleSize = AC_MAX_BHOP_SAMPLES)
{
	char report[512];
	int maxIndex = IntMin(gI_BhopCountV2[client], sampleSize);
	bool[] perfs = new bool[maxIndex];
	GOKZ_AC_GetHitPerfV2(client, perfs, maxIndex);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputsV2(client, jumpInputs, maxIndex);
	int[] preJumpInputs = new int[maxIndex];
	GOKZ_AC_GetPreJumpInputsV2(client, preJumpInputs, maxIndex);
	int[] postJumpInputs = new int[maxIndex];
	GOKZ_AC_GetPostJumpInputsV2(client, postJumpInputs, maxIndex);
	
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

void OnClientPutInServer_BhopTrackingV2(int client)
{
	ResetBhopStatsV2(client);
}

void OnJumpValidated_RecordJumpbugV2(int client, int cmdnum)
{
	if (gCV_sv_autobunnyhopping.BoolValue)
	{
		return;
	}
    
	// If a bhop was already recorded on this tick, update it to be a jumpbug
	// This is fine because a jumpbug IS a bhop, just a special type
	bool alreadyRecorded = (gI_BhopLastRecordedBhopCmdnumV2[client] == cmdnum);
	
	if (alreadyRecorded)
	{
		// A bhop was already recorded this tick - just update the perf status
		// Use the stored pending index to avoid recalculation
		// The pre/post jump inputs are already correct from the bhop recording
		int pendingIdx = gI_BhopPendingIndexV2[client];
		if (pendingIdx >= 0 && pendingIdx < AC_MAX_BHOP_SAMPLES)
		{
			gB_BhopHitPerfV2[client][pendingIdx] = Movement_GetHitPerf(client);
		}
		// gB_BhopPostJumpInputsPendingV2 is already true from the bhop recording,
		// so the index will be advanced when post-inputs are collected
	}
	else
	{
		// New jumpbug (not preceded by a bhop recording), record it normally
		int nextIndex = NextIndex(gI_BhopIndexV2[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndexV2[client] = nextIndex;
			RecordJumpV2(client, nextIndex, cmdnum);
			// RecordJumpV2 sets gB_BhopPostJumpInputsPendingV2[client] = true,
			// so the index will be advanced when post-inputs are collected
		}
	}
	
	// Clear bind exception since we successfully recorded the jumpbug
	gB_BindExceptionPendingV2[client] = false;
}

void OnPlayerRunCmdPost_BhopTrackingV2(int client, int buttons, int cmdnum)
{
	if (gCV_sv_autobunnyhopping.BoolValue)
	{
		return;
	}

	// Record buttons BEFORE checking for bhop
	RecordButtonsV2(client, buttons);

	// If bhop was last tick, then record the pre bhop inputs.
	bool hitBhop = HitBhopV2(client, cmdnum);
	
	// Cooldown check: require minimum ticks between bhops to prevent spam from head bonks
	// Allow 8 ticks minimum between jumps (should accommodate both 64 and 128 tick)
	int ticksSinceLastJump = cmdnum - gI_BhopLastRecordedBhopCmdnumV2[client];
	bool onCooldown = (gI_BhopLastRecordedBhopCmdnumV2[client] > 0 && ticksSinceLastJump < 8);
	
	// Track if we recorded a jump this tick (for bind exception prevention)
	bool recordedJump = false;
	
	// Bhops require valid landing
	if (hitBhop && gB_LastLandingWasValid[client] && !onCooldown)
	{
		// If there's a pending bhop, finalize it first
		if (gB_BhopPostJumpInputsPendingV2[client])
		{
			int pendingIdx = gI_BhopPendingIndexV2[client];
			if (pendingIdx >= 0 && pendingIdx < AC_MAX_BHOP_SAMPLES)
			{
				// Finalize with whatever inputs we have
				gI_BhopPostJumpInputsV2[client][pendingIdx] = CountJumpInputsV2(client);
				gI_BhopIndexV2[client] = pendingIdx;
				gI_BhopCountV2[client]++;
				CheckForBhopMacroV2(client);
			}
			gB_BhopPostJumpInputsPendingV2[client] = false;
		}
		// Now record the new bhop
		int nextIndex = NextIndex(gI_BhopIndexV2[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndexV2[client] = nextIndex;
			RecordJumpV2(client, nextIndex, cmdnum);
			recordedJump = true;
		}
	}
	// Note: Jumpbugs are also recorded via the GOKZ_OnJumpValidated forward
	// If a jumpbug occurs on the same tick as a bhop, the forward will update the bhop data
	
	// Bind exception - only trigger if we haven't already recorded a jump this tick
	// Also skip if this is a jumpbug tick (jumpbugs are handled by the forward)
	// Also skip if we're still waiting for post-inputs from a previous jump (to prevent double-recording)
	if (gB_BindExceptionPendingV2[client] && cmdnum > Movement_GetLandingCmdNum(client) + AC_MAX_BHOP_GROUND_TICKS
		&& !recordedJump && !gB_JumpbugThisTick[client] && !gB_BhopPostJumpInputsPendingV2[client])
	{
		int nextIndex = NextIndex(gI_BhopIndexV2[client], AC_MAX_BHOP_SAMPLES);
		// Validate index is within bounds before storing and using
		if (nextIndex >= 0 && nextIndex < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPendingIndexV2[client] = nextIndex;
			gB_BhopHitPerfV2[client][nextIndex] = false;
			gI_BhopPreJumpInputsV2[client][nextIndex] = -1; // Special value for binded jumps
			gI_BhopLastRecordedBhopCmdnumV2[client] = cmdnum;
			gB_BhopPostJumpInputsPendingV2[client] = true;
			gB_BindExceptionPendingV2[client] = false;
			gB_BindExceptionPostPendingV2[client] = true;
		}
	}
	
	// Record post bhop inputs once enough ticks have passed
	if (gB_BhopPostJumpInputsPendingV2[client] && cmdnum == gI_BhopLastRecordedBhopCmdnumV2[client] + AC_MAX_BUTTON_SAMPLES)
	{
		// Use the stored pending index to finalize the recording
		int pendingIdx = gI_BhopPendingIndexV2[client];
		if (pendingIdx >= 0 && pendingIdx < AC_MAX_BHOP_SAMPLES)
		{
			gI_BhopPostJumpInputsV2[client][pendingIdx] = CountJumpInputsV2(client);
			gI_BhopIndexV2[client] = pendingIdx;
			gI_BhopCountV2[client]++;
			CheckForBhopMacroV2(client);
		}
		gB_BhopPostJumpInputsPendingV2[client] = false;
		gB_BindExceptionPostPendingV2[client] = false;
	}
	
	// Record last jump takeoff time
	if (JustJumpedV2(client, cmdnum))
	{
		gI_BhopLastTakeoffCmdnumV2[client] = cmdnum;
		gB_BindExceptionPendingV2[client] = false;
		// Note: Pending bhops are now auto-finalized when a new bhop is recorded
		// No need to discard here since the bhop recording section handles it
	}
	
	if (JustLandedV2(client, cmdnum))
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
		bool wasJumpbug = false;
		if (IsValidClient(client))
		{
    		wasJumpbug = Movement_GetJumpbugged(client);
		}
		gB_BindExceptionPendingV2[client] = !wasJumpbug && gI_ButtonCountV2[client] >= AC_MAX_BUTTON_SAMPLES 
			&& (CountJumpInputsV2(client, AC_BINDEXCEPTION_SAMPLES) == 1 && CountJumpInputsV2(client, AC_MAX_BUTTON_SAMPLES) == 1);
		gB_BindExceptionPostPendingV2[client] = false;
	}
}



// =====[ PRIVATE ]=====

static void RecordJumpV2(int client, int nextIndex, int cmdnum)
{
	gB_BhopHitPerfV2[client][nextIndex] = Movement_GetHitPerf(client);
	int preInputs = CountJumpInputsV2(client);
	
	// If we have no jump inputs but there's a bind exception pending, 
	// this might be a false positive - clear the exception and use 0 instead of -1
	if (preInputs == 0 && gB_BindExceptionPendingV2[client])
	{
		gB_BindExceptionPendingV2[client] = false;
	}
	
	gI_BhopPreJumpInputsV2[client][nextIndex] = preInputs;
	gI_BhopLastRecordedBhopCmdnumV2[client] = cmdnum;
	gB_BhopPostJumpInputsPendingV2[client] = true;
	gB_BindExceptionPendingV2[client] = false;
	gB_BindExceptionPostPendingV2[client] = false;
}

static void CheckForBhopMacroV2(int client)
{
	// Use V2 getters for detection
	if (GOKZ_AC_GetPerfCountV2(client, 19) == 19)
	{
		SuspectPlayerV2(client, ACReason_BhopHack, "High perf ratio", GenerateBhopBanStatsV2(client, 19));
	}
	else if (GOKZ_AC_GetPerfCountV2(client, 30) >= 28)
	{
		SuspectPlayerV2(client, ACReason_BhopHack, "High perf ratio", GenerateBhopBanStatsV2(client, 30));
	}
	else if (GOKZ_AC_GetPerfCountV2(client, 20) >= 16 && GOKZ_AC_GetAverageJumpInputsV2(client, 20) <= 2.0 + EPSILON)
	{
		SuspectPlayerV2(client, ACReason_BhopHack, "1's or 2's scroll pattern", GenerateBhopBanStatsV2(client, 20));
	}
	else if (gI_BhopCountV2[client] >= 20 && GOKZ_AC_GetPerfCountV2(client, 20) >= 8
		 && GOKZ_AC_GetAverageJumpInputsV2(client, 20) >= 19.0 - EPSILON)
	{
		SuspectPlayerV2(client, ACReason_BhopMacro, "High scroll pattern", GenerateBhopBanStatsV2(client, 20));
	}
	else if (GOKZ_AC_GetPerfCountV2(client, 30) >= 10 && CheckForRepeatingJumpInputsCountV2(client, 25, 30) >= 14)
	{
		SuspectPlayerV2(client, ACReason_BhopMacro, "Repeating scroll pattern", GenerateBhopBanStatsV2(client, 30));
	}
}

static char[] GenerateBhopBanStatsV2(int client, int sampleSize)
{
	char stats[512];
	FormatEx(stats, sizeof(stats), 
		"[FKZ AC] Perfs: %d/%d, Average: %.2f, Scroll pattern: %s", 
		GOKZ_AC_GetPerfCountV2(client, sampleSize), 
		IntMin(gI_BhopCountV2[client], sampleSize), 
		GOKZ_AC_GetAverageJumpInputsV2(client, sampleSize), 
		GenerateScrollPatternExV2(client, sampleSize));
	return stats;
}

static int CheckForRepeatingJumpInputsCountV2(int client, int threshold, int sampleSize = AC_MAX_BHOP_SAMPLES)
{
	int maxIndex = IntMin(gI_BhopCountV2[client], sampleSize);
	int[] jumpInputs = new int[maxIndex];
	GOKZ_AC_GetJumpInputsV2(client, jumpInputs, maxIndex);
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

// Returns true if ther was a jump last tick and was within a number of ticks after landing
static bool HitBhopV2(int client, int cmdnum)
{
	return JustJumpedV2(client, cmdnum) && Movement_GetTakeoffCmdNum(client) - Movement_GetLandingCmdNum(client) <= AC_MAX_BHOP_GROUND_TICKS;
}

static bool JustJumpedV2(int client, int cmdnum)
{
	return Movement_GetJumped(client) && Movement_GetTakeoffCmdNum(client) == cmdnum;
}

static bool JustLandedV2(int client, int cmdnum)
{
	return Movement_GetLandingCmdNum(client) == cmdnum;
}

// Records current button inputs
void RecordButtonsV2(int client, int buttons)
{
	gI_ButtonsIndexV2[client] = NextIndex(gI_ButtonsIndexV2[client], AC_MAX_BUTTON_SAMPLES);
	gI_ButtonsV2[client][gI_ButtonsIndexV2[client]] = buttons;
	gI_ButtonCountV2[client]++;
}

// Counts the number of times buttons went from !IN_JUMP to IN_JUMP
static int CountJumpInputsV2(int client, int sampleSize = AC_MAX_BUTTON_SAMPLES)
{
	int[] recentButtons = new int[sampleSize];
	SortByRecent(gI_ButtonsV2[client], AC_MAX_BUTTON_SAMPLES, recentButtons, sampleSize, gI_ButtonsIndexV2[client]);
	int maxIndex = IntMin(gI_ButtonCountV2[client], sampleSize);
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

// Reset the tracked bhop stats of the client (V2)
static void ResetBhopStatsV2(int client)
{
    gI_ButtonCountV2[client] = 0;
    gI_ButtonsIndexV2[client] = 0;
	gI_BhopCountV2[client] = 0;
	gI_BhopIndexV2[client] = 0;
	gI_BhopPendingIndexV2[client] = 0;
	gI_BhopLastTakeoffCmdnumV2[client] = 0;
	gI_BhopLastRecordedBhopCmdnumV2[client] = 0;
	gB_BhopPostJumpInputsPendingV2[client] = false;
	gB_BindExceptionPendingV2[client] = false;
	gB_BindExceptionPostPendingV2[client] = false;
}

// V2-specific suspect function that uses local/SBPP bans only
static void SuspectPlayerV2(int client, ACReason reason, const char[] reasonDetails, const char[] reasonStats)
{
	// Log to console/admin with [V2] prefix
	LogMessage("[FKZ AC] %N suspected: %s - %s", client, reasonDetails, reasonStats);
	
	// Notify admins
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && CheckCommandAccess(i, "sm_ban", ADMFLAG_BAN))
		{
			GOKZ_PrintToChat(i, true, "{grey}[{red}FKZ AC{grey}] {default}%N {grey}- %s", client, reasonDetails);
		}
	}
	
	// NOTE: V2 does NOT mark as cheater in local DB to keep it isolated from Global API
	// NOTE: V2 does NOT call GOKZ_AC_OnPlayerSuspected forward (no Global API ban)
	
	// Apply local/SBPP ban (NOT Global API)
	if (gCV_gokz_autoban.BoolValue)
	{
		char banReason[256];
		char kickMessage[256];
		int duration = (reason == ACReason_BhopHack) ? gCV_gokz_autoban_duration_bhop_hack.IntValue : gCV_gokz_autoban_duration_bhop_macro.IntValue;
		
		FormatEx(banReason, sizeof(banReason), "[FKZ] gokz-anticheat - %s", reasonDetails);
		FormatEx(kickMessage, sizeof(kickMessage), "You have been banned by FKZ AC detection.\nContact the server administrator for more info.\n%s", reasonStats);
		
		// Use standard ban methods (local/SBPP only, no Global API)
		if (gB_SourceBansPP)
		{
			SBPP_BanPlayer(0, client, duration, banReason);
		}
		else if (gB_SourceBans)
		{
			SBBanPlayer(0, client, duration, banReason);
		}
		else
		{
			BanClient(client, duration, BANFLAG_AUTO, banReason, kickMessage, "gokz-anticheat-v2", 0);
		}
	}
}
