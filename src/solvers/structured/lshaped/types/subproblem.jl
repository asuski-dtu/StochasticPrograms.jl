struct SubProblem{H <: AbstractFeasibilityHandler, T <: AbstractFloat, S <: MOI.AbstractOptimizer}
    id::Int
    probability::T
    tolerance::T
    optimizer::S
    feasibility_handler::H
    linking_constraints::Vector{MOI.ConstraintIndex}
    masterterms::Vector{Vector{Tuple{Int, T}}}

    function SubProblem(model::JuMP.Model,
                        id::Integer,
                        π::AbstractFloat,
                        τ::AbstractFloat,
                        master_indices::Vector{MOI.VariableIndex},
                        ::Type{H}) where H <: AbstractFeasibilityHandler
        T = typeof(π)
        # Get optimizer backend
        optimizer = backend(model)
        S = typeof(optimizer)
        # Instantiate feasibility handler if requested
        feasibility_handler = H(optimizer)
        # Collect all constraints with known decision occurances
        constraints, terms =
            collect_linking_constraints(model,
                                        master_indices,
                                        T)
        return new{H,T,S}(id,
                          π,
                          τ,
                          optimizer,
                          feasibility_handler,
                          constraints,
                          terms)
    end
end

# Feasibility handlers #
# ========================== #
struct FeasibilityIgnorer <: AbstractFeasibilityHandler end
FeasibilityIgnorer(::MOI.ModelLike) = FeasibilityIgnorer()

restore!(::MOI.ModelLike, ::FeasibilityIgnorer) = nothing


mutable struct FeasibilityHandler <: AbstractFeasibilityHandler
    objective::MOI.AbstractScalarFunction
    feasibility_variables::Vector{MOI.VariableIndex}
end

HandlerType(::Type{IgnoreFeasibility}) = FeasibilityIgnorer
HandlerType(::Type{<:HandleFeasibility}) = FeasibilityHandler

function FeasibilityHandler(model::MOI.ModelLike)
    # Cache objective
    func_type = MOI.get(model, MOI.ObjectiveFunctionType())
    obj = MOI.get(model, MOI.ObjectiveFunction{func_type}())
    return FeasibilityHandler(obj, Vector{MOI.VariableIndex}())
end

prepared(handler::FeasibilityHandler) = length(handler.feasibility_variables) > 0

function prepare!(model::MOI.ModelLike, handler::FeasibilityHandler)
    # Set objective to zero
    G = MOI.ScalarAffineFunction{Float64}
    MOI.set(model, MOI.ObjectiveFunction{G}(), zero(MOI.ScalarAffineFunction{Float64}))
    i = 1
    # Create auxiliary feasibility variables
    for (F, S) in MOI.get(model, MOI.ListOfConstraints())
        if F <: AffineDecisionFunction
            for ci in MOI.get(model, MOI.ListOfConstraintIndices{F, S}())
                # Positive feasibility variable
                pos_aux_var = MOI.add_variable(model)
                name = add_subscript(:v⁺, i)
                MOI.set(model, MOI.VariableName(), pos_aux_var, name)
                push!(handler.feasibility_variables, pos_aux_var)
                # Nonnegativity constraint
                MOI.add_constraint(model, MOI.SingleVariable(pos_aux_var),
                           MOI.GreaterThan{Float64}(0.0))
                # Add to objective
                MOI.modify(model, MOI.ObjectiveFunction{G}(),
                           MOI.ScalarCoefficientChange(pos_aux_var, 1.0))
                # Add to constraint
                MOI.modify(model, ci, MOI.ScalarCoefficientChange(pos_aux_var, 1.0))
                # Negative feasibility variable
                neg_aux_var = MOI.add_variable(model)
                name = add_subscript(:v⁻, i)
                MOI.set(model, MOI.VariableName(), neg_aux_var, name)
                push!(handler.feasibility_variables, neg_aux_var)
                # Nonnegativity constraint
                MOI.add_constraint(model, MOI.SingleVariable(neg_aux_var),
                           MOI.GreaterThan{Float64}(0.0))
                # Add to objective
                MOI.modify(model, MOI.ObjectiveFunction{G}(),
                           MOI.ScalarCoefficientChange(neg_aux_var, 1.0))
                # Add to constraint
                MOI.modify(model, ci, MOI.ScalarCoefficientChange(neg_aux_var, -1.0))
                # Update identification index
                i += 1
            end
        end
    end
    return nothing
end

function restore!(model::MOI.ModelLike, handler::FeasibilityHandler)
    # Delete any feasibility variables
    if !isempty(handler.feasibility_variables)
        MOI.delete(model, handler.feasibility_variables)
    end
    empty!(handler.feasibility_variables)
    # Restore objective
    F = typeof(handler.objective)
    MOI.set(model, MOI.ObjectiveFunction{F}(), handler.objective)
    return nothing
end

# Subproblem methods #
# ========================== #
function collect_linking_constraints(model::JuMP.Model,
                                     master_indices::Vector{MOI.VariableIndex},
                                     ::Type{T}) where T <: AbstractFloat
    linking_constraints = Vector{MOI.ConstraintIndex}()
    masterterms = Vector{Vector{Tuple{Int,T}}}()
    F = CombinedAffExpr{Float64}
    for S in [MOI.EqualTo{Float64}, MOI.LessThan{Float64}, MOI.GreaterThan{Float64}]
        for cref in all_constraints(model, F, S)
            push!(linking_constraints, cref.index)
            coeffs = Vector{Tuple{Int,T}}()
            aff = JuMP.jump_function(model, MOI.get(model, MOI.ConstraintFunction(), cref))::CombinedAffExpr
            for (coef, kvar) in linear_terms(aff.knowns)
                # Map known decisions to master decision,
                # assuming sorted order
                idx = master_indices[index(kvar).value].value
                push!(coeffs, (idx, T(coef)))
            end
            push!(masterterms, coeffs)
        end
    end
    return linking_constraints, masterterms
end

function update_subproblem!(subproblem::SubProblem, change::KnownModification)
    func_type = MOI.get(subproblem.optimizer, MOI.ObjectiveFunctionType())
    if func_type <: AffineDecisionFunction
        # Only need to update if there are known decisions in objective
        MOI.modify(subproblem.optimizer,
                   MOI.ObjectiveFunction{func_type}(),
                   change)
    end
    for cref in subproblem.linking_constraints
        update_decision_constraint!(subproblem.optimizer, cref, change)
    end
    return nothing
end

function restore_subproblem!(subproblem::SubProblem)
    restore!(subproblem.optimizer, subproblem.feasibility_handler)
end

function solve(subproblem::SubProblem, x::AbstractVector)
    MOI.optimize!(subproblem.optimizer)
    status = MOI.get(subproblem.optimizer, MOI.TerminationStatus())
    if status == MOI.OPTIMAL
        return OptimalityCut(subproblem, x)
    elseif status == MOI.INFEASIBLE
        return Infeasible(subproblem)
    elseif status == MOI.DUAL_INFEASIBLE
        return Unbounded(subproblem)
    else
        error("Subproblem $(subproblem.id) was not solved properly, returned status code: $status")
    end
end

function (subproblem::SubProblem{FeasibilityHandler})(x::AbstractVector)
    model = subproblem.optimizer
    if !prepared(subproblem.feasibility_handler)
        prepare!(model, subproblem.feasibility_handler)
    end
    # Optimize auxiliary problem
    MOI.optimize!(model)
    # Sanity check that aux problem could be solved
    status = MOI.get(subproblem.optimizer, MOI.TerminationStatus())
    if status != MOI.OPTIMAL
        error("Subproblem $(subproblem.id) was not solved properly during feasibility check, returned status code: $status")
    end
    if MOI.get(model, MOI.ObjectiveValue()) > subproblem.tolerance
        # Subproblem is infeasible, create feasibility cut
        return FeasibilityCut(subproblem, x)
    end
    # Restore subproblem
    restore_subproblem!(subproblem)
    return solve(subproblem, x)
end
function (subproblem::SubProblem{FeasibilityIgnorer})(x::AbstractVector)
    return solve(subproblem, x)
end

# Cuts #
# ========================== #
function OptimalityCut(subproblem::SubProblem, x::AbstractVector)
    π = subproblem.probability
    nterms = mapreduce(+, subproblem.masterterms) do terms
        length(terms)
    end
    cols = zeros(nterms)
    vals = zeros(nterms)
    j = 1
    for (i, ci) in enumerate(subproblem.linking_constraints)
        λ = MOI.get(subproblem.optimizer, MOI.ConstraintDual(), ci)
        for (idx, coeff) in subproblem.masterterms[i]
            cols[j] = idx
            vals[j] = π*λ*coeff
            j += 1
        end
    end
    # Get sense
    sense = MOI.get(subproblem.optimizer, MOI.ObjectiveSense())
    correction = sense == MOI.MIN_SENSE ? 1.0 : -1.0
    # Create sense-corrected optimality cut
    δQ = sparsevec(cols, vals, length(x))
    q = correction * π * MOI.get(subproblem.optimizer, MOI.ObjectiveValue()) + δQ⋅x
    return OptimalityCut(δQ, q, subproblem.id)
end

function FeasibilityCut(subproblem::SubProblem, x::AbstractVector)
    nterms = mapreduce(+, subproblem.masterterms) do terms
        length(terms)
    end
    cols = zeros(nterms)
    vals = zeros(nterms)
    j = 1
    for (i, ci) in enumerate(subproblem.linking_constraints)
        λ = MOI.get(subproblem.optimizer, MOI.ConstraintDual(), ci)
        for (idx, coeff) in subproblem.masterterms[i]
            cols[j] = idx
            vals[j] = λ*coeff
            j += 1
        end
    end
    # Get sense
    sense = MOI.get(subproblem.optimizer, MOI.ObjectiveSense())
    correction = sense == MOI.MIN_SENSE ? 1.0 : -1.0
    # Create sense-corrected optimality cut
    G = sparsevec(cols, vals, length(x))
    g = correction * MOI.get(subproblem.optimizer, MOI.ObjectiveValue()) + G⋅x
    return FeasibilityCut(G, g, subproblem.id)
end

Infeasible(subprob::SubProblem) = Infeasible(subprob.id)
Unbounded(subprob::SubProblem) = Unbounded(subprob.id)
