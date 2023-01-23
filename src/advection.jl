export Advection, MeanWind, ConstantWind

"""
$(SIGNATURES)

A model component that represents the mean wind velocity, where `t` is the independent variable
and `ndims` is the number of dimensions that wind is traveling in.
"""
struct MeanWind <: EarthSciMLODESystem
    sys::ODESystem
    function MeanWind(t, ndims) 
        uvars = (@variables u(t) v(t) w(t))[1:ndims]
        new(ODESystem(Equation[], t, uvars, []; name=:meanwind))
    end
end

"""
$(SIGNATURES)

Apply advection to a model.

# Example

```@example
using EarthSciMLBase
using DomainSets, MethodOfLines, ModelingToolkit, Plots

# Create our independent variable `t` and our partially-independent variable `x`.
@parameters t, x

# Create our ODE system of equations as a subtype of `EarthSciMLODESystem`.
# Creating our system in this way allows us to convert it to a PDE system 
# using just the `+` operator as shown below.
struct ExampleSys <: EarthSciMLODESystem
    sys::ODESystem
    function ExampleSys(t; name)
        @variables y(t)
        @parameters p=2.0
        D = Differential(t)
        new(ODESystem([D(y) ~ p], t; name))
    end
end
@named sys = ExampleSys(t)

# Create our initial and boundary conditions.
icbc = ICBC(constBC(1.0, x ∈ Interval(0, 1.0)), constIC(0.0, t ∈ Interval(0, 1.0)))

# Convert our ODE system to a PDE system and add advection to each of the state variables.
# We're also adding a constant wind in the x-direction, with a speed of 1.0.
sys_advection = sys + icbc + ConstantWind(t, 1.0) + Advection()
sys_mtk = get_mtk(sys_advection)

# Discretize the system and solve it.
discretization = MOLFiniteDifference([x=>10], t, approx_order=2)
@time prob = discretize(sys_mtk, discretization)
@time sol = solve(prob, Tsit5(), saveat=0.1)

# Plot the solution.
discrete_x = sol[x]
discrete_t = sol[t]
@variables sys₊y(..)
soly = sol[sys₊y(x, t)]
anim = @animate for k in 1:length(discrete_t)
    plot(soly[1:end, k], title="t=\$(discrete_t[k])", ylim=(0,2.5), lab=:none)
end
gif(anim, fps = 8)
```
"""
struct Advection end

# Create a system of equations that apply advection to the variables in `vars`, 
# using the given initial and boundary conditions to determine which directions
# to advect in.
function advection(vars, icbc::ICBC)
    iv = ivar(icbc)
    pvs = pvars(icbc)
    @assert length(pvs) <= 3 "Advection is only implemented for 3 or fewer dimensions."
    uvars = (@variables meanwind₊u(..) meanwind₊v(..) meanwind₊w(..))[1:length(pvs)]
    varsdims = Num[v for v ∈ vars]
    udims = Num[ui(pvs..., iv) for ui ∈ uvars]
    eqs = Equation[]
    for var ∈ varsdims
        terms(wind) = sum(((pv) -> -wind * Differential(pv)(var)).(pvs))
        rhs = sum(vcat([terms(wind) for wind in udims]))
        eq = Differential(iv)(var) ~ rhs
        push!(eqs, eq)
    end
    eqs
end

function Base.:(+)(c::ComposedEarthSciMLSystem, _::Advection)::ComposedEarthSciMLSystem
    @assert isa(c.icbc, ICBC) "The system must have initial and boundary conditions to add advection."
    
    # Add in a model component to allow the specification of the wind velocity.
    c += MeanWind(ivar(c.icbc), length(pvars(c.icbc)))
    
    function f(sys::ModelingToolkit.PDESystem)
        eqs = advection(sys.dvs, c.icbc)
        operator_compose!(sys, eqs)
    end
    ComposedEarthSciMLSystem(c.systems, c.icbc, [c.pdefunctions; f])
end
Base.:(+)(a::Advection, c::ComposedEarthSciMLSystem)::ComposedEarthSciMLSystem = c + a

"""
$(SIGNATURES)

Construct a constant wind velocity model component.
"""
struct ConstantWind <: EarthSciMLODESystem
    sys::ODESystem
    ndims

    function ConstantWind(t, vals...)
        @assert 0 < length(vals) <= 3 "Must specify between one and three wind component speeds."
        uvars = (@variables u(t) v(t) w(t))[1:length(vals)]
        eqs = Symbolics.scalarize(uvars .~ collect(vals))
        new(ODESystem(eqs, t, uvars, []; name=:constantwind), length(vals))
    end
end
function Base.:(+)(mw::MeanWind, w::ConstantWind)::ComposedEarthSciMLSystem
    eqs = [mw.sys.u ~ w.sys.u]
    w.ndims >= 2 ? push!(eqs, mw.sys.v ~ w.sys.v) : nothing
    w.ndims == 3 ? push!(eqs, mw.sys.w ~ w.sys.w) : nothing
    ComposedEarthSciMLSystem(ConnectorSystem(
        eqs,
        mw, w,
    ))
end
Base.:(+)(w::ConstantWind, mw::MeanWind)::ComposedEarthSciMLSystem = mw + w