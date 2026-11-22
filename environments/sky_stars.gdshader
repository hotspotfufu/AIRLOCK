shader_type sky;
// Deep space seen through the observation windows: black with stars.
float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 cell = floor(d * 140.0);
	float h = hash(cell);
	float star = step(0.9965, h) * (0.4 + 0.6 * hash(cell + 7.0));
	vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.9, 0.75), hash(cell + 3.0));
	COLOR = tint * star * 1.6 + vec3(0.002, 0.003, 0.006);
}
