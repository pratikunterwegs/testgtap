
# Load packages
using GlobalTradeAnalysisProjectModelV7, HeaderArrayFile, NamedArrays

# Get the sample data
(; hData, hParameters, hSets) = get_sample_data();

# check some data
get!(hData, "vmgb", nothing)

# Produce initial uncalibrated model using the GTAP data
mc = generate_initial_model(hSets=hSets, hData=hData, hParameters=hParameters)

# Keep the start data for calibration---the value flows are the correct ones
start_data = deepcopy(mc.data)

# Get the required inputs for calibration by providing the target values in start_data
(;fixed_calibration, data_calibration)=generate_calibration_inputs(mc, start_data)

# Keep the default closure (fixed) for later
fixed_default = deepcopy(mc.fixed)

# Load the calibration data and closure 
mc.data = deepcopy(data_calibration)
mc.fixed = deepcopy(fixed_calibration)

run_model!(mc)

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
round.((mc.data["qxs"][:,:,"eu"] ./ calibrated_data["qxs"][:,:,"eu"] .-1) .* 100,digits = 2)

# See the percentage change in qpa, for example:
round.((mc.data["qpa"] ./ calibrated_data["qpa"] .-1) .* 100, digits = 2)

# Calculate EV
ev = calculate_expenditure(sets = mc.sets, data0=calibrated_data, data1=mc.data, parameters=mc.parameters)  .- calibrated_data["y"]

