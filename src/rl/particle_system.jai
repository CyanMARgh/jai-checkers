Particle_System :: struct {
	vao, vbo, instance_vbo : u32;
	shader_draw : Shader;

	max_particles : u32;
	buffer_cpu	: [..]Particle_CPU_Part;
	buffer_gpu	: [..]Particle_GPU_Part;

	is_fresh := false;
}
init :: (using particle_system : *Particle_System, _max_particles :u32= 100000) {
	add_attrib :: (size : int) #expand {
		glEnableVertexAttribArray(xx attr_index);
		glVertexAttribPointer(xx attr_index, size, GL_FLOAT, GL_FALSE, size_of(Particle_GPU_Part), xx offset); // position
		glVertexAttribDivisor(xx attr_index, 1);
		offset += size * 4;
		attr_index += 1;
	}

	max_particles = _max_particles;
	glGenVertexArrays(1, *vao);
	glGenBuffers(1, *instance_vbo);
	glGenBuffers(1, *vbo);

	glBindVertexArray(vao);
		glBindBuffer(GL_ARRAY_BUFFER, vbo);
		glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
		glBufferData(GL_ARRAY_BUFFER, size_of(Particle_GPU_Part) * max_particles, null, GL_STATIC_DRAW);
		offset := 0;
		attr_index := 0;
		add_attrib(3);
		add_attrib(1);
		add_attrib(3);
		add_attrib(3);
		glBindBuffer(GL_ARRAY_BUFFER, 0);
	glBindVertexArray(0);

	shader_draw = LoadShaderFromMemory(SRC_VERT_PARTICLE, SRC_FRAG_PARTICLE_CHECKERS);
}
deinit :: (using particle_system : *Particle_System) {
	glDeleteVertexArrays(1, *vao);
	glDeleteBuffers(1, *instance_vbo);
	array_reset(*buffer_cpu);
	array_reset(*buffer_gpu);
	UnloadShader(shader_draw);
}
draw :: (using particle_system : *Particle_System) {
	EnableShader(shader_draw.id); defer DisableShader();
	if IsWindowResized() is_fresh = false;
	if !is_fresh {
		is_fresh = true;
		ratio := cast(float)GetScreenWidth() / GetScreenHeight();
		set_uniform(shader_draw.id, "u_width_over_height", ratio);
	}
	_mv := GetMatrixModelview();
	_p := GetMatrixProjection();
	mat_mvp := MatrixMultiply(_mv, _p);

	DisableDepthMask();
		SetUniformMatrix(shader_draw.locs[SHADER_LOC_MATRIX_MVP], mat_mvp);
		glBindVertexArray(vao);
		glDrawArraysInstanced(GL_TRIANGLES, 0, 6, xx buffer_gpu.count);
		glBindVertexArray(0);
	EnableDepthMask();
}
simulate :: (using particle_system : *Particle_System, dt : float) {
	i := 0;
	while i < buffer_cpu.count {
		buffer_gpu[i].time -= dt;
		if buffer_gpu[i].time < 0 {
			count := buffer_cpu.count - 1;
			buffer_cpu[i] = buffer_cpu[count]; buffer_cpu.count = count;
			buffer_gpu[i] = buffer_gpu[count]; buffer_gpu.count = count;
		} else {
			buffer_gpu[i].position += buffer_cpu[i].velocity * dt;
			buffer_cpu[i].velocity += Vector3.{0, -6, 0} * dt;
			buffer_cpu[i].velocity *= 1 - dt * 3;
			i += 1;
		}
	}
	commit_buffer(particle_system);
}
emit :: (using particle_system : *Particle_System, center : Vector3, color : Color, count : int) {
	// print("emit at: %\n", center);
	emit(particle_system, count, center, center, Vector3.{xx color.r, xx color.g, xx color.b} / 255.);
}
reset :: (using particle_system : *Particle_System) {
	array_reset(*buffer_cpu);
	array_reset(*buffer_gpu);
	commit_buffer(particle_system);
}

#scope_file
#import "GL";

MatrixMultiply :: (left : Matrix, right : Matrix) -> Matrix {
    result : Matrix;

    result.m0 = left.m0*right.m0 + left.m1*right.m4 + left.m2*right.m8 + left.m3*right.m12;
    result.m1 = left.m0*right.m1 + left.m1*right.m5 + left.m2*right.m9 + left.m3*right.m13;
    result.m2 = left.m0*right.m2 + left.m1*right.m6 + left.m2*right.m10 + left.m3*right.m14;
    result.m3 = left.m0*right.m3 + left.m1*right.m7 + left.m2*right.m11 + left.m3*right.m15;
    result.m4 = left.m4*right.m0 + left.m5*right.m4 + left.m6*right.m8 + left.m7*right.m12;
    result.m5 = left.m4*right.m1 + left.m5*right.m5 + left.m6*right.m9 + left.m7*right.m13;
    result.m6 = left.m4*right.m2 + left.m5*right.m6 + left.m6*right.m10 + left.m7*right.m14;
    result.m7 = left.m4*right.m3 + left.m5*right.m7 + left.m6*right.m11 + left.m7*right.m15;
    result.m8 = left.m8*right.m0 + left.m9*right.m4 + left.m10*right.m8 + left.m11*right.m12;
    result.m9 = left.m8*right.m1 + left.m9*right.m5 + left.m10*right.m9 + left.m11*right.m13;
    result.m10 = left.m8*right.m2 + left.m9*right.m6 + left.m10*right.m10 + left.m11*right.m14;
    result.m11 = left.m8*right.m3 + left.m9*right.m7 + left.m10*right.m11 + left.m11*right.m15;
    result.m12 = left.m12*right.m0 + left.m13*right.m4 + left.m14*right.m8 + left.m15*right.m12;
    result.m13 = left.m12*right.m1 + left.m13*right.m5 + left.m14*right.m9 + left.m15*right.m13;
    result.m14 = left.m12*right.m2 + left.m13*right.m6 + left.m14*right.m10 + left.m15*right.m14;
    result.m15 = left.m12*right.m3 + left.m13*right.m7 + left.m14*right.m11 + left.m15*right.m15;

    return result;
}
set_uniform :: (shader : u32, name : *u8, value : float) {
	loc := glGetUniformLocation(shader, name);
	glUniform1f(loc, value);
}
set_uniform :: (shader : u32, name : *u8, value : s32) {
	loc := glGetUniformLocation(shader, name);
	glUniform1i(loc, value);
}
set_uniform :: (shader : u32, name : *u8, value : Vector3) {
	loc := glGetUniformLocation(shader, name);
	glUniform3f(loc, value.x, value.y, value.z);
}
set_uniform :: (shader : u32, name : *u8, value : Vector4) {
	loc := glGetUniformLocation(shader, name);
	glUniform4f(loc, value.x, value.y, value.z, value.w);
}
set_uniform :: (shader : u32, name : *u8, value : Color) {
	set_uniform(shader, name, Vector3.{xx value.r, xx value.g, xx value.b} / 255.);
}

Particle_CPU_Part :: struct {
	velocity : Vector3;
}
Particle_GPU_Part :: struct {
	position : Vector3;
	time : float;
	base_color : Vector3;
	aspect_color : Vector3;
}

commit_buffer :: (using particle_system : *Particle_System) {
	glBindBuffer(GL_ARRAY_BUFFER, instance_vbo);
	glBufferSubData(GL_ARRAY_BUFFER, 0, size_of(Particle_GPU_Part) * buffer_gpu.count, buffer_gpu.data);	
	glBindBuffer(GL_ARRAY_BUFFER, 0);
}
emit :: (using particle_system : *Particle_System, count : int, center_0 : Vector3, center_1 : Vector3, color : Vector3) {
	to_emit := min(count, max_particles - buffer_cpu.count);
	for i : 0..to_emit-1 {
		center := center_0 + (center_1 - center_0) * (cast(float)i / (to_emit-1));
		direction := Vector3.{random_get_within_range(-1, 1), random_get_within_range(-1, 1), random_get_within_range(-1, 1)};
		direction /= length(direction);
		P0 := array_add(*buffer_cpu);
		P1 := array_add(*buffer_gpu);

		P0.velocity = direction * random_get_within_range(2.5, 3.5) + Vector3.{0, 2, 0};

		P1.time = random_get_within_range(.5, 1.5);
		P1.position = center;
		// P1.base_color = .{1.5, .5, .2};
		P1.base_color = color;
		P1.aspect_color = .{1., 1., 1.};
	}
}

SRC_VERT_PARTICLE :: #string GLSL
	#version 410 core

	in vec3 a_position;
	in float a_time;
	in vec3 a_base_color;
	in vec3 a_aspect_color;

	uniform mat4 mvp;
	uniform float u_width_over_height;

	out struct VO {
		vec2 uv;
		vec3 base_color;
		vec3 aspect_color;
	} vo;

	void main() {
		float points[12] = float[12](0, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1, 1);
		vec2 p = vec2(points[gl_VertexID << 1], points[(gl_VertexID << 1) | 1]);
		float size = (1 - 1 / (1 + a_time * 1)) * .5; 
		// float size = a_time > 0 ? 0.05 : 0;
		vec2 uv = p * 2 - 1;
		vo.uv = uv;
		vo.aspect_color = a_aspect_color;
		vo.base_color = a_base_color;
		gl_Position = (mvp * vec4(a_position, 1)) + vec4((uv * size) * vec2(1. / u_width_over_height, 1), 0, 0);
	}
GLSL
SRC_FRAG_PARTICLE_CHECKERS :: #string GLSL
	#version 410 core
	in struct VO {
		vec2 uv;
		vec3 base_color;
		vec3 aspect_color;
	} vo;
	out vec4 o_color;	
	void main() {
		float r = length(vo.uv);
		o_color = vec4(r < .5 ? vo.aspect_color : vo.base_color, r < 1 ? 1 : 0);
	}
GLSL
// Particle_System :: struct {
// 	particles_count : u32;
// 	is_fresh := false;

// 	vao, vbo : u32;
// 	draw_shader : Shader;
// 	particles_counter : u32;
// 	shader_simulate : u32;
// 	shader_emit : u32;
// }
// init :: (using particle_system : *Particle_System) {
// 	vao = LoadVertexArray();
// 	// EnableVertexArray(vao); defer DisableVertexArray();
// 	vbo = LoadVertexBuffer(null, xx(particles_count * size_of(Particle)), true);

// 	draw_shader = LoadShaderFromMemory(GLSL_VERT_PARTICLE, GLSL_FRAG_PARTICLE);
// 	particles_counter = get_atomic_counter();
// 	shader_simulate = get_compute_shader(GLSL_COMP_PARTICLE_SIMULATE);
// 	shader_emit = get_compute_shader(GLSL_COMP_PARTICLE_EMIT);
// }
// deinit :: (using particle_system : *Particle_System) {
// 	glDeleteProgram(shader_emit);
// 	glDeleteProgram(shader_simulate);
// 	clear_atomic_counter(particles_counter);
// 	UnloadShader(draw_shader);

// 	UnloadVertexArray(vao);
// 	UnloadVertexBuffer(vbo);
// }
// reset :: (using particle_system : *Particle_System) {
// 	glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, particles_counter);
// 	val :u32= 0;
// 	glBufferSubData(GL_ATOMIC_COUNTER_BUFFER, 0, size_of(u32), *val);
// 	glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, 0);
// 	particles_count = 0;
// 	// print("reset!\n");
// }
// draw :: (using particle_system : *Particle_System) {
// 	EnableShader(draw_shader.id); defer DisableShader();
//     EnableVertexArray(vao); defer DisableVertexArray();

// 	particles_count = get_value(particles_counter);
// 	// print("particles_counter = %\n", particles_count);

// 	glBindVertexArray(vao);
// 	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, vbo);

// 	mat_mvp := MatrixMultiply(GetMatrixModelview(), GetMatrixProjection());
// 	SetUniformMatrix(draw_shader.locs[SHADER_LOC_MATRIX_MVP], mat_mvp);
// 	if IsWindowResized() is_fresh = false;
// 	if !is_fresh {
// 		is_fresh = true;
// 		ratio := cast(float)GetScreenHeight() / GetScreenWidth();
// 		set_uniform(draw_shader.id, "ratio", ratio);
// 	}
// 	// print("particles_count = %\n", particles_count);
// 	DisableDepthMask();
// 		glDrawArrays(GL_TRIANGLES, 0, xx (particles_count * 6));
// 	EnableDepthMask();
// }
// simulate :: (using particle_system : *Particle_System, delta_time : float) {
// 	glUseProgram(shader_simulate);
// 	set_uniform(shader_simulate, "u_dt", delta_time);

// 	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, particle_system.vbo);
// 	glBindBufferBase(GL_ATOMIC_COUNTER_BUFFER, 0, particles_counter);

// 	glDispatchCompute(xx particles_count, 1, 1);
// 	glMemoryBarrier(GL_ALL_BARRIER_BITS);
// }
// emit :: (using particle_system : *Particle_System, point : Vector3, new_particles_count := 100, speed_factor := 1.,
// 	base_color := RED, base_variation := Vector3.{.1, 0, 0},
// 	aspect_color := WHITE, aspect_variation := Vector3.{}
// ) {
// 	glUseProgram(shader_emit);
// 	set_uniform(shader_emit, "u_random_state", __random_state);
// 	set_uniform(shader_emit, "u_center", point);
// 	set_uniform(shader_emit, "u_base_color", base_color);
// 	set_uniform(shader_emit, "u_base_variation", base_variation);
// 	set_uniform(shader_emit, "u_aspect_color", aspect_color);
// 	set_uniform(shader_emit, "u_aspect_variation", aspect_variation);
// 	set_uniform(shader_emit, "u_speed_factor", speed_factor);

// 	__random_state += 1;

// 	glBindBufferBase(GL_SHADER_STORAGE_BUFFER, 0, vbo);
// 	glBindBufferBase(GL_ATOMIC_COUNTER_BUFFER, 0, particles_counter);

// 	glDispatchCompute(xx new_particles_count, 1, 1);
// 	glMemoryBarrier(GL_ALL_BARRIER_BITS);		
// }

// #scope_file
// #import "GL";

// Particle :: struct {
// 	lifetime : float;
// 	pos, velocity, acceleration : Vector3;
// 	dragg : float;
// 	base_color, aspect_color : Vector3;
// 	next : u32;
// }

// MatrixMultiply :: (left : Matrix, right : Matrix) -> Matrix {
//     result : Matrix;

//     result.m0 = left.m0*right.m0 + left.m1*right.m4 + left.m2*right.m8 + left.m3*right.m12;
//     result.m1 = left.m0*right.m1 + left.m1*right.m5 + left.m2*right.m9 + left.m3*right.m13;
//     result.m2 = left.m0*right.m2 + left.m1*right.m6 + left.m2*right.m10 + left.m3*right.m14;
//     result.m3 = left.m0*right.m3 + left.m1*right.m7 + left.m2*right.m11 + left.m3*right.m15;
//     result.m4 = left.m4*right.m0 + left.m5*right.m4 + left.m6*right.m8 + left.m7*right.m12;
//     result.m5 = left.m4*right.m1 + left.m5*right.m5 + left.m6*right.m9 + left.m7*right.m13;
//     result.m6 = left.m4*right.m2 + left.m5*right.m6 + left.m6*right.m10 + left.m7*right.m14;
//     result.m7 = left.m4*right.m3 + left.m5*right.m7 + left.m6*right.m11 + left.m7*right.m15;
//     result.m8 = left.m8*right.m0 + left.m9*right.m4 + left.m10*right.m8 + left.m11*right.m12;
//     result.m9 = left.m8*right.m1 + left.m9*right.m5 + left.m10*right.m9 + left.m11*right.m13;
//     result.m10 = left.m8*right.m2 + left.m9*right.m6 + left.m10*right.m10 + left.m11*right.m14;
//     result.m11 = left.m8*right.m3 + left.m9*right.m7 + left.m10*right.m11 + left.m11*right.m15;
//     result.m12 = left.m12*right.m0 + left.m13*right.m4 + left.m14*right.m8 + left.m15*right.m12;
//     result.m13 = left.m12*right.m1 + left.m13*right.m5 + left.m14*right.m9 + left.m15*right.m13;
//     result.m14 = left.m12*right.m2 + left.m13*right.m6 + left.m14*right.m10 + left.m15*right.m14;
//     result.m15 = left.m12*right.m3 + left.m13*right.m7 + left.m14*right.m11 + left.m15*right.m15;

//     return result;
// }
// make_shader_part :: (src : *u8, type : GLuint) -> u32 {
// 	id := glCreateShader(GL_COMPUTE_SHADER);
// 	glShaderSource(id, 1, *src, null);
// 	glCompileShader(id);
// 	succes : s32;
// 	info_log : [512]u8;
// 	glGetShaderiv(id, GL_COMPILE_STATUS, *succes);
// 	if !succes {
// 		glGetShaderInfoLog(id, 512, null, cast(*GLchar) *info_log);
// 		print("failed to compile shader: %\n", to_string(info_log));		
// 		glDeleteShader(id);
// 		return 0;
// 	}
// 	print("shader compiling done\n");
// 	return id;
// }
// get_compute_shader :: (src : *u8) -> u32 {
// 	comp := make_shader_part(src, GL_COMPUTE_SHADER); defer glDeleteShader(comp);
// 	id := glCreateProgram();
// 	glAttachShader(id, comp);
// 	glLinkProgram(id);
// 	succes : s32;
// 	info_log : [512]u8;
// 	glGetProgramiv(id, GL_LINK_STATUS, *succes);
// 	if !succes {
// 		glGetProgramInfoLog(id, 512, null, cast(*GLchar) *info_log);
// 		print("failed to link shader: %\n", to_string(info_log));
// 		glDeleteProgram(id);
// 		return 0;
// 	}
// 	print("shader linking done\n");
// 	return id;	
// }
// get_atomic_counter :: () -> u32 {
// 	id : u32;
// 	glGenBuffers(1, *id);
// 	glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, id);
// 		glBufferData(GL_ATOMIC_COUNTER_BUFFER, size_of(u32), null, GL_DYNAMIC_DRAW);
// 	glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, 0);
// 	return id;
// }
// clear_atomic_counter :: (id : u32) {
// 	glDeleteBuffers(1, *id);
// }
// get_value :: (id : u32) -> u32 {
// 	glBindBuffer(GL_ATOMIC_COUNTER_BUFFER, id);
// 	ptr := glMapBuffer(GL_ATOMIC_COUNTER_BUFFER, GL_READ_ONLY);
// 	val := << cast(*u32) ptr;
// 	glUnmapBuffer(GL_ATOMIC_COUNTER_BUFFER);
// 	return val;
// }
// set_uniform :: (shader : u32, name : *u8, value : float) {
// 	loc := glGetUniformLocation(shader, name);
// 	glUniform1f(loc, value);
// }
// set_uniform :: (shader : u32, name : *u8, value : s32) {
// 	loc := glGetUniformLocation(shader, name);
// 	glUniform1i(loc, value);
// }
// set_uniform :: (shader : u32, name : *u8, value : Vector3) {
// 	loc := glGetUniformLocation(shader, name);
// 	glUniform3f(loc, value.x, value.y, value.z);
// }
// set_uniform :: (shader : u32, name : *u8, value : Vector4) {
// 	loc := glGetUniformLocation(shader, name);
// 	glUniform4f(loc, value.x, value.y, value.z, value.w);
// }
// set_uniform :: (shader : u32, name : *u8, value : Color) {
// 	set_uniform(shader, name, Vector3.{xx value.r, xx value.g, xx value.b} / 255.);
// }
// __random_state : s32;
// GLSL_COMP_PARTICLE_EMIT :: #string GLSL
// 	#version 430 core
// 	layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// 	struct Particle_Sim {
// 		float lifetime;

// 		vec3 pos;
// 		vec3 velocity;
// 		vec3 acceleration;
// 		float dragg;

// 		vec3 base_color;
// 		vec3 aspect_color;

// 		uint next;
// 	};
// 	layout(std430, binding = 0) buffer u_sim_particles {
// 		Particle_Sim sim_particles[];
// 	};
// 	layout (binding = 0) uniform atomic_uint u_alive_counter;

// 	uniform int u_random_state;
// 	uniform vec3 u_center;
// 	uniform float u_speed_factor;

// 	uniform vec3 u_base_color;
// 	uniform vec3 u_base_variation;

// 	uniform vec3 u_aspect_color;
// 	uniform vec3 u_aspect_variation;

// 	vec2 hash22(vec2 p) {
// 		p = p * mat2(127.1, 311.7, 269.5 ,183.3);
// 		p = -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
// 		return sin(p * 6.283);
// 	}
// 	const float PI = 3.14159265;
// 	vec3 hash32(vec2 p) {
// 		vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
// 		p3 += dot(p3, p3.yxz+33.33);
// 		return fract((p3.xxy+p3.yzz)*p3.zyx);
// 	}

// 	vec3 hsv2rgb(vec3 c) {
// 		vec4 K = vec4(1., 2. / 3., 1. / 3., 3.);
// 		return c.z * mix(K.xxx, clamp(abs(fract(c.x + K.xyz) * 6. - K.w) - K.x, 0, 1), c.y);
// 	}
// 	vec3 rgb2hsv(vec3 c) {
// 		float
// 			cMax = max(max(c.r, c.g), c.b),
// 			cMin = min(min(c.r, c.g), c.b),
// 			delta = cMax - cMin;
// 		vec3 hsv = vec3(0, 0, cMax);
// 		if(cMax > cMin){
// 			hsv.y = delta / cMax;
// 			if(c.r == cMax){
// 				hsv.x = (c.g - c.b) / delta;
// 			} else if(c.g == cMax){
// 				hsv.x = 2 + (c.b - c.r) / delta;
// 			} else {
// 				hsv.x = 4 + (c.r - c.g) / delta;
// 			}
// 			hsv.x = fract(hsv.x / 6);
// 		}
// 		return hsv;
// 	}

// 	vec3 gen_color(vec3 col, vec3 H, vec3 variation) {
// 		vec3 hsv = rgb2hsv(col) + (H - .5) * variation;
// 		hsv.x = mod(hsv.x, 1);
// 		return hsv2rgb(hsv);
// 	}

// 	Particle_Sim gen_particle(uint i) {
// 		float fi = float(i);
// 		vec3 H = hash32(vec2(fi, u_random_state));
// 		vec3 phi_y_r = vec3(H.x * 2 * PI, H.y * 2 - 1, (H.z * .3 + 1) * 3);
// 		vec3 speed = vec3(0, 3, 0) + .7 * phi_y_r.z * vec3(vec2(sin(phi_y_r.x), cos(phi_y_r.x)) * sqrt(1 - phi_y_r.y * phi_y_r.y),  phi_y_r.y);
// 		float timer = .4 + .3 * hash22(vec2(fi, u_random_state + 1)).x;

// 		vec3 var = hash32(vec2(fi, u_random_state + 2)) - .5;
	
// 		return Particle_Sim(
// 			timer,
// 			u_center,
// 			speed * u_speed_factor,
// 			vec3(0, -2, 0),
// 			4,
// 			gen_color(u_base_color.rgb, var, u_base_variation),
// 			gen_color(u_aspect_color.rgb, var, u_aspect_variation),
// 			0xFFFFFFFF
// 		);
// 	}

// 	void main() {
// 		uint particle_id = atomicCounterIncrement(u_alive_counter);
// 		sim_particles[particle_id] = gen_particle(particle_id);
// 	}
// GLSL
// GLSL_COMP_PARTICLE_SIMULATE :: #string GLSL
// 	#version 430 core
// 	layout(local_size_x = 1, local_size_y = 1, local_size_z = 1) in;

// 	struct Particle_Sim {
// 		float lifetime;
// 		vec3 pos;
// 		vec3 velocity;
// 		vec3 acceleration;
// 		float dragg;

// 		vec3 base_color;
// 		vec3 aspect_color;

// 		uint next;
// 	};
// 	layout(std430, binding = 0) buffer u_sim_particles {
// 		Particle_Sim sim_particles[];
// 	};
// 	layout (binding = 0) uniform atomic_uint u_alive_counter;

// 	uniform float u_dt;

// 	void main() {
// 		int particle_id = int(gl_GlobalInvocationID.x);
// 		uint alive_count = atomicCounter(u_alive_counter);

// 		if(particle_id < alive_count) {
// 			Particle_Sim P = sim_particles[particle_id];
// 			P.velocity.xyz += P.acceleration * u_dt;
// 			P.velocity.xyz *= (1 - P.dragg * u_dt);
// 			P.pos += P.velocity.xyz * u_dt;

// 			P.lifetime -= u_dt;
// 			if(P.lifetime < 0) {
// 				P.next = atomicCounterDecrement(u_alive_counter);
// 			}
// 			sim_particles[particle_id] = P;
// 		}
// 		memoryBarrier();
// 		alive_count = atomicCounter(u_alive_counter);

// 		if(particle_id < alive_count) {
// 			uint repl = particle_id;
// 			int MAX_ITERATIONS = 100;
// 			for(int i = 0; i < MAX_ITERATIONS; i++) {
// 				uint next = sim_particles[repl].next;
// 				if(next == 0xFFFFFFFF) break;
// 				repl = next;
// 			}
// 			sim_particles[particle_id] = sim_particles[repl];
// 		}
// 	}
// GLSL
// GLSL_VERT_PARTICLE :: #string GLSL
// 	#version 430

// 	uniform mat4 mvp;
// 	uniform float ratio = 1;
// 	const float size = .2;

// 	struct Particle_Sim {
// 		float lifetime;
// 		vec3 pos;
// 		vec3 velocity;
// 		vec3 acceleration;
// 		float dragg;

// 		vec3 base_color;
// 		vec3 aspect_color;

// 		uint next;
// 	};
// 	layout(std430, binding = 0) buffer u_sim_particles {
// 		Particle_Sim sim_particles[];
// 	};

// 	struct Particle_Visual {
// 		vec2 uv;
// 		vec3 base_color;
// 		vec3 aspect_color;
// 		float angle;
// 	};
// 	out Particle_Visual particle_visual;

// 	void main() {
// 		int id = gl_VertexID;
// 		int particle_id = id / 6;
// 		int offset_id = id % 6;

// 		vec2 offsets[6] = vec2[6](
// 			vec2(-1,-1),
// 			vec2( 1, 1),
// 			vec2(-1, 1),
// 			vec2(-1,-1),
// 			vec2( 1,-1),
// 			vec2( 1, 1)
// 		);
// 		Particle_Sim particle = sim_particles[particle_id]; 
// 		float time = particle.lifetime;
// 		float scale = time <= 0 ? 0 : 1 - 1 / (20 * time + 1);

// 		vec4 p = mvp * vec4(particle.pos, 1);
// 		vec2 offset = offsets[offset_id];

// 		particle_visual = Particle_Visual(
// 			offset,
// 			particle.base_color.rgb,
// 			particle.aspect_color.rgb,
// 			0
// 		);

// 		gl_Position = p + vec4(offset * vec2(ratio, 1), 0, 0) * size * scale;
// 	}
// GLSL
// GLSL_FRAG_PARTICLE :: #string GLSL
// 	#version 430

// 	struct Particle_Visual {
// 	    vec2 uv;
// 	    vec3 base_color;
// 	    vec3 aspect_color;
// 	    float angle;
// 	};
// 	in Particle_Visual particle_visual;
// 	out vec4 o_color;

// 	void main() {
// 	    float r = length(particle_visual.uv);
// 	    o_color = vec4(r < .5 ? particle_visual.aspect_color : particle_visual.base_color, r < 1 ? 1 : 0);
// 	}
// GLSL