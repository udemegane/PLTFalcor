/***************************************************************************
 # Copyright (c) 2015-23, NVIDIA CORPORATION. All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without
 # modification, are permitted provided that the following conditions
 # are met:
 #  * Redistributions of source code must retain the above copyright
 #    notice, this list of conditions and the following disclaimer.
 #  * Redistributions in binary form must reproduce the above copyright
 #    notice, this list of conditions and the following disclaimer in the
 #    documentation and/or other materials provided with the distribution.
 #  * Neither the name of NVIDIA CORPORATION nor the names of its
 #    contributors may be used to endorse or promote products derived
 #    from this software without specific prior written permission.
 #
 # THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS "AS IS" AND ANY
 # EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 # IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 # PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 # CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 # EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 # PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 # PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 # OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 # (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 # OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 **************************************************************************/
#include "TinySpectralPathTracer.h"
// #include <memory>
// #include "Core/Program/ProgramVars.h"
// #include "Core/Program/RtBindingTable.h"
// #include "Core/Program/RtProgram.h"
#include "RenderGraph/RenderPassHelpers.h"
#include "RenderGraph/RenderPassStandardFlags.h"
#include "Rendering/Lights/EmissiveUniformSampler.h"

#define USE_PARAMETER_BLOCK 0

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, TinySpectralPathTracer>();
}

namespace
{
const uint32_t kMaxPayloadSizeBytes = 100u;
const uint32_t kMaxRecursionDepth = 2u;
const std::string kTracePassFileName = "RenderPasses/TinySpectralPathTracer/TinySpectralPathTracer.cs.slang";
// const std::string kTracePassRTFileName = "RenderPasses/TinySpectralPathTracer/TinySpectralPathTracer2.rt.slang";
const std::string kTracePassRTFileName = "RenderPasses/TinySpectralPathTracer/RISSpectralPathTracer.rt.slang";
// const std::string kTracePassRTFileName = "RenderPasses/TinySpectralPathTracer/TracePath.rt.slang";

const std::string kShaderModel = "6_5";

const ChannelList kInputChannels = {
    {"vbuffer", "gVBuffer", "Visibility buffer", false},
    {"viewW", "gViewW", "World space View Direction ", false},
};

const ChannelList kOutputChannels = {
    {"color", "gOutputColor", "OutputColor", false, ResourceFormat::RGBA32Float},
};

const std::string kMaxBounces = "maxBounces";

} // namespace

TinySpectralPathTracer::TracePass::TracePass(
    std::shared_ptr<Device> pDevice,
    const std::string& name,
    const std::string& path,
    const std::string& passDefine,
    const Scene::SharedPtr& pScene,
    const Program::DefineList& defines,
    const Program::TypeConformanceList& typeConformances
)
    : name(name), passDefine(passDefine)
{
    const auto& globalTypeConformances = pScene->getMaterialSystem()->getTypeConformances();

    auto desc = [&]()
    {
        RtProgram::Desc desc;
        desc.addShaderModules(pScene->getShaderModules());
        desc.addShaderLibrary(path);
        // desc.setShaderModel(kShaderModel);
        desc.setMaxPayloadSize(kMaxPayloadSizeBytes);
        desc.setMaxAttributeSize(pScene->getRaytracingMaxAttributeSize());
        desc.setMaxTraceRecursionDepth(kMaxRecursionDepth);
        return desc;
    }();
    pBindingTable = RtBindingTable::create(2, 2, pScene->getGeometryCount());
    pBindingTable->setRayGen(desc.addRayGen("rayGen", globalTypeConformances));
    pBindingTable->setMiss(0, desc.addMiss("scatterMiss"));
    pBindingTable->setMiss(1, desc.addMiss("shadowMiss"));

    if (pScene->hasGeometryType(Scene::GeometryType::TriangleMesh))
    {
        pBindingTable->setHitGroup(
            0, pScene->getGeometryIDs(Scene::GeometryType::TriangleMesh),
            desc.addHitGroup("scatterTriangleMeshClosestHit", "scatterTriangleMeshAnyHit")
        );
        pBindingTable->setHitGroup(
            1, pScene->getGeometryIDs(Scene::GeometryType::TriangleMesh), desc.addHitGroup("", "shadowTriangleMeshAnyHit")
        );
    }

    if (pScene->hasGeometryType(Scene::GeometryType::DisplacedTriangleMesh))
    {
        pBindingTable->setHitGroup(
            0, pScene->getGeometryIDs(Scene::GeometryType::DisplacedTriangleMesh),
            desc.addHitGroup("scatterDisplacedTriangleMeshClosestHit", "", "displacedTriangleMeshIntersection")
        );
        pBindingTable->setHitGroup(
            1, pScene->getGeometryIDs(Scene::GeometryType::DisplacedTriangleMesh),
            desc.addHitGroup("", "", "displacedTriangleMeshIntersection")
        );
    }

    if (pScene->hasGeometryType(Scene::GeometryType::Curve))
    {
        pBindingTable->setHitGroup(
            0, pScene->getGeometryIDs(Scene::GeometryType::Curve), desc.addHitGroup("scatterCurveClosestHit", "", "curveIntersection")
        );
        pBindingTable->setHitGroup(1, pScene->getGeometryIDs(Scene::GeometryType::Curve), desc.addHitGroup("", "", "curveIntersection"));
    }

    if (pScene->hasGeometryType(Scene::GeometryType::SDFGrid))
    {
        pBindingTable->setHitGroup(
            0, pScene->getGeometryIDs(Scene::GeometryType::SDFGrid), desc.addHitGroup("scatterSdfGridClosestHit", "", "sdfGridIntersection")
        );
        pBindingTable->setHitGroup(
            1, pScene->getGeometryIDs(Scene::GeometryType::SDFGrid), desc.addHitGroup("", "", "sdfGridIntersection")
        );
    }

    pProgram = RtProgram::create(pDevice, desc, defines);
}

void TinySpectralPathTracer::TracePass::prepareProgram(std::shared_ptr<Device> pDevice, const Program::DefineList& defines)
{
    FALCOR_ASSERT(pProgram != nullptr && pBindingTable != nullptr);
    pProgram->setDefines(defines);
    if (!passDefine.empty())
        pProgram->addDefine(passDefine);
    pVars = RtProgramVars::create(pDevice, pProgram, pBindingTable);
}

TinySpectralPathTracer::SharedPtr TinySpectralPathTracer::create(std::shared_ptr<Device> pDevice, const Dictionary& dict)
{
    SharedPtr pPass = SharedPtr(new TinySpectralPathTracer(std::move(pDevice)));
    pPass->parseDictionary(dict);
    return pPass;
}

void TinySpectralPathTracer::parseDictionary(const Dictionary& dict)
{
    for (const auto& [k, v] : dict)
    {
        if (k == kMaxBounces)
            mParams.maxBounces;
        else
            logError("Unknown field '{}' in TinySpectralPathTracer dictionary.", k);
    }
}

Dictionary TinySpectralPathTracer::getScriptingDictionary()
{
    Dictionary d;
    d[kMaxBounces] = mParams.maxBounces;
    return d;
}

RenderPassReflection TinySpectralPathTracer::reflect(const CompileData& compileData)
{
    // Define the required resources here
    RenderPassReflection reflector;
    addRenderPassInputs(reflector, kInputChannels);
    addRenderPassOutputs(reflector, kOutputChannels);
    return reflector;
}

Program::DefineList TinySpectralPathTracer::StaticParams::getDefines(const TinySpectralPathTracer& owner) const
{
    Program::DefineList defines;
    defines.add("MAX_BOUNCES", std::to_string(maxBounces));
    defines.add("USE_MIS", conbineBSDFandNEESampling ? "1" : "0");
    defines.add("USE_RIS_DI", useRISDI ? "1" : "0");
    defines.add("RIS_SAMPLES", std::to_string(RISSamples));
    defines.add("HWSS_SAMPLES", std::to_string(mHWSS));
    defines.add("USE_ANALYTIC_LIGHTS", useAnalyticLights ? "1" : "0");
    defines.add("USE_EMISSIVE_LIGHTS", useEmissiveLights ? "1" : "0");
    defines.add("USE_ENV_LIGHTS", useEnvLight ? "1" : "0");
    return defines;
}

void TinySpectralPathTracer::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene)
{
    mFrameCount = 0u;
    mpScene = pScene;
    mpTracePass = nullptr;
    mpRtPass = nullptr;
    mpEmissiveSampler = nullptr;
    mpEnvMapSampler = nullptr;
    mpSampleGenerator = SampleGenerator::create(mpDevice, SAMPLE_GENERATOR_TINY_UNIFORM);
    if (mpScene)
    {
        if (pScene->hasGeometryType(Scene::GeometryType::Custom))
        {
            logWarning("TinySpectralPathTracer does not support custom primitive type.");
        }
        mRecompile = true;
    }
}

void TinySpectralPathTracer::preparePathtracer() {}

void TinySpectralPathTracer::updatePrograms()
{
    // executed every frame
    FALCOR_ASSERT(mpScene);
    if (mRecompile == false)
        return;
    auto defines = [&]()
    {
        auto defines = mParams.getDefines(*this);
        FALCOR_ASSERT(mpSampleGenerator);
        defines.add(mpScene->getSceneDefines());
        defines.add(mpSampleGenerator->getDefines());
        // defines.add(mpScene->getTypeConformances());
        return defines;
    }();

    Program::Desc baseDesc = [&]()
    {
        Program::Desc d;
        d.addShaderLibrary(kTracePassFileName).csEntry("main").setShaderModel(kShaderModel);
        d.addShaderModules(mpScene->getShaderModules());
        d.addTypeConformances(mpScene->getTypeConformances());
        return d;
    }();
    if (!mpTracePass)
    {
        // baseDesc.addShaderModules(mpScene->getShaderModules());
        mpTracePass = ComputePass::create(mpDevice, baseDesc, defines, true);
    }
    if (!mpRtPass)
    {
        mpRtPass =
            std::make_unique<TracePass>(mpDevice, "TracePass", kTracePassRTFileName, "", mpScene, defines, mpScene->getTypeConformances());
        mpRtPass->pProgram->setTypeConformances(mpScene->getTypeConformances());
        mpRtPass->prepareProgram(mpDevice, defines);
    }
    mRecompile = false;
}

void TinySpectralPathTracer::execute(RenderContext* pRenderContext, const RenderData& renderData)
{
    // renderData holds the requested resources
    // auto& pTexture = renderData.getTexture("src");
    auto& dict = renderData.getDictionary();
    const uint2& targetDim = renderData.getDefaultTextureDims();
    if (mOptionsChanged)
    {
        auto flags = dict.getValue(kRenderPassRefreshFlags, RenderPassRefreshFlags::None);
        dict[Falcor::kRenderPassRefreshFlags] = flags | Falcor::RenderPassRefreshFlags::RenderOptionsChanged;
        mOptionsChanged = false;
    }

    // Wait for the scene to be loaded
    if (!mpScene)
    {
        const auto clear = [&](const auto& name)
        {
            Texture* pDst = renderData.getTexture(name).get();
            if (pDst)
                pRenderContext->clearTexture(pDst);
        };
        for (const auto& c : kInputChannels)
            clear(c.name);
        for (const auto& c : kOutputChannels)
            clear(c.name);
        return;
    }

    // don't support dynamic scene because of difficuluties of Resampling theory
    if (is_set(mpScene->getUpdates(), Scene::UpdateFlags::GeometryChanged))
    {
        throw RuntimeError("TinySpectralPathTracer does not support dynamic Object.");
    }

    // handle environment map
    if (mpScene->useEnvLight())
    {
        mParams.useEnvLight = true;
        if (!mpEnvMapSampler)
            mpEnvMapSampler = EnvMapSampler::create(this->mpDevice, mpScene->getEnvMap());
        FALCOR_ASSERT(mpEnvMapSampler);
    }
    else
    {
        mpEnvMapSampler = nullptr;
        mParams.useEnvLight = false;
    }

    // handle emissive lights
    if (mpScene->getRenderSettings().useEmissiveLights)
    {
        mpScene->getLightCollection(pRenderContext);
    }
    if (mpScene->useEmissiveLights())
    {
        mParams.useEmissiveLights = true;
        if (!mpEmissiveSampler)
            mpEmissiveSampler = EmissiveUniformSampler::create(pRenderContext, mpScene);
        FALCOR_ASSERT(mpEmissiveSampler);
        mpEmissiveSampler->update(pRenderContext);
    }
    else
    {
        mParams.useEmissiveLights = false;
        mpEmissiveSampler = nullptr;
    }
    // set defines

    if (mpScene->useAnalyticLights())
        mParams.useAnalyticLights = true;
    else
        mParams.useAnalyticLights = false;

    // update programs
    updatePrograms();
    FALCOR_ASSERT(mpTracePass);
    FALCOR_ASSERT(mpRtPass);

// // prepare pathtracer
#if USE_PARAMETER_BLOCK
    {
        if (!mpPathTracerBlock)
        {
            auto reflector = mpTracePass->getProgram()->getReflector()->getParameterBlock("gPathTracer");

            mpPathTracerBlock = ParameterBlock::create(mpDevice.get(), reflector);
            FALCOR_ASSERT(mpPathTracerBlock);
        }
    }
#endif

    ///////////////////////////////////////////////////////////////////////////////////////////////
    /* DEPRECATED */
    if (mParams.useInlineTracing)
    {
        mpTracePass->getProgram()->addDefines(mParams.getDefines(*this));
        mpTracePass->getProgram()->addDefines(getValidResourceDefines(kInputChannels, renderData));
        mpTracePass->getProgram()->addDefines(getValidResourceDefines(kOutputChannels, renderData));

        // preapre programVars

        auto var = mpTracePass->getRootVar();
        var["CB"]["gFrameCount"] = mFrameCount;
        var["CB"]["gFrameDim"] = targetDim;

        const auto& bind = [&](const ChannelDesc& desc)
        {
            if (!desc.texname.empty())
            {
                var[desc.texname] = renderData.getTexture(desc.name);
            }
        };
        for (auto channel : kInputChannels)
            bind(channel);
        for (auto channel : kOutputChannels)
            bind(channel);

        mpSampleGenerator->setShaderData(var);
        mpScene->setRaytracingShaderData(pRenderContext, var);
        mpTracePass->execute(pRenderContext, {targetDim, 1u});
    }
    else
    {
        if (mpEmissiveSampler)
            mpRtPass->pProgram->addDefines(mpEmissiveSampler->getDefines());
        mpRtPass->pProgram->addDefines(mParams.getDefines(*this));
        mpRtPass->pProgram->addDefines(getValidResourceDefines(kInputChannels, renderData));
        mpRtPass->pProgram->addDefines(getValidResourceDefines(kOutputChannels, renderData));
        mpRtPass->pProgram->addDefine("ENABLE_DEBUG_FEATURES", "1");

        auto var = mpRtPass->pVars.getRootVar();

        // prepare buffers
        {
            if (!mpPathBuffer || mOptionsChanged)
            {
                mpPathBuffer = nullptr;
                uint32_t pathSurfaceCount = targetDim.x * targetDim.y * mParams.maxBounces;
                mpPathBuffer = Buffer::createStructured(
                    mpDevice.get(), var["gPathData"], pathSurfaceCount,
                    ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false
                );
                FALCOR_ASSERT(mpPathBuffer);
            }
        }

        var["CB"]["gFrameCount"] = mFrameCount;
        var["CB"]["gFrameDim"] = targetDim;
        if (mpEnvMapSampler)
            mpEnvMapSampler->setShaderData(var["CB"]["envMapSampler"]);
        if (mpEmissiveSampler)
            mpEmissiveSampler->setShaderData(var["CB"]["emissiveSampler"]);
        const auto& bind = [&](const ChannelDesc& desc)
        {
            if (!desc.texname.empty())
            {
                var[desc.texname] = renderData.getTexture(desc.name);
            }
        };
        for (auto channel : kInputChannels)
            bind(channel);
        for (auto channel : kOutputChannels)
            bind(channel);

        mpSampleGenerator->setShaderData(var);
        mpScene->setRaytracingShaderData(pRenderContext, var);
        mpScene->raytrace(pRenderContext, mpRtPass->pProgram.get(), mpRtPass->pVars, {targetDim, 1u});
    }
#if USE_PARAMETER_BLOCK
    else
    {
        if (mpEmissiveSampler)
            mpRtPass->pProgram->addDefines(mpEmissiveSampler->getDefines());
        mpRtPass->pProgram->addDefines(mParams.getDefines(*this));
        mpRtPass->pProgram->addDefines(getValidResourceDefines(kInputChannels, renderData));
        mpRtPass->pProgram->addDefines(getValidResourceDefines(kOutputChannels, renderData));

        auto var = mpRtPass->pVars.getRootVar();
        auto ptvar = mpPathTracerBlock->getRootVar();
        // prepare buffers
        {
            if (!mpPathBuffer)
            {
                uint32_t pathSurfaceCount = targetDim.x * targetDim.y * mParams.maxBounces;
                mpPathBuffer = Buffer::createStructured(
                    mpDevice.get(), ptvar["gPathData"], pathSurfaceCount,
                    ResourceBindFlags::ShaderResource | ResourceBindFlags::UnorderedAccess, Buffer::CpuAccess::None, nullptr, false
                );
                FALCOR_ASSERT(mpPathBuffer);
            }
        }

        ptvar["gFrameCount"] = mFrameCount;
        ptvar["gFrameDim"] = targetDim;
        if (mpEnvMapSampler)
            mpEnvMapSampler->setShaderData(ptvar["envMapSampler"]);
        if (mpEmissiveSampler)
            mpEmissiveSampler->setShaderData(ptvar["emissiveSampler"]);
        ptvar["gPathData"] = mpPathBuffer;
        const auto& bind = [&](const ChannelDesc& desc)
        {
            if (!desc.texname.empty())
            {
                var[desc.texname] = renderData.getTexture(desc.name);
            }
        };
        for (auto channel : kInputChannels)
            bind(channel);
        for (auto channel : kOutputChannels)
            bind(channel);

        mpSampleGenerator->setShaderData(var);
        mpScene->setRaytracingShaderData(pRenderContext, var);
        var["gPathTracer"] = mpPathTracerBlock;
        mpScene->raytrace(pRenderContext, mpRtPass->pProgram.get(), mpRtPass->pVars, {targetDim, 1u});
    }
#endif

    mFrameCount++;
}

void TinySpectralPathTracer::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;
    dirty |= widget.var("Max bounces", mParams.maxBounces, 0u, 1u << 16);
    widget.tooltip("Maximum path length for indirect illumination.\n0 = direct only\n1 = one indirect bounce etc.", true);
    dirty |= widget.var("HWSS Samples", mParams.mHWSS, 0u, 8u);
    dirty |= widget.checkbox("Use MIS", mParams.conbineBSDFandNEESampling);
    dirty |= widget.checkbox("Use RIS DI", mParams.useRISDI);
    dirty |= widget.var("RIS Samples", mParams.RISSamples, 0u, 32u);
    if (dirty)
    {
        mOptionsChanged = true;
    }
}
