EXRStream(filename::AbstractString) = EXRStream(open(filename, "r"))
EXRStream(io::IO) = read_binary(io, EXRStream)

function BinaryParsingTools.swap_endianness(io::IO, ::Type{EXRStream})
  magic_number = read(io, UInt32)
  magic_number == 0x762f3101 && return true
  magic_number == MAGIC_NUMBER && return false
  error("The provided file is not an EXR file (magic_number: $(repr(magic_number)))")
end

BinaryParsingTools.cache_stream_in_ram(::IO, ::Type{EXRStream}) = true

function EXRPart(io::IO)
  part = EXRPart{typeof(io)}(io)
  part.type = EXR_PART_SCANLINE_IMAGE
  part.attributes = AttributeIterator(io)
  part.chunk_count = 0
  for attribute in part.attributes
    attribute.name == :name && (part.name = Symbol(payload(attribute, NullTerminatedString, io)))
    attribute.name == :type && (part.type = payload(attribute, EXRPartType, io))
    attribute.name == :displayWindow && (part.display_window = payload(attribute, Box2I, io))
    attribute.name == :dataWindow && (part.data_window = payload(attribute, Box2I, io))
    attribute.name == :pixelAspectRatio && (part.pixel_aspect_ratio = payload(attribute, Float32, io))
    attribute.name == :screenWindowWidth && (part.screen_window_width = payload(attribute, LittleEndian{Float32}, io))
    attribute.name == :screenWindowCenter && (part.screen_window_center = payload(attribute, NTuple{2, LittleEndian{Float32}}, io))
    attribute.name == :compression && (part.compression = payload(attribute, Compression, io))
    attribute.name == :lineOrder && (part.line_order = payload(attribute, LineOrder, io))
    attribute.name == :chunkCount && (part.chunk_count = payload(attribute, Int32, io))
    attribute.name == :channels && (part.channels = collect(ChannelIterator(io, attribute.offset)))
  end
  part
end

function Base.read(io::BinaryIO, ::Type{EXRStream})
  exr = EXRStream{typeof(io)}(io)
  exr.io = io
  bytes = read(io, UInt32)
  exr.version = UInt8(bytes & 0x000000ff)
  exr.version ≤ 2 || error("Required EXR version ≤ 2")
  exr.flags = EXRFlags(bytes >> 8)
  !in(EXR_MULTIPLE_PARTS, exr.flags) || error("Only single-part EXR files are supported")
  exr.parts = EXRPart(io)
  exr.offset_tables_origin = position(io)
  exr
end
