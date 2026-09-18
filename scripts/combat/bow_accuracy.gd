extends RefCounted
## 姿态决定实际发射锥角；采样点对称分布，保留初速，不读取敌人隐藏位置。
static func spread_degrees(crouched: bool, moving: bool, airborne: bool) -> float:
	if airborne: return 2.6
	if crouched: return 0.55 if moving else 0.18
	return 1.5 if moving else 0.75

static func deviate(velocity: Vector3, degrees: float, rng: RandomNumberGenerator) -> Vector3:
	var forward := velocity.normalized()
	var right := forward.cross(Vector3.UP if absf(forward.y)<0.99 else Vector3.RIGHT).normalized()
	var up := right.cross(forward).normalized()
	var radius := sqrt(rng.randf())*tan(deg_to_rad(degrees))
	var angle := rng.randf()*TAU
	return (forward+radius*(right*cos(angle)+up*sin(angle))).normalized()*velocity.length()
