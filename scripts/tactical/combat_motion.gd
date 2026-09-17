extends RefCounted
## The weapon and pixel pose sample the same anticipation / strike / recovery.
static func blend(value: float) -> float:
	var t := clampf(value,0,1)
	return t*t*(3-2*t)

static func melee(elapsed: float, windup: float, active: float, total: float, thrust: bool=false) -> Dictionary:
	var angle := 0.0
	var weight := 0.0
	var extension := 0.0
	if elapsed<windup:
		var t := blend(elapsed/windup)
		angle=-0.9*t
		weight=-t
	elif elapsed<windup+active:
		var t := blend((elapsed-windup)/active)
		angle=lerpf(-0.9,0.8,t)
		weight=lerpf(-1,2,t)
		extension=sin(t*PI)*(0.48 if thrust else 0.12)
	else:
		var t := blend((elapsed-windup-active)/maxf(0.01,total-windup-active))
		angle=lerpf(0.8,0,t)
		weight=lerpf(2,0,t)
	return {"angle":angle*(0.25 if thrust else 1.0),"arm":clampi(roundi((angle+0.9)/1.7*24),0,24),"weight":roundi(weight),"extension":extension}
