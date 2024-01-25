/***************************************************************************
 # Copyright (c) 2023, udemegane All rights reserved.
 **************************************************************************/
#pragma once
#include "Utils/Math/MathConstants.slangh"
#include "Scene/SceneDefines.slangh"

__exported import Scene.HitInfo;
__exported import Scene.HitInfoType;
import Scene.RaytracingInline;
import Utils.Geometry.GeometryHelpers;
import Utils.Debug.PixelDebug;
import Rendering.Utils.PixelStats;

static const float kShadowRayTMin = 1e-4;
static const float kRayTMax = FLT_MAX;

float3 computeNewRayOrigin(const ShadingData sd, float3 rayDir)
{
    return computeRayOrigin(sd.posW, dot(sd.faceN, rayDir) >= .0f ? sd.faceN : -sd.faceN);
}

struct ShadowRayHit
{
    PackedHitInfo hitInfo;
    float dist;
    property isHit : bool
    {
        get
        {
            return dist > .0f;
        }
    }
};

/**
    \param[in] ray
    \param[out] hit
    \param[out] hitT
    \return True if ray get a hit.
*/

bool traceRayInline(const Ray ray, inout HitInfo hit, inout float hitT)
{
    logTraceRay(PixelStatsRayType::ClosestHit);
    SceneRayQuery<true> srq;
    return srq.traceRay(ray, hit, hitT, RAY_FLAG_NONE, 0xff);
}

/**
    \param[in] ray
    \return True if ray get a hit.
 */

bool traceVisibilityRay(const Ray ray)
{
    logTraceRay(PixelStatsRayType::Visibility);
    SceneRayQuery<true> srq;
    return srq.traceVisibilityRay(ray, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff);
}

ShadowRayHit shadowRay(float3 origin, float3 dir, float distMax, float distMin = kShadowRayTMin, uint rayIdx = 1)
{
    Ray ray = Ray(origin, dir, distMin, distMax);
    HitInfo hit;
    float hitT;
    traceRayInline(ray, hit, hitT);
    ShadowRayHit srh;
    srh.hitInfo = hit.data;
    srh.dist = hitT;
    return srh;
}

bool visibilityRay(float3 origin, float3 dir, float distMax, float distMin = kShadowRayTMin, uint rayIdx = 1)
{
    Ray ray = Ray(origin, dir, distMin, distMax);
    return traceVisibilityRay(ray);
}
