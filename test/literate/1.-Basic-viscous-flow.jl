# # 1. Basic viscous flow
# In this example, we will simulate various examples of a basic *unbounded* viscous flow---a flow
# without boundaries. Our initial condition will be a distribution of *vorticity*.

using ViscousFlow
using Plots

#=
### The basic steps
To carry out any simulation in `ViscousFlow`, we need to carry out a few basic steps:
* **Specify the problem**: Set the Reynolds number and free stream
* **Discretize**: Set up a solution domain, grid cell size, time step size
* **Construct the system structure**: Create the operators that will be used to perform the simulation
* **Initialize**: Set the initial flow field and initialize the integrator
* **Solve**: Solve the flow field
* **Examine**: Examine the results

We will go through all of these here. For the examples we will carry out in this notebook,
the first three steps need only be carried out once.
=#

#=
### Problem specification
We will set the Reynolds number to be 200 and no free stream
=#
Re = 200

#=
### Discretize
We will set up a domain from x = -2 to x = 2, and y = -2 to y = 2. The Reynolds number helps us
determine the grid spacing `Δx` and time step size `Δt`. To set these, we set a target *grid Reynolds
number*, `gridRe`. We will set this to 4 here; if we ignore it, it defaults to 2. Note that this choice is a compromise
* smaller grid Reynolds number means smaller grid spacing, and slower simulations
* larger grid Reynolds number means less accurate results
=#
xlim = (-2.0,2.0)
ylim = (-2.0,2.0)
Δx, Δt = setstepsizes(Re,gridRe=4)

# ### Construct the system structure
# This part is easy - you just supply the parameters you have just set up. It returns a structure with all of the necessary mathematical operators:
sys = NavierStokes(Re,Δx,xlim,ylim,Δt)

# Now, we will solve a few different problems

#=
## A basic example: the Lamb-Oseen vortex
This example starts with a single vortex with a Gaussian distribution of vorticity. To generate this, will use the `SpatialGaussian` function:
The command below creates a Gaussian with radius σ at (0,0) with strength 1.
=#
σ = 0.2
x0 = 0.0
y0 = 0.0
A = 1
gauss = SpatialGaussian(σ,x0,y0,A)

#=
### Initialize
Now, we create an instance of this vorticity distribution on the grid by
calling `newstate` with this vortex.
=#
u0 = newstate(gauss,sys)

#=
We use this initial condition to initialize the **integrator**. The integrator is the structure that
holds all of our solution and operator information. With it, we can start the simulation, restart
the simulation later, etc. We specify a range of time over which to advance the solution.

**Note**: This range need only be large enough to contain the whole interval of time we wish to simulate. It does not need to be chosen very precisely.

**Note 2**: There is no need to restart the problem! We can keep applying the `step!` function below as long we need.
=#
tspan = (0.0,10.0)
integrator = init(u0,tspan,sys)

# ### Solve
# Now we are ready to solve the problem. Let's advance the solution to $t = 1$:
step!(integrator,1.0)

# We can see now that the solution has been advanced in time:
integrator

#=
### Examine
Let's examine the results. It is important to show a few different ways that we can do this.
The most straightforward way is to just look at the flow fields at the current state of the
integrator. For example, to get the current velocity field, type `velocity(integrator)`. We can
do the same for `vorticity`, `streamfunction` (the streamlines), `scalarpotential`, `convective_derivative`,
and `pressure`.
=#

# We will look at some of these at the current state:
plot(
 plot(vorticity(integrator),sys,title="Vorticity"),
 plot(streamfunction(integrator),sys,title="Streamlines"),
 plot(pressure(integrator),sys,title="Pressure"),
 plot(velocity(integrator),sys))

# For this problem, we can compare with the exact solution. The exact solution is also a Gaussian,
# but with a radius $\\sqrt{\\sigma^2+4t/Re}$
oseen_exact(t) = SpatialGaussian(sqrt(σ^2+4*t/Re),x0,y0,A)
exactsol(t) = newstate(oseen_exact(t),sys)

#-
plot(vorticity(integrator)[:,104],label="Numerical")
plot!(vorticity(exactsol(integrator.t),sys,integrator.t)[:,104],label="Exact")
plot!(title=string("Vorticity at t = ",round(integrator.t,digits=2)))

#=
## Second example: co-rotating vortices
The previous example is not very exciting, because the convection of the flow is simply circular.
The next example is more interesting, because we will start with two vortices that influence each
other's motion:
=#
σ = 0.1
x01, y01 = 0.5, 0.0
x02, y02 = -0.5, 0.0
A = 1
twogauss = SpatialGaussian(σ,x01,y01,A) + SpatialGaussian(σ,x02,y02,A)

### Initialize
# Now, we create an instance of this vorticity distribution on the grid.
u0 = newstate(twogauss,sys)

#-
plot(vorticity(u0,sys,0.0),sys)

#-
tspan = (0.0,8.0)
integrator = init(u0,tspan,sys)

# ### Solve
# Now we are ready to solve the problem. Let's advance the solution to $t = 8$:
step!(integrator,8.0)

#=
### Examine
In this case, it is best to view the results as an animation. In the previous example, we just
looked at the final state of the integrator. Here, to animate, we will make use of the solution
history that is held by the integrator, `integrator.sol`. Let's create an alias for this to shorten
our commands:
=#
sol = integrator.sol;

# Now we will animate the solution, plotting the vorticity every 5 steps
@gif for (u,t) in zip(sol.u,sol.t)
    plot(vorticity(u,sys,t),sys)
end every 5

# The vortices orbit each other and then eventually merge together. If we wish to make a nice
# figure, we can arrange snapshots on a grid:
plt = plot(layout = (2,4), size = (800, 400), legend=:false)
framejump = 100
nframes = 8
for (i, frame) in enumerate(1:framejump:(nframes-1)*framejump+1)
    plot!(plt[i],vorticity(sol[frame],sys,sol.t[frame]),sys,levels=range(0.1,5,length=31))
end
savefig(plt,"CoRotating.pdf")
plt

#=
**Try other examples!**
* Make one or both of the vortices into elliptical shapes
* Make one stronger than the other
* Add other vortices into the initial distribution
=#
