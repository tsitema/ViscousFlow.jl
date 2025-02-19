### Basic operators for any Navier-Stokes system ###
# Note that the input vector `w` is vorticity x cell spacing (i.e., it
# has units of velocity), and
# we expect the rhs of the equations to have units of dw/dt

export ns_rhs!


# RHS of Navier-Stokes equations
function ns_rhs!(dw::Nodes{Dual,NX,NY},w::Nodes{Dual,NX,NY},sys::NavierStokes{NX,NY},t::Real) where {NX,NY}
  dw .= 0.0
  #_ns_rhs_convectivederivative!(dw,w,sys,t)
  #_ns_rhs_double_layer!(dw,sys,t)
  fill!(sys.Vn,0.0)
  _vel_ns_rhs_convectivederivative!(sys.Vn,w,sys,t)
  _vel_ns_rhs_double_layer!(sys.Vn,sys,t)
  curl!(dw,sys.Vn)
  _ns_rhs_pulses!(dw,sys,t)
  return dw
end

_ns_rhs_pulses!(dw::Nodes{Dual,NX,NY},sys::NavierStokes{NX,NY},t) where {NX,NY} = _ns_rhs_pulses!(dw,sys.pulses,cellsize(sys),t)

_ns_rhs_pulses!(dw,::Nothing,Δx,t) = dw

function _ns_rhs_pulses!(dw,pulses::Vector{<:ModulatedField},Δx,t)
  for p in pulses
    dw .+= Δx*p(t)
  end
  dw
end

#=
function _ns_rhs_convectivederivative!(dw::Nodes{Dual,NX,NY},w::Nodes{Dual,NX,NY},sys::NavierStokes{NX,NY},t) where {NX,NY}
  Δx⁻¹ = 1/cellsize(sys)
  velocity!(sys.Vv,w,sys,t)
  _unscaled_convective_derivative!(sys.Vv,sys)
  sys.Sn .= 0.0
  curl!(sys.Sn,sys.Vv)
  sys.Sn .*= Δx⁻¹
  dw .-= sys.Sn
end
=#

function _vel_ns_rhs_convectivederivative!(u::Edges{Primal,NX,NY},w::Nodes{Dual,NX,NY},sys::NavierStokes{NX,NY},t) where {NX,NY}
    Δx⁻¹ = 1/cellsize(sys)
    fill!(sys.Vv,0.0)
    velocity!(sys.Vv,w,sys,t)
    _unscaled_convective_derivative!(sys.Vv,sys)
    sys.Vv .*= Δx⁻¹
    u .-= sys.Vv
end


#=
function _ns_rhs_double_layer!(dw::Nodes{Dual,NX,NY},
                              sys::NavierStokes{NX,NY,N,MT,FS,ExternalInternalFlow},
                              t::Real) where {NX,NY,N,MT,FS}
  return dw
end

function _ns_rhs_double_layer!(dw::Nodes{Dual,NX,NY},
                              sys::NavierStokes{NX,NY,N,MT,FS,SD},
                              t::Real) where {NX,NY,N,MT,FS,SD}
  Δx⁻¹ = 1/cellsize(sys)
  fact = Δx⁻¹/sys.Re
  surface_velocity_jump!(sys.Δus,sys,t)
  sys.Vf .= 0.0
  sys.dlf(sys.Vf,sys.Δus)
  sys.Sn .= 0.0
  curl!(sys.Sn,sys.Vf)
  sys.Sn .*= fact
  dw .-= sys.Sn
end
=#

@inline _vel_ns_rhs_double_layer!(u::Edges{Primal,NX,NY},sys::NavierStokes{NX,NY,N,MT,FS,
                                  ExternalInternalFlow},t::Real) where {NX,NY,N,MT,FS} = u

@inline _vel_ns_rhs_double_layer!(u::Edges{Primal,NX,NY},sys::NavierStokes{NX,NY,0},t::Real) where {NX,NY} = u

function _vel_ns_rhs_double_layer!(u::Edges{Primal,NX,NY},sys::NavierStokes{NX,NY,N,MT,FS,SD},t::Real) where {NX,NY,N,MT,FS,SD}
    Δx⁻¹ = 1/cellsize(sys)
    fact = Δx⁻¹/sys.Re
    surface_velocity_jump!(sys.Δus,sys,t)
    fill!(sys.Vf,0.0)
    sys.dlf(sys.Vf,sys.Δus)
    sys.Vf .*= fact
    u .-= sys.Vf
end

_unscaled_convective_derivative!(u::Edges{Primal,NX,NY},sys::NavierStokes{NX,NY}) where {NX,NY} =
      _unscaled_convective_derivative!(u,sys.Vtf,sys.DVf,sys.VDVf)

# Operates in-place on `u`, which comes in with the velocity field and
# returns the unscaled convective derivative
function _unscaled_convective_derivative!(u::Edges{Primal,NX,NY},
                                          Vtf::EdgeGradient{Primal,Dual,NX,NY},
                                          DVf::EdgeGradient{Primal,Dual,NX,NY},
                                          VDVf::EdgeGradient{Primal,Dual,NX,NY}) where {NX,NY}
    transpose!(Vtf,grid_interpolate!(DVf,u))
    DVf .= 0.0
    grad!(DVf,u)
    product!(VDVf,Vtf,DVf)
    u .= 0.0
    grid_interpolate!(u,VDVf)
    u
end
