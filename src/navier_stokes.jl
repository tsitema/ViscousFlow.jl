import Base: size

const NDIM = 2


import CartesianGrids: cellsize, origin
import RigidBodyTools: assign_velocity!
import ImmersedLayers: normals, areas

"""
$(TYPEDEF)

A system type that utilizes a grid of `NX` x `NY` dual cells and `N` Lagrange forcing
points to solve the discrete Navier-Stokes equations in vorticity form. The
parameter `static_points` specifies whether the forcing points remain static in the
grid. It should be set to `false` if a supplied motion requires that the points move.

# Constructors:

`NavierStokes(Re,Δx,xlimits,ylimits,Δt
              [,freestream = (0.0, 0.0)]
              [,pulses=nothing])` specifies the Reynolds number `Re`, the grid
              spacing `Δx`, the dimensions of the domain in the tuples `xlimits`
              and `ylimits` (excluding the ghost cells), and the time step size `Δt`.
              The other arguments are optional. The `freestream` argument can be
              passed as either a tuple (a static freestream) or a `RigidBodyMotion`
              for a time-varying freestream. The `pulses` argument can be
              used to pass in one or more spatiotemporal pulses.


`NavierStokes(Re,Δx,xlimits,ylimits,Δt,bodies::Body/BodyList
              [,flow_side=ExternalInternalFlow]
              [,ddftype=CartesianGrids.Yang3])` passes the body
              information. This constructor
              sets the motions of the body/ies to be stationary.
              The same optional arguments used for the basic constructor
              also apply for this one. In addition, the `flow_side` can be set to
              `ExternalFlow` (default), `InternalFlow`, or `ExternalInternalFlow`.
              However, it is forced to `ExternalInternalFlow` for open Bodies
              (like `Plate` type).

`NavierStokes(Re,Δx,xlimits,ylimits,Δt,bodies::Body/BodyList,
              motions::RigidBodyMotion/RigidMotionList
              [,static_points=false])`
              passes the body and associated motion information.
              The list of motions must be the same length as the list of bodies.
              The same optional arguments used for the other constructors
              also apply for this one. In addition, `static_points` can
              be set to `true` if the supplied motion should not cause the
              points to move.

"""
mutable struct NavierStokes{NX, NY, N, MT<:PointMotionType, FS<:FreestreamType, SD<:FlowSide, DDF<:CartesianGrids.DDFType, FT, SP, FST} #, RKT}
    # Physical Parameters
    "Reynolds number"
    Re::Float64
    "Free stream velocities"
    U∞::FST
    "Bodies"
    bodies::Union{BodyList,Nothing}
    "Body motions"
    motions::Union{RigidMotionList,Nothing}
    "Pulses"
    pulses::Union{Vector{ModulatedField},Nothing}

    # Discretization
    "Grid metadata"
    grid::CartesianGrids.PhysicalGrid{2}
    "Time step"
    Δt::Float64

    # Operators
    "Laplacian operator"
    L::CartesianGrids.Laplacian

    # Layers
    dlf::Union{DoubleLayer,Nothing} # used for viscous surface terms
    slc::Union{SingleLayer,Nothing} # used for scalar potential field in velocity
    sln::Union{SingleLayer,Nothing} # might not be used

    # Body coordinate data, if present
    # if a static problem, these coordinates are in inertial coordinates
    # if a non-static problem, in their own coordinate systems
    points::VectorData{N,Float64}

    # Pre-stored regularization and interpolation matrices (if present)
    Rf::Union{RegularizationMatrix,Nothing} # faces (edges)
    Ef::Union{InterpolationMatrix,Nothing}
    Cf::Union{AbstractMatrix,Nothing}
    Rc::Union{RegularizationMatrix,Nothing} # cell centers
    Ec::Union{InterpolationMatrix,Nothing}
    Rn::Union{RegularizationMatrix,Nothing} # cell nodes
    En::Union{InterpolationMatrix,Nothing}

    # Operators
    f :: FT

    # state vector
    state_prototype :: SP

    # Scratch space

    ## Pre-allocated space for intermediate values
    Vb::VectorData{N,Float64}
    Sb::ScalarData{N,Float64}
    Δus::VectorData{N,Float64}
    τ::VectorData{N,Float64}
    Vf::Edges{Primal, NX, NY, Float64}
    Vv::Edges{Primal, NX, NY, Float64}
    Vn::Edges{Primal, NX, NY, Float64}
    Sc::Nodes{Primal, NX, NY,Float64}
    Sn::Nodes{Dual, NX, NY,Float64}
    Wn::Nodes{Dual, NX, NY,Float64}
    Vtf::EdgeGradient{Primal,Dual,NX,NY,Float64}
    DVf::EdgeGradient{Primal,Dual,NX,NY,Float64}
    VDVf::EdgeGradient{Primal,Dual,NX,NY,Float64}

end

function NavierStokes(Re::Real, Δx::Real, xlimits::Tuple{Real,Real},ylimits::Tuple{Real,Real}, Δt::Real;
                       freestream::FST = (0.0, 0.0),
                       bodies::Union{BodyList,Nothing} = nothing,
                       motions::Union{RigidMotionList,Nothing} = nothing,
                       pulses::PT = nothing,
                       static_points = true,
                       flow_side::Type{SD} = ExternalFlow,
                       ddftype=CartesianGrids.Yang3) where {FST,PT,SD<:FlowSide}

    g = PhysicalGrid(xlimits,ylimits,Δx)
    NX, NY = size(g)

    α = Δt/(Re*Δx^2)

    # Set up buffers
    Vf = Edges{Primal,NX,NY,Float64}()
    Vv = Edges{Primal,NX,NY,Float64}()
    Vn = Edges{Primal,NX,NY,Float64}()
    Sc = Nodes{Primal,NX,NY,Float64}()
    Sn = Nodes{Dual,NX,NY,Float64}()
    Wn = Nodes{Dual,NX,NY,Float64}()
    Vtf = EdgeGradient{Primal,Dual,NX,NY,Float64}()
    DVf = EdgeGradient{Primal,Dual,NX,NY,Float64}()
    VDVf = EdgeGradient{Primal,Dual,NX,NY,Float64}()

    L = plan_laplacian(Sn,with_inverse=true)

    pulsefields = _process_pulses(pulses,Sn,g)


    # for now, if there are any bodies that are Open,
    # then force flow_side to ExternalInternalFlow.
    # but should be more flexible here
    flow_side_internal = _any_open_bodies(bodies) ? ExternalInternalFlow : flow_side

    N = numpts(bodies)

    Vb = VectorData(N)
    Sb = ScalarData(N)
    Δus = VectorData(N)
    τ = VectorData(N)

    points, dlf, slc, sln, Rf, Ef, Cf, Rc, Ec, Rn, En =
              _immersion_operators(bodies,g,flow_side_internal,ddftype,Vf,Sc,Vb)


    viscous_L = plan_laplacian(Sn,factor=1/(Re*Δx^2))

    if isnothing(bodies)
      state_prototype = solvector(state=Sn)
      f = ConstrainedODEFunction(ns_rhs!,viscous_L,_func_cache=state_prototype)
    else
      if static_points
        state_prototype = solvector(state=Sn,constraint=τ)
        f = ConstrainedODEFunction(ns_rhs!,bc_constraint_rhs!,
                                      ns_op_constraint_force!,bc_constraint_op!,
                                      viscous_L,_func_cache=state_prototype)
      else
        state_prototype = solvector(state=Sn,constraint=τ,aux_state=zero_body_state(bodies))
        rhs! = ConstrainedSystems.r1vector(state_r1 = ns_rhs!,aux_r1 = rigid_body_rhs!)
        f = ConstrainedODEFunction(rhs!,bc_constraint_rhs!,
                                      ns_op_constraint_force!,bc_constraint_op!,
                                      viscous_L,_func_cache=state_prototype,
                                      param_update_func=update_immersion_operators!)
      end

    end





    NavierStokes{NX, NY, N, _motiontype(static_points), _fstype(FST), flow_side_internal, ddftype, typeof(f), typeof(state_prototype),FST}( #,typeof(rk)}(
                          Re, freestream, bodies, motions, pulsefields,
                          g, Δt, # rk,
                          L,
                          dlf,slc,sln,
                          points, Rf, Ef, Cf, Rc, Ec, Rn, En,
                          f,state_prototype,
                          Vb, Sb, Δus, τ,
                          Vf, Vv, Vn, Sc, Sn, Wn, Vtf, DVf, VDVf)
end

NavierStokes(Re,Δx,xlim,ylim,Δt,bodies::BodyList;
        motions=RigidMotionList(map(x -> RigidBodyMotion(0.0,0.0),bodies)),kwargs...) =
        NavierStokes(Re,Δx,xlim,ylim,Δt;bodies=bodies,motions=motions,kwargs...)

NavierStokes(Re,Δx,xlim,ylim,Δt,body::Body;kwargs...) =
        NavierStokes(Re,Δx,xlim,ylim,Δt,BodyList([body]);kwargs...)

function NavierStokes(Re,Δx,xlim,ylim,Δt,bodies::BodyList,motions::RigidMotionList;static_points=false,kwargs...)
    length(bodies) == length(motions) || error("Inconsistent lengths of bodies and motions lists")
    NavierStokes(Re,Δx,xlim,ylim,Δt,bodies;motions=motions,static_points=static_points,kwargs...)
end

NavierStokes(Re,Δx,xlim,ylim,Δt,body::Body,motion::RigidBodyMotion;static_points=false,kwargs...) =
        NavierStokes(Re,Δx,xlim,ylim,Δt,BodyList([body]),RigidMotionList([motion]);static_points=static_points,kwargs...)


function Base.show(io::IO, sys::NavierStokes{NX,NY,N,MT,FS,SD}) where {NX,NY,N,MT,FS,SD}
    mtype = (MT == StaticPoints) ? "static" : "moving"
    fsmsg = (FS == StaticFreestream) ? "Static freestream = $(sys.U∞)" : "Variable freestream"
    sdmsg = (N == 0) ? "Unbounded" : ((SD == ExternalFlow) ? "External flow" : ((SD == InternalFlow) ? "Internal flow" : "External/internal"))
    println(io, "$sdmsg Navier-Stokes system on a grid of size $NX x $NY and $N $mtype immersed points")
    println(io, "   $fsmsg")
    if N > 0
      bdmsg = (length(sys.bodies) == 1) ? "1 body" : "$(length(sys.bodies)) bodies"
      println(io, "   $bdmsg")
    end
end

# Routines to set up the immersion operators

function _immersion_operators(bodies::BodyList,g::PhysicalGrid,flow_side::Type{SD},ddftype,Vf::GridData{NX,NY},Sc::GridData{NX,NY},Vb::PointData{N}) where {NX,NY,N,SD<:ViscousFlow.FlowSide}

  points = VectorData(collect(bodies))
  numpts(bodies) == N || error("Inconsistent size of bodies")

  body_areas = areas(bodies)
  body_normals = normals(bodies)

  if !(flow_side==ExternalInternalFlow)
    dlf = DoubleLayer(bodies,g,Vf)
    slc = SingleLayer(bodies,g,Sc)
    #sln = SingleLayer(bodies,g,Sn)
    sln = nothing
  else
    dlf = nothing
    slc = nothing
    sln = nothing
  end

  #regop = Regularize(points,cellsize(g);I0=CartesianGrids.origin(g),weights=body_areas.data,ddftype=ddftype)
  regop = _regularization(points,g,bodies,ddftype)

  Rf = RegularizationMatrix(regop,Vb,Vf) # Used by B₁ᵀ
  Ef = InterpolationMatrix(regop,Vf,Vb) # Used by constraint_rhs! and B₂

  #Rc = RegularizationMatrix(regop,Sb,Sc)
  #Ec = InterpolationMatrix(regop,Sc,Sb)
  #Rn = RegularizationMatrix(regop,Sb,Sn)
  #En = InterpolationMatrix(regop,Sn,Sb)
  Rc = nothing
  Ec = nothing
  Rn = nothing
  En = nothing

  regopfilt = Regularize(points,cellsize(g);I0=CartesianGrids.origin(g),filter=true,weights=cellsize(g)^2,ddftype=ddftype)
  Ẽf = InterpolationMatrix(regopfilt,Vf,Vb)
  Cf = sparse(Ẽf*Rf)

  return points, dlf, slc, sln, Rf, Ef, Cf, Rc, Ec, Rn, En
end

_immersion_operators(::Nothing,a...) =
    VectorData(0), nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing, nothing


# For updating the system with body data

function update_immersion_operators!(sys::NavierStokes{NX,NY,N,MT,FS,SD,DDF},bodies::BodyList) where {NX,NY,N,MT,FS,SD,DDF<:CartesianGrids.DDFType}
    sys.bodies = deepcopy(bodies)
    sys.points, sys.dlf, sys.slc, sys.sln, sys.Rf, sys.Ef, sys.Cf, sys.Rc, sys.Ec, sys.Rn, sys.En =
      _immersion_operators(sys.bodies,sys.grid,SD,DDF,sys.Vf,sys.Sc,sys.Vb)
    return sys
end

update_immersion_operators!(sys::NavierStokes,body::Body) = update_immersion_operators!(sys,BodyList([body]))

function update_immersion_operators!(sys::NavierStokes,x::AbstractVector)
    tl! = RigidTransformList(x)
    tl!(sys.bodies)
    update_immersion_operators!(sys,sys.bodies)
end

# The form passed to ConstrainedODEFunction
update_immersion_operators!(sys::NavierStokes,u,sys_old::NavierStokes,t) =
    update_immersion_operators!(sys,aux_state(u))




"""
    setstepsizes(Re[,gridRe=2][,cfl=0.5][,fourier=0.5]) -> Float64, Float64

Set the grid cell spacing and time step size based on the Reynolds number `Re`,
the grid Reynolds number `gridRe`, cfl number `cfl`, and grid Fourier number `fourier`.
The last three parameters all have default values.

# Example

Here is an example of setting parameters based on Reynolds number 100 (with
  default choices for grid Reynolds number, CFL number, and Fourier number):
```jldoctest
julia> Δx, Δt = setstepsizes(100)
(0.02, 0.01)
```
"""
function setstepsizes(Re::Real; gridRe = 2.0, cfl = 0.5, fourier = 0.5)
    Δx = gridRe/Re
    Δt = min(fourier*Δx,cfl*Δx^2*Re)
    return Δx, Δt
end




# some convenience functions
"""
    size(sys::NavierStokes,d::Int) -> Int

Return the number of indices of the grid used by `sys` along dimension `d`.
"""
size(sys::NavierStokes{NX,NY},d::Int) where {NX,NY} = d == 1 ? NX : NY

"""
    size(sys::NavierStokes) -> Tuple{Int,Int}

Return a tuple of the number of indices of the grid used by `sys`
"""
size(sys::NavierStokes{NX,NY}) where {NX,NY} = (size(sys,1),size(sys,2))

"""
    cellsize(sys::NavierStokes) -> Float64

Return the grid cell size of system `sys`
"""
cellsize(sys::NavierStokes) = cellsize(sys.grid)

"""
    timestep(sys::NavierStokes) -> Float64

Return the time step size of system `sys`
"""
timestep(sys::NavierStokes) = sys.Δt

"""
    origin(sys::NavierStokes) -> Tuple{Int,Int}

Return a tuple of the indices of the primal node that corresponds to the
physical origin of the coordinate system used by `sys`. Note that these
indices need not lie inside the range of indices occupied by the grid.
For example, if the range of physical coordinates occupied by the grid
is (1.0,3.0) x (2.0,4.0), then the origin is not inside the grid.
"""
origin(sys::NavierStokes) = origin(sys.grid)


"""
    timerange(tf,sys::NavierStokes)

Create a range of times, starting at the t = Δt (the time step of `sys`),
and ending at t = `tf`.
"""
timerange(tf,sys) = timestep(sys):timestep(sys):tf

# Wrap the output of the motion evaluation in VectorData
@inline assign_velocity!(u::VectorData,a...) = (assign_velocity!(u.u,u.v,a...); u)


@inline normals(sys::NavierStokes) = (!isnothing(sys.bodies)) ? normals(sys.bodies) : nothing


"""
    freestream(t,sys::NavierStokes) -> Tuple

Return the value of the freestream in `sys` at time `t` as a tuple.
"""
freestream(t::Real,sys::NavierStokes{NX,NY,N,MT,StaticFreestream}) where {NX,NY,N,MT} = sys.U∞

function freestream(t::Real,sys::NavierStokes{NX,NY,N,MT,VariableFreestream}) where {NX,NY,N,MT}
    _,ċ,_,_,_,_ = sys.U∞(t)
    return reim(ċ)
end

"""
    newstate(sys::NavierStokes)

Return a new (zero) instance of the state vector for `sys`.
"""
newstate(sys::NavierStokes) = zero(sys.state_prototype)

"""
    newstate(s::AbstractSpatialField,sys::NavierStokes)

Return an instance of the state vector for `sys`, assigned the
data in the spatial field `s`.
"""
function newstate(s::AbstractSpatialField,sys::NavierStokes)
  u = newstate(sys)
  gf = GeneratedField(state(u),s,sys.grid)
  state(u) .= cellsize(sys)*gf()
  return u
end

# Other functions
_hasfilter(sys::NavierStokes) = !isnothing(sys.Cf)
_motiontype(isstatic::Bool) = isstatic ? StaticPoints : MovingPoints
  _fstype(F) = F <: Union{RigidBodyMotion,Kinematics} ? VariableFreestream : StaticFreestream

_body_closure_type(b::T) where {T<:Body{N,C}} where {N,C} = C

_any_open_bodies(nothing) = false
_any_open_bodies(bodies::BodyList) =  any(b -> _body_closure_type(b) == RigidBodyTools.OpenBody,bodies)

_regularization(sys::NavierStokes{NX, NY, N, MT, FS, SD, DDF}) where {NX,NY,N,MT,FS,SD,DDF} =
        _regularization(sys.points,sys.grid,sys.bodies,DDF)

_regularization(points,g,bodies,ddftype) = Regularize(points,cellsize(g),
                                I0=CartesianGrids.origin(g),weights=areas(bodies).data,ddftype=ddftype)


include("navierstokes/surfacevelocities.jl")
include("navierstokes/fields.jl")
include("navierstokes/pointforce.jl")
include("navierstokes/basicoperators.jl")
include("navierstokes/rigidbodyoperators.jl")
include("navierstokes/movingbodyoperators.jl")
include("navierstokes/timemarching.jl")
