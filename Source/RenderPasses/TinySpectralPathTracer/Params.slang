#pragma once
#include "Utils/Math/MathConstants.slangh"

static const bool kUseEnvLight = USE_ENV_LIGHTS;
static const uint kMaxBounces = MAX_BOUNCES;
static const bool kUseEmissiveLights = USE_EMISSIVE_LIGHTS;
static const bool kUseAnalyticLights = USE_ANALYTIC_LIGHTS;
static const bool kUSERISDirectIllumination = USE_RIS_DI;
static const uint kRISSamples = RIS_SAMPLES;
static const bool kDoMIS = USE_MIS;
static const bool kHWSSDoMIS = true;
static const bool kForceFullyCoherent = false;
// Area on emissive geometry from which we source beams
static const float kSourcingAreaFromEmissiveGeometry = 1.0f;
// Max diffusivity of sourced beams
static const float kSourcingMaxBeamOmega = 0.025f;
static const float kShadowRayTMin = 1e-4;
static const float kRayTMax = FLT_MAX;
