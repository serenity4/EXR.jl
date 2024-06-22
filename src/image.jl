function retrieve_image(::Type{T}, exr::EXRStream, channels = default_channels(T)) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  retrieve_image(T, exr, exr.parts, channels)
end

function retrieve_image(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  is_single_part(exr) || error("Only single-part EXR files are currently supported")
  is_tiled(part) && return retrieve_image_from_tiles(part, channels)
  retrieve_image_from_scanline(T, exr, part, channels)
end

default_channels(::Type{T}) where {T} = (:R, :G, :B, :A)
default_channels(::Type{T}) where {T<:AbstractFloat} = (:D,)

# XXX: Should we really cache that, or could it hold on to
# unreasonably too much memory?
function retrieve_offset_table!(exr::EXRStream, part::EXRPart)
  isdefined(part, :offsets) && return part.offsets
  seek(exr.io, exr.offset_tables_origin)
  part.offsets = [read(exr.io, UInt64) for _ in 1:number_of_chunks(part)]
end

function read_scanline_uncompressed!(data::Matrix{T}, channel_data, io::IO, part::EXRPart, j, channels, channel_offsets, channel_size) where {T}
  (; width) = dimensions(part.data_window)
  n = length(channel_offsets)
  CT = component_type(T)
  CT === Any && error("Inferred component type for `$T` is `Any`; you will need to extend `component_type(::Type{$T})` to return the appropriate component type")
  origin = position(io)

  # Gather every channel.
  for (channel, chdata, offset) in zip(channels, channel_data, channel_offsets)
    for i in 1:width
      seek(io, origin + offset * width + (i - 1) * channel_size)
      chdata[i] = read_component(io, CT, channel)
    end
  end

  # Aggregate channels into the desired type.
  for i in 1:width
    data[i, j] = construct(T, ntuple(ni -> channel_data[ni][i], ncomponents(T)))
  end
  data
end

component_type(::Type{T}) where {T} = eltype(T)
construct(::Type{T}, components) where {T} = T(components...)
construct(::Type{T}, components) where {T<:Tuple} = convert(T, components)
ncomponents(::Type{T}) where {T} = length(T)
ncomponents(::Type{T}) where {N,T<:NTuple{N}} = N

function read_component(io::IO, ::Type{CT}, channel::Channel) where {CT}
  channel.pixel_type === PIXEL_TYPE_FLOAT16 && return convert(CT, read(io, LittleEndian{Float16}))
  channel.pixel_type === PIXEL_TYPE_FLOAT32 && return convert(CT, read(io, LittleEndian{Float32}))
  channel.pixel_type === PIXEL_TYPE_UINT32 && return convert(CT, read(io, UInt32))
  error("Unknown pixel type")
end

function retrieve_image_from_scanline(::Type{T}, exr::EXRStream, part::EXRPart, channels) where {T}
  channel_mask = [findfirst(y -> x === y.name, part.channels) for x in channels]
  channel_offsets = [(ind - 1) * channelsize(part.channels) for ind in channel_mask]
  channel_size = channelsize(part.channels)
  CT = component_type(T)
  width, height = dimensions(part.data_window)
  channel_data = ntuple(_ -> zeros(CT, width), length(channels))
  data = Matrix{T}(undef, width, height)
  for (j, offset) in enumerate(retrieve_offset_table!(exr, part))
    seek(exr.io, offset)
    is_multi_part(exr) && (part_number = read(exr.io, UInt64))
    y = read(exr.io, Int32)
    pixel_data_size = read(exr.io, Int32)
    if part.compression == COMPRESSION_NONE
      read_scanline_uncompressed!(data, channel_data, exr.io, part, j, part.channels[channel_mask], channel_offsets, channel_size)
    else
      error("Compressed data is not yet supported for reading")
    end
  end
  data
end

function retrieve_image_from_tiles(part::EXRPart)
  error("Not implemented yet")
end
