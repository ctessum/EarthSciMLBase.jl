module EarthSciMLBase
using ModelingToolkit, Symbolics, Catalyst
using DocStringExtensions
using Unitful

include("add_dims.jl")
include("domaininfo.jl")
include("composed_system.jl")
include("operator_compose.jl")
include("advection.jl")
include("coord_trans.jl")
include("param_to_var.jl")

end
