module GroupSlices

import Base.hash
import Base.Cartesian, Base.Cartesian.@nloops, Base.Cartesian.@nref

export groupslices, groupinds, firstinds, lastinds

struct Prehashed
    hash::UInt
end
hash(x::Prehashed) = x.hash

"""
    groupslices(A, dim)
Returns a vector of integers where each integer element of the returned vector
is a group number corresponding to the unique slices along dimension `dim` as
returned from `unique(A, dim)`, where `A` can be a multidimensional array.

Example usage:

If `C = unique(A, dim)`, `ic = groupslices(A, dim)`, and
`ndims(A) == ndims(C) == 3`, then:
```
if dim == 1
   all(A .== C[ic,:,:])
elseif dim == 2
   all(A .== C[:,ic,:])
elseif dim == 3
   all(A .== C[:,:,ic])
end
```
"""
@generated function groupslices(A::AbstractArray{T,N}, dim::Int) where {T,N}
    quote
        if !(1 <= dim <= $N)
            ArgumentError("Input argument dim must be 1 <= dim <= $N, but is currently $dim")
        end
        hashes = zeros(UInt, size(A, dim))

        # Compute hash for each row
        k = 0
        @nloops $N i A d->(if d == dim; k = i_d; end) begin
            @inbounds hashes[k] = hash(hashes[k], hash((@nref $N A i)))
        end

        # Collect index of first row for each hash
        uniquerow = Array{Int}(undef,size(A, dim))
        firstrow = Dict{Prehashed,Int}()
        for k = 1:size(A, dim)
            uniquerow[k] = get!(firstrow, Prehashed(hashes[k]), k)
        end
        uniquerows = collect(values(firstrow))

        # Check for collisions
        collided = falses(size(A, dim))
        @inbounds begin
            @nloops $N i A d->(if d == dim
                k = i_d
                j_d = uniquerow[k]
            else
                j_d = i_d
            end) begin
                if (@nref $N A j) != (@nref $N A i)
                    collided[k] = true
                end
            end
        end

        if any(collided)
            nowcollided = BitArray(size(A, dim))
            while any(collided)
                # Collect index of first row for each collided hash
                empty!(firstrow)
                for j = 1:size(A, dim)
                    collided[j] || continue
                    uniquerow[j] = get!(firstrow, Prehashed(hashes[j]), j)
                end
                for v in values(firstrow)
                    push!(uniquerows, v)
                end

                # Check for collisions
                fill!(nowcollided, false)
                @nloops $N i A d->begin
                    if d == dim
                        k = i_d
                        j_d = uniquerow[k]
                        (!collided[k] || j_d == k) && continue
                    else
                        j_d = i_d
                    end
                end begin
                    if (@nref $N A j) != (@nref $N A i)
                        nowcollided[k] = true
                    end
                end
                (collided, nowcollided) = (nowcollided, collided)
            end
        end
        ie = unique(uniquerow)
        ic_dict = Dict{Int,Int}()
        for k = 1:length(ie)
            ic_dict[ie[k]] = k
        end

        ic = similar(uniquerow)
        for k = 1:length(ic)
            ic[k] = ie[ic_dict[uniquerow[k]]]
        end
        return ic
    end
end

"""
    groupinds(ic)
Returns a vector of vectors of integers wherein the vector of group slice
index integers as returned from `groupslices(A, dim)` is converted into a
grouped vector of vectors.  Each vector entry in the returned vector of
vectors contains all of the positional indices of slices in the original
input array `A` that correspond to the unique slices along dimension `dim`
that are present in the array `C` as returned from `unique(A, dim)`.
"""
function groupinds(ic::Vector{Int})
    d = Dict{Int, Int}()
    ia = unique(ic)
    n = length(ia)
    for i = 1:n
        d[ia[i]]= i
    end

    ib = Vector{Vector{Int}}(undef,n)
    for k = 1:n
        ib[k] = Int[]
    end

    for h = 1:length(ic)
        push!(ib[d[ic[h]]], h)
    end
    return ib
end

"""
    firstinds(ic::Vector{Int})
    firstinds(ib::Vector{Vector{Int}})

Returns a vector of integers containing the first index position of each unique
value in the input integer vector `ic`, or the first index position of each
entry in the input vector of integer vectors `ib`.

When operating on the output returned from `unique(A, dim)`, the returned
vector of integers correspond to the positions of the first of each unique slice
present in the original input multidimensional array `A` along dimension `dim`.

The implementation of `firstinds` accepting a vector of integers operates on the
output returned from `groupslices(A, dim)`.

The implementation of `firstinds` accepting a vector of vector of integers
operates on the output returned from `groupinds(ic::Vector{Int})`.
"""
function firstinds(ic::Vector{Int})
    id = unique(ic)
    n = length(id)
    ia = Vector{Int}(undef,n)
    for i = 1:n
        ia[i] = findfirst(elt -> elt==id[i],ic)
    end
    return ia
end

function firstinds(ib::Vector{Vector{Int}})
    ia = map(first, ib)
end

"""
    lastinds(ic::Vector{Int})
Returns a vector of integers containing the last index position of each unique
value in the input integer vector `ic`.

When operating on the output returned from `groupinds(unique(A, dim))`, the
returned vector of integers correspond to the positions of the last of each
unique slice present in the original input multidimensional array `A` along
dimension `dim`.

The implementation of `firstinds` accepting a vector of vector of integers
operates on the output returned from `groupinds(ic::Vector{Int})`.
"""
function lastinds(ib::Vector{Vector{Int}})
    ia = map(last, ib)
end


end # module
