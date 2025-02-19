# ViscousFlow.jl

*a framework for simulating viscous incompressible flows*

The objective of this package is to allow easy setup and fast simulation of incompressible
flows, particularly those past bodies in motion. The package provides
tools for
- constructing grids and body shapes,
- specifying the relevant parameters and setting their values,
- solving the problem, and finally,
- visualizing and analyzing the results.

The underlying grids are uniform and Cartesian, making use of the [CartesianGrids](https://github.com/JuliaIBPM/CartesianGrids.jl) package. This package allows the use of the lattice
Green's function (LGF) for inverting the Poisson equation; the diffusion operators are
solved with the integrating factor (Liska and Colonius [^1]). Many of the core aspects
of the fluid-body interaction are based on the immersed boundary projection method,
developed by Taira and Colonius [^2]. The coupled fluid-body interactions are based
on the work of Wang and Eldredge [^3]. These are implemented with the [ConstrainedSystems](https://github.com/JuliaIBPM/ConstrainedSystems.jl) package. Tools for creating bodies and
their motions are based on the [RigidBodyTools](https://github.com/JuliaIBPM/RigidBodyTools.jl) package.

![](https://github.com/JuliaIBPM/ViscousFlow.jl/raw/master/cylinderRe400.gif)

## Installation

This package works on Julia `1.4` and above and is registered in the general Julia registry. To install from the REPL, type
e.g.,
```julia
] add ViscousFlow
```

Then, in any version, type
```julia
julia> using ViscousFlow
```

The plots in this documentation are generated using [Plots.jl](http://docs.juliaplots.org/latest/).
You might want to install that, too, to follow the examples.

## References

[^1]: Liska, S. and Colonius, T. (2017) "A fast immersed boundary method for external incompressible viscous flows using lattice Green's functions," *J. Comput. Phys.*, 331, 257--279.

[^2]: Taira, K. and Colonius, T. (2007) "The immersed boundary method: a projection approach," *J. Comput. Phys.*, 225, 2118--2137.

[^3]: Wang, C. and Eldredge, J. D. (2015) "Strongly coupled dynamics of fluids and rigid-body systems with the immersed boundary projection method," *J. Comput. Phys.*, 295, 87--113. [(DOI)](https://doi.org/10.1016/j.jcp.2015.04.005).
