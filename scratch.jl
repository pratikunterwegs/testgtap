
# Load packages
using GlobalTradeAnalysisProjectModelV7, HeaderArrayFile, NamedArrays

using BenchmarkTools

# Get the sample data
(; hData, hParameters, hSets) = get_sample_data();

# check some data
get!(hData, "vmgb", nothing)

get!(hSets, "endw", nothing)

# Produce initial uncalibrated model using the GTAP data
mc = generate_initial_model(hSets=hSets, hData=hData, hParameters=hParameters)

# initial model generation produces lots of output
# let's benchmark this
# about 0.5s per run
@benchmark generate_initial_model(hSets=hSets, hData=hData, hParameters=hParameters)

# Keep the start data for calibration---the value flows are the correct ones
start_data = deepcopy(mc.data)

# Get the required inputs for calibration by providing the target values in start_data
(; fixed_calibration, data_calibration) = generate_calibration_inputs(mc, start_data);

# Keep the default closure (fixed) for later
fixed_default = deepcopy(mc.fixed)

# Load the calibration data and closure 
mc.data = deepcopy(data_calibration)
mc.fixed = deepcopy(fixed_calibration)

run_model!(mc);

# Save the calibrated data---this is the starting point for all simulation
calibrated_data = deepcopy(mc.data)

# Let's change the closure to the default (simulation) closure
mc.fixed = deepcopy(fixed_default)

# Drop the equations that are not needed for solution
rebuild_model!(mc)

# Start with the calibrated data
mc.data = deepcopy(calibrated_data)

### TARIFF SCENARIO
# Double the power of tariff
mc.data["tms"][["crops", "processed food"], ["mena", "sub-saharan africa"], "eu"] .= mc.data["tms"][["crops", "processed food"], ["mena", "sub-saharan africa"], "eu"] * 2

# Run the model
run_model!(mc)

## View some of the solutions:
# See change in exports to the eu
round.((mc.data["qxs"][:, :, "eu"] ./ calibrated_data["qxs"][:, :, "eu"] .- 1) .* 100, digits=2)

# See the percentage change in qpa, for example:
round.((mc.data["qpa"] ./ calibrated_data["qpa"] .- 1) .* 100, digits=2)

# Calculate EV
ev = calculate_expenditure(sets=mc.sets, data0=calibrated_data, data1=mc.data, parameters=mc.parameters) .- calibrated_data["y"]

#### Labour supply shocks per quarter ####

# NOTE: this is essentially pseudocode

# --- Quarterly labour shock simulation ---
# Settings
quarters = 1:8  # example: 8 quarters
regions = mc.sets["reg"]
labour_name = "labour"   # change to actual endowment name in your dataset if different

# Baseline copies
base_qe = deepcopy(calibrated_data["qe"])   # aggregate factor endowments
base_qes = deepcopy(calibrated_data["qes"]) # detailed per-activity factor (optional)

# Example shock series (multiplicative): e.g., quarter 1 = -5%, then recover
shock_multipliers = [0.95, 0.98, 0.99, 1.00, 1.00, 1.00, 1.00, 1.00]

# Prepare storage for results
y_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))
wage_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))
ev_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))

# Optional: if you want to incorporate capital dynamics, set up δ (depr.) and initial vkb
δ = deepcopy(mc.data["δ"])  # depreciation rate by region (if present)
vkb = deepcopy(mc.data["vkb"]) # starting capital stock (if present)

for (i, q) in enumerate(quarters)
    println("Running quarter $q ...")

    # Apply shock to aggregate labour endowment (exogenous)
    mc.data["qe"][labour_name, :] .= base_qe[labour_name, :] .* shock_multipliers[i]

    # Optionally adjust detailed factor allocation instead:
    # mc.data["qes"][labour_name, :, :] .= base_qes[labour_name, :, :] .* shock_multipliers[i]

    # Ensure labour is fixed (exogenous shock). If not already:
    mc.fixed["qe"][labour_name, :] .= true
    # For qes (detail) use mc.fixed["qesf"] if needed.

    # Start from previous solution for robustness (warm start)
    # mc.data already holds last solution after run_model!

    # Solve
    run_model!(mc)

    # Save outputs
    y_by_q[:, i] .= mc.data["y"]  # GDP/income
    wage_by_q[:, i] .= mc.data["pe"][labour_name, :]  # factor price (wage)
    ev_by_q[:, i] .= calculate_expenditure(sets=mc.sets, data0=calibrated_data, data1=mc.data, parameters=mc.parameters) .- calibrated_data["y"]

    # Optional capital update (simple approximation):
    if haskey(mc.data, "vkb") && haskey(mc.data, "qinv")
        # example: next_period_k = current_k * (1 - δ) + investment (value-based approximation)
        # Using qinv (investment quantity) and pinv price to get value:
        inv_value = mc.data["qinv"] .* mc.data["pinv"]
        # spread investment to vkb using shares or simple direct add (user choice)
        vkb .= vkb .* (1 .- δ) .+ mc.data["qinv"]  # simplistic: add quantities
        mc.data["vkb"] = deepcopy(vkb)
        # If using value-based update, convert appropriately before next run
    end
end

# Example post-processing output:
println("GDP by quarter (% change from baseline):")
round.((y_by_q .- calibrated_data["y"][:, None]) ./ calibrated_data["y"][:, None] .* 100, digits=3)

# Save results to disk if desired:
using JLD2
@save "labour_shock_results.jld2" y_by_q wage_by_q ev_by_q
# --- end of quarterly simulation snippet ---
