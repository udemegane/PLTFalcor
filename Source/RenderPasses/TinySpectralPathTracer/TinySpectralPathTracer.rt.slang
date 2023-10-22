#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"

import Scene.Raytracing;
import Scene.Intersection;
import Scene.ShadingData;
import Scene.Scene;
import Utils.HWSS;
import Utils.HWSS;
import Utils.Math.MathHelpers;
import Utils.Sampling.SampleGenerator;
import Utils.Geometry.GeometryHelpers;
import Utils.Color.SpectrumSampler;
import Utils.Color.SpectrumUtils;
import Utils.Geometry.GeometryHelpers;
import Utils.Sampling.SampleGenerator;
import Rendering.Lights.LightHelpers;
import Rendering.Utils.LightsSamplingUtils;
import Rendering.Materials.BxDF;
import Rendering.Materials.PLT.Mueller;

cbuffer CB
{
    uint gFrameCount;
    uint2 gFrameDim;
}

// Inputs
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float4> gViewW; // Optional

// Outputs
RWTexture2D<float4> gOutputColor;

#define is_valid(name) (is_valid_##name != 0)
static const uint kMaxBounces = MAX_BOUNCES;

struct ShadowRayData
{
    bool visible;
}

struct DummyRayData
{
    float3 radiance;
    bool visible;
};

float3 getPrimaryRayDir(uint2 launchIndex, uint2 launchDim, const Camera camera)
{
    if (false)
    {
        // If we have the view vector bound as a buffer, just fetch it. No need to compute anything.
        return -gViewW[launchIndex].xyz;
    }
    else
    {
        // Compute the view vector. This must exactly match what the G-buffer pass is doing (jitter etc.).
        // Note that we do not take depth-of-field into account as it would require exactly matching the
        // sample generator between the passes, which is error prone. The host side will issue a warning instead.
        return camera.computeRayPinhole(launchIndex, launchDim).dir;
    }
}

float3 tracePath(const in uint2 pixel, const in uint2 frameDim)
{
    float3 outColor = float3(0.0f);
    const float3 primaryRayOrigin = gScene.camera.getPosition();
    const float3 primaryRayDir = getPrimaryRayDir(pixel, frameDim, gScene.camera);
    DummyRayData rayData;
    RayDesc ray;
    ray.Origin = primaryRayOrigin;
    ray.Direction = primaryRayDir;
    ray.TMin = 0.f;
    ray.TMax = FLT_MAX;
    uint rayFlags = 0;

    TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray, rayData);
    return rayData.radiance;
}

// Miss Shader
[shader("miss")]
void scatterMiss(inout DummyRayData rayData)
{
    rayData.radiance = float3(1.0f, 0.0f, 1.0f);
}
[shader("miss")]
void shadowMiss(inout ShadowRayData rayData)
{
    rayData.visible = true;
}

// Handle hit of Basic Trinagle
[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout DummyRayData rayData, BuiltInTriangleIntersectionAttributes attribs)
{
    rayData.radiance = float3(0.0f, 1.0f, 0.0f);
}
[shader("anyhit")]
void scatterTriangleMeshAnyHit(inout DummyRayData rayData, BuiltInTriangleIntersectionAttributes attribs)
{
    // rayData.radiance = float3(0.0f, 1.0f, 0.0f);
}
[shader("anyhit")]
void shadowTriangleMeshAnyHit(inout ShadowRayData rayData, BuiltInTriangleIntersectionAttributes attribs) {}

// Handle hit of Displacemented Triangle
[shader("closesthit")]
void scatterDisplacedTriangleMeshClosestHit() {}
[shader("intersection")]
void displacedTriangleMeshIntersection() {}

// Handle hit of Curve
[shader("closesthit")]
void scatterCurveMeshClosestHit() {}
[shader("intersection")]
void curveMeshIntersection() {}

// Handle hit of SDFGrid
[shader("closesthit")]
void scatterSdfGridMeshClosestHit() {}
[shader("intersection")]
void sdfGridMeshIntersection() {}

// Ray-generation
[shader("raygeneration")]
void rayGen()
{
    uint2 pixel = DispatchRaysIndex().xy;
    uint2 frameDim = DispatchRaysDimensions().xy;
    float3 finalColor = tracePath(pixel, frameDim);
    gOutputColor[pixel] = float4(finalColor, 1.0f);
}
