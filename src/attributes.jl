@serializable struct Attribute
  name::Symbol << Symbol(read_null_terminated_string(io))
  type::Symbol << Symbol(read_null_terminated_string(io))
  size::UInt32
  offset::UInt32 << begin
    offset = position(io)
    skip(io, size)
    offset
  end
end

payload(attribute::Attribute, ::Type{T}, io::IO) where {T} = read_at(io, T, attribute.offset; start = 0)
payload(attribute::Attribute, ::Type{NTuple{N,T}}, io::IO) where {N,T} = ntuple(i -> read_at(io, T, attribute.offset + (i - 1) * sizeof(T); start = 0), N)

function Base.getindex(attributes::Vector{Attribute}, name::Symbol)
  i = findfirst(x -> x.name == name, attributes)
  isnothing(i) && throw(KeyError(name))
  attributes[i]
end

struct AttributeIterator{IO}
  io::IO
  offset::Int64
  AttributeIterator(io::IO, offset = position(io)) = new{typeof(io)}(io, offset)
end

Base.IteratorEltype(::Type{AttributeIterator{IO}}) where {IO} = Base.HasEltype()
Base.eltype(::Type{AttributeIterator{IO}}) where {IO} = Attribute
Base.IteratorSize(::Type{AttributeIterator{IO}}) where {IO} = Base.SizeUnknown()
Base.length(iterator::AttributeIterator) = count(_ -> true, iterator)

function Base.iterate(iterator::AttributeIterator, offset::Int64 = iterator.offset)
  seek(iterator.io, offset)
  eof(iterator.io) && return nothing
  peek(iterator.io, UInt8) == 0x00 && return nothing
  read(iterator.io, Attribute), position(iterator.io)
end
