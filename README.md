# ReverseSearch.jl
[![CI](https://github.com/mxhbl/ReverseSearch.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/mxhbl/ReverseSearch.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/mxhbl/ReverseSearch.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/mxhbl/ReverseSearch.jl)

This is a pure Julia implementation of the [reverse search](https://en.wikipedia.org/wiki/Reverse-search_algorithm) algorithm for combinatorial enumeration and search problems, originally introduced by Avis and Fukuda (see [References](#references)).

## Example usage
Before using this package, it is recommended to read the original reverse search [paper](#references), which explains the concepts needed below.
To specify an enumeration procedure, you need to provide a local search function `ls(v)` and an adjacency oracle `adj(v, j, aux)`. For example, to enumerate all connected induced subgraphs of a graph `G`, one could use
```julia
using ReverseSearch, Graphs

N = 10
G = complete_graph(N)

function ls(U)
    isempty(U) && return U
    length(U) == 1 && return eltype(U)[]

    for v in U
        V = sort!(setdiff(U, v))
        g = G[V]
        is_connected(g) && return V
    end
    return nothing
end
function adj(U, j, aux)
    j > N && return nothing
    V = sort!(union(U, j))
    g = G[V]
    if is_connected(g) 
        return V
    else
        return missing
    end
end
```
This is a very basic implementation of the connected subgraph enumeration method described in the paper above, where subgraphs of `G` are represented as lists of vertices.

To perform reverse search with these functions, we first create a `RSSystem`:
```julia
v0 = Int[]
rsys = RSSystem(ls, adj, v0)
```
Here we start the enumeration from the empty subgraph (`v0 = Int[]`).

Once the reverse search system is defined, we can carry out the enumeration using
```julia
result = reversesearch(rsys) do v, d
    println("Found a subgraph with vertices $v at depth $d.")
    true
end
```
The code above will perform the complete enumeration and call the callback on every object `v` found at depth `d`.
In the present example, depth is just the number of vertices of the induced subgraph.
`reversesearch` returns an `RSResult` containing the termination status, total number of vertices generated, and the maximum depth reached.
Through the callback, it is also possible to reject some of the generated objects — see the docstring of `reversesearch` for details.

There is also a simpler, but more limited, alternative to the `reversesearch` function: Constructing an `RSIterator` makes it possible iterate over the reverse search output, for example with a `for` loop.
```julia
for (v, d) in RSIterator(rsys)
    println("Found a subgraph with vertices $v at depth $d.")
end
```

## References

  - Avis, D. & Fukuda, K. Reverse search for enumeration.
    *Discrete Applied Mathematics*, **65**, 21-46 (1996).
    [doi:10.1016/0166-218x(95)00026-n](https://doi.org/10.1016/0166-218x(95)00026-n)
