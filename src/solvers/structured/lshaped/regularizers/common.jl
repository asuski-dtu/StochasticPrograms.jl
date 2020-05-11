# Common
# ------------------------------------------------------------
function add_regularization_params!(regularization::AbstractRegularizer; kwargs...)
    push!(regularization.parameters, kwargs...)
    return nothing
end

function add_projection_targets!(regularization::AbstractRegularization, model::MOI.AbstractOptimizer)
    ξ = regularization.ξ
    for i in eachindex(ξ)
        name = add_subscript(:ξ, i)
        var_index, _ = MOI.add_constrained_variable(model, SingleKnownSet(ξ[i]))
        set_known_decision!(regularization.decisions, var_index, ξ[i])
        MOI.set(model, MOI.VariableName(), var_index, name)
        regularization.projection_targets[i] = var_index
    end
    return nothing
end

function decision(::AbstractLShaped, regularization::AbstractRegularization)
    return map(regularization.ξ) do ξᵢ
        ξᵢ.value
    end
end

function objective_value(::AbstractLShaped, regularization::AbstractRegularization)
    return regularization.data.Q̃
end

function solve_regularized_master!(lshaped::AbstractLShaped, ::AbstractRegularization)
    #lshaped.mastersolver(lshaped.mastervector)
    return nothing
end

function gap(lshaped::AbstractLShaped, regularization::AbstractRegularization)
    @unpack θ = lshaped.data
    @unpack Q̃ = regularization.data
    return abs(θ-Q̃)/(abs(Q̃)+1e-10)
end

function process_cut!(lshaped::AbstractLShaped, cut::AbstractHyperPlane, ::AbstractRegularization)
    return nothing
end

function add_regularization_params!(regularization::AbstractRegularization; kwargs...)
    push!(regularization.params, kwargs...)
    return nothing
end
