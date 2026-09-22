/*
	Anti-cheat strafe features, computed at landing from the pose history.
*/


// CS:GO AirAccelerate caps only the addspeed check at 30 u/s.
// The accelspeed budget itself uses the uncapped wishspeed, which is cl_sidespeed 450 clamped to the knife max speed of 250.
#define AC_AIR_SPEED_CAP 30.0
#define AC_WISHSPEED 250.0

#define AC_TURN_EPSILON 0.001
#define AC_PITCH_EPSILON 0.001
#define AC_FLIP_SEARCH 8
#define AC_MIN_MOUSE_SAMPLES 8
#define AC_IMPULSE_SPIKE 2.0
#define AC_IMPULSE_SETTLE 1.0
#define AC_SHARPNESS_FLOOR 0.5

// Ceiling stats are meaningless without sustained real turning
#define AC_MIN_CEILING_TURN_TICKS 16
#define AC_MIN_CEILING_PEAK 1.0

// Above this |deltaYaw| a tick is a spin/snap, not strafing
#define AC_SPIN_THRESHOLD 30.0

static const float AC_MODE_AIRACCELERATE[MODE_COUNT] = { 12.0, 100.0, 100.0 }; // (Vanilla, SimpleKZ, KZTimer).

#define acPose(%1) (poseHistory[jumper][(%1) % JS_FAILSTATS_MAX_TRACKED_TICKS])

// Per-tick optimum under the CS:GO air accelerate rules.
//
// The engine adds min(A, W - v*cos(gamma)) along wishdir, where gamma is the angle between horizontal velocity and wishdir,
// A the accel budget and W = 30 the addspeed cap.
//
// When A >= W (SKZ/KZT at airaccelerate 100) the addspeed term always binds and the gain peaks at cos(gamma) = 0: 
// push perpendicular to velocity.
// When A < W (VNL) the peak is the largest cos(gamma) that still fits the whole budget, cos(gamma*) = (W - A) / v.
//
// optDeltaYaw is how far the velocity direction rotates on an optimal tick.
// A perfect strafer turns the view by exactly this much to hold gamma*.
static void AcTickOptimal(float speed, float accel, float &maxGain, float &optDeltaYaw)
{
	if (accel <= 0.0)
	{
		maxGain = 0.0;
		optDeltaYaw = 0.0;
		return;
	}
	if (accel >= AC_AIR_SPEED_CAP)
	{
		maxGain = SquareRoot(speed * speed + AC_AIR_SPEED_CAP * AC_AIR_SPEED_CAP) - speed;
		optDeltaYaw = ArcTangent2(AC_AIR_SPEED_CAP, speed) * (180.0 / FLOAT_PI);
		return;
	}
	if (speed <= AC_AIR_SPEED_CAP - accel)
	{
		maxGain = accel;
		optDeltaYaw = 0.0;
		return;
	}
	float cosG = (AC_AIR_SPEED_CAP - accel) / speed;
	float sinG = SquareRoot(1.0 - cosG * cosG);
	float newSpeed = SquareRoot(speed * speed + accel * accel + 2.0 * speed * accel * cosG);
	maxGain = newSpeed - speed;
	optDeltaYaw = ArcTangent2(accel * sinG, speed + accel * cosG) * (180.0 / FLOAT_PI);
}

void ComputeAcFeatures(JumpTracker tracker)
{
	int jumper = tracker.jumper;
	int duration = tracker.jump.duration;

	tracker.jump.acKFit = -1.0;
	tracker.jump.acKResidualRms = -1.0;
	// Tracker persists across jumps, so clear fields only written conditionally below.
	// Yaw residual -1 = no turning ticks, save_ac keeps it out of the pooled mean.
	tracker.jump.acEffMean = 0.0;
	tracker.jump.acEffStd = 0.0;
	tracker.jump.acYawResidualRms = -1.0;

	// The ring holds the last 128 poses and every tick needs its predecessor.
	// The last tick is the grounded landing tick, skip it (its gain includes ground friction).
	int firstTick = 1;
	if (duration > JS_FAILSTATS_MAX_TRACKED_TICKS - 2)
	{
		firstTick = duration - (JS_FAILSTATS_MAX_TRACKED_TICKS - 2);
	}
	int lastTick = duration - 1;
	if (lastTick < firstTick)
	{
		tracker.jump.acUsableTicks = 0;
		return;
	}

	int mode = GOKZ_GetCoreOption(jumper, Option_Mode);
	float baseAccel = AC_MODE_AIRACCELERATE[mode] * AC_WISHSPEED * GetTickInterval();

	float effSum, effSqSum;
	int effTicks;
	float yawResSqSum;
	int yawResTicks;
	float ratios[JS_FAILSTATS_MAX_TRACKED_TICKS];
	float kMouse[JS_FAILSTATS_MAX_TRACKED_TICKS];
	float kDYaw[JS_FAILSTATS_MAX_TRACKED_TICKS];
	int kSamples;
	float turnMags[JS_FAILSTATS_MAX_TRACKED_TICKS];
	int turnTicks;
	int mouseTicks, injectedTicks, turnBindTicks, spinTicks, yawlessMouseTicks;
	float pitchRatios[JS_FAILSTATS_MAX_TRACKED_TICKS];
	int pitchSamples;
	int mouseYDeadTicks, pitchFrozenTicks, cmdGapTicks;
	int sidemoveGhostTicks, sidemoveNullTicks, sidemoveMismatchTicks, rollTicks;
	int prevSideCond;

	for (int t = firstTick; t <= lastTick; t++)
	{
		float prevSpeed = acPose(t - 1).speed;
		float gain = acPose(t).speed - prevSpeed;
		float dYaw = CalcDeltaAngle(acPose(t - 1).orientation[1], acPose(t).orientation[1]);
		float absDYaw = FloatAbs(dYaw);
		int buttons = acPose(t).buttons;
		bool turnBind = (buttons & (IN_LEFT | IN_RIGHT)) != 0;

		// Lagged movement scales the accel budget, matching the replay side
		float lagged = acPose(t).lagged > 0.0 ? acPose(t).lagged : 1.0;
		float accel = baseAccel * lagged;

		float maxGain, optDeltaYaw;
		AcTickOptimal(prevSpeed, accel, maxGain, optDeltaYaw);
		if (maxGain > 0.000001)
		{
			float eff = gain / maxGain;
			effSum += eff;
			effSqSum += eff * eff;
			effTicks++;
		}

		if (turnBind)
		{
			turnBindTicks++;
		}
		if (absDYaw > AC_TURN_EPSILON)
		{
			if (absDYaw > AC_SPIN_THRESHOLD)
			{
				spinTicks++;
			}
			else
			{
				float residual = absDYaw - optDeltaYaw;
				yawResSqSum += residual * residual;
				yawResTicks++;
				if (!turnBind)
				{
					turnMags[turnTicks++] = absDYaw;
				}
			}
		}

		// Turn-bind ticks (constant cl_yawspeed) and yaw-dead mouse ticks
		// (+strafe / m_yaw 0) stay out of the k samples
		int mouseX = acPose(t).mouseX;
		if (mouseX != 0)
		{
			mouseTicks++;
			if (!turnBind)
			{
				if (absDYaw <= AC_TURN_EPSILON)
				{
					yawlessMouseTicks++;
				}
				else
				{
					// Positive mouse x moves the view right = negative yaw
					ratios[kSamples] = -dYaw / float(mouseX);
					kMouse[kSamples] = float(mouseX);
					kDYaw[kSamples] = dYaw;
					kSamples++;
				}
			}
		}
		else if (absDYaw > 0.01 && !turnBind)
		{
			injectedTicks++;
		}

		float dPitch = CalcDeltaAngle(acPose(t - 1).orientation[0], acPose(t).orientation[0]);
		int mouseY = acPose(t).mouseY;
		if (mouseX != 0 && mouseY == 0)
		{
			mouseYDeadTicks++;
		}
		if (mouseY != 0)
		{
			if (FloatAbs(dPitch) <= AC_PITCH_EPSILON)
			{
				pitchFrozenTicks++;
			}
			else
			{
				pitchRatios[pitchSamples++] = dPitch / float(mouseY);
			}
		}

		cmdGapTicks += acPose(t).cmdGap;

		// Positive sidemove is +moveright.
		// Key transitions skew sidemove vs buttons by one tick, so a condition must hold two ticks to count.
		float side = acPose(t).sidemove;
		bool moveLeft = (buttons & IN_MOVELEFT) != 0;
		bool moveRight = (buttons & IN_MOVERIGHT) != 0;
		int sideCond = 0;
		if (FloatAbs(side) > 0.01 && !moveLeft && !moveRight)
		{
			sideCond = 1;
		}
		else if (FloatAbs(side) <= 0.01 && (moveLeft || moveRight))
		{
			sideCond = 2;
		}
		else if (side > 0.01 && moveLeft && !moveRight
			 || side < -0.01 && moveRight && !moveLeft)
		{
			sideCond = 3;
		}
		if (sideCond != 0 && sideCond == prevSideCond)
		{
			if (sideCond == 1)
			{
				sidemoveGhostTicks++;
			}
			else if (sideCond == 2)
			{
				sidemoveNullTicks++;
			}
			else
			{
				sidemoveMismatchTicks++;
			}
		}
		prevSideCond = sideCond;

		if (FloatAbs(acPose(t).orientation[2]) > 0.001)
		{
			rollTicks++;
		}
	}

	int usableTicks = lastTick - firstTick + 1;
	tracker.jump.acUsableTicks = usableTicks;
	tracker.jump.acTurnBindTicks = turnBindTicks;
	tracker.jump.acMouseTicks = mouseTicks;
	tracker.jump.acInjectedTicks = injectedTicks;
	tracker.jump.acYawlessMouseTicks = yawlessMouseTicks;
	tracker.jump.acMouseYDeadTicks = mouseYDeadTicks;
	tracker.jump.acPitchFrozenTicks = pitchFrozenTicks;
	tracker.jump.acCmdGapTicks = cmdGapTicks;
	tracker.jump.acSidemoveGhostTicks = sidemoveGhostTicks;
	tracker.jump.acSidemoveNullTicks = sidemoveNullTicks;
	tracker.jump.acSidemoveMismatchTicks = sidemoveMismatchTicks;
	tracker.jump.acRollTicks = rollTicks;

	// Positive mouse y = positive pitch, no sign flip. Negative is legit (inverted m_pitch).
	tracker.jump.acPitchSamples = pitchSamples;
	tracker.jump.acKPitchFit = 0.0;
	if (pitchSamples >= AC_MIN_MOUSE_SAMPLES)
	{
		SortFloats(pitchRatios, pitchSamples, Sort_Ascending);
		if (pitchSamples % 2 == 1)
		{
			tracker.jump.acKPitchFit = pitchRatios[pitchSamples / 2];
		}
		else
		{
			tracker.jump.acKPitchFit = (pitchRatios[pitchSamples / 2 - 1] + pitchRatios[pitchSamples / 2]) / 2.0;
		}
	}

	if (effTicks > 0)
	{
		float effMean = effSum / float(effTicks);
		tracker.jump.acEffMean = effMean;
		tracker.jump.acEffStd = SquareRoot(FloatMax(0.0, effSqSum / float(effTicks) - effMean * effMean));
	}
	if (yawResTicks > 0)
	{
		tracker.jump.acYawResidualRms = SquareRoot(yawResSqSum / float(yawResTicks));
	}

	// Robust (median) mouse sensitivity fit, then the residual around it
	if (kSamples >= AC_MIN_MOUSE_SAMPLES)
	{
		SortFloats(ratios, kSamples, Sort_Ascending);
		float kFit;
		if (kSamples % 2 == 1)
		{
			kFit = ratios[kSamples / 2];
		}
		else
		{
			kFit = (ratios[kSamples / 2 - 1] + ratios[kSamples / 2]) / 2.0;
		}
		float kResSqSum;
		for (int i = 0; i < kSamples; i++)
		{
			float r = kDYaw[i] + kFit * kMouse[i];
			kResSqSum += r * r;
		}
		tracker.jump.acKFit = kFit;
		tracker.jump.acKResidualRms = SquareRoot(kResSqSum / float(kSamples));
	}

	// Yaw ceiling saturation over turning ticks, turn binds excluded.
	// Peak -1.0 = too little turning, save_ac skips the ceiling/peak columns.
	float peak;
	for (int i = 0; i < turnTicks; i++)
	{
		if (turnMags[i] > peak)
		{
			peak = turnMags[i];
		}
	}
	int ceilingTicks;
	if (turnTicks >= AC_MIN_CEILING_TURN_TICKS && peak >= AC_MIN_CEILING_PEAK)
	{
		for (int i = 0; i < turnTicks; i++)
		{
			if (turnMags[i] >= 0.98 * peak)
			{
				ceilingTicks++;
			}
		}
	}
	else
	{
		peak = -1.0;
	}
	tracker.jump.acPeakDeltaYaw = peak;
	tracker.jump.acTurnTicks = turnTicks;
	tracker.jump.acCeilingTicks = ceilingTicks;
	tracker.jump.acSpinTicks = spinTicks;

	AcComputeStrafeStats(tracker);
	AcComputeFlipLag(tracker, firstTick, lastTick);
}

static int AcIntAbs(int value)
{
	return value < 0 ? -value : value;
}

// Strafe duration regularity. UpdateStrafes() stores strafe k at index k (index 0 collects pre-strafe dead air).
// First and last strafe are cut off by takeoff/landing, so they are excluded when there are enough strafes.
static void AcComputeStrafeStats(JumpTracker tracker)
{
	int strafeCount = tracker.jump.strafes;
	if (strafeCount > JS_MAX_TRACKED_STRAFES - 1)
	{
		strafeCount = JS_MAX_TRACKED_STRAFES - 1;
	}

	int from = 1;
	int to = strafeCount;
	if (strafeCount >= 3)
	{
		from = 2;
		to = strafeCount - 1;
	}
	int n = to - from + 1;
	if (n <= 0)
	{
		return;
	}

	float sum, sqSum;
	for (int i = from; i <= to; i++)
	{
		float len = float(tracker.jump.strafes_ticks[i]);
		sum += len;
		sqSum += len * len;
	}
	float mean = sum / float(n);
	tracker.jump.acStrafeLenMean = mean;
	tracker.jump.acStrafeLenStd = SquareRoot(FloatMax(0.0, sqSum / float(n) - mean * mean));
}

// Lag between each turn-direction flip and the matching A/D key press.
static void AcComputeFlipLag(JumpTracker tracker, int firstTick, int lastTick)
{
	int jumper = tracker.jumper;
	int strafeCount = tracker.jump.strafes;
	if (strafeCount > JS_MAX_TRACKED_STRAFES - 1)
	{
		strafeCount = JS_MAX_TRACKED_STRAFES - 1;
	}

	float lagSum, lagSqSum, sharpnessSum;
	int matched, zeroLag, impulses, accelSamples;

	// Boundary tick of strafe k = first tick after the ticks of everything before it. Skip strafe 1.
	int boundary = 1 + tracker.jump.strafes_ticks[0] + tracker.jump.strafes_ticks[1];
	for (int k = 2; k <= strafeCount; k++)
	{
		int start = boundary;
		boundary += tracker.jump.strafes_ticks[k];
		if (start < firstTick || start > lastTick)
		{
			continue;
		}

		// Turn direction on the boundary tick decides which key to expect.
		// Positive deltaYaw = turning left = expect a +moveleft press.
		float dYaw = CalcDeltaAngle(acPose(start - 1).orientation[1], acPose(start).orientation[1]);
		int key = dYaw > 0.0 ? IN_MOVELEFT : IN_MOVERIGHT;

		// Yaw-accel shape at the flip: accel(t) = dYaw(t) - dYaw(t-1).
		// AcYawAccel(start - 1) reaches back to pose start - 3.
		if (start - 3 >= firstTick - 1 && start + 1 <= lastTick)
		{
			float aB = FloatAbs(AcYawAccel(jumper, start));
			float aPrev = FloatAbs(AcYawAccel(jumper, start - 1));
			float aNext = FloatAbs(AcYawAccel(jumper, start + 1));
			accelSamples++;
			sharpnessSum += aB / ((aPrev + aNext) / 2.0 + AC_SHARPNESS_FLOOR);
			if (aB > AC_IMPULSE_SPIKE && aPrev < AC_IMPULSE_SETTLE && aNext < AC_IMPULSE_SETTLE)
			{
				impulses++;
			}
		}

		int best = AC_FLIP_SEARCH + 1;
		bool found = false;
		for (int off = -AC_FLIP_SEARCH; off <= AC_FLIP_SEARCH; off++)
		{
			int t = start + off;
			if (t - 1 < firstTick - 1 || t > lastTick)
			{
				continue;
			}
			if ((acPose(t).buttons & key) && !(acPose(t - 1).buttons & key))
			{
				if (!found || AcIntAbs(off) < AcIntAbs(best))
				{
					best = off;
					found = true;
				}
			}
		}

		if (found)
		{
			matched++;
			lagSum += float(best);
			lagSqSum += float(best) * float(best);
			if (best == 0)
			{
				zeroLag++;
			}
		}
	}

	tracker.jump.acFlipMatched = matched;
	tracker.jump.acFlipZeroLag = zeroLag;
	if (matched > 0)
	{
		float mean = lagSum / float(matched);
		tracker.jump.acFlipLagMean = mean;
		tracker.jump.acFlipLagStd = SquareRoot(FloatMax(0.0, lagSqSum / float(matched) - mean * mean));
	}

	tracker.jump.acFlipImpulses = impulses;
	tracker.jump.acFlipAccelSamples = accelSamples;
	if (accelSamples > 0)
	{
		tracker.jump.acFlipSharpness = sharpnessSum / float(accelSamples);
	}
}

// Signed yaw acceleration at tick t, deg/tick^2. Needs poses t-2 .. t.
static float AcYawAccel(int jumper, int t)
{
	float dYawCur = CalcDeltaAngle(acPose(t - 1).orientation[1], acPose(t).orientation[1]);
	float dYawPrev = CalcDeltaAngle(acPose(t - 2).orientation[1], acPose(t - 1).orientation[1]);
	return dYawCur - dYawPrev;
}
