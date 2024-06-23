using EXR
using BenchmarkTools

asset_file(path) = joinpath(dirname(@__DIR__), "test", "assets", path)

file = asset_file("render_uncompressed.exr")
data = retrieve_image(NTuple{4, Float32}, exr)

@profview for i in 1:1000; retrieve_image(NTuple{4, Float32}, exr); end
@profview for i in 1:10; retrieve_image(NTuple{4, Float32}, exr); end

@btime exr = EXRStream($file) setup = GC.gc()
@btime retrieve_image(NTuple{4, Float32}, $exr)

# Try these with different BinaryParsingTools options,
# e.g. toggling RAM caching and/or memory-mapping.
read_all(io) = IOBuffer(read(io))
@btime read_all($(exr.io)) setup = seekstart(exr.io)
