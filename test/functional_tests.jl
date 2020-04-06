@info "Running functionality tests..."
@testset "Stochastic Programs: Functionality" begin
    @testset "SP Constructs: $name" for (sp,res,name) in problems
        tol = 1e-2
        @test optimize!(sp) == MOI.OPTIMAL
        @test isapprox(decisions(optimal_decision(sp)), res.x̄, rtol = tol)
        @test isapprox(optimal_value(sp), res.VRP, rtol = tol)
        @test isapprox(EWS(sp), res.EWS, rtol = tol)
        @test isapprox(EVPI(sp), res.EVPI, rtol = tol)
        @test isapprox(VSS(sp), res.VSS, rtol = tol)
        @test isapprox(EV(sp), res.EV, rtol = tol)
        @test isapprox(EEV(sp), res.EEV, rtol = tol)
    end
    @testset "Inequalities: $name" for (sp,res,name) in problems
        @test EWS(sp) <= VRP(sp)
        @test VRP(sp) <= EEV(sp)
        @test VSS(sp) >= 0
        @test EVPI(sp) >= 0
        @test VSS(sp) <= EEV(sp)-EV(sp)
        @test EVPI(sp) <= EEV(sp)-EV(sp)
    end
    @testset "Copying: $name" for (sp,res,name) in problems
        tol = 1e-2
        sp_copy = copy(sp)
        add_scenarios!(sp_copy, scenarios(sp))
        @test nscenarios(sp_copy) == nscenarios(sp)
        generate!(sp_copy)
        @test nsubproblems(sp_copy) == nsubproblems(sp)
        @test optimize!(sp_copy) == MOI.OPTIMAL
        optimize!(sp)
        @test isapprox(decisions(optimal_decision(sp_copy)), decisions(optimal_decision(sp)), rtol = tol)
        @test isapprox(optimal_value(sp_copy), optimal_value(sp), rtol = tol)
        @test isapprox(EWS(sp_copy), EWS(sp), rtol = tol)
        @test isapprox(EVPI(sp_copy), EVPI(sp), rtol = tol)
        @test isapprox(VSS(sp_copy), VSS(sp), rtol = tol)
        @test isapprox(EV(sp_copy), EV(sp), rtol = tol)
        @test isapprox(EEV(sp_copy), EEV(sp), rtol = tol)
    end
    @testset "Sampling" begin
        sampled_sp = sample(simple_model, sampler, 100, optimizer = GLPK.Optimizer)
        @test nscenarios(sampled_sp) == 100
        @test nsubproblems(sampled_sp) == 100
        @test isapprox(stage_probability(sampled_sp), 1.0)
        sample!(sampled_sp, sampler, 100)
        @test nscenarios(sampled_sp) == 200
        @test nsubproblems(sampled_sp) == 200
        @test isapprox(stage_probability(sampled_sp), 1.0)
    end
    @testset "Confidence intervals" begin
        try
            CI = confidence_interval(simple_model, sampler, optimizer = GLPK.Optimizer, N = 200, log = false)
            @test lower(CI) <= upper(CI)
        catch end
        set_optimizer!(simple_model, GLPK.Optimizer)
        sol = optimize!(simple_model, sampler, confidence = 0.95, tol = 1e-1, log = false)
        @test lower(optimal_value(simple_model)) <= upper(optimal_value(simple_model))
    end
end
