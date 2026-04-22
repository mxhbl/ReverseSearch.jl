using ReverseSearch
using Test

@testset verbose=true "ReverseSearch" begin
    include("./reversesearch.jl")
    include("./subgraphs.jl")
    include("./isographs.jl")
    include("./jet.jl")
end
