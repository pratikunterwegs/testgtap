
# Load packages
using GlobalTradeAnalysisProjectModelV7, HeaderArrayFile, NamedArrays

# Get the sample data
(; hData, hParameters, hSets) = get_sample_data();

# Produce initial uncalibrated model using the GTAP data
mc = generate_initial_model(hSets=hSets, hData=hData, hParameters=hParameters);

# Keep the start data for calibration---the value flows are the correct ones
start_data = deepcopy(mc.data);

# Get the required inputs for calibration by providing the target values in start_data
(; fixed_calibration, data_calibration) = generate_calibration_inputs(mc, start_data);

# Keep the default closure (fixed) for later
fixed_default = deepcopy(mc.fixed);

# Load the calibration data and closure 
mc.data = deepcopy(data_calibration);
mc.fixed = deepcopy(fixed_calibration);

run_model!(mc);

# Save the calibrated data---this is the starting point for all simulation
calibrated_data = deepcopy(mc.data);

#### example of quarterly shocks ####
# NOTE: this model has no real representation of time; the shocks
# occur at some t timepoints that could represent any time interval

quarters = 1:8  # example: 8 quarters
regions = mc.sets["reg"]

# NOTE: example data only has skilled or unskilled labour
labour_name = ["skilled labor", "unskilled labor"]

# make deep copies as calibrated data is modified in place
# NOTE: example data has NaNs - unclear whether this is expected or
# these should be replaced with zeros
# NOTE: "qe" appears to be endowment per region, "qes" is the same per sector
# qes has one more dimension than qe to accommodate this
base_qe = deepcopy(calibrated_data["qe"])   # aggregate factor endowments
base_qes = deepcopy(calibrated_data["qes"]) # detailed per-activity factor (optional)

# generate an example sequence of shocks per quarter. these are proportional
# modifications to the available unskilled labour
# this example shows a 30% reduction in Q1, with a recovery to below the
# pre-pandemic maximum over the next 3 quarters
shock_multipliers = [0.7, 0.8, 0.95, 0.95, 0.95, 0.95, 0.95, 0.95]

# have a much worse shock
shock_multipliers = repeat([0.5], maximum(quarters))

# prepare storage for results
# NOTE: no real reason to use NamedArray other than user convenience IMO
y_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))
wage_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))
ev_by_q = NamedArray(zeros(length(regions), length(quarters)), (regions, collect(quarters)))

for q in quarters
    println("Running quarter $q ...")

    # apply shock to aggregate labour endowment (exogenous)
    # NOTE: must re-use initial value as mc.data is modified in place
    mc.data["qe"][labour_name, :] .= base_qe[labour_name, :] .* shock_multipliers[q]

    # optionally adjust detailed factor allocation instead:
    # mc.data["qes"][labour_name, :, :] .= base_qes[labour_name, :, :] .* shock_multipliers[i]

    # assumes labour is fixed (exogenous shock); check by examining and set
    # true if needed
    # `mc.fixed["qe"][labour_name, :]`

    run_model!(mc)

    # save outputs
    y_by_q[:, q] .= mc.data["y"]  # GDP/income
    # wage_by_q[:, q] .= mc.data["pe"][labour_name, :]  # factor price (wage)
    ev_by_q[:, q] .= calculate_expenditure(
        sets=mc.sets,
        data0=calibrated_data,
        data1=mc.data,
        parameters=mc.parameters
    ) .- calibrated_data["y"]
end

# examine gdp/income and expenditure
# NOTE: I don't understand the specifics of the internal calculations
# or the correct interpretation
y_by_q

ev_by_q
