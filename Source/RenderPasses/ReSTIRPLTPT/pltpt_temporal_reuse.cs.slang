#pragma once

#include "pltpt_cs.slangh"
import LocalUtils;

RWStructuredBuffer<PackedReservoir> gPrevReservoirs;
RWStructuredBuffer<PackedReservoir> gCurrReservoirs;

StructuredBuffer<BounceData> bounceBuffer;
StructuredBuffer<BounceData> retracedBounceBuffer;
// Read a bounce

RWTexture2D<float4> gIndirectIllumination;

BounceData readBounce(int p, const uint2 pixel, const bool retraced = false)
{
    const uint idx = ((pixel.x % mTileSize) + (pixel.y % mTileSize) * mTileSize) * (mMaxBounces + 1) + p;
    // const uint idx = pixel.x + pixel.y * kOutputSize.x;
    if (retraced)
        return retracedBounceBuffer[idx];
    else
        return bounceBuffer[idx];
}

Reservoir readReservoir(const uint2 pixel, const bool prev = false)
{
    const uint idx = encodeMortonCode(pixel);
    // const uint idx = ((pixel.x % mTileSize) + (pixel.y % mTileSize) * mTileSize);
    // const uint idx = pixel.x + pixel.y * kOutputSize.x;
    if (!prev)
        return gCurrReservoirs[idx].unpack();
    else
        return gPrevReservoirs[idx].unpack();
}

void forwardHWSSMis(const IMaterialInstance bsdf, const ShadingData sd, const float3 wo, const uint sampledBsdfLobe, inout PLTBeam beam)
{
    if (mHWSSDoMIS)
    {
        const hwss_t pdfs = bsdf.lambdaPdf(sd, wo, sampledBsdfLobe, beam, beam.wavelengths);
        beam.spectralPDFs *= pdfs;
    }
}

void forwardUnwindStep(const TriangleHit triangleHit, const VertexData v, const float3 wo, const uint sampledBsdfLobe, inout PLTBeam beam)
{
    let lod = ExplicitLodTextureSampler(0.f);
    const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, -beam.r, lod);

    // Propagate
    beam.propagate(sd.posW);

    // BSDF
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    bsdf.eval(sd, wo, sampledBsdfLobe, beam);

    // Spectral MIS
    forwardHWSSMis(bsdf, sd, wo, sampledBsdfLobe, beam);
}
// Replay path and evaluate contributions
void forwardUnwind(const int bounceIdx, const uint2 pixel, inout PLTBeam beam)
{
    for (int p = bounceIdx - 1; p >= 0; --p)
    {
        const BounceData bounce = readBounce(p, pixel);

        const TriangleHit triangleHit = TriangleHit(bounce.hit);
        const VertexData v = gScene.getVertexData(triangleHit);

        const float3 wo = bounce.wi;

        forwardUnwindStep(triangleHit, v, wo, bounce.sampledBsdfLobe, beam);
    }
}
void manifoldForwardUnwind(const ManifoldSampleData result, const float3 origin, inout PLTBeam beam)
{
    for (int idx = result.hitCount - 1; idx >= 0; --idx)
    {
        const TriangleHit triangleHit = TriangleHit(result.hits[idx].hit);
        VertexData v = gScene.getVertexData(triangleHit);
        v.posW = result.hits[idx].posW;

        const float3 p2 = idx == 0 ? origin : result.hits[idx - 1].posW;
        const float3 wo = normalize(p2 - v.posW);

        forwardUnwindStep(triangleHit, v, wo, result.hits[idx].lobe, beam);
    }
}

// Measure beam at sensor
void measure(inout PLTSolve solveData, const int bounceIdx, float pathContribution, inout PLTBeam beam, bool isRetracing = false)
{
    if (!kUseDirectLights && bounceIdx <= 1)
        return;

    const float k = M_2PI / (1e-3f * beam.wavelengths.x);

#if DO_DEBUG_VIEW == 1
    // Write coherence debug values before propagation to camera
    writeDebugOutputCC2(DebugViewType::coherence_area, solveData, sqrt(beam.coherenceArea(k)) / 150.f);
    writeDebugOutputCC(DebugViewType::coherence_anisotropy, solveData, beam.coherenceAnisotropy(k));
#endif

    // Propagate to camera
    beam.propagate(gScene.camera.data.posW);

    // Camera polarizer
    const float polarizationIntensity = gScene.camera.data.polarizer;
    const float polarizationTheta = gScene.camera.data.polarizerTheta;
    if (polarizationIntensity > .0f)
    {
        // Rotate to camera frame
        const float3 cameraW = normalize(gScene.camera.data.cameraW);
        const float3 cameraU = normalize(gScene.camera.data.cameraU);
        beam.rotateFrame(cameraU, -cameraW);

        // Polarize
        const float4x4 P = (1.f - polarizationIntensity) * ident4() + polarizationIntensity * MuellerPolarizer(polarizationTheta);
        for (int j = 0; j < beam.hwss_comps; ++j)
            beam.setSP(j, mul(P, beam.getSP(j)));
    }

    // TODO: Camera/lens effects

    hwss_t hwss_mod = 1.0f;
    if (isRetracing)
    {
        // 多分これで合ってる
        // const float sum = dot(beam.L, hwss_t(1.f));
        // hwss_mod *= sum > FLT_EPSILON ? beam.L / sum : .0f;

        const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
        hwss_mod *= sum > FLT_EPSILON ? beam.spectralPDFs / sum : .0f;
    }
    else if (mHWSSDoMIS)
    {
        // MIS spectral contributions
        const float sum = dot(beam.spectralPDFs, hwss_t(1.f));
        hwss_mod *= sum > FLT_EPSILON ? beam.spectralPDFs / sum : .0f;
    }
    else
        hwss_mod *= 1.f / float(beam.hwss_comps);
    // TODO:
    beam.scale(isRetracing ? (solveData.initialReservoir.evalUCW()[0]) : pathContribution * hwss_mod);

    // 間違いなく色の何かがおかしい
    // リサンプリング計算の単位?は合っている気がする
    const hwss_t Li = beam.L;
    const float3 Lrgb =
        max(float3(.0f), SpectrumUtils.spectrumToRgb(Li, beam.wavelengths, beam.hwss_comps) /** * (isRetracing ? 1.0f : 1.0f) **/);

    if (all(isfinite(Lrgb)))
        solveData.Lrgb += Lrgb;

#if DO_DEBUG_VIEW == 1
    // Write debug views
    markDebug(solveData, bounceIdx, beam);
#endif
}

bool wasNEEAvailable(const int bounceIdx, const RayFlags pathFlags)
{
    return kDoNEE && bounceIdx > 0 &&
           (!pathFlags.lastBounceWasDelta || (kDoMSonNEE && pathFlags.MSCompatibleBounces <= kMNEEMaxMSOccluders && bounceIdx > 1));
}

float MISWeight(float p0, float p1, float n0 = 1.f, float n1 = 1.f)
{
    // Balance heuristic
    float q0 = n0 * p0;
    float q1 = n1 * p1;
    return q0 / (q0 + q1);
}

void evalNEEwithUCW(
    inout PLTSolve solveData,
    const int bounceIdx,
    const BounceData bounce,
    const uint2 pixel,
    const VertexData V,
    const uint materialID,
    const IMaterialInstance bsdf,
    inout PLTBeam beam,
    const bool NEEEvalCurrentVertex,
    const float UCW
)
{
    if (NEEEvalCurrentVertex)
    {
        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData forwardSd = gScene.materials.prepareShadingData(V, materialID, -beam.r, lod);

        // Propagate beam from source and evaluate non-delta BSDF interaction
        beam.propagate(forwardSd.posW);
        bsdf.eval(forwardSd, bounce.wi, (uint)LobeType::NonDelta, beam);

        // Spectral MIS
        forwardHWSSMis(bsdf, forwardSd, bounce.wi, (uint)LobeType::NonDelta, beam);
    }

    // Forward unwind beam
    forwardUnwind(bounceIdx, pixel, beam);
    measure(solveData, bounceIdx, UCW, beam, true);
}

void Retrace(
    inout PLTSolve solveData,
    const int bounceIdx,
    const BounceData bounce,
    const uint2 pixel,
    const TriangleHit triangleHit,
    const ShadingData sd,
    const VertexData V,
    const IMaterialInstance bsdf,
    const BSDFProperties bsdfProp
)
{
    const uint lobes = bsdf.getLobes(sd);

    const bool allowMSOnCurrentVertex =
        kDoMSonNEE && bounceIdx > 0 && !bounce.flags.lastBounceWasDelta && bsdfProp.canManifoldWalkReflective;
    // NEE on non-delta lobes, or manifold walk on a delta lobe
    const bool sampleReflection = (lobes & (uint)LobeType::NonDeltaReflection) != 0 || allowMSOnCurrentVertex;
    const bool sampleTransmission = (lobes & (uint)LobeType::NonDeltaTransmission) != 0;

    if (!sampleReflection && !sampleTransmission)
        return;

    // Sample a light.
    LightSample ls;
    const bool importanceSampleSpectrum = kImportanceSampleEmissiveSpectra;
    const bool valid = regenerateSample(solveData.initialReservoir.s, ls);
    if (!valid || !any(ls.beam.L > .0f))
        return;

    // Update HWSS component count of sourced beam
    if (!mHWSSDoMIS && bounce.flags.dispersiveDeltaSegment)
        ls.beam.collapseToHeroWavelengthOnly();

    // Do we do MIS?
    bool doMis = kDoMIS && ls.lightType != (uint)SampledLightType::Analytic;
    // Do we need to eval current vertex on forward unwind? (Manifold sampling might involve current vertex)
    bool evalCurrentVertex = true;

    // Check visibility, or do MNEE
    const int maxMSBounces = int(mMaxBounces) - bounceIdx;
    let visRayDesc = ls.getVisibilityRay();
    if (!kDoMSonNEE || maxMSBounces <= 0)
    {
        Ray ray = Ray(visRayDesc.Origin, visRayDesc.Direction, visRayDesc.TMin, visRayDesc.TMax);
        if (!traceVisibilityRay(ray))
            return;

        // MIS?
        if (doMis)
        {
            const float bsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, bsdfPdf));
        }
    }
    else
    {
        /** Manifold sampling on NEE
         */

        const float3 lightDir = -ls.beam.r;
        float MISBsdfPdf;

        ManifoldSampleData msresult = ManifoldSampleData(ls.beam.wavelengths.x);

        // Are we doing MS on this vertex (e.g., delta lobe) as well? (Never on initial bounce)
        const bool isReflection = dot(sd.N, lightDir) * dot(sd.N, sd.V) > .0f;
        const bool currentVertexMS = isReflection && allowMSOnCurrentVertex;

        if (currentVertexMS)
        {
            if (!manifoldSampleVertex(bounce.hit, triangleHit, sd, bsdf, lightDir, solveData.sg, msresult) ||
                (msresult.hits[0].lobe & (uint)LobeType::Reflection) == 0)
                return;
        }

        // Do MS
        const float3 origin = !currentVertexMS ? V.posW : solveData.pathOrigin;
        const bool mneeOk =
            manifoldNEESample(visRayDesc, origin, ls.beam.posW, lightDir, ls.beam.distant, maxMSBounces, solveData.sg, msresult);

#if DO_DEBUG_VIEW == 1
        // MNEE debug views
        writeDebugOutputCC(DebugViewType::mnee_iterations, solveData, msresult.iterations / float(kMNEEMaxIterations));
        if (msresult.hitCount > 0 && mneeOk)
            writeDebugOutput(
                DebugViewType::mnee_bounces, solveData,
                msresult.hitCount == 0   ? float3(.0f)
                : msresult.hitCount == 1 ? float3(0, 0.3, 1)
                                         : float3(1, 0, 0)
            );
#endif

        if (!mneeOk || msresult.pdf < 1e-6f)
            return;

        // If hitcount is 0, then this is a simple NEE, otherwise need to evaluate the found connections.
        if (msresult.hitCount > 0)
        {
            // If the MS path is dispersive, reduce to single-wavelength beam
            if (!mHWSSDoMIS && msresult.dispersive)
                ls.beam.collapseToHeroWavelengthOnly();
            if (!ls.beam.distant)
            {
                ls.dir = msresult.woLastHitToLight;
                // Rotate beam towards the new last interaction point
                ls.beam.r = -msresult.woLastHitToLight;
                ls.beam.t = perp_stark(ls.beam.r);
            }

            // MS pdf
            ls.beam.scale(1.f / msresult.pdf);
            // Evaluate MS path
            manifoldForwardUnwind(msresult, origin, ls.beam);

            // Special care when MS is done for this vertex
            if (currentVertexMS)
            {
                evalCurrentVertex = false;
                MISBsdfPdf = bounce.lastNonDeltaPdf;
            }
        }

        // MIS
        if (doMis)
        {
            // MIS BSDF pdf for MS that involves the current vertex was computed above
            if (msresult.hitCount == 0 || !currentVertexMS)
                MISBsdfPdf = bsdf.pdf(sd, ls.dir, ls.beam.wavelengths.x);
            ls.beam.scale(MISWeight(ls.pdf, MISBsdfPdf * msresult.pdf));
        }
    }

    // Finally, evaluate NEE contributions
    evalNEEwithUCW(solveData, bounceIdx, bounce, pixel, V, sd.materialID, bsdf, ls.beam, evalCurrentVertex, bounce.pathContribution);
}

float3 PathReuse(const uint2 pixel)
{
    SampleGenerator sg = SampleGenerator(pixel, gFrameCount);
    const Reservoir r = readReservoir(pixel);
    const int p = r.s.lastBounceIdx;
    const BounceData bounce = readBounce(p, pixel);

    PLTSolve solveData = PLTSolve(sg, sg, r.s.wavelength);
    {
        const BounceData prevBounce = readBounce(p - 1, pixel);
        // Process hit data
        const TriangleHit triangleHit = TriangleHit(prevBounce.hit);
        const VertexData v = gScene.getVertexData(triangleHit);
        const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
        let lod = ExplicitLodTextureSampler(0.f);
        const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, prevBounce.wi, lod);
        solveData.pathNormal = sd.N;
        solveData.pathOrigin = v.posW;
    }


    // Process hit data
    const TriangleHit triangleHit = TriangleHit(bounce.hit);
    const VertexData v = gScene.getVertexData(triangleHit);
    const uint materialID = gScene.getMaterialID(triangleHit.instanceID);
    let lod = ExplicitLodTextureSampler(0.f);

    const ShadingData sd = gScene.materials.prepareShadingData(v, materialID, bounce.wi, lod);
    let bsdf = gScene.materials.getMaterialInstance(sd, lod);
    const BSDFProperties bsdfProp = bsdf.getProperties(sd);
    Retrace(solveData, p, bounce, pixel, triangleHit, sd, v, bsdf, bsdfProp);
    // return r.s.posW;
    return solveData.Lrgb;
}

[numthreads(16, 16, 1)]
void main(
    uint3 groupId: SV_GroupID,
    uint3 groupThreadId: SV_GroupThreadID,
    uint3 dispatchThreadId: SV_DispatchThreadID,
    uint3 groupIndex: SV_GroupIndex
)
{
    uint2 pixel = dispatchThreadId.xy;
    if (any(pixel >= kOutputSize.xy))
        return;

    gIndirectIllumination[pixel] = float4(PathReuse(pixel), 1.0f);
    // gIndirectIllumination[pixel] = float4(0.0f ,1.0f, 0.f, 1.0f);
    // float a;

    // SampleGenerator sg = SampleGenerator(pixel, gFrameCount * gFrameCount);
    // gOutputColor[pixel] += gIndirectIllumination[pixel];

}
