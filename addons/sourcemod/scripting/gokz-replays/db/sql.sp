/*
	SQL query templates for gokz-replays.
*/



// =====[ CLEANUP ]=====

// Args (in order):
//   steamID, mapID, course, mode,
//   steamID, mapID, course, mode, maxNub,
//   steamID, mapID, course, mode, maxPro
char sql_cleanup_select_prunable[] = "\
SELECT t.TimeGUID FROM Times t \
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
	)";
