/***************************************************************************

 **************************************************************************/
#include "PLTDiffuseFluorescenceMaterial.h"
#include "Scene/SceneBuilderAccess.h"
#include "Utils/Scripting/ScriptBindings.h"
#include "Utils/Color/SpectrumUtils.h"
#include "Scene/Scene.h"
#include <imgui.h>

namespace Falcor
{
namespace
{
const char kShaderFile[] = "Rendering/Materials/PLT/PLTDiffuseFluorescenceMaterial.slang";
}

PLTDiffuseFluorescenceMaterial::SharedPtr PLTDiffuseFluorescenceMaterial::create(std::shared_ptr<Device> pDevice, const std::string& name)
{
    return SharedPtr(new PLTDiffuseFluorescenceMaterial(std::move(pDevice), name));
}

PLTDiffuseFluorescenceMaterial::PLTDiffuseFluorescenceMaterial(std::shared_ptr<Device> pDevice, const std::string& name)
    : BasicMaterial(std::move(pDevice), name, MaterialType::PLTDiffuse)
{
    // Setup additional texture slots.
    mTextureSlotInfo[(uint32_t)TextureSlot::BaseColor] = {"baseColor", TextureChannelFlags::RGB, true};
    mTextureSlotInfo[(uint32_t)TextureSlot::Normal] = {"normal", TextureChannelFlags::RGB, false};
}

Program::ShaderModuleList PLTDiffuseFluorescenceMaterial::getShaderModules() const
{
    return {Program::ShaderModule(kShaderFile)};
}

Program::TypeConformanceList PLTDiffuseFluorescenceMaterial::getTypeConformances() const
{
    return {{{"PLTDiffuseFluorescenceMaterial", "IMaterial"}, (uint32_t)MaterialType::PLTDiffuse}};
}

bool PLTDiffuseFluorescenceMaterial::renderUI(Gui::Widgets& widget, const Scene* scene)
{
    // We're re-using the material's update flags here to track changes.
    // Cache the previous flag so we can restore it before returning.
    UpdateFlags prevUpdates = mUpdates;
    mUpdates = UpdateFlags::None;

    widget.text("Type: " + to_string(getType()));

    if (auto pTexture = getBaseColorTexture())
    {
        bool hasAlpha = isAlphaSupported() && doesFormatHaveAlpha(pTexture->getFormat());
        bool alphaConst = mIsTexturedAlphaConstant && hasAlpha;
        bool colorConst = mIsTexturedBaseColorConstant;

        std::ostringstream oss;
        oss << "Texture info: " << pTexture->getWidth() << "x" << pTexture->getHeight() << " (" << to_string(pTexture->getFormat()) << ")";
        if (colorConst && !alphaConst)
            oss << " (color constant)";
        else if (!colorConst && alphaConst)
            oss << " (alpha constant)";
        else if (colorConst && alphaConst)
            oss << " (color and alpha constant)"; // Shouldn't happen

        widget.text("Base color: " + pTexture->getSourcePath().string());
        widget.text(oss.str());

        if (colorConst || alphaConst)
        {
            float4 baseColor = getBaseColor();
            if (widget.var("Base color", baseColor, 0.f, 1.f, 0.01f))
                setBaseColor(baseColor);
        }

        widget.image("Base color", pTexture, float2(100.f));
        if (widget.button("Remove texture##BaseColor"))
            setBaseColorTexture(nullptr);
    }
    else
    {
        float4 baseColor = getBaseColor();
        if (widget.var("Base color", baseColor, 0.f, 1.f, 0.01f))
            setBaseColor(baseColor);
    }

    if (auto pTexture = getNormalMap())
    {
        widget.text("Normal map: " + pTexture->getSourcePath().string());
        widget.text(
            "Texture info: " + std::to_string(pTexture->getWidth()) + "x" + std::to_string(pTexture->getHeight()) + " (" +
            to_string(pTexture->getFormat()) + ")"
        );
        widget.image("Normal map", pTexture, float2(100.f));
        if (widget.button("Remove texture##NormalMap"))
            setNormalMap(nullptr);
    }

    const float3& emission = isEmissive() ? scene->getSpectralProfile(getEmissionSpectralProfile().get()).rgb : float3(.0f);
    const float intensity = std::max(1.f, std::max(emission.r, std::max(emission.g, emission.b)));
    if (isEmissive())
    {
        const auto& profile = scene->getSpectralProfile(getEmissionSpectralProfile().get());
        widget.graph("emission spectrum", BasicMaterial::UIHelpers::grapher, (void*)&profile, BasicMaterial::UIHelpers::grapher_bins, 0);
        widget.rgbColor("", emission / intensity);
    }

    // Restore update flags.
    const auto changed = mUpdates != UpdateFlags::None;
    markUpdates(prevUpdates | mUpdates);

    return changed;
}

FALCOR_SCRIPT_BINDING(PLTDiffuseFluorescenceMaterial)
{
    using namespace pybind11::literals;

    FALCOR_SCRIPT_BINDING_DEPENDENCY(BasicMaterial)

    pybind11::class_<PLTDiffuseFluorescenceMaterial, BasicMaterial, PLTDiffuseFluorescenceMaterial::SharedPtr> material(
        m, "PLTDiffuseFluorescenceMaterial"
    );
    auto create = [](const std::string& name)
    { return PLTDiffuseFluorescenceMaterial::create(getActivePythonSceneBuilder().getDevice(), name); };
    material.def(pybind11::init(create), "name"_a = ""); // PYTHONDEPRECATED
}
} // namespace Falcor
