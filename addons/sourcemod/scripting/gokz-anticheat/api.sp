static GlobalForward H_OnPlayerSuspected;



// =====[ FORWARDS ]=====

void CreateGlobalForwards()
{
	H_OnPlayerSuspected = new GlobalForward("GOKZ_AC_OnPlayerSuspected", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String);
}

void Call_OnPlayerSuspected(int client, ACReason reason, const char[] notes, const char[] stats)
{
	Call_StartForward(H_OnPlayerSuspected);
	Call_PushCell(client);
	Call_PushCell(reason);
	Call_PushString(notes);
	Call_PushString(stats);
	Call_Finish();
}



// =====[ NATIVES ]=====

void CreateNatives()
{
	CreateNative("GOKZ_AC_GetSampleSize", Native_GetSampleSize);
	CreateNative("GOKZ_AC_GetHitPerf", Native_GetHitPerf);
	CreateNative("GOKZ_AC_GetPerfCount", Native_GetPerfCount);
	CreateNative("GOKZ_AC_GetPerfRatio", Native_GetPerfRatio);
	CreateNative("GOKZ_AC_GetJumpInputs", Native_GetJumpInputs);
	CreateNative("GOKZ_AC_GetAverageJumpInputs", Native_GetAverageJumpInputs);
	CreateNative("GOKZ_AC_GetPreJumpInputs", Native_GetPreJumpInputs);
	CreateNative("GOKZ_AC_GetPostJumpInputs", Native_GetPostJumpInputs);
}

public int Native_GetSampleSize(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	return IntMin(gI_BhopCount[client], AC_MAX_BHOP_SAMPLES);
}

public int Native_GetHitPerf(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(3));

	if (sampleSize == 0)
	{
		return 0;
	}

	bool[] perfs = new bool[sampleSize];
	SortByRecentBool(gB_BhopHitPerf[client], AC_MAX_BHOP_SAMPLES, perfs, sampleSize, gI_BhopIndex[client]);
	SetNativeArray(2, perfs, sampleSize);
	return sampleSize;
}

public int Native_GetPerfCount(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(2));

	if (sampleSize == 0)
	{
		return 0;
	}

	bool[] perfs = new bool[sampleSize];
	GOKZ_AC_GetHitPerf(client, perfs, sampleSize);

	int perfCount = 0;
	for (int i = 0; i < sampleSize; i++)
	{
		if (perfs[i])
		{
			perfCount++;
		}
	}
	return perfCount;
}

public int Native_GetPerfRatio(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(2));

	if (sampleSize == 0)
	{
		return view_as<int>(0.0);
	}

	int perfCount = GOKZ_AC_GetPerfCount(client, sampleSize);
	return view_as<int>(float(perfCount) / float(sampleSize));
}

public int Native_GetJumpInputs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(3));

	if (sampleSize == 0)
	{
		return 0;
	}

	int[] preJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPreJumpInputs[client], AC_MAX_BHOP_SAMPLES, preJumpInputs, sampleSize, gI_BhopIndex[client]);
	int[] postJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPostJumpInputs[client], AC_MAX_BHOP_SAMPLES, postJumpInputs, sampleSize, gI_BhopIndex[client]);

	int[] jumpInputs = new int[sampleSize];
	for (int i = 0; i < sampleSize; i++)
	{
		jumpInputs[i] = preJumpInputs[i] + postJumpInputs[i];
	}

	SetNativeArray(2, jumpInputs, sampleSize);
	return sampleSize;
}

public int Native_GetAverageJumpInputs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(2));

	if (sampleSize == 0)
	{
		return view_as<int>(0.0);
	}

	int[] jumpInputs = new int[sampleSize];
	GOKZ_AC_GetJumpInputs(client, jumpInputs, sampleSize);

	int jumpInputCount = 0;
	for (int i = 0; i < sampleSize; i++)
	{
		jumpInputCount += jumpInputs[i];
	}
	return view_as<int>(float(jumpInputCount) / float(sampleSize));
}

public int Native_GetPreJumpInputs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(3));

	if (sampleSize == 0)
	{
		return 0;
	}

	int[] preJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPreJumpInputs[client], AC_MAX_BHOP_SAMPLES, preJumpInputs, sampleSize, gI_BhopIndex[client]);
	SetNativeArray(2, preJumpInputs, sampleSize);
	return sampleSize;
}

public int Native_GetPostJumpInputs(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int sampleSize = IntMin(GOKZ_AC_GetSampleSize(client), GetNativeCell(3));

	if (sampleSize == 0)
	{
		return 0;
	}

	int[] postJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPostJumpInputs[client], AC_MAX_BHOP_SAMPLES, postJumpInputs, sampleSize, gI_BhopIndex[client]);
	SetNativeArray(2, postJumpInputs, sampleSize);
	return sampleSize;
}



// =====[ HELPERS ]=====

static void SortByRecentBool(const bool[] input, int inputSize, bool[] buffer, int bufferSize, int index)
{
	if (index < 0 || index >= inputSize)
	{
		// If index is invalid, just return empty buffer
		return;
	}
	
	int reorderedIndex = 0;
	for (int i = index; reorderedIndex < bufferSize && i >= 0; i--)
	{
		buffer[reorderedIndex] = input[i];
		reorderedIndex++;
	}
	for (int i = inputSize - 1; reorderedIndex < bufferSize && i > index; i--)
	{
		buffer[reorderedIndex] = input[i];
		reorderedIndex++;
	}
}



// =====[ V2 API FUNCTIONS ]===== 
// Internal use only - not exposed as natives

int GOKZ_AC_GetSampleSizeV2(int client)
{
	return IntMin(gI_BhopCountV2[client], AC_MAX_BHOP_SAMPLES);
}

int GOKZ_AC_GetHitPerfV2(int client, bool[] perfs, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0;
	}
	SortByRecentBool(gB_BhopHitPerfV2[client], AC_MAX_BHOP_SAMPLES, perfs, sampleSize, gI_BhopIndexV2[client]);
	return sampleSize;
}

int GOKZ_AC_GetPerfCountV2(int client, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0;
	}

	bool[] perfs = new bool[sampleSize];
	GOKZ_AC_GetHitPerfV2(client, perfs, sampleSize);

	int perfCount = 0;
	for (int i = 0; i < sampleSize; i++)
	{
		if (perfs[i])
		{
			perfCount++;
		}
	}
	return perfCount;
}

int GOKZ_AC_GetJumpInputsV2(int client, int[] jumpInputs, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0;
	}

	int[] preJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPreJumpInputsV2[client], AC_MAX_BHOP_SAMPLES, preJumpInputs, sampleSize, gI_BhopIndexV2[client]);
	int[] postJumpInputs = new int[sampleSize];
	SortByRecent(gI_BhopPostJumpInputsV2[client], AC_MAX_BHOP_SAMPLES, postJumpInputs, sampleSize, gI_BhopIndexV2[client]);

	for (int i = 0; i < sampleSize; i++)
	{
		jumpInputs[i] = preJumpInputs[i] + postJumpInputs[i];
	}
	return sampleSize;
}

float GOKZ_AC_GetAverageJumpInputsV2(int client, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0.0;
	}

	int[] jumpInputs = new int[sampleSize];
	GOKZ_AC_GetJumpInputsV2(client, jumpInputs, sampleSize);

	int jumpInputCount = 0;
	for (int i = 0; i < sampleSize; i++)
	{
		jumpInputCount += jumpInputs[i];
	}
	return float(jumpInputCount) / float(sampleSize);
}

int GOKZ_AC_GetPreJumpInputsV2(int client, int[] preJumpInputs, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0;
	}
	SortByRecent(gI_BhopPreJumpInputsV2[client], AC_MAX_BHOP_SAMPLES, preJumpInputs, sampleSize, gI_BhopIndexV2[client]);
	return sampleSize;
}

int GOKZ_AC_GetPostJumpInputsV2(int client, int[] postJumpInputs, int sampleSize)
{
	sampleSize = IntMin(GOKZ_AC_GetSampleSizeV2(client), sampleSize);
	if (sampleSize == 0)
	{
		return 0;
	}
	SortByRecent(gI_BhopPostJumpInputsV2[client], AC_MAX_BHOP_SAMPLES, postJumpInputs, sampleSize, gI_BhopIndexV2[client]);
	return sampleSize;
}
