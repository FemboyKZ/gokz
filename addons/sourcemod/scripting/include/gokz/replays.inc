/*
	gokz-replays Plugin Include
	
	Website: https://bitbucket.org/kztimerglobalteam/gokz
*/

#if defined _gokz_replays_included_
#endinput
#endif
#define _gokz_replays_included_

// Bit of a hack, but need it for other plugins that depend on replays to compile
#if defined REQUIRE_PLUGIN
#undef REQUIRE_PLUGIN
#include <gokz/anticheat>
#define REQUIRE_PLUGIN
#else
#include <gokz/anticheat>
#endif



// =====[ ENUMS ]=====
enum
{
	ReplayType_Run = 0,
	ReplayType_Cheater,
	ReplayType_Jump,
	REPLAYTYPE_COUNT
};

// NOTE: Replays use delta compression for storage.
// This enum is the indices of the ReplayTickData enum struct.
// NOTE: This has to match the ReplayTickData enum struct!!!
enum
{
	RPDELTA_DELTAFLAGS = 0,
	RPDELTA_DELTAFLAGS2,
	RPDELTA_VEL_X,
	RPDELTA_VEL_Y,
	RPDELTA_VEL_Z,
	RPDELTA_MOUSE_X,
	RPDELTA_MOUSE_Y,
	RPDELTA_ORIGIN_X,
	RPDELTA_ORIGIN_Y,
	RPDELTA_ORIGIN_Z,
	RPDELTA_ANGLES_X,
	RPDELTA_ANGLES_Y,
	RPDELTA_ANGLES_Z,
	RPDELTA_VELOCITY_X,
	RPDELTA_VELOCITY_Y,
	RPDELTA_VELOCITY_Z,
	RPDELTA_FLAGS,
	RPDELTA_PACKETSPERSECOND,
	RPDELTA_LAGGEDMOVEMENTVALUE,
	RPDELTA_BUTTONSFORCED,
	
	RP_V2_TICK_DATA_BLOCKSIZE
};



// =====[ STRUCTS ] =====

enum struct GeneralReplayHeader
{
	int magicNumber;
	int formatVersion;
	int replayType;
	char gokzVersion[32];
	char mapName[64];
	int mapFileSize;
	int serverIP;
	int timestamp;
    char playerAlias[MAX_NAME_LENGTH];
    int playerSteamID;
    int mode;
    int style;
	float playerSensitivity;
	float playerMYaw;
    float tickrate;
    int tickCount;
	int equippedWeapon;
	int equippedKnife;
}

enum struct JumpReplayHeader
{
	int jumpType;
	float distance;
	int blockDistance;
	int strafeCount;
	float sync;
	float pre;
	float max;
	int airtime;
}

enum struct CheaterReplayHeader
{
	ACReason ACReason;
}

enum struct RunReplayHeader
{
	float time;
	int course;
	int teleportsUsed;
}

// NOTE: Make sure to change the RPDELTA_* enum when adding/removing stuff from this!!!
enum struct ReplayTickData
{
	int deltaFlags;
	int deltaFlags2;
	float vel[3];
	int mouse[2];
	float origin[3];
	float angles[3];
	float velocity[3];
	int flags;
	float packetsPerSecond;
	float laggedMovementValue;
	int buttonsForced;
}



// =====[ CONSTANTS ]=====

#define RP_DIRECTORY "data/gokz-replays" // In Path_SM
#define RP_DIRECTORY_RUNS "data/gokz-replays/_runs" // In Path_SM
#define RP_DIRECTORY_CHEATERS "data/gokz-replays/_cheaters" // In Path_SM
#define RP_DIRECTORY_JUMPS "data/gokz-replays/_jumps" // In Path_SM
#define RP_DIRECTORY_JUMPSTATS "data/gokz-replays/_jumpstats" // In Path_SM
#define RP_DIRECTORY_BLOCKJUMPS "blocks"
#define RP_FILE_EXTENSION "replay"
#define RP_MAGIC_NUMBER 0x676F6B7A
#define RP_FORMAT_VERSION 0x02
#define RP_NAV_FILE "maps/gokz-replays.nav"
#define RP_V1_TICK_DATA_BLOCKSIZE 7
#define RP_CACHE_BLOCKSIZE 4
#define RP_MAX_BOTS 4
#define RP_PLAYBACK_BREATHER_TIME 2.0
#define RP_MIN_CHEATER_REPLAY_LENGTH 30 // 30 seconds
#define RP_MAX_CHEATER_REPLAY_LENGTH 120 // 2 minutes
#define RP_MAX_BHOP_GROUND_TICKS 5
#define RP_SKIP_TIME 10 // 10 seconds
#define RP_MAX_DURATION 6451200 // 14 hours on 128 tick
#define RP_JUMP_STEP_SOUND_THRESHOLD 140.0
#define RP_PLAYER_ACCELSPEED 450.0

#define RP_MOVETYPE_MASK		(0xF)
#define RP_IN_ATTACK			(1 << 4)
#define RP_IN_ATTACK2			(1 << 5)
#define RP_IN_JUMP				(1 << 6)
#define RP_IN_DUCK				(1 << 7)
#define RP_IN_FORWARD			(1 << 8)
#define RP_IN_BACK				(1 << 9)
#define RP_IN_LEFT				(1 << 10)
#define RP_IN_RIGHT				(1 << 11)
#define RP_IN_MOVELEFT			(1 << 12)
#define RP_IN_MOVERIGHT			(1 << 13)
#define RP_IN_RELOAD			(1 << 14)
#define RP_IN_SPEED				(1 << 15)
#define RP_IN_USE				(1 << 16)
#define RP_IN_BULLRUSH			(1 << 17)
#define RP_FL_ONGROUND			(1 << 18)
#define RP_FL_DUCKING			(1 << 19)
#define RP_FL_SWIM				(1 << 20)
#define RP_UNDER_WATER			(1 << 21)
#define RP_TELEPORT_TICK		(1 << 22)
#define RP_TAKEOFF_TICK			(1 << 23)
#define RP_HIT_PERF				(1 << 24)
#define RP_SECONDARY_EQUIPPED	(1 << 25)



// =====[ FORWARDS ]=====

/**
 * Called after a run replay has been written to disk.
 *
 * @param client			Client index of the player who completed the run.
 * @param replayType		Replay type (Run/Jump/Cheater).
 * @param map				Map the run was completed on.
 * @param course			Course the run was completed on.
 * @param timeType			Time type (Pro/Nub).
 * @param time				Run time.
 * @param filePath			Replay file path.
 * @param tempReplay		Always false here, present for compatibility with forks that store replays temporarily.
 * @return					Ignored by gokz-replays.
 */
forward Action GOKZ_RP_OnReplaySaved(int client, int replayType, const char[] map, int course, int timeType, float time, const char[] filePath, bool tempReplay);



// =====[ NATIVES ]====

/**
 * Called by the HUD to get the state of the current replay.
 *
 * @param client			Client index.
 * @param info				Struct to pass the values into.
 * @return					If successful
 */
native int GOKZ_RP_GetPlaybackInfo(int client, any[] info);

/**
 * Called by the LocalDB to initiate a replay of a jump
 *
 * @param client			Client index.
 * @param path				Path to the replay file.
 * @param isAuto			Whether the bot loops its replay and is never auto-kicked.
 * @return					Bot slot playing the replay, or -1 on failure.
 */
native int GOKZ_RP_LoadJumpReplay(int client, const char[] path, bool isAuto = false);

/**
 * Gets the client index of a replay bot.
 *
 * @param bot				Bot slot.
 * @return					Client index, 0 until the bot has joined, or -1 if the slot is invalid.
 */
native int GOKZ_RP_GetClientFromBot(int bot);

/**
 * Gets the bot slot a client is replaying on.
 *
 * @param client			Client index.
 * @return					Bot slot, or -1 if the client isn't a replay bot.
 */
native int GOKZ_RP_GetBotSlotFromClient(int client);

/**
 * Sets whether a bot loops its replay and survives having no spectators.
 *
 * @param bot				Bot slot.
 * @param isAuto			Auto state.
 * @return					True if the bot slot is valid.
 */
native bool GOKZ_RP_SetBotIsAuto(int bot, bool isAuto);

/**
 * Freezes a replay bot on its current tick.
 *
 * @param bot				Bot slot.
 * @return					True if the bot slot is valid.
 */
native bool GOKZ_RP_Pause(int bot);

/**
 * Unfreezes a replay bot.
 *
 * @param bot				Bot slot.
 * @return					True if the bot slot is valid.
 */
native bool GOKZ_RP_Resume(int bot);

/**
 * Jumps replay playback to a specific tick.
 *
 * @param bot				Bot slot.
 * @param tick				Tick to move to.
 * @return					True if the bot slot and tick are valid.
 */
native bool GOKZ_RP_SkipToTick(int bot, int tick);

/**
 * Gets the number of ticks in a bot's loaded replay.
 *
 * @param bot				Bot slot.
 * @return					Tick count, or 0 if nothing is loaded.
 */
native int GOKZ_RP_GetTickCount(int bot);

/**
 * Reads one tick of a bot's loaded replay, indexed by the RPDELTA_* enum.
 * Version 1 replays only fill in origin, angles and flags.
 *
 * @param bot				Bot slot.
 * @param tick				Tick to read.
 * @param output			Array to receive the tick data.
 * @return					True if the tick was read.
 */
native bool GOKZ_RP_GetTickData(int bot, int tick, any output[RP_V2_TICK_DATA_BLOCKSIZE]);

/**
 * Called by the HUD to show the replay control menu.
 *
 * @param client			Client index.
 */
native bool GOKZ_RP_UpdateReplayControlMenu(int client);

/**
 * Records the player's recent buffer as a standalone jumpstat replay,
 * written to RP_DIRECTORY_JUMPSTATS/<guid>.replay after the post-jump breather.
 *
 * @param client			Client index.
 * @param guid				Unique id used as the filename (no extension).
 * @param mode				Mode index.
 * @param style				Style index.
 * @param jumpType			Jump type.
 * @param distance			Jump distance.
 * @param block				Block distance (0 if not a block jump).
 * @param strafes			Strafe count.
 * @param sync				Sync.
 * @param pre				Prespeed.
 * @param max				Max speed.
 * @param airtime			Airtime (seconds * GOKZ_DB_JS_AIRTIME_PRECISION).
 * @return					True if the save was scheduled.
 */
native bool GOKZ_RP_SaveJumpStatReplay(int client, const char[] guid, int mode, int style, int jumpType, float distance, int block, int strafes, float sync, float pre, float max, int airtime);



// =====[ STOCKS ]=====

stock void GOKZ_RP_FormatRunReplayPath(char[] buffer, int maxlength, const char[] guid)
{
	BuildPath(Path_SM, buffer, maxlength,
		"%s/%s.%s",
		RP_DIRECTORY_RUNS,
		guid,
		RP_FILE_EXTENSION);
}

stock void GOKZ_RP_FormatJumpStatReplayPath(char[] buffer, int maxlength, const char[] guid)
{
	BuildPath(Path_SM, buffer, maxlength,
		"%s/%s.%s",
		RP_DIRECTORY_JUMPSTATS,
		guid,
		RP_FILE_EXTENSION);
}



// =====[ DEPENDENCY ]=====

public SharedPlugin __pl_gokz_replays = 
{
	name = "gokz-replays", 
	file = "gokz-replays.smx", 
	#if defined REQUIRE_PLUGIN
	required = 1, 
	#else
	required = 0, 
	#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_gokz_replays_SetNTVOptional()
{
	MarkNativeAsOptional("GOKZ_RP_GetPlaybackInfo");
	MarkNativeAsOptional("GOKZ_RP_LoadJumpReplay");
	MarkNativeAsOptional("GOKZ_RP_UpdateReplayControlMenu");
	MarkNativeAsOptional("GOKZ_RP_SaveJumpStatReplay");
	MarkNativeAsOptional("GOKZ_RP_GetClientFromBot");
	MarkNativeAsOptional("GOKZ_RP_GetBotSlotFromClient");
	MarkNativeAsOptional("GOKZ_RP_SetBotIsAuto");
	MarkNativeAsOptional("GOKZ_RP_Pause");
	MarkNativeAsOptional("GOKZ_RP_Resume");
	MarkNativeAsOptional("GOKZ_RP_SkipToTick");
	MarkNativeAsOptional("GOKZ_RP_GetTickCount");
	MarkNativeAsOptional("GOKZ_RP_GetTickData");
}
#endif
