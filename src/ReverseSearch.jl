module ReverseSearch

import SciMLBase
using Base.Threads: nthreads, @spawn

export RSSystem, RSState, RSIterator, rs, prs, reversesearch

include("./reverse_search.jl")
include("./utils.jl")

end