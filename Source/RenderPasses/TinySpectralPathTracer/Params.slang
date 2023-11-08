#pragma once
#include "Utils/Math/MathConstants.slangh"

static const bool kUseEnvLight = true;
static const uint kMaxBounces = MAX_BOUNCES;
static const bool kUseEmissiveLights = true;
static const bool kUseAnalyticLights = true;
static const bool kDoMIS = true;
static const bool kHWSSDoMIS = true;
static const bool kForceFullyCoherent = false;
// Area on emissive geometry from which we source beams
static const float kSourcingAreaFromEmissiveGeometry = 1.0f;
// Max diffusivity of sourced beams
static const float kSourcingMaxBeamOmega = 0.025f;
static const float kShadowRayTMin = 1e-4;
static const float kRayTMax = FLT_MAX;
