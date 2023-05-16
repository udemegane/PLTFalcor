/***************************************************************************

 **************************************************************************/
#pragma once
#include "Scene/Material/BasicMaterial.h"

namespace Falcor
{
/** This class implements a Lambertian diffuse material, where
    reflectance does not depend on wo.

    Texture channel layout:

        BaseColor
            - RGB - Base Color
        Normal
            - 3-Channel standard normal map, or 2-Channel BC5 format
*/
class FALCOR_API PLTDiffuseFluorescenceMaterial : public BasicMaterial
{
public:
    using SharedPtr = std::shared_ptr<PLTDiffuseFluorescenceMaterial>;

    /** Create a new PLTDiffuse material.
        \param[in] name The material name.
    */
    static SharedPtr create(std::shared_ptr<Device> pDevice, const std::string& name = "");

    Program::ShaderModuleList getShaderModules() const override;
    Program::TypeConformanceList getTypeConformances() const override;

    virtual bool renderUI(Gui::Widgets& widget, const Scene* scene) override;

protected:
    PLTDiffuseFluorescenceMaterial(std::shared_ptr<Device> pDevice, const std::string& name);
};
} // namespace Falcor
