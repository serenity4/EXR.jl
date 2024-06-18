EXRStream(filename::AbstractString) = EXRStream(open(filename, "r"))
EXRStream(io::IO) = read_binary(io, EXRStream)

function BinaryParsingTools.swap_endianness(io::IO, ::Type{EXRStream})
  magic_number = read(io, UInt32)
  magic_number == 0x762f3101 && return true
  magic_number == MAGIC_NUMBER && return false
  error("The provided file is not an EXR file (magic_number: $(repr(magic_number)))")
end

BinaryParsingTools.cache_stream_in_ram(::IO, ::Type{EXRStream}) = false

function Base.read(io::BinaryIO, ::Type{EXRStream})
  exr = EXRStream{typeof(io)}(io)
  exr.io = io
  bytes = read(io, UInt32)
  exr.version = UInt8(bytes & 0x000000ff)
  exr.version ≤ 2 || error("Required EXR version ≤ 2")
  exr.flags = EXRFlags(bytes >> 8)
  !in(EXR_MULTIPLE_PARTS, exr.flags) || error("Only single-part EXR files are supported")
  exr.attributes = AttributeIterator(io)
  for attribute in exr.attributes
    attribute.name == :channels && (exr.channels = ChannelIterator(io, attribute.offset))
    attribute.name == :pixelAspectRatio && (exr.pixel_aspect_ratio = payload(attribute, Float32, io))
    attribute.name == :compression && payload(attribute, Compression, io)
    attribute.name == :screenWindowWidth && (exr.screen_window_width = payload(attribute, LittleEndian{Float32}, io))
    attribute.name == :screenWindowCenter && (exr.screen_window_center = payload(attribute, NTuple{2, LittleEndian{Float32}}, io))
  end
  exr
end
