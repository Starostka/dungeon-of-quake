#version 330

in Vec2 fragTexCoord;
in Vec4 fragColor;
in Vec3 fragPosition;
in Vec3 fragNormal;

uniform sampler2D texture0;
uniform sampler2D texture1;
uniform sampler2D texture2;
uniform Vec4 colDiffuse;
uniform Vec3 camPos;
uniform Vec4 fogColor;

out Vec4 finalColor;


float rand01(const in Vec2 uv) {
	return fract(sin(dot(uv, Vec2(12.98194798, 78.233283))) * 43758.5952453);
}

// simplex 3d
// discontinuous pseudorandom uniformly distributed in [-0.5, +0.5]^3
Vec3 simplex_rand3(const in Vec3 c) {
	float j = 4096.0 * sin(dot(c,Vec3(17.0, 59.4, 15.0)));
	Vec3 r;
	r.z = fract(512.0 * j);
	j *= 0.125;
	r.x = fract(512.0 * j);
	j *= 0.125;
	r.y = fract(512.0 * j);
	return r-0.5;
}

// skew constants for 3d simplex functions
const float F3 =  0.3333333;
const float G3 =  0.1666667;
// 3d simplex noise
float simplex3d(Vec3 point) {
	// 1. find current tetrahedron T and it's four vertices
	// s, s+i1, s+i2, s+1.0 - absolute skewed (integer) coordinates of T vertices
	// x, x1, x2, x3 - unskewed coordinates of point relative to each of T vertices
	// calculate s and x
	Vec3 s = floor(point + dot(point, Vec3(F3)));
	Vec3 x = point - s + dot(s, Vec3(G3));
	// calculate i1 and i2
	Vec3 e = step(Vec3(0.0), x - x.yzx);
	Vec3 i1 = e*(1.0 - e.zxy);
	Vec3 i2 = 1.0 - e.zxy * (1.0 - e);
	// x1, x2, x3
	Vec3 x1 = x - i1 + G3;
	Vec3 x2 = x - i2 + 2.0 * G3;
	Vec3 x3 = x - 1.0 + 3.0 * G3;
	// 2. find four surflets and store them in d
	Vec4 w;
	Vec4 d;
	// calculate surflet weights
	w.x = dot(x, x);
	w.y = dot(x1, x1);
	w.z = dot(x2, x2);
	w.w = dot(x3, x3);
	// w fades from 0.6 at the center of the surflet to 0.0 at the margin
	w = max(0.6 - w, 0.0);
	// calculate surflet components
	d.x = dot(simplex_rand3(s), x);
	d.y = dot(simplex_rand3(s + i1), x1);
	d.z = dot(simplex_rand3(s + i2), x2);
	d.w = dot(simplex_rand3(s + 1.0), x3);
	// multiply d by w^4
	w *= w;
	w *= w;
	d *= w;
	// 3. return the sum of the four surflets
	return dot(d, Vec4(52.0));
}

// const matrices for 3d rotation
const Mat3 rot1 = Mat3(-0.37, 0.36, 0.85,-0.14,-0.93, 0.34,0.92, 0.01,0.4);
const Mat3 rot2 = Mat3(-0.55,-0.39, 0.74, 0.33,-0.91,-0.24,0.77, 0.12,0.63);
const Mat3 rot3 = Mat3(-0.71, 0.52,-0.47,-0.08,-0.72,-0.68,-0.7,-0.45,0.56);
// directional artifacts can be reduced by rotating each octave
float simplex3d_fractal(Vec3 m) {
	return 0.5333333 * simplex3d(m * rot1)
		+ 0.2666667 * simplex3d(2.0 * m * rot2)
		+ 0.1333333 * simplex3d(4.0 * m * rot3)
		+ 0.0666667 * simplex3d(8.0 * m);
}

Vec3 toGridPos(Vec3 pos) { return floor(pos*64.0)/64.0; } // pixel/texture grid!

#define TILE_WIDTH 30.0

void main() {
	// Texel color fetching from texture sampler
	Vec2 uv = fragTexCoord;
	Vec4 texelColor = texture(texture0, uv)*colDiffuse*fragColor;
	float dist = length(fragPosition - camPos);

	Vec3 col = texelColor.rgb;
	Vec2 griduv = floor(uv*64.0)/64.0;
	//col += Vec3(abs(fragNormal.x)*0.04 + fragNormal.y*0.04);
	float tileCenterDist = (pow(abs(mod(griduv.x,1.0) - 0.5)*2.0, 3.0)+pow(abs(mod(griduv.y,1.0) - 0.5)*2.0, 3.0))*0.5;
	Vec3 gridpos = toGridPos(fragPosition*1.0001/TILE_WIDTH);
	float gridnoise = simplex3d(gridpos*1.0/4.0);
	gridnoise += simplex3d(gridpos*Vec3(2.0,0.3,2.0))*0.5;
	gridnoise -= tileCenterDist*0.7;
	gridnoise += sign(gridnoise)*0.2;
	col += Vec3(gridnoise*0.06);
	//col = Vec3(pow(tileCenterDist, 0.5));
	//col *= Vec3(1.0) + Vec3(abs(gridnoise)*tileCenterDist*simplex3d(toGridPos(fragPosition/TILE_WIDTH)*0.4)*10.0);
	//Vec3 tilepos = floor(fragPosition/TILE_WIDTH - fragNormal*0.001 + Vec3(0,0.5,0));
	//col += texelColor.rgb * gridnoise * 2.0;
	//col = tilepos*0.1;

	//col = Vec3(dot(col, Vec3(0.299, 0.587, 0.114)));

	float fog = pow(dist * 0.001 * fogColor.a, 0.6);
	col = mix(col, fogColor.rgb, clamp(fog, 0.0, 1.0));

	finalColor = Vec4(col, 1.0);
}