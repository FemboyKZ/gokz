/*
	SQL query templates.
*/



// =====[ PLAYERS ]=====

char sqlite_players_create[] = "\
CREATE TABLE IF NOT EXISTS Players ( \
    SteamID32 INTEGER NOT NULL, \
    Alias TEXT, \
    Country TEXT, \
    IP TEXT, \
    Cheater INTEGER NOT NULL DEFAULT '0', \
    LastPlayed TIMESTAMP NULL DEFAULT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Player PRIMARY KEY (SteamID32))";

char mysql_players_create[] = "\
CREATE TABLE IF NOT EXISTS Players ( \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    Alias VARCHAR(32), \
    Country VARCHAR(45), \
    IP VARCHAR(15), \
    Cheater TINYINT UNSIGNED NOT NULL DEFAULT '0', \
    LastPlayed TIMESTAMP NULL DEFAULT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Player PRIMARY KEY (SteamID32))";

char sqlite_players_insert[] = "\
INSERT OR IGNORE INTO Players (Alias, Country, IP, SteamID32, LastPlayed) \
    VALUES ('%s', '%s', '%s', %d, CURRENT_TIMESTAMP)";

char sqlite_players_update[] = "\
UPDATE OR IGNORE Players \
    SET Alias='%s', Country='%s', IP='%s', LastPlayed=CURRENT_TIMESTAMP \
    WHERE SteamID32=%d";

char mysql_players_upsert[] = "\
INSERT INTO Players (Alias, Country, IP, SteamID32, LastPlayed) \
    VALUES ('%s', '%s', '%s', %d, CURRENT_TIMESTAMP) \
    ON DUPLICATE KEY UPDATE \
    SteamID32=VALUES(SteamID32), Alias=VALUES(Alias), Country=VALUES(Country), \
    IP=VALUES(IP), LastPlayed=VALUES(LastPlayed)";

char sql_players_get_cheater[] = "\
SELECT Cheater \
    FROM Players \
    WHERE SteamID32=%d";

char sql_players_set_cheater[] = "\
UPDATE Players \
    SET Cheater=%d \
    WHERE SteamID32=%d";



// =====[ MAPS ]=====

char sqlite_maps_create[] = "\
CREATE TABLE IF NOT EXISTS Maps ( \
    MapID INTEGER NOT NULL, \
    Name VARCHAR(32) NOT NULL UNIQUE, \
    LastPlayed TIMESTAMP NULL DEFAULT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Maps PRIMARY KEY (MapID))";

char mysql_maps_create[] = "\
CREATE TABLE IF NOT EXISTS Maps ( \
    MapID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    Name VARCHAR(32) NOT NULL UNIQUE, \
    LastPlayed TIMESTAMP NULL DEFAULT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Maps PRIMARY KEY (MapID))";

char sqlite_maps_insert[] = "\
INSERT OR IGNORE INTO Maps (Name, LastPlayed) \
    VALUES ('%s', CURRENT_TIMESTAMP)";

char sqlite_maps_update[] = "\
UPDATE OR IGNORE Maps \
    SET LastPlayed=CURRENT_TIMESTAMP \
    WHERE Name='%s'";

char mysql_maps_upsert[] = "\
INSERT INTO Maps (Name, LastPlayed) \
    VALUES ('%s', CURRENT_TIMESTAMP) \
    ON DUPLICATE KEY UPDATE \
    LastPlayed=CURRENT_TIMESTAMP";

char sql_maps_findid[] = "\
SELECT MapID, Name \
    FROM Maps \
    WHERE Name LIKE '%%%s%%' \
    ORDER BY (Name='%s') DESC, LENGTH(Name) \
    LIMIT 1";



// =====[ MAPCOURSES ]=====

char sqlite_mapcourses_create[] = "\
CREATE TABLE IF NOT EXISTS MapCourses ( \
    MapCourseID INTEGER NOT NULL, \
    MapID INTEGER NOT NULL, \
    Course INTEGER NOT NULL, \
    Created INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_MapCourses PRIMARY KEY (MapCourseID), \
    CONSTRAINT UQ_MapCourses_MapIDCourse UNIQUE (MapID, Course), \
    CONSTRAINT FK_MapCourses_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char mysql_mapcourses_create[] = "\
CREATE TABLE IF NOT EXISTS MapCourses ( \
    MapCourseID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    MapID INTEGER UNSIGNED NOT NULL, \
    Course INTEGER UNSIGNED NOT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_MapCourses PRIMARY KEY (MapCourseID), \
    CONSTRAINT UQ_MapCourses_MapIDCourse UNIQUE (MapID, Course), \
    CONSTRAINT FK_MapCourses_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char sqlite_mapcourses_insert[] = "\
INSERT OR IGNORE INTO MapCourses (MapID, Course) \
    VALUES (%d, %d)";

char mysql_mapcourses_insert[] = "\
INSERT IGNORE INTO MapCourses (MapID, Course) \
    VALUES (%d, %d)";



// =====[ TIMES ]=====

char sqlite_times_create[] = "\
CREATE TABLE IF NOT EXISTS Times ( \
    TimeID INTEGER NOT NULL, \
    SteamID32 INTEGER NOT NULL, \
    MapCourseID INTEGER NOT NULL, \
    Mode INTEGER NOT NULL, \
    Style INTEGER NOT NULL, \
    RunTime INTEGER NOT NULL, \
    Teleports INTEGER NOT NULL, \
    Created INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Times PRIMARY KEY (TimeID), \
    CONSTRAINT FK_Times_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE, CONSTRAINT FK_Times_MapCourseID \
    FOREIGN KEY (MapCourseID) REFERENCES MapCourses(MapCourseID) \
    ON DELETE CASCADE)";

char mysql_times_create[] = "\
CREATE TABLE IF NOT EXISTS Times ( \
    TimeID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    MapCourseID INTEGER UNSIGNED NOT NULL, \
    Mode TINYINT UNSIGNED NOT NULL, \
    Style TINYINT UNSIGNED NOT NULL, \
    RunTime INTEGER UNSIGNED NOT NULL, \
    Teleports SMALLINT UNSIGNED NOT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Times PRIMARY KEY (TimeID), \
    CONSTRAINT FK_Times_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE, \
    CONSTRAINT FK_Times_MapCourseID FOREIGN KEY (MapCourseID) REFERENCES MapCourses(MapCourseID) \
    ON DELETE CASCADE)";

char sql_times_insert[] = "\
INSERT INTO Times (SteamID32, MapCourseID, Mode, Style, RunTime, Teleports, TimeGUID) \
    SELECT %d, MapCourseID, %d, %d, %d, %d, '%s' \
    FROM MapCourses \
    WHERE MapID=%d AND Course=%d";

char sql_times_delete[] = "\
DELETE FROM Times \
    WHERE TimeID=%d";

char sql_times_alter_add_guid[] = "\
ALTER TABLE Times \
    ADD TimeGUID VARCHAR(255)";



// =====[ JUMPSTATS ]=====

char sqlite_jumpstats_create[] = "\
CREATE TABLE IF NOT EXISTS Jumpstats ( \
    JumpID INTEGER NOT NULL, \
    SteamID32 INTEGER NOT NULL, \
    JumpType INTEGER NOT NULL, \
    Mode INTEGER NOT NULL, \
    Distance INTEGER NOT NULL, \
    IsBlockJump INTEGER NOT NULL, \
    Block INTEGER NOT NULL, \
    Strafes INTEGER NOT NULL, \
    Sync INTEGER NOT NULL, \
    Pre INTEGER NOT NULL, \
    Max INTEGER NOT NULL, \
    Airtime INTEGER NOT NULL, \
    Created INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Jumpstats PRIMARY KEY (JumpID), \
    CONSTRAINT FK_Jumpstats_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char mysql_jumpstats_create[] = "\
CREATE TABLE IF NOT EXISTS Jumpstats ( \
    JumpID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    JumpType TINYINT UNSIGNED NOT NULL, \
    Mode TINYINT UNSIGNED NOT NULL, \
    Distance INTEGER UNSIGNED NOT NULL, \
    IsBlockJump TINYINT UNSIGNED NOT NULL, \
    Block SMALLINT UNSIGNED NOT NULL, \
    Strafes INTEGER UNSIGNED NOT NULL, \
    Sync INTEGER UNSIGNED NOT NULL, \
    Pre INTEGER UNSIGNED NOT NULL, \
    Max INTEGER UNSIGNED NOT NULL, \
    Airtime INTEGER UNSIGNED NOT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_Jumpstats PRIMARY KEY (JumpID), \
    CONSTRAINT FK_Jumpstats_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char sql_jumpstats_insert[] = "\
INSERT INTO Jumpstats (SteamID32, JumpType, Mode, Distance, IsBlockJump, Block, Strafes, Sync, Pre, Max, Airtime) \
    VALUES (%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d)";

char sql_jumpstats_update[] = "\
UPDATE Jumpstats \
    SET \
        SteamID32=%d, \
        JumpType=%d, \
        Mode=%d, \
        Distance=%d, \
        IsBlockJump=%d, \
        Block=%d, \
        Strafes=%d, \
        Sync=%d, \
        Pre=%d, \
        Max=%d, \
        Airtime=%d \
    WHERE \
        JumpID=%d";

char sql_jumpstats_getrecord[] = "\
SELECT JumpID, Distance, Block \
    FROM \
        Jumpstats \
    WHERE \
        SteamID32=%d AND \
        JumpType=%d AND \
        Mode=%d AND \
        IsBlockJump=%d \
    ORDER BY Block DESC, Distance DESC";

char sql_jumpstats_deleterecord[] = "\
DELETE \
    FROM \
        Jumpstats \
    WHERE \
        JumpID = \
        ( SELECT * FROM ( \
            SELECT JumpID \
                FROM \
                    Jumpstats \
                WHERE \
                    SteamID32=%d AND \
                    JumpType=%d AND \
                    Mode=%d AND \
                    IsBlockJump=%d \
                ORDER BY Block DESC, Distance DESC \
                LIMIT 1 \
			) AS tmp \
        )";

char sql_jumpstats_deleteallrecords[] = "\
DELETE \
	FROM \
		Jumpstats \
	WHERE \
		SteamID32 = %d;";

char sql_jumpstats_deletejump[] = "\
DELETE \
	FROM \
		Jumpstats \
	WHERE \
		JumpID = %d;";

char sql_jumpstats_getpbs[] = "\
SELECT MAX(Distance), Mode, JumpType \
    FROM \
        Jumpstats \
    WHERE \
        SteamID32=%d \
    GROUP BY \
    	Mode, JumpType";

char sql_jumpstats_getblockpbs[] = "\
SELECT MAX(js.Distance), js.Mode, js.JumpType, js.Block \
	FROM \
		Jumpstats js \
	INNER JOIN \
	( \
		SELECT Mode, JumpType, MAX(BLOCK) Block \
			FROM \
				Jumpstats \
			WHERE \
				IsBlockJump=1 AND \
				SteamID32=%d \
			GROUP BY \
				Mode, JumpType \
	) pb \
	ON \
		js.Mode=pb.Mode AND \
		js.JumpType=pb.JumpType AND \
		js.Block=pb.Block \
	WHERE \
		js.SteamID32=%d \
	GROUP BY \
		js.Mode, js.JumpType, js.Block";



// =====[ JUMPSTAT REPLAYS ]=====
// Archive of every valid jumpstat replay. 
// ReplayPath is relative to the gokz-replays data dir.

char sqlite_jumpstatreplays_create[] = "\
CREATE TABLE IF NOT EXISTS JumpstatReplays ( \
    ReplayID INTEGER NOT NULL, \
    SteamID32 INTEGER NOT NULL, \
    JumpType INTEGER NOT NULL, \
    Mode INTEGER NOT NULL, \
    Distance INTEGER NOT NULL, \
    IsBlockJump INTEGER NOT NULL, \
    Block INTEGER NOT NULL, \
    Strafes INTEGER NOT NULL, \
    Sync INTEGER NOT NULL, \
    Pre INTEGER NOT NULL, \
    Max INTEGER NOT NULL, \
    Airtime INTEGER NOT NULL, \
    Created INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    ReplayPath VARCHAR(255) NOT NULL, \
    CONSTRAINT PK_JumpstatReplays PRIMARY KEY (ReplayID), \
    CONSTRAINT FK_JumpstatReplays_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char sqlite_jumpstatreplays_index[] = "\
CREATE INDEX IF NOT EXISTS IX_JumpstatReplays_Group \
    ON JumpstatReplays (SteamID32, JumpType, Mode, Distance)";

char mysql_jumpstatreplays_create[] = "\
CREATE TABLE IF NOT EXISTS JumpstatReplays ( \
    ReplayID INTEGER UNSIGNED NOT NULL AUTO_INCREMENT, \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    JumpType TINYINT UNSIGNED NOT NULL, \
    Mode TINYINT UNSIGNED NOT NULL, \
    Distance INTEGER UNSIGNED NOT NULL, \
    IsBlockJump TINYINT UNSIGNED NOT NULL, \
    Block SMALLINT UNSIGNED NOT NULL, \
    Strafes INTEGER UNSIGNED NOT NULL, \
    Sync INTEGER UNSIGNED NOT NULL, \
    Pre INTEGER UNSIGNED NOT NULL, \
    Max INTEGER UNSIGNED NOT NULL, \
    Airtime INTEGER UNSIGNED NOT NULL, \
    Created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    ReplayPath VARCHAR(255) NOT NULL, \
    CONSTRAINT PK_JumpstatReplays PRIMARY KEY (ReplayID), \
    KEY IX_JumpstatReplays_Group (SteamID32, JumpType, Mode, Distance), \
    CONSTRAINT FK_JumpstatReplays_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char sql_jumpstatreplays_insert[] = "\
INSERT INTO JumpstatReplays (SteamID32, JumpType, Mode, Distance, IsBlockJump, Block, Strafes, Sync, Pre, Max, Airtime, ReplayPath) \
    VALUES (%d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, '%s')";

// Selects rows ranked beyond the keep-limit within their (player, mode, type) group,
// lowest distance first, capped to a batch size. %d = keep limit,  %d = batch size.
char sql_jumpstatreplays_cleanup_select[] = "\
SELECT ReplayID, ReplayPath \
    FROM JumpstatReplays jr \
    WHERE ( \
        SELECT COUNT(*) FROM JumpstatReplays jr2 \
        WHERE jr2.SteamID32 = jr.SteamID32 AND jr2.JumpType = jr.JumpType AND jr2.Mode = jr.Mode \
            AND (jr2.Distance > jr.Distance OR (jr2.Distance = jr.Distance AND jr2.ReplayID > jr.ReplayID)) \
    ) >= %d \
    ORDER BY Distance ASC \
    LIMIT %d";

// %s = comma-separated ReplayID list.
char sql_jumpstatreplays_delete_ids[] = "\
DELETE FROM JumpstatReplays WHERE ReplayID IN (%s)";



// =====[ ANTICHEAT STATS ]=====
// Running per-player aggregates of the anti-cheat strafe features, one row per (player, mode, jump type).
// Sums accumulate per jump so mean/std per metric fall out of a single SELECT.
// See gokz-jumpstats/anticheat_metrics.sp.

char sqlite_acstats_create[] = "\
CREATE TABLE IF NOT EXISTS AnticheatStats ( \
    SteamID32 INTEGER NOT NULL, \
    Mode INTEGER NOT NULL, \
    JumpType INTEGER NOT NULL, \
    Jumps INTEGER NOT NULL, \
    UsableTicks INTEGER NOT NULL, \
    TurnTicks INTEGER NOT NULL, \
    TurnBindTicks INTEGER NOT NULL, \
    CeilingTicks INTEGER NOT NULL, \
    MouseTicks INTEGER NOT NULL, \
    InjectedTicks INTEGER NOT NULL, \
    FlipMatched INTEGER NOT NULL, \
    FlipZeroLag INTEGER NOT NULL, \
    KJumps INTEGER NOT NULL, \
    LenStdJumps INTEGER NOT NULL, \
    PeakJumps INTEGER NOT NULL, \
    FlipImpulses INTEGER NOT NULL, \
    FlipAccelSamples INTEGER NOT NULL, \
    SharpJumps INTEGER NOT NULL, \
    EffSum REAL NOT NULL, \
    EffSqSum REAL NOT NULL, \
    YawResSum REAL NOT NULL, \
    YawResSqSum REAL NOT NULL, \
    KResSum REAL NOT NULL, \
    KResSqSum REAL NOT NULL, \
    LenStdSum REAL NOT NULL, \
    LenStdSqSum REAL NOT NULL, \
    FlipLagSum REAL NOT NULL, \
    FlipLagSqSum REAL NOT NULL, \
    PeakSum REAL NOT NULL, \
    PeakSqSum REAL NOT NULL, \
    SharpSum REAL NOT NULL, \
    SharpSqSum REAL NOT NULL, \
    Updated INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP, \
    CONSTRAINT PK_AnticheatStats PRIMARY KEY (SteamID32, Mode, JumpType), \
    CONSTRAINT FK_AnticheatStats_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char mysql_acstats_create[] = "\
CREATE TABLE IF NOT EXISTS AnticheatStats ( \
    SteamID32 INTEGER UNSIGNED NOT NULL, \
    Mode TINYINT UNSIGNED NOT NULL, \
    JumpType TINYINT UNSIGNED NOT NULL, \
    Jumps INTEGER UNSIGNED NOT NULL, \
    UsableTicks INTEGER UNSIGNED NOT NULL, \
    TurnTicks INTEGER UNSIGNED NOT NULL, \
    TurnBindTicks INTEGER UNSIGNED NOT NULL, \
    CeilingTicks INTEGER UNSIGNED NOT NULL, \
    MouseTicks INTEGER UNSIGNED NOT NULL, \
    InjectedTicks INTEGER UNSIGNED NOT NULL, \
    FlipMatched INTEGER UNSIGNED NOT NULL, \
    FlipZeroLag INTEGER UNSIGNED NOT NULL, \
    KJumps INTEGER UNSIGNED NOT NULL, \
    LenStdJumps INTEGER UNSIGNED NOT NULL, \
    PeakJumps INTEGER UNSIGNED NOT NULL, \
    FlipImpulses INTEGER UNSIGNED NOT NULL, \
    FlipAccelSamples INTEGER UNSIGNED NOT NULL, \
    SharpJumps INTEGER UNSIGNED NOT NULL, \
    EffSum DOUBLE NOT NULL, \
    EffSqSum DOUBLE NOT NULL, \
    YawResSum DOUBLE NOT NULL, \
    YawResSqSum DOUBLE NOT NULL, \
    KResSum DOUBLE NOT NULL, \
    KResSqSum DOUBLE NOT NULL, \
    LenStdSum DOUBLE NOT NULL, \
    LenStdSqSum DOUBLE NOT NULL, \
    FlipLagSum DOUBLE NOT NULL, \
    FlipLagSqSum DOUBLE NOT NULL, \
    PeakSum DOUBLE NOT NULL, \
    PeakSqSum DOUBLE NOT NULL, \
    SharpSum DOUBLE NOT NULL, \
    SharpSqSum DOUBLE NOT NULL, \
    Updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
    CONSTRAINT PK_AnticheatStats PRIMARY KEY (SteamID32, Mode, JumpType), \
    CONSTRAINT FK_AnticheatStats_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    ON DELETE CASCADE)";

char sqlite_acstats_upsert[] = "\
INSERT INTO AnticheatStats (SteamID32, Mode, JumpType, Jumps, UsableTicks, TurnTicks, TurnBindTicks, \
        CeilingTicks, MouseTicks, InjectedTicks, FlipMatched, FlipZeroLag, KJumps, LenStdJumps, PeakJumps, \
        FlipImpulses, FlipAccelSamples, SharpJumps, \
        EffSum, EffSqSum, YawResSum, YawResSqSum, KResSum, KResSqSum, LenStdSum, LenStdSqSum, \
        FlipLagSum, FlipLagSqSum, PeakSum, PeakSqSum, SharpSum, SharpSqSum, Updated) \
    VALUES (%d, %d, %d, 1, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, CURRENT_TIMESTAMP) \
    ON CONFLICT (SteamID32, Mode, JumpType) DO UPDATE SET \
        Jumps = Jumps + 1, \
        UsableTicks = UsableTicks + excluded.UsableTicks, \
        TurnTicks = TurnTicks + excluded.TurnTicks, \
        TurnBindTicks = TurnBindTicks + excluded.TurnBindTicks, \
        CeilingTicks = CeilingTicks + excluded.CeilingTicks, \
        MouseTicks = MouseTicks + excluded.MouseTicks, \
        InjectedTicks = InjectedTicks + excluded.InjectedTicks, \
        FlipMatched = FlipMatched + excluded.FlipMatched, \
        FlipZeroLag = FlipZeroLag + excluded.FlipZeroLag, \
        KJumps = KJumps + excluded.KJumps, \
        LenStdJumps = LenStdJumps + excluded.LenStdJumps, \
        PeakJumps = PeakJumps + excluded.PeakJumps, \
        FlipImpulses = FlipImpulses + excluded.FlipImpulses, \
        FlipAccelSamples = FlipAccelSamples + excluded.FlipAccelSamples, \
        SharpJumps = SharpJumps + excluded.SharpJumps, \
        EffSum = EffSum + excluded.EffSum, \
        EffSqSum = EffSqSum + excluded.EffSqSum, \
        YawResSum = YawResSum + excluded.YawResSum, \
        YawResSqSum = YawResSqSum + excluded.YawResSqSum, \
        KResSum = KResSum + excluded.KResSum, \
        KResSqSum = KResSqSum + excluded.KResSqSum, \
        LenStdSum = LenStdSum + excluded.LenStdSum, \
        LenStdSqSum = LenStdSqSum + excluded.LenStdSqSum, \
        FlipLagSum = FlipLagSum + excluded.FlipLagSum, \
        FlipLagSqSum = FlipLagSqSum + excluded.FlipLagSqSum, \
        PeakSum = PeakSum + excluded.PeakSum, \
        PeakSqSum = PeakSqSum + excluded.PeakSqSum, \
        SharpSum = SharpSum + excluded.SharpSum, \
        SharpSqSum = SharpSqSum + excluded.SharpSqSum, \
        Updated = CURRENT_TIMESTAMP";

char mysql_acstats_upsert[] = "\
INSERT INTO AnticheatStats (SteamID32, Mode, JumpType, Jumps, UsableTicks, TurnTicks, TurnBindTicks, \
        CeilingTicks, MouseTicks, InjectedTicks, FlipMatched, FlipZeroLag, KJumps, LenStdJumps, PeakJumps, \
        FlipImpulses, FlipAccelSamples, SharpJumps, \
        EffSum, EffSqSum, YawResSum, YawResSqSum, KResSum, KResSqSum, LenStdSum, LenStdSqSum, \
        FlipLagSum, FlipLagSqSum, PeakSum, PeakSqSum, SharpSum, SharpSqSum) \
    VALUES (%d, %d, %d, 1, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %d, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f, %f) \
    ON DUPLICATE KEY UPDATE \
        Jumps = Jumps + 1, \
        UsableTicks = UsableTicks + VALUES(UsableTicks), \
        TurnTicks = TurnTicks + VALUES(TurnTicks), \
        TurnBindTicks = TurnBindTicks + VALUES(TurnBindTicks), \
        CeilingTicks = CeilingTicks + VALUES(CeilingTicks), \
        MouseTicks = MouseTicks + VALUES(MouseTicks), \
        InjectedTicks = InjectedTicks + VALUES(InjectedTicks), \
        FlipMatched = FlipMatched + VALUES(FlipMatched), \
        FlipZeroLag = FlipZeroLag + VALUES(FlipZeroLag), \
        KJumps = KJumps + VALUES(KJumps), \
        LenStdJumps = LenStdJumps + VALUES(LenStdJumps), \
        PeakJumps = PeakJumps + VALUES(PeakJumps), \
        FlipImpulses = FlipImpulses + VALUES(FlipImpulses), \
        FlipAccelSamples = FlipAccelSamples + VALUES(FlipAccelSamples), \
        SharpJumps = SharpJumps + VALUES(SharpJumps), \
        EffSum = EffSum + VALUES(EffSum), \
        EffSqSum = EffSqSum + VALUES(EffSqSum), \
        YawResSum = YawResSum + VALUES(YawResSum), \
        YawResSqSum = YawResSqSum + VALUES(YawResSqSum), \
        KResSum = KResSum + VALUES(KResSum), \
        KResSqSum = KResSqSum + VALUES(KResSqSum), \
        LenStdSum = LenStdSum + VALUES(LenStdSum), \
        LenStdSqSum = LenStdSqSum + VALUES(LenStdSqSum), \
        FlipLagSum = FlipLagSum + VALUES(FlipLagSum), \
        FlipLagSqSum = FlipLagSqSum + VALUES(FlipLagSqSum), \
        PeakSum = PeakSum + VALUES(PeakSum), \
        PeakSqSum = PeakSqSum + VALUES(PeakSqSum), \
        SharpSum = SharpSum + VALUES(SharpSum), \
        SharpSqSum = SharpSqSum + VALUES(SharpSqSum)";



// =====[ VB POSITIONS ]=====

char sqlite_vbpos_create[] = "\
CREATE TABLE IF NOT EXISTS VBPosition ( \
	SteamID32 INTEGER NOT NULL, \
	MapID INTEGER NOT NULL, \
	X REAL NOT NULL, \
	Y REAL NOT NULL, \
	Z REAL NOT NULL, \
	Course INTEGER NOT NULL, \
	IsStart INTEGER NOT NULL, \
	CONSTRAINT PK_VBPosition PRIMARY KEY (SteamID32, MapID, IsStart), \
    CONSTRAINT FK_VBPosition_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32), \
    CONSTRAINT FK_VBPosition_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char mysql_vbpos_create[] = "\
CREATE TABLE IF NOT EXISTS VBPosition ( \
	SteamID32 INTEGER UNSIGNED NOT NULL, \
	MapID INTEGER UNSIGNED NOT NULL, \
	X REAL NOT NULL, \
	Y REAL NOT NULL, \
	Z REAL NOT NULL, \
	Course INTEGER NOT NULL, \
	IsStart INTEGER NOT NULL, \
	CONSTRAINT PK_VBPosition PRIMARY KEY (SteamID32, MapID, IsStart), \
    CONSTRAINT FK_VBPosition_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32), \
    CONSTRAINT FK_VBPosition_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char sql_vbpos_upsert[] = "\
REPLACE INTO VBPosition (SteamID32, MapID, X, Y, Z, Course, IsStart) \
	VALUES (%d, %d, %f, %f, %f, %d, %d)";

char sql_vbpos_get[] = "\
SELECT SteamID32, MapID, Course, IsStart, X, Y, Z \
	FROM \
		VBPosition \
	WHERE \
		SteamID32 = %d AND \
		MapID = %d";



// =====[ START POSITIONS ]=====

char sqlite_startpos_create[] = "\
CREATE TABLE IF NOT EXISTS StartPosition ( \
	SteamID32 INTEGER NOT NULL, \
	MapID INTEGER NOT NULL, \
	X REAL NOT NULL, \
	Y REAL NOT NULL, \
	Z REAL NOT NULL, \
	Angle0 REAL NOT NULL, \
	Angle1 REAL NOT NULL, \
	CONSTRAINT PK_StartPosition PRIMARY KEY (SteamID32, MapID), \
    CONSTRAINT FK_StartPosition_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32) \
    CONSTRAINT FK_StartPosition_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char mysql_startpos_create[] = "\
CREATE TABLE IF NOT EXISTS StartPosition ( \
	SteamID32 INTEGER UNSIGNED NOT NULL, \
	MapID INTEGER UNSIGNED NOT NULL, \
	X REAL NOT NULL, \
	Y REAL NOT NULL, \
	Z REAL NOT NULL, \
	Angle0 REAL NOT NULL, \
	Angle1 REAL NOT NULL, \
	CONSTRAINT PK_StartPosition PRIMARY KEY (SteamID32, MapID), \
    CONSTRAINT FK_StartPosition_SteamID32 FOREIGN KEY (SteamID32) REFERENCES Players(SteamID32), \
    CONSTRAINT FK_StartPosition_MapID FOREIGN KEY (MapID) REFERENCES Maps(MapID) \
    ON DELETE CASCADE)";

char sql_startpos_upsert[] = "\
REPLACE INTO StartPosition (SteamID32, MapID, X, Y, Z, Angle0, Angle1) \
	VALUES (%d, %d, %f, %f, %f, %f, %f)";

char sql_startpos_get[] = "\
SELECT SteamID32, MapID, X, Y, Z, Angle0, Angle1 \
	FROM \
		StartPosition \
	WHERE \
		SteamID32 = %d AND \
		MapID = %d";
