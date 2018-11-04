"""
    AbstractScenario

Abstract supertype for scenario objects.
"""
abstract type AbstractScenario end
"""
    Probability

A type-safe wrapper for `Float64` used to represent probability of a scenario occuring.
"""
mutable struct Probability
    π::Float64
end
"""
    probability(scenario::AbstractScenario)

Return the probability of `scenario` occuring.

Is always defined for scenarios created through @scenario. Other user defined scenario types must implement this method to generate a proper probability.
"""
probability(scenario::AbstractScenario)::Float64 = scenario.probability.π
"""
    probability(scenarios::Vector{<:AbstractScenario})

Return the probability of that any scenario in the collection `scenarios` occurs.
"""
probability(scenarios::Vector{<:AbstractScenario}) = sum(probability.(scenarios))
"""
    set_probability!(scenario::AbstractScenario, probability::AbstractFloat)

Set the probability of `scenario` occuring.

Is always defined for scenarios created through @scenario. Other user defined scenario types must implement this method.
"""
function set_probability!(scenario::AbstractScenario, π::AbstractFloat)
    scenario.probability.π = π
end
function Base.zero(::Type{S}) where S <: AbstractScenario
    error("zero not implemented for scenario type: ", S)
end
function Base.show(io::IO, scenario::S) where S <: AbstractScenario
    print(io, "$(S.name.name) with probability $(probability(scenario))")
end
struct ExpectedScenario{S <: AbstractScenario} <: AbstractScenario
    scenario::S

    (::Type{ExpectedScenario})(scenario::AbstractScenario) = new{typeof(scenario)}(scenario)
end
function Base.show(io::IO, scenario::ExpectedScenario{S}) where S <: AbstractScenario
    print(io, "Expected scenario of type $(S.name.name)")
end
"""
    expected(scenarios::Vector{<:AbstractScenario})

Return the expected scenario out of the collection `scenarios`.

This is defined through classical expectation: sum([probability(s)*s for s in scenarios]), and is always defined for scenarios created through @scenario, if the requested fields support it.

Otherwise, user-defined scenario types must implement this method for full functionality.
"""
function expected(::Vector{S}) where S <: AbstractScenario
    error("Expectation not implemented for scenario type: ", S)
end
