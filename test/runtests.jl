using EXR
using Test

asset_file(path) = joinpath(@__DIR__, "assets", path)

file = asset_file("golden_bay_1k.exr")

exr = EXRStream(file)

@testset "EXR.jl" begin
  data = retrieve_image(NTuple{4, Float32}, exr)
  @test isa(data, Matrix{NTuple{4, Float32}})
  @test size(data) == (256, 256)
  @test all(color -> last(color) === 1f0, data)
  @test all(color -> all(0f0 .≤ color[1:3] .≤ 1f0), data)
end;
