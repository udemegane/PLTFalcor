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
#include "RenderGraph/RenderPassHelpers.h"
#include "RenderGraph/RenderPassStandardFlags.h"

extern "C" FALCOR_API_EXPORT void registerPlugin(Falcor::PluginRegistry& registry)
{
    registry.registerClass<RenderPass, TinySpectralPathTracer>();
}

namespace
{
const std::string kTracePassFileName = "RenderPasses/TinySpectralPathTracer/TinySpectralPathTracer.cs.slang";

const std::string kShaderModel = "6_5";

const ChannelList kInputChannels = {
    {"vbuffer", "gVBuffer", "Visibility buffer", false},
    {"viewW", "gViewW", "World space View Direction ", true},
};

const ChannelList kOutputChannels = {
    {"color", "gOutputColor", "OutputColor", false, ResourceFormat::RGBA32Float},
};

const std::string kMaxBounces = "maxBounces";

} // namespace

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
    return defines;
}

void TinySpectralPathTracer::setScene(RenderContext* pRenderContext, const Scene::SharedPtr& pScene)
{
    mFrameCount = 0u;
    mpScene = pScene;
    mpTracePass = nullptr;
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

void TinySpectralPathTracer::updatePrograms()
{
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

    updatePrograms();
    FALCOR_ASSERT(mpTracePass);

    if (is_set(mpScene->getUpdates(), Scene::UpdateFlags::GeometryChanged))
    {
        throw RuntimeError("TinySpectralPathTracer does not support dynamic Object.");
    }

    // EmissiveLight対応してるっけ？
    // if(mpScene->getRenderSettings().useEmissiveLights){

    // }
    // set defines
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
    mFrameCount++;
}

void TinySpectralPathTracer::renderUI(Gui::Widgets& widget)
{
    bool dirty = false;
    dirty |= widget.var("Max bounces", mParams.maxBounces, 0u, 1u << 16);
    widget.tooltip("Maximum path length for indirect illumination.\n0 = direct only\n1 = one indirect bounce etc.", true);

    if (dirty)
    {
        mOptionsChanged = true;
    }
}
