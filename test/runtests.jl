using EXR
using Test

asset_file(path) = joinpath(@__DIR__, "assets", path)

file = asset_file("golden_bay_1k.exr")

exr = EXRStream(file)

@testset "EXR.jl" begin
    # Write your tests here.
end
