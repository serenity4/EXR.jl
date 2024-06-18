@bitmask EXRFlags::UInt32 begin
  EXR_SINGLE_PART_SCAN_LINE = 0
  EXR_SINGLE_PART_TILED = 1
  EXR_LONG_NAMES = 2
  EXR_DEEP_DATA = 4
  EXR_MULTIPLE_PARTS = 8
end

mutable struct EXRStream{IO<:Base.IO}
  io::IO
  version::UInt32
  flags::EXRFlags
  display_window::Box2I
  pixel_aspect_ratio::Float32
  screen_window_width::Float32
  screen_window_center::Tuple{Float32, Float32}
  channels::ChannelIterator{IO}
  attributes::AttributeIterator{IO}
  EXRStream{IO}(io::IO) where {IO} = finalizer(exr -> close(exr.io), new{IO}(io))
end

Base.show(io::IO, exr::EXRStream) = print(io, typeof(exr), "(version = $(Int(exr.version)), flags = $(bitmask_name(exr.flags)), $(length(exr.attributes)) attributes, $(length(exr.channels)) channels)")
