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

#include "backward.h"
#include "auxiliary.h"
#include <cooperative_groups.h>
#include <cooperative_groups/reduce.h>
#include "ssr.h"
namespace cg = cooperative_groups;

// Backward pass for conversion of spherical harmonics to RGB for
// each Gaussian.
__device__ void computeColorFromSH(int idx, int deg, int max_coeffs, const glm::vec3* means, glm::vec3 campos, const float* shs, const bool* clamped, const glm::vec3* dL_dcolor, glm::vec3* dL_dmeans, glm::vec3* dL_dshs)
{
	// Compute intermediate values, as it is done during forward
	glm::vec3 pos = means[idx];
	glm::vec3 dir_orig = pos - campos;
	glm::vec3 dir = dir_orig / glm::length(dir_orig);

	glm::vec3* sh = ((glm::vec3*)shs) + idx * max_coeffs;

	// Use PyTorch rule for clamping: if clamping was applied,
	// gradient becomes 0.
	glm::vec3 dL_dRGB = dL_dcolor[idx];
	dL_dRGB.x *= clamped[3 * idx + 0] ? 0 : 1;
	dL_dRGB.y *= clamped[3 * idx + 1] ? 0 : 1;
	dL_dRGB.z *= clamped[3 * idx + 2] ? 0 : 1;

	glm::vec3 dRGBdx(0, 0, 0);
	glm::vec3 dRGBdy(0, 0, 0);
	glm::vec3 dRGBdz(0, 0, 0);
	float x = dir.x;
	float y = dir.y;
	float z = dir.z;

	// Target location for this Gaussian to write SH gradients to
	glm::vec3* dL_dsh = dL_dshs + idx * max_coeffs;

	// No tricks here, just high school-level calculus.
	float dRGBdsh0 = SH_C0;
	dL_dsh[0] = dRGBdsh0 * dL_dRGB;
	if (deg > 0)
	{
		float dRGBdsh1 = -SH_C1 * y;
		float dRGBdsh2 = SH_C1 * z;
		float dRGBdsh3 = -SH_C1 * x;
		dL_dsh[1] = dRGBdsh1 * dL_dRGB;
		dL_dsh[2] = dRGBdsh2 * dL_dRGB;
		dL_dsh[3] = dRGBdsh3 * dL_dRGB;

		dRGBdx = -SH_C1 * sh[3];
		dRGBdy = -SH_C1 * sh[1];
		dRGBdz = SH_C1 * sh[2];

		if (deg > 1)
		{
			float xx = x * x, yy = y * y, zz = z * z;
			float xy = x * y, yz = y * z, xz = x * z;

			float dRGBdsh4 = SH_C2[0] * xy;
			float dRGBdsh5 = SH_C2[1] * yz;
			float dRGBdsh6 = SH_C2[2] * (2.f * zz - xx - yy);
			float dRGBdsh7 = SH_C2[3] * xz;
			float dRGBdsh8 = SH_C2[4] * (xx - yy);
			dL_dsh[4] = dRGBdsh4 * dL_dRGB;
			dL_dsh[5] = dRGBdsh5 * dL_dRGB;
			dL_dsh[6] = dRGBdsh6 * dL_dRGB;
			dL_dsh[7] = dRGBdsh7 * dL_dRGB;
			dL_dsh[8] = dRGBdsh8 * dL_dRGB;

			dRGBdx += SH_C2[0] * y * sh[4] + SH_C2[2] * 2.f * -x * sh[6] + SH_C2[3] * z * sh[7] + SH_C2[4] * 2.f * x * sh[8];
			dRGBdy += SH_C2[0] * x * sh[4] + SH_C2[1] * z * sh[5] + SH_C2[2] * 2.f * -y * sh[6] + SH_C2[4] * 2.f * -y * sh[8];
			dRGBdz += SH_C2[1] * y * sh[5] + SH_C2[2] * 2.f * 2.f * z * sh[6] + SH_C2[3] * x * sh[7];

			if (deg > 2)
			{
				float dRGBdsh9 = SH_C3[0] * y * (3.f * xx - yy);
				float dRGBdsh10 = SH_C3[1] * xy * z;
				float dRGBdsh11 = SH_C3[2] * y * (4.f * zz - xx - yy);
				float dRGBdsh12 = SH_C3[3] * z * (2.f * zz - 3.f * xx - 3.f * yy);
				float dRGBdsh13 = SH_C3[4] * x * (4.f * zz - xx - yy);
				float dRGBdsh14 = SH_C3[5] * z * (xx - yy);
				float dRGBdsh15 = SH_C3[6] * x * (xx - 3.f * yy);
				dL_dsh[9] = dRGBdsh9 * dL_dRGB;
				dL_dsh[10] = dRGBdsh10 * dL_dRGB;
				dL_dsh[11] = dRGBdsh11 * dL_dRGB;
				dL_dsh[12] = dRGBdsh12 * dL_dRGB;
				dL_dsh[13] = dRGBdsh13 * dL_dRGB;
				dL_dsh[14] = dRGBdsh14 * dL_dRGB;
				dL_dsh[15] = dRGBdsh15 * dL_dRGB;

				dRGBdx += (
					SH_C3[0] * sh[9] * 3.f * 2.f * xy +
					SH_C3[1] * sh[10] * yz +
					SH_C3[2] * sh[11] * -2.f * xy +
					SH_C3[3] * sh[12] * -3.f * 2.f * xz +
					SH_C3[4] * sh[13] * (-3.f * xx + 4.f * zz - yy) +
					SH_C3[5] * sh[14] * 2.f * xz +
					SH_C3[6] * sh[15] * 3.f * (xx - yy));

				dRGBdy += (
					SH_C3[0] * sh[9] * 3.f * (xx - yy) +
					SH_C3[1] * sh[10] * xz +
					SH_C3[2] * sh[11] * (-3.f * yy + 4.f * zz - xx) +
					SH_C3[3] * sh[12] * -3.f * 2.f * yz +
					SH_C3[4] * sh[13] * -2.f * xy +
					SH_C3[5] * sh[14] * -2.f * yz +
					SH_C3[6] * sh[15] * -3.f * 2.f * xy);

				dRGBdz += (
					SH_C3[1] * sh[10] * xy +
					SH_C3[2] * sh[11] * 4.f * 2.f * yz +
					SH_C3[3] * sh[12] * 3.f * (2.f * zz - xx - yy) +
					SH_C3[4] * sh[13] * 4.f * 2.f * xz +
					SH_C3[5] * sh[14] * (xx - yy));
			}
		}
	}

	// The view direction is an input to the computation. View direction
	// is influenced by the Gaussian's mean, so SHs gradients
	// must propagate back into 3D position.
	glm::vec3 dL_ddir(glm::dot(dRGBdx, dL_dRGB), glm::dot(dRGBdy, dL_dRGB), glm::dot(dRGBdz, dL_dRGB));

	// Account for normalization of direction
	float3 dL_dmean = dnormvdv(float3{ dir_orig.x, dir_orig.y, dir_orig.z }, float3{ dL_ddir.x, dL_ddir.y, dL_ddir.z });

	// Gradients of loss w.r.t. Gaussian means, but only the portion 
	// that is caused because the mean affects the view-dependent color.
	// Additional mean gradient is accumulated in below methods.
	dL_dmeans[idx] += glm::vec3(dL_dmean.x, dL_dmean.y, dL_dmean.z);
}

// Backward version of INVERSE 2D covariance matrix computation
// (due to length launched as separate kernel before other 
// backward steps contained in preprocess)
__global__ void computeCov2DCUDA(int P,
	const float3* means,
	const int* radii,
	const float* cov3Ds,
	const float h_x, float h_y,
	const float tan_fovx, float tan_fovy,
	const float* view_matrix,
	const float* dL_dconics,
	const float* dL_depth,
	float3* dL_dmeans,
	float* dL_dcov)
{
	auto idx = cg::this_grid().thread_rank();
	if (idx >= P || !(radii[idx] > 0))
		return;

	// Reading location of 3D covariance for this Gaussian
	const float* cov3D = cov3Ds + 6 * idx;

	// Fetch gradients, recompute 2D covariance and relevant 
	// intermediate forward results needed in the backward.
	float3 mean = means[idx];
	float3 dL_dconic = { dL_dconics[4 * idx], dL_dconics[4 * idx + 1], dL_dconics[4 * idx + 3] };
	float3 t = transformPoint4x3(mean, view_matrix);
	
	const float limx = 1.3f * tan_fovx;
	const float limy = 1.3f * tan_fovy;
	const float txtz = t.x / t.z;
	const float tytz = t.y / t.z;
	t.x = min(limx, max(-limx, txtz)) * t.z;
	t.y = min(limy, max(-limy, tytz)) * t.z;
	
	const float x_grad_mul = txtz < -limx || txtz > limx ? 0 : 1;
	const float y_grad_mul = tytz < -limy || tytz > limy ? 0 : 1;

	glm::mat3 J = glm::mat3(h_x / t.z, 0.0f, -(h_x * t.x) / (t.z * t.z),
		0.0f, h_y / t.z, -(h_y * t.y) / (t.z * t.z),
		0, 0, 0);

	glm::mat3 W = glm::mat3(
		view_matrix[0], view_matrix[4], view_matrix[8],
		view_matrix[1], view_matrix[5], view_matrix[9],
		view_matrix[2], view_matrix[6], view_matrix[10]);

	glm::mat3 Vrk = glm::mat3(
		cov3D[0], cov3D[1], cov3D[2],
		cov3D[1], cov3D[3], cov3D[4],
		cov3D[2], cov3D[4], cov3D[5]);

	glm::mat3 T = W * J;

	glm::mat3 cov2D = glm::transpose(T) * glm::transpose(Vrk) * T;

	// Use helper variables for 2D covariance entries. More compact.
	float a = cov2D[0][0] += 0.3f;
	float b = cov2D[0][1];
	float c = cov2D[1][1] += 0.3f;

	float denom = a * c - b * b;
	float dL_da = 0, dL_db = 0, dL_dc = 0;
	float denom2inv = 1.0f / ((denom * denom) + 0.0000001f);

	if (denom2inv != 0)
	{
		// Gradients of loss w.r.t. entries of 2D covariance matrix,
		// given gradients of loss w.r.t. conic matrix (inverse covariance matrix).
		// e.g., dL / da = dL / d_conic_a * d_conic_a / d_a
		dL_da = denom2inv * (-c * c * dL_dconic.x + 2 * b * c * dL_dconic.y + (denom - a * c) * dL_dconic.z);
		dL_dc = denom2inv * (-a * a * dL_dconic.z + 2 * a * b * dL_dconic.y + (denom - a * c) * dL_dconic.x);
		dL_db = denom2inv * 2 * (b * c * dL_dconic.x - (denom + 2 * b * b) * dL_dconic.y + a * b * dL_dconic.z);

		// Gradients of loss L w.r.t. each 3D covariance matrix (Vrk) entry, 
		// given gradients w.r.t. 2D covariance matrix (diagonal).
		// cov2D = transpose(T) * transpose(Vrk) * T;
		dL_dcov[6 * idx + 0] = (T[0][0] * T[0][0] * dL_da + T[0][0] * T[1][0] * dL_db + T[1][0] * T[1][0] * dL_dc);
		dL_dcov[6 * idx + 3] = (T[0][1] * T[0][1] * dL_da + T[0][1] * T[1][1] * dL_db + T[1][1] * T[1][1] * dL_dc);
		dL_dcov[6 * idx + 5] = (T[0][2] * T[0][2] * dL_da + T[0][2] * T[1][2] * dL_db + T[1][2] * T[1][2] * dL_dc);

		// Gradients of loss L w.r.t. each 3D covariance matrix (Vrk) entry, 
		// given gradients w.r.t. 2D covariance matrix (off-diagonal).
		// Off-diagonal elements appear twice --> double the gradient.
		// cov2D = transpose(T) * transpose(Vrk) * T;
		dL_dcov[6 * idx + 1] = 2 * T[0][0] * T[0][1] * dL_da + (T[0][0] * T[1][1] + T[0][1] * T[1][0]) * dL_db + 2 * T[1][0] * T[1][1] * dL_dc;
		dL_dcov[6 * idx + 2] = 2 * T[0][0] * T[0][2] * dL_da + (T[0][0] * T[1][2] + T[0][2] * T[1][0]) * dL_db + 2 * T[1][0] * T[1][2] * dL_dc;
		dL_dcov[6 * idx + 4] = 2 * T[0][2] * T[0][1] * dL_da + (T[0][1] * T[1][2] + T[0][2] * T[1][1]) * dL_db + 2 * T[1][1] * T[1][2] * dL_dc;
	}
	else
	{
		for (int i = 0; i < 6; i++)
			dL_dcov[6 * idx + i] = 0;
	}

	// Gradients of loss w.r.t. upper 2x3 portion of intermediate matrix T
	// cov2D = transpose(T) * transpose(Vrk) * T;
	float dL_dT00 = 2 * (T[0][0] * Vrk[0][0] + T[0][1] * Vrk[0][1] + T[0][2] * Vrk[0][2]) * dL_da +
		(T[1][0] * Vrk[0][0] + T[1][1] * Vrk[0][1] + T[1][2] * Vrk[0][2]) * dL_db;
	float dL_dT01 = 2 * (T[0][0] * Vrk[1][0] + T[0][1] * Vrk[1][1] + T[0][2] * Vrk[1][2]) * dL_da +
		(T[1][0] * Vrk[1][0] + T[1][1] * Vrk[1][1] + T[1][2] * Vrk[1][2]) * dL_db;
	float dL_dT02 = 2 * (T[0][0] * Vrk[2][0] + T[0][1] * Vrk[2][1] + T[0][2] * Vrk[2][2]) * dL_da +
		(T[1][0] * Vrk[2][0] + T[1][1] * Vrk[2][1] + T[1][2] * Vrk[2][2]) * dL_db;
	float dL_dT10 = 2 * (T[1][0] * Vrk[0][0] + T[1][1] * Vrk[0][1] + T[1][2] * Vrk[0][2]) * dL_dc +
		(T[0][0] * Vrk[0][0] + T[0][1] * Vrk[0][1] + T[0][2] * Vrk[0][2]) * dL_db;
	float dL_dT11 = 2 * (T[1][0] * Vrk[1][0] + T[1][1] * Vrk[1][1] + T[1][2] * Vrk[1][2]) * dL_dc +
		(T[0][0] * Vrk[1][0] + T[0][1] * Vrk[1][1] + T[0][2] * Vrk[1][2]) * dL_db;
	float dL_dT12 = 2 * (T[1][0] * Vrk[2][0] + T[1][1] * Vrk[2][1] + T[1][2] * Vrk[2][2]) * dL_dc +
		(T[0][0] * Vrk[2][0] + T[0][1] * Vrk[2][1] + T[0][2] * Vrk[2][2]) * dL_db;

	// Gradients of loss w.r.t. upper 3x2 non-zero entries of Jacobian matrix
	// T = W * J
	float dL_dJ00 = W[0][0] * dL_dT00 + W[0][1] * dL_dT01 + W[0][2] * dL_dT02;
	float dL_dJ02 = W[2][0] * dL_dT00 + W[2][1] * dL_dT01 + W[2][2] * dL_dT02;
	float dL_dJ11 = W[1][0] * dL_dT10 + W[1][1] * dL_dT11 + W[1][2] * dL_dT12;
	float dL_dJ12 = W[2][0] * dL_dT10 + W[2][1] * dL_dT11 + W[2][2] * dL_dT12;

	float tz = 1.f / t.z;
	float tz2 = tz * tz;
	float tz3 = tz2 * tz;

	// Gradients of loss w.r.t. transformed Gaussian mean t
	float dL_dtx = x_grad_mul * -h_x * tz2 * dL_dJ02;
	float dL_dty = y_grad_mul * -h_y * tz2 * dL_dJ12;
	float dL_dtz = -h_x * tz2 * dL_dJ00 - h_y * tz2 * dL_dJ11 + (2 * h_x * t.x) * tz3 * dL_dJ02 + (2 * h_y * t.y) * tz3 * dL_dJ12;

	// Account for transformation of mean to t
	// t = transformPoint4x3(mean, view_matrix);
	float3 dL_dmean = transformVec4x3Transpose({ dL_dtx, dL_dty, dL_dtz }, view_matrix);
	dL_dmean.x += view_matrix[2]*dL_depth[idx];
	dL_dmean.y += view_matrix[6]*dL_depth[idx];
	dL_dmean.z += view_matrix[10]*dL_depth[idx];

	// Gradients of loss w.r.t. Gaussian means, but only the portion 
	// that is caused because the mean affects the covariance matrix.
	// Additional mean gradient is accumulated in BACKWARD::preprocess.
	dL_dmeans[idx] = dL_dmean;
}

// Backward pass for the conversion of scale and rotation to a 
// 3D covariance matrix for each Gaussian. 
__device__ void computeCov3D(int idx, const glm::vec3 scale, float mod, const glm::vec4 rot, const float* dL_dcov3Ds, glm::vec3* dL_dscales, glm::vec4* dL_drots)
{
	// Recompute (intermediate) results for the 3D covariance computation.
	glm::vec4 q = rot;// / glm::length(rot);
	float r = q.x;
	float x = q.y;
	float y = q.z;
	float z = q.w;

	glm::mat3 R = glm::mat3(
		1.f - 2.f * (y * y + z * z), 2.f * (x * y - r * z), 2.f * (x * z + r * y),
		2.f * (x * y + r * z), 1.f - 2.f * (x * x + z * z), 2.f * (y * z - r * x),
		2.f * (x * z - r * y), 2.f * (y * z + r * x), 1.f - 2.f * (x * x + y * y)
	);

	glm::mat3 S = glm::mat3(1.0f);

	glm::vec3 s = mod * scale;
	S[0][0] = s.x;
	S[1][1] = s.y;
	S[2][2] = s.z;

	glm::mat3 M = S * R;

	const float* dL_dcov3D = dL_dcov3Ds + 6 * idx;

	glm::vec3 dunc(dL_dcov3D[0], dL_dcov3D[3], dL_dcov3D[5]);
	glm::vec3 ounc = 0.5f * glm::vec3(dL_dcov3D[1], dL_dcov3D[2], dL_dcov3D[4]);

	// Convert per-element covariance loss gradients to matrix form
	glm::mat3 dL_dSigma = glm::mat3(
		dL_dcov3D[0], 0.5f * dL_dcov3D[1], 0.5f * dL_dcov3D[2],
		0.5f * dL_dcov3D[1], dL_dcov3D[3], 0.5f * dL_dcov3D[4],
		0.5f * dL_dcov3D[2], 0.5f * dL_dcov3D[4], dL_dcov3D[5]
	);

	// Compute loss gradient w.r.t. matrix M
	// dSigma_dM = 2 * M
	glm::mat3 dL_dM = 2.0f * M * dL_dSigma;

	glm::mat3 Rt = glm::transpose(R);
	glm::mat3 dL_dMt = glm::transpose(dL_dM);

	// Gradients of loss w.r.t. scale
	glm::vec3* dL_dscale = dL_dscales + idx;
	dL_dscale->x = glm::dot(Rt[0], dL_dMt[0]);
	dL_dscale->y = glm::dot(Rt[1], dL_dMt[1]);
	dL_dscale->z = glm::dot(Rt[2], dL_dMt[2]);

	dL_dMt[0] *= s.x;
	dL_dMt[1] *= s.y;
	dL_dMt[2] *= s.z;

	// Gradients of loss w.r.t. normalized quaternion
	glm::vec4 dL_dq;
	dL_dq.x = 2 * z * (dL_dMt[0][1] - dL_dMt[1][0]) + 2 * y * (dL_dMt[2][0] - dL_dMt[0][2]) + 2 * x * (dL_dMt[1][2] - dL_dMt[2][1]);
	dL_dq.y = 2 * y * (dL_dMt[1][0] + dL_dMt[0][1]) + 2 * z * (dL_dMt[2][0] + dL_dMt[0][2]) + 2 * r * (dL_dMt[1][2] - dL_dMt[2][1]) - 4 * x * (dL_dMt[2][2] + dL_dMt[1][1]);
	dL_dq.z = 2 * x * (dL_dMt[1][0] + dL_dMt[0][1]) + 2 * r * (dL_dMt[2][0] - dL_dMt[0][2]) + 2 * z * (dL_dMt[1][2] + dL_dMt[2][1]) - 4 * y * (dL_dMt[2][2] + dL_dMt[0][0]);
	dL_dq.w = 2 * r * (dL_dMt[0][1] - dL_dMt[1][0]) + 2 * x * (dL_dMt[2][0] + dL_dMt[0][2]) + 2 * y * (dL_dMt[1][2] + dL_dMt[2][1]) - 4 * z * (dL_dMt[1][1] + dL_dMt[0][0]);

	// Gradients of loss w.r.t. unnormalized quaternion
	float4* dL_drot = (float4*)(dL_drots + idx);
	*dL_drot = float4{ dL_dq.x, dL_dq.y, dL_dq.z, dL_dq.w };//dnormvdv(float4{ rot.x, rot.y, rot.z, rot.w }, float4{ dL_dq.x, dL_dq.y, dL_dq.z, dL_dq.w });
}

// Backward pass of the preprocessing steps, except
// for the covariance computation and inversion
// (those are handled by a previous kernel call)
template<int C>
__global__ void preprocessCUDA(
	int P, int D, int M,
	const float3* means,
	const int* radii,
	const float* shs,
	const bool* clamped,
	const glm::vec3* scales,
	const glm::vec4* rotations,
	const float scale_modifier,
	const float* proj,
	const glm::vec3* campos,
	const float3* dL_dmean2D,
	glm::vec3* dL_dmeans,
	float* dL_dcolor,
	float* dL_dcov3D,
	float* dL_dsh,
	glm::vec3* dL_dscale,
	glm::vec4* dL_drot)
{
	auto idx = cg::this_grid().thread_rank();
	if (idx >= P || !(radii[idx] > 0))
		return;

	float3 m = means[idx];

	// Taking care of gradients from the screenspace points
	float4 m_hom = transformPoint4x4(m, proj);
	float m_w = 1.0f / (m_hom.w + 0.0000001f);

	// Compute loss gradient w.r.t. 3D means due to gradients of 2D means
	// from rendering procedure
	glm::vec3 dL_dmean;
	float mul1 = (proj[0] * m.x + proj[4] * m.y + proj[8] * m.z + proj[12]) * m_w * m_w;
	float mul2 = (proj[1] * m.x + proj[5] * m.y + proj[9] * m.z + proj[13]) * m_w * m_w;
	dL_dmean.x = (proj[0] * m_w - proj[3] * mul1) * dL_dmean2D[idx].x + (proj[1] * m_w - proj[3] * mul2) * dL_dmean2D[idx].y;
	dL_dmean.y = (proj[4] * m_w - proj[7] * mul1) * dL_dmean2D[idx].x + (proj[5] * m_w - proj[7] * mul2) * dL_dmean2D[idx].y;
	dL_dmean.z = (proj[8] * m_w - proj[11] * mul1) * dL_dmean2D[idx].x + (proj[9] * m_w - proj[11] * mul2) * dL_dmean2D[idx].y;

	// That's the second part of the mean gradient. Previous computation
	// of cov2D and following SH conversion also affects it.
	dL_dmeans[idx] += dL_dmean;

	// Compute gradient updates due to computing colors from SHs
	if (shs)
		computeColorFromSH(idx, D, M, (glm::vec3*)means, *campos, shs, clamped, (glm::vec3*)dL_dcolor, (glm::vec3*)dL_dmeans, (glm::vec3*)dL_dsh);

	// Compute gradient updates due to computing covariance from scale/rotation
	if (scales)
		computeCov3D(idx, scales[idx], scale_modifier, rotations[idx], dL_dcov3D, dL_dscale, dL_drot);
}

// Backward version of the rendering procedure.
template <uint32_t C>
__global__ void __launch_bounds__(BLOCK_X * BLOCK_Y)
renderCUDA(
	const int W, int H,
	const float* means3D,
	const float* cam_pos,
	const uint2* __restrict__ ranges,
	const uint32_t* __restrict__ point_list,
	const float* __restrict__ bg_color,
	const float2* __restrict__ points_xy_image,
	const float4* __restrict__ conic_opacity,
	const float* __restrict__ colors,
	const float* __restrict__ normals,
	const float* __restrict__ albedo,
	const float* __restrict__ roughness,
	const float* __restrict__ metallic,
	const float* __restrict__ semantic, //新增
	const float* __restrict__ flow, //新增
	const float* __restrict__ final_Ts,
	const uint32_t* __restrict__ n_contrib,
	const float* __restrict__ dL_dpixels_depth,
	const float* __restrict__ dL_dpixels,
	const float* __restrict__ dL_dpixels_opacity,
	const float* __restrict__ dL_dpixels_normal,
	const float* __restrict__ dL_dpixels_albedo,
	const float* __restrict__ dL_dpixels_roughness,
	const float* __restrict__ dL_dpixels_metallic,
	const float* __restrict__ dL_dpixels_semantic, //新增
	const float* __restrict__ dL_dpixels_flow, //新增
	float3* __restrict__ dL_dmean2D,
	float4* __restrict__ dL_dconic2D,
	float* __restrict__ dL_depth,
	float* __restrict__ dL_dopacity,
	float* __restrict__ dL_dcolors,
	float* __restrict__ dL_dnormals,
	float* __restrict__ dL_dalbedo,
	float* __restrict__ dL_droughness,
	float* __restrict__ dL_dmetallic,
	float* __restrict__ dL_dsemantic, //新增
	float* __restrict__ dL_dflow) //新增
{
	// We rasterize again. Compute necessary block info.
	auto block = cg::this_thread_block();
	const uint32_t horizontal_blocks = (W + BLOCK_X - 1) / BLOCK_X;
	const uint2 pix_min = { block.group_index().x * BLOCK_X, block.group_index().y * BLOCK_Y };
	const uint2 pix_max = { min(pix_min.x + BLOCK_X, W), min(pix_min.y + BLOCK_Y , H) };
	const uint2 pix = { pix_min.x + block.thread_index().x, pix_min.y + block.thread_index().y };
	const uint32_t pix_id = W * pix.y + pix.x;
	const float2 pixf = { (float)pix.x, (float)pix.y };

	const bool inside = pix.x < W && pix.y < H;
	const uint2 range = ranges[block.group_index().y * horizontal_blocks + block.group_index().x];

	const int rounds = ((range.y - range.x + BLOCK_SIZE - 1) / BLOCK_SIZE);

	bool done = !inside;
	int toDo = range.y - range.x;

	__shared__ int collected_id[BLOCK_SIZE];
	__shared__ float2 collected_xy[BLOCK_SIZE];
	__shared__ float4 collected_conic_opacity[BLOCK_SIZE];
	__shared__ float collected_colors[C * BLOCK_SIZE];

	// In the forward, we stored the final value for T, the
	// product of all (1 - alpha) factors. 
	const float T_final = inside ? final_Ts[pix_id] : 0;
	float T = T_final;

	// We start from the back. The ID of the last contributing
	// Gaussian is known from each pixel from the forward.
	uint32_t contributor = toDo;
	const int last_contributor = inside ? n_contrib[pix_id] : 0;

	float last_alpha = 0.0f;

	float accum_opacity = 0.0f;
	float accum_rec[C] = { 0.0f };
	float dL_dpixel[C];
	float dL_dpixel_opacity;
	// NOTE: PBR
	float dL_dpixel_normal[C];
	float dL_dpixel_albedo[C];
	float dL_dpixel_roughness;
	float dL_dpixel_metallic;
	float dL_dpixel_semantic[20]; //新增
	float dL_dpixel_flow[2]; //新增
	float dL_dpixel_depth;
	if (inside) {
		for (int i = 0; i < C; i++) {
			dL_dpixel[i] = dL_dpixels[i * H * W + pix_id];
			dL_dpixel_normal[i] = dL_dpixels_normal[i * H * W + pix_id];
			dL_dpixel_albedo[i] = dL_dpixels_albedo[i * H * W + pix_id];
		}
		for (int i = 0; i < 20; i++) {
			dL_dpixel_semantic[i] = dL_dpixels_semantic[i * H * W + pix_id];
		}
		for (int i = 0; i < 2; i++) {
			dL_dpixel_flow[i] = dL_dpixels_flow[i * H * W + pix_id];
		}
		dL_dpixel_opacity = dL_dpixels_opacity[pix_id];
		dL_dpixel_roughness = dL_dpixels_roughness[pix_id];
		dL_dpixel_metallic = dL_dpixels_metallic[pix_id];
		dL_dpixel_depth = dL_dpixels_depth[pix_id];
	}
	float last_color[C] = { 0.0f };
	
	// Skip the edge normal
	if (pix.x == 0 || pix.x == W - 1 || pix.y == 0 || pix.y == H - 1) {
		for (int i = 0; i < C; i++) {
			dL_dpixel_normal[i] = 0.0f;
		}
	}

	// Gradient of pixel coordinate w.r.t. normalized 
	// screen-space viewport corrdinates (-1 to 1)
	const float ddelx_dx = 0.5 * W;
	const float ddely_dy = 0.5 * H;

	// Traverse all Gaussians
	for (int i = 0; i < rounds; i++, toDo -= BLOCK_SIZE)
	{
		// Load auxiliary data into shared memory, start in the BACK
		// and load them in revers order.
		block.sync();
		const int progress = i * BLOCK_SIZE + block.thread_rank();
		if (range.x + progress < range.y)
		{
			const int coll_id = point_list[range.y - progress - 1];
			collected_id[block.thread_rank()] = coll_id;
			collected_xy[block.thread_rank()] = points_xy_image[coll_id];
			collected_conic_opacity[block.thread_rank()] = conic_opacity[coll_id];
			for (int i = 0; i < C; i++) {
				collected_colors[i * BLOCK_SIZE + block.thread_rank()] = colors[coll_id * C + i];
			}
		}
		block.sync();

		// Iterate over Gaussians
		for (int j = 0; !done && j < min(BLOCK_SIZE, toDo); j++)
		{
			// Keep track of current Gaussian ID. Skip, if this one
			// is behind the last contributor for this pixel.
			contributor--;
			if (contributor >= last_contributor)
				continue;

			// Compute blending values, as before.
			const float2 xy = collected_xy[j];
			const float2 d = { xy.x - pixf.x, xy.y - pixf.y };
			const float4 con_o = collected_conic_opacity[j];
			const float power = -0.5f * (con_o.x * d.x * d.x + con_o.z * d.y * d.y) - con_o.y * d.x * d.y;
			if (power > 0.0f)
				continue;

			const float G = exp(power);
			const float alpha = min(0.99f, con_o.w * G);
			if (alpha < 1.0f / 255.0f)
				continue;

			T = T / (1.f - alpha);
			const float dchannel_dcolor = alpha * T;

			float3 view_dir = {
				cam_pos[0] - means3D[collected_id[j] * 3 + 0],
				cam_pos[1] - means3D[collected_id[j] * 3 + 1],
				cam_pos[2] - means3D[collected_id[j] * 3 + 2],
			};
			const float NoV = normals[collected_id[j] * 3 + 0] * view_dir.x + \
							  normals[collected_id[j] * 3 + 1] * view_dir.y + \
							  normals[collected_id[j] * 3 + 2] * view_dir.z;

			// Propagate gradients to per-Gaussian colors and keep
			// gradients w.r.t. alpha (blending factor for a Gaussian/pixel
			// pair).
			float dL_dalpha = 0.0f;
			const int global_id = collected_id[j];
			for (int ch = 0; ch < C; ch++)
			{
				const float c = collected_colors[ch * BLOCK_SIZE + j];
				// Update last color (to be used in the next iteration)
				accum_rec[ch] = last_alpha * last_color[ch] + (1.f - last_alpha) * accum_rec[ch];
				last_color[ch] = c;

				const float dL_dchannel = dL_dpixel[ch];
				dL_dalpha += (c - accum_rec[ch]) * dL_dchannel;
				// Update the gradients w.r.t. color of the Gaussian. 
				// Atomic, since this pixel is just one of potentially
				// many that were affected by this Gaussian.
				atomicAdd(&(dL_dcolors[global_id * C + ch]), dchannel_dcolor * dL_dchannel);

				// NOTE: PBR (do not contribute to the alpha/opacity)
                //if (NoV > 0.0f) { // NOTE: the trick from GIR, do not make scene for scenes
					const float dL_dchannel_normal = dL_dpixel_normal[ch];
					atomicAdd(&(dL_dnormals[global_id * C + ch]), dchannel_dcolor * dL_dchannel_normal);
				//}
				const float dL_dchannel_albedo = dL_dpixel_albedo[ch];
				atomicAdd(&(dL_dalbedo[global_id * C + ch]), dchannel_dcolor * dL_dchannel_albedo);
			}
			atomicAdd(&(dL_droughness[global_id]), dchannel_dcolor * dL_dpixel_roughness);
			atomicAdd(&(dL_dmetallic[global_id]), dchannel_dcolor * dL_dpixel_metallic);
			atomicAdd(&(dL_depth[global_id]), dchannel_dcolor * dL_dpixel_depth);


			//NOTE: add semantic gradients(20channel)
			for (int i = 0; i < 20; i++) {
				atomicAdd(&(dL_dsemantic[global_id * 20 + i]), dchannel_dcolor * dL_dpixel_semantic[i]);
			}
			//NOTE: add flow gradients(2channel)
			for (int i = 0; i < 2; i++) {
				atomicAdd(&(dL_dflow[global_id * 2 + i]), dchannel_dcolor * dL_dpixel_flow[i]);
			}

			// NOTE: for opacity
			accum_opacity = last_alpha + (1.f - last_alpha) * accum_opacity;
			dL_dalpha += (1.0f - accum_opacity) * dL_dpixel_opacity;

			dL_dalpha *= T;
			// Update last alpha (to be used in the next iteration)
			last_alpha = alpha;

			// Account for fact that alpha also influences how much of
			// the background color is added if nothing left to blend
			float bg_dot_dpixel = 0;
			for (int i = 0; i < C; i++) {
				bg_dot_dpixel += bg_color[i] * dL_dpixel[i];
			}
			dL_dalpha += (-T_final / (1.f - alpha)) * bg_dot_dpixel;

			// Helpful reusable temporary variables
			const float dL_dG = con_o.w * dL_dalpha;
			const float gdx = G * d.x;
			const float gdy = G * d.y;
			const float dG_ddelx = -gdx * con_o.x - gdy * con_o.y;
			const float dG_ddely = -gdy * con_o.z - gdx * con_o.y;

			// Update gradients w.r.t. 2D mean position of the Gaussian
			atomicAdd(&dL_dmean2D[global_id].x, dL_dG * dG_ddelx * ddelx_dx);
			atomicAdd(&dL_dmean2D[global_id].y, dL_dG * dG_ddely * ddely_dy);
			const float abs_dL_dmean2D = abs(dL_dG * dG_ddelx * ddelx_dx) + abs(dL_dG * dG_ddely * ddely_dy);
            atomicAdd(&dL_dmean2D[global_id].z, abs_dL_dmean2D);

			// Update gradients w.r.t. 2D covariance (2x2 matrix, symmetric)
			atomicAdd(&dL_dconic2D[global_id].x, -0.5f * gdx * d.x * dL_dG);
			atomicAdd(&dL_dconic2D[global_id].y, -0.5f * gdx * d.y * dL_dG);
			atomicAdd(&dL_dconic2D[global_id].w, -0.5f * gdy * d.y * dL_dG);

			// Update gradients w.r.t. opacity of the Gaussian
			atomicAdd(&(dL_dopacity[global_id]), G * dL_dalpha);
		}
	}
}

__global__ void __launch_bounds__(BLOCK_X * BLOCK_Y)
SSRCUDA(
	int W, int H,
	const float focal_x,
	const float focal_y,
	const float* __restrict__ out_normal,
	const float* __restrict__ out_pos,
	const float* __restrict__ out_rgb,
    const float* __restrict__ out_albedo,
    const float* __restrict__ out_roughness,
    const float* __restrict__ out_metallic,
    const float* __restrict__ out_F0,
	const float* __restrict__ dL_dpixels,
	float* __restrict__ dl_albedo,
	float* __restrict__ dl_roughness,
	float* __restrict__ dl_metallic)
{
	auto block = cg::this_thread_block();
	uint2 pix_min = { block.group_index().x * BLOCK_X, block.group_index().y * BLOCK_Y };
	uint2 pix_max = { min(pix_min.x + BLOCK_X, W), min(pix_min.y + BLOCK_Y , H) };
	uint2 pix = { pix_min.x + block.thread_index().x, pix_min.y + block.thread_index().y };
	uint32_t pix_id = W * pix.y + pix.x;
    float3 pos = {out_pos[pix_id], out_pos[1 * H * W + pix_id], out_pos[2 * H * W + pix_id]};
	const float kernelSize = 32.0;
	// const float radius = 0.15;
	// const float bias = -0.0005;
	const float radius = 0.8;
	const float bias = -0.01;
	int step = 16;

    float3 diffuse = {0.0f, 0.0f, 0.0f}; 
    float3 specular = {0.0f, 0.0f, 0.0f};                                                                                                 
	float3 normal_un = {out_normal[pix_id], out_normal[1 * H * W + pix_id], out_normal[2 * H * W + pix_id]};
	float3 normal = normalize(normal_un);
    float3 N = normal;
    float3 up = {0.0f, 1.0f, 0.0f};
    float rndot = dot(up, normal); 
	float3 untangent = {up.x - normal.x * rndot, up.y - normal.y * rndot, up.z - normal.z * rndot};
	float3 tangent = normalize(untangent);
	float3 bitangent = cross(normal, tangent);
    float TBN[9];
	TBN[0] = tangent.x;
	TBN[1] = tangent.y;
	TBN[2] = tangent.z;
	TBN[3] = bitangent.x;
	TBN[4] = bitangent.y;
	TBN[5] = bitangent.z;
	TBN[6] = normal.x;
	TBN[7] = normal.y;
	TBN[8] = normal.z;


    float3 albedo = {out_albedo[pix_id], out_albedo[1 * H * W + pix_id], out_albedo[2 * H * W + pix_id]};
    float3 F0 = {out_F0[pix_id], out_F0[1 * H * W + pix_id], out_F0[2 * H * W + pix_id]};
    float roughness = out_roughness[pix_id];
    float metallic = out_metallic[pix_id];

    float3 V = normalize(-pos);
    float3 F = fresnelSchlick(fmaxf(dot(N, V), 0.00000001), F0);
    float3 kS = F;
    float3 kD = {1.0 - kS.x, 1.0 - kS.y, 1.0 - kS.z};
    kD.x *= 1.0 - metallic;
    kD.y *= 1.0 - metallic;
    kD.z *= 1.0 - metallic;

    float sampleDelta = 0.0625 * M_PIf;
    float nrSamples = 0.0; 
    for(float phi = 0.0; phi < 2.0 * M_PIf; phi += sampleDelta)
    {
        for(float theta = 0.0; theta <= 0.5 * M_PIf; theta += sampleDelta * 0.5)
        {
        // spherical to cartesian (in tangent space)
            float3 tangentSample = {sinf(theta) * cosf(phi),  sinf(theta) * sinf(phi), cosf(theta)};
            tangentSample = normalize(tangentSample);
        // tangent space to view
            float3 sampleVec = transformVec3x3(tangentSample, TBN);
            float3 samplePos = {0.0f, 0.0f, 0.0f};
		    for(int j = 8; j < step; ++j)
		    {
			    samplePos.x = pos.x + sampleVec.x * j * (1 + pos.z / 100) * (1 + pos.z / 100 ) * radius / step; 
			    samplePos.y = pos.y + sampleVec.y * j * (1 + pos.z / 100) * (1 + pos.z / 100)* radius / step; 
			    samplePos.z = pos.z + sampleVec.z * j * (1 + pos.z / 100) * (1 + pos.z / 100) * radius / step; 
			    float cx = float(W) / 2.0f, cy = float(H) / 2.0f;
			    int2 depth_id = get_coord(cx, cy, focal_x, focal_y, samplePos);
			    if (depth_id.x < 0)
				    break;
			    else if (depth_id.x > W - 1)
				    break;
			    if (depth_id.y < 0)
				    break;
			    else if (depth_id.y > H - 1)
				    break;
			    float3 rgb = {out_rgb[W * depth_id.y + depth_id.x], out_rgb[H * W + W * depth_id.y + depth_id.x], out_rgb[2 * H * W + W * depth_id.y + depth_id.x]}; 
				float sampleDepth = out_pos[2 * H * W + W * depth_id.y + depth_id.x]; 
			    if (sampleDepth <= samplePos.z + bias && sampleDepth >= samplePos.z - 0.05)
			    {
					diffuse.x += rgb.x * cosf(theta) * sinf(theta);
                    diffuse.y += rgb.y * cosf(theta) * sinf(theta);
                    diffuse.z += rgb.z * cosf(theta) * sinf(theta);
                    nrSamples++;
				    break;
			    }
		    }
        }
    }
	if(nrSamples > 0.0){
		diffuse.x = M_PIf * diffuse.x * (1.0 / float(nrSamples)) *  kD.x;
		diffuse.y = M_PIf * diffuse.y * (1.0 / float(nrSamples)) *  kD.y;
    	diffuse.z = M_PIf * diffuse.z * (1.0 / float(nrSamples)) *  kD.z;
	}
    else{
		diffuse.x = 0.0;
		diffuse.y = 0.0;
    	diffuse.z = 0.0;
	}
   
	// nrSamples = 0.0; 
    // const uint SAMPLE_COUNT = 64;      
    // for(uint i = 0u; i < SAMPLE_COUNT; ++i)
    // {
    //     float3 samplePos = {0.0f, 0.0f, 0.0f};
    //     float2 Xi = Hammersley(i, SAMPLE_COUNT);
    //     float3 Half = ImportanceSampleGGX(Xi, N, roughness);
    //     float3 L = normalize(2.0 * dot(V, Half) * Half - V);
    //     float NdotL = fmaxf(dot(N, L), 0.0);
    //     if(NdotL > 0.0)
    //     {
    //         for(int j = 4; j < step; ++j)
	// 	    {
	// 		    samplePos.x = pos.x + L.x * j * (1 + pos.z / 100) * (1 + pos.z / 100 ) * radius / step; 
	// 		    samplePos.y = pos.y + L.y * j * (1 + pos.z / 100) * (1 + pos.z / 100)* radius / step; 
	// 		    samplePos.z = pos.z + L.z * j * (1 + pos.z / 100) * (1 + pos.z / 100) * radius / step; 
	// 		    float cx = float(W) / 2.0f, cy = float(H) / 2.0f;
	// 		    int2 depth_id = get_coord(cx, cy, focal_x, focal_y, samplePos);
	// 		    if (depth_id.x < 0)
	// 			    break;
	// 		    else if (depth_id.x > W - 1)
	// 			    break;
	// 		    if (depth_id.y < 0)
	// 			    break;
	// 		    else if (depth_id.y > H - 1)
	// 			    break;
	// 		    float3 rgb = {out_rgb[W * depth_id.y + depth_id.x], out_rgb[H * W + W * depth_id.y + depth_id.x], out_rgb[2 * H * W + W * depth_id.y + depth_id.x]}; 
	// 			float sampleDepth = out_pos[2 * H * W + W * depth_id.y + depth_id.x]; 
	// 		    if (sampleDepth <= samplePos.z + bias && sampleDepth >= samplePos.z - 0.15)
	// 		    {
				    
    //                 float attenuation = 1.0 / ((samplePos.x-pos.x)*(samplePos.x-pos.x)+(samplePos.y-pos.y)*(samplePos.y-pos.y)+(samplePos.z-pos.z)*(samplePos.z-pos.z)+0.0001);
    //                 float3 radiance = {rgb.x * attenuation, rgb.y * attenuation, rgb.z * attenuation};
    //                 float NDF = DistributionGGX(N, Half, roughness);        
    //                 float G = GeometrySmith(N, V, L, roughness);      
    //                 float3 nominator = {NDF * G * F.x, NDF * G * F.y, NDF * G * F.z};
    //                 float denominator = 4.0 * fmaxf(dot(N, V), 0.0) * fmaxf(dot(N, L), 0.0) + 0.001; 
    //                 float3 spec = {nominator.x / denominator, nominator.y / denominator, nominator.z / denominator};               
    //                 specular.x += spec.x * radiance.x * NdotL; 
    //                 specular.y += spec.y * radiance.y * NdotL; 
    //                 specular.z += spec.z * radiance.z * NdotL; 
	// 				nrSamples++;
	// 			    break;
	// 		    }
	// 	    }
    //     }
    // }

    dl_albedo[pix_id] = diffuse.x * dL_dpixels[pix_id];
    dl_albedo[1 * H * W + pix_id] = diffuse.y * dL_dpixels[1 * H * W + pix_id];
    dl_albedo[2 * H * W + pix_id] = diffuse.z * dL_dpixels[2 * H * W + pix_id];	
	dl_roughness[pix_id] = 0.0f;
    dl_roughness[1 * H * W + pix_id] = 0.0f;
    dl_roughness[2 * H * W + pix_id] = 0.0f;
	dl_metallic[pix_id] = 0.0f;
    dl_metallic[1 * H * W + pix_id] = 0.0f;
    dl_metallic[2 * H * W + pix_id] = 0.0f;	
	// color[pix_id] = diffuse.x + specular.x * (1.0 / float(nrSamples));
    // color[1 * H * W + pix_id] = diffuse.y + specular.y * (1.0 / float(nrSamples));
    // color[2 * H * W + pix_id] = diffuse.z + specular.z * (1.0 / float(nrSamples));	
}

void BACKWARD::preprocess(
	const int P, int D, int M,
	const float focal_x, float focal_y,
	const float tan_fovx, float tan_fovy,
	const float3* means3D,
	const int* radii,
	const float* shs,
	const bool* clamped,
	const glm::vec3* scales,
	const glm::vec4* rotations,
	const float scale_modifier,
	const float* cov3Ds,
	const float* viewmatrix,
	const float* projmatrix,
	const glm::vec3* campos,
	const float3* dL_dmean2D,
	const float* dL_dconic,
	const float* dL_depth,
	glm::vec3* dL_dmean3D,
	float* dL_dcolor,
	float* dL_dcov3D,
	float* dL_dsh,
	glm::vec3* dL_dscale,
	glm::vec4* dL_drot)
{
	// Propagate gradients for the path of 2D conic matrix computation. 
	// Somewhat long, thus it is its own kernel rather than being part of 
	// "preprocess". When done, loss gradient w.r.t. 3D means has been
	// modified and gradient w.r.t. 3D covariance matrix has been computed.	
	computeCov2DCUDA<<<(P + 255) / 256, 256>>>(
		P,
		means3D,
		radii,
		cov3Ds,
		focal_x,
		focal_y,
		tan_fovx,
		tan_fovy,
		viewmatrix,
		dL_dconic,
		dL_depth,
		(float3*)dL_dmean3D,
		dL_dcov3D);

	// Propagate gradients for remaining steps: finish 3D mean gradients,
	// propagate color gradients to SH (if desireD), propagate 3D covariance
	// matrix gradients to scale and rotation.
	preprocessCUDA<NUM_CHANNELS><<<(P + 255) / 256, 256>>>(
		P, D, M,
		(float3*)means3D,
		radii,
		shs,
		clamped,
		(glm::vec3*)scales,
		(glm::vec4*)rotations,
		scale_modifier,
		projmatrix,
		campos,
		(float3*)dL_dmean2D,
		(glm::vec3*)dL_dmean3D,
		dL_dcolor,
		dL_dcov3D,
		dL_dsh,
		dL_dscale,
		dL_drot);
}

void BACKWARD::render(
	const dim3 grid, const dim3 block,
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
	const float* semantic, //新增
	const float* flow, //新增
	const float* final_Ts,
	const uint32_t* n_contrib,
	const float* dL_dpixels_depth,
	const float* dL_dpixels,
	const float* dL_dpixels_opacity,
	const float* dL_dpixels_normal,
	const float* dL_dpixels_albedo,
	const float* dL_dpixels_roughness,
	const float* dL_dpixels_metallic,
	const float* dL_dpixels_semantic, //新增
	const float* dL_dpixels_flow, //新增
	float3* dL_dmean2D,
	float4* dL_dconic2D,
	float* dL_depth,
	float* dL_dopacity,
	float* dL_dcolors,
	float* dL_dnormals,
	float* dL_dalbedo,
	float* dL_droughness,
	float* dL_dmetallic,
	float* dL_dsemantic, //新增
	float* dL_dflow) //新增
{
	renderCUDA<NUM_CHANNELS><<<grid, block>>>(
		W, H,
		means3D,
		cam_pos,
		ranges,
		point_list,
		bg_color,
		means2D,
		conic_opacity,
		colors,
		normal,
		albedo,
		roughness,
		metallic,
		semantic, //新增
		flow, //新增
		final_Ts,
		n_contrib,
		dL_dpixels_depth,
		dL_dpixels,
		dL_dpixels_opacity,
		dL_dpixels_normal,
		dL_dpixels_albedo,
		dL_dpixels_roughness,
		dL_dpixels_metallic,
		dL_dpixels_semantic, //新增
		dL_dpixels_flow,
		dL_dmean2D,
		dL_dconic2D,
		dL_depth,
		dL_dopacity,
		dL_dcolors,
		dL_dnormals,
		dL_dalbedo,
		dL_droughness,
		dL_dmetallic,
		dL_dsemantic, //新增
		dL_dflow
	);
}

void BACKWARD::SSR(
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
	float* dl_metallic) {
	SSRCUDA<<<grid, block>>>(
		W, H,
		focal_x,
		focal_y,
		out_normal,
		out_pos,
		out_rgb,
		out_albedo,
		out_roughness,
		out_metallic,
		out_F0,
		dL_dpixels,
		dl_albedo,
		dl_roughness,
		dl_metallic
	);
}