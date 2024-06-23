@serializable struct Channel
  name::Symbol << Symbol(read_null_terminated_string(io))
  pixel_type::PixelType << PixelType(read(io, UInt32))
  linear::Bool << read(io, UInt8)
  @reserved 3
  xsampling::Int32
  ysampling::Int32
end

channelsize(channel::Channel) = pixelsize(channel.pixel_type)

struct ChannelIterator{IO}
  io::IO
  offset::Int64
  ChannelIterator(io::IO, offset = position(io)) = new{typeof(io)}(io, offset)
end

Base.IteratorEltype(::Type{ChannelIterator{IO}}) where {IO} = Base.HasEltype()
Base.eltype(::Type{ChannelIterator{IO}}) where {IO} = Channel
Base.IteratorSize(::Type{ChannelIterator{IO}}) where {IO} = Base.SizeUnknown()
Base.length(iterator::ChannelIterator) = count(_ -> true, iterator)

function Base.iterate(iterator::ChannelIterator, offset::Int64 = iterator.offset)
  seek(iterator.io, offset)
  eof(iterator.io) && return nothing
  peek(iterator.io, UInt8) == 0x00 && return nothing
  read(iterator.io, Channel), position(iterator.io)
end
