/*
 * Copyright (C) 2023, Inria
 * GRAPHDECO research group, https://team.inria.fr/graphdeco
 * All rights reserved.
 *
 * This software is free for non-commercial, research and evaluation use 
 * under the terms of the LICENSE.md file.
 *
 * For inquiries contact  george.drettakis@inria.fr
 */

#ifndef CUDA_RASTERIZER_BACKWARD_H_INCLUDED
#define CUDA_RASTERIZER_BACKWARD_H_INCLUDED

#include <cuda.h>
#include "cuda_runtime.h"
#include "device_launch_parameters.h"
#define GLM_FORCE_CUDA
#include <glm/glm.hpp>

#include "vec_math.h"

namespace BACKWARD
{
	void render(
		const dim3 grid, dim3 block,
		const int W, int H,
		const float* means3D,
		const float* cam_pos,
		const uint2* ranges,
		const uint32_t* point_list,
		const float* bg_color,
		const float2* means2D,
		const float4* conic_opacity,
		const float* colors,
		const float* normal,
		const float* albedo,
		const float* roughness,
		const float* metallic,
		const float* semantic,  // 新增
		const float* flow,  // 新增
		const float* final_Ts,
		const uint32_t* n_contrib,
		const float* dL_dpixels_depth,
		const float* dL_dpixels,
		const float* dL_dpixels_opacity,
		const float* dL_dpixels_normal,
		const float* dL_dpixels_albedo,
		const float* dL_dpixels_roughness,
		const float* dL_dpixels_metallic,
		const float* dL_dpixels_semantic,  // 新增
		const float* dL_dpixels_flow,  // 新增
		float3* dL_dmean2D,
		float4* dL_dconic2D,
		float* dL_depth,
		float* dL_dopacity,
		float* dL_dcolors,
		float* dL_dnormals,
		float* dL_dalbedo,
		float* dL_droughness,
		float* dL_dmetallic,
		float* dL_dsemantic,  // 新增
		float* dL_dflow);

	void preprocess(
		const int P, int D, int M,
		const float focal_x, float focal_y,
		const float tan_fovx, float tan_fovy,
		const float3* means,
		const int* radii,
		const float* shs,
		const bool* clamped,
		const glm::vec3* scales,
		const glm::vec4* rotations,
		const float scale_modifier,
		const float* cov3Ds,
		const float* view,
		const float* proj,
		const glm::vec3* campos,
		const float3* dL_dmean2D,
		const float* dL_dconics,
		const float* dL_depth,
		glm::vec3* dL_dmeans,
		float* dL_dcolor,
		float* dL_dcov3D,
		float* dL_dsh,
		glm::vec3* dL_dscale,
		glm::vec4* dL_drot);

	void SSR(
		const dim3 grid, 
		const dim3 block,
		int W, int H,
		const float focal_x,
		const float focal_y,
		const float* out_normal,
		const float* out_pos,
		const float* out_rgb,
		const float* out_albedo,
    	const float* out_roughness,
    	const float* out_metallic,
    	const float* out_F0,
		const float* dL_dpixels,
		float* dl_albedo,
		float* dl_roughness,
		float* dl_metallic);
}

#endif