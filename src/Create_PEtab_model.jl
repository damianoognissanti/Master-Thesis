# PEtab structs 
include(joinpath(pwd(), "src", "PeTab_structs.jl"))

include(joinpath(pwd(), "src", "Common.jl"))

# Files related to computing the cost (likelihood)
include(joinpath(pwd(), "src", "Compute_cost", "Compute_priors.jl"))
include(joinpath(pwd(), "src", "Compute_cost", "Compute_cost.jl"))
include(joinpath(pwd(), "src", "Compute_cost", "Compute_cost_zygote.jl"))

# Files related to computing derivatives 
include(joinpath(pwd(), "src", "Derivatives", "Hessian.jl"))
include(joinpath(pwd(), "src", "Derivatives", "Gradient.jl"))
include(joinpath(pwd(), "src", "Derivatives", "Adjoint_sensitivity_analysis.jl"))
include(joinpath(pwd(), "src", "Derivatives", "Forward_sensitivity_equations.jl"))
include(joinpath(pwd(), "src", "Derivatives", "Gauss_newton.jl"))
include(joinpath(pwd(), "src", "Derivatives", "Common.jl"))

# Files related to solving the ODE-system 
include(joinpath(pwd(), "src", "Solve_ODE", "Change_experimental_condition.jl"))
include(joinpath(pwd(), "src", "Solve_ODE", "Solve_ode_Zygote.jl"))
include(joinpath(pwd(), "src", "Solve_ODE", "Solve_ode_model.jl"))

# Files related to distributed computing 
include(joinpath(pwd(), "src", "Distributed", "Distributed.jl"))

# Files related to processing PEtab files 
include(joinpath(pwd(), "src", "Process_PEtab_files", "Common.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Get_simulation_info.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Get_parameter_indices.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Process_measurements.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Process_parameters.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Process_callbacks.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Observables", "Common.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Observables", "Create_h_sigma_derivatives.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Observables", "Create_u0_h_sigma.jl"))
include(joinpath(pwd(), "src", "Process_PEtab_files", "Read_PEtab_files.jl"))

# For creating a PEtab ODE problem 
include(joinpath(pwd(), "src", "Create_PEtab_ODEProblem.jl"))


"""
    setUpPeTabModel(modelName::String, dirModel::String)::PEtabModel

    Given a model directory (dirModel) containing the PeTab files and a 
    xml-file on format modelName.xml will return a PEtabModel struct holding 
    paths to PeTab files, ode-system in ModellingToolkit format, functions for 
    evaluating yMod, u0 and standard deviations, and a parameter and state maps 
    for how parameters and states are mapped in the ModellingToolkit ODE system
    along with state and parameter names.

    dirModel must contain a SBML file named modelName.xml, and files starting with 
    measurementData, experimentalCondition, parameter, and observables (tsv-files).
    The latter files must be unique (e.g only one file starting with measurementData)

    TODO : Example  
"""
function readPEtabModel(pathYAML::String; 
                        forceBuildJuliaFiles::Bool=false, 
                        verbose::Bool=true, 
                        ifElseToEvent::Bool=true, 
                        jlFile=false)::PEtabModel

    pathSBML, pathParameters, pathConditions, pathObservables, pathMeasurements, dirJulia, dirModel, modelName = readPEtabYamlFile(pathYAML, jlFile=jlFile)                    
    
    if jlFile == false
        
        pathModelJlFile = joinpath(dirJulia, modelName * ".jl")
        
        if !isfile(pathModelJlFile) && forceBuildJuliaFiles == false
            verbose == true && @printf("Julia model file does not exist, will build it\n")
            modelDict = XmlToModellingToolkit(pathSBML, pathModelJlFile, modelName, ifElseToEvent=ifElseToEvent)

        elseif isfile(pathModelJlFile) && forceBuildJuliaFiles == false
            verbose == true && @printf("Julia model file exists at %s - will not rebuild\n", pathModelJlFile)
            
        elseif forceBuildJuliaFiles == true
            verbose == true && @printf("By user option will rebuild Julia model file\n")
            isfile(pathModelJlFile) == true && rm(pathModelJlFile)
            modelDict = XmlToModellingToolkit(pathSBML, pathModelJlFile, modelName, ifElseToEvent=ifElseToEvent)
        end

    else
        jlDir = joinpath(dirModel, "Julia_model_files")
        modelDict, pathModelJlFile = JLToModellingToolkit(modelName, jlDir, ifElseToEvent=ifElseToEvent)
    end

    println("pathModelJlFile = ", pathModelJlFile)
    addParameterForConditionSpecificInitialValues(pathModelJlFile, pathConditions)

    # Load model ODE-system
    include(pathModelJlFile)
    expr = Expr(:call, Symbol("getODEModel_" * modelName))
    _odeSystem, stateMap, parameterMap = eval(expr)
    odeSystem = structural_simplify(_odeSystem)
    # TODO : Make these to strings here to save conversions
    parameterNames = parameters(odeSystem)
    stateNames = states(odeSystem)

    # Build functions for observables, sd and u0 if does not exist and include
    path_u0_h_sigma = joinpath(dirJulia, modelName * "_h_sd_u0.jl")
    path_D_h_sd = joinpath(dirJulia, modelName * "_D_h_sd.jl")
    if !isfile(path_u0_h_sigma) || !isfile(path_D_h_sd) || forceBuildJuliaFiles == true
        verbose && forceBuildJuliaFiles == false && @printf("File for h, u0 and σ does not exist will build it\n")
        verbose && forceBuildJuliaFiles == true && @printf("By user option will rebuild h, σ and u0\n")
            
        if !@isdefined(modelDict)
            modelDict = XmlToModellingToolkit(pathSBML, pathModelJlFile, modelName, writeToFile=false, ifElseToEvent=ifElseToEvent)
        end
        create_σ_h_u0_File(modelName, pathYAML, dirJulia, odeSystem, stateMap, modelDict, verbose=verbose, jlFile=jlFile)
        createDerivative_σ_h_File(modelName, pathYAML, dirJulia, odeSystem, modelDict, verbose=verbose, jlFile=jlFile)
    else
        verbose == true && @printf("File for h, u0 and σ exists will not rebuild it\n")
    end
    include(path_u0_h_sigma)
    include(path_D_h_sd)    

    pathCallback = joinpath(dirJulia, modelName * "_callbacks.jl")
    if !isfile(pathCallback) || forceBuildJuliaFiles == true
        verbose && forceBuildJuliaFiles == false && @printf("File for callback does not exist will build it\n")
        verbose && forceBuildJuliaFiles == true && @printf("By user option will rebuild callback file\n")
        
        if !@isdefined(modelDict)
            modelDict = XmlToModellingToolkit(pathSBML, pathModelJlFile, modelName, writeToFile=false, ifElseToEvent=ifElseToEvent)
        end
        createCallbacksForTimeDepedentPiecewise(odeSystem, modelDict, modelName, pathYAML, dirJulia, jlFile = jlFile)
    end
    include(pathCallback)
    exprCallback = Expr(:call, Symbol("getCallbacks_" * modelName))
    cbSet::CallbackSet, checkCbActive::Vector{Function} = eval(exprCallback)    

    # Check if callbacks are triggered at a time-point defined by a model parameter. If true then to accurately compute 
    # the gradient tsops must be a vector of floats, and the timespan of the ODE-problem must be converted to Duals. 
    if !@isdefined(modelDict)
        modelDict = XmlToModellingToolkit(pathSBML, pathModelJlFile, modelName, writeToFile=false, ifElseToEvent=ifElseToEvent)
    end
    convertTspan = shouldConvertTspan(pathYAML, modelDict, odeSystem, jlFile)

    petabModel = PEtabModel(modelName,
                            compute_h,
                            compute_u0!,
                            compute_u0,
                            compute_σ,
                            compute_∂h∂u!,
                            compute_∂σ∂σu!,
                            compute_∂h∂p!,
                            compute_∂σ∂σp!,
                            computeTstops,
                            convertTspan,
                            odeSystem,
                            parameterMap,
                            stateMap,
                            parameterNames, 
                            stateNames,
                            dirModel,
                            dirJulia,
                            pathMeasurements,
                            pathConditions,
                            pathObservables, 
                            pathParameters, 
                            pathSBML, 
                            pathYAML,
                            cbSet, 
                            checkCbActive)

    return petabModel
end


# For reading the run-time generated PEtab-related functions which via Meta.parse are passed 
# on to @RuntimeGeneratedFunction to build the PEtab related functions without world-problems.
function getFunctionsAsString(filePath::AbstractString, nFunctions::Int64)::Vector{String}

    fStart, fEnd = zeros(Int64, nFunctions), zeros(Int64, nFunctions)
    iFunction = 1
    inFunction::Bool = false
    nLines = open(filePath, "r") do f countlines(f) end
    bodyStr = Vector{String}(undef, nLines)

    f = open(filePath, "r")
    for (iLine, line) in pairs(readlines(f))

        if length(line) ≥ 8 && line[1:8] == "function"
            fStart[iFunction] = iLine
            inFunction = true
        end

        if length(line) ≥ 3 && line[1:3] == "end"
            fEnd[iFunction] = iLine
            inFunction = false
            iFunction += 1
        end

        bodyStr[iLine] = string(line)
    end
    close(f)

    out = Vector{String}(undef, nFunctions)
    for i in eachindex(out)

        # Runtime generated functions requrie at least on function argument input, hence if missing we 
        # add a foo argument 
        if bodyStr[fStart[i]][end-1:end] == "()"
            bodyStr[fStart[i]] = bodyStr[fStart[i]][1:end-2] * "()"
        end

        out[i] = prod([bodyStr[j] * '\n' for j in fStart[i]:fEnd[i]])
    end
    return out
end


# The PEtab standard allows the condition table to have headers which corresponds to states. In order for this to 
# be compatible with gradient compuations we add such initial values as an additional parameter in odeProblem.p 
# by overwriting the Julia-model file 
function addParameterForConditionSpecificInitialValues(pathJuliaFile::String, 
                                                       pathConditions::String)

    fAsString = getFunctionsAsString(pathJuliaFile, 1)
    experimentalConditionsFile = CSV.read(pathConditions, DataFrame)

    stateNames = getStateOrParameterNamesFromJlFunction(fAsString[1], getStates=true)
    parameterNames = getStateOrParameterNamesFromJlFunction(fAsString[1], getStates=false)

    colNames = names(experimentalConditionsFile)
    iStart = colNames[2] == "conditionName" ? 3 : 2 # Sometimes PEtab file does not include column conditionName
    # Only change model file in case on of the experimental conditions map to a state (that is add an init parameter)
    if any(name -> name ∈ stateNames, colNames[iStart:end]) == false
        return
    end

    # In case we have conditions mapping to initial values
    whichStates = (colNames[iStart:end])[findall(x -> x ∈ stateNames, colNames[iStart:end])]
    newParameterNames = "__init__" .* whichStates .* "__"

    # In case the funciton already has been rewritten return 
    if any(x -> x ∈ parameterNames, newParameterNames)
        return
    end

    # Go through each line and add init parameters to @parameters and parameterArray and in the inital value map
    functionLineByLine = split(fAsString[1], '\n')
    linesAdd = 0:0
    for i in eachindex(functionLineByLine)
        lineNoWhiteSpace = replace(functionLineByLine[i], " " => "")
        lineNoWhiteSpace = replace(lineNoWhiteSpace, "\t" => "")

        # Check which lines new initial value parameters should be added to the parametersMap
        if length(lineNoWhiteSpace) ≥ 19 && lineNoWhiteSpace[1:19] == "trueParameterValues"
            linesAdd = (i+1):(i+length(newParameterNames))
        end

        # Add new parameters for ModelingToolkit.@parameters line 
        if length(lineNoWhiteSpace) ≥ 27 && lineNoWhiteSpace[1:27] == "ModelingToolkit.@parameters"
            functionLineByLine[i] *= (" " * prod([str * " " for str in newParameterNames]))[1:end-1]
        end

        # Add new parameters in parameterArray
        if length(lineNoWhiteSpace) ≥ 14 && lineNoWhiteSpace[1:14] == "parameterArray"
            functionLineByLine[i] = functionLineByLine[i][1:end-1] * ", " * (" " * prod([str * ", " for str in newParameterNames]))[1:end-2] * "]"
        end

        # Move through state array 
        for j in eachindex(whichStates)
            if startsWithx(lineNoWhiteSpace, whichStates[j])
                functionLineByLine[i] = "\t" * whichStates[j] * " => " * newParameterNames[j] * ","
            end
        end
    end

    functionLineByLineNew = Vector{String}(undef, length(functionLineByLine) + length(newParameterNames))
    k = 1
    for i in eachindex(functionLineByLineNew)
        if i ∈ linesAdd
            continue
        end
        functionLineByLineNew[i] = functionLineByLine[k]
        k += 1
    end
    functionLineByLineNew[linesAdd] .= "\t" .* newParameterNames .* " => 0.0,"

    newFunctionString = functionLineByLineNew[1]
    newFunctionString *= prod(row * "\n" for row in functionLineByLineNew[2:end])
    open(pathJuliaFile, "w") do f
        write(f, newFunctionString)
        flush(f)
    end
end

# Extract model state names from stateArray in the JL-file (and also parameter names)
function getStateOrParameterNamesFromJlFunction(fAsString::String; getStates::Bool=false)

    functionLineByLine = split(fAsString, '\n')
    for i in eachindex(functionLineByLine)
        lineNoWhiteSpace = replace(functionLineByLine[i], " " => "")
        lineNoWhiteSpace = replace(lineNoWhiteSpace, "\t" => "")

        # Add new parameters in parameterArray
        if getStates == true
            if length(lineNoWhiteSpace) ≥ 10 && lineNoWhiteSpace[1:10] == "stateArray"
                return split(lineNoWhiteSpace[13:end-1], ",")
            end
        end

        if getStates == false
            if length(lineNoWhiteSpace) ≥ 14 && lineNoWhiteSpace[1:14] == "parameterArray"
                return split(lineNoWhiteSpace[17:end-1], ",")
            end
        end
    end

end


# Check if a str starts with x
function startsWithx(str, x)
    if length(str) < length(x)
        return false
    end

    if str[1:length(x)] == x && str[length(x)+1] ∈ [' ', '=']
        return true
    end
    return false
end