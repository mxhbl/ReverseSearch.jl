using ReverseSearch
using Test

@testset verbose=true "ReverseSearch" begin
    println("num threads: $(Threads.nthreads())")
    include("./subgraphs.jl")
end
