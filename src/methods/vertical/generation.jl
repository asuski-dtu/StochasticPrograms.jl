# Block-vertical generation #
# ========================== #
function generate!(stochasticprogram::StochasticProgram{N}, structure::VerticalBlockStructure{N}) where N
    # Generate all stages
    for stage in 1:N
        generate!(stochasticprogram, structure, stage)
    end
    return nothing
end

function generate!(stochasticprogram::StochasticProgram{N}, structure::VerticalBlockStructure{N}, stage::Integer) where N
    1 <= stage <= N || error("Stage $stage not in range 1 to $N.")
    if stage == 1
        # Check generators
        has_generator(stochasticprogram, :stage_1) || error("First-stage problem not defined in stochastic program. Consider @stage 1.")
        # Set the optimizer (if any)
        if has_provided_optimizer(stochasticprogram.optimizer)
            set_optimizer(structure.first_stage, master_optimizer(stochasticprogram))
        end
        # Prepare decisions
        structure.first_stage.ext[:decisions] = structure.decisions[1]
        add_decision_bridges!(structure.first_stage)
        # Generate first stage
        generator(stochasticprogram, :stage_1)(structure.first_stage, stage_parameters(stochasticprogram, 1))
    else
        # Check generators
        stage_key = Symbol(:stage_, stage)
        decision_key = Symbol(:stage_, stage - 1, :_decisions)
        has_generator(stochasticprogram, stage_key) || error("Stage problem $stage not defined in stochastic program. Consider @stage $stage.")
        has_generator(stochasticprogram, decision_key) || error("No decision variables defined in stage problem $(stage-1).")
        # Sanity check on scenario probabilities
        if num_scenarios(stochasticprogram, stage) > 0
            p = stage_probability(stochasticprogram, stage)
            abs(p - 1.0) <= 1e-6 || @warn "Scenario probabilities do not add up to one. The probability sum is given by $p"
        end
        # Generate
        generate_vertical!(scenarioproblems(structure, stage),
                           generator(stochasticprogram, decision_key),
                           generator(stochasticprogram, stage_key),
                           stage_parameters(stochasticprogram, stage - 1),
                           stage_parameters(stochasticprogram, stage),
                           structure.decisions[stage],
                           sub_optimizer(stochasticprogram))
    end
    return nothing
end

function generate_vertical!(scenarioproblems::ScenarioProblems,
                            decision_generator::Function,
                            generator::Function,
                            decision_params::Any,
                            stage_params::Any,
                            decisions::Decisions,
                            optimizer)
    for i in num_subproblems(scenarioproblems)+1:num_scenarios(scenarioproblems)
        # Create subproblem
        subproblem = optimizer == nothing ? Model() : Model(optimizer)
        # Prepare decisions
        subproblem.ext[:decisions] = decisions
        add_decision_bridges!(subproblem)
        # Generate and return the stage model
        decision_generator(subproblem, decision_params)
        generator(subproblem, stage_params, scenario(scenarioproblems, i))
        push!(scenarioproblems.problems, subproblem)
    end
    return nothing
end
function generate_vertical!(scenarioproblems::DistributedScenarioProblems,
                            decision_generator::Function,
                            generator::Function,
                            decision_params::Any,
                            stage_params::Any,
                            ::Decisions,
                            optimizer)
    @sync begin
        for w in workers()
            @async remotecall_fetch(
                w,
                scenarioproblems[w-1],
                decision_generator,
                generator,
                decision_params,
                stage_params,
                scenarioproblems.decisions[w-1],
                optimizer) do (sp,dgenerator,generator,dparams,params,decisions,opt)
                    generate_vertical!(fetch(sp),
                                       dgenerator,
                                       generator,
                                       dparams,
                                       params,
                                       decisions,
                                       opt)
                end
        end
    end
    return nothing
end

function clear(structure::VerticalBlockStructure{N}) where N
    # Clear all stages
    for stage in 1:N
        clear_stage!(structure, stage)
    end
    return nothing
end

function clear_stage!(structure::VerticalBlockStructure{N}, s::Integer) where N
    1 <= s <= N || error("Stage $s not in range 1 to $N.")
    if s == 1
        empty!(first_stage(stochasticprogram))
    else
        clear!(scenarioproblems(structure, s))
    end
    return nothing
end

# Getters #
# ========================== #
function first_stage(stochasticprogram::StochasticProgram, structure::VerticalBlockStructure; optimizer = nothing)
    if optimizer == nothing
        return structure.first_stage
    end
    stage_one = copy(structure.first_stage)
    set_optimizer(stage_one, optimizer)
    return stage_one
end
