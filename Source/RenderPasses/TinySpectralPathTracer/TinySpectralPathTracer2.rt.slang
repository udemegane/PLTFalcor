#pragma once

#include "Scene/SceneDefines.slangh"
#include "Utils/Math/MathConstants.slangh"

import Scene.Raytracing;
import Scene.Intersection;
import Scene.ShadingData;
import Scene.Scene;
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
import Rendering.Lights.EmissiveLightSampler;
import Rendering.Materials.BxDF;
import Rendering.Materials.PLT.Mueller;
// import Rendering.Materials.PLT;
import Utils.Color.ColorHelpers;

import Rendering.PLT;
import LightSampling;
import Path;
import Params;
import CB;
import Reservoir;
import RISPathTracer;

// Inputs
Texture2D<PackedHitInfo> gVBuffer;
Texture2D<float4> gViewW; // Optional

// Outputs
RWTexture2D<float4> gOutputColor;

RWStructuredBuffer<PathSurface> gPathData;

#define is_valid(name) (is_valid_##name != 0)

struct ShadowRayData
{
    bool visible;
}

bool traceShadowRay(float3 origin, float3 dir, float distance)
{
    RayDesc ray;
    ray.Origin = origin;
    ray.Direction = dir;
    ray.TMin = 0.f;
    ray.TMax = distance;
    ShadowRayData rayData;
    rayData.visible = false;
    TraceRay(
        gScene.rtAccel, RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH, 0xff /* instanceInclusionMask */, 1 /* hitIdx */, rayTypeCount,
        1 /* missIdx */, ray, rayData
    );
    return rayData.visible;
}

enum class PropagationDirection
{
    ToLight,
    ToCamera,
};

float RR(const float rrVal, const float rrE, const float sample)
{
    const float p = pow(rrVal, rrE);

    return sample < p ? .0f : 1.f - p;
}

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

float MISWeight(float p0, float p1, float n0 = 1.f, float n1 = 1.f)
{
    // Balance heuristic
    float q0 = n0 * p0;
    float q1 = n1 * p1;
    return q0 / (q0 + q1);
}

float HWSSWeight(const PLTBeam beam)
{
    if (kHWSSDoMIS)
    {
        // MIS spectral contributions
        const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
        return sum > FLT_EPSILON ? beam.spectralPDFs[0] / sum : .0f;
    }
    else
        return 1.f / float(beam.hwss_comps);
}

void forwardHWSSMis(const IMaterialInstance bsdf, const ShadingData sd, const float3 wo, const uint sampledBsdfLobe, inout PLTBeam beam)
{
    if (kHWSSDoMIS)
    {
        const hwss_t pdfs = bsdf.lambdaPdf(sd, wo, sampledBsdfLobe, beam, beam.wavelengths);
        beam.spectralPDFs *= pdfs;
    }
}

// BSDF sampling
bool pltSampleBSDF<
    S : ISampleGenerator>(const ShadingData sd, const IMaterialInstance bsdf, inout S sg, out BSDFSample bsdfSample, const float wavelength)
{
    const bool valid = bsdf.sample(sd, sg, bsdfSample, wavelength);
    if (!valid || bsdfSample.pdf == .0f)
        return false;
    return true;
}
ShadingData loadShadingData(const HitInfo hit, const float3 dir, const ITextureSampler lod, const PropagationDirection lightDir)
{
    const float3 toPrevSurface = lightDir == PropagationDirection::ToLight ? -dir : dir;
    VertexData v = {};
    uint materialID = {};

#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_TRIANGLE_MESH)
    if (hit.getType() == HitType::Triangle)
    {
        const TriangleHit triangleHit = hit.getTriangleHit();
        v = gScene.getVertexData(triangleHit);
        materialID = gScene.getMaterialID(triangleHit.instanceID);
    }
#endif
#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_DISPLACED_TRIANGLE_MESH)
    if (hit.getType() == HitType::DisplacedTriangle)
    {
        const DisplacedTriangleHit displacedTriangleHit = hit.getDisplacedTriangleHit();
        v = gScene.getVertexData(displacedTriangleHit, toPrevSurface);
        materialID = gScene.getMaterialID(displacedTriangleHit.instanceID);
    }
#endif
#if SCENE_HAS_GEOMETRY_TYPE(GEOMETRY_TYPE_CURVE)
    if (hit.getType() == HitType::Curve)
    {
        const CurveHit curveHit = hit.getCurveHit();
        v = gScene.getVertexDataFromCurve(curveHit);
        materialID = gScene.getMaterialID(curveHit.instanceID);
    }
#endif

    ShadingData sd = gScene.materials.prepareShadingData(v, materialID, toPrevSurface, lod);

    return sd;
}

bool evalEmissive<S : ISampleGenerator>(
    inout float3 L,
    inout S sg,
    const float wavelength,
    const float lastNonDeltaPdf,
    const ShadingData sd,
    const BSDFProperties bsdfProp,
    const TriangleHit triangleHit
)
{
    // TODO:
    // if (kUseEmissiveLights && bsdfProp.isEmissive)
    // {
    //     TriangleLightHit hit;
    //     hit.triangleIndex = gScene.lightCollection.getTriangleIndex(triangleHit.instanceID, triangleHit.primitiveIndex);
    //     hit.posW = sd.posW;
    //     hit.normalW = sd.frontFacing ? sd.faceN : -sd.faceN;
    //     const float lightPdf =
    //         getEmissiveSelectionProbability() * emissiveSampler.evalPdf(solveData.pathOrigin, solveData.pathNormal, false, hit);
    //     const float misWeight = MISWeight(lastNonDeltaPdf, lightPdf);

    //     // Emitted intensity
    //     hwss_t sampledWavelengths;
    //     hwss_t Le = gScene.sampleSpectrum(bsdfProp.emissionSpectralId, wavelength, sg, importanceSampleSpectrum, sampledWavelengths);
    //     Le *= misWeight * SpectrumUtils.rgbToSpectrum(bsdfProp.emissionRGB, sampledWavelengths);
    // }
    return true;
}

bool NEE<S : ISampleGenerator>(
    inout float3 L,
    inout S sg,
    inout float hwssWeight,
    float wavelength,
    const int bounceIdx,
    // const float3 wi,
    // const uint2 pixel,
    // const TriangleHit triangleHit,
    const ShadingData sd,
    const VertexData V,
    const uint matID,
    const IMaterialInstance bsdf,
    const BSDFProperties bsdfProp,
    const float3 prevOrigin
)
{
    const uint lobes = bsdf.getLobes(sd);
    // MNEE and MSはしない

    const bool sampleReflection = (lobes & (uint)LobeType::NonDeltaReflection) != 0;
    const bool sampleTransmission = (lobes & (uint)LobeType::NonDeltaTransmission) != 0;
    if (!sampleReflection && !sampleTransmission)
        return false; // If bsdf has delta lobes.

    if (!kUSERISDirectIllumination)
    {
        // sample light
        LightSample ls;
        const bool importanceSampleSpectrum = true; // TODO: move to params
        const bool valid = generateLightSample(sd, sampleReflection, sampleTransmission, sg, wavelength, importanceSampleSpectrum, ls);
        if (!valid || !any(ls.beam.L > 0.f))
            return false;
        // Update HWSS component
        // 代表波長以外を捨てる時
        // if (!mHWSSDoMIS &&)
        //     ls.beam.collapseToHeroWavelengthOnly();

        bool doMis = kDoMIS && ls.lightType != (uint)SampledLightType::Analytic;

        // Check visibility
        // V(wo)
        let visRayDesc = ls.getVisibilityRay();
        if (!traceShadowRay(visRayDesc.Origin, visRayDesc.Direction, visRayDesc.TMax))
            return true;

        if (doMis)
        {
            const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, bsdfPdf));
        }

        // eval lighting
        // fs(wi,wo)*dot(wo,n)
        // sd.V = ls.dir;

        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData forwardSd = gScene.materials.prepareShadingData(V, matID, -ls.beam.r /*-(light to surface)*/, lod);
        ls.beam.propagate(forwardSd.posW);
        // ここで光源からカメラまで全部evalしないとスループットがおかしくなる
        // MAX_BOUNSEサイズの配列に全部格納する力技でどうにかなりそうな気はする
        bsdf.eval(forwardSd, sd.V, (uint)LobeType::NonDelta, ls.beam);
        forwardHWSSMis(bsdf, forwardSd, sd.V, (uint)LobeType::NonDelta, ls.beam);
        ls.beam.propagate(prevOrigin);

        { // ヤバいやつ
            const float k = M_2PI / (1e-3f * ls.beam.wavelengths.x);
            const float polarizationIntensity = gScene.camera.data.polarizer;
            const float polarizationTheta = gScene.camera.data.polarizerTheta;
            if (polarizationIntensity > .0f)
            {
                // Rotate to camera frame
                const float3 cameraW = normalize(gScene.camera.data.cameraW);
                const float3 cameraU = normalize(gScene.camera.data.cameraU);
                ls.beam.rotateFrame(cameraU, -cameraW);

                // Polarize
                const float4x4 P = (1.f - polarizationIntensity) * ident4() + polarizationIntensity * MuellerPolarizer(polarizationTheta);
                for (int j = 0; j < ls.beam.hwss_comps; ++j)
                    ls.beam.setSP(j, mul(P, ls.beam.getSP(j)));
            }
        }
        hwssWeight = HWSSWeight(ls.beam);

        // Le(x_D<->x_D-1)
        L = max(float3(.0f), SpectrumUtils.spectrumToRgb(ls.beam.L, ls.beam.wavelengths, ls.beam.hwss_comps));
        return true;
    }

    // [unroll]
    Reservoir r = Reservoir();
    for (int i = 0; i < kRISSamples; i++)
    {
        // wavelength = SpectrumSampler.sampleOne(sampleNext1D(sg));
        // sample light
        LightSample ls;
        const bool importanceSampleSpectrum = true; // TODO: move to params
        const S tmpSg = sg;
        const bool valid = generateLightSample(sd, sampleReflection, sampleTransmission, sg, wavelength, importanceSampleSpectrum, ls);
        if (!valid || !any(ls.beam.L > 0.f))
            continue;

        // Update HWSS component
        // 代表波長以外を捨てる時
        // if (!mHWSSDoMIS &&)
        //     ls.beam.collapseToHeroWavelengthOnly();

        bool doMis = kDoMIS && ls.lightType != (uint)SampledLightType::Analytic;

        if (doMis)
        {
            const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, bsdfPdf));
        }

        // eval lighting
        // fs(wi,wo)*dot(wo,n)
        // sd.V = ls.dir;

        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData forwardSd = gScene.materials.prepareShadingData(V, matID, -ls.beam.r, lod);
        // const ShadingData forwardSd =
        ls.beam.propagate(forwardSd.posW);
        bsdf.eval(forwardSd, sd.V, (uint)LobeType::NonDelta, ls.beam);
        forwardHWSSMis(bsdf, forwardSd, sd.V, (uint)LobeType::NonDelta, ls.beam);

        // 元の実装だとカメラに到達するビームに対して謎の偏光処理をしている
        if (bounceIdx == 0)
        { // ヤバいやつ
            const float k = M_2PI / (1e-3f * ls.beam.wavelengths.x);
            ls.beam.propagate(gScene.camera.data.posW);
            const float polarizationIntensity = gScene.camera.data.polarizer;
            const float polarizationTheta = gScene.camera.data.polarizerTheta;
            if (polarizationIntensity > .0f)
            {
                // Rotate to camera frame
                const float3 cameraW = normalize(gScene.camera.data.cameraW);
                const float3 cameraU = normalize(gScene.camera.data.cameraU);
                ls.beam.rotateFrame(cameraU, -cameraW);

                // Polarize
                const float4x4 P = (1.f - polarizationIntensity) * ident4() + polarizationIntensity * MuellerPolarizer(polarizationTheta);
                for (int j = 0; j < ls.beam.hwss_comps; ++j)
                    ls.beam.setSP(j, mul(P, ls.beam.getSP(j)));
            }
        }
        // hwssWeight = HWSSWeight(ls.beam);

        // Le(x_D<->x_D-1)
        float3 l = max(float3(.0f), SpectrumUtils.spectrumToRgb(ls.beam.L, ls.beam.wavelengths, ls.beam.hwss_comps));
        float p_hat = luminance(l);
        float m_i = 1.0f / kRISSamples;
        float w_i = m_i * p_hat * (1.0f / ls.pdf /*resampling mis weight*/);
        r.update(ls, w_i, p_hat, sampleNext1D(sg));
    }

    bool doMis = kDoMIS && r.s.lightType != (uint)SampledLightType::Analytic;

    // Check visibility
    // V(wo)
    let visRayDesc = r.s.getVisibilityRay();
    if (!traceShadowRay(visRayDesc.Origin, visRayDesc.Direction, visRayDesc.TMax))
        return true;

    hwssWeight = HWSSWeight(r.s.beam);
    // Le(x_D<->x_D-1)
    r.s.beam.scale(r.evalUCW() * r.s.pdf);
    L = max(float3(.0f), SpectrumUtils.spectrumToRgb(r.s.beam.L, r.s.beam.wavelengths, r.s.beam.hwss_comps));
    // const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
    // L = ls.beam.L[0];
    return true;
}

void onHit(inout Path path, const HitInfo hit)
{
    let lod = ExplicitLodTextureSampler(0.f);
    const ShadingData sd = loadShadingData(hit, path.dir, lod, PropagationDirection::ToLight);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);

    // BSDF Sampling
    BSDFSample bsdfSample;
    const bool sampleValid = pltSampleBSDF(sd, bsdf, path.sg, bsdfSample, path.wavelength);
    // if (!sampleValid)
    // {
    //     path.terminated = true;
    // }

    {                                               // Emissibe Material Contribution
        const bool importanceSampleSpectrum = true; // TODO:
                                                    // float3 Le = float3(0.f);
                                                    // evalEmissive(Le, path.sg); TODO:
        hwss_t sampledWavelengths;
        hwss_t Le =
            gScene.sampleSpectrum(bsdfProp.emissionSpectralId, path.wavelength, path.sg, importanceSampleSpectrum, sampledWavelengths);
        Le *= SpectrumUtils.rgbToSpectrum(bsdfProp.emissionRGB, sampledWavelengths);
    }
    if (path.length >= kMaxBounces)
    {
        path.terminated = true;
        return;
    }

    { // NEE Contribution
        float3 L = float3(0.f);
        float hwssWeight = 1.f;
        const TriangleHit triangleHit = hit.getTriangleHit();
        // v = ;
        // materialID = ;
        NEE(L, path.sg, hwssWeight, path.wavelength, path.length, sd, gScene.getVertexData(triangleHit),
            gScene.getMaterialID(triangleHit.instanceID), bsdf, bsdfProp, path.origin);
        const float contrib = hwssWeight * path.weight / (path.pdf * path.thp_mod);
        path.radiance += max(contrib * L, 0.0f);
    }
    { // PRR //update path
        // BSDFSample bsdfSample;
        const float prr = path.length == 0 ? 1.0f : 0.9f;
        const float rcp_thp = RR(1.f - path.weight, 2.f, sampleNext1D(path.sg));

        // const bool sampleValid = pltSampleBSDF(sd, bsdf, path.sg, bsdfSample, path.wavelength);
        // if (rcp_thp != 0.0f)
        if (rcp_thp != 0.0f)
        {
            const bool isDelta = bsdfSample.isLobe(LobeType::Delta);
            path.dir = bsdfSample.wo;
            path.origin = sd.computeNewRayOrigin();
            // const ShadingData forwardSd = loadShadingData(hit, path.origin, -path.dir, lod);
            /*
            わかったこととして、スループットのbsdf項を光源方向からbeamを育てないと正しい値にならなさそうな感じ
            weightはbackward-weightらしいので、逆向き。
            */
            path.weight *= bsdfSample.weight;
            path.pdf *= bsdfSample.pdf;
            path.thp_mod *= rcp_thp;
            //
            path.lastNonDeltaPdf = !isDelta ? bsdfSample.pdf : path.lastNonDeltaPdf;
        }
        else
        {
            path.terminated = true;
            return;
        }
    }
    path.length++;
}

void onMiss(inout Path path)
{
    path.terminated = true;
    {
        float3 Le = gScene.envMap.eval(WorldRayDirection());
        // path.radiance += path.thp * Le;
    }
}

float3 tracePath(const in uint2 pixel, const in uint2 frameDim)
{
    const float3 primaryRayOrigin = gScene.camera.getPosition();
    const float3 primaryRayDir = getPrimaryRayDir(pixel, frameDim, gScene.camera);
    const HitInfo hit = HitInfo(gVBuffer[pixel]);
    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);
    const float wl = SpectrumSampler.sampleOne(sampleNext1D(sg)); // use RIS instead of random sampling?
    Path path = Path(sg, primaryRayOrigin, primaryRayDir, wl);
    float3 oc = float3(0.0f);
    bool useVBuffer = false;
    if (useVBuffer)
    {
        if (hit.isValid())
        {
            // DI
            {
                onHit(path, hit);
            }
            // GI
            if (!path.terminated)
            {
                ;
            }
        }
        else
        {
            onMiss(path);
        }
    }
    else
    {
        for (; path.length < kMaxBounces && !path.terminated;)
        {
            RayDesc ray;
            ray.Origin = path.origin;
            ray.Direction = path.dir;
            ray.TMin = 0.f;
            ray.TMax = kRayTMax;
            uint rayFlags = 0;
            TraceRay(gScene.rtAccel, rayFlags, 0xff, 0, rayTypeCount, 0, ray, path);
            // oc += path.radiance;
        }
    }

    return path.radiance;
}

// Miss Shader
[shader("miss")]
void scatterMiss(inout Path path)
{
    onMiss(path);
}
[shader("miss")]
void shadowMiss(inout ShadowRayData rayData)
{
    rayData.visible = true;
}

// Handle hit of Basic Trinagle
[shader("closesthit")]
void scatterTriangleMeshClosestHit(inout Path path, BuiltInTriangleIntersectionAttributes attribs)
{
    // Shading data
    TriangleHit triangleHit;
    triangleHit.instanceID = getGeometryInstanceID();
    triangleHit.primitiveIndex = PrimitiveIndex();
    triangleHit.barycentrics = attribs.barycentrics;
    const PackedHitInfo hit = triangleHit.pack();
    onHit(path, HitInfo(hit));
}

[shader("anyhit")]
void scatterTriangleMeshAnyHit(inout Path path, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test for non-opaque geometry.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}
[shader("anyhit")]
void shadowTriangleMeshAnyHit(inout ShadowRayData rayData, BuiltInTriangleIntersectionAttributes attribs)
{
    // Alpha test for non-opaque geometry.
    GeometryInstanceID instanceID = getGeometryInstanceID();
    VertexData v = getVertexData(instanceID, PrimitiveIndex(), attribs);
    const uint materialID = gScene.getMaterialID(instanceID);
    if (gScene.materials.alphaTest(v, materialID, 0.f))
        IgnoreHit();
}

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

