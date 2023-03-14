function getCallbacks_Smith_BMCSystBiol2013()
	cb_Ins_event_bool3 = DiscreteCallback(condition_Ins_event_bool3, affect_Ins_event_bool3!, save_positions=(false, false))

	cb_Ins_event_bool1 = DiscreteCallback(condition_Ins_event_bool1, affect_Ins_event_bool1!, save_positions=(false, false))

	cb_Ins_event_bool2 = DiscreteCallback(condition_Ins_event_bool2, affect_Ins_event_bool2!, save_positions=(false, false))

	return CallbackSet(cb_Ins_event_bool3, cb_Ins_event_bool1, cb_Ins_event_bool2), [isActiveAtTime0_Ins_event_bool3!, isActiveAtTime0_Ins_event_bool1!, isActiveAtTime0_Ins_event_bool2!]
end


function condition_Ins_event_bool3(u, t, integrator)
	t == 2895
end

function affect_Ins_event_bool3!(integrator)
	integrator.p[48] = 1.0
end

function isActiveAtTime0_Ins_event_bool3!(u, p)
	t = 0.0 # Used to check conditions activated at t0=0
	p[48] = 0.0 # Default to being off
	if (t == 2895)
		p[48] = 1.0
	end
end



function condition_Ins_event_bool1(u, t, integrator)
	t == integrator.p[71]
end

function affect_Ins_event_bool1!(integrator)
	integrator.p[29] = 1.0
end

function isActiveAtTime0_Ins_event_bool1!(u, p)
	t = 0.0 # Used to check conditions activated at t0=0
	p[29] = 0.0 # Default to being off
	if (t == p[71])
		p[29] = 1.0
	end
end



function condition_Ins_event_bool2(u, t, integrator)
	t == 2880
end

function affect_Ins_event_bool2!(integrator)
	integrator.p[53] = 1.0
end

function isActiveAtTime0_Ins_event_bool2!(u, p)
	t = 0.0 # Used to check conditions activated at t0=0
	p[53] = 0.0 # Default to being off
	if (t == 2880)
		p[53] = 1.0
	end
end


function computeTstops(u::AbstractVector, p::AbstractVector)
	 return Float64[dualToFloat(2895.0), dualToFloat(p[71]), dualToFloat(2880.0)]
end