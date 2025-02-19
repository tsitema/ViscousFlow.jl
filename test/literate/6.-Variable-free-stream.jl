#=
# 6. Variable free stream
In this notebook we will simulate the flow with a time-varying free stream past a
stationary body. To demonstrate this, we will solve for oscillatory flow past a
rectangular object, in which the $x$ component of the free stream is

$$U_\infty(t) = A \sin(\Omega t)$$
=#
using ViscousFlow
#-
using Plots

#=
### Problem specification
We will set the Reynolds number to 200
=#
Re = 200 # Reynolds number

#=
In order to set the time-varying free stream, we will use the `OscillationX` function,
which generates a set of oscillatory kinematics. Type `?OscillationX` to
learn more.

Since we are using this function to specify the velocity (the first derivative of
the position), then we set
=#
Ux = 0.0
Ω  = 1.0
Ax = 1.0
fs = OscillationX(Ux,Ω,Ax,π/2)

#=
As with body motion, it is useful to verify that this provides the expected behavior
by plotting it:
=#
plot(fs)

# Now let us carry on with the other usual steps:

# ### Discretize
xlim = (-2.0,2.0)
ylim = (-1.5,1.5)

Δx, Δt = setstepsizes(Re,gridRe=3.0)

#=
### Set up bodies
Here, we will set up a rectangle in the center of the domain
=#
body = Rectangle(0.25,0.5,1.5Δx)
T = RigidTransform((0.0,0.0),0.0)
T(body)
#-
plot(body,xlim=xlim,ylim=ylim)

#=
### Construct the system structure
This step is like the previous notebook, but now we also provide the body and the freestream:
=#
sys = NavierStokes(Re,Δx,xlim,ylim,Δt,body,freestream = fs)

#=
### Initialize
Now, we initialize with zero vorticity
=#
u0 = newstate(sys)
# and create the integrator
tspan = (0.0,10.0)
integrator = init(u0,tspan,sys)

#=
### Solve
Now we are ready to solve the problem. Let's advance the solution to $t = 1$.
=#
@time step!(integrator,1.0)
sol = integrator.sol;

#=
### Examine
Let's look at the flow field at the end of this interval
=#
plot(
plot(vorticity(integrator),sys,title="Vorticity",clim=(-10,10),levels=range(-10,10,length=30), color = :RdBu,ylim=ylim),
plot(streamfunction(integrator),sys,title="Streamlines",ylim=ylim,color = :Black),
    size=(700,300)
    )

# Now let's make a movie
@gif for (u,t) in zip(sol.u,sol.t)
    #plot(streamfunction(u,sys,t),sys, color = :Black)
    plot(vorticity(u,sys,t),sys,clim=(-10,10),levels=range(-10,10,length=30), color = :RdBu)
    end every 10

#=
#### Compute the force history
Just as we did for the stationary body in a constant free stream
=#
fx, fy = force(sol,sys,1);
# Plot them
plot(
plot(sol.t,2*fx,xlim=(0,Inf),ylim=(-6,6),xlabel="Convective time",ylabel="\$C_D\$",legend=:false),
plot(sol.t,2*fy,xlim=(0,Inf),ylim=(-6,6),xlabel="Convective time",ylabel="\$C_L\$",legend=:false),
    size=(800,350)
)

# The mean drag and lift coefficients are
meanCD = GridUtilities.mean(2*fx)
#-
meanCL = GridUtilities.mean(2*fy)
