to_yaw_pitch_r :: (using v : Vector3) -> yaw:float, pitch:float, r:float {
	rxz := sqrt(x * x + z * z);
	return atan2(z, x), atan2(y, rxz), sqrt(x * x + y * y + z * z);
}
from_yaw_pitch_r :: (yaw : float, pitch : float, r : float) -> Vector3 {
	return r * Vector3.{cos(pitch) * cos(yaw), sin(pitch), cos(pitch) * sin(yaw)};
}
mix :: (c1 : Color, c2 : Color, x : float) -> Color {
	mix :: (a : u8, b : u8, x : float) -> u8 {
		return cast(u8)(a * (1 - x) + b * x);
	}
	return .{
		mix(c1.r, c2.r, x),
		mix(c1.g, c2.g, x),
		mix(c1.b, c2.b, x),
		mix(c1.a, c2.a, x)
	};
}
