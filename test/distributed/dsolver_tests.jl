reference_solver = GLPKSolverLP()
osqp = OSQP.OSQPMathProgBaseInterface.OSQPSolver(verbose=0)

regularizers = [DontRegularize(),
                RegularizedDecomposition(linearize = true),
                TrustRegion(),
                LevelSet(linearize = true, projectionsolver = reference_solver)]

aggregators = [DontAggregate(),
               PartialAggregate(2),
               Aggregate(),
               DynamicAggregate(2, SelectUniform(2))]

consolidators = [Consolidate(), DontConsolidate()]

penalties = [Fixed(),
             Adaptive(θ = 1.01)]

executors = [Serial(),
             Synchronous()]

@testset "Structured Solvers" begin
    @testset "L-shaped: simple problems" begin
        @testset "$(solverstr(ls)): $name" for ls in [LShapedSolver(reference_solver,
                                                                    crash = Crash.EVP(),
                                                                    regularize = regularizer,
                                                                    aggregate = aggregator,
                                                                    distributed = true,
                                                                    κ = 1.0,
                                                                    log = false)
                                                      for regularizer in regularizers, aggregator in aggregators], (sp,name) in problems
            @testset "Distributed data" begin
                tol = 1e-5
                optimize!(sp, solver=reference_solver)
                x̄ = optimal_decision(sp)
                Q̄ = optimal_value(sp)
                optimize!(sp, solver=ls)
                @test abs(optimal_value(sp) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
            @testset "Data on single remote node" begin
                tol = 1e-5
                sp_onenode = copy(sp)
                add_scenarios!(sp_onenode, scenarios(sp), workers()[1])
                optimize!(sp_onenode, solver=reference_solver)
                x̄ = optimal_decision(sp_onenode)
                Q̄ = optimal_value(sp_onenode)
                optimize!(sp, solver=ls)
                @test abs(optimal_value(sp_onenode) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp_onenode) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
            @testset "Local data" begin
                tol = 1e-5
                sp_nondist = copy(sp, procs = [1])
                add_scenarios!(sp_nondist, scenarios(sp))
                optimize!(sp_nondist, solver=reference_solver)
                x̄ = optimal_decision(sp_nondist)
                Q̄ = optimal_value(sp_nondist)
                optimize!(sp_nondist, solver=ls)
                @test abs(optimal_value(sp_nondist) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp_nondist) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
        end
        @testset "$(solverstr(ls)) on distributed data: $name" for ls in [LShapedSolver(reference_solver,
                                                                                        crash = Crash.EVP(),
                                                                                        regularize = regularizer,
                                                                                        aggregate = aggregator,
                                                                                        log = false)
                                                                          for regularizer in regularizers, aggregator in aggregators], (sp,name) in problems
            tol = 1e-5
            optimize!(sp, solver=reference_solver)
            x̄ = optimal_decision(sp)
            Q̄ = optimal_value(sp)
            with_logger(NullLogger()) do
                optimize!(sp, solver=ls)
            end
            @test abs(optimal_value(sp) - Q̄)/(1e-10+abs(Q̄)) <= tol
            @test norm(optimal_decision(sp) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
        end
    end
    @testset "Progressive-hedging: simple problems" begin
        @testset "$(solverstr(ph)): $name" for ph in [ProgressiveHedgingSolver(osqp,
                                                                               execution = executor,
                                                                               penalty = penalty,
                                                                               τ = 1e-3,
                                                                               log = false)
                                                      for executor in executors, penalty in penalties], (sp,name) in problems
            @testset "Distributed data" begin
                tol = 1e-2
                optimize!(sp, solver=reference_solver)
                x̄ = optimal_decision(sp)
                Q̄ = optimal_value(sp)
                with_logger(NullLogger()) do
                    optimize!(sp, solver=ph)
                end
                @test abs(optimal_value(sp) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
            @testset "Data on single remote node" begin
                tol = 1e-2
                sp_onenode = copy(sp)
                add_scenarios!(sp_onenode, scenarios(sp), workers()[1])
                optimize!(sp_onenode, solver=reference_solver)
                x̄ = optimal_decision(sp_onenode)
                Q̄ = optimal_value(sp_onenode)
                with_logger(NullLogger()) do
                    optimize!(sp, solver=ph)
                end
                @test abs(optimal_value(sp_onenode) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp_onenode) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
            @testset "Local data" begin
                tol = 1e-2
                sp_nondist = copy(sp, procs = [1])
                add_scenarios!(sp_nondist, scenarios(sp))
                optimize!(sp_nondist, solver=reference_solver)
                x̄ = optimal_decision(sp_nondist)
                Q̄ = optimal_value(sp_nondist)
                with_logger(NullLogger()) do
                    optimize!(sp, solver=ph)
                end
                @test abs(optimal_value(sp_nondist) - Q̄)/(1e-10+abs(Q̄)) <= tol
                @test norm(optimal_decision(sp_nondist) - x̄)/(1e-10+norm(x̄)) <= sqrt(tol)
            end
        end
    end
end